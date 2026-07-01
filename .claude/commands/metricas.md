---
description: Agrega events.jsonl — rejeições por agente, tentativas médias, lead time
---

Leia todos os `.swarm/state/sprints/*/events.jsonl` e agregue: taxa de rejeição por agente ·
tentativas médias por task · tasks por sprint · lead time DISPATCHED→COMMITTED · gargalos
(agente/fronteira com mais REJECTED). O harness aprende sobre si mesmo — use para orientar
`/reaudit` e decisões de fusão/aposentadoria de agente (ADR-F5).
Apresente a agregação em tabela markdown (agente × métrica), nunca só prosa — decisão de
fusão/aposentadoria exige comparação numérica lado a lado, não impressão qualitativa.
Poucas sprints registradas ⇒ declarar amostra pequena explicitamente, nunca extrapolar tendência.
