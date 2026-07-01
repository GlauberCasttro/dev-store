#!/usr/bin/env bash
# check-knowledge-jsonl.sh — gate E3 (pre-commit) de integridade do store de memória.
# Valida: cada linha é JSON válido · campos obrigatórios presentes · ids únicos.
# Fail-closed: id duplicado, json inválido ou campo faltante ⇒ exit 1 (bloqueia commit).
# Portável: não conhece prefixos nem nomes de projeto.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
KNOWLEDGE="${SWARM_MEMORY_FILE:-$REPO_ROOT/.swarm/knowledge/memory/conhecimento.jsonl}"

[ ! -f "$KNOWLEDGE" ] && exit 0   # store ainda não criado: nada a validar.

python3 - "$KNOWLEDGE" <<'PY'
import json, sys
path = sys.argv[1]
required = {"id", "text", "applies_to", "agent", "validated"}
ids, errors = [], []
with open(path, encoding="utf-8") as f:
    for n, raw in enumerate(f, 1):
        raw = raw.strip()
        if not raw:
            continue
        try:
            obj = json.loads(raw)
        except json.JSONDecodeError as e:
            errors.append(f"linha {n}: JSON inválido ({e})")
            continue
        missing = required - obj.keys()
        if missing:
            errors.append(f"linha {n} (id={obj.get('id','?')}): campos faltando {sorted(missing)}")
        if "id" in obj:
            ids.append(obj["id"])
dups = sorted({i for i in ids if ids.count(i) > 1})
if dups:
    errors.append(f"ids duplicados: {dups}")
if errors:
    print("ERRO em conhecimento.jsonl:")
    for e in errors:
        print("  -", e)
    sys.exit(1)
print(f"OK conhecimento.jsonl — {len(ids)} entradas, ids únicos.")
PY
