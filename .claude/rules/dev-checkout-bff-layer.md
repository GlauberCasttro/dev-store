---
description: "Regras e critérios idiomáticos para a fronteira dev-checkout-bff"
globs: ["src/api-gateways/DevStore.Bff.Checkout/**"]
---

# Layer rule — dev-checkout-bff (Bff.Checkout)

Camada de composição (orquestra Catalog/Cart/Order/Customer via HTTP e gRPC), não de domínio.
Complementa o cartão do agente (`.claude/agents/dev-checkout-bff.md`) — aqui ficam as receitas
técnicas e os critérios idiomáticos citáveis; não duplicar a persona/escopo/playbooks já
definidos lá.

## How-tos da camada

### 1. Criar um novo client HTTP tipado

Sempre herdar de `Service` (abstract base em `Services/Service.cs`), nunca instanciar
`HttpClient` cru dentro do client:

```csharp
public class VoucherService : Service, IVoucherService
{
    private readonly HttpClient _httpClient;

    public VoucherService(HttpClient httpClient, IOptions<AppServicesSettings> settings)
    {
        _httpClient = httpClient;
        _httpClient.BaseAddress = new Uri(settings.Value.CheckoutBffUrl);
    }

    public async Task<VoucherDTO> GetByCode(string code)
    {
        var response = await _httpClient.GetAsync($"vouchers/{code}");
        return await DeserializeResponse<VoucherDTO>(response);
    }
}
```

Registrar em `Configuration/DependencyInjectionConfig.cs` com `AddHttpClient<IVoucherService, VoucherService>()`.

### 2. Adicionar endpoint que orquestra múltiplos serviços

Controller fino — delega para os Services tipados, sem lógica de agregação inline extensa.
Seguir o padrão de `Controllers/OrderController.cs`: um método por rota, chamadas sequenciais
aos Services já injetados, e montagem do DTO de resposta só no fim.

### 3. Consumir o carrinho — escolher HTTP ou gRPC corretamente

Antes de adicionar chamada a dev-cart, inspecionar o Controller/fluxo já existente para saber
se o caminho ativo é `IShoppingCartService` (HTTP) ou `IShoppingCartGrpcService` (gRPC):

```bash
grep -rn "IShoppingCartService\|IShoppingCartGrpcService" src/api-gateways/DevStore.Bff.Checkout/Controllers/*.cs
```

Nunca introduzir um terceiro caminho ad-hoc para o mesmo dado.

### 4. Tratar erro de dependência downstream

`ManageHttpResponse` (em `Service`) já centraliza o tratamento de status code — usar esse
método em vez de `response.EnsureSuccessStatusCode()` direto, para manter o padrão de
propagação de erro consistente com os demais clients da camada.

### 5. Regenerar o stub gRPC após mudança de contrato

Quando dev-cart alterar `Protos/shoppingcart.proto`, rebuildar o `.csproj` (elemento
`<Protobuf Include="...">`) para regenerar o stub antes de ajustar
`Services/gRPC/ShoppingCartGrpcService.cs`. Nunca editar o `.proto` a partir deste lado.

## Critérios idiomáticos

- **Herdar de `Service` (abstract base), nunca `HttpClient` cru** — todo client novo em
  `Services/*.cs` deve seguir o padrão `GetContent`/`DeserializeResponse`/`ManageHttpResponse`
  já usado por `CatalogService`, `ShoppingCartService`, `OrderService` e `CustomerService`.
  Fonte: `src/api-gateways/DevStore.Bff.Checkout/Services/Service.cs:10` — DOMAIN-BFF-003.
  Um client que só recebe `HttpClient` via DI e chama `GetAsync`/`PostAsync` direto, sem
  herdar de `Service`, é desvio idiomático — reescrever antes de mergear.

- **Não tratar `IShoppingCartService`/`IShoppingCartGrpcService` como intercambiáveis** —
  DOMAIN-BFF-001 confirma que a escolha entre HTTP e gRPC para dev-cart depende do endpoint do
  BFF, não é uma preferência de estilo. Trocar o protocolo numa rota existente sem confirmar
  o impacto no client (BFF) e no server (dev-cart) quebra o contrato silenciosamente.

- **Nunca completar `IPaymentService` por iniciativa própria** — DOMAIN-BFF-002 registra que a
  interface está vazia porque o fluxo real de pagamento passa por
  `OrderService`→Orders.API→Billing.API. Uma implementação nova aqui criaria uma segunda rota
  de pagamento concorrente com o anchor gold `command_handler`
  (`src/services/DevStore.Orders.API/Application/Commands/OrderCommandHandler.cs`, ver
  `STACK_PROFILE.yaml`), que já é o dono desse fluxo.

- **Tratar `OrderDto` como superfície adicional de PCI** — DOMAIN-BFF-004: os mesmos campos de
  cartão em claro (`CardNumber`/`Holder`/`ExpirationDate`/`SecurityCode`) que trafegam via
  dev-billing passam também por aqui. Qualquer mitigação de PCI decidida para dev-billing tem
  que ser replicada nesta camada; não é um problema isolado do serviço de origem.
