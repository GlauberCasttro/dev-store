---
description: "Consulta estrutural no grafo de símbolos — repo-map.py query \"$ARGS\""
---

`python3 .swarm/scripts-harness/repo-map.py query "$ARGUMENTS" --graph .swarm/knowledge/graph.json --top 10`

Pergunta ESTRUTURAL (quem chama, o que existe, onde está) consulta o grafo primeiro — não
grepar o repo inteiro para isso. Pergunta de IMPLEMENTAÇÃO (como funciona linha a linha) lê o
arquivo depois de localizado aqui.
Exemplo: `/pesquisar-grafo OrderCommandHandler` retorna os arquivos que mais referenciam o
símbolo, rankeados por PageRank — use isso para achar a âncora antes de abrir qualquer arquivo.
Grafo ausente/desatualizado (`graph.json` não existe) ⇒ sugerir `/rescan` antes de responder.
