# EXTERNAL_INTEGRATIONS — DevStore

Levantado de `docker/docker-compose.yml`, `docker/docker-common-resources.yml`, `.github/workflows/build.yml` e `appsettings.*.json` por serviço. Nenhum segredo/valor de conexão real é reproduzido aqui — só nomes, propósitos e evidência de arquivo.

## Infra compartilhada (`docker/docker-common-resources.yml`)

| Integração | Direção | Evidência | Risco/observação |
|---|---|---|---|
| **SQL Server 2022** (`mcr.microsoft.com/mssql/server:2022-latest`) | todos os serviços → 1 instância, 1 banco por serviço (`DSUsers`, `DSCatalog`, `DSCustomers`, `DSOrders`, `DSBilling`, `DSShoppingCart`, `DSStatus`) | `docker/docker-compose.yml` (`CUSTOMCONNSTR_DefaultConnection` por serviço) | Banco único para todos os serviços (não é 1 instância por serviço) — acoplamento de infra em dev/local. |
| **RabbitMQ 4.1** (`rabbitmq:4.1`) | todos os serviços que publicam/consomem `IntegrationEvent` | `docker/docker-common-resources.yml` (`RABBITMQ_DEFAULT_USER/PASS`); consumida via `MessageQueueConnection__MessageBus` | Ver `dev-billing` para o achado de PII/PCI trafegando em claro por este bus. |
| **Seq** (`datalust/seq:2025.1`) | todos os serviços → logging centralizado | `docker/docker-common-resources.yml`; consumido via `Serilog.Sinks.Seq` (`ApiCoreConfig.cs:16-21`) | — |
| **nginx** (`nginx:1.29`, `devstore-server`) | reverse proxy/TLS termination na frente de todos os serviços | `docker/docker-common-resources.yml` + `docker/nginx/devstore.conf` | Portas expostas: 7500/7501 (HTTP/HTTPS) e 7510/7511 (alt). |
| **generate-pfx** (`emberstack/openssl`) | gera certificado self-signed `devstore.academy-localhost.pfx` compartilhado por todos os serviços | `docker/docker-common-resources.yml` | Certificado de desenvolvimento, não produção. |

## Topologia de dependência entre serviços (`docker-compose.yml`, `depends_on`)

```
api-identity  ← (nenhuma dependência de serviço, só database+rabbitmq+logging)
api-cart      ← api-identity
api-catalog   ← api-identity
api-customers ← api-identity
api-order     ← api-identity
api-billing   ← api-identity, api-order
api-bff-checkout ← api-identity, api-cart, api-billing, api-order
web-mvc       ← api-catalog, api-identity, api-customers, api-bff-checkout
web-status    ← web-mvc
```

Confirma independentemente a cadeia `depends_on` do `ORCHESTRATION_MAP.yaml` (ex.: `dev-checkout-bff` depende de `dev-cart`+`dev-billing`+`dev-orders`; `dev-web` depende de `dev-checkout-bff`).

## CI (`.github/workflows/build.yml`)

| Etapa | Comando/serviço | Evidência |
|---|---|---|
| Setup .NET | `actions/setup-dotnet@v4` | linha 71 |
| Restore/Build/Test | `dotnet restore` / `dotnet build --configuration Release --no-restore` / `dotnet test --no-build --no-restore --configuration Release` | linhas 74-77 |
| Serviços de teste no CI | `mssql` (`mcr.microsoft.com/mssql/server:2022-latest`, porta 1433) + `rabbitmq` (`masstransit/rabbitmq`, porta 5672) | linhas 45-58 |
| Build/push de imagens Docker | `docker compose -f docker-compose-local.yml build/push` | linhas 88-101 |

Confirma que `build_cmd`/`test_cmd` do `PROJECT_PROFILE.yaml` vêm do CI real, não de hipótese.

## Autenticação/Identidade

| Integração | Direção | Evidência |
|---|---|---|
| **JWKS rotativo** (NetDevPack.Security.Jwt) | `dev-identity` emite, todos os outros serviços validam via `WebAPI.Core/Identity/JwtConfig.cs` | `JwtConfig.cs:22` (`KeepFor=15min`) |
| **Argon2** (NetDevPack.Security.PasswordHasher.Argon2) | hashing de senha, só em `dev-identity` | `IdentityConfig.cs:38-40` |

## Dashboard de observabilidade (`dev-status`)

Consome `/healthz-infra` de 8 serviços via HTTP polling — lista completa em `appsettings.Development.json` do `DevStore.WebApp.Status`: Frontend Web, Shopping Cart API, Identity API, Catalog API, Customer API, BFF Checkout, Billing API, Order API. **Bug de config confirmado**: formato diverge entre `Development`/`Docker` (string `Nome|URL;Nome|URL`) e `Production` (array JSON) — ver `ORCHESTRATION_MAP.yaml` (frontier `dev-status`).

## gRPC interno

`DevStore.ShoppingCart.API` expõe `ShoppingCartOrders.GetShoppingCart` (`Protos/shoppingcart.proto`); `DevStore.Bff.Checkout` consome como client gerado do mesmo `.proto` (`GrpcConfig.cs:18-23`) — único uso de gRPC no repositório, coexistindo com o caminho HTTP REST para o mesmo serviço.
