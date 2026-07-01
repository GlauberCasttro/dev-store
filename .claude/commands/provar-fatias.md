---
description: Executa o check_cmd das fatias de conhecimento e fixa confidence por prova de campo — run-checks.py
---

`python3 .swarm/scripts-harness/run-checks.py --root . --slices .swarm/knowledge/stack/dotnet-9.yaml,.swarm/knowledge/domain/*.yaml`

Roda o `check`/`check_cmd` de cada entrada de fatia (grep/comando real) e registra
PASS/FAIL/não-executável — não é auto-avaliação, é prova de campo. Entradas `unverified` que
passarem o check ganham candidatura a `verified` (curadoria humana decide a promoção).
Entrada com FAIL persistente (2+ rodadas) ⇒ sinal de que a claim ficou obsoleta (código mudou);
reportar ao usuário, não silenciar. Resultado grava em `confidence`/`last_checked` da própria fatia.
