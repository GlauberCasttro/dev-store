# ARCHITECTURE_TREE — DevStore

Mapa completo do repositório. Toda pasta real do `graph.json` aparece como nó próprio da árvore (nunca colapsada em parêntese) com ≥1 arquivo-âncora (★) mostrado DIRETAMENTE sob ela e contagem real `(+N arquivos)` do restante. Gerado do scan do Estágio 1 (11 subagentes de leitura) + `repo-map.py` (tree-sitter+pagerank, 249 arquivos, 350 assinaturas).

```
src/
├── api-gateways/
│   └── DevStore.Bff.Checkout/  — BFF do checkout, orquestra Catalog/Cart/Order/Customer via HTTP+gRPC
│       ├── Program.cs ★
│       ├── Configuration/
│       │   └── GrpcConfig.cs ★  registra ShoppingCartOrders.ShoppingCartOrdersClient  (+4 arquivos)
│       ├── Controllers/
│       │   ├── OrderController.cs ★  POST orders/, GET orders/last, GET orders/customers
│       │   └── ShoppingCartController.cs  orders/shopping-cart/* (7 endpoints)
│       ├── Extensions/
│       │   └── HttpClientAuthorizationDelegatingHandler.cs ★  (+1 arquivos)
│       ├── Models/
│       │   └── OrderDto.cs ★  Code/Status/Amount/Discount + CardNumber/Holder/CVV  (+5 arquivos)
│       └── Services/
│           ├── CatalogService.cs
│           ├── OrderService.cs
│           ├── PaymentService.cs  vazio  (+3 arquivos)
│           └── gRPC/
│               └── ShoppingCartGrpcService.cs ★  (+1 arquivos)
├── building-blocks/
│   ├── DevStore.Core/  — shared kernel de domínio, zero dependências de saída
│   │   ├── Communication/
│   │   │   └── ResponseResult.cs ★  payload padrão de erro HTTP
│   │   ├── Data/
│   │   │   └── IRepository.cs ★  contrato base de repositório (IDisposable, IAggregateRoot)  (+1 arquivos)
│   │   ├── DomainObjects/
│   │   │   ├── Entity.cs ★  public abstract class Entity (Id, Notificacoes/eventos)
│   │   │   ├── DomainException.cs
│   │   │   ├── Email.cs  value object com validação
│   │   │   └── IAggregateRoot.cs
│   │   ├── Exceptions/
│   │   │   └── DatabaseNotFoundException.cs ★
│   │   ├── Mediator/
│   │   │   └── MediatorHandler.cs ★  fachada sobre MediatR (SendCommand/PublishEvent)  (+1 arquivos)
│   │   ├── Messages/
│   │   │   ├── Command.cs ★  Command : IRequest<ValidationResult>
│   │   │   ├── Event.cs  Event : INotification
│   │   │   ├── CommandHandler.cs
│   │   │   ├── Message.cs
│   │   │   └── Integration/
│   │   │       └── OrderInitiatedIntegrationEvent.cs ★  carrega Holder/CardNumber/ExpirationDate/SecurityCode EM CLARO  (+8 arquivos)
│   │   └── Validation/
│   │       └── CreditCardExpiredAttribute.cs ★
│   ├── DevStore.MessageBus/  — território de dev-messaging (standby); dev-core só LÊ o contrato
│   │   └── DependencyInjectionExtensions.cs ★  AddMessageBus: bootstrap MassTransit/RabbitMQ  (+1 arquivos)
│   └── DevStore.WebAPI.Core/  — infra de API cross-cutting
│       ├── Configuration/
│       │   ├── ApiCoreConfig.cs ★  AddApiCoreConfiguration/UseApiCoreConfiguration (bootstrap de TODA API)
│       │   ├── DbHealthChecker.cs  polling de conexão no startup (10x, 5s)
│       │   ├── GenericHealthCheck.cs  /healthz e /healthz-infra por provider
│       │   └── MessagingExtensions.cs  AddMessagingHealthCheck — nunca chamada em nenhum Program.cs, código morto
│       ├── Controllers/
│       │   └── MainController.cs ★  base com CustomResponse
│       ├── DatabaseFlavor/
│       │   ├── ProviderConfiguration.cs ★  arquivo mais central do repo inteiro (PageRank 0.0268)
│       │   ├── DatabaseType.cs  enum None/SqlServer/MySql/Postgre/Sqlite
│       │   ├── ProviderSelector.cs
│       │   └── ContextConfiguration.cs
│       ├── Extensions/
│       │   └── PollyExtensions.cs ★  retry HttpClient (1s/5s/10s)  (+1 arquivos)
│       ├── Identity/
│       │   └── JwtConfig.cs ★  AddJwtConfiguration (JWKS)  (+1 arquivos)
│       └── User/
│           └── IAspNetUser.cs ★  GetUserId/GetUserEmail/GetUserToken  (+2 arquivos)
├── services/
│   ├── DevStore.Billing.API/  — 100% mensageria, Controller HTTP vazio
│   │   ├── Program.cs ★
│   │   ├── Configuration/
│   │   │   └── DependencyInjectionConfig.cs ★  (+3 arquivos)
│   │   ├── Controllers/
│   │   │   └── PaymentController.cs ★  classe VAZIA, sem endpoints reais
│   │   ├── Data/
│   │   │   ├── BillingContext.cs ★
│   │   │   ├── Mappings/
│   │   │   │   ├── PaymentMapping.cs ★
│   │   │   │   └── TransactionMapping.cs
│   │   │   └── Repository/
│   │   │       └── PaymentRepository.cs ★
│   │   ├── Facade/
│   │   │   └── CreditCardPaymentFacade.cs ★  BUG: cast enum posicional Chargeback→Refund (linha 73)  (+2 arquivos)
│   │   ├── Migrations/
│   │   │   └── BillingContextModelSnapshot.cs ★  (+2 arquivos)
│   │   ├── Models/
│   │   │   └── TransactionStatus.cs ★  Authorized/Paid/Denied/Refund/Canceled  (+5 arquivos)
│   │   └── Services/
│   │       ├── BillingIntegrationHandler.cs ★  3x IConsumer<IntegrationEvent>, única superfície real
│   │       └── BillingService.cs  Authorize/Capture/Cancel, SEM idempotência  (+1 arquivos)
│   ├── DevStore.Billing.DevsPay/  — lib in-process (ProjectReference), simulador de gateway
│   │   ├── Transaction.cs ★  Bogus.Random.Bool(0.7f) simula autorização (linha 101-102)
│   │   └── TransactionStatus.cs  Authorized/Paid/Refused/Chargeback/Cancelled  (+3 arquivos)
│   ├── DevStore.Catalog.API/
│   │   ├── Program.cs ★
│   │   ├── Configuration/
│   │   │   └── DependencyInjectionConfig.cs ★  (+4 arquivos)
│   │   ├── Controllers/
│   │   │   └── CatalogController.cs ★  GET products, products/{id}, products/list/{ids}
│   │   ├── Data/
│   │   │   ├── CatalogContext.cs ★
│   │   │   ├── Mappings/
│   │   │   │   └── ProductMapping.cs ★
│   │   │   └── Repository/
│   │   │       └── ProductRepository.cs ★  AsNoTrackingWithIdentityResolution() em GetAll
│   │   ├── Migrations/
│   │   │   └── CatalogContextModelSnapshot.cs ★  (+2 arquivos)
│   │   ├── Models/
│   │   │   └── Product.cs ★  Price/Stock/Active, TakeFromInventory  (+2 arquivos)
│   │   └── Services/
│   │       └── CatalogIntegrationHandler.cs ★  reage a OrderAuthorizedIntegrationEvent
│   ├── DevStore.Customers.API/
│   │   ├── Program.cs ★
│   │   ├── Application/
│   │   │   ├── Commands/
│   │   │   │   └── CustomerCommandHandler.cs ★  (+2 arquivos)
│   │   │   └── Events/
│   │   │       └── CustomerEventHandler.cs ★  (+1 arquivos)
│   │   ├── Configuration/
│   │   │   └── DependencyInjectionConfig.cs ★  (+4 arquivos)
│   │   ├── Controllers/
│   │   │   └── CustomerController.cs ★  GET/POST customers/address
│   │   ├── Data/
│   │   │   ├── CustomerContext.cs ★
│   │   │   ├── Mappings/
│   │   │   │   ├── CustomerMapping.cs ★
│   │   │   │   └── AddressMapping.cs
│   │   │   └── Repository/
│   │   │       └── CustomerRepository.cs ★
│   │   ├── Migrations/
│   │   │   └── CustomerContextModelSnapshot.cs ★  (+2 arquivos)
│   │   ├── Models/
│   │   │   └── Customer.cs ★  Name/Email/SocialNumber(CPF)/Deleted  (+2 arquivos)
│   │   └── Services/
│   │       └── NewCustomerIntegrationHandler.cs ★
│   ├── DevStore.Identity.API/
│   │   ├── Program.cs ★
│   │   ├── Configuration/
│   │   │   └── IdentityConfig.cs ★  Argon2  (+4 arquivos)
│   │   ├── Controllers/
│   │   │   └── AuthController.cs ★  Register/Login/RefreshToken/ValidateJwt(debug)
│   │   ├── Data/
│   │   │   └── ApplicationDbContext.cs ★  IdentityDbContext + ISecurityKeyContext
│   │   ├── Migrations/
│   │   │   └── ApplicationDbContextModelSnapshot.cs ★  (+2 arquivos)
│   │   └── Models/
│   │       └── UserViewModels.cs ★
│   ├── DevStore.Orders.API/
│   │   ├── Program.cs ★
│   │   ├── Application/
│   │   │   ├── Commands/
│   │   │   │   └── OrderCommandHandler.cs ★  AddOrder: valida→aplica voucher→recalcula valor→paga→persiste→publica  (+1 arquivos)
│   │   │   ├── DTO/
│   │   │   │   └── OrderDTO.cs ★  (+3 arquivos)
│   │   │   ├── Events/
│   │   │   │   └── OrderEventHandler.cs ★  (+1 arquivos)
│   │   │   └── Queries/
│   │   │       └── OrderQueries.cs ★  (+1 arquivos)
│   │   ├── Configuration/
│   │   │   └── DependencyInjectionConfig.cs ★  (+4 arquivos)
│   │   ├── Controllers/
│   │   │   ├── OrderController.cs ★  POST /orders, GET /orders/last, /orders/customers
│   │   │   └── VoucherController.cs
│   │   └── Services/
│   │       └── OrderIntegrationHandler.cs ★  (+1 arquivos)
│   ├── DevStore.Orders.Domain/
│   │   ├── Orders/
│   │   │   ├── Order.cs ★  CalculateOrderAmount, Authorize/Finish/Cancel
│   │   │   └── OrderStatus.cs  enum: Refused/Delivered SEM transição implementada (gap confirmado)  (+3 arquivos)
│   │   └── Vouchers/
│   │       ├── Voucher.cs ★  aggregate root próprio (não composição de Order)  (+2 arquivos)
│   │       └── Specs/
│   │           └── VoucherSpec.cs ★  (+1 arquivos)
│   ├── DevStore.Orders.Infra/
│   │   ├── Context/
│   │   │   └── OrdersContext.cs ★  Commit()+PublishEvents via ChangeTracker
│   │   ├── Mappings/
│   │   │   └── OrderMapping.cs ★  (+2 arquivos)
│   │   ├── Migrations/
│   │   │   └── OrdersContextModelSnapshot.cs ★  (+2 arquivos)
│   │   └── Repository/
│   │       └── OrderRepository.cs ★  (+1 arquivos)
│   └── DevStore.ShoppingCart.API/  — Minimal API, sem Controllers/
│       ├── Program.cs ★
│       ├── ShoppingCart.cs
│       ├── Configuration/
│       │   └── DependencyInjectionConfig.cs ★  (+4 arquivos)
│       ├── Data/
│       │   └── ShoppingCartContext.cs ★
│       ├── Migrations/
│       │   └── ShoppingCartContextModelSnapshot.cs ★  (+2 arquivos)
│       ├── Model/
│       │   ├── CustomerShoppingCart.cs ★  MAX_ITEMS=5
│       │   ├── CartItem.cs
│       │   └── Voucher.cs
│       └── Services/
│           ├── ShoppingCartIntegrationHandler.cs ★
│           └── gRPC/
│               └── ShoppingCartGrpcService.cs ★
├── tests/
│   └── DevStore.Tests/  — ÚNICO projeto de teste; testa SÓ Catalog (1/11 fronteiras)
│       ├── IntegrationTest.cs ★  fixture genérica (WebApplicationFactory)
│       └── CatalogApi/
│           ├── CatalogTests.cs ★  ÚNICO [Fact] de todo o repositório
│           └── CatalogIntegrationTests.cs
└── web/
    ├── DevStore.WebApp.MVC/
    │   ├── Program.cs ★
    │   ├── Configuration/
    │   │   └── DependencyInjectionConfig.cs ★  HttpClient tipado + Polly por serviço consumido  (+2 arquivos)
    │   ├── Controllers/
    │   │   ├── OrderController.cs
    │   │   ├── CatalogController.cs
    │   │   └── ShoppingCartController.cs  (+4 arquivos)
    │   ├── Extensions/
    │   │   └── ExceptionMiddleware.cs ★  trata ApiException/RpcException, refresh de token em 401  (+7 arquivos)
    │   ├── Models/
    │   │   ├── OrderViewModel.cs ★  arquivo MAIS central de todo o repo (PageRank 0.0400)
    │   │   ├── AddressViewModel.cs
    │   │   └── TransactionViewModel.cs  (+6 arquivos)
    │   ├── Properties/
    │   │   └── AssemblyInfo.cs ★
    │   ├── Services/
    │   │   ├── CheckoutBffService.cs ★  MapToOrder, FinishOrder, GetLastOrder (contra o BFF)  (+4 arquivos)
    │   │   └── Handlers/
    │   │       └── HttpClientAuthorizationDelegatingHandler.cs ★
    │   └── wwwroot/
    │       ├── js/
    │       │   ├── site.js ★
    │       │   └── payment.js  (+3 arquivos)
    │       └── lib/
    │           └── jquery-validation-unobtrusive/
    │               └── jquery.validate.unobtrusive.js ★  (+1 arquivos)
    └── DevStore.WebApp.Status/  — gate devops/observabilidade, NÃO dev-* pleno
        └── Program.cs ★  dashboard HealthChecksUI, agrega 8 serviços via /healthz-infra
```

## Notas de completude

- **`docs/`** existe na raiz mas está **vazio** (0 arquivos) — sem ADRs pré-existentes.
- **`Views/`** de `DevStore.WebApp.MVC` (23 arquivos `.cshtml`) não aparecem no `graph.json` (repo-map indexa só extensões de código, `.cshtml` fora do `CODE_EXT`) — listadas aqui via `find` direto: `Catalog/`, `Home/`, `Identity/`, `Order/`, `Shared/Components/{Paging,ShoppingCart,Summary}/`, `ShoppingCart/`.
- **`docker/`** (infra, fora de `src/`): `docker-compose.yml` + `docker-common-resources.yml` (SQL Server 2022, RabbitMQ 4.1, Seq, nginx) + `nginx/devstore.conf` + certs.
- Todas as contagens `(+N arquivos)` vêm de `repo-map.py build` (249 arquivos indexados, incl. `.cs`/`.js` — ver `wwwroot/js`, `wwwroot/lib`) — pastas com apenas arquivos não-código (`.cshtml`, `.json`, `.csproj`, `.css`) não entram na contagem estrutural; citadas via `find` direto quando relevante (ex.: Views).
