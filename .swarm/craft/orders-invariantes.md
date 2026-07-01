# craft/orders-invariantes — testar invariantes de negócio (state-based)

> Método técnico **sob demanda**, DERIVADO da fatia `dev-orders` e das invariantes reais
> (`DOMAIN_INVARIANTS.yaml`: BIZ-1/BIZ-2). Puxado pelo §4 quando a task toca `Order`,
> `Voucher` ou `OrderCommandHandler`. Escola **clássica** (objeto real), não mockista.

## 1 — Anti-fraude: servidor recalcula (BIZ-2 · `OrderCommandHandler.cs:140-143`)
O valor/desconto enviado pelo cliente no `AddOrderCommand` é **só comparação** — o servidor
SEMPRE recalcula e **rejeita divergência**. É porta de fraude se não testado.
```csharp
[Fact]
public void ValorAdulteradoPeloCliente_ERejeitado()
{
    var cmd = new AddOrderCommand(clientId, itens, amountDoCliente: 1m /* mentira */);
    var result = await handler.Handle(cmd, default);
    Assert.False(result.IsValid);   // servidor recalculou e rejeitou a divergência
}
```

## 2 — Order.Amount = soma das linhas (BIZ-1)
```csharp
[Fact]
public void Amount_IgualSomaDasLinhas_ComDesconto()
{
    var order = new Order(customerId, amount: 0, itens, hasVoucher: true, discount: 5m);
    order.CalcularValorPedido();
    Assert.Equal(itens.Sum(i => i.CalcularValor()) - 5m, order.Amount);
}
```
Borda: desconto maior que o total → **clampa em 0**, nunca negativo.

## 3 — Voucher / bordas
Voucher aplicado uma única vez; quantidade/percentual nas bordas (0, limite). `Voucher`
real, não mock.

## Anti-padrões
- Mockar `Order`/`Voucher` pra testar a aritmética deles.
- Persistir o `Amount` do cliente sem recalcular (fura BIZ-2).

## Critério de aceitação (o verificador cobra)
- [ ] adulteração de valor do cliente é **rejeitada** (BIZ-2)?
- [ ] `Amount` = soma das linhas com desconto, borda inclusa?
