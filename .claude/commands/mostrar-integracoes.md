---
description: Lê EXTERNAL_INTEGRATIONS.md e responde integração · direção · evidência · risco, sem re-scan
---

Leia `.swarm/knowledge/EXTERNAL_INTEGRATIONS.md` e responda a pergunta do usuário sobre
integrações externas (SQL Server, RabbitMQ, Seq, nginx, JWKS, gRPC) citando direção,
evidência (arquivo/config real) e risco conhecido. Nunca re-escanear o repo para isso — a
resposta já está no arquivo; se a pergunta exigir dado mais novo, sugira `/rescan-config`.
Exemplo de resposta: "RabbitMQ 4.1 — direção: publish/consume via MassTransit (bidirecional) —
evidência: `docker-compose.yml`, `AddMessageBus` — risco: sem DLQ configurada explicitamente".
Pergunta fora do arquivo (integração nova, não mapeada) ⇒ dizer isso, nunca inventar risco.
