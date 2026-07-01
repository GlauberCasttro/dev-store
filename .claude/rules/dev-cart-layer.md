---
description: "Regras e critérios idiomáticos para a fronteira dev-cart"
globs: ["src/services/DevStore.ShoppingCart.API/**"]
---

# Layer Rule — dev-cart (ShoppingCart.API)

Destino de how-to e critério idiomático da fronteira ShoppingCart. O cartão do agente
(`.claude/agents/dev-cart.md`) já cobre persona/escopo/território — este arquivo não duplica
aquilo, só a receita técnica e o "isso está certo?" verificável.

## How-tos da camada

### 1. Adicionar rota nova via Minimal API — nunca criar Controller

Este é o único serviço do repo sem pasta `Controllers/`. Toda rota vive em `Program.cs`:

```csharp
// Program.cs — padrão de rota existente (MapActions)
app.MapPost("/shopping-cart/items", [Authorize] async (
    CartItem item,
    ShoppingCart cart,
    IShoppingCartRepository repository) =>
{
    cart.AddItem(item);
    await repository.Save(cart);
    return Results.Ok(cart);
})
.WithName("AddItem")
.WithTags("ShoppingCart")
.Produces(StatusCodes.Status200OK)
.Produces(StatusCodes.Status400BadRequest);
```

❌ Nunca criar `Controllers/ShoppingCartController.cs` — introduziria um segundo estilo
arquitetural (MVC) onde o serviço inteiro é Minimal API (DOMAIN-CART-001, NET9-STACK-014).

### 2. Alterar o contrato gRPC com aviso explícito ao consumidor

`Protos/shoppingcart.proto` é consumido pelo dev-checkout-bff via client gerado por build
(`<Protobuf Include>` no `.csproj` do BFF):

```protobuf
// Protos/shoppingcart.proto — alteração de contrato
service ShoppingCartOrders {
  rpc GetShoppingCart (ShoppingCartRequest) returns (ShoppingCartResponse);
}
```

Depois de editar o `.proto`, rodar build local para confirmar a geração do stub e **sinalizar
explicitamente ao tech-lead** que `DevStore.Bff.Checkout` precisa rebuildar — o acoplamento é de
build, não de runtime, então o erro só aparece no próximo build do BFF, não imediatamente.

### 3. Respeitar `MAX_ITEMS` como regra de negócio, não configuração

```csharp
// Model/CustomerShoppingCart.cs:8
public const int MAX_ITEMS = 5; // limite de negócio hardcoded — não é appsettings
```

Nunca "normalizar" isso para `IConfiguration`/`appsettings.json` sem confirmação explícita do
tech-lead de que é uma mudança de regra de negócio intencional (DOMAIN-CART-003) — tratar como
constante deliberada até ordem em contrário.

### 4. Não duplicar a limpeza de carrinho fora do fluxo reativo

O carrinho é removido só ao consumir `OrderDoneIntegrationEvent`:

```csharp
// ShoppingCartIntegrationHandler.cs
public async Task Consume(ConsumeContext<OrderDoneIntegrationEvent> context)
{
    await _repository.RemoveShoppingCart(context.Message.ClientId);
}
```

Se a task pedir para "garantir que o carrinho sempre seja limpo", não adicionar uma segunda
remoção síncrona no fluxo de checkout sem alinhar com dev-orders/dev-checkout-bff — duplicar a
responsabilidade de limpeza em dois lugares cria risco de race condition entre o síncrono e o
reativo (DOMAIN-CART-004 é comportamento conhecido, não bug a corrigir por conta própria).

### 5. Query de leitura aproveitando `QueryTrackingBehavior.NoTracking` já configurado

Diferente de `OrdersContext`, `ShoppingCartContext` já configura tracking global — não é
necessário `.AsNoTracking()` manual por query:

```csharp
// ShoppingCartContext.cs:12-13 já configura NoTracking global
public async Task<CustomerShoppingCart> GetById(Guid customerId) =>
    await _context.CustomerShoppingCart
        .Include(c => c.Items)
        .FirstOrDefaultAsync(c => c.CustomerId == customerId);
```

## Critérios idiomáticos

- [DOMAIN-CART-001]: `Program.cs:40-81` é o único ponto de definição de rotas HTTP desta
  fronteira via `app.MapGet/Post/Put/Delete` — verificável com
  `find src/services/DevStore.ShoppingCart.API -iname Controllers` retornando vazio; qualquer PR
  que introduza uma pasta `Controllers/` viola o padrão arquitetural confirmado (NET9-STACK-014).
- [DOMAIN-CART-002]: `Protos/shoppingcart.proto:7-9` define `ShoppingCartOrders.GetShoppingCart`,
  consumido via client gerado no `.csproj` de `DevStore.Bff.Checkout` — verificável checando que
  toda alteração de contrato vem acompanhada de nota explícita de rebuild para o BFF; PR que
  altera o `.proto` sem mencionar o impacto no BFF está incompleto.
- [DOMAIN-CART-003]: `CustomerShoppingCart.cs:8` define `MAX_ITEMS=5` como constante — verificável
  com `grep -n MAX_ITEMS CustomerShoppingCart.cs`; qualquer PR que mova esse valor para
  configuração externa sem decisão explícita registrada do tech-lead está fora do critério
  idiomático da fronteira.
- [minimal_api]: `Program.cs` é a âncora gold de Minimal API do projeto (NET9-STACK-014) — único
  exemplar do estilo no repo, "padrão isolado, não convenção dominante"; toda nova rota deve
  seguir a mesma composição (`[Authorize] async (params) => ...` + `.WithName/.WithTags/.Produces*`)
  já usada nas rotas existentes, sem inventar uma variação de estilo dentro do próprio arquivo.

## Referências

- Cartão do agente: `.claude/agents/dev-cart.md`
- Fatia de domínio: `.swarm/knowledge/domain/dev-cart.yaml`
- Fatia de stack: `.swarm/knowledge/stack/dotnet-9.yaml` (NET9-STACK-013/014)
- Convenções transversais: `.claude/rules/conventions.md`
