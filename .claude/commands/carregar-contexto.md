---
description: Get-bearings — retoma a sessão lendo RESUME, sprint ativa e próxima task
---

Execute o ritual de get-bearings (core-spec §8), ordem fixa, pare quando suficiente:

1. Leia `.swarm/state/RESUME.md`.
2. Leia `sprints/SPRINT-NN/sprint.json` da sprint ativa (se houver).
3. Leia o brief da próxima task pendente.
4. Se houver task `IN_PROGRESS` numa janela nova, re-enuncie a âncora ao usuário
   ("Estávamos em TASK-N, fazendo X, próximo passo Y") e **aguarde confirmação**
   antes de qualquer despacho.

Nunca "explore o projeto" como substituto deste ritual. Se `RESUME.md` não existir
ainda (harness recém-gerado, nenhuma sprint aberta), declare isso e proponha `/nova-sprint`.
