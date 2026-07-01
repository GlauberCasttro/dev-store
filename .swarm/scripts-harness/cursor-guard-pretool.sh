#!/bin/bash
# cursor-guard-pretool.sh — Cursor hook: preToolUse (E2, PRÉ-bloqueio real).
# preToolUse dispara ANTES de TODA tool e PODE bloquear (doc oficial Cursor).
# Payload: {tool_name, tool_input{...}}; saída {"permission":"allow"|"deny",...}.
# Porta guard-zones + guard-allowed-paths + protect-harness para o Cursor e bloqueia
# delegação aninhada durante task ativa (política Fable ADR-F1).
#
# IDENTIDADE do ator (main vs subagent): o payload do preToolUse pode não expor.
# Aproximação fiel ao harness via .swarm/state/.active-task.json (gravado pelo
# transition.py em DISPATCHED): task ativa ⇒ enforce allowed_paths; sem task ativa
# ⇒ é o main, bloqueia zona de produto. Confirmar nomes de campo do payload no
# Estágio 0 (probe). Ver knowledge/cursor-2026-capabilities.md.
# Diagnóstico: SWARM_GUARD_OFF=1 · Manutenção: SWARM_MAINT=1.
set -u
INPUT=$(cat)
allow(){ echo '{"permission":"allow"}'; exit 0; }
deny(){ printf '{"permission":"deny","user_message":%s,"agent_message":%s}\n' "$1" "$2"; exit 0; }
[ "${SWARM_GUARD_OFF:-0}" = "1" ] && allow
command -v python3 >/dev/null 2>&1 || deny '"fable: guard-pretool sem python3 (fail-closed)"' '"Instale python3 (doctor.sh)."'

PARSED=$(printf '%s' "$INPUT" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
except Exception:
    sys.exit(10)
roots=d.get("workspace_roots") if isinstance(d.get("workspace_roots"),list) else []
root=(__import__("os").environ.get("CURSOR_PROJECT_DIR")
      or __import__("os").environ.get("CURSOR_WORKSPACE_ROOT")
      or (roots[0] if roots else "")
      or d.get("cwd") or __import__("os").getcwd())
t=d.get("tool_name") or d.get("toolName") or ""
ti=d.get("tool_input") or d.get("toolInput") or {}
if isinstance(ti,str):
    try: ti=json.loads(ti)
    except Exception: ti={}
fp=ti.get("file_path") or ti.get("path") or ti.get("target_file") or ti.get("filePath") or ti.get("relative_workspace_path") or ""
sys.stdout.write(root+"\t"+t+"\t"+fp)')
case "$?" in
  10) deny '"fable E2: payload preToolUse invalido"' '"Hook recebeu JSON invalido; acao bloqueada fail-closed. Confirme o contrato do Cursor no Estagio 0."' ;;
esac
ROOT=$(printf '%s' "$PARSED" | cut -f1)
TOOL=$(printf '%s' "$PARSED" | cut -f2)
FP=$(printf '%s' "$PARSED" | cut -f3-)
ACTIVE="$ROOT/.swarm/state/.active-task.json"

TOOL_LC="$(printf '%s' "$TOOL" | tr 'A-Z' 'a-z')"

# Cursor dispara preToolUse para Task/subagent. Com task ativa, qualquer nova
# delegação é nested delegation e viola ADR-F1.
case "$TOOL_LC" in
  task|*task*|*subagent*|*agent*)
    if [ -f "$ACTIVE" ]; then
      deny '"fable E2: delegacao aninhada bloqueada"' '"Subagente nao aciona outro agente. Retorne PARTIAL ao tech-lead com o que precisa ser delegado."'
    fi
    allow ;;
esac

# Só tools de ESCRITA de arquivo interessam; o resto (read, shell, etc.) passa.
case "$TOOL_LC" in
  *edit*|*write*|*create*file*|*search*replace*|*apply*|*delete*file*) : ;;
  *) allow ;;
esac
[ -z "$FP" ] && deny '"fable E2: tool de escrita sem path reconhecido"' '"Payload de escrita sem file_path/path/target_file; bloqueado fail-closed. Atualize o guard se o Cursor mudou o schema."'

case "$FP" in
  /*) case "$FP" in "$ROOT"/*) REL="${FP#"$ROOT"/}";; *) allow;; esac ;;
  *)  REL="${FP#./}" ;;
esac

# 1) Harness imutável (qualquer ator) sem manutenção.
if [ "${SWARM_MAINT:-0}" != "1" ]; then
  case "$REL" in
    .cursor/agents/*|.cursor/rules/*|.cursor/skills/*|.cursor/hooks/*|.cursor/hooks.json|.swarm/scripts-harness/*|.swarm/core-spec.md|AGENTS.md)
      deny '"fable E2: harness imutável em runtime"' '"Edição de harness exige SWARM_MAINT=1 (aprovado), com diff revisável."' ;;
  esac
fi

# 2) Estado/logs/archive: superficie livre (operacional; transition.py governa).
case "$REL" in .swarm/state/*|.swarm/logs/*|.swarm/archive/*) allow;; esac

# 2b) (v9 F3.3) .swarm/knowledge POR PAPEL. Sem task = main/tech-lead persiste. Com task,
#     o ator e o subagente do brief: dev/qa nao escrevem knowledge global; architect so ADR;
#     curator so memory; verifier nada. Papel vem do .active-task.json (campo agent).
case "$REL" in
  .swarm/knowledge/*)
    [ -f "$ACTIVE" ] || allow
    AG=$(python3 -c 'import sys,json
try: print((json.load(open(sys.argv[1])) or {}).get("agent") or "")
except Exception: print("")' "$ACTIVE")
    case "$AG" in
      architect*) case "$REL" in .swarm/knowledge/ADR/*) allow;; *) deny '"fable E2: architect escreve so ADR"' "\"architect escreve apenas .swarm/knowledge/ADR/. '$REL' fora disso.\"";; esac ;;
      curator*)   case "$REL" in .swarm/knowledge/memory/*) allow;; *) deny '"fable E2: curator escreve so memoria"' "\"curator escreve apenas .swarm/knowledge/memory/. '$REL' fora disso.\"";; esac ;;
      verifier*)  deny '"fable E2: verifier e readonly"' '"verifier nao escreve arquivos — emite gate_report pelo fluxo."' ;;
      dev-*|qa-*) deny '"fable E2: dev/qa nao escrevem knowledge global"' "\"'$REL' e conhecimento global. Produto vai em allowed_paths; licao recorrente vira proposta ao curator, nao escrita direta.\"" ;;
      *) allow ;;
    esac ;;
esac

# 3) Produto: zonas (sem task) ou allowed_paths (com task ativa).
# (v9 F3.2) zones.conf gerado do PROJECT_PROFILE e a fonte PRIMARIA; regex fixa = fallback unico.
PRODUCT_RE='^(src|app|lib|frontend|backend|tests?|pkg|internal|cmd|packages|components|pages|server|client)/'
CONF="$ROOT/.swarm/scripts-harness/zones.conf"
[ -f "$CONF" ] && . "$CONF"
if [ -f "$ACTIVE" ]; then
  ACT=$(python3 -c 'import sys,json
try: a=json.load(open(sys.argv[1]))
except Exception: a={}
print(a.get("task_id") or "")
[print(p) for p in (a.get("allowed_paths") or [])]' "$ACTIVE")
  TASK=$(printf '%s' "$ACT" | sed -n '1p')
  inscope=0
  while IFS= read -r a || [ -n "$a" ]; do
    [ -z "$a" ] && continue
    a="${a#./}"; a="${a%/}"; a="${a%/\*\*}"; a="${a%/}"
    if [ "$REL" = "$a" ] || [[ "$REL" == "$a/"* ]]; then inscope=1; break; fi
  done < <(printf '%s\n' "$ACT" | tail -n +2)
  if [ "$inscope" = "0" ] && printf '%s' "$REL" | grep -Eq "$PRODUCT_RE"; then
    deny '"fable E2: escrita fora do allowed_paths"' "\"'$REL' fora do escopo da task $TASK. Se o escopo excede o brief, retorne PARTIAL — não contorne o guard.\""
  fi
else
  if printf '%s' "$REL" | grep -Eq "$PRODUCT_RE"; then
    deny '"fable E2: tech-lead (main) nao escreve produto"' "\"'$REL' e produto. Despache o especialista por /<nome> apos o brief.\""
  fi
fi
allow
