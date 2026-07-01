#!/bin/bash
# test-guards.sh — roda os guards contra o PAYLOAD REAL do PreToolUse do Claude
# Code e AFIRMA os exit codes. É o teste negativo do Estágio 5, EXECUTÁVEL — não
# prosa. Lição de campo (v5.2): guard escrito por suposição falha calado; o bug do
# exit code e o do fail-open só aparecem rodando contra o JSON real. Este teste é o
# que prova que o guard bloqueia. Rode no Estágio 5 e no pre-commit do harness.
set -u
HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJ=$(mktemp -d)
export CLAUDE_PROJECT_DIR="$PROJ"
mkdir -p "$PROJ/.swarm/state"
FAILS=0
pass(){ echo "  ok  $1"; }
fail(){ echo "  XX  $1 (esperado $2, veio $3)"; FAILS=$((FAILS+1)); }
check(){ [ "$3" = "$2" ] && pass "$1" || fail "$1" "$2" "$3"; }

# payload FILE_PATH [AGENT_TYPE] — estrutura REAL: file_path em .tool_input
payload(){ python3 -c 'import json,sys
d={"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":"x"}}
if len(sys.argv)>2 and sys.argv[2]: d["agent_type"]=sys.argv[2]
print(json.dumps(d))' "$@"; }

run(){ local guard="$1" json="$2"; shift 2
  printf '%s' "$json" | env "$@" bash "$HOOKS_DIR/$guard" >/dev/null 2>&1; echo $?; }

echo "guard-zones (exit 2 = bloqueia):"
check "main → produto: BLOQUEIA"        2 "$(run guard-zones.sh "$(payload "$PROJ/src/Foo.cs")")"
check "main → estado: permite"          0 "$(run guard-zones.sh "$(payload "$PROJ/.swarm/state/x.json")")"
check "main → harness s/ maint: BLOQUEIA" 2 "$(run guard-zones.sh "$(payload "$PROJ/.claude/agents/dev.md")")"
check "subagente → produto: ignora"     0 "$(run guard-zones.sh "$(payload "$PROJ/src/Foo.cs" dev-api)")"
check "fora do projeto: permite"        0 "$(run guard-zones.sh "$(payload "/Users/x/.claude/memory.md")")"

echo "protect-harness:"
check "agente s/ maint: BLOQUEIA"       2 "$(run protect-harness.sh "$(payload "$PROJ/.claude/agents/dev.md")")"
check "agente c/ maint: permite"        0 "$(run protect-harness.sh "$(payload "$PROJ/.claude/agents/dev.md")" SWARM_MAINT=1)"
check "produto (não-harness): permite"  0 "$(run protect-harness.sh "$(payload "$PROJ/src/Foo.cs")")"

echo "guard-allowed-paths:"
rm -f "$PROJ/.swarm/state/.active-task.json"
check "subagente sem task ativa: BLOQUEIA" 2 "$(run guard-allowed-paths.sh "$(payload "$PROJ/src/Api/X.cs" dev-api)")"
cat > "$PROJ/.swarm/state/.active-task.json" <<'EOF'
{"task_id":"TASK-1","agent":"dev-api","allowed_paths":["src/Api/"],"brief_path":".swarm/state/sprints/S/tasks/TASK-1.json"}
EOF
check "dentro do allowed: permite"      0 "$(run guard-allowed-paths.sh "$(payload "$PROJ/src/Api/X.cs" dev-api)")"
check "fora do allowed: BLOQUEIA"       2 "$(run guard-allowed-paths.sh "$(payload "$PROJ/src/Domain/Y.cs" dev-api)")"
check "grava o próprio brief: permite"  0 "$(run guard-allowed-paths.sh "$(payload "$PROJ/.swarm/state/sprints/S/tasks/TASK-1.json" dev-api)")"
check "principal (sem agent_type): ignora" 0 "$(run guard-allowed-paths.sh "$(payload "$PROJ/src/Api/X.cs")")"

rm -rf "$PROJ"
echo
[ "$FAILS" = "0" ] && { echo "test-guards: OK — guards bloqueiam/permitem certo contra o payload real do Claude Code"; exit 0; }
echo "test-guards: $FAILS FALHA(S)"; exit 1
