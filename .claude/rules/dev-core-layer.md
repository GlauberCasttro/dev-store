---
description: "Regras e critérios idiomáticos para a fronteira dev-core"
globs: ["src/building-blocks/DevStore.Core/**", "src/building-blocks/DevStore.WebAPI.Core/**"]
---

# Layer Rule — dev-core (shared kernel)

Destino sancionado dos how-tos e critérios idiomáticos do shared kernel (`DevStore.Core` +
`DevStore.WebAPI.Core`). `DevStore.MessageBus/` é território de **dev-messaging** (ver
`dev-messaging-layer.md`) — dev-core só LÊ o contrato de `AddMessageBus`. O cartão do agente (`.claude/agents/dev-core.md`)
cobre persona/escopo/território — este arquivo cobre COMO fazer e O QUE é objetivamente
checável nesta fronteira.

## How-tos da camada

### 1. Adicionar um novo provider de banco (multi-provider por configuração)

Nunca chame `UseSqlServer()`/`UseSqlite()`/`UseMySQL()`/`UseNpgsql()` fora de
`ProviderConfiguration.cs`. O fluxo correto é registrar a opção no enum e deixar o
`ProviderSelector` decidir em runtime via `AppSettings:DatabaseType`. Os providers reais
referenciados em `DevStore.WebAPI.Core.csproj` (grupo `Databases`) são `Microsoft.EntityFrameworkCore.SqlServer`
e `Npgsql.EntityFrameworkCore.PostgreSQL` (+ `Microsoft.EntityFrameworkCore.Sqlite`) — qualquer
provider novo entra nesse mesmo grupo, nunca solto num `.csproj` de serviço:

```csharp
// DatabaseFlavor/DatabaseType.cs
public enum DatabaseType
{
    SqlServer,
    Sqlite,
    MySql,
    Npgsql   // novo provider entra aqui, nunca hardcoded no Program.cs de um serviço
}

// DatabaseFlavor/ProviderConfiguration.cs
public static void UseProvider(this DbContextOptionsBuilder builder, DatabaseType type, string cnn)
{
    switch (type)
    {
        case DatabaseType.SqlServer: builder.UseSqlServer(cnn); break;
        case DatabaseType.Sqlite:    builder.UseSqlite(cnn); break;
        case DatabaseType.MySql:     builder.UseMySql(cnn, ServerVersion.AutoDetect(cnn)); break;
        case DatabaseType.Npgsql:
            AppContext.SetSwitch("Npgsql.EnableLegacyTimestampBehavior", true); // NET9-STACK-019
            builder.UseNpgsql(cnn);
            break;
    }
}
```

### 2. Registrar um novo `IntegrationEvent` consumido por outro serviço

`IntegrationEvent` é contrato publicado — trate mudança de shape como breaking change:

```csharp
// Messages/Integration/NovoEventoIntegrationEvent.cs
public class NovoEventoIntegrationEvent : IntegrationEvent
{
    public Guid AggregateId { get; set; }
    // nunca incluir PAN/CVV/CPF em claro aqui sem passar pelo gate security
}
```

Antes de alterar shape existente: `grep -rln "IConsumer<NovoEventoIntegrationEvent>" src/services`
para levantar todo consumidor e avisar o dono da fronteira consumidora.

### 3. Bootstrap de MassTransit/RabbitMQ em um novo serviço

A ordem é sempre `AddConsumers → UsingRabbitMq → ConfigureEndpoints(context)` por último —
nunca registrar `AddConsumer<T>` manualmente dentro do `UsingRabbitMq`:

```csharp
services.AddMassTransit(cfg =>
{
    cfg.AddConsumers(assembly);         // 1. descobre todos IConsumer<T> do assembly
    cfg.UsingRabbitMq((context, rmq) =>
    {
        rmq.Host(configuration["MessageBus:Host"]);
        rmq.ConfigureEndpoints(context); // 2. sempre por último — fanout-per-consumer
    });
});
```

### 4. Separar os dois canais de erro de negócio dentro de um `CommandHandler`

`DomainException` e `ValidationResult`/`AddError` nunca se misturam DENTRO do mesmo
`CommandHandler.Handle` de Command/MediatR (fora dele, ex. em `IConsumer`, `DomainException`
pode ser usada livremente — DOMAIN-CORE-002):

```csharp
public class NovoCommandHandler : CommandHandler, IRequestHandler<NovoCommand, ValidationResult>
{
    public async Task<ValidationResult> Handle(NovoCommand message, CancellationToken ct)
    {
        if (!message.IsValid()) return message.ValidationResult;

        if (/* invariante de negócio violada */)
        {
            AddError("mensagem de erro"); // canal ValidationResult — não lance DomainException aqui
            return ValidationResult;
        }
        // ...
    }
}
```

### 5. Configurar `AddMediatR` respeitando o gap de licenciamento conhecido

Hoje nenhum dos 6 serviços com MediatR seta `LicenseKey` — se a task pedir mitigar o warning,
a decisão de ONDE centralizar é do architect (gap real, não convenção já resolvida):

```csharp
services.AddMediatR(cfg =>
{
    cfg.RegisterServicesFromAssembly(assembly);
    // cfg.LicenseKey = "..." — ausente hoje nos 6 Program.cs; não afirmar que já existe
});
```

## Critérios idiomáticos

- [DOMAIN-CORE-003]: nenhum `Program.cs` de serviço chama `UseSqlServer`/`UseSqlite`/`UseMySQL`/`UseNpgsql` diretamente — a seleção de provider passa exclusivamente por `src/building-blocks/DevStore.WebAPI.Core/DatabaseFlavor/ProviderSelector.cs:10-24`. Checável via `grep -rn 'UseSqlServer\|UseSqlite\|UseMySQL\|UseNpgsql' src/services` — só pode aparecer dentro de `ProviderConfiguration.cs`.
- [DOMAIN-CORE-005]: todo bootstrap de MassTransit segue a ordem `AddConsumers(assemblies) → UsingRabbitMq → ConfigureEndpoints(context)` por último, como em `src/building-blocks/DevStore.MessageBus/DependencyInjectionExtensions.cs:17-30` (âncora gold `messagebus_bootstrap`). Checável verificando que `ConfigureEndpoints(context)` é a última chamada dentro do `UsingRabbitMq` de qualquer novo serviço — NÃO registrar `AddConsumer<T>` manual dentro do bloco, que é o anti-padrão conhecido.
- [NET9-STACK-001 / NET9-STACK-002]: nenhuma chamada a `AddMediatR` seta `cfg.LicenseKey` — confirmado em `src/services/DevStore.Orders.API/Program.cs:18` e `src/services/DevStore.Customers.API/Program.cs:20`. Um novo serviço com MediatR deve reproduzir o estado real (sem LicenseKey) e não afirmar que a licença já está centralizada — se a task for justamente mitigar isso, a centralização é decisão do architect, não do dev-core isoladamente.
- [DOMAIN-CORE-002]: `DomainException` e `ValidationResult` acumulado via `CommandHandler.AddError` nunca aparecem juntos dentro do mesmo `Handle` de um `CommandHandler` de MediatR — ver `src/building-blocks/DevStore.Core/Messages/CommandHandler.cs:16-19` e `src/building-blocks/DevStore.Core/DomainObjects/DomainException.cs:5`. Checável via inspeção do método `Handle`: se lança `DomainException` E chama `AddError` para o mesmo erro, é violação.
- [DOMAIN-CORE-001]: toda nova entidade de agregado herda de `Entity` (nunca `BaseEntity` ou hierarquia própria) e implementa `IAggregateRoot` como marker, como `src/building-blocks/DevStore.Core/DomainObjects/Entity.cs:7,17`. Checável via `grep -rn 'class.*: Entity' src/services`.
