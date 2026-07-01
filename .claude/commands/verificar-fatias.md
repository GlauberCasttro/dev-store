---
description: Marca fatia stale quando a âncora mudou no disco — check-slice-drift.py
---

`python3 .swarm/scripts-harness/check-slice-drift.py --root .`

Compara o `source_fingerprint` do `STACK_PROFILE.yaml` contra o hash atual dos
`fingerprint_inputs` (global.json, .csproj dos building-blocks). Diferença ⇒ fatia marcada
`stale`, nunca atualizada em silêncio — só `/especializar` regenera de fato. Rode no pre-commit.
Saída esperada: lista de fatias `stale` (se houver) + fingerprint antigo vs novo, para o
usuário decidir se a mudança justifica re-especializar agora ou esperar a próxima sprint.
