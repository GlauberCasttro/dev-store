---
description: Fecha a sprint ativa — exige todas as tasks COMMITTED, roda consolidação de memória e aprendizado
---

⚠ ACCEPTED sem commit NÃO fecha o ciclo — jamais arquivar assim.

1. Confirmar que TODAS as tasks da sprint estão `COMMITTED` (ou `CANCELLED` com justificativa).
2. Rodar `ops-verify` da sprint (rubrica `references/ops-verifier.md`): OPS-4 objetivo entregue ·
   OPS-5 delegação boa · OPS-6 estado limpo — grava prova em `.swarm/state/ops-validation.jsonl`.
3. `python3 .swarm/scripts-harness/consolidate-memory.py` — minera `events.jsonl` da sprint,
   apresenta lições candidatas (episódica→semântica, com evidência) + propostas de decay.
4. `python3 .swarm/scripts-harness/harvest-rejections.py` — cada REJECT do sprint vira candidato
   de fatia de domínio (`confidence: unverified`, `source`=task+gate).
5. `python3 .swarm/scripts-harness/transition.py --sprint SPRINT-NN --to ARCHIVED`
   (a ferramenta valida COMMITTED/CANCELLED).
6. Arquivar briefs+logs em `.swarm/archive/SPRINT-NN/`, atualizar índices, propor próxima sprint.
7. Commit proposto (aprovação humana explícita).
