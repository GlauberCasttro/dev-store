---
description: Reconstrói graph.json — repo-map.py build --method auto
---

`python3 .swarm/scripts-harness/repo-map.py build --root . --out .swarm/knowledge/graph.json --method auto`

Usa tree-sitter onde a gramática C# está instalada (refs sem comentário/string, símbolos
exatos), degrada para naive por arquivo quando falta (declarado em `degradations`). Rode após
mudança estrutural relevante (novo serviço, refactor grande) — árvore/âncoras defasadas geram
brief cego.
