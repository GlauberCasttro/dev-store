---
description: Roda eval-harness.py — mede ganho on×off por agente + backstop comportamental
---

`python3 .swarm/scripts-harness/eval-harness.py --root . --results .swarm/state/eval-results.json`

Compara desempenho COM vs SEM o cartão/fatia do agente (on×off) e roda o backstop
comportamental (`--flow-probe`/`--reads`: leituras de produto por fronteira `verified`, limiar
≤1 — agente que já tem `ORCHESTRATION_MAP` não deveria precisar reler o código do zero).
Agente sem ganho mensurável vira candidato a `retired` no `ASSUMPTIONS.yaml` (ADR-F5).
