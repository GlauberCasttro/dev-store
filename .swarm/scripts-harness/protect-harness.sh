#!/bin/bash
# protect-harness.sh — PreToolUse (Write|Edit). Roster e harness imutáveis em runtime:
# agentes, hooks, kernel e core do harness só mudam em modo manutenção (SWARM_MAINT=1),
# para QUALQUER ator (main ou subagente).
#
# Exit: 0=permite · 2=BLOQUEIA (Claude Code: 1 NÃO bloqueia). Parse: python3 > jq;
# sem parser = fail-closed. file_path vive em .tool_input.file_path. Path fora do
# projeto = exit 0 (não é responsabilidade do guard).
set -u
INPUT=$(cat)
[ "${SWARM_GUARD_OFF:-0}" = "1" ] && exit 0
[ "${SWARM_MAINT:-0}" = "1" ] && exit 0
ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

parse_fp() {
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$INPUT" | python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: d={}
ti=d.get("tool_input") or {}
sys.stdout.write(ti.get("file_path") or ti.get("path") or "")'
  elif command -v jq >/dev/null 2>&1; then
    printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""'
  else
    return 1
  fi
}
if ! FP=$(parse_fp); then
  echo "X [fable] protect-harness sem python3 nem jq — BLOQUEANDO (fail-closed). Instale python3 (doctor.sh)." >&2
  exit 2
fi
[ -z "$FP" ] && exit 0

case "$FP" in
  /*) case "$FP" in "$ROOT"/*) REL="${FP#"$ROOT"/}";; *) exit 0;; esac ;;
  *)  REL="${FP#./}" ;;
esac

case "$REL" in
  .claude/agents/*|.cursor/agents/*|agents/*.md|.claude/hooks/*|.swarm/scripts-harness/*|CLAUDE.md|AGENTS.md|.cursor/rules/swarm-kernel.mdc)
    echo "X [fable E2] '$REL' é harness — imutável em runtime. Mudança exige SWARM_MAINT=1 aprovado pelo usuário, com diff revisável." >&2
    exit 2 ;;
esac
exit 0
