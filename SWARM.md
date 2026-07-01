# SWARM.md — DevStore (Fable v9/v11, protocol_version 7)

Visão DIAGNÓSTICA do harness — o que ele É, não como usá-lo no dia a dia (isso é
[HARNESS_USAGE.md](HARNESS_USAGE.md)). Fluxo visual completo em
[SWARM_DIAGRAM.md](.swarm/knowledge/SWARM_DIAGRAM.md) (8 seções, 8 diagramas Mermaid).

## Time (17 agentes, derivados do scan real)

| Território | Agente | Modelo |
|---|---|---|
| `DevStore.Core` + `WebAPI.Core` | dev-core | sonnet |
| `Catalog.API` | dev-catalog | sonnet |
| `Customers.API` | dev-customers | sonnet |
| `Identity.API` | dev-identity | sonnet |
| `Orders.API`/`Domain`/`Infra` | dev-orders | sonnet |
| `Billing.API`/`DevsPay` | dev-billing | sonnet |
| `ShoppingCart.API` | dev-cart | sonnet |
| `Bff.Checkout` | dev-checkout-bff | sonnet |
| `WebApp.MVC` | dev-web | sonnet |
| `MessageBus` (standby) | dev-messaging | sonnet |
| `tests/DevStore.Tests` | qa-dotnet | sonnet |
| (readonly, transversal) | verifier | sonnet |
| (produto/escopo) | po | haiku |
| (ADR/Tier A, cross-serviço) | architect | opus |
| (gate: auth/PII/pagamento) | security | sonnet |
| (gate: docker/CI/migrations) | devops | sonnet |
| (`/salvar-sessao`) | curator | haiku |

## Fluxo da tríade (executar / verificar / aceitar)

`dev-*`/`qa-dotnet` executam em contexto limpo, escrevem só em `allowed_paths`. `verifier` roda
isolado e readonly, cético por calibração, emite `gate_report` com evidência. `tech-lead`
(papel do agente principal, nunca subagente) decide ACCEPTED/REJECTED — nunca re-verifica no
próprio contexto. Ver seção 1–3 do diagrama para o fluxo visual e a máquina de estados.

## Enforcement Ladder instalada (níveis REAIS, Estágio 5)

| Regra | Nível instalado | Mecanismo |
|---|---|---|
| tech-lead não escreve produto | E2 | `guard-zones.sh` (PreToolUse Write\|Edit) |
| subagente só escreve no `allowed_paths` | E2 | `guard-allowed-paths.sh`, fail-closed |
| harness imutável fora de manutenção | E2 | `protect-harness.sh` |
| memória injetada antes do despacho | E2 | `inject-memory.sh` (PreToolUse Agent) |
| nenhum subagente com tool de delegação | E3 | `harness-lint.sh` |
| aceite completo no commit (não só lint) | E3 | `accept-check.sh` via `lefthook.yml` |

Nenhum nível acima do que a plataforma (`CAPABILITY.yaml`: `platform: claude-code`,
E1/E2/E3 todos `true`) realmente suporta — ver `.swarm/state/init-validation.jsonl` para a
prova em duas camadas (mecânica + semântica) de cada fase do INIT.

## Achados reais já mapeados (não corrigidos — aguardando priorização do founder)

- Enum mismatch confirmado: `CreditCardPaymentFacade.cs:73` faz cast posicional entre os dois
  `TransactionStatus` (Billing.API vs DevsPay) — `Chargeback`→`Refund` silenciosamente errado.
- PII/PCI em claro no bus: `OrderInitiatedIntegrationEvent` carrega `CardNumber`/`SecurityCode`.
- Zero idempotência em `BillingService.cs` (Authorize/Capture/Cancel) — redelivery duplicaria.
- `OrderStatus.Refused`/`Delivered` sem transição implementada (BIZ-3, gap de backlog).

## Invariantes inegociáveis

Fonte canônica: `.swarm/knowledge/DOMAIN_INVARIANTS.yaml` — SEC-1 (IDOR→404), SEC-2 (PII nunca
em log), SEC-3 (idempotência antes de nova feature de pagamento), OPS-1 (health-check antes de
deploy), BIZ-1/2 (Order.Amount recalculado no servidor, nunca confiado do cliente).

## Migração / histórico

Harness gerado do zero neste INIT (protocol_version 7, modo mesa adversarial/roundtable no
Estágio 2b). Não há harness Fable anterior neste repositório a migrar — dois INITs anteriores
foram tentados e perdidos por nunca terem sido commitados; este ciclo fecha com commit
explícito no Estágio 7 para não repetir o mesmo furo.
