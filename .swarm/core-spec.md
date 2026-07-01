# Core Spec — Fonte Única Normativa (protocol_version 7)

Este é o ÚNICO arquivo que define os protocolos operacionais do harness Fable.
Todo artefato gerado (kernel, agentes, commands) referencia esta spec — nunca a
duplica. Em conflito, esta spec vence.

Convenção de enforcement: cada regra termina com `[En | fallback Em]` — o nível
real emitido depende do `CAPABILITY.yaml` do projeto (ver SKILL.md → P1).

---

## 1. Máquina de estados de task (canônica)

```
DRAFT → READY → DISPATCHED → IN_PROGRESS → SUBMITTED
SUBMITTED → VERIFYING → ACCEPTED → COMMITTED
VERIFYING → REJECTED → READY        (retry; máx 3 tentativas)
VERIFYING → BLOCKED                 (precisa decisão/dependência — transitório, nunca final)
READY → DEFERRED                    (sprint destino obrigatório)
READY → CANCELLED                   (justificativa obrigatória no brief)
```

- Subagente entrega `SUBMITTED`. Verifier produz `gate_report`. Tech-lead decide
  `ACCEPTED`/`REJECTED`/`BLOCKED`. Três atores, três contextos. `[E0 + estrutura]`
- Toda transição passa por `scripts/transition.py <TASK> --to <STATE>` — valida a
  máquina, exige `gate_report.verdict: PASS` para ACCEPTED, registra ator,
  incrementa `attempts` em REJECTED, grava `events.jsonl`. Edição manual de
  `status` é violação — e é **detectável**: `--validate-all` falha se o
  `status` divergir do último `status_history[].to` (mão humana não deixa
  trilha). `[E3: pre-commit valida coerência | fallback E0]`
- Sprint tem máquina de estados PRÓPRIA e ferramentada — ver §1.1.

## 1.1 Máquina de estados de sprint (canônica)

```
DRAFT → ACTIVE → ARCHIVED
```

- Transição SOMENTE via `transition.py --sprint SPRINT-NN --to <STATE>` —
  edição direta de `sprint.json.status` é a mesma violação da edição de task.
- **ARCHIVED exige TODAS as tasks em COMMITTED ou CANCELLED** — a ferramenta
  recusa qualquer outra coisa. "ACCEPTED sem commit" é ciclo aberto, não entrega.
- **ACTIVE exige toda outra sprint ARCHIVED** (salvo `pre_migration`) — sprint
  nova não abre sobre sprint anterior mal fechada.
- `--validate-all` detecta sprint ARCHIVED com task fora de COMMITTED/CANCELLED.
- Não invente estados — "CLOSED", "DONE" etc. são bloqueados.
- Estados legados de harness migrado são tolerados apenas em sprints marcadas
  `pre_migration: true`.

## 2. Layout de estado

```
# FRONTEIRA (v7.5 — explícita p/ não confundir): `state/` = verdade estruturada da
# MÁQUINA (config + estado vivo que os SCRIPTS/transition consomem); `knowledge/` =
# corpus AGENTE-FACING que vira `context_inline` (o tech-lead extrai p/ o brief).
# Regra de colocação: "um AGENTE lê direto (§4) → knowledge/; só a máquina lê → state/".
.swarm/
├── state/                     # config + estado vivo da MÁQUINA (scripts/transition)
│   ├── CAPABILITY.yaml        # plataforma, níveis E, tools (Estágio 0)
│   ├── PROJECT_PROFILE.yaml   # scan: stack, versões, comandos, glossário, never_use v2, agent_trees
│   ├── STACK_PROFILE.yaml     # versões reais + índice de fatias + source_fingerprint (Estágio 2b)
│   ├── TEAM_ROSTER.yaml       # roster + protocol_version + status por agente
│   ├── ASSUMPTIONS.yaml       # Assumption Ledger (ver §9)
│   ├── RESUME.md              # âncora de retomada (ver §8)
│   ├── WORKFLOW.md            # estado macro: IDLE | IN_PROGRESS | BLOCKED | IN_REVIEW | DELIVERED
│   └── sprints/SPRINT-NN/
│       ├── sprint.json        # manifesto da sprint (decide)
│       ├── tasks/TASK-NN-XX-<TYPE>.json
│       └── events.jsonl       # append-only, trilha de auditoria
├── knowledge/                 # corpus AGENTE-FACING — fonte do context_inline
│   ├── ARCHITECTURE_TREE.md   # árvore enxuta do repo (ONDE) — norte do tech-lead (Estágio 1)
│   ├── ORCHESTRATION_MAP.yaml # fluxo de cada fronteira (COMO) — entry_points/typical_flow (Estágio 1)
│   ├── DOMAIN_INVARIANTS.yaml # invariantes SEC/OPS/BIZ (Estágio 2c) — agente-facing (§4), v7.5: era state/
│   ├── CONVENTIONS.md         # glossário/convenções em formato humano
│   ├── EXTERNAL_INTEGRATIONS.md
│   ├── SWARM_DIAGRAM.md       # 8 seções + 8 Mermaid; onboarding/debugging
│   ├── stack/                 # fatias de versão (Estágio 2b): <eco>-<major>.yaml
│   │                          #   entradas {id, kind, claim, applies_to, source, confidence, check}
│   ├── domain/                # fatias de domínio por agente (Estágio 2b.5): <agente>.yaml
│   ├── ADR/                   # decisões acumuladas
│   └── proposals/             # memória proposta por agentes, aguardando curadoria
├── logs/                      # 1 log curto por sessão (máx 15 linhas)
└── archive/SPRINT-NN/         # sprints encerradas (briefs + logs + snapshot)
```

Dados estruturados (JSON + YAML) decidem; Markdown explica. `SPRINT.md`/`PROJECT.md` (se gerados) são
interfaces humanas derivadas — nunca fonte de verdade.

## 3. Schema do brief (task JSON)

Campos obrigatórios — brief sem eles **não é despachável** (`harness-lint`
bloqueia `[E3]`):

```jsonc
{
  "id": "TASK-NN-XX-TYPE",          // TYPE ∈ {DEV, ARCH, QA, SEC, PERF, OPS}
  "sprint": "SPRINT-NN",
  "agent": "dev-api",
  "status": "DRAFT",
  "dependencies": ["TASK-NN-01-ARCH"],
  "allowed_paths": ["src/Api/Modules/Pedidos/"],   // nunca null, nunca glob amplo
  "objective": "máx 5 bullets",
  "context_inline": "trechos de ADR/contrato JÁ EXTRAÍDOS pelo tech-lead",
  "anchors": ["src/Api/Modules/Catalogo/CatalogoModule.cs"],  // existentes no disco
  "acceptance_criteria": ["critério específico e testável", "..."],
  "verification_command": "dotnet test --filter Pedidos",      // executável, escopado
  "probe_command": "dotnet test --filter Pedidos --list-tests", // OPCIONAL (D6) — modo não-mutante; transition.py roda no DISPATCHED
  "contract": null,                  // contract handshake (§5) — obrigatório se effort=high
  "attempts": 0,
  "status_history": [],
  "submission": null,                // preenchido pelo executor (§6)
  "gate_report": null                // preenchido pelo verifier (§7)
}
```

Regras de montagem (tech-lead):

- `context_inline` é etapa EXPLÍCITA: o tech-lead extrai os trechos relevantes de
  ADR/contrato/handoff para dentro do brief. Subagente não lê docs de arquitetura.
  **Fluxo pré-computado (v7.5): para task que mapeia/explica/altera um FLUXO** (ex.:
  "mapeie o fluxo de pedido", "como o pagamento circula", design cross-fronteira), o
  tech-lead extrai a entrada da fronteira do `knowledge/ORCHESTRATION_MAP.yaml`
  (typical_flow + entry_points + key_abstractions) **para o `context_inline`** — o
  agente recebe o fluxo pronto e responde dele, sem re-varrer o código. É o que torna o
  architect "certeiro e econômico em tokens" como no v6.4: o fluxo já está computado;
  o agente sintetiza, não redescobre. Sem isso, o agente grepa o código a cada pedido.
  **Boost por contexto (v5):** ao montar o `context_inline`, o tech-lead roda
  `repo-map.py anchors --frontier <fronteira> --boost "<termos do objetivo>"` —
  os símbolos citados no objetivo da task pesam 10x (aider), então as âncoras +
  assinaturas que entram no brief são as **relevantes àquela task**, não só as
  globalmente centrais. Ex.: objetivo "cancelar Pedido" traz `StatusPedido`/
  `PedidoCancelado` ao topo mesmo com centralidade global baixa.
- `verification_command` indefinível ⇒ o brief não está pronto; volte ao usuário
  com a pergunta certa. Nunca despache "a verificar depois".
- **Runnability (v5, D6):** presença do `verification_command` não basta — ele
  precisa **rodar**. No pré-despacho (§6, `--to DISPATCHED`), a ferramenta executa
  o comando em modo **não-mutante** (`--collect-only`/`--list-tests`/`--dry-run`/
  `-n` conforme a stack do PROFILE; o mapeamento por ecossistema vive em
  `PROJECT_PROFILE.stacks[].probe_cmd`). Comando que não resolve (binário ausente,
  filtro que casa zero testes, erro de sintaxe) ⇒ **brief volta a DRAFT**, não é
  despachado. Fecha o gap dos 3 ancestrais (todos só checavam presença; a falha
  do comando aparecia tarde, no verifier, depois do dev já ter trabalhado).
  `[E2: transition.py recusa DISPATCHED | fallback E0]` (anti-padrão 25)
- `allowed_paths` aperta ao arquivo/pasta real da task. QA nunca em código de
  produto. `[E2: guard-allowed-paths]`
- **Stack notes (v4):** task que toca superfície coberta por fatia
  (`knowledge/stack/`) ⇒ extrair os itens relevantes para o `context_inline`
  (≤10 linhas, com ids). Item `unverified` crítico para a task ⇒ o tech-lead
  resolve ANTES do despacho (fetch pontual, humano no loop, promove a
  `verified` com source) ou o declara como hipótese no brief — executor nunca
  fetcha (anti-padrão 20). `[E0]`
- **Critérios idiomáticos (v4):** checks aplicáveis da layer rule da fronteira
  ⇒ promover a `acceptance_criteria`. Cobrança idiomática é contratual: o
  verifier não julga estilo fora de critério — o que não foi promovido não
  será cobrado. `[E0; E3 na forma via lint da layer rule]`

## 4. Triagem (tech-lead, antes de qualquer despacho)

Três verificações mentais primeiro: **Rota clara?** (ambígua ⇒ apresente as
interpretações e pergunte) · **Brief pronto?** (§3) · **Escopo mínimo?** (um
subagente certo > vários desnecessários).

| Demanda | Rota | Critério de conclusão |
|---|---|---|
| Pergunta/status | responder direto (grafo/índice primeiro se estrutural) | — |
| Briefing/visão/diagrama do sistema | tech-lead ou architect respondem (ARCHITECTURE_TREE + grafo); diagrama via skill `diagramas-legais` — **nunca recusar** (§13, anti-padrão 27) | briefing/diagrama entregue no chat |
| Feature/épico | po → architect → dev-* → verifier → qa → verifier | gate_report PASS em cada elo |
| CRUD em padrão existente | dev-* direto (**nunca** architect) | gate_report PASS |
| Decisão de arquitetura/contrato | architect antes de qualquer dev (não-trivial ⇒ mesa_redonda: true, §5.1) | ADR aceita |
| Segurança/PII/auth | gate security + dev | audit PASS |
| Hot path/performance | dev → gate perf | meta do brief atingida |
| CI/deploy/infra | gate devops | pipeline verde |
| Bug produção | branch hotfix + dev + qa | verificação + aprovação humana |
| Harness/agentes | founder gate + modo manutenção | lint verde + diff aprovado |

Com 2+ tasks: apresentar plano (tabela task → agente → dependência) e perguntar
**sequencial ou paralelo**. Nunca assumir. Paralelo só sem dependência entre
tasks e nunca dois agentes no mesmo arquivo.

## 5. Contract handshake (tasks não-triviais)

Antes da primeira linha de código, dev e verifier acordam o "pronto":

1. Tech-lead despacha o **dev em modo proposta**: devolve `contract.proposed` —
   o que vai construir + como verificar (cenários concretos).
2. Tech-lead despacha o **verifier em modo revisão**: aprova ou contesta
   (`contract.review`), apontando critério não-testável ou lacuna.
3. Convergiu ⇒ `contract.agreed: true` no brief; só então a execução começa.

Quando usar: task com 3+ critérios de aceite, contrato entre frentes (BE/FE),
ou primeiro uso de um padrão novo. CRUD trivial pula o handshake.

Não-convergência no handshake (v5, D7): se dev e verifier não acordam o
`contract` em **2 rodadas** de proposta/revisão, o tech-lead escala ao architect
para arbitrar o "pronto" ANTES de qualquer código — mesmo mecanismo do §7.4,
aplicado na fase de contrato em vez da de verificação. Handshake que não fecha
não vira BLOCKED silencioso.

## 5.1 Mesa redonda arquitetural (runtime, opt-in)

Para decisão de arquitetura **não-trivial**, o tech-lead define no brief do
architect: `"mesa_redonda": true`. Com a flag ativa, o architect delibera com
**4–5 vozes do domínio do produto** (não personas genéricas de cloud) que devem
**discordar ou refinar de verdade** — mesa que só concorda é decoração:

```
MESA REDONDA — {produto}
Problema: [1 parágrafo]
[Voz 1 — papel no domínio] opinião + objeção concreta
[Voz N] ...
→ Convergência: decisão + O QUE FOI SACRIFICADO (trade-off explícito)
```

Regras: a convergência entra na ADR com os trade-offs nomeados; se a resposta
é "copiar padrão existente", **pule a mesa** ("padrão estabelecido — sem ADR;
seguir âncora X", anti-padrão 11); flag ausente/false ⇒ decisão direta com
tabela de trade-offs simples. Brief de architect com `mesa_redonda: true`
recebe extrato do STACK_PROFILE/fatia no `context_inline` (≤10 linhas) — as
vozes deliberam sobre as versões REAIS do projeto, não sobre a stack genérica. `[E0]`

## 6. Protocolo de despacho (tech-lead → executor)

**Atores das transições — explícito, sem elo tácito (modelo Encante):**
o tech-lead executa TODAS via ferramenta; o executor nunca toca o campo raiz
`status` (rodapé abaixo). Sequência por task:

| Transição | Quando | Quem |
|---|---|---|
| `--to DISPATCHED` | brief validado, pré-despacho (valida deps ACCEPTED+, branch ≠ main; **roda o probe não-mutante do `verification_command` — D6 §3, falha ⇒ recusa e volta a DRAFT**; grava `.active-task.json`) | tech-lead |
| `--to IN_PROGRESS` | imediatamente ANTES da invocação do subagent (Claude Code: tool Agent/Task; **Cursor: `/<nome>` explícito**), no mesmo turno (`.active-task` permanece p/ o guard) | tech-lead |
| `--to SUBMITTED` | no RETORNO do executor, conferida a `submission` preenchida | tech-lead |
| `--to VERIFYING` | ao despachar o verifier | tech-lead |

Executor que retorna sem `submission` (ou sem `submission.status`):
`--to SUBMITTED` → `--to VERIFYING` → `--to REJECTED --reason protocol_failure`
— a máquina anda pela ferramenta mesmo na falha. `[E3-coerência | fallback E0]`

Prompt de despacho — **cabeçalho fixo**:

```
Sprint: {NN} | Task: {TASK-ID} | Estado: DISPATCHED
O brief está COMPLETO abaixo — não leia estado, docs ou explore o projeto.
Path do brief (apenas para gravar submission): {path}

[BRIEF JSON COMPLETO INLINE]
```

— **rodapé fixo**:

```
Ao concluir:
1. Self-heal: rode {build/format escopado do PROJECT_PROFILE}; corrija até verde (máx 3 ciclos).
2. Preencha o campo `submission` do brief: {status: "SUBMITTED" ou "PARTIAL — motivo",
   files_changed, checks_run, risks, notes, handoff}.
   ⚠ NÃO toque no campo RAIZ `status` — pertence exclusivamente ao transition.py
   (edição é detectada pelo validate-all). `submission.status` ≠ `status` raiz.
3. NÃO atualize sprint.json/SPRINT.md/RESUME.md. NÃO rode git. NÃO acione outro agente.
4. Se não concluir: submission.status: "PARTIAL — {motivo específico}". Nunca silencie.
Retorne ao tech-lead.
```

Executor que retorna sem SUBMITTED = falha de protocolo ⇒ REJECTED
(`protocol_failure`).

## 7. Verificação (verifier) e aceite (tech-lead)

1. `transition.py <TASK> --to VERIFYING`.
2. Despachar **verifier** com: brief inline + `git diff --stat` + instrução de
   calibração (ver `verifier-calibration.md`) + extrato da fatia de stack
   relevante à task (≤10 linhas, com ids — base de evidência para FAIL de API
   de versão coberta por critério; sem o extrato, o verifier tem o MESMO cutoff
   do dev e aprova a mesma alucinação). O verifier:
   - confere arquivos alterados × `allowed_paths`;
   - roda `verification_command` e os `acceptance_criteria` um a um;
   - executa o cenário fim-a-fim quando houver superfície executável (servidor,
     CLI, testes de integração) — não confia só em unit test;
   - **retorna** o `gate_report` como bloco JSON no corpo da resposta:
     `{verdict: PASS|FAIL, evidence: [...], criteria: [{id, pass, proof}]}`.
     O verifier é readonly — **não persiste nada** (nem o brief).
3. Tech-lead **persiste** o gate_report via ferramenta — nunca na mão:
   `transition.py <TASK> --gate '<json>'` valida o schema, exige status
   VERIFYING, grava o campo no brief e emite `gate.report` em events.jsonl.
4. Tech-lead decide **sobre o gate_report** (não re-roda a verificação):
   - PASS ⇒ ACCEPTED. FAIL corrigível ⇒ REJECTED (erro exato no
     `status_history`; retry focado no erro — sem feature creep; máx 3) ⇒ READY.
   - **Escalada de não-convergência (v5, D7):** 2 REJECTED consecutivos no
     **mesmo critério** = dev e verifier não convergem (dev entrega X, verifier
     reprova; dev entrega Y, verifier reprova Y). Antes de BLOCKED, o tech-lead
     despacha o **architect como árbitro**, com as duas posições inline: a
     `submission.notes` do dev e o `gate_report.criteria[].proof` do verifier
     sobre o critério em disputa. O architect decide quem está certo OU reformula
     o `acceptance_criteria` (critério não-testável vira testável) e devolve um
     veredito de arbitragem. Só então: critério reformulado ⇒ READY (novo ciclo,
     `attempts` zera para o critério); impasse real (ambos defensáveis, falta
     decisão de produto) ⇒ BLOCKED + avisar usuário. Sem árbitro, o impasse
     consumia retries até intervenção humana (gap dos 3 ancestrais — terminal
     sempre BLOCKED). `[E0 + estrutura: architect isolado]` (anti-padrão 26)
   - 3 falhas independentes ou decisão de produto necessária ⇒ BLOCKED + avisar usuário.
5. Aprovação humana do commit: task ACCEPTED, lista exata de arquivos e mensagem
   propostas, **aprovação humana explícita**. Nunca `git add .`. `[E0 + E3: pre-commit]`
6. **Fechar o ciclo num ÚNICO commit — ordem que importa (achado de campo v6):**
   a) `transition.py <TASK> --to COMMITTED` (grava o estado: task JSON, events.jsonl)
   → b) atualizar `RESUME.md` → c) `git add` {arquivos de produto **+** os de estado
   que a transição sujou} → d) `git commit`. A transição vem ANTES do `git add` para
   que produto e estado entrem no MESMO commit. Rodar `--to COMMITTED` DEPOIS do
   commit deixa task JSON / events.jsonl / RESUME sujos fora dele = dois commits e
   working tree sujo (bug real). O fechamento NÃO é opcional: task em ACCEPTED é
   ciclo aberto — bloqueia o archive da sprint (§1.1) e aparece no /metricas.

## 8. Sessão: get-bearings, RESUME, encerramento

**Início de sessão (get-bearings — ordem fixa, pare quando suficiente):**
1. `RESUME.md` → 2. `sprints/SPRINT-NN/sprint.json` da sprint ativa → 3. brief
da próxima task → 4. (se IN_PROGRESS em janela nova) re-enunciar a âncora ao
usuário e **aguardar confirmação** antes de qualquer despacho.

**RESUME.md** (âncora): Status · última task ACCEPTED · próxima task · contexto
mínimo (≤5 linhas) · prompt-para-continuar. Atualizar após **cada** task aceita;
avançar 2+ tasks sem atualizar = falha de protocolo.

**Fim de sessão (`/salvar-sessao`):** log ≤15 linhas em `logs/` (data, task, o
que foi feito, decisões, arquivos, próximo passo) + RESUME atualizado + decisão
arquitetural → `knowledge/`. Sprint 100% **COMMITTED** ⇒ encerramento na MESMA sessão:
`transition.py --sprint SPRINT-NN --to ARCHIVED` (ferramenta valida COMMITTED/
CANCELLED) → só então arquivar briefs+logs em `archive/SPRINT-NN/`, atualizar
índices, propor próxima sprint (sprint sem sucessora planejada = roadmap órfão).

**Compatibilidade operacional V6.4 (mantida no v7 sem estado Markdown):**

- `/verificar-artefatos` (`/verify-artifacts` em migração): roda
  `.swarm/scripts-harness/verify-artifacts.sh --root .`. Confere manifesto, sentinelas de
  conteúdo, placeholders e docs ricos. Falha não autoriza INIT/fechamento.
- `/mostrar-integracoes`: lê `knowledge/EXTERNAL_INTEGRATIONS.md` e responde
  integração · direção · evidência · risco, sem re-scan.
- `/rescan-config`: reexecuta apenas a Camada D do scan (configs da raiz e em
  qualquer profundidade) e atualiza `EXTERNAL_INTEGRATIONS.md` com diff revisável.
- `/fechar-feature`: ritual de 8 etapas herdado do V6.4, mapeado ao v7. Exige
  tasks da feature em COMMITTED, gera relatório em
  `.swarm/archive/features/{FEATURE-ID}/` e não altera a máquina de sprint.

**Docs ricos:** `SWARM.md` deve linkar para `knowledge/SWARM_DIAGRAM.md`; o
diagrama deve ter exatamente 8 seções, exatamente 8 blocos Mermaid, >=3500
caracteres, zero placeholder e cobrir hierarquia, ciclo, rework, fronteiras,
paralelo/background, handoff e fechamento. O verificador executável é a fonte de
verdade desse gate.

## 9. Assumption Ledger (`ASSUMPTIONS.yaml`)

```yaml
- id: A-001
  component: "verifier isolado"
  assumption: "executores inflam a própria avaliação mesmo com critérios verificáveis"
  baseline_model: "{modelo em uso no INIT}"
  load_test: "aceitar 3 tasks via self-report e comparar com re-verificação independente"
  status: active        # active | relaxed | retired
- id: A-002
  component: "brief inline (anti-exploração)"
  assumption: "agente com contexto aberto desperdiça orçamento explorando e alucina paths"
  load_test: "1 task com brief por referência; medir reads extras e erros de path"
  status: active
```

`/reaudit` (disparar ao trocar de modelo): para cada entrada `active`, rodar ou
raciocinar o `load_test` e propor manter/afrouxar/aposentar. Componente
aposentado sai do harness **e** do ledger ganha `status: retired` com data —
histórico de por que já não é necessário.

## 10. Eventos (`events.jsonl`, append-only)

```json
{"type":"task.dispatched","task":"TASK-NN-XX","agent":"dev-api","at":"ISO8601"}
{"type":"task.submitted","task":"TASK-NN-XX","partial":false,"at":"..."}
{"type":"gate.report","task":"TASK-NN-XX","verdict":"PASS","at":"..."}
{"type":"task.accepted","task":"TASK-NN-XX","by":"tech-lead","at":"..."}
{"type":"task.rejected","task":"TASK-NN-XX","reason":"tests_failed","attempt":1,"at":"..."}
```

`/metricas` consome o ledger: taxa de rejeição por agente, tentativas médias,
tasks por sprint, gargalos — o harness aprende sobre si mesmo.

## 11. Memória e conhecimento

- **Memória — três tipos (v6):** **semântica** (`conhecimento.jsonl` — fatos/padrões),
  **episódica** (`events.jsonl` — o que aconteceu) e **estrutural** (`graph.json` —
  o mapa do código). O harness já produzia os três crus; a v6 os gere com regra própria.
- **Store semântico (P7):** `conhecimento.jsonl` (JSONL append-only). Escrita SÓ pelo
  **Curator** (`/salvar-sessao`) — append validado, dedup por id; subagente propõe em
  `submission.handoff`, nunca escreve durante a task (anti-padrão 24). Integridade por
  `check-knowledge-jsonl.sh` `[E3]`. Schema: `.swarm/knowledge/memory/MEMORY-SCHEMA.md`.
- **Aprender (consolidação episódica → semântica, v6):** `consolidate-memory.py` no
  `/fechar-sprint` minera o `events.jsonl`, acha padrões de falha recorrentes e PROPÕE
  lição semântica com os episódios como `evidence`. É o "aprendizado" real — abstração
  do histórico estruturado, não destilação de narrativa. Curadoria humana valida.
- **Recuperar (LLM-as-retriever, v6, NÃO grep):** `MEMORY_MODE=index` emite o índice
  compacto (id · título · tags · agente); o tech-lead ESCOLHE por significado as
  lições relevantes e puxa só o detalhe das escolhidas para o `context_inline`.
  Recuperação semântica sem vector DB. Keyword-match fica como pré-filtro do
  `inject-memory` (PreToolUse em Agent → `.swarm/state/memory-cache/<agent>.md`).
- **Esquecer (decay, v6):** `consolidate-memory.py` também propõe decay de lições
  nunca consultadas / com evidência sumida. Memória que só cresce vira ruído —
  esquecer é parte de aprender (mesmo princípio do Assumption Ledger). Promoção
  `validated:false→true` e decay passam por curadoria (diff de commit).
- ADRs acumulam em `knowledge/ADR/` e entram nos briefs **por extração inline** —
  agentes não abrem ADRs. O mesmo vale para TODO o knowledge/: árvore,
  convenções e integrações são matéria-prima do tech-lead ao montar o
  `context_inline` (§3); subagente só recebe o extrato.
- Fatias de **domínio** (`knowledge/domain/<agent>`, v5.2) seguem o MESMO regime
  das de stack: o tech-lead extrai o extrato relevante para o brief; capturam a
  profundidade da DELEGAÇÃO (princípios + padrões do projeto + ADRs vinculantes),
  com `source`/`confidence`/`check`. Maestria do especialista é verificada na sonda
  do 2b.6 (`mastery.passed` no STACK_PROFILE) antes de `specialized: approved`.
- Fatias de stack (`knowledge/stack/`) seguem o MESMO regime das ADRs: agente
  não abre por padrão; o tech-lead extrai para o brief (§3, stack notes). O
  `source_fingerprint` do STACK_PROFILE detecta fatia defasada (lint avisa
  quando o lockfile atual diverge `[E3]`) — atualização SÓ via `/rescan`,
  nunca automática e nunca silenciosa.
- `/rescan` re-roda o Estágio 1 **e o 2b** e atualiza PROFILE + STACK_PROFILE +
  knowledge/ (incl. fatias) com diff revisável, sem tocar no roster. Use após
  mudança estrutural relevante ou bump de dependência — árvore defasada gera
  brief cego; fatia defasada gera brief que mente.
- **Grafo de código (v5, P8):** `repo-map.py` constrói `.swarm/knowledge/graph.json`
  (portável, sucede o graphify). Pergunta **estrutural** (quem chama, o que existe,
  onde está) consulta o grafo primeiro (`/pesquisar-grafo`); pergunta de
  **implementação** (como funciona linha a linha) lê o arquivo. O grafo também
  alimenta as âncoras por centralidade da Seção 2 dos agentes (Estágio 4). Agentes
  de estado/git não se beneficiam — não force. `/atualizar-grafo` após mudança
  estrutural relevante.

## 12. Papéis fixos mínimos

Todo harness Fable tem, independente da stack: **tech-lead** (papel do main),
**verifier**, **po**, **qa-\*** (≥1), **curator** (v5 — escreve o store de
memória em `/salvar-sessao`; readonly fora dele). `architect` entra se o scan
detectar arquitetura em camadas/contratos entre módulos — e também atua como
**árbitro** na escalada de não-convergência (§5, §7.4). `dev-*` emergem do scan
(1 por fronteira real de escrita — camada, runtime ou pacote). Gates condicionais
(security, perf, devops, git-specialist) só com sinal do scan que os justifique
(ver `phases/02-derive.md`). Roster é imutável em runtime: mudança exige modo
manutenção. `[E2: protect-harness]`

## 13. Modos de operação e superfície de capacidade (v5)

Distinção fundamental que o template v4 confundia: **superfície de ESCRITA ≠
superfície de CAPACIDADE.**

- **Escrita** — que arquivos o agente grava. Apertada, enforçada por guard `[E2]`.
  Inalterada (architect só grava `knowledge/ADR/`, dev só no `allowed_paths`).
- **Capacidade** — o que o agente pode analisar, explicar, projetar, diagramar,
  discorrer. **Ampla no seu domínio.** Recusar explicar/discorrer/diagramar dentro
  do domínio é anti-padrão 27: "não gravo X como entrega" ≠ "não te ajudo com X".
  Um architect que não dá briefing do sistema, ou um tech-lead que recusa um
  diagrama, está quebrado — é o trabalho deles.

Três modos, regras distintas de pesquisa e escrita:

| Modo | Quem / quando | Pesquisa externa | Escrita |
|---|---|---|---|
| **Execução** | dev-*/qa contra brief | **NÃO** (anti-padrão 20 — brief é completo) | `allowed_paths` |
| **Especialização** | mesa 2b · `/especializar` | SIM, com proveniência → vira fatia | `knowledge/stack` (via tech-lead) |
| **Consultoria/design** | architect projetando · po refinando · tech-lead em briefing | SIM, limitada, com proveniência | só o artefato do papel; conselho/diagrama volta no chat |

**Conhecimento de sistema (só core):** tech-lead, architect e po conhecem o
sistema INTEIRO — têm o `ARCHITECTURE_TREE` completo e o grafo (`/pesquisar-grafo`)
como instrumento de pé (Seção 4 do agente) e **devem** produzir briefing, visão ou
diagrama quando pedido (diagrama via skill `diagramas-legais`). dev-*/qa seguem
cartão escopado à fronteira (P6 — contexto é orçamento, e eles são despachados o
tempo todo). Amplitude paga onde é rara, não onde é quente.

**Protocolo de pesquisa com proveniência (modos especialização e consultoria):**
1. Lacuna real **no domínio do agente** (não no brief) ⇒ o agente pesquisa na sua área.
2. Todo achado entra marcado: `source` (url/doc), `confidence` (verified|unverified),
   `check` (como confirmar na prática) — a MESMA disciplina das fatias 2b.
3. Achado que vira **decisão vinculante** (ADR, contrato, escolha de lib) ⇒
   **CHECKPOINT humano** antes de cravar. Exploratório volta marcado e não-vinculante.
4. O **verifier cobra**: claim de pesquisa sem `source`/`confidence` em artefato é
   anti-padrão 19 (idêntico às fatias); `unverified` crítico nunca vira fato.
5. Pesquisa que vira conhecimento durável é **promovida a fatia** `knowledge/stack/`
   pelo tech-lead — não se re-pesquisa o que já foi resolvido.

Anti-padrão 20 reconciliado (v5): fetch é proibido em **EXECUÇÃO** (dev numa task,
onde o brief é a verdade). Em **especialização** e **consultoria** é permitido com
a disciplina acima. A diferença é o modo, não o agente.

## Ops-verify — qualidade da OPERAÇÃO no fechar-sprint (v9-fix Parte B)

A máquina de estados garante o ESQUELETO (task não vira ACCEPTED sem `gate_report` PASS; sprint não
arquiva com task aberta). O **ops-verify** (rubrica `references/ops-verifier.md`) julga a QUALIDADE
que o script não vê, e é **exigido mecanicamente**:

- **Por task (no ACCEPTED):** ops-verify task — OPS-1 entrega==acceptance · OPS-2 handoff limpo ·
  OPS-3 verifier não-leniente.
- **Por sprint (no `/fechar-sprint`):** ops-verify sprint — OPS-4 objetivo entregue · OPS-5 delegação
  boa (escopo mínimo, agente certo) · OPS-6 estado limpo.
- Veredito PASS+`proof` por escopo em `.swarm/state/ops-validation.jsonl`.
- `transition.py --sprint X --to ARCHIVED` **bloqueia** sem essa prova (binding mecânico, espelha o
  `accept-check --audit` do INIT). Checagem avulsa: `transition.py --audit-ops --sprint X`.
