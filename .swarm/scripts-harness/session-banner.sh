#!/bin/bash
# session-banner.sh — SessionStart: elimina metade do get-bearings com 1 linha.
# branch · sprint ativa · tasks por estado · último log
set -u
ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
BRANCH=$(cd "$ROOT" && git branch --show-current 2>/dev/null || echo '?')
SPRINT=$(ls -d "$ROOT"/.swarm/state/sprints/SPRINT-* 2>/dev/null | sort | tail -1 | xargs -n1 basename 2>/dev/null || echo 'nenhuma')
COUNTS=""
if command -v jq >/dev/null 2>&1 && [ -d "$ROOT/.swarm/state/sprints" ]; then
  COUNTS=$(cat "$ROOT"/.swarm/state/sprints/*/tasks/*.json 2>/dev/null | jq -r '.status' 2>/dev/null | sort | uniq -c | awk '{printf "%s:%s ", $2, $1}')
fi
LAST_LOG=$(ls -t "$ROOT/.swarm/logs/" 2>/dev/null | head -1)
UNCOMMITTED=$(cd "$ROOT" && git status --short 2>/dev/null | wc -l | tr -d ' ')
echo "[fable] 🌿 $BRANCH | 🏃 $SPRINT | ${COUNTS:-sem tasks }| 📝 $UNCOMMITTED uncommitted | log: ${LAST_LOG:-nenhum}"
exit 0
