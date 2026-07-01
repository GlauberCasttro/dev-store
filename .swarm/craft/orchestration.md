# craft/orchestration — método do tech-lead (papel do main)

> Craft do **orquestrador**. O tech-lead não é subagente — é como o main **compõe,
> roteia, calibra e destila**. Puxado sob demanda; o kernel só aponta (contexto é
> orçamento). O que deixa o tech-lead esperto é **dado + método**, não kernel maior.

## 1 — Compor o brief (a decisão de maior alavancagem)
Antes de despachar, monte o `context_inline` a partir da **memória**, não do olho:
- puxe os patterns do agente+território (o hook já injeta em `memory-cache/<agente>.md`);
- olhe o **histórico de falha** do agente (rejeições recorrentes no `learning.db`);
- derive `acceptance_criteria` que cobrem o ponto fraco conhecido e escolha o
  `verification_command` que já pegou esse tipo de bug antes.

Brief que **pré-carrega a lição** > brief que confia que o agente redescobre.

## 2 — Rotear pelo placar, não pelo achismo
Leia o placar de confiabilidade (`success`/`failure` por agente no `learning.db`):
- mande a task pro agente com melhor track record naquele território;
- re-fatie a task que historicamente falha inteira;
- área de baixa confiança → probe / gate mais apertado antes.

## 3 — Calibrar o gate (não carimbar)
Ao decidir sobre o `gate_report`, pese o histórico do verificador: falso-PASS recorrente
num tipo de task → exija prova extra; critério que já regrediu → não aceite sem re-teste.

## 4 — Destilar (dispara o passo generativo)
No sucesso, ao fechar, pergunte **"que regra generalizável fez isso funcionar?"** e
registre como pattern *earned* (não string canned). É o ÚNICO ponto onde o modelo
generativo entra no loop de aprendizado.

## Guardrail (não estragar o v9)
- Plumbing (recall, escrita do placar, decay, consolidação) é **mecânico** — NÃO é
  tarefa do tech-lead. Mantém ele lean.
- **Não absorver o verificador:** o tech-lead ACEITA, não re-verifica (a tríade
  existe pra separar isso).
- Kernel só **aponta** pra este craft; nunca inlina o método. "Mais inteligente" =
  decide melhor, não decide mais coisas.

## 5 — Topologia de dispatch (OPÇÃO, não default)
O default é **hub-and-spoke** (tech-lead → dev → volta): simples, auditável, um decisor.
Só troque quando a ESTRUTURA da task pedir — e cada handoff continua sendo um brief
novo do tech-lead (delegação nível-único preservada; nada de subagente chamando subagente):
- **fan-out** (`waves[]`, o v9 já tem): tasks independentes em paralelo — SÓ sem dependência
  e sem interseção de `allowed_paths`.
- **pipeline** (A→B→C): quando a saída de um é entrada do outro (architect define contrato →
  dev implementa → qa testa). O tech-lead sequencia; cada etapa é um brief.
- **supervisor**: o próprio papel do main — monitora, re-despacha o que voltou PARTIAL/BLOCKED.

Guardrail: mais topologia = mais **modo de falha** (deadlock em pipeline, ordem/corrida em
fan-out). Por isso é opção, não default. E **NUNCA** mesh/consenso (Raft/Byzantine): fere
o nível-único e é justo o runtime de swarm do Ruflo que ficou idle no dev-store. Roteamento
de modelo por complexidade: `route-model.py` (barato/forte + bandit, carimba `routedBy`).
