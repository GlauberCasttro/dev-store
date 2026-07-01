---
description: Roda harvest-rejections.py — cada REJECT do verifier vira candidato de fatia de domínio
---

`python3 .swarm/scripts-harness/harvest-rejections.py --root .`

Cada `REJECTED` registrado em `events.jsonl` vira candidato de entrada em
`.swarm/knowledge/domain/<agent>.yaml` (`confidence: unverified`, `source`=task+gate).
Apresente os candidatos; o **curator** aplica o aprovado. Fecha o ciclo de aprendizado — o
agente absorve o que errou, não só registra memória episódica.
