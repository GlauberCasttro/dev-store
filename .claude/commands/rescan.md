---
description: Re-roda os Estágios 1 e 2b — PROFILE + STACK_PROFILE + knowledge/ atualizados com diff, roster intocado
---

1. Re-executar o Estágio 1 (Scan⁺): `python3 .swarm/scripts-harness/repo-map.py build --method auto`
   para atualizar `graph.json`, depois re-derivar `PROJECT_PROFILE.yaml` + `ARCHITECTURE_TREE.md` +
   `ORCHESTRATION_MAP.yaml` + `CONVENTIONS.md` + `EXTERNAL_INTEGRATIONS.md`.
2. Re-executar o Estágio 2b (Specialize): **pergunta o modo de novo** (single × roundtable) —
   atualiza `STACK_PROFILE.yaml` + fatias de stack/domínio, com diff revisável.
3. Roster (`TEAM_ROSTER.yaml`) fica intocado — use `/especializar` para re-perguntar só o modo,
   ou derive manualmente se surgiu fronteira nova.
4. Apresentar diff ao usuário antes de aplicar.
