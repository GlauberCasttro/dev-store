---
description: Migração de harness Fable anterior (protocol_version < 7) — mapeia estado antigo, preserva histórico
---

Não aplicável hoje — este harness já nasceu em `protocol_version: 7` (v9-cursor build, 7.6.0).
Se detectar `.project-swarm/` ou harness Encante/SwiftMap-style num merge/import futuro, mapeie
os artefatos antigos → novos equivalentes (ver tabela de detecção de estado do SKILL.md),
preserve `events.jsonl`/histórico, e NUNCA re-scan destrutivo sem confirmação explícita.
Mapear = converter cada artefato antigo para o equivalente do template atual (9 seções de
agente, `TEAM_ROSTER.yaml`, `DOMAIN_INVARIANTS.yaml`) preservando IDs de task/sprint já em uso.
Apresente o diff de mapeamento ao usuário antes de sobrescrever qualquer arquivo antigo.
