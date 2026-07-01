---
description: Percorre ASSUMPTIONS.yaml ao trocar de modelo — propõe manter/afrouxar/aposentar cada componente
---

Para cada entrada `status: active` em `.swarm/state/ASSUMPTIONS.yaml`, rode ou raciocine o
`load_test` contra o modelo ATUAL (não o `baseline_model` registrado) e proponha: manter,
afrouxar, ou aposentar (`status: retired` + data + motivo). Componente aposentado sai do
harness E do ledger. Harness que só cresce vira burocracia — este é o corte.
Apresente a proposta ao usuário ANTES de editar `ASSUMPTIONS.yaml` — aposentar componente
(ex.: remover um guard) é decisão do founder, nunca aplicada em silêncio pelo tech-lead.
Gatilho típico: menu do harness já existente item "⑤ /reaudit (troquei de modelo)".
