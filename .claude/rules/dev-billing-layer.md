---
description: "Regras e critérios idiomáticos para a fronteira dev-billing"
globs: ["src/services/DevStore.Billing.API/**", "src/services/DevStore.Billing.DevsPay/**"]
---

# Layer Rule — dev-billing (Billing.API + Billing.DevsPay)

Destino de how-to e critério idiomático da fronteira Billing+DevsPay. O cartão do agente
(`.claude/agents/dev-billing.md`) já cobre persona/escopo/território — este arquivo não duplica
aquilo, só a receita técnica e o "isso está certo?" verificável.

## How-tos da camada

### 1. Converter `TransactionStatus` sempre por switch nominal — NUNCA cast posicional

Este é o bug real confirmado da fronteira (`CreditCardPaymentFacade.cs:73`): os dois enums
`TransactionStatus` (Billing.API e DevsPay) têm nomes e posições diferentes na semântica de
estorno. Cast posicional produz mapeamento errado silenciosamente.

```csharp
// ERRADO — cast posicional (o bug real, CreditCardPaymentFacade.cs:73)
var status = (Billing.API.Models.TransactionStatus)transaction.Status;
// DevsPay.Chargeback(4) → Billing.API.Refund(4) — semântica ERRADA e silenciosa

// CORRETO — switch nominal explícito
Billing.API.Models.TransactionStatus MapStatus(DevsPay.TransactionStatus devsPayStatus) =>
    devsPayStatus switch
    {
        DevsPay.TransactionStatus.Authorized => Billing.API.Models.TransactionStatus.Authorized,
        DevsPay.TransactionStatus.Paid       => Billing.API.Models.TransactionStatus.Paid,
        DevsPay.TransactionStatus.Refused    => Billing.API.Models.TransactionStatus.Denied,
        DevsPay.TransactionStatus.Chargeback => Billing.API.Models.TransactionStatus.Refund,
        DevsPay.TransactionStatus.Cancelled  => Billing.API.Models.TransactionStatus.Canceled,
        _ => throw new ArgumentOutOfRangeException(nameof(devsPayStatus))
    };
```

Qualquer PR que toque `TransactionStatus` precisa comparar os dois enums lado a lado antes de
editar — nomes coincidem mas valores na posição 4 divergem semanticamente.

### 2. Garantir idempotência antes de qualquer novo handler de pagamento (SEC-3)

`BillingService.Authorize/Capture/Cancel` não têm chave de deduplicação hoje — redelivery do
RabbitMQ duplicaria a operação. Todo novo consumer/handler de pagamento deve verificar isso
primeiro:

```csharp
public async Task Authorize(Guid transactionId, ...)
{
    if (await _paymentRepository.ExistsByMessageId(messageId))
    {
        _logger.LogWarning("Mensagem {MessageId} já processada — ignorando redelivery.", messageId);
        return;
    }

    // ... lógica de autorização, persistindo messageId junto com a transação
}
```

Não adicionar lógica nova em `BillingService` sem essa checagem — é a lacuna real (DOMAIN-BILLING-004)
que SEC-3 exige fechar antes de expandir a superfície de pagamento.

### 3. Nunca aumentar a superfície de dados de cartão em claro no bus

`OrderInitiatedIntegrationEvent` já carrega `Holder`/`CardNumber`/`ExpirationDate`/`SecurityCode`
em claro pelo RabbitMQ (violação PCI-DSS confirmada, DOMAIN-BILLING-003). Nesta fronteira:

```csharp
// ERRADO — logar ou repersistir o payload de cartão em claro
_logger.LogInformation("Pagamento recebido: {@Event}", integrationEvent); // nunca serializar o evento completo

// CORRETO — logar só identificadores não sensíveis
_logger.LogInformation("Pagamento recebido para pedido {OrderId}, transação {TransactionId}",
    integrationEvent.OrderId, transactionId);
```

Nenhuma mudança nesta fronteira deve re-publicar, logar ou persistir `CardNumber`/`SecurityCode`
em texto plano — mascaramento/tokenização é responsabilidade da origem (dev-core/dev-orders),
não desta fronteira.

### 4. Não tratar `DevsPay.Transaction` como gateway real ao desenhar teste/feature

`DevStore.Billing.DevsPay` é lib in-process (`ProjectReference`, sem HTTP) que usa
`Bogus.Random.Bool(0.7f)` para simular 70% de sucesso:

```csharp
// Transaction.cs:101-102 — comportamento real do "gateway"
var approved = faker.Random.Bool(0.7f); // sem chamada de rede, sem latência, sem rate-limit
```

Não simular timeout/rate-limit/retry contra ele — esses cenários não existem nesta lib. Se a
task pedir teste de resiliência de gateway, o ponto de falha a simular é a mensageria
(RabbitMQ indisponível), não o DevsPay.

### 5. Não criar endpoint HTTP em `PaymentController` sem confirmar o motivo do design

`PaymentController.cs` é uma classe vazia — toda a superfície real é mensageria via
`BillingIntegrationHandler` (3 `IConsumer<T>`). Antes de adicionar `[HttpPost]`:

```bash
grep -n "class PaymentController" src/services/DevStore.Billing.API/Controllers/PaymentController.cs
# confirma: classe vazia herdando MainController, sem métodos — decisão de design, não esquecimento
```

Se a task exigir endpoint HTTP síncrono, tratar como mudança arquitetural e confirmar com o
tech-lead antes de implementar.

## Critérios idiomáticos

- [DOMAIN-BILLING-002]: `CreditCardPaymentFacade.cs:73` faz cast posicional entre
  `DevsPay.TransactionStatus` e `Billing.API.TransactionStatus` — verificável comparando os dois
  enums (`Models/TransactionStatus.cs:3-9` em cada projeto); qualquer PR que altere conversão de
  status deve substituir o cast por switch nominal explícito (ver how-to 1) e não introduzir novo
  cast posicional em nenhum outro ponto da fronteira.
- [DOMAIN-BILLING-004 / SEC-3]: `BillingService.cs:24-118` (Authorize/Capture/Cancel) não tem
  chave de deduplicação — verificável com `grep -rn 'Idempot\|MessageId' src/services/DevStore.Billing.API`
  (hoje vazio); todo novo handler de pagamento deve incluir checagem de idempotência desde o
  início, não como retrofit.
- [DOMAIN-BILLING-003]: `OrderInitiatedIntegrationEvent` carrega dados de cartão em claro
  (`src/building-blocks/DevStore.Core/Messages/Integration/OrderInitiatedIntegrationEvent.cs:12-15`) —
  verificável com `grep -rn 'CardNumber\|SecurityCode' src/services/DevStore.Billing.API`; nenhuma
  alteração nesta fronteira deve adicionar log, persistência ou nova publicação desses campos em
  texto plano.
- [integration_consumer]: `BillingIntegrationHandler.cs` é a âncora gold de `IConsumer<T>` +
  Facade da fronteira (contém o bug de enum mismatch citado como CAUTION, não desqualifica a
  estrutura) — todo novo consumer de evento de pagamento deve seguir esse padrão estrutural,
  mas corrigindo a lacuna de idempotência que os 3 consumers atuais têm.

## Referências

- Cartão do agente: `.claude/agents/dev-billing.md`
- Fatia de domínio: `.swarm/knowledge/domain/dev-billing.yaml`
- Fatia de stack: `.swarm/knowledge/stack/dotnet-9.yaml` (NET9-STACK-008/009/013)
- Invariantes: `.swarm/knowledge/DOMAIN_INVARIANTS.yaml` — SEC-3
- Convenções transversais: `.claude/rules/conventions.md`
