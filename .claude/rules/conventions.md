---
description: Convenções transversais do DevStore — glossário, padrões arquiteturais, never_use
alwaysApply: true
---

# Convenções — DevStore (transversal, todas as fronteiras)

Fonte completa: `.swarm/knowledge/CONVENTIONS.md`. Este arquivo resume o que TODO dev-*/qa
precisa saber, independente da fronteira.

## Glossário fixo (nunca sinonimizar)

Order (não Pedido) · ShoppingCart (não Basket/Cart) · Voucher (não Coupon) · Customer (não
Client) · Product (não Item) · SocialNumber (não CPF como nome de campo). Nomes de
classe/pasta/namespace são 100% inglês; mensagens de validação ao usuário final são em
português.

## Padrões estabelecidos (seguir, não reinventar)

- Base de domínio: `Entity` (nunca `BaseEntity`) + `IAggregateRoot` marker.
- Erro de negócio: `DomainException` (Value Objects) e `ValidationResult` via
  `CommandHandler.AddError` (Commands/MediatR) — dois canais, nunca misturados no mesmo Handler.
- Banco multi-provider por `AppSettings:DatabaseType`, nunca hardcoded (`ApiCoreConfig.WithDbContext<T>()`).
- MassTransit: `AddConsumers(assemblies)` + `UsingRabbitMq` + `ConfigureEndpoints(context)` — única forma correta.
- Acesso a dados: `IRepository<T>`, nunca `IGateway`/`IClient`.

## never_use v2 (scope: convention — source no PROJECT_PROFILE.yaml)

| Padrão | Nunca porque |
|---|---|
| AutoMapper | mapeamento é sempre manual/explícito (0/16 projetos referenciam) |
| BaseEntity | base é sempre `Entity` |
| Basket / Coupon | domínio usa ShoppingCart / Voucher |
| IGateway / IClient (persistência) | acesso a dados é via IRepository<T> |
| Moq / NSubstitute / Bogus em qa | filosofia é 100% integração real, zero mock |
| Refit como client ativo | vestigial — client real é HttpClient tipado + Polly |

## Stack .NET 9 — footguns ativos (ver `.swarm/knowledge/stack/dotnet-9.yaml` para os 20 completos)

- MediatR 13 sem `LicenseKey` configurado (NET9-STACK-001/002).
- `EnsureCreatedAsync()` em todos os 6 serviços — migrations versionadas são código morto em
  Dev/Docker (NET9-STACK-004).
- Guard de ambiente `IsDevelopment()||IsEnvironment("Docker")` — deploy fora desses ambientes
  sobe sem schema (NET9-STACK-005).
- Sem `IPipelineBehavior` de validação — Handler que esquece `IsValid()` bypassa tudo
  (NET9-STACK-010).

## Invariantes de domínio

Fonte canônica: `.swarm/knowledge/DOMAIN_INVARIANTS.yaml` (SEC-1/2/3, OPS-1, BIZ-1/2/3).
Toda task tocando dev-billing/dev-identity/dev-customers considera SEC-*; toda task tocando
dev-orders considera BIZ-*.

## Hierarquia de conflito

ADR > DOMAIN_INVARIANTS > rule local (este arquivo / layer rule) > fatia de stack > fatia de
domínio > orchestration_map > memória > skill global > preferência.
