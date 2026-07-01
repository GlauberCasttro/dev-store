#!/bin/bash
# validate-phase.sh (v9 M7) — gate MECANICO por fase do INIT (ratchet).
# Cada fase do pipeline ganha um portao executavel: nao avanca com a anterior vermelha.
# Substitui o DoD em prosa (auto-report do LLM — exatamente o que o Fable desconfia) por
# verificacao mecanica do que JA e checavel ate aquela fase. Reusa validate-state /
# harness-lint / accept-check. A porta agregadora final continua sendo o accept-check (fase 7).
#
# ESTA E A CAMADA MECANICA. A camada SEMANTICA (o defeito "bem-formado mas errado") e a
# VERIFICADOR init-verify (subagente LLM isolado, despachado INLINE pela v9 — nao skill separada;
# verificador LLM isolado/cetico, dispatch INIT-time. Gate da fase = mecanica (este script) PASS
# rubrica em references/init-verifier.md). Gate da fase = mecanica *E* semantica (init-verify) PASS.
#
# Uso: validate-phase.sh <0|1|2|2b|2c|3|4|5|6|7> [--root R]
set -u
STAGE="${1:-}"; shift 2>/dev/null || true
ROOT="."
while [ "$#" -gt 0 ]; do
  case "$1" in --root) ROOT="${2:-.}"; shift 2;; --root=*) ROOT="${1#--root=}"; shift;; *) shift;; esac
done
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" 2>/dev/null || { echo "validate-phase: root inexistente: $ROOT" >&2; exit 2; }
rc=0
miss(){ echo "  FALTA $1"; rc=1; }
okp(){ echo "  ok   $1"; }
have(){ [ -e "$1" ] && okp "presente: $1" || miss "$1 (esperado ao fim da fase $STAGE)"; }
vstate(){ command -v python3 >/dev/null 2>&1 && { _FABLE_LIB="$DIR" python3 "$DIR/validate-state.py" . || rc=1; }; }
lint(){ command -v python3 >/dev/null 2>&1 && { bash "$DIR/harness-lint.sh" --root . || rc=1; }; }
LEDGER=".swarm/state/init-validation.jsonl"

# --audit (chamado pelo accept-check / Estagio 7): exige PROVA no ledger de que CADA fase
# passou nas DUAS camadas — mecanica (este script) E semantica (verificador init-verify). Sem o
# registro, o INIT nao conclui. E o que torna a auto-invocacao do gate por fase MECANICAMENTE
# EXIGIDA, nao confiada ao "o agente lembrou de validar".
if [ "$STAGE" = "--audit" ]; then
  command -v python3 >/dev/null 2>&1 || { echo "validate-phase --audit: sem python3 (fail-closed)"; exit 1; }
  python3 - "$LEDGER" <<'PY'
import json, os, sys
led = sys.argv[1]
if not os.path.isfile(led):
    print("AUDIT FAIL: ledger ausente (.swarm/state/init-validation.jsonl) — gate por fase nunca rodou"); sys.exit(1)
seen = {}
for ln in open(led, encoding="utf-8", errors="replace"):
    ln = ln.strip()
    if not ln: continue
    try: d = json.loads(ln)
    except Exception: continue
    seen[(str(d.get("phase")), d.get("layer"))] = d
bad = 0
# required: fases ANTERIORES (0-6) nas 2 camadas + fase 7 SO na semantica.
# (v9-fix S7) fase 7/mecanica = o proprio resultado deste accept-check em execucao — nao pode
# ser pre-condicao de si mesma (auto-referencia sem ponto fixo: accept-check chama este audit,
# que exigiria fase-7/mecanica ja PASS antes do accept-check corrente ter terminado de rodar).
# A camada semantica da fase 7 e uma revisao independente (init-verify), essa sim auditavel aqui.
required = [(ph, layer) for ph in ("0", "1", "2", "2b", "2c", "3", "4", "5", "6") for layer in ("mechanical", "semantic")]
required.append(("7", "semantic"))
for ph, layer in required:
        e = seen.get((ph, layer))
        v = (e or {}).get("verdict")
        if v != "PASS":
            print(f"AUDIT FAIL: fase {ph}/{layer}: {v or 'ausente'} — validacao por fase incompleta (auto-invocacao do init-verify nao comprovada)")
            bad = 1; continue
        if layer == "semantic":
            proof = str((e.get("proof") or e.get("evidence") or "")).strip()
            if not proof:
                print(f"AUDIT FAIL: fase {ph}/semantic: PASS sem 'proof' — veredito semantico sem evidencia e shallow (=FAIL); ledger fabricado? (v9-fix S1)")
                bad = 1
print("validate-phase --audit: OK — todas as fases validadas nas 2 camadas (semantico com prova)" if not bad else "validate-phase --audit: FALHOU")
sys.exit(bad)
PY
  exit $?
fi

echo "== validate-phase $STAGE (root=$(pwd)) =="
case "$STAGE" in
  0|probe)
    have .swarm/state/CAPABILITY.yaml; vstate ;;
  1|scan)
    have .swarm/state/PROJECT_PROFILE.yaml
    have .swarm/knowledge/graph.json
    have .swarm/knowledge/ORCHESTRATION_MAP.yaml
    vstate
    if [ -f .swarm/knowledge/ORCHESTRATION_MAP.yaml ]; then
      if grep -nE '\((inferido|assumido|inferred|assumed)\)' .swarm/knowledge/ORCHESTRATION_MAP.yaml >/dev/null 2>&1; then
        echo "  FALHA ORCHESTRATION_MAP com marcador (inferido)/(assumido) — fluxo nao lido de ancora real"; rc=1
      else okp "ORCHESTRATION_MAP sem marcador inferido"; fi
    fi ;;
  2|derive)
    have .swarm/state/TEAM_ROSTER.yaml; vstate ;;
  2b|specialize)
    have .swarm/state/STACK_PROFILE.yaml; vstate ;;
  2c|interview)
    have .swarm/knowledge/DOMAIN_INVARIANTS.yaml; vstate
    if [ -f .swarm/knowledge/DOMAIN_INVARIANTS.yaml ] && ! grep -qE '^\s*source\s*:' .swarm/knowledge/DOMAIN_INVARIANTS.yaml; then
      echo "  FALHA DOMAIN_INVARIANTS sem 'source:' (scan|founder|generic-default)"; rc=1; fi ;;
  3|compose)
    vstate
    if ! grep -qE '^\s*status:\s*(approved|integrated)' .swarm/state/TEAM_ROSTER.yaml 2>/dev/null; then
      echo "  FALHA TEAM_ROSTER sem 'status: approved' — Estagio 3 exige aprovacao humana"; rc=1
    else okp "TEAM_ROSTER approved/integrated"; fi ;;
  4|generate)
    lint ;;                       # kernel+agentes+mapa+grafo ja existem: harness-lint completo
  5|enforce)
    lint
    [ -f .swarm/scripts-harness/zones.conf ] && okp "zones.conf gerado (gen-zones)" || miss ".swarm/scripts-harness/zones.conf (rode gen-zones.py --write)" ;;
  6|bootstrap)
    lint
    [ -d .swarm/state/sprints ] && okp ".swarm/state/sprints presente (smoke)" || miss ".swarm/state/sprints (smoke dispatch nao rodou)" ;;
  7|accept)
    bash "$DIR/accept-check.sh" --root . || rc=1 ;;
  *)
    echo "uso: validate-phase.sh <0|1|2|2b|2c|3|4|5|6|7> [--root R]" >&2; exit 2 ;;
esac
# registra o veredito MECANICO desta fase no ledger (o verificador init-verify anexa o SEMANTICO).
mkdir -p .swarm/state 2>/dev/null && printf '{"phase":"%s","layer":"mechanical","verdict":"%s","at":"%s"}\n' \
  "$STAGE" "$([ "$rc" = 0 ] && echo PASS || echo FAIL)" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo now)" >> "$LEDGER" 2>/dev/null || true
[ "$rc" = 0 ] && echo "validate-phase $STAGE: PASS" || echo "validate-phase $STAGE: FALHOU — corrija ANTES de avancar de fase"
exit $rc
