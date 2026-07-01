#!/bin/bash
# cursor-guard-edit.sh — Cursor hook: afterFileEdit (E2~ pós-hoc).
# afterFileEdit é OBSERVACIONAL — não bloqueia pré-fato (o Cursor não tem
# beforeFileEdit). Garante imutabilidade de harness REVERTENDO (git checkout) o
# que foi editado fora de SWARM_MAINT, e avisa o agente. Para zonas de PRODUTO
# pelo agente principal não há prevenção limpa — o verifier (scope_check) cobre.
# LIMITAÇÃO conhecida (confiança média): há indício de que afterFileEdit dispara
# só para edições de Tab/inline; se não disparar para o agente, esta camada
# degrada e o verifier assume integralmente. Confirmar no Estágio 0 (probe).
# Ver knowledge/cursor-2026-capabilities.md.
set -u
INPUT=$(cat)
[ "${SWARM_GUARD_OFF:-0}" = "1" ] && exit 0
[ "${SWARM_MAINT:-0}" = "1" ] && exit 0
ROOT="${CURSOR_PROJECT_DIR:-${CURSOR_WORKSPACE_ROOT:-$(pwd)}}"
command -v python3 >/dev/null 2>&1 || exit 0

FP=$(printf '%s' "$INPUT" | python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: d={}
print(d.get("file_path") or d.get("filePath") or d.get("path") or "")')
[ -z "$FP" ] && exit 0

case "$FP" in
  /*) case "$FP" in "$ROOT"/*) REL="${FP#"$ROOT"/}";; *) exit 0;; esac ;;
  *)  REL="${FP#./}" ;;
esac

case "$REL" in
  .cursor/agents/*|.cursor/rules/swarm-kernel.mdc|.cursor/skills/*|.cursor/hooks/*|.cursor/hooks.json|.swarm/scripts-harness/*|AGENTS.md)
    if git -C "$ROOT" rev-parse >/dev/null 2>&1 && git -C "$ROOT" cat-file -e "HEAD:$REL" 2>/dev/null; then
      if git -C "$ROOT" checkout -- "$REL" 2>/dev/null; then
        printf '{"agent_message":"fable E2: %s é harness e foi REVERTIDO (imutável em runtime). Use SWARM_MAINT=1 para manutenção."}\n' "$REL"
        exit 0
      fi
    fi
    printf '{"agent_message":"fable: %s é harness — não altere em runtime (SWARM_MAINT=1 para manutenção, com diff revisável)."}\n' "$REL"
    exit 0 ;;
esac
exit 0
