---
description: "Regras e critérios idiomáticos para a fronteira dev-identity"
globs: ["src/services/DevStore.Identity.API/**"]
---

# Layer Rule — dev-identity (serviço Identity)

Destino sancionado dos how-tos e critérios idiomáticos do serviço Identity (emissão/validação
de JWT, JWKS rotativo, Argon2, saga de compensação manual). O cartão do agente
(`.claude/agents/dev-identity.md`) cobre persona/escopo/território — este arquivo cobre COMO
fazer e O QUE é objetivamente checável nesta fronteira.

## How-tos da camada

### 1. Emitir JWT com claims novas sem violar SEC-2

Qualquer claim adicional entra no bloco fluente já existente em `AuthController` — nunca um
segundo ponto de emissão de token:

```csharp
// Controllers/AuthController.cs (Login)
var jwt = await _jwtBuilder
    .WithUserId(user.Id)
    .WithEmail(user.Email)              // já existe — cuidado com SEC-2 se for logar isso
    .WithJwtClaims()
    .WithUserClaims()
    .WithUserRoles()
    .WithClaim("plan", user.Plan)        // nova claim: adicionar aqui, nunca fora do builder fluente
    .BuildToken();
```

Antes de adicionar uma claim sensível: confirmar que nenhum middleware de log expõe o payload
do token (SEC-2 — Email/SocialNumber/CardNumber/SecurityCode nunca em log ou resposta de erro).

### 2. Rotação de chave JWKS medindo o raio de impacto real

`SecurityKeys`/`ISecurityKeyContext` são dado crítico — qualquer mudança em `KeepFor` levanta
antes os chamadores reais de `AddJwtConfiguration` (são 7, não 9 — DOMAIN-IDENTITY-001):

```bash
grep -rl 'AddJwtConfiguration' src/services   # confirma os 7 consumidores reais antes de rotacionar
```

```csharp
// Data/ApplicationDbContext.cs
public class ApplicationDbContext : IdentityDbContext, ISecurityKeyContext
{
    public DbSet<SecurityKeyWithPrivate> SecurityKeys { get; set; }
    // KeepFor de 15min é lido em WebAPI.Core/Identity/JwtConfig.cs — não duplicar aqui
}
```

### 3. Hashing de senha exclusivamente via `IdentityConfig`

Nunca hashear senha manualmente em outro arquivo do serviço — Argon2 tem um único ponto de
configuração:

```csharp
// Configuration/IdentityConfig.cs
services.AddIdentity<IdentityUser, IdentityRole>(options => { /* ... */ })
    .AddErrorDescriber<IdentityMensagensPortugues>()
    .UseArgon2<IdentityUser>()          // único ponto — nunca replicar em outro lugar
    .AddEntityFrameworkStores<ApplicationDbContext>();
```

```csharp
// Controllers/AuthController.cs — nunca fazer isto:
// var hash = Convert.ToBase64String(SHA256.HashData(Encoding.UTF8.GetBytes(senha)));  ❌
```

### 4. Manter a saga de compensação manual do `Register()`

Sem orquestrador formal (nenhum MassTransit Saga/StateMachine no repo) — qualquer ajuste no
fluxo de registro preserva o padrão criar→publicar→aguardar→desfazer:

```csharp
// Controllers/AuthController.cs (Register)
var user = new IdentityUser { UserName = model.Email, Email = model.Email };
var createResult = await _userManager.CreateAsync(user, model.Password);
if (!createResult.Succeeded) return BadRequest(createResult.Errors);

var response = await _bus.Request<UserRegisteredIntegrationEvent, ResponseMessage>(
    new UserRegisteredIntegrationEvent(user.Id, model.Name, model.Email, model.SocialNumber),
    timeout: RequestTimeout.After(s: 30)); // teto default do MassTransit — não assumir maior (NET9-STACK-008)

if (!response.Message.ValidationResult.IsValid)
{
    await _userManager.DeleteAsync(user);  // compensação manual — nunca remover este bloco
    return BadRequest(response.Message.ValidationResult.Errors);
}
```

### 5. Endpoint de diagnóstico de token respeitando `#if DEBUG`

`ValidateJwt` só existe sob `#if DEBUG` — nunca reaproveitar ou expor esse endpoint em
Release/Production:

```csharp
#if DEBUG
[HttpPost("validate")]
public IActionResult ValidateJwt([FromBody] string token) { /* ... */ }
#endif
// endpoint de diagnóstico para produção = nova rota, com aprovação do gate security
```

## Critérios idiomáticos

- [DOMAIN-IDENTITY-003]: `Argon2`/`PasswordHasher` só aparece em `src/services/DevStore.Identity.API/Configuration/IdentityConfig.cs:38-40` — checável via `grep -rn 'Argon2\|PasswordHasher' src/services/DevStore.Identity.API`, que deve retornar exclusivamente esse arquivo. Um segundo ponto de hashing (ex. dentro de `AuthController`) é violação direta da política de configuração centralizada.
- [DOMAIN-IDENTITY-001]: o número real de chamadores de `AddJwtConfiguration` é 7 (Bff.Checkout, Orders.API, ShoppingCart.API, Billing.API, Customers.API, Catalog.API, Identity.API) — checável via `grep -rl 'AddJwtConfiguration' src/services`. Qualquer alteração de `KeepFor`/rotação de JWKS em `src/building-blocks/DevStore.WebAPI.Core/Identity/JwtConfig.cs:22` declara esse raio de impacto real (não 9, que inclui 2 libs sem `Program.cs` e 1 simulador in-process que não consome JWT).
- [DOMAIN-IDENTITY-004]: o endpoint `ValidateJwt` está envolto por `#if DEBUG`/`#endif` em `src/services/DevStore.Identity.API/Controllers/AuthController.cs:155-177` — checável via `grep -n '#if DEBUG' AuthController.cs`. Remover essa diretiva para habilitar o endpoint em builds Release é violação, mesmo que motivada por "facilitar debug".
- [DOMAIN-IDENTITY-002]: `Register()` implementa saga de compensação manual (`IBus.Request` → aguarda confirmação → `DeleteAsync` em caso de falha), ver `src/services/DevStore.Identity.API/Controllers/AuthController.cs:53,107-124` — checável confirmando que `grep -rliE 'saga|statemachine' --include=*.cs src` permanece vazio (ausência de orquestrador formal) e que o bloco de rollback (`DeleteAsync`) não foi removido sem substituição por orquestrador real.
