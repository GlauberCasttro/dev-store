# CONVENTIONS — DevStore

Gerado do scan real (Estágio 1). Toda entrada tem evidência em `PROJECT_PROFILE.yaml` (`glossary`/`never_use`).

## Glossário de domínio (termo dominante · contagem real · never_use)

| Conceito | Termo do projeto | Ocorrências | Nunca use |
|---|---|---|---|
| Pedido | **Order** | 702 | Pedido (em nome de classe/pasta) |
| Carrinho | **ShoppingCart** | 226 | Basket, Cart isolado |
| Cupom/Desconto | **Voucher** | 283 | Coupon, Cupom |
| Cliente | **Customer** | 39 | Client |
| Produto | **Product** | 62 | Item (para produto de catálogo) |
| Documento fiscal | **SocialNumber** | 16 | CPF (como nome de campo) |
| Base de domínio | **Entity** | 24 (arquivos) | BaseEntity |
| Acesso a dados | **Repository** (`IRepository<T>`) | 12 | Gateway, Client (para persistência) |
| Erro de negócio | **ValidationResult** (FluentValidation) + **DomainException** | 6 | Notification pattern clássico (lista de notificações no Entity) |

Nomes de classe/pasta são **100% inglês** em todas as 11 fronteiras (0 ocorrências de "Pedido"/"Cupom"/"Cliente" como identificador). Mensagens de validação voltadas ao usuário final são em **português** (ex.: `VoucherValidation.cs`: "Este voucher está expirado").

## Sufixos e o que significam

| Sufixo | Papel |
|---|---|
| `*Controller` | endpoint HTTP MVC-style. **Exceção**: `DevStore.ShoppingCart.API` usa Minimal API em `Program.cs`, sem Controllers. |
| `*Service` | ambíguo por convenção do projeto: ou orquestração de caso de uso, ou client HTTP tipado — depende da fronteira. |
| `*Repository` | acesso a dados via `IRepository<T> : IDisposable where T : IAggregateRoot`. |
| `*Context` | `DbContext` do EF Core, 1 por serviço (nunca compartilhado entre fronteiras). |
| `*Command` / `*CommandHandler` | escrita via MediatR (`IRequest<ValidationResult>`). |
| `*Event` / `*EventHandler` | evento de domínio **in-process** via MediatR (`INotification`). |
| `*IntegrationEvent` / `*IntegrationHandler` | evento **cross-serviço** via MassTransit/RabbitMQ (`IConsumer<T>`). |
| `*ViewModel` | DTO de apresentação, só em `DevStore.WebApp.MVC`. |
| `*Dto` / `*DTO` | DTO de integração do BFF (`DevStore.Bff.Checkout`) — **grafia inconsistente**, as duas formas coexistem no mesmo projeto. |
| `*Mapping` | `IEntityTypeConfiguration<T>` do EF Core. |
| `*Validation` (nested class) | `AbstractValidator<T>` do FluentValidation, quase sempre classe aninhada dentro do próprio `Command`/`Model`. |

## Padrões que o projeto EVITA (never_use, `scope: convention`)

Toda entrada abaixo tem `source` = evidência de ausência verificada por grep, não presunção:

- **AutoMapper** — 0 ocorrências em qualquer `.csproj` (16/16). Mapeamento é sempre manual/explícito (`MapOrder`, `ToViewModel`, construtores de DTO).
- **BaseEntity** — 0 ocorrências. A base de domínio chama-se sempre `Entity` (`DevStore.Core/DomainObjects/Entity.cs`).
- **Basket** — 0 ocorrências. O domínio usa `ShoppingCart` de ponta a ponta (API + BFF + MVC).
- **Coupon / Cupom** — 0 ocorrências. O domínio usa `Voucher` em Orders, ShoppingCart e Bff.Checkout.
- **IGateway / IClient (para persistência)** — 0 ocorrências. Acesso a dados sempre via `IRepository<T>`.
- **Moq / NSubstitute / FluentAssertions / AutoFixture / Bogus em testes de qa** — ausentes do único `.csproj` de teste. O único teste real (`DevStore.Tests`) é 100% integração ponta-a-ponta com `WebApplicationFactory` + SQL Server real.
- **Refit como client HTTP ativo** — apesar de referenciado em 3 `.csproj` (`WebApp.MVC`, `Bff.Checkout`), NENHUM `Service` implementa uma interface Refit. Refit só é usado para capturar `ValidationApiException`/`ApiException` em `WebApp.MVC/Extensions/ExceptionMiddleware.cs`. Todo client HTTP real é `HttpClient` tipado (`AddHttpClient<TInterface,TImpl>`) + Polly.

## Padrões arquiteturais confirmados (não são never_use, são o padrão positivo)

- **Multi-provider de banco por configuração**: `AppSettings:DatabaseType` (`None|SqlServer|MySql|Postgre|Sqlite`) decide o provider EF Core em runtime via `ProviderSelector` — nenhum serviço fixa o provider no código.
- **CQRS in-process com MediatR**, não Command/Query separados por infraestrutura — mesmo `DbContext` para leitura e escrita (Dapper está declarado em 2 `.csproj` mas SEM uso real confirmado — dependência vestigial).
- **Eventos de domínio (MediatR, in-process) vs eventos de integração (MassTransit, cross-serviço)** são duas camadas distintas e nomeadas de forma diferente (`*Event` vs `*IntegrationEvent`) — nunca confundidas no código lido.
- **Autorização por claims customizada** (`CustomAuthorize.cs`, `ClaimsAuthorizeAttribute`) sobre JWT com JWKS rotativo (`KeepFor=15min`), não JWT com segredo estático.

## Idioma

| Camada | Idioma |
|---|---|
| Nomes de classe/pasta/namespace | Inglês (100%) |
| Mensagens de validação (usuário final) | Português |
| Comentários de código | Mistos, majoritariamente inglês |
