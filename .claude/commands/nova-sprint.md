---
description: Abre uma nova sprint — exige a anterior ARCHIVED com todas as tasks COMMITTED
---

PRÉ-CHECK obrigatório: a sprint anterior está `ARCHIVED` com TODAS as tasks `COMMITTED`?
Se não → rode `/fechar-sprint` primeiro (nunca abrir sprint nova sobre uma mal fechada).

1. Refinamento com **po**: escopo, stories, critérios de aceite.
2. Montar `sprints/SPRINT-NN/sprint.json`.
3. `python3 .swarm/scripts-harness/transition.py --sprint SPRINT-NN --to ACTIVE`
   (a ferramenta valida a pré-condição — nunca editar o JSON à mão).
4. Branch de trabalho via aprovação humana explícita.
