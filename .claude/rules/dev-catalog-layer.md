---
description: "Regras e critérios idiomáticos para a fronteira dev-catalog"
globs: ["src/services/DevStore.Catalog.API/**"]
---

# Layer Rule — dev-catalog (bounded context Catalog)

Destino sancionado dos how-tos e critérios idiomáticos do bounded context Catalog
(Product/Stock, CRUD direto, sem CQRS). O cartão do agente (`.claude/agents/dev-catalog.md`)
cobre persona/escopo/território — este arquivo cobre COMO fazer e O QUE é objetivamente
checável nesta fronteira.

## How-tos da camada

### 1. Nova query de leitura preservando `AsNoTrackingWithIdentityResolution`

`ProductRepository.GetAll` é o exemplar gold de query otimizada do repo — qualquer query
paginada nova sobre `Product` reproduz o mesmo padrão de tracking, nunca regride para
`AsNoTracking()` simples:

```csharp
// Data/Repository/ProductRepository.cs
public async Task<PagedResult<Product>> GetByCategory(int ps, int page, string category)
{
    var query = _context.Products
        .AsNoTrackingWithIdentityResolution()   // preservar — não trocar por AsNoTracking()
        .Where(p => p.Category == category);

    var items = await query.Skip((page - 1) * ps).Take(ps).ToListAsync();
    return new PagedResult<Product> { List = items, TotalResults = await query.CountAsync() };
}
```

### 2. Novo endpoint de leitura no `CatalogController` sem introduzir CQRS

A ausência de MediatR/Command/Handler é deliberada nesta fronteira — todo novo endpoint
delega direto ao repositório:

```csharp
// Controllers/CatalogController.cs
[HttpGet("products/category/{category}")]
public async Task<IActionResult> ByCategory(string category, [FromQuery] int page = 1)
{
    var result = await _productRepository.GetByCategory(10, page, category);
    return Ok(result); // nunca: _mediator.Send(new GetProductsByCategoryQuery(...))
}
```

### 3. Alterar regra de baixa de estoque respeitando o delay assíncrono

`TakeFromInventory`/`IsAvailable` são acionados reativamente pelo consumer, não no fluxo
síncrono de compra — qualquer nova regra de estoque precisa considerar que o pedido pode já
estar autorizado antes da baixa ocorrer:

```csharp
// Services/CatalogIntegrationHandler.cs
public async Task Consume(ConsumeContext<OrderAuthorizedIntegrationEvent> context)
{
    foreach (var item in context.Message.Items)
    {
        var product = await _productRepository.GetById(item.ProductId);
        if (!product.IsAvailable(item.Quantity)) { /* nova regra entra aqui, ciente do delay */ }
        product.TakeFromInventory(item.Quantity);
        _productRepository.Update(product);
    }
    await _productRepository.UnitOfWork.Commit();
    await context.Publish(new OrderLoweredStockIntegrationEvent(/* ... */));
}
```

### 4. Adicionar campo ao `Product` sem "corrigir" a anemia do modelo

`Product.cs` é o único aggregate root do repo com setters públicos — desvio conhecido
(NET9-STACK-018/DOMAIN-CATALOG-001). Um novo campo segue o estilo já existente, sem
converter setters existentes para `private set` na mesma task:

```csharp
// Models/Product.cs — reproduzir o estilo atual, não "corrigir" DDD-lite aqui
public string Ean { get; set; }   // novo campo com setter público, igual aos demais
```

```csharp
// Data/Mappings/ProductMapping.cs
builder.Property(p => p.Ean).HasMaxLength(14);
```

## Critérios idiomáticos

- [DOMAIN-CATALOG-003 / anchors_gold.repository_query_otimizado]: toda query de leitura sobre `Product` usa `AsNoTrackingWithIdentityResolution()`, como `src/services/DevStore.Catalog.API/Data/Repository/ProductRepository.cs:26,32` — NÃO `AsNoTracking()` simples, que é o padrão usado (e aceitável) em outros repositórios do repo (ex. `PaymentRepository.cs:34,40`) mas seria regressão aqui, onde o padrão mais avançado já está estabelecido.
- [DOMAIN-CATALOG-002]: ausência de pasta `Application/Commands` e de qualquer referência a MediatR em `DevStore.Catalog.API` — checável via `grep -rl MediatR src/services/DevStore.Catalog.API` (deve retornar vazio). Introduzir Command/Handler aqui sem aprovação explícita do architect é violação do padrão deliberado desta fronteira.
- [DOMAIN-CATALOG-001 / NET9-STACK-018]: `Product.cs` mantém todas as propriedades com setter público — comparável a `src/services/DevStore.Orders.Domain/Orders/Order.cs` (construtor + `private set`, âncora gold `entity_aggregate_root`), que é o padrão DDD-lite do resto do repo mas NÃO deve ser retroaplicado a `Product` como efeito colateral de outra task.
- [NET9-STACK-004]: nenhuma chamada a `.Migrate()`/`.MigrateAsync()` em `DbMigrationHelpers.cs` — o serviço usa `EnsureCreatedAsync()` exclusivamente (`src/services/DevStore.Catalog.API/Configuration/DbMigrationHelpers.cs:38`). Checável via `grep -rn 'EnsureCreatedAsync\|\.Migrate(' src/services/DevStore.Catalog.API` — só `EnsureCreatedAsync` deve aparecer; as pastas `Migrations/*.cs` são geradas por consistência de histórico, mas não afetam runtime.
