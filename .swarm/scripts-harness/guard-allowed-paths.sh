#!/bin/bash
# guard-allowed-paths.sh — PreToolUse (Write|Edit). FAIL-CLOSED para SUBAGENTES:
# escrita só dentro do allowed_paths da task ativa (.swarm/state/.active-task.json,
# gravado por transition.py ao mover para DISPATCHED/IN_PROGRESS).
# O agente principal é ignorado (tratado pelo guard-zones.sh).
#
# Exit: 0=permite · 2=BLOQUEIA (Claude Code: 1 NÃO bloqueia). agent_type ausente
# = principal. Parse robusto: python3 (dep do harness) > jq; sem parser = fail-closed.
set -u
INPUT=$(cat)
[ "${SWARM_GUARD_OFF:-0}" = "1" ] && exit 0
ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
ACTIVE="$ROOT/.swarm/state/.active-task.json"

parse_input() {  # imprime FILE_PATH<TAB>AGENT_TYPE
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$INPUT" | python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: d={}
ti=d.get("tool_input") or {}
sys.stdout.write((ti.get("file_path") or ti.get("path") or "")+"\t"+(d.get("agent_type") or ""))'
  elif command -v jq >/dev/null 2>&1; then
    printf '%s' "$INPUT" | jq -r '[(.tool_input.file_path // .tool_input.path // ""), (.agent_type // "")] | @tsv'
  else
    return 1
  fi
}
parse_active() {  # linha1=task_id linha2=brief_path resto=allowed_paths
  [ -f "$ACTIVE" ] || { printf '\n\n'; return 0; }
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys,json
try: a=json.load(open(sys.argv[1]))
except Exception: a={}
print(a.get("task_id") or "")
print(a.get("brief_path") or "")
[print(p) for p in (a.get("allowed_paths") or [])]' "$ACTIVE"
  elif command -v jq >/dev/null 2>&1; then
    jq -r '(.task_id // ""), (.brief_path // ""), (.allowed_paths[]? // empty)' "$ACTIVE"
  else
    return 1
  fi
}

if ! PARSED=$(parse_input); then
  echo "X [fable] guard-allowed-paths sem python3 nem jq — BLOQUEANDO (fail-closed). Instale python3 (doctor.sh)." >&2
  exit 2
fi
FP="${PARSED%%	*}"; ATYPE="${PARSED#*	}"
[ -z "$FP" ] && exit 0
{ [ -z "$ATYPE" ]; } && exit 0                 # principal → guard-zones governa

# path fora do projeto não é responsabilidade do guard
case "$FP" in
  /*) case "$FP" in "$ROOT"/*) REL="${FP#"$ROOT"/}";; *) exit 0;; esac ;;
  *)  REL="${FP#./}" ;;
esac

ACT=$(parse_active) || { echo "X [fable] guard-allowed-paths sem parser p/ .active-task — BLOQUEANDO." >&2; exit 2; }
TASK_ID=$(printf '%s' "$ACT" | sed -n '1p')
BRIEF=$(printf '%s' "$ACT" | sed -n '2p'); BRIEF="${BRIEF#./}"
if [ -z "$TASK_ID" ]; then
  echo "X [fable E2] $ATYPE escrevendo sem task ativa. Tech-lead: transition.py --to DISPATCHED antes do despacho." >&2
  exit 2
fi

MATCH=0
[ -n "$BRIEF" ] && [ "$REL" = "$BRIEF" ] && MATCH=1
if [ "$MATCH" = "0" ]; then
  # `|| [ -n "$allowed" ]`: lê também a ÚLTIMA linha sem newline final (o command
  # substitution tira o \n do fim — sem isto o último allowed_path é ignorado;
  # bug pego pelo test-guards.sh contra o payload real).
  while IFS= read -r allowed || [ -n "$allowed" ]; do
    [ -z "$allowed" ] && continue
    # normalizar: tira ./ inicial, / final, e o SUFIXO LITERAL "/**" (não como
    # glob — `%/**` greedy comeria "/Api" de "src/Api" e casaria todo "src/").
    a="${allowed#./}"; a="${a%/}"; a="${a%/\*\*}"; a="${a%/}"
    if [ "$REL" = "$a" ] || [[ "$REL" == "$a/"* ]]; then MATCH=1; break; fi
  done < <(printf '%s\n' "$ACT" | tail -n +3)
fi

if [ "$MATCH" = "0" ]; then
  echo "X [fable E2] $ATYPE tentou escrever em '$REL' fora do allowed_paths (task $TASK_ID)." >&2
  echo "  Se o escopo real excede o brief: retorne PARTIAL — não contorne o guard." >&2
  exit 2
fi
exit 0
