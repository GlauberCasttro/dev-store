#!/usr/bin/env bash
# inject-memory.sh — PreToolUse hook (Claude Code): injeta memória relevante
# ANTES de spawnar um subagente, para o agente não redescobrir o que o projeto
# já aprendeu. Portável (Fable v5): roda para qualquer subagente nomeado; o
# filtro real é feito por query-memory.sh (campo `agent` + score + validated).
#
# Saída: escreve em $SWARM_MEM_CACHE/<agent>.md (default .swarm/state/memory-cache/),
# que o agente lê no início via a linha de "Consulta sob demanda" (Seção 4).
# Nenhuma escrita = nenhum ruído: arquivo vazio se não houver memória relevante.

set -euo pipefail

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

# Derivar o agente do payload — Claude Code (Agent/PreToolUse: subagent_type) OU
# Cursor (beforeSubmitPrompt: prompt/command com /<nome>). Sem esta segunda via o
# hook ficava MORTO no Cursor: lia só .tool_input.subagent_type, campo que o
# beforeSubmitPrompt do Cursor não carrega ⇒ AGENT vazio ⇒ exit 0, nunca injetava.
AGENT=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // .subagent_type // .agent // ""' 2>/dev/null || echo "")
DESC=$(echo "$INPUT"  | jq -r '.tool_input.description // .prompt // .command // .text // .message // ""' 2>/dev/null || echo "")
if [ -z "$AGENT" ]; then
  # Cursor: /<nome> explícito no prompt é o gatilho de invocação do subagente.
  AGENT=$(printf '%s' "$DESC" | grep -oE '(^|[[:space:]])/[a-z][a-z0-9-]+' | head -1 | tr -d ' /')
fi

# Sem agente nomeado (ex.: chamada não-Agent) ⇒ nada a fazer.
[ -z "$AGENT" ] && exit 0
# tech-lead é o papel do main, não recebe memória injetada por hook.
[ "$AGENT" = "tech-lead" ] && exit 0

REPO_ROOT="$(git -C "$(dirname "$0")/../.." rev-parse --show-toplevel 2>/dev/null || pwd)"
MEM_DIR="${SWARM_MEM_CACHE:-$REPO_ROOT/.swarm/state/memory-cache}"
mkdir -p "$MEM_DIR"

"$REPO_ROOT/.swarm/scripts-harness/query-memory.sh" "$DESC" "$AGENT" > "$MEM_DIR/${AGENT}.md" 2>/dev/null || true
# (v11) além da memória JSONL do v9, anexa os patterns aprendidos do learning.db —
# fail-safe e aditivo: se o script/store não existir, não escreve nada e o hook segue igual ao v9.
[ -x "$REPO_ROOT/.swarm/scripts-harness/recall-learning.py" ] && \
  "$REPO_ROOT/.swarm/scripts-harness/recall-learning.py" "$DESC" "$AGENT" >> "$MEM_DIR/${AGENT}.md" 2>/dev/null || true
exit 0
