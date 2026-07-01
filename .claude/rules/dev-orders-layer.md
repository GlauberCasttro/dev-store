---
description: "Regras e critérios idiomáticos para a fronteira dev-orders"
globs: ["src/services/DevStore.Orders.API/**", "src/services/DevStore.Orders.Domain/**", "src/services/DevStore.Orders.Infra/**"]
---

# Layer Rule — dev-orders (Orders.API + Orders.Domain + Orders.Infra)

Destino de how-to e critério idiomático da fronteira Orders. O cartão do agente
(`.claude/agents/dev-orders.md`) já cobre persona/escopo/território — este arquivo não duplica
aquilo, só a receita técnica e o "isso está certo?" verificável.

## How-tos da camada

### 1. Recalcular o valor do pedido sem reabrir a porta de fraude (BIZ-2)

Nunca aceitar `Amount`/`Discount` do cliente como valor final. O padrão correto é sempre
recalcular no servidor e usar o valor do cliente só para comparação:

```csharp
// OrderCommandHandler.cs — padrão correto (IsOrderValid)
var order = new Order(command.ClientId);
order.AddItems(command.Items);
order.CalculateOrderAmount(); // recalcula 100% no servidor a partir dos itens + voucher

if (!IsOrderValid(order, command.Amount))
{
    AddError("O valor do pedido não corresponde ao valor calculado no servidor.");
    return ValidationResult;
}
```

❌ Nunca fazer `order.Amount = command.Amount;` direto — isso elimina a defesa anti-fraude.

### 2. Acessar/alterar Voucher sempre pela raiz própria

Voucher é aggregate root independente — nunca navegar por `order.Voucher` para mutar estado:

```csharp
// Correto
var voucher = await _voucherRepository.GetVoucherByCode(command.VoucherCode);
var validation = new VoucherValidation(voucher, order.Amount);
if (!validation.IsValid())
{
    AddError(validation.ErrorMessage);
    return ValidationResult;
}
order.ApplyVoucher(voucher);
```

❌ Nunca `order.Voucher.Discount = x;` — quebra o Specification pattern (`VoucherValidation`) e
acopla dois aggregate roots que devem permanecer fracamente associados (via `VoucherId` nullable).

### 3. Tratar o pagamento síncrono via MassTransit com timeout em mente

`_bus.Request<>` bloqueia o Handler esperando Billing responder, sem try/catch para
`RequestTimeoutException` hoje (gap real, NET9-STACK-008). Ao tocar esse fluxo:

```csharp
try
{
    var response = await _bus.Request<OrderInitiatedIntegrationEvent, ResponseMessage>(
        integrationEvent, timeout: RequestTimeout.After(s: 10));
}
catch (RequestTimeoutException)
{
    AddError("Não foi possível confirmar o pagamento a tempo. Tente novamente.");
    return ValidationResult;
}
```

Se a task não pedir explicitamente essa correção, ao menos documentar o risco no PR — não
silenciar.

### 4. Verificar transição de OrderStatus antes de assumir que ela existe

`OrderStatus` tem 5 valores, só 3 têm transição implementada (`Authorize`/`Finish`/`Cancel`).
Antes de escrever código que dependa de `Refused`/`Delivered`:

```bash
grep -rn 'OrderStatus.Refused\|OrderStatus.Delivered' src/services/DevStore.Orders*
# esperado: vazio (só declaração no enum) — confirma que não há transição implementada
```

Se a task pedir para implementar a transição faltante, tratar como item novo de domínio
(precisa de método explícito em `Order`, ex. `Refuse()`/`Deliver()`), não como bug a "corrigir"
silenciosamente.

### 5. Consultar leitura via `AsNoTracking()` manual, não pelo `QueryTrackingBehavior` global

`OrdersContext` é o único DbContext do repo que não configura `QueryTrackingBehavior.NoTracking`
global — decidir explicitamente por query:

```csharp
public async Task<Order> GetById(Guid id) =>
    await _context.Orders.AsNoTracking().FirstOrDefaultAsync(o => o.Id == id);
```

Não copiar o padrão vestigial de `IOrderRepository.GetConnection()` (exposição de `DbConnection`
para Dapper) — não há uso real de Dapper nesta fronteira.

## Critérios idiomáticos

- [DOMAIN-ORDERS-001]: `Order.CalculateOrderAmount()` recalcula sempre no servidor a partir dos
  itens + desconto de voucher; `AddOrderCommand.Amount` é usado só para comparação em
  `IsOrderValid` (`OrderCommandHandler.cs:110-130`) — verificar com `grep -n 'CalculateOrderAmount\|IsOrderValid'`
  que nenhuma alteração passou a persistir `Amount` do cliente direto.
- [DOMAIN-ORDERS-003]: `Voucher` é aggregate root próprio (`src/services/DevStore.Orders.Domain/Vouchers/Voucher.cs:7`),
  nunca entidade filha de `Order` — todo acesso passa por `IVoucherRepository.GetVoucherByCode` +
  `VoucherValidation` (Specification pattern); verificável checando que não existe setter de
  desconto acessado via `order.Voucher.*` fora dessas duas classes.
- [DOMAIN-ORDERS-002]: `OrderStatus` (`src/services/DevStore.Orders.Domain/Orders/OrderStatus.cs:3-9`)
  tem 5 valores mas só 3 transições implementadas em `Order.cs:45-58` (Authorize/Finish/Cancel) —
  verificável com `grep -rn 'OrderStatus.Refused\|OrderStatus.Delivered' src/services/DevStore.Orders*`
  retornando vazio; qualquer PR que assuma `order.Refuse()`/`order.Deliver()` existentes está errado.
- [entity_aggregate_root]: `Order.cs` é a âncora gold de aggregate root do projeto — construtor +
  `{ get; private set; }` + métodos de invariante (`Authorize`/`Finish`/`Cancel`); todo novo
  método de domínio em `Order` deve seguir esse encapsulamento (nunca setter público solto, que
  foi o motivo de `Product.cs` ser REJEITADO como gold — NET9-STACK-018).
- [controller_cqrs]: `OrderController.cs` é a âncora gold de Controller CQRS — delega 100% para
  `IMediatorHandler.SendCommand`, sem lógica de negócio no controller; qualquer novo endpoint
  nesta fronteira deve manter o controller como camada fina de tradução HTTP→Command.

## Referências

- Cartão do agente: `.claude/agents/dev-orders.md`
- Fatia de domínio: `.swarm/knowledge/domain/dev-orders.yaml`
- Fatia de stack: `.swarm/knowledge/stack/dotnet-9.yaml` (NET9-STACK-008/009/011/013)
- Invariantes: `.swarm/knowledge/DOMAIN_INVARIANTS.yaml` — BIZ-1/2/3
- Convenções transversais: `.claude/rules/conventions.md`
