---
description: Re-roda só a Camada D do scan (integrações/config) — atualiza EXTERNAL_INTEGRATIONS.md
---

Varra configs da raiz e em qualquer profundidade (`**/{config,settings,deploy,infra,env}*`,
incl. `docker/`, `.github/workflows/`) por URLs, filas, buckets, APIs de terceiros, connection
strings (NUNCA copiar segredos — só nomes/propósitos). Atualize
`.swarm/knowledge/EXTERNAL_INTEGRATIONS.md` com diff revisável antes de aplicar.
Reavalie também `gate_signals.devops`/`security` em `PROJECT_PROFILE.yaml` se a config nova
mudar a evidência (ex.: integração de pagamento nova liga `security`). Nunca aplicar o diff
sem o usuário revisar — este comando propõe, não substitui a leitura humana da mudança.
