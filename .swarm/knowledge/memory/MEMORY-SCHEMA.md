# Store de memória — `conhecimento.jsonl`

Memória persistente entre sessões (lição aprendida → reaplicada). Cada linha é um
JSON independente (JSONL), **append-only**. É o que evita o agente redescobrir, a
cada sprint, o que o projeto já decidiu. Origem: sistema de memória do Encante,
generalizado no Fable v5 (filtro por campo `agent`, não por prefixo de ID).

## Campos

```json
{
  "id": "SP-1",
  "text": "frase curta (≤ 20 palavras) — a lição",
  "detail": "detalhe técnico completo: o padrão, código/âncora, por que importa",
  "applies_to": ["keyword1", "keyword2"],
  "agent": "shared | <nome-do-agente-do-roster>",
  "sprint": "02",
  "validated": true,
  "supersedes": null,
  "superseded_by": null,
  "source": "TASK-NN-XX ou ADR-00N",
  "score": 1,
  "consultado_em": null
}
```

| Campo | Regra |
|---|---|
| `agent` | `shared` (todos) ou o nome exato de um agente do `TEAM_ROSTER`. É o filtro de relevância — **não há prefixo de ID por domínio** (portabilidade). |
| `validated` | só entradas `true` são injetadas. Lição nova entra `false` até confirmada por uso. |
| `score` | relevância acumulada (default 1). Sobe quando consultada e aplicada com sucesso. `query-memory.sh` injeta só `score >= MEMORY_SCORE_MIN`. |
| `superseded_by` | id que tornou esta entrada obsoleta. Não-nulo ⇒ nunca injetada. Lição não se apaga, se supera. |
| `consultado_em` | sprint mais recente em que foi aplicada. Null = nunca. Alimenta poda de memória morta. |
| `evidence` | (v6) ids de episódios (tasks) que sustentam a lição quando ela veio da consolidação. Evidência some ⇒ candidata a decay. |

## Os três tipos de memória (v6)

O harness tem os três tipos cognitivos — e já produzia os crus:

| Tipo | É | Onde |
|---|---|---|
| **Semântica** | fatos/padrões abstraídos | `conhecimento.jsonl` (este arquivo) |
| **Episódica** | o que aconteceu, com timestamp | `events.jsonl` (audit trail) |
| **Estrutural** | o mapa do código (quem chama quem) | `graph.json` (repo-map) |

## Aprender = consolidar episódica → semântica (v6)

`consolidate-memory.py` (no `/fechar-sprint`) lê o `events.jsonl`, acha **padrões de
falha recorrentes** (ex.: "dev-api rejeitado 3x por idempotência") e PROPÕE lição
semântica com os episódios como `evidence`. Não é o Curator destilando a narrativa —
é minerar o histórico estruturado e abstrair a regra. Curadoria humana decide o que
vira `validated:true` (anti-padrão 24).

## Recuperar = LLM-as-retriever, não grep (v6)

`MEMORY_MODE=index` emite o **índice compacto** (id · título · tags · agente). O
tech-lead lê o índice e ESCOLHE por significado as lições relevantes à task — só os
ids escolhidos têm o detalhe puxado para o `context_inline`. Recuperação semântica
sem vector DB. O keyword-match continua como pré-filtro barato do `inject-memory`.

## Esquecer = decay (v6)

Memória que só cresce vira ruído. `consolidate-memory.py` também PROPÕE decay de
lições nunca consultadas / com evidência sumida. Esquecer é parte de aprender
(mesmo princípio do Assumption Ledger).

## Regras de delta-update (Curator — roda em `/salvar-sessao`)

1. **Append-only para entrada nova.** Nunca reescrever o arquivo inteiro.
2. **Edit cirúrgico para existente.** Só `detail`/`score`/`superseded_by`, via `jq` ou edição localizada.
3. **Dedup por `id`** antes do append (`check-knowledge-jsonl.sh` é o gate E3).
4. **Sobreposição de `applies_to` ≥ 60%** com entrada existente ⇒ editar a existente, não duplicar.
5. **Quem escreve é o Curator**, despachado pelo tech-lead no fim da sessão — nunca o subagente durante a task (anti-padrão 3: subagente não escreve estado global).

## Fluxo

- **Leitura:** `inject-memory.sh` (PreToolUse) chama `query-memory.sh` com a `description`
  da task e o nome do agente → grava `.swarm/state/memory-cache/<agent>.md`. O agente lê
  esse arquivo pela linha de Consulta sob demanda (Seção 4 do template).
- **Escrita:** `/salvar-sessao` despacha o Curator, que destila a sessão em lições e faz
  append validado. O gate `check-knowledge-jsonl.sh` no pre-commit bloqueia store corrompido.

## Assumption Ledger

Este componente compensa: *"o modelo não tem estado entre sessões e re-deriva decisões já
tomadas, gastando contexto e divergindo do que o projeto firmou"*. Entrada `A-mem` no
`ASSUMPTIONS.yaml` — load-test: rodar a mesma classe de task em duas sessões sem memória e
medir divergência de decisão. Se um modelo futuro mantiver decisões estáveis sem o store,
`/reaudit` propõe relaxar.
