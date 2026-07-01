---
description: Roda verify-artifacts.sh — confere manifesto, sentinelas de conteúdo e gate de docs ricos
---

`bash .swarm/scripts-harness/verify-artifacts.sh --root .`

Reexecuta o Aceite Final sem re-INIT: manifesto completo (todo artefato do TEAM_ROSTER existe),
sentinelas de conteúdo (zero placeholder, zero command-stub, `SWARM_DIAGRAM.md` com 8
seções/8 Mermaid/≥3500 chars), e docs ricos. Falha aqui **não autoriza** INIT/fechamento de
sessão como concluído — remedie só o que faltar, não regenere tudo.
