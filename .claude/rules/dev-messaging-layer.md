---
description: "Regras e critérios idiomáticos para a fronteira dev-messaging"
globs: ["src/building-blocks/DevStore.MessageBus/**"]
---

# Layer rule — dev-messaging (MessageBus, STANDBY)

dev-messaging está em modo STANDBY (`TEAM_ROSTER.yaml`: `trees: []`, `trees_if_activated:
["src/building-blocks/DevStore.MessageBus/"]`). Esta rule usa o glob de `trees_if_activated` —
ela existe e se aplica a partir do momento em que o agente for ativado pelo tech-lead; até lá,
`DevStore.MessageBus/` continua 100% território de dev-core. Complementa o cartão do agente
(`.claude/agents/dev-messaging.md`); mais curta que as demais layer rules porque o standby
limita o escopo de receitas aplicáveis hoje.

## How-tos da camada

### 1. Checar o gatilho de ativação antes de qualquer coisa

```bash
grep -rliE 'saga|statemachine' --include=*.cs src
```

Vazio hoje (DOMAIN-MESSAGING-001). Se este grep deixar de retornar vazio — ou se o tech-lead
pedir explicitamente uma Saga/StateMachine formal — é o sinal de que a ativação é justificada.

### 2. Investigar (não corrigir) o health check morto

`AddMessagingHealthCheck` existe em `MessagingExtensions.cs` mas nunca é chamado:

```bash
grep -rn "AddMessagingHealthCheck" src
```

Confirmar a ausência de call site fora da própria definição e reportar ao tech-lead
(DOMAIN-MESSAGING-003) — a correção em si é território de dev-core enquanto standby.

### 3. Desenhar uma Saga/StateMachine (só pós-ativação)

Ao ser ativado para uma orquestração cross-cutting nova, considerar o footgun de timeout já
mapeado antes de definir qualquer `RequestTimeout` ou retry: o orçamento de retry do Polly no
BFF/MVC (1s+5s+10s=16s) é menor que o timeout default do MassTransit `Request<>` (30s)
— NET9-STACK-009. Uma Saga nova não deve herdar esse descompasso sem tratá-lo explicitamente.

## Critérios idiomáticos

- **Saga/StateMachine real justifica ativação; consumer de bounded context não** —
  DOMAIN-MESSAGING-001 é o gatilho formal: hoje não existe nenhum `MassTransit
  Saga`/`StateMachine` no repo (grep vazio), e toda orquestração cross-serviço é ad-hoc
  (Request/Response síncrono ou Publish/Consume com compensação manual, ex.:
  dev-identity.Register). Só uma necessidade real de estado durável multi-serviço formal
  (Saga/StateMachine) justifica promover `trees_if_activated` a `trees` — uma correção pontual
  de consumer nunca justifica.

- **Os 5 `IConsumer<T>` existentes continuam do dono do bounded context, não migram por
  padrão** — DOMAIN-MESSAGING-002: `OrderIntegrationHandler`/`OrderOrchestratorIntegrationHandler`
  (Orders), `BillingIntegrationHandler` (Billing), `CatalogIntegrationHandler` (Catalog),
  `NewCustomerIntegrationHandler` (Customers) e `ShoppingCartIntegrationHandler` (Cart) são
  território de dev-orders/dev-billing/dev-catalog/dev-customers/dev-cart respectivamente. Uma
  task que pede para "corrigir o consumer do Billing" é escopo de dev-billing, não motivo para
  ativar dev-messaging — só a coordenação entre eles crescendo em complexidade reabriria essa
  discussão de fusão.

- **`AddMassTransit`+`AddConsumers`+`UsingRabbitMq`+`ConfigureEndpoints` é o único bootstrap
  correto, e é hoje 100% de dev-core** — o anchor gold `messagebus_bootstrap`
  (`src/building-blocks/DevStore.MessageBus/DependencyInjectionExtensions.cs`, confirmado por
  duas análises independentes em `STACK_PROFILE.yaml`) é o padrão de referência. Mesmo pós-ativação
  de uma Saga, o bootstrap do bus não migra para dev-messaging — só o desenho da
  orquestração nova entra no território ativado.
