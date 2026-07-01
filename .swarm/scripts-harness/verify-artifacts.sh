#!/bin/bash
# verify-artifacts.sh - V6.4 content sentinels ported to Fable v7.
# Runs against a GENERATED harness, not this skill package.
set -u

ROOT="."
DOCS_ONLY=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    --root=*) ROOT="${1#--root=}"; shift ;;
    --docs-only) DOCS_ONLY=1; shift ;;
    -h|--help)
      echo "usage: verify-artifacts.sh [--root DIR] [--docs-only]"
      exit 0
      ;;
    *)
      echo "verify-artifacts: unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

[ -n "$ROOT" ] || { echo "verify-artifacts: --root vazio" >&2; exit 2; }
cd "$ROOT" 2>/dev/null || { echo "verify-artifacts: root inexistente: $ROOT" >&2; exit 2; }

FAIL=0
WARN=0
err(){ echo "FAIL $1"; FAIL=1; }
warn(){ echo "WARN $1"; WARN=1; }
ok(){ echo "ok   $1"; }

first_existing(){
  for p in "$@"; do
    [ -e "$p" ] && { printf '%s\n' "$p"; return 0; }
  done
  return 1
}

strip_frontmatter_nonempty_lines(){
  awk '
    BEGIN {fm=0; body=1}
    NR==1 && $0=="---" {fm=1; body=0; next}
    fm && $0=="---" {fm=0; body=1; next}
    body && $0 !~ /^[[:space:]]*$/ {c++}
    END {print c+0}
  ' "$1"
}

has_placeholder(){
  # v9/F4.1: pega placeholder MAIUSCULO ({PROJETO},{N}) tambem; o guard (inicio|nao-cifrao)
  # antes da chave evita falso-positivo em variaveis de shell tipo ${ROOT} nos hooks .cursor/.claude.
  # (dev-store fix): restrito a MAIUSCULO/hifen no single-brace — a versao case-insensitive
  # dava falso-positivo em sintaxe de rota real do projeto (`products/{id}`, `/voucher/{code}`)
  # e em prosa que CITA o anti-padrao (`{chave}` como exemplo do que NUNCA usar). Placeholder
  # residual real do framework e sempre MAIUSCULO ({PROJETO},{N},{FEATURE-ID}); duplo-chave
  # continua sem essa restricao.
  grep -RE '\{\{[^}]+\}\}|(^|[^$])\{[A-Z_][A-Z0-9_-]*\}|← DINÂMICO' "$@" >/dev/null 2>&1
}

check_docs(){
  local swarm diagram heads mermaids chars i
  swarm=$(first_existing SWARM.md .swarm/SWARM.md || true)
  diagram=".swarm/knowledge/SWARM_DIAGRAM.md"

  [ -n "$swarm" ] || err "SWARM.md ausente"
  [ -f "$diagram" ] || err "$diagram ausente"
  [ -f "$diagram" ] || return

  heads=$(grep -Ec '^## +[1-8]\.' "$diagram" || true)
  [ "$heads" = "8" ] || err "$diagram: esperado 8 secoes numeradas, veio $heads"
  for i in 1 2 3 4 5 6 7 8; do
    grep -Eq "^## +$i\\." "$diagram" || err "$diagram: secao ## $i. ausente"
  done

  mermaids=$(grep -Ec '^```mermaid[[:space:]]*$' "$diagram" || true)
  [ "$mermaids" = "8" ] || err "$diagram: esperado 8 blocos mermaid, veio $mermaids"

  chars=$(wc -c < "$diagram" | tr -d ' ')
  [ "$chars" -ge 3500 ] || err "$diagram: conteudo pobre (<3500 chars, veio $chars)"

  has_placeholder "$diagram" && err "$diagram: placeholder nao-resolvido"
  if [ -n "$swarm" ]; then
    grep -q 'SWARM_DIAGRAM.md' "$swarm" || err "$swarm: nao linka SWARM_DIAGRAM.md"
    grep -q 'SWARM.md' "$diagram" || err "$diagram: nao linka de volta para SWARM.md"
  fi

  # D1 — guia de uso operacional (restaurado do v6.4: fluxo por tipo de demanda)
  local usage uheads
  usage=$(first_existing HARNESS_USAGE.md .swarm/HARNESS_USAGE.md docs/HARNESS_USAGE.md || true)
  if [ -z "$usage" ]; then
    err "HARNESS_USAGE.md ausente — guia de uso operacional (fluxo por demanda) nao gerado (D1)"
  else
    uheads=$(grep -Ec '^## +' "$usage" || true)
    [ "$uheads" -ge 4 ] || err "$usage: guia de uso raso (<4 secoes de fluxo; veio $uheads)"
    chars=$(wc -c < "$usage" | tr -d ' ')
    [ "$chars" -ge 1500 ] || err "$usage: guia de uso pobre (<1500 chars)"
    grep -qiE 'demanda|nova feature|corre|retomar|despach' "$usage" \
      || err "$usage: sem fluxo por tipo de demanda (D1)"
    has_placeholder "$usage" && err "$usage: placeholder nao-resolvido"
  fi
}

check_kernel(){
  local kernel lines
  kernel=$(first_existing AGENTS.md .cursor/rules/swarm-kernel.mdc CLAUDE.md || true)
  [ -n "$kernel" ] || { err "kernel ausente (AGENTS.md/.cursor/rules/swarm-kernel.mdc/CLAUDE.md)"; return; }
  lines=$(wc -l < "$kernel" | tr -d ' ')
  [ "$lines" -le 160 ] || err "$kernel: kernel longo demais (>160 linhas) para roteador"
  grep -qi 'tech-lead' "$kernel" || err "$kernel: sem papel tech-lead"
  if grep -q 'core-spec' "$kernel"; then
    [ -f ".swarm/core-spec.md" ] || err "$kernel: referencia core-spec mas .swarm/core-spec.md nao existe"
  fi
  has_placeholder "$kernel" && err "$kernel: placeholder nao-resolvido"
}

check_agents(){
  local dir found_dev base body lines
  dir=$(first_existing .cursor/agents .claude/agents agents || true)
  [ -n "$dir" ] || { err "diretorio de agentes ausente"; return; }
  [ ! -f "$dir/tech-lead.md" ] || err "$dir/tech-lead.md: tech-lead nao pode ser subagente"
  [ -f "$dir/verifier.md" ] || warn "$dir/verifier.md ausente (se roster nao tem verifier, justifique no TEAM_ROSTER)"

  found_dev=0
  for f in "$dir"/dev-*.md; do
    [ -f "$f" ] || continue
    found_dev=1
    base=$(basename "$f")
    grep -qi 'playbook' "$f" || err "$f: dev-* sem Playbooks"
    grep -Eq '[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,6}' "$f" || \
      err "$f: Playbooks/ancoras sem path real"
    has_placeholder "$f" && err "$f: placeholder nao-resolvido"
    body=$(strip_frontmatter_nonempty_lines "$f")
    [ "$body" -gt 20 ] || err "$f: agente parece casca vazia ($body linhas uteis)"
    lines=$(wc -l < "$f" | tr -d ' ')
    [ "$lines" -le 260 ] || warn "$base: agente muito longo ($lines linhas)"
  done
  [ "$found_dev" = "1" ] || warn "nenhum dev-*.md encontrado; greenfield/consultivo deve estar justificado"
}

check_commands(){
  local dir required f body
  dir=$(first_existing .cursor/commands .claude/commands commands || true)
  [ -n "$dir" ] || { err "diretorio de commands ausente"; return; }

  required="carregar-contexto salvar-sessao nova-sprint fechar-sprint verificar-saude rescan especializar verificar-artefatos mostrar-integracoes rescan-config fechar-feature"
  for c in $required; do
    [ -f "$dir/$c.md" ] || err "$dir/$c.md ausente"
  done

  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    body=$(strip_frontmatter_nonempty_lines "$f")
    [ "$body" -ge 5 ] || err "$f: command-stub sem corpo ($body linhas uteis)"
    has_placeholder "$f" && err "$f: placeholder nao-resolvido"
  done

  f="$dir/fechar-feature.md"
  if [ -f "$f" ]; then
    grep -Eq 'archive/features/\{FEATURE-ID\}|archive/features/' "$f" || \
      err "$f: falta sentinela archive/features/{FEATURE-ID}"
    grep -qiE '8 etapas|oito etapas' "$f" || err "$f: falta sentinela das 8 etapas"
  fi

  f="$dir/fechar-sprint.md"
  if [ -f "$f" ]; then
    grep -q 'consolidate-memory.py' "$f" || err "$f: falta consolidate-memory.py"
    grep -q 'transition.py --sprint' "$f" || err "$f: falta transition.py --sprint"
  fi

  f="$dir/verificar-artefatos.md"
  if [ -f "$f" ]; then
    grep -q 'verify-artifacts.sh' "$f" || err "$f: nao chama verify-artifacts.sh"
  fi
}

check_knowledge(){
  for f in \
    .swarm/knowledge/ARCHITECTURE_TREE.md \
    .swarm/knowledge/CONVENTIONS.md \
    .swarm/knowledge/EXTERNAL_INTEGRATIONS.md; do
    [ -f "$f" ] || err "$f ausente"
  done
}

check_scripts(){
  [ -f ".swarm/scripts-harness/verify-artifacts.sh" ] || err ".swarm/scripts-harness/verify-artifacts.sh ausente"
  [ -f ".swarm/scripts-harness/harness-lint.sh" ] || warn ".swarm/scripts-harness/harness-lint.sh ausente"
}

check_global_placeholders(){
  local files
  # (dev-store fix): *.jsonl excluido do sweep — ledger/knowledge-store append-only
  # (init-validation.jsonl, events.jsonl, conhecimento.jsonl) e AUDITORIA de achados
  # passados, nao template ativo; PROOF de fase pode legitimamente CITAR uma string
  # como '{FEATURE-ID}' que foi encontrada e corrigida, sem isso ser um placeholder
  # residual no artefato atual.
  files=$(find . -path './.git' -prune -o -path './node_modules' -prune -o \
    \( -path './.cursor/*' -o -path './.claude/*' -o -path './.swarm/knowledge/*' -o -path './.swarm/state/*' -o -name 'AGENTS.md' -o -name 'CLAUDE.md' -o -name 'SWARM.md' \) \
    -type f ! -name '*.jsonl' -print 2>/dev/null)
  [ -z "$files" ] && return
  # shellcheck disable=SC2086
  has_placeholder $files && err "placeholder nao-resolvido em artefatos do harness"
}

echo "verify-artifacts: root=$(pwd)"
check_docs

if [ "$DOCS_ONLY" = "0" ]; then
  check_kernel
  check_agents
  check_commands
  check_knowledge
  check_scripts
  check_global_placeholders
fi

if [ "$FAIL" = "0" ]; then
  [ "$WARN" = "0" ] && echo "verify-artifacts: OK" || echo "verify-artifacts: OK com avisos"
  exit 0
fi
echo "verify-artifacts: FALHOU"
exit 1
