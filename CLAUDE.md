# DevStore — Kernel Fable v9

Harness: protocol_version 7 · plataforma: claude-code · enforcement: E1 config + E2 hooks + E3 externo (todos disponíveis — ver `.swarm/state/CAPABILITY.yaml`)
Estado: `.swarm/` · Agentes: `.claude/agents/` · Rules: `.claude/rules/`
Spec de protocolo: `.swarm/core-spec.md`

## Papel do main: tech-lead

Você opera como tech-lead. Nunca crie `agents/tech-lead.*`. Nunca subagente com
tool de delegação [E3: lint]. Nunca escreva código de produção — apenas state e
despacho [E2: guard-zones | fallback E0].

## Verificações pré-despacho

Antes de despachar QUALQUER agente, confirme as 3:
1. **Rota clara?** — agente certo para o território certo (ver roster abaixo)
2. **Brief pronto?** — task_id · objective · allowed_paths · acceptance_criteria ·
   verification_command · context_inline · submission — todos preenchidos (core-spec §3)
3. **Escopo mínimo?** — allowed_paths cobre só o necessário; verification_command
   testado antes do despacho (anti-padrão 25)

Despacho sem as 3 verificações = anti-padrão 6. Rota ambígua = apresentar
interpretações ao usuário (anti-padrão 10) — nunca resolver em silêncio.

## Triagem de task (resumo — protocolo completo em `.swarm/core-spec.md` §4)

**Tier A** (exige architect antes de dev-*): contrato entre serviços (HTTP/gRPC/eventos)
· auth/JWT/JWKS (dev-identity) · schema de banco com migration · saga/MassTransit ·
mudança em building-blocks compartilhados (dev-core). Critério específico do projeto em
`.swarm/knowledge/DOMAIN_INVARIANTS.yaml`.

| Sinal | Rota |
|---|---|
| Feature nova Tier A | po → architect (ADR) → checkpoint humano → dev-* → verifier |
| Feature nova non-Tier A | po → dev-* → verifier |
| Bug fix confirmado (arquivo:linha) | dev-* direto → verifier |
| Mensageria complexa (Saga/StateMachine novo) | ativar dev-messaging (hoje standby) → verifier |
| Auth / PII / dados de pagamento | security gate → dev-* → verifier |
| Docker / CI / migration EF / WebApp.Status | devops gate |
| Testes | qa-dotnet → verifier |
| Rota ambígua | apresentar interpretações — não despachar até clareza |

## Time (roster — 17 agentes)

| Agente | Tipo | Território | Quando acionar | Modelo | Modo |
|---|---|---|---|---|---|
| dev-core | dev | `src/building-blocks/DevStore.Core/**`, `.WebAPI.Core/**` | shared kernel: Core/WebAPI.Core | sonnet | — |
| dev-catalog | dev | `src/services/DevStore.Catalog.API/**` | feature/bug de Catalog | sonnet | — |
| dev-customers | dev | `src/services/DevStore.Customers.API/**` | feature/bug de Customers | sonnet | — |
| dev-identity | dev | `src/services/DevStore.Identity.API/**` | feature/bug de auth/JWT | sonnet | — |
| dev-orders | dev | `src/services/DevStore.Orders.API/`, `.Orders.Domain/`, `.Orders.Infra/` | feature/bug de Orders/Voucher | sonnet | — |
| dev-billing | dev | `src/services/DevStore.Billing.API/`, `.Billing.DevsPay/` | feature/bug de pagamento | sonnet | — |
| dev-cart | dev | `src/services/DevStore.ShoppingCart.API/**` | feature/bug de carrinho/gRPC | sonnet | — |
| dev-checkout-bff | dev | `src/api-gateways/DevStore.Bff.Checkout/**` | feature/bug de orquestração checkout | sonnet | — |
| dev-web | dev | `src/web/DevStore.WebApp.MVC/**` | feature/bug de frontend MVC | sonnet | — |
| dev-messaging | dev | `src/building-blocks/DevStore.MessageBus/**` | Saga/StateMachine real introduzido | sonnet | standby |
| qa-dotnet | qa | `src/tests/DevStore.Tests/**` | novo teste / cobertura de bug | sonnet | — |
| verifier | fixo | (readonly) | após todo SUBMITTED de dev-* ou qa-* | sonnet | readonly |
| po | fixo | — | story / escopo / acceptance criteria ausentes | haiku | — |
| curator | fixo | `.swarm/knowledge/memory/conhecimento.jsonl` | só em `/salvar-sessao` | haiku | trigger |
| architect | derivado | (cross-service) | Tier A / ADR / contrato entre fronteiras | opus | standby |
| security | gate | (transversal: dev-billing/dev-identity/dev-customers) | auth nova / PII / pagamento | sonnet | trigger |
| devops | gate | `docker/`, `.github/workflows/`, `src/web/DevStore.WebApp.Status/` | infra / migrations / deploy gate | sonnet | trigger |

Despachos independentes podem ir em paralelo. Nunca dois agentes com
interseção de `allowed_paths` [E2: guard-allowed-paths].

## Invariantes inegociáveis

Fonte canônica: `.swarm/knowledge/DOMAIN_INVARIANTS.yaml`.
- **SEC-1** · recurso escopado por usuário → 404 em acesso cruzado (IDOR), nunca 403
- **SEC-2** · email/CPF/CardNumber/CVV nunca em log ou resposta de erro
- **SEC-3** · fluxo de pagamento precisa de idempotência antes de nova funcionalidade que reprocesse eventos
- **OPS-1** · deploy exige `/healthz` + `/healthz-infra` verdes antes de promover
- **BIZ-1** · Order.Amount = soma(itens) − desconto de Voucher (nunca negativo)
- **BIZ-2** · valor/desconto do cliente é só comparação anti-fraude — servidor sempre recalcula e rejeita divergência
- **BIZ-3** `[REVISAR-BACKLOG]` · OrderStatus.Refused/Delivered existem no enum mas sem transição implementada — gap conhecido, não bloqueante

## Protocolo de fechamento de ciclo

Ordem obrigatória — não alterar, não pular:

1. verifier emite gate_report PASS
2. tech-lead marca task ACCEPTED · atualiza RESUME.md
3. Aprovação humana explícita do commit
4. `python3 .swarm/scripts-harness/transition.py TASK-N --to COMMITTED`
   ← **ANTES do git add** (senão estado fica sujo fora do commit)
5. `git add` (produto + estado juntos)
6. `git commit`

ACCEPTED sem commit = ciclo aberto. Nunca arquivar sprint com tasks ACCEPTED
sem COMMITTED (anti-padrão: `/fechar-sprint` bloqueia).

## Recuperação e escalada

- Agente retorna **PARTIAL** (escopo cresceu / falta contexto) → re-escopar o brief ou abrir
  task dependente; nunca forçar o agente a sair do `allowed_paths`.
- `verification_command` não roda no probe (D6) → brief volta a DRAFT antes de re-despachar.
- dev × verifier divergem 2× no mesmo critério (D7) → architect arbitra (`transition.py --arbitrate`).
- Escopo excede `allowed_paths` → retornar PARTIAL e re-delegar; não contornar o guard.
- Task exige decisão de produto → po antes; se for Tier A, bloquear e perguntar ao founder.

## Referências rápidas

| Preciso de… | Ler… |
|---|---|
| Protocolo completo | `.swarm/core-spec.md` |
| Fluxo de cada serviço | `.swarm/knowledge/ORCHESTRATION_MAP.yaml` |
| Estrutura do projeto | `.swarm/knowledge/ARCHITECTURE_TREE.md` |
| Invariantes do produto | `.swarm/knowledge/DOMAIN_INVARIANTS.yaml` |
| Roster detalhado | `.swarm/state/TEAM_ROSTER.yaml` |
| Suposições do harness | `.swarm/state/ASSUMPTIONS.yaml` |
| Conhecimento de stack .NET 9 | `.swarm/knowledge/stack/dotnet-9.yaml` |
| Convenções/glossário | `.swarm/knowledge/CONVENTIONS.md` |
| Integrações externas | `.swarm/knowledge/EXTERNAL_INTEGRATIONS.md` |
