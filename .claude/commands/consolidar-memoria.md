---
description: Roda consolidate-memory.py avulso — lições candidatas (episódica→semântica) + decay
---

`python3 .swarm/scripts-harness/consolidate-memory.py --root .`

Minera `.swarm/state/sprints/*/events.jsonl`, abstrai padrão de falha recorrente em lição
semântica COM evidência (episódios reais, não narrativa), e propõe decay de lições nunca
consultadas/com evidência sumida. Apresente as propostas ao usuário; o **curator** aplica o
aprovado em `.swarm/knowledge/memory/conhecimento.jsonl` (dedup por id).
