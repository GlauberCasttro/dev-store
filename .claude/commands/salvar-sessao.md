---
description: Fecha a sessão — log curto, RESUME atualizado, e despacha o Curator para destilar memória
---

1. Escreva um log ≤15 linhas em `.swarm/logs/` (data, task, o que foi feito, decisões, arquivos, próximo passo).
2. Atualize `.swarm/state/RESUME.md` (status · última task ACCEPTED · próxima task · contexto ≤5 linhas · prompt-para-continuar).
3. Despache o agente **curator** com o log desta sessão + `submission.handoff` de tasks recentes
   — ele destila lições REAIS (rejeições recorrentes, retrabalho, decisão de runtime) e faz
   append validado em `.swarm/knowledge/memory/conhecimento.jsonl` (dedup por id).
4. Se a sprint ativa está 100% COMMITTED, proponha `/fechar-sprint` na mesma sessão.

Nunca o main escreve direto em `conhecimento.jsonl` — só o curator, e só aqui.
