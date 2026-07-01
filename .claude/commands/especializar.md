---
description: Re-roda só o Estágio 2b — pergunta o modo (single × roundtable) e regenera fatias com diff revisável
---

1. **Pergunte o modo** (nunca assuma): single-context (~3-5k tokens/stack, barato) × mesa
   adversarial (~15-25k tokens/stack, 3 vozes + gate de evidência). Mesa já usada nesta sessão
   com delta de 183% de itens verificados vs single — cite como referência, mas pergunte de novo.
2. Rode a especialização (mesa ou single) sobre `PROJECT_PROFILE.yaml` atual.
3. Regenere `STACK_PROFILE.yaml` + `.swarm/knowledge/stack/dotnet-9.yaml` com diff revisável.
4. Se modo = roundtable: registre a medição A-013 (mesa vs baseline existente) no
   `STACK_PROFILE.yaml` — obrigatório, sem ela o `harness-lint` reprova.
5. Não re-roda a sonda de maestria (2b.6) automaticamente — sinalize quais agentes precisam
   re-sonda se a fatia mudou de forma material.
