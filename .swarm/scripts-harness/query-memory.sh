#!/usr/bin/env bash
# query-memory.sh — busca entradas relevantes no store de memória por keywords.
# Portável (Fable v5): nada de nome de projeto nem prefixos de ID hardcoded.
# O filtro de relevância por papel usa o CAMPO `agent` da entrada
# (`shared` | <nome-do-agente-do-roster>), não prefixos de ID — assim funciona
# para qualquer roster derivado do scan, sem mapa fixo.
#
# Uso:   query-memory.sh "keywords da task" [agente]
#        agente: nome do agente do TEAM_ROSTER (ou "all" = sem filtro de papel)
# Saída: markdown com as entradas relevantes (text + detail), pronto para inline.
#
# Store:  .swarm/knowledge/memory/conhecimento.jsonl   (JSONL append-only)
# Env:    MEMORY_SCORE_MIN (default 1) · MEMORY_MAX_RESULTS (default 5)

set -euo pipefail

QUERY="${1:-}"
AGENT="${2:-all}"
REPO_ROOT="$(git -C "$(dirname "$0")/../.." rev-parse --show-toplevel 2>/dev/null || pwd)"
KNOWLEDGE="${SWARM_MEMORY_FILE:-$REPO_ROOT/.swarm/knowledge/memory/conhecimento.jsonl}"

SCORE_MIN="${MEMORY_SCORE_MIN:-1}"
MAX_RESULTS="${MEMORY_MAX_RESULTS:-5}"

[ ! -f "$KNOWLEDGE" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Modo ÍNDICE (v6, LLM-as-retriever): em vez de casar keyword, emite o índice
# COMPACTO (id · título · tags · agente) das lições candidatas. O tech-lead lê o
# índice e ESCOLHE por significado as relevantes — recuperação semântica sem
# vector DB. Só os ids escolhidos têm o detalhe puxado depois (query normal).
if [ "${MEMORY_MODE:-}" = "index" ]; then
  echo "## Índice de memória (escolha por significado as relevantes à task)"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    echo "$line" | jq -r --arg ag "$AGENT" '
      select((.validated // false)==true and (.superseded_by // "null")=="null")
      | select((.agent // "shared")=="shared" or (.agent // "shared")==$ag or $ag=="all")
      | "- [\(.id)] \(.text)  · tags: \((.applies_to // [])|join(", "))  · \(.agent // "shared")"' 2>/dev/null
  done < "$KNOWLEDGE"
  exit 0
fi

[ -z "$QUERY" ] && exit 0

# Query → palavras (lowercase), descartando termos genéricos e numéricos.
WORDS=$(echo "$QUERY" | tr '[:upper:]' '[:lower:]' | tr ' ,/-' '\n\n\n\n' \
  | grep -vE '^(task|sprint|module|modulo|[0-9]+|[a-z])$' | sort -u)

MATCHES=""
COUNT=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  [ "$COUNT" -ge "$MAX_RESULTS" ] && break

  parsed=$(echo "$line" | jq -r \
    '[.validated // false, .superseded_by // "null", .id, .text, .detail,
      (.applies_to | join("|")), (.agent // "shared"), (.score // 1)] | @tsv' 2>/dev/null) || continue
  [ -z "$parsed" ] && continue

  validated=$(echo "$parsed" | cut -f1)
  superseded=$(echo "$parsed" | cut -f2)
  id=$(echo "$parsed" | cut -f3)
  text=$(echo "$parsed" | cut -f4)
  detail=$(echo "$parsed" | cut -f5)
  applies_raw=$(echo "$parsed" | cut -f6 | tr '[:upper:]' '[:lower:]' | tr '|' '\n')
  entry_agent=$(echo "$parsed" | cut -f7)
  score=$(echo "$parsed" | cut -f8)

  [ "$validated" != "true" ] && continue
  [ "$superseded" != "null" ] && continue
  awk "BEGIN{exit !($score >= $SCORE_MIN)}" || continue

  # Filtro de papel: a entrada serve se for `shared` ou do agente consultado.
  if [ "$AGENT" != "all" ] && [ "$entry_agent" != "shared" ] && [ "$entry_agent" != "$AGENT" ]; then
    continue
  fi

  searchable=$(printf '%s\n%s\n%s' "$applies_raw" \
    "$(echo "$text" | tr '[:upper:]' '[:lower:]')" \
    "$(echo "$detail" | tr '[:upper:]' '[:lower:]')")
  matched=false
  for word in $WORDS; do
    [ ${#word} -lt 3 ] && continue
    if echo "$searchable" | grep -qF "$word"; then matched=true; break; fi
  done

  if [ "$matched" = "true" ]; then
    MATCHES="${MATCHES}- [${id}] ${text}\n  > ${detail}\n"
    COUNT=$((COUNT + 1))
  fi
done < "$KNOWLEDGE"

if [ -n "$MATCHES" ]; then
  echo "## Memória relevante (knowledge store)"
  echo ""
  printf "%b" "$MATCHES"
fi
exit 0
