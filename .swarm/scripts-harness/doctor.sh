#!/bin/bash
# doctor.sh — saúde do harness Fable + diagnóstico de degradação graciosa.
# Nunca trava o trabalho: reporta o que caiu de nível e como restaurar.
set -u
ROOT="${1:-$(pwd)}"
echo "== Fable doctor =="
W=0
need() { command -v "$1" >/dev/null 2>&1 && echo "  ok: $1" || { echo "  AUSENTE: $1 — $2"; W=1; }; }
need python3 "CRÍTICO: parser primário dos GUARDS + transition/validate — sem ele os guards FALHAM-FECHADO (bloqueiam tudo) e o estado vira manual"
need jq      "opcional — fallback dos guards; python3 é o primário (v5.2)"
need git     "sem trilha de commits — harness opera, mas sem auditoria"

# (v9 F5.2) tree_sitter e OPCIONAL no python3 RESOLVIDO: presente => repo-map em tree-sitter+pagerank;
# ausente => degrada para naive+pagerank (portavel, sem trava). Reporta qual python3 foi resolvido.
if python3 -c 'import importlib.util,sys; sys.exit(0 if importlib.util.find_spec("tree_sitter") else 1)' 2>/dev/null; then
  echo "  ok: tree_sitter disponivel ($(command -v python3)) — repo-map usa tree-sitter+pagerank"
else
  echo "  info: tree_sitter AUSENTE no $(command -v python3) — repo-map degrada para naive+pagerank (portavel)"
fi

# os guards realmente bloqueiam contra o payload real? (teste de campo v5.2)
if [ -x "$ROOT/.swarm/scripts-harness/test-guards.sh" ]; then
  if bash "$ROOT/.swarm/scripts-harness/test-guards.sh" >/dev/null 2>&1; then
    echo "  ok: guards bloqueiam/permitem certo contra o payload real (test-guards)"
  else
    echo "  FALHA: guards NÃO se comportam certo — rode .swarm/scripts-harness/test-guards.sh"; W=1
  fi
fi

[ -f "$ROOT/.swarm/state/CAPABILITY.yaml" ] && echo "  ok: CAPABILITY.yaml" || { echo "  AUSENTE: CAPABILITY.yaml — rode o Estágio 0"; W=1; }
[ -f "$ROOT/.swarm/state/ASSUMPTIONS.yaml" ] && echo "  ok: ASSUMPTIONS.yaml" || { echo "  AUSENTE: ASSUMPTIONS.yaml — anti-padrão 8"; W=1; }

ACTIVE="$ROOT/.swarm/state/.active-task.json"
if [ -f "$ACTIVE" ]; then
  echo "  atenção: task ativa pendente ($(command -v jq >/dev/null && jq -r '.task_id' "$ACTIVE" || echo '?')) — sessão anterior caiu no meio? Verifique o brief antes de despachar outra."
fi

# pre-commit instalado?
if [ -d "$ROOT/.git" ]; then
  HP=$(git -C "$ROOT" config core.hooksPath 2>/dev/null || true)
  if [ -n "$HP" ] || [ -f "$ROOT/lefthook.yml" ] || [ -f "$ROOT/.husky/pre-commit" ] || [ -f "$ROOT/.pre-commit-config.yaml" ]; then
    echo "  ok: gate E3 (pre-commit) presente"
  else
    echo "  AUSENTE: gate E3 — lint/validate não rodam no commit. Instale lefthook/husky ou core.hooksPath"; W=1
  fi
fi

[ "$W" = "0" ] && echo "Tudo no nível pleno." || echo "Degradações acima — o harness segue operável; restaure quando puder."
exit 0
