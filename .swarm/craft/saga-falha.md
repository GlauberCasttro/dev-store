# craft/saga-falha — testar a saga Orders↔Billing contra falha

> Método técnico **sob demanda**, DERIVADO da fatia real (`dev-billing`) e dos bugs
> CONFIRMADOS do dev-store (não copiado de template). Puxado pelo §4 quando a task toca
> `BillingIntegrationHandler`, `BillingService` ou a compensação. NÃO mocke o repositório.

## Princípio
Numa saga o bug mora na costura entre "efeito externo já aconteceu" e "estado local
falhou/duplicou". Teste o **caminho de falha** e o **reenvio**, com repositório in-memory
real — nunca o caminho feliz só, nunca com mock.

## 1 — Idempotência (DOMAIN-BILLING-004 · `BillingService.cs:24-118`)
`Authorize/Capture/Cancel` **não têm chave de deduplicação**. Redelivery do RabbitMQ do
mesmo `OrderLoweredStockIntegrationEvent` executaria uma **segunda captura completa**.
Toda task de "melhorar confiabilidade" nesta fronteira trata isto PRIMEIRO.
```csharp
[Fact]
public async Task RedeliveryDoMesmoEvento_CapturaUmaVez()
{
    await handler.Handle(orderLoweredStock);
    await handler.Handle(orderLoweredStock);   // reentrega do RabbitMQ
    Assert.Equal(1, billing.CaptureCount);      // hoje FALHA — sem chave de idempotência
}
```

## 2 — Enum mismatch (DOMAIN-BILLING-002 · `CreditCardPaymentFacade.cs:73`)
Cast **posicional** entre dois enums independentes: `DevsPay.Chargeback(4)` →
`Billing.API.Refund(4)` — semântica diferente na mesma posição. Toda mudança em
`TransactionStatus` corrige com **switch nominal**, nunca cast por posição.
```csharp
[Fact]
public void MapStatus_UsaSwitchNominal_NaoPosicao()
    => Assert.Equal(Billing.TransactionStatus.Chargeback,
                    facade.MapStatus(DevsPay.TransactionStatus.Chargeback)); // não (Billing.Status)src
```

## 3 — Compensação lê estado persistido
`authorize ok → commit falha`: a compensação tem que achar a transação que precisa desfazer.
Repo in-memory que lança no commit; afirme que o charge é estornado.

## PCI (DOMAIN-BILLING-003) — não piorar
`OrderInitiatedIntegrationEvent` já trafega `CardNumber/SecurityCode` em claro. **Nenhuma
mudança aqui aumenta essa superfície** — nada de logar/re-publicar o payload de cartão.

## Critério de aceitação (o verificador cobra)
- [ ] teste do caminho de falha **e do reenvio** (idempotência)?
- [ ] `TransactionStatus` por **switch nominal**, sem cast posicional?
- [ ] compensação lê estado **persistido**; nenhum dado de cartão novo em claro?
