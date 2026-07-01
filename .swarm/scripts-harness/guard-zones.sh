#!/bin/bash
# guard-zones.sh — PreToolUse (Write|Edit). Três zonas para o AGENTE PRINCIPAL.
#   produto -> main SEMPRE bloqueado (delega ao especialista)
#   estado  -> liberado
#   harness -> só com SWARM_MAINT=1
# Subagentes são tratados pelo guard-allowed-paths.sh (este guard os ignora).
# Config: .swarm/scripts-harness/zones.conf (gerado no Estágio 5 a partir do PROJECT_PROFILE)
# Escape de diagnóstico: SWARM_GUARD_OFF=1
#
# Semântica de exit (Claude Code, confirmada na doc): 0=permite · 2=BLOQUEIA
# (stderr volta ao modelo) · 1/outros=erro NÃO-bloqueante (a escrita passa!).
# Bloqueio é SEMPRE exit 2. Campo de subagente: `agent_type` presente=subagente,
# ausente=principal (doc oficial dos hooks).
set -u
INPUT=$(cat)
[ "${SWARM_GUARD_OFF:-0}" = "1" ] && exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CONF="$ROOT/.swarm/scripts-harness/zones.conf"
if [ -f "$CONF" ]; then . "$CONF"; else
  PRODUCT_GLOBS="src/*|app/*|lib/*|frontend/*|backend/*|tests/*|test/*|pkg/*|internal/*|cmd/*|packages/*|components/*|pages/*|server/*|client/*"
  STATE_GLOBS=".swarm/state/*|.swarm/logs/*|.swarm/knowledge/*|.swarm/archive/*"
  HARNESS_GLOBS=".claude/*|.cursor/*|.swarm/scripts-harness/*|CLAUDE.md|AGENTS.md|Makefile"
fi

# Parse robusto do stdin: python3 (dep do harness, sempre presente) > jq.
# Sem NENHUM parser ⇒ fail-closed (exit 2): um guard que não lê seu input não
# pode garantir segurança — bloqueia e avisa, NUNCA libera em silêncio (era o
# fail-open que tornava o guard teatro). Instale python3 (doctor.sh confere).
parse_input() {
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
if ! PARSED=$(parse_input); then
  echo "X [fable] guard-zones sem python3 nem jq — não consigo ler o file_path; BLOQUEANDO (fail-closed). Instale python3 ou rode .swarm/scripts-harness/doctor.sh. Diagnóstico: SWARM_GUARD_OFF=1." >&2
  exit 2
fi
FP="${PARSED%%	*}"; ATYPE="${PARSED#*	}"
[ -z "$FP" ] && exit 0                       # tool sem file_path (Bash etc.)
[ -n "$ATYPE" ] && exit 0                     # subagente → guard-allowed-paths governa

# Resolver REL; path fora do projeto NÃO é responsabilidade deste guard (exit 0).
case "$FP" in
  /*) case "$FP" in "$ROOT"/*) REL="${FP#"$ROOT"/}";; *) exit 0;; esac ;;
  *)  REL="${FP#./}" ;;
esac

match_any() { local p; IFS='|' read -ra PATS <<< "$1"; for p in "${PATS[@]}"; do
  case "$REL" in $p|${p%/\*}/*) return 0;; esac; done; return 1; }

if match_any "$STATE_GLOBS";   then exit 0; fi
if match_any "$PRODUCT_GLOBS"; then
  echo "X [fable E2] tech-lead não escreve produto ($REL). Despache o especialista via delegação." >&2
  exit 2
fi
if match_any "$HARNESS_GLOBS" && [ "${SWARM_MAINT:-0}" != "1" ]; then
  echo "X [fable E2] alteração de harness ($REL) exige modo manutenção (SWARM_MAINT=1, aprovado pelo usuário)." >&2
  exit 2
fi
exit 0
