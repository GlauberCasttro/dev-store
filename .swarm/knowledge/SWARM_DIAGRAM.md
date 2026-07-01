# SWARM_DIAGRAM — DevStore (Fable v9/v11)

Diagrama de onboarding/debugging do harness. Ver [SWARM.md](../../SWARM.md) para a visão
diagnóstica (o que o harness É). Este arquivo é ONBOARDING — como as peças se encaixam na
prática, com os agentes/fronteiras REAIS deste repositório, não um template genérico.

## 1. Visão geral do harness

O tech-lead (papel do agente principal, nunca subagente) triagem, monta briefs e despacha para
17 agentes derivados do scan real do DevStore — 9 `dev-*` de bounded context, 1 `dev-messaging`
em standby, `qa-dotnet`, `verifier`, `po`, `curator`, `architect`, `security` e `devops` (gates).
Nenhum subagente tem tool de delegação (Agent/Task) — delegação é de nível único, sempre.

```mermaid
flowchart TD
    Founder[Founder/Usuário] --> TL[tech-lead — papel do main]
    TL -->|triagem + brief| Dev[dev-* / qa-dotnet]
    TL -->|ADR/Tier A| Arch[architect]
    TL -->|refinamento| PO[po]
    Dev -->|SUBMITTED| Ver[verifier — readonly]
    Ver -->|gate_report| TL
    TL -->|ACCEPTED/REJECTED| Dev
    TL -.->|/salvar-sessao| Cur[curator]
```

## 2. Hierarquia e roteamento de agentes

Roteamento é por território real (não por adivinhação): bug em `CreditCardPaymentFacade.cs`
vai para `dev-billing`; endpoint novo em `CatalogController.cs` vai para `dev-catalog`; contrato
gRPC em `Protos/shoppingcart.proto` cruza `dev-cart`↔`dev-checkout-bff` e pode exigir
`architect` se o contrato mudar. `security` é gate transversal (auth/PII/pagamento);
`devops` cobre `docker/`, `.github/workflows/`, `WebApp.Status`.

```mermaid
flowchart LR
    TL[tech-lead] --> Core[dev-core]
    TL --> Catalog[dev-catalog]
    TL --> Customers[dev-customers]
    TL --> Identity[dev-identity]
    TL --> Orders[dev-orders]
    TL --> Billing[dev-billing]
    TL --> Cart[dev-cart]
    TL --> BFF[dev-checkout-bff]
    TL --> Web[dev-web]
    TL -.standby.-> Msg[dev-messaging]
    Billing -.gate.-> Sec[security]
    Identity -.gate.-> Sec
    Customers -.gate.-> Sec
    TL -.infra.-> Ops[devops]
```

## 3. Ciclo de vida de task e rework

Máquina canônica (`core-spec.md §1`): `DRAFT → READY → DISPATCHED → SUBMITTED → VERIFYING →
(ACCEPTED | REJECTED)`. REJECTED volta a `READY` para retry; 2 REJECTED no MESMO critério aciona
arbitragem do `architect` (D7) em vez de insistir no loop. `PARTIAL` (escopo cresceu/faltou
contexto) re-escopa o brief, nunca força o agente a sair do `allowed_paths`.

```mermaid
stateDiagram-v2
    [*] --> DRAFT
    DRAFT --> READY
    READY --> DISPATCHED
    DISPATCHED --> SUBMITTED
    SUBMITTED --> VERIFYING
    VERIFYING --> ACCEPTED
    VERIFYING --> REJECTED
    REJECTED --> READY: retry
    REJECTED --> READY: 2x mesmo critério -> architect arbitra
    ACCEPTED --> COMMITTED: aprovação humana + git
    COMMITTED --> [*]
```

## 4. Fluxo típico de feature

Exemplo real da fronteira Orders: uma feature que toca `AddOrderCommand` passa por
`OrderCommandHandler` (valida → aplica Voucher via `VoucherValidation` → `CalculateOrderAmount`
recalcula no servidor, nunca confia no `Amount` do cliente — BIZ-2 — → paga via
`_bus.Request<OrderInitiatedIntegrationEvent>` síncrono → persiste → publica
`OrderDoneIntegrationEvent`). Se a feature for Tier A (contrato entre serviços), passa por
`architect` (ADR) ANTES do dev-*; se for bug-fix confirmado, vai direto a `dev-orders` → `verifier`.

```mermaid
sequenceDiagram
    participant PO as po
    participant TL as tech-lead
    participant AR as architect
    participant DO as dev-orders
    participant VE as verifier
    PO->>TL: escopo/critérios de aceite
    TL->>AR: Tier A? (contrato cross-serviço)
    AR->>TL: ADR aprovado
    TL->>DO: brief (allowed_paths=Orders.API/Domain/Infra)
    DO->>DO: AddOrderCommand -> OrderCommandHandler
    DO->>VE: SUBMITTED
    VE->>TL: gate_report PASS
    TL->>PO: ACCEPTED
```

## 5. Subagentes vs fronteiras reais do repo

Cada `dev-*` mapeia 1:1 para uma fronteira real do `ARCHITECTURE_TREE.md` — não é um template
com 4 slots fixos: `dev-orders` sozinho cobre 3 projetos (`Orders.API`+`Domain`+`Infra`) porque
compartilham stack/fluxo; `dev-billing` cobre `Billing.API`+`Billing.DevsPay` pela mesma razão.
`dev-messaging` fica em standby porque não há Saga/StateMachine real hoje (grep vazio) — só
ativa se essa realidade mudar.

```mermaid
flowchart TB
    subgraph Fronteiras reais
        A[DevStore.Core + WebAPI.Core] --- dc[dev-core]
        B[Catalog.API] --- dcat[dev-catalog]
        C[Customers.API] --- dcu[dev-customers]
        D[Identity.API] --- di[dev-identity]
        E[Orders.API+Domain+Infra] --- do[dev-orders]
        F[Billing.API+DevsPay] --- db[dev-billing]
        G[ShoppingCart.API] --- dca[dev-cart]
        H[Bff.Checkout] --- dbf[dev-checkout-bff]
        I[WebApp.MVC] --- dw[dev-web]
        J[MessageBus - standby] --- dm[dev-messaging]
    end
```

## 6. Modos sequencial, paralelo e background

Despachos SEM interseção de `allowed_paths` podem ir em paralelo (ex.: `dev-catalog` e
`dev-web` numa feature que toca as duas pontas). Despachos que dependem um do outro (ex.:
`dev-cart` altera `Protos/shoppingcart.proto` → `dev-checkout-bff` regenera o client gRPC) são
sequenciais. Nunca dois agentes com interseção de `allowed_paths` ao mesmo tempo — o
`guard-allowed-paths.sh` bloqueia por task ativa, não por cortesia.

```mermaid
flowchart LR
    subgraph Paralelo seguro
        P1[dev-catalog: endpoint novo] -.-> Merge[tech-lead concilia]
        P2[dev-web: tela nova] -.-> Merge
    end
    subgraph Sequencial obrigatório
        S1[dev-cart: muda .proto] --> S2[dev-checkout-bff: regenera client]
    end
```

## 7. Leis de handoff e `allowed_paths`

Executor nunca verifica/aceita o próprio trabalho (P2). `allowed_paths` do brief é a única
superfície de escrita do subagente — `guard-allowed-paths.sh` (PreToolUse Write|Edit) bloqueia
fail-closed sem task ativa ou fora do escopo. `protect-harness.sh` bloqueia QUALQUER ator
editando `.claude/`/`.swarm/scripts-harness/`/kernel fora de `SWARM_MAINT=1`.

```mermaid
flowchart TD
    Dev[dev-* tenta Write/Edit] --> G1{path em allowed_paths?}
    G1 -->|não| Block1[BLOQUEIA exit 2]
    G1 -->|sim| G2{path é harness?}
    G2 -->|sim, sem SWARM_MAINT| Block2[BLOQUEIA exit 2]
    G2 -->|não| Allow[permite escrita]
    Dev -->|SUBMITTED| Ver[verifier roda verification_command]
    Ver -->|nunca o próprio dev| Gate[gate_report]
```

## 8. Ritual de fechamento (`/fechar-feature` + `/fechar-sprint`)

`/fechar-feature`: exige TODAS as tasks da feature em `COMMITTED`, compila o diff completo,
resume objetivo entregue vs planejado, lista débitos conhecidos, gera relatório em
`.swarm/archive/features/FEATURE-ID/` — nunca altera a máquina de sprint. `/fechar-sprint`:
exige sprint 100% `COMMITTED` (nunca `ACCEPTED` sem commit — foi exatamente o furo que perdeu
os 2 INITs anteriores deste projeto), arquiva briefs+logs, atualiza `RESUME.md`.

```mermaid
sequenceDiagram
    participant TL as tech-lead
    participant Founder as founder
    TL->>TL: confirma todas as tasks COMMITTED
    TL->>TL: compila diff + lições + débitos
    TL->>Founder: relatório em archive/features/FEATURE-ID/
    Founder->>TL: aprova fechamento
    TL->>TL: transition.py --sprint SPRINT-NN --to ARCHIVED
    TL->>TL: atualiza RESUME.md
```
