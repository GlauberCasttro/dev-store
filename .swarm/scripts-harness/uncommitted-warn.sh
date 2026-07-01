#!/bin/bash
# uncommitted-warn.sh — Stop: avisa (não bloqueia) se a sessão encerra com
# mudanças não commitadas ou task ativa pendente.
set -u
ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$ROOT" 2>/dev/null || exit 0
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null || [ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]; then
  echo "[fable] ⚠️ Mudanças não commitadas — proponha commit (aprovação humana) ou registre no RESUME antes de encerrar." >&2
fi
if [ -f "$ROOT/.swarm/state/.active-task.json" ]; then
  echo "[fable] ⚠️ Task ativa pendente — sessão encerrando no meio de um despacho. Atualize o RESUME com o ponto exato." >&2
fi
exit 0
