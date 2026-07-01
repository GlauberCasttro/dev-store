---
description: "Alias de migração V6.4 para /verificar-artefatos"
---

Alias — execute exatamente o mesmo protocolo de `/verificar-artefatos`:
`bash .swarm/scripts-harness/verify-artifacts.sh --root .`
Mantido só por compatibilidade de nome com o V6.4 anterior — prefira `/verificar-artefatos`
em documentação nova. Mesmo comportamento: manifesto completo, sentinelas de conteúdo,
zero placeholder. Falha aqui não autoriza fechar sessão/INIT como concluído.
