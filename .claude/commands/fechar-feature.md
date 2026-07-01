---
description: Ritual de 8 etapas (V6.4→v7) — exige tasks da feature COMMITTED, gera relatório, não altera a máquina de sprint
---

1. Confirmar TODAS as tasks da feature em `COMMITTED`.
2. Compilar o diff completo da feature (arquivos tocados, por task).
3. Resumo do objetivo entregue vs planejado.
4. Lições/decisões relevantes (candidatas a `/aprender` ou `/consolidar-memoria`).
5. Invariantes de domínio tocadas (`DOMAIN_INVARIANTS.yaml`) — todas respeitadas?
6. Débitos conhecidos deixados (se houver).
7. Gerar relatório em `.swarm/archive/features/FEATURE-ID/` (substitua `FEATURE-ID` pelo identificador real da feature sendo fechada).
8. Apresentar ao usuário — este comando NÃO altera `sprint.json` nem a máquina de estados de sprint.
