#!/bin/bash
# accept-check.sh — porta de aceitação MECÂNICA do Estágio 7 (fail-closed).
# Roda os gates substantivos do harness e SÓ sai 0 se TODOS passarem. O INIT não
# pode declarar "concluído" sem este exit 0 — é o que impede shippar geração rasa
# SEM depender de o usuário lembrar de rodar /verificar-saude. Junto com o E3
# pre-commit (que exige o harness versionado — gate scripts-versionados), fecha o
# meta-furo "enforcement que só roda se invocado à mão".
set -u
ROOT="${2:-$(pwd)}"; [ "${1:-}" = "--root" ] && ROOT="$2"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc=0

run_gate() {  # nome · comando...
  local name="$1"; shift
  echo "── $name ──"
  if "$@"; then echo "   $name: OK"; else echo "   $name: FALHOU"; rc=1; fi
}

echo "== accept-check (Estágio 7 — fail-closed) =="
run_gate harness-lint     bash "$DIR/harness-lint.sh"     --root "$ROOT"
run_gate verify-artifacts bash "$DIR/verify-artifacts.sh" --root "$ROOT"

# E3 realmente wired? (o pre-commit que roda o lint a cada commit — backstop do clone)
if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  echo "── E3 ──"
  hp=$(git -C "$ROOT" config core.hooksPath 2>/dev/null || true)
  if [ -n "$hp" ]; then pc="$ROOT/$hp/pre-commit"; else pc="$ROOT/.git/hooks/pre-commit"; fi
  # (dev-store fix) hook manager (lefthook): o .git/hooks/pre-commit gerado é um wrapper
  # generico que so invoca `lefthook run pre-commit` em runtime — o comando real vive em
  # lefthook.yml, nao no wrapper. Reconhecer esse caso em vez de exigir grep no wrapper.
  lefthook_cfg=""
  for cand in "$ROOT/lefthook.yml" "$ROOT/lefthook.yaml" "$ROOT/.lefthook.yml" "$ROOT/.lefthook.yaml"; do
    [ -f "$cand" ] && lefthook_cfg="$cand" && break
  done
  if [ -f "$pc" ] && grep -q "accept-check" "$pc" 2>/dev/null; then
    echo "   E3 pre-commit: OK (roda accept-check — gate completo no commit)"
  elif [ -f "$pc" ] && grep -qi "lefthook" "$pc" 2>/dev/null && [ -n "$lefthook_cfg" ] && grep -q "accept-check" "$lefthook_cfg" 2>/dev/null; then
    echo "   E3 pre-commit: OK (lefthook wired -> $lefthook_cfg roda accept-check no pre-commit)"
  elif [ -f "$pc" ] && grep -q "harness-lint" "$pc" 2>/dev/null; then
    echo "   E3 pre-commit: FRACO — roda só harness-lint; o accept-check inteiro (audit do ledger +"
    echo "      verify-artifacts + roster) NÃO roda no commit. Aponte o pre-commit p/ accept-check.sh"
    echo "      (v9-fix S1: foi exatamente o furo do INIT do dev-store — harness quebrado entrou no repo)"; rc=1
  else
    echo "   E3 pre-commit: AUSENTE — nenhum gate roda no commit (Estágio 5 wiring incompleto)"; rc=1
  fi
fi

# (v9 M7) auditoria do ratchet por fase: o INIT so conclui com PROVA no ledger de que cada
# fase passou na mecanica E na semantica (verificador init-verify, inline). Torna a auto-invocacao
# do gate por fase mecanicamente EXIGIDA — sem o registro, accept-check reprova.
if [ -f "$DIR/validate-phase.sh" ]; then
  echo "── validacao-por-fase ──"
  if bash "$DIR/validate-phase.sh" --audit --root "$ROOT"; then
    echo "   validacao-por-fase: OK"
  else
    echo "   validacao-por-fase: FALHOU — ledger sem prova das 2 camadas por fase (init-verify nao rodou?)"; rc=1
  fi
fi

# (v9 F4.4) roster so e aceito no Estagio 7 como integrado (proposed/approved = INIT em aberto)
RO="$ROOT/.swarm/state/TEAM_ROSTER.yaml"
if [ -f "$RO" ]; then
  echo "── roster-status ──"
  if grep -qE '^[[:space:]]*status:[[:space:]]*integrated' "$RO"; then
    echo "   roster-status: OK (integrated)"
  else
    echo "   roster-status: FALHOU — TEAM_ROSTER sem 'status: integrated' (Estagio 7 exige; v9 F4.4)"; rc=1
  fi
fi

# (v9-fix S1) token de conclusão: SÓ o gate o cunha. Exit 0 grava .accept-ok com digest do
# harness; exit !=0 remove qualquer token velho. "INIT concluído" sem token fresco (digest batendo)
# é auto-atestado — mata o ledger all-PASS fabricado à mão do dev-store, onde o accept-check nunca
# rodou e o RESUME declarou sucesso assim mesmo.
TOK="$ROOT/.swarm/state/.accept-ok"
if [ "$rc" = "0" ]; then
  if command -v git >/dev/null 2>&1; then head=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo nogit); else head=nogit; fi
  sum=$( { cat "$ROOT"/.claude/agents/*.md "$ROOT/CLAUDE.md" "$ROOT/.swarm/state/TEAM_ROSTER.yaml" "$ROOT/.swarm/state/init-validation.jsonl"; } 2>/dev/null | { sha1sum 2>/dev/null || shasum 2>/dev/null; } | cut -c1-16)
  mkdir -p "$ROOT/.swarm/state" 2>/dev/null
  printf 'accept-ok ts=%s digest=%s head=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo now)" "${sum:-nohash}" "$head" > "$TOK" 2>/dev/null || true
else
  rm -f "$TOK" 2>/dev/null || true
fi

echo ""
if [ "$rc" = "0" ]; then
  echo "accept-check: PASS — INIT pode concluir (token .accept-ok cunhado)"
else
  echo "accept-check: FALHOU — INIT NÃO pode declarar concluído. Corrija e re-rode."
fi
exit $rc
