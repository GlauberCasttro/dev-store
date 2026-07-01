---
description: "Regras e critérios idiomáticos para a fronteira dev-web"
globs: ["src/web/DevStore.WebApp.MVC/**"]
---

# Layer rule — dev-web (WebApp.MVC)

Fronteira 100% consumidora HTTP (Views Razor + Controllers MVC + ViewModels), sem acesso a
domínio de backend. Complementa o cartão do agente (`.claude/agents/dev-web.md`) — aqui ficam
as receitas técnicas e os critérios idiomáticos citáveis; não duplicar persona/escopo/playbooks
já definidos lá.

## How-tos da camada

### 1. Criar um novo client HTTP tipado com Polly

Registrar em `Configuration/DependencyInjectionConfig.cs` usando `AddHttpClient<TClient,
TImplementation>()` encadeado com as policies padrão da camada (retry 1s/5s/10s + circuit
breaker 5x/30s), seguindo `CatalogService.cs`:

```csharp
services.AddHttpClient<ICatalogService, CatalogService>(client =>
    {
        client.BaseAddress = new Uri(settings.CatalogUrl);
    })
    .AddHttpMessageHandler<HttpClientAuthorizationDelegatingHandler>()
    .AddPolicyHandler(PollyExtensions.RetryPolicy())
    .AddPolicyHandler(PollyExtensions.CircuitBreakerPolicy());
```

Nunca declarar uma interface `[Get(...)]`/`[Post(...)]` estilo Refit para esse client — Refit
está no `.csproj` só como dependência vestigial (ver critério idiomático abaixo).

### 2. Nova página/rota MVC

Action em `Controllers/*.cs` → View em `Views/<Controller>/*.cshtml` → ViewModel em
`Models/*.cs`, populado exclusivamente a partir da resposta do Service tipado — nunca compor o
ViewModel com cálculo de negócio próprio.

### 3. Propagar o token de autorização em uma chamada nova

Usar o `HttpClientAuthorizationDelegatingHandler` já registrado (via
`AddHttpMessageHandler<T>()`), que lê o token obtido pelo `AuthService` e injeta o header
`Authorization: Bearer`. Não ler o cookie/claim diretamente dentro do Service para montar o
header à mão.

### 4. Investigar valor incorreto exibido numa View

Seguir a cadeia `CheckoutBffService.MapToOrder`/`GetLastOrder` → resposta HTTP do BFF → origem
(dev-orders/dev-billing) antes de alterar a View ou o ViewModel. Ver DOMAIN-WEB-004 — o
ViewModel é espelho passivo, não tem lógica de cálculo para corrigir.

### 5. Capturar exceção de API numa nova chamada

Deixar a captura de `ValidationApiException`/`ApiException` centralizada em
`Extensions/ExceptionMiddleware.cs` (único ponto real de uso de Refit no projeto, só para esse
propósito). Não replicar `try/catch` desse tipo em cada Controller.

## Critérios idiomáticos

- **Client HTTP real é `HttpClient` tipado + Polly — Refit nunca é client ativo** —
  DOMAIN-WEB-003 confirma que Refit está no `.csproj` apenas para capturar
  `ValidationApiException`/`ApiException` em `ExceptionMiddleware.cs`; todo client de dados
  usa `HttpClient` com retry (1s/5s/10s) e circuit breaker (5x/30s) via Polly, registrado em
  `Configuration/DependencyInjectionConfig.cs`. Introduzir uma interface `[Get(...)]` Refit
  nova para consumir um endpoint é desviar do padrão real sem uma decisão de arquitetura
  revisitada — tratar como bloqueante sem confirmação do tech-lead/architect.
  Fonte: `src/web/DevStore.WebApp.MVC/Extensions/ExceptionMiddleware.cs:8,34,38`.

- **Autenticação de sessão é Cookie, não Bearer direto** — DOMAIN-WEB-002:
  `CookieAuthenticationDefaults.AuthenticationScheme` é o esquema real
  (`Configuration/IdentityConfig.cs:12-18`); o JWT obtido via `AuthService` é parseado
  manualmente (`JwtSecurityTokenHandler`) só para extrair claims, o transporte de sessão do
  browser continua sendo o cookie. Copiar o padrão Bearer usado nos serviços de API
  (dev-orders/dev-catalog/etc.) sem adaptar para o fluxo de Cookie é erro idiomático nesta
  fronteira.

- **Zero acesso a domínio de backend — tudo passa por Service tipado** — DOMAIN-WEB-001: o
  `.csproj` só referencia `DevStore.Core`/`DevStore.WebAPI.Core`, nenhuma ProjectReference a
  `*.API`/`*.Domain` de serviço de negócio. Nenhuma task nesta camada deve propor acesso direto
  a `DbContext` ou repositório de outro bounded context — mesmo que pareça um atalho válido
  para "simplificar" uma consulta.

- **ViewModel é espelho passivo do BFF, não lugar de recálculo** — DOMAIN-WEB-004:
  `OrderViewModel`/`AddressViewModel`/`TransactionViewModel` são preenchidos 100% pela resposta
  HTTP de `CheckoutBffService` (`MapToOrder`/`GetLastOrder`,
  `src/web/DevStore.WebApp.MVC/Services/CheckoutBffService.cs:112-154`). Um bug de valor errado
  na tela nunca se resolve adicionando lógica de cálculo no Controller/ViewModel — a correção
  pertence ao BFF ou ao serviço de origem.
