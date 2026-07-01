#!/bin/bash
# harness-lint.sh — E3: valida o CONTEÚDO do harness (agentes + kernel + briefs
# + fatias de stack/layer rules desde a v4). Detector de drift: roda no
# pre-commit e no Estágio 7. Exit 1 em qualquer violação.
# Uso: harness-lint.sh [--root DIR]
set -u
ROOT="${2:-$(pwd)}"; [ "${1:-}" = "--root" ] && ROOT="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1
FAIL=0
err() { echo "LINT FAIL: $1"; FAIL=1; }

AGENT_DIRS=""
for d in .claude/agents .cursor/agents agents; do [ -d "$d" ] && AGENT_DIRS="$AGENT_DIRS $d"; done

# ---------- agentes ----------
for dir in $AGENT_DIRS; do
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    case "$base" in README*|ORCHESTRATION*|GUIA*) continue;; esac

    # 0. tech-lead nunca é subagente
    [ "$base" = "tech-lead.md" ] && err "$f: tech-lead como subagente (ADR-F1)"

    # 1. description funcional
    desc=$(awk '/^---$/{c++} c==1 && /^description:/{sub(/^description:[ ]*/,""); print; exit}' "$f")
    [ -z "$desc" ] && err "$f: sem description no frontmatter"
    [ -n "$desc" ] && [ "${#desc}" -lt 60 ] && err "$f: description curta demais para roteamento (<60 chars)"

    # 2. nenhuma tool de delegação em subagente
    grep -E '^tools:.*\b(Agent|Task)\b' "$f" >/dev/null && err "$f: subagente com tool de delegação (anti-padrão 1)"

    # verifier sem escrita
    if [ "$base" = "verifier.md" ]; then
      grep -E '^tools:.*\b(Write|Edit)\b' "$f" >/dev/null && \
        ! grep -E '^disallowedTools:.*\b(Write|Edit)\b' "$f" >/dev/null && \
        err "$f: verifier com Write/Edit sem disallow (P2)"
    fi

    # (v9-fix S3) schema do frontmatter Claude Code (doc oficial /en/sub-agents):
    #   tools/disallowedTools = lista por VIRGULA, nunca array YAML [..] (array pode nao aplicar
    #   a restricao); effort in {low,medium,high,xhigh,max} (NUNCA "normal"); model = alias|claude-*.
    fm=$(awk 'NR==1&&/^---$/{p=1;next} p&&/^---$/{exit} p' "$f")
    echo "$fm" | grep -qE '^(tools|disallowedTools):[[:space:]]*\[' && \
      err "$f: tools/disallowedTools como array YAML [..] — Claude Code usa lista por virgula (tools: Read, Grep) (v9-fix S3)"
    eff=$(echo "$fm" | sed -nE 's/^effort:[[:space:]]*"?([A-Za-z]+).*/\1/p')
    if [ -n "$eff" ] && ! echo "$eff" | grep -qE '^(low|medium|high|xhigh|max)$'; then
      err "$f: effort '$eff' invalido — use low|medium|high|xhigh|max (v9-fix S3)"
    fi
    mdl=$(echo "$fm" | sed -nE 's/^model:[[:space:]]*"?([A-Za-z0-9._-]+).*/\1/p')
    if [ -n "$mdl" ] && ! echo "$mdl" | grep -qE '^(sonnet|opus|haiku|inherit|claude-[a-z0-9._-]+)$'; then
      err "$f: model '$mdl' invalido — alias (sonnet|opus|haiku|inherit) ou id claude-* (v9-fix S3)"
    fi

    # 3. nove seções 0–8
    for s in 0 1 2 3 4 5 6 7 8; do
      grep -E "^##+ +$s( |—|-)" "$f" >/dev/null || err "$f: seção $s ausente"
    done

    # 4. (v9-fix S5) SNIPPET de codigo no corpo (anti-padrao 4). Cerca COM tag de linguagem
    #    (```csharp, ```python, ```json...) = snippet = FAIL. Cerca SEM tag (arvore do §2,
    #    diagrama ASCII) e SANCIONADA — o template §2 mostra a arvore cercada. Excecao: verifier.md
    #    pode ter 1 bloco (o contrato gate_report).
    body=$(awk '/^---$/{c++; next} c>=2' "$f")
    code_fences=$(echo "$body" | grep -cE '^```[a-zA-Z]')
    if [ "$base" = "verifier.md" ]; then
      [ "$code_fences" -gt 1 ] && err "$f: verifier com mais de 1 bloco de código (só o contrato gate_report é sancionado)"
    else
      [ "$code_fences" -gt 0 ] && err "$f: snippet de código no corpo (anti-padrão 4) — árvore/diagrama deve usar cerca SEM tag de linguagem"
    fi

    # 5. contagens voláteis (era grep -piE: opção inválida — o check nunca rodava; PM Jarvis)
    #    contagens de árvore "(+N arquivos)" são SANCIONADAS pelo template §2 — excluídas
    #    antes do grep (conflito regra5 × §2 detectado na rodada 3; PM Jarvis)
    echo "$body" | sed -E 's/\(\+[0-9]+ ?(arquivos|files|routers|docs)?[^)]*\)//g' | \
      grep -iE '\b[0-9]{2,} (testes|tests|arquivos|files)\b' >/dev/null && \
      err "$f: contagem volátil no corpo (anti-padrão 4)"

    # 5b. (v4) dev-*: Seção 2 deve ser árvore real, não 3 linhas vagas — proxy
    #     mecânico: exige o padrão "(+N" do template §2 (PM Jarvis-Teste-Fable)
    case "$base" in
      dev-*)
        sec2=$(awk '/^##+ +2( |—|-)/{flag=1;next} /^##+ +3( |—|-)/{flag=0} flag' "$f")
        echo "$sec2" | grep -qE '\(\+[0-9]+' || \
          err "$f: Seção 2 (Território) sem árvore com '(+N arquivos)' — template §2; OWNS vago não ensina fronteira"
        ;;
    esac

    # 5c. (v4.1) '(+N)' ou '(+X)' LITERAL = placeholder não-resolvido — a contagem
    #     é número contado no disco (anti-padrão 14; PM rodada 2 Jarvis: 4 ocorrências)
    echo "$body" | grep -qE '\(\+[A-Za-z]+\)' && \
      err "$f: contagem '(+N)' literal não-resolvida — conte os arquivos de verdade (anti-padrão 14)"

    # 5d. (v4.2) analistas raciocinam sobre o produto inteiro: po/architect têm
    #     "Esqueleto do projeto" na Seção 2 (PM rodada 3 Jarvis: po cego a 10/14 módulos)
    case "$base" in
      po.md|architect.md)
        grep -qi 'Esqueleto do projeto' "$f" || \
          err "$f: Seção 2 sem 'Esqueleto do projeto' — analista sem o mapa do todo alucina produto (template §2, v4.2)"
        ;;
    esac

    # 12. (v5) gates têm PODER DE VETO: corpo com "Bloquear se:" ou veredito
    #     BLOQUEADO — gate sem veto vira consultor decorativo (template v5, regra 12)
    case "$base" in
      security.md|perf.md|devops.md|git-specialist.md|*-gate.md)
        echo "$body" | grep -qiE 'bloquear se|bloqueado|veto' || \
          err "$f: gate sem poder de veto — Seção 7 precisa de 'Bloquear se:' ou veredito BLOQUEADO (regra 12, v5)"
        ;;
    esac

    # 13. (v5.2) Gate de Profundidade: especialista integrado tem maestria registrada
    #     (mastery.passed no STACK_PROFILE; 2b.6). Cobra que a SONDA RODOU e PASSOU,
    #     não a profundidade em si — essa quem mede é a sonda.
    #     (fix F4) Estendido a architect/po/qa: a sonda de maestria 2b.6 só era
    #     cobrada de dev-*/gates — analistas viravam "integrated" com maestria
    #     cerimonial. Sem fatia de domínio sondada, o agente direto fica sem
    #     conhecimento (raiz do "architect parece burro" / §22–25 da auditoria).
    case "$base" in
      dev-*.md|qa-*.md|architect.md|po.md|security.md|perf.md|devops.md|git-specialist.md)
        SPf=".swarm/state/STACK_PROFILE.yaml"
        if [ -f "$SPf" ]; then
          aname="${base%.md}"
          if grep -qE "^[[:space:]]*${aname}:.*passed: *true" "$SPf"; then
            # (v9 F1.3) passed:true exige EVIDENCIA persistida da sonda — senao e carimbo
            if [ -f ".swarm/state/mastery/${aname}.json" ]; then
              # (v9-fix S7) PISO de profundidade: a sonda tem de ter >=3 perguntas COM prova citada,
              # senao "passed:true" mede nada (sonda cerimonial). Profundidade com chao mecanico.
              if command -v python3 >/dev/null 2>&1; then
                python3 - ".swarm/state/mastery/${aname}.json" "$f" <<'PY' || FAIL=1
import json,sys
p,af=sys.argv[1],sys.argv[2]
try: d=json.load(open(p,encoding="utf-8"))
except Exception as e: print(f"LINT FAIL: {p} JSON invalido ({e}) (v9-fix S7)"); raise SystemExit(1)
qs=d.get("questions") or []
bad=0
if len(qs)<3:
    print(f"LINT FAIL: {af}: sonda de maestria com {len(qs)} pergunta(s) (<3) — profundidade nao medida, sonda cerimonial (v9-fix S7)"); bad=1
np=[q.get("id","?") for q in qs if not str(q.get("proof") or "").strip()]
if np:
    print(f"LINT FAIL: {af}: perguntas de maestria sem 'proof' ({np[:3]}) — veredito sem evidencia citada (v9-fix S7)"); bad=1
raise SystemExit(1 if bad else 0)
PY
              fi
            else
              err "$f: mastery.passed:true sem evidencia persistida (.swarm/state/mastery/${aname}.json com perguntas/veredito/prova) — sonda carimbada, nao provada (regra 13e, v9 F1.3)"
            fi
          else
            err "$f: especialista sem maestria registrada (mastery.passed) no STACK_PROFILE — Gate de Profundidade 2b.6 não rodou/passou (regra 13, v5.2; fix F4)"
          fi
        fi
        ;;
    esac

    # 13b. (fix NOVO/ADR-F7) especialista referencia a PRÓPRIA fatia de domínio na §4
    #      — é o cano que entrega conhecimento de produto ao /agente direto (sem brief)
    #      sem inflar o §0. Sem o ponteiro, o agente direto fica cego e varre o repo.
    case "$base" in
      dev-*.md|qa-*.md|architect.md|po.md|security.md|perf.md|devops.md|git-specialist.md)
        echo "$body" | grep -qE "domain/${base%.md}(\.ya?ml)?" || \
          err "$f: §4 sem ponteiro para a fatia de domínio (.swarm/knowledge/domain/${base%.md}.yaml) — /agente direto fica cego ao produto (template §4 v7; ADR-F7; fix NOVO)"
        ;;
    esac

    # 13c. (fix R1/S2) architect/po/gates referenciam DOMAIN_INVARIANTS na §4 — fonte
    #      canônica das invariantes; sem o ponteiro de pé o analista em /agente direto
    #      não vê o arquivo e o declara ausente (incidente DOC-DIST-REP, sintoma S2).
    case "$base" in
      architect.md|po.md|security.md|perf.md|devops.md|git-specialist.md)
        echo "$body" | grep -qF "DOMAIN_INVARIANTS" || \
          err "$f: §4 sem ponteiro para .swarm/knowledge/DOMAIN_INVARIANTS.yaml — analista/gate direto não vê as invariantes (template §4 v7; fix R1/S2)"
        ;;
    esac

    # 13d. (v7.5) architect/po/dev-* referenciam ORCHESTRATION_MAP na §4 — a fonte de
    #      FLUXO pré-computada (ONDE=ARCHITECTURE_TREE, COMO=ORCHESTRATION_MAP). Sem ela,
    #      "mapeie o fluxo de X" faz o agente RE-VARRER o código em vez de ler o mapa —
    #      a degradação medida vs v6.4 (agente deixa de parecer especialista do projeto).
    case "$base" in
      architect.md|po.md|dev-*.md)
        echo "$body" | grep -q "ORCHESTRATION_MAP" || \
          err "$f: §4 sem ponteiro para .swarm/knowledge/ORCHESTRATION_MAP.yaml — agente reconstrói o fluxo greando em vez de ler o mapa pré-computado (fluxo-no-cartao; degradação vs v6.4)"
        ;;
    esac

    # 6. âncoras citadas existem no disco — só tokens com separador de path
    #    (max.poll.interval.ms, Thread.Sleep etc. não são arquivos; PM§6 do kafkalib)
    echo "$body" | grep -oE '`[A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,5}`' | tr -d '\`' | sort -u | while read -r anchor; do
      case "$anchor" in
        *.md|*.json|*.yaml|*.yml) continue;;
        */*) ;;
        *) continue;;
      esac
      find . -path "./node_modules" -prune -o -path "*$anchor" -print 2>/dev/null | grep -q . || \
        echo "LINT WARN: $f cita âncora não encontrada: $anchor"
    done

    # 7. teto por perfil (v4.2): analistas têm corpo expandido SANCIONADO
    #    (architect 240, po 170 — re-herdado do V6.3); executores são cartão (140)
    lines=$(echo "$body" | wc -l | tr -d ' ')
    case "$base" in
      architect.md) cap=240;;
      po.md)        cap=170;;
      *)            cap=140;;
    esac
    [ "$lines" -gt "$cap" ] && err "$f: corpo com $lines linhas (>$cap para este perfil — template v4.2)"

    # 7b. (fix F2) PISO por perfil: cartão raso de analista NÃO passa. A spec manda
    #     architect expandido e po médio; sem piso, um INIT degradado entrega 51
    #     linhas e passa nos gates formais (incidente DOC-DIST-REP §1).
    case "$base" in
      architect.md)      floor=120;;
      po.md)             floor=80;;
      dev-*.md|qa-*.md)  floor=40;;
      *)                 floor=0;;
    esac
    [ "$floor" -gt 0 ] && [ "$lines" -lt "$floor" ] && \
      err "$f: corpo com $lines linhas (<$floor piso para este perfil — cartão raso; expanda conforme agent-template, perfis por papel; fix F2)"

    # 7c. (fix F2) architect: Fases 0–4 obrigatórias no corpo expandido (template v4.2)
    if [ "$base" = "architect.md" ]; then
      for ph in "Fase 0" "Fase 1" "Fase 2" "Fase 3" "Fase 4"; do
        grep -qi "$ph" "$f" || err "$f: architect sem '$ph' — corpo expandido exige Fases 0–4 (agent-template, perfil expandido; fix F2)"
      done
      # 7d. (fix F1) architect grava ADR — readonly:true o impede de entregar (incidente S3)
      grep -qE '^readonly:[[:space:]]*true' "$f" && \
        err "$f: architect com 'readonly: true' — não consegue gravar ADR/knowledge (a entrega). Use readonly:false; o E2 (preToolUse) escopa a escrita (adapter-cursor; fix F1)"
    fi
  done
done

# ---------- 10. (v5) completude da Seção 2 dos dev-* via grafo (WARN, não FAIL:
#            sem o roster em JSON, omissão é sinal p/ revisão humana, não veredito) ----------
GRAPH=".swarm/knowledge/graph.json"
if command -v python3 >/dev/null 2>&1 && [ -f "$GRAPH" ]; then
  for dir in $AGENT_DIRS; do
    for f in "$dir"/dev-*.md; do
      [ -f "$f" ] || continue
      python3 - "$f" "$GRAPH" <<'PY' || true
import json, sys, re, os
from collections import Counter
agent, graph = sys.argv[1], sys.argv[2]
body = open(agent, encoding="utf-8").read()
m = re.search(r'^#{2,}\s*2[ \-—].*?(?=^#{2,}\s*3[ \-—])', body, re.S | re.M)
sec2 = m.group(0) if m else ""
if not sec2:
    sys.exit(0)
# raiz da fronteira = primeiro segmento mais comum nos paths citados na Seção 2
segs = [p.split("/")[0] for p in re.findall(r'([A-Za-z0-9_.]+(?:/[A-Za-z0-9_.]+)+)', sec2)]
if not segs:
    sys.exit(0)
root = Counter(segs).most_common(1)[0][0]
files = json.load(open(graph)).get("files", [])
subdirs = set()
for p in files:
    parts = p.replace("\\", "/").split("/")
    if parts and parts[0] == root and len(parts) >= 2:
        subdirs.add(parts[1])
missing = [d for d in sorted(subdirs) if d and d not in sec2]
if missing:
    print(f"LINT WARN: {os.path.basename(agent)}: Seção 2 pode omitir subpastas reais de '{root}/': "
          f"{missing[:6]} — confira completude (regra 10, v5)")
PY
    done
  done
fi

# ---------- (fix cobertura) toda invariante coletada (2c) FLUI para algum agente/fatia ----------
#   Órfã = conhecimento coletado que nunca chega ao especialista. Medido no INIT
#   DevStore: 9/10 invariantes órfãs (BIZ-1/2/3 nunca chegaram ao dev-orders).
INV=".swarm/knowledge/DOMAIN_INVARIANTS.yaml"
if [ -f "$INV" ] && [ -n "$AGENT_DIRS" ]; then
  while read -r inv; do
    [ -z "$inv" ] && continue
    found=0
    for d in $AGENT_DIRS .swarm/knowledge/domain; do
      [ -d "$d" ] || continue
      grep -rqlE "\b$inv\b" "$d" 2>/dev/null && { found=1; break; }
    done
    [ "$found" = "0" ] && err "invariante $inv (DOMAIN_INVARIANTS) órfã — não citada em nenhum agente nem fatia de domínio; conhecimento coletado não chegou ao especialista"
  done < <(grep -oE '\b(SEC|PERF|OPS|BIZ)-[0-9]+\b' "$INV" | sort -u)
fi

# ---------- (fix árvore-completa) ARCHITECTURE_TREE lista TODA pasta real + >=1 âncora ----------
#   "o agente precisa saber ONDE criar algo" — toda pasta do graph aparece na árvore,
#   com ao menos um arquivo-âncora citado por pasta.
TREE_MD=".swarm/knowledge/ARCHITECTURE_TREE.md"
GRAPH_J=".swarm/knowledge/graph.json"
if command -v python3 >/dev/null 2>&1 && [ -f "$TREE_MD" ] && [ -f "$GRAPH_J" ]; then
  python3 - "$TREE_MD" "$GRAPH_J" <<'PY' || FAIL=1
import json, os, re, sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
tree = "\n".join(lines)
files = json.load(open(sys.argv[2])).get("files", [])
gfolders = sorted({os.path.dirname(f.replace("\\","/")) for f in files if os.path.dirname(f.replace("\\","/"))})
bad = 0
if "├──" not in tree and "└──" not in tree:
    print("LINT FAIL: ARCHITECTURE_TREE nao usa formato visual de arvore (├──/└──) — regenere (01-scan.md §FORMATO)"); bad=1
# (no-colapso) proibir "(Foo/, Bar/, ...)": pastas listadas em parentese sem arquivo proprio
for ln in lines:
    for pm in re.finditer(r"\(([^)]*)\)", ln):
        if re.search(r"[\w.\-]+/\s*,", pm.group(1)):
            print(f"LINT FAIL: ARCHITECTURE_TREE colapsa pastas em parentese ({pm.group(0)[:48]}) — liste CADA pasta com >=1 arquivo, sem parentese (no-colapso)"); bad=1; break
# parse ESTRUTURAL: reconstroi o caminho de cada no pela indentacao; pasta -> arquivos DIRETOS
conn = re.compile(r"^(.*?)(?:├──|└──)\s*(\S+)")
path_at = {}; root = None; fol_nodes=set(); fol_files={}
for ln in lines:
    sline = ln.strip()
    if "──" not in ln and re.match(r"^[\w.\-]+/$", sline):
        root = sline.rstrip("/"); path_at = {0: root}; fol_nodes.add(root); fol_files.setdefault(root,set()); continue
    m = conn.match(ln)
    if not m: continue
    prefix, name = m.groups()
    depth = len(prefix)//4 + 1
    is_dir = name.endswith("/"); clean = name.rstrip("/")
    path_at = {k:v for k,v in path_at.items() if k < depth}
    parent = "/".join(path_at[k] for k in sorted(path_at))
    full = (parent + "/" + clean) if parent else clean
    if is_dir:
        path_at[depth] = clean; fol_nodes.add(full); fol_files.setdefault(full,set())
    else:
        fol_files.setdefault(parent,set()).add(clean)
miss_node = [d for d in gfolders if d not in fol_nodes]
miss_file = [d for d in gfolders if d in fol_nodes and not fol_files.get(d)]
for d in miss_node[:25]:
    print(f"LINT FAIL: ARCHITECTURE_TREE nao tem a pasta '{d}/' como no REAL da arvore — agente nao sabe onde criar (arvore-completa, estrutural)"); bad=1
for d in miss_file[:25]:
    print(f"LINT FAIL: ARCHITECTURE_TREE: pasta '{d}/' sem >=1 arquivo mostrado DIRETAMENTE sob ela (1-arquivo-por-pasta, estrutural)"); bad=1
sys.exit(1 if bad else 0)
PY
fi

# ---------- (fix gate especialista) por-agente: o agente é DONO da sua fronteira ----------
#   (A) escopo completo: o §2 cobre TODA pasta do graph dentro do `trees` do roster.
#   (B) invariante que TOCA a fronteira (evidence × trees) é citada pelo agente dono;
#       sem dono por tree, cai no gate por prefixo (SEC→security, OPS→devops, PERF→perf).
#   É o gate que garante especialista cirúrgico com TODO o dado coletado da fronteira.
ROSTER_F=".swarm/state/TEAM_ROSTER.yaml"
if command -v python3 >/dev/null 2>&1 && [ -f "$ROSTER_F" ]; then
  _FABLE_LIB="$SCRIPT_DIR" python3 - <<'PY' || FAIL=1
import json, os, re, sys; sys.path.insert(0, os.environ['_FABLE_LIB'])
from roster_parser import parse_roster, norm, in_tree, parse_inv, rd
INV=".swarm/knowledge/DOMAIN_INVARIANTS.yaml"; GRAPH=".swarm/knowledge/graph.json"
AGDIR=next((d for d in (".cursor/agents",".claude/agents","agents") if os.path.isdir(d)), None)
if AGDIR is None: raise SystemExit(0)

agents=parse_roster(".swarm/state/TEAM_ROSTER.yaml")
def atext(n): return rd(os.path.join(AGDIR,n+".md"))+"\n"+rd(os.path.join(".swarm/knowledge/domain",n+".yaml"))
bad=0

GATE={"SEC":"security","OPS":"devops","PERF":"perf"}
if os.path.exists(INV):
    for inv in parse_inv(INV):
        owner=None
        if inv["ev"]:
            for n,tr in agents.items():
                if tr and in_tree(inv["ev"],tr): owner=n; break
        if owner is None:
            g=GATE.get(inv["id"].split("-")[0])
            owner=g if g in agents else None
        if owner and not re.search(r'\b'+re.escape(inv["id"])+r'\b', atext(owner)):
            print(f"LINT FAIL: invariante {inv['id']} toca a fronteira de '{owner}' mas nao e citada no cartao/fatia dele (especializacao incompleta)"); bad=1

# FAIL-CLOSED: sem graph.json NÃO dá para verificar a completude do §2 — e foi assim
# que o §2 raso passou (achado dev-store: harness gerado sem grafo → gate pulava em
# silêncio). Roster com fronteira E sem grafo = Estágio 1 não rodou: reprova, não pula.
frontiers=[n for n,tr in agents.items() if tr]
if not os.path.exists(GRAPH):
    if frontiers:
        print(f"LINT FAIL: graph.json ausente (.swarm/knowledge/graph.json) — a completude do §2 de "
              f"{len(frontiers)} fronteira(s) NAO pode ser verificada e o escopo raso passa; o Estagio 1 "
              f"(scan/grafo) nao rodou ou foi perdido (graph-obrigatorio; fail-closed)")
        bad=1
else:
    files=json.load(open(GRAPH)).get("files",[])
    folders=sorted({os.path.dirname(f.replace("\\","/")) for f in files if os.path.dirname(f.replace("\\","/"))})
    for n,tr in agents.items():
        if not tr: continue
        body=rd(os.path.join(AGDIR,n+".md"))
        m=re.search(r'(?ms)^#{1,3}\s*2[ \-—].*?(?=^#{1,3}\s*3[ \-—]|\Z)', body)
        sec2=m.group(0) if m else body
        # cada PROJETO/raiz da fronteira (trees) tem de aparecer no §2 — pega o "só mostra API"
        for t in tr:
            root=norm(t)
            base=root.split("/")[-1]
            if root and base and base not in sec2 and root not in sec2:
                print(f"LINT FAIL: {n}: §2 nao cobre a raiz de fronteira '{root}/' — projeto inteiro ausente do escopo"); bad=1
        # cada pasta real da fronteira aparece (path OU basename)
        miss=[fl for fl in folders if in_tree(fl,tr) and fl not in sec2 and fl.split("/")[-1] not in sec2]
        for fl in miss[:8]:
            print(f"LINT FAIL: {n}: §2 nao cobre a pasta '{fl}/' da sua fronteira — escopo incompleto"); bad=1
        # (v9-fix arvore) cada pasta COBERTA mostra >=1 arquivo dela no §2 (nao so o nome da pasta)
        byf={}
        for ff in files:
            ff2=ff.replace("\\","/"); dd=os.path.dirname(ff2)
            if dd: byf.setdefault(dd,[]).append(os.path.basename(ff2))
        covered=[fl for fl in folders if in_tree(fl,tr) and fl not in miss]
        mf=[fl for fl in covered if byf.get(fl) and not any(b in sec2 for b in byf[fl])]
        for fl in mf[:8]:
            print(f"LINT FAIL: {n}: §2 mostra a pasta '{fl}/' mas SEM >=1 arquivo dela — agente nao conhece o conteudo (1-arquivo-por-pasta)"); bad=1
raise SystemExit(1 if bad else 0)
PY
fi

# ---------- (fix P1 stack-por-fronteira) o dono especializa a stack REAL da sua fronteira ----------
#   Cada agente com `trees` é dono dos manifestos DENTRO do tree (`*.csproj`,
#   `package.json`, `go.mod`...). Dela saem as libs de MENSAGERIA e BANCO — a
#   classe onde o modelo mais alucina cross-stack (Kafka onde é RabbitMQ, Mongo
#   onde é SQL). Se a lib significativa da fronteira não aparece na
#   especialização do dono (cartão OU fatia de domínio OU layer rule) = FAIL.
#   Rigor (decisão): mensageria + banco por NOME (recomendado; pega o que
#   importa sem o ruído de libs triviais). Tabelas extensíveis; "top-N por
#   centralidade" pode endurecer depois. E o §0 do dono tem de carregar
#   `never_use` (recusa de off-stack) quando há stack de fronteira detectada.
ROSTER_P1=".swarm/state/TEAM_ROSTER.yaml"
if command -v python3 >/dev/null 2>&1 && [ -f "$ROSTER_P1" ]; then
  _FABLE_LIB="$SCRIPT_DIR" python3 - <<'PY' || FAIL=1
import json, os, re, sys; sys.path.insert(0, os.environ['_FABLE_LIB'])
from roster_parser import parse_roster, norm, rd
ROSTER=".swarm/state/TEAM_ROSTER.yaml"
AGDIR=next((d for d in (".cursor/agents",".claude/agents","agents") if os.path.isdir(d)), None)
if AGDIR is None or not os.path.exists(ROSTER): raise SystemExit(0)

agents=parse_roster(ROSTER)

SKIP={"node_modules","bin","obj",".git","dist","build","target",".venv","venv","__pycache__",".svn",".idea"}
# Manifesto em pasta de TESTE/sample/vendor NAO e stack de PRODUCAO da fronteira —
# projetos de teste puxam Testcontainers (Kafka/Mongo/Redis), brokers in-memory e
# drivers alternativos que o codigo de producao RECUSA. Contar isso forcaria o
# agente a "especializar" tech que o proprio never_use proibe (false positive).
TESTDIR={"tests","test","__tests__","samples","sample","examples","example",
         "fixtures","testdata","e2e","mocks","mock","vendor","benchmarks","benchmark"}
def skip_dir(d):
    dl=d.lower()
    if d in SKIP or dl in TESTDIR: return True
    return any(dl.endswith(s) for s in (".tests",".test",".unittests",".integrationtests",".e2e",".benchmarks"))
MANIFEST=re.compile(r'(\.csproj|\.fsproj)$|^package\.json$|^requirements.*\.txt$|^go\.mod$|^pom\.xml$|^build\.gradle(\.kts)?$|^Cargo\.toml$|^pyproject\.toml$|^Gemfile$|^composer\.json$')

def libs_from(fname, text):
    libs=set(); low=fname.lower()
    if low.endswith(".csproj") or low.endswith(".fsproj"):
        libs|=set(re.findall(r'(?:PackageReference|PackageVersion)\s+Include="([^"]+)"', text))
    elif fname=="package.json" or fname=="composer.json":
        try:
            d=json.loads(text)
            for k in ("dependencies","devDependencies","peerDependencies","require","require-dev"):
                if isinstance(d.get(k),dict): libs|=set(d[k].keys())
        except Exception: pass
    elif low.startswith("requirements") and low.endswith(".txt"):
        for ln in text.splitlines():
            ln=ln.split('#')[0].strip()
            if ln and not ln.startswith('-'): libs.add(re.split(r'[<>=!~\[ ;]', ln)[0].strip())
    elif fname=="go.mod":
        for ln in text.splitlines():
            mm=re.match(r'\s*(?:require\s+)?([\w.\-/]+)\s+v\d', ln)
            if mm: libs.add(mm.group(1))
    elif fname=="pom.xml":
        libs|=set(m.strip() for m in re.findall(r'<artifactId>([^<]+)</artifactId>', text))
    elif low.startswith("build.gradle"):
        libs|=set(m for _,m in re.findall(r'''['"]([\w.\-]+):([\w.\-]+):''', text))
    elif fname=="Cargo.toml":
        insec=False
        for ln in text.splitlines():
            s=ln.strip()
            if s.startswith('['): insec=('dependencies' in s); continue
            if insec:
                mm=re.match(r'([\w\-]+)\s*=', s)
                if mm: libs.add(mm.group(1))
    elif fname=="pyproject.toml":
        for ln in text.splitlines():
            mm=re.match(r'([A-Za-z0-9_.\-]+)\s*=\s*["\{]', ln.strip())
            if mm and mm.group(1) not in ("python","name","version","description","readme","license","requires-python"): libs.add(mm.group(1))
        for mm in re.findall(r'"([A-Za-z0-9_.\-]+)(?:[<>=!~\[].*?)?"', text): libs.add(mm)
    elif fname=="Gemfile":
        libs|=set(re.findall(r'gem\s+["\']([\w\-]+)["\']', text))
    return {l for l in libs if l}

# classificação MENSAGERIA + BANCO (a classe de maior alucinação cross-stack)
SIGNIF=[(re.compile(p, re.I),c) for p,c in [
  (r'^MassTransit$','mensageria'),(r'^MassTransit\.RabbitMq$','mensageria'),(r'^RabbitMQ\.Client$','mensageria'),
  (r'^MassTransit\.Kafka$','mensageria'),(r'^Confluent\.Kafka$','mensageria'),(r'^MassTransit\.AmazonSqs$','mensageria'),
  (r'^Azure\.Messaging\.ServiceBus$','mensageria'),(r'^NServiceBus','mensageria'),
  (r'^amqplib$','mensageria'),(r'^kafkajs$','mensageria'),(r'^pika$','mensageria'),(r'^kombu$','mensageria'),
  (r'^kafka-python$','mensageria'),(r'^confluent-kafka$','mensageria'),(r'^aio-pika$','mensageria'),
  (r'^Dapper$','banco'),(r'^Microsoft\.Data\.SqlClient$','banco'),(r'^System\.Data\.SqlClient$','banco'),
  (r'EntityFrameworkCore\.SqlServer$','banco'),(r'EntityFrameworkCore\.(Npgsql|PostgreSQL)','banco'),
  (r'^Npgsql','banco'),(r'^MySql(Connector|\.Data)','banco'),(r'^MongoDB\.Driver$','banco'),
  (r'^StackExchange\.Redis$','banco'),(r'^mongoose$','banco'),(r'^pymongo$','banco'),(r'^motor$','banco'),
  (r'^psycopg2?(-binary)?$','banco'),(r'^mysqlclient$','banco'),(r'^redis$','banco'),(r'^ioredis$','banco'),
  (r'^sqlalchemy$','banco'),(r'^pg$','banco'),(r'^mysql2?$','banco'),(r'^mssql$','banco'),
]]
def classify(lib):
    for rx,c in SIGNIF:
        if rx.search(lib): return c
    return None

def spec_text(n):
    parts=[rd(os.path.join(AGDIR,n+".md")),
           rd(os.path.join(".swarm/knowledge/domain",n+".yaml")),
           rd(os.path.join(".swarm/knowledge/domain",n+".yml"))]
    for rdir in (".cursor/rules",".claude/rules","rules"):
        parts.append(rd(os.path.join(rdir,n+"-layer.mdc")))
        parts.append(rd(os.path.join(rdir,n+"-layer.md")))
    return "\n".join(parts)

def sec0(n):
    body=rd(os.path.join(AGDIR,n+".md"))
    m=re.search(r'(?ms)^#{1,3}\s*0[ \-—].*?(?=^#{1,3}\s*1[ \-—]|\Z)', body)
    return m.group(0) if m else ""

bad=0
for n,tr in agents.items():
    if not tr: continue
    libs=set()
    for t in tr:
        root=norm(t)
        if not root: continue
        if os.path.isfile(root):
            fn=os.path.basename(root)
            if MANIFEST.search(fn): libs|=libs_from(fn, rd(root))
            continue
        if not os.path.isdir(root): continue
        for dp,dirs,files in os.walk(root):
            dirs[:]=[d for d in dirs if not skip_dir(d)]
            for fn in files:
                if MANIFEST.search(fn): libs|=libs_from(fn, rd(os.path.join(dp,fn)))
    signif={}
    for l in libs:
        c=classify(l)
        if c: signif[l]=c
    if not signif: continue
    txt=spec_text(n)
    for lib,cat in sorted(signif.items()):
        if not re.search(re.escape(lib), txt, re.I):
            print(f"LINT FAIL: {n} nao especializa {lib} (stack real da sua fronteira: {cat}) — cartao/fatia/layer rule sem a lib; o agente inventaria tech de fora")
            bad=1
    s0=sec0(n)
    if not re.search(r'never_use|nunca introduza', s0, re.I):
        cats=", ".join(sorted(set(signif.values())))
        print(f"LINT FAIL: {n}: §0 nao carrega never_use (recusa de off-stack) — stack de fronteira detectada ({cats}) exige recusa explicita de tech rival")
        bad=1
raise SystemExit(1 if bad else 0)
PY
fi

# ---------- (fix P3) profundidade da fatia de dominio ∝ tamanho da fronteira ----------
#   Fatia de 3 bullets para uma fronteira de 180 arquivos passava sem gate.
#   min_entries = max(3, ceil(frontier_files/40)) + #invariantes_que_tocam_a_fronteira.
#   Fatia que EXISTE mas e rasa = FAIL. Fatia AUSENTE em fronteira grande = WARN
#   (conservador; o handoff manda comecar conservador e endurecer depois).
ROSTER_P3=".swarm/state/TEAM_ROSTER.yaml"
GRAPH_P3=".swarm/knowledge/graph.json"
if command -v python3 >/dev/null 2>&1 && [ -f "$ROSTER_P3" ] && [ -f "$GRAPH_P3" ]; then
  _FABLE_LIB="$SCRIPT_DIR" python3 - <<'PY' || FAIL=1
import json, os, re, sys; sys.path.insert(0, os.environ['_FABLE_LIB'])
from roster_parser import parse_roster, norm, in_tree, parse_inv, rd
ROSTER=".swarm/state/TEAM_ROSTER.yaml"; GRAPH=".swarm/knowledge/graph.json"
INV=".swarm/knowledge/DOMAIN_INVARIANTS.yaml"
if not os.path.exists(GRAPH): raise SystemExit(0)

def count_entries(text):
    # conta so entradas SUBSTANTIVAS: id nao-vazio + source + confidence + check
    # (fatia oca com '- id:' vazio, ou so com claim, NAO engana a profundidade ∝
    #  fronteira — achado do audit adversarial: padding de markers gamava o gate).
    n=0
    for p in re.split(r'(?m)^\s*-\s*id:', text)[1:]:
        first=p.splitlines()[0].strip() if p.strip() else ""
        if first and re.search(r'(?m)^\s*source:\s*\S', p) \
                 and re.search(r'(?m)^\s*confidence:\s*\S', p) \
                 and re.search(r'(?m)^\s*check:\s*\S', p):
            n+=1
    return n

agents=parse_roster(ROSTER)
files=json.load(open(GRAPH)).get("files",[])
invs=parse_inv(INV) if os.path.exists(INV) else []
bad=0
for n,tr in agents.items():
    if not tr: continue
    ff=sum(1 for f in files if in_tree(f, tr))
    if ff==0: continue
    inv_touch=sum(1 for iv in invs if iv.get("ev") and in_tree(iv["ev"], tr))
    min_entries=max(3, -(-ff//40)) + inv_touch
    slice_path=next((os.path.join(".swarm/knowledge/domain", n+e)
                     for e in (".yaml",".yml")
                     if os.path.exists(os.path.join(".swarm/knowledge/domain", n+e))), None)
    if slice_path is None:
        if ff>=80:
            print(f"LINT WARN: {n}: fronteira grande ({ff} arquivos) sem fatia de dominio (knowledge/domain/{n}.yaml) — profundidade nao cobravel (P3)")
        continue
    entries=count_entries(rd(slice_path))
    if entries < min_entries:
        print(f"LINT FAIL: fatia de {n} rasa: {entries} entradas para {ff} arquivos + {inv_touch} invariantes (minimo {min_entries}) — profundidade nao escala com a fronteira (P3)")
        bad=1
raise SystemExit(1 if bad else 0)
PY
fi

# ---------- kernel × roster (PM§2: kernel obsoleto roteando p/ agentes inexistentes) ----------
#   (fix P2) Detecção do kernel: no Cursor o kernel é `swarm-kernel.mdc`
#   (`alwaysApply:true`) e o `AGENTS.md` é ponteiro ENXUTO. Ordem antiga
#   (CLAUDE → AGENTS → swarm-kernel) elegia o AGENTS.md como kernel e exigia o
#   roster NELE, forçando duplicação em dois arquivos always-on que divergem.
#   Prioridade correta: CLAUDE.md (Claude Code) > swarm-kernel.mdc (Cursor) >
#   AGENTS.md (fallback genérico, único always-on).
ROSTER=".swarm/state/TEAM_ROSTER.yaml"
if [ -f "$ROSTER" ]; then
  KERNEL=""
  for k in CLAUDE.md .cursor/rules/swarm-kernel.mdc AGENTS.md; do
    [ -f "$k" ] && KERNEL="$k" && break
  done
  if [ -n "$KERNEL" ] && command -v python3 >/dev/null 2>&1; then
    # roster-no-kernel: nome presente (kernel não-órfão) + TERRITÓRIO citado para agente
    #   com `trees` (roster do time exige agente+escopo, não nome solto — fix do roster fraco,
    #   04-generate). Território = `trees` normalizado; basta UM aparecer no texto do kernel.
    _FABLE_LIB="$SCRIPT_DIR" python3 - "$KERNEL" "$ROSTER" <<'PY' || FAIL=1
import os, sys
sys.path.insert(0, os.environ['_FABLE_LIB'])
from roster_parser import parse_roster, norm, rd
kpath, rpath = sys.argv[1], sys.argv[2]
ktext = rd(kpath)
agents = parse_roster(rpath)
bad = 0
for name, trees in agents.items():
    if name not in ktext:
        print(f"LINT FAIL: {kpath}: agente '{name}' do TEAM_ROSTER ausente no kernel (kernel obsoleto ou agente orfao)")
        bad = 1
        continue
    if trees:  # agente com fronteira de escrita: território tem de aparecer no kernel
        toks = [t for t in (norm(x) for x in trees) if t]
        if toks and not any(tok in ktext for tok in toks):
            print(f"LINT FAIL: {kpath}: agente '{name}' citado SEM territorio no kernel "
                  f"(esperado um de: {', '.join(toks[:3])}) — roster do time exige agente+territorio, "
                  f"nao nome solto (04-generate: roster-no-kernel)")
            bad = 1
sys.exit(1 if bad else 0)
PY
  elif [ -n "$KERNEL" ]; then
    # fallback sem python3: degrada para só nome presente
    while IFS= read -r agent; do
      [ -z "$agent" ] && continue
      grep -q "$agent" "$KERNEL" || \
        err "$KERNEL: agente '$agent' do TEAM_ROSTER ausente no kernel (kernel obsoleto ou agente órfão)"
    done < <(grep -E '^\s*-\s*name:' "$ROSTER" | sed 's/.*name:[[:space:]]*//' | tr -d '"')
  fi

  # (fix P2) quando swarm-kernel.mdc é o kernel, AGENTS.md tem de ser ENXUTO —
  #   ponteiro (≤30 linhas) e SEM tabela de roster. Senão é always-on duplicado
  #   do kernel (roster em dois arquivos que divergem).
  if [ -f ".cursor/rules/swarm-kernel.mdc" ] && [ -f "AGENTS.md" ]; then
    al=$(wc -l < "AGENTS.md" | tr -d ' ')
    [ "$al" -gt 30 ] && err "AGENTS.md duplica o kernel ($al linhas >30); deixe-o como ponteiro enxuto (roster vive no swarm-kernel.mdc) — fix P2"
    grep -qiE '^\s*\|\s*agentes?\s*\|' "AGENTS.md" && \
      err "AGENTS.md duplica o kernel (tabela de roster); deixe-o como ponteiro enxuto — o roster vive no swarm-kernel.mdc (fix P2)"
  fi
fi

# ---------- (v9 F0A.1) kernel forte: tech-lead nao pode ser ponteiro raso ----------
#   O kernel e o prompt operacional do tech-lead (04-generate §kernel): sem as secoes
#   operacionais ele nao roteia/decompoe/verifica/recupera/fecha — vira pasta de agentes.
#   Detecta o kernel FORTE (CLAUDE > swarm-kernel > AGENTS); no Cursor o AGENTS.md ponteiro
#   nao e cobrado porque o forte (swarm-kernel.mdc) e preferido na ordem.
K9=""
for k in CLAUDE.md .cursor/rules/swarm-kernel.mdc AGENTS.md; do [ -f "$k" ] && K9="$k" && break; done
if [ -n "$K9" ]; then
  k9miss=""
  grep -qiE 'tech-lead' "$K9"                                   || k9miss="$k9miss papel/tech-lead"
  grep -qiE 'pr[eé]-despacho|antes de despachar|verifica' "$K9" || k9miss="$k9miss verificacoes-pre-despacho"
  grep -qiE 'triagem|roteamento|\bTier\b|\brota\b' "$K9"        || k9miss="$k9miss triagem/roteamento"
  grep -qiE 'fechamento|COMMITTED' "$K9"                        || k9miss="$k9miss fechamento-de-ciclo"
  grep -qiE 'recupera|escala|PARTIAL|BLOCKED' "$K9"             || k9miss="$k9miss recuperacao/escalada"
  [ -n "$k9miss" ] && err "$K9: kernel raso — secoes operacionais ausentes:$k9miss. O tech-lead precisa rotear/decompor/verificar/recuperar/fechar, nao ser ponteiro (04-generate §kernel; kernel-forte, v9 F0A.1)"
fi

# ---------- (v9-fix S4) protocol_version de fonte unica ----------
#   O INIT do dev-store carimbou protocol_version: 7 no CAPABILITY/ROSTER mas 7.6.0 no kernel/RESUME.
#   Versao em dois valores faz /migrate e gates de versao decidirem errado. Exige UM valor em todo lugar.
pv_kernel=$(grep -hoE 'protocol_version[^0-9]*[0-9]+(\.[0-9]+){1,3}' ${K9:-/dev/null} RESUME.md .swarm/state/RESUME.md 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+){1,3}' | head -1)
pv_state=$(grep -hoE '^protocol_version:[[:space:]]*"?[0-9]+(\.[0-9]+){0,3}' .swarm/state/*.yaml 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+){0,3}' | sort -u)
if [ -n "$pv_kernel" ] && [ -n "$pv_state" ]; then
  for v in $pv_state; do
    [ "$v" != "$pv_kernel" ] && err "protocol_version divergente: estado declara '$v' mas kernel/RESUME declara '$pv_kernel' — use fonte unica (v9-fix S4)"
  done
fi
npv=$(echo "$pv_state" | grep -c .)
[ "${npv:-0}" -gt 1 ] && err "protocol_version divergente entre YAMLs de estado ($(echo $pv_state | tr '\n' ' ')) — fonte unica (v9-fix S4)"

# ---------- kernel ----------
for k in CLAUDE.md AGENTS.md .cursor/rules/swarm-kernel.mdc; do
  [ -f "$k" ] || continue
  kl=$(wc -l < "$k" | tr -d ' ')
  [ "$kl" -gt 160 ] && err "$k: kernel com $kl linhas (>160)"
  grep -E '\{[a-z_]+\}' "$k" >/dev/null && err "$k: placeholder não-resolvido (anti-padrão 14)"
  # 14. (v6) kernel referencia core-spec mas o arquivo não foi emitido no projeto
  #     = link morto (achado de campo: kernel apontava p/ core-spec inexistente).
  if grep -q 'core-spec' "$k" && [ ! -f ".swarm/core-spec.md" ] && [ ! -f "core-spec.md" ]; then
    err "$k: referencia 'core-spec' mas .swarm/core-spec.md não existe — emita no Estágio 4 (passo 0); referência morta (regra 14, v6)"
  fi
done

# ---------- v4: fatias de stack (anti-padrão 19) ----------
SLICES=".swarm/knowledge/stack"
if [ -d "$SLICES" ]; then
  for sf in "$SLICES"/*.yaml "$SLICES"/*.yml; do
    [ -f "$sf" ] || continue
    ids=$(grep -c '^- id:' "$sf")
    [ "$ids" -eq 0 ] && { echo "LINT WARN: $sf: fatia sem entradas"; continue; }
    for field in source confidence check; do
      n=$(grep -c "^  $field:" "$sf")
      [ "$n" -lt "$ids" ] && err "$sf: $((ids-n)) entrada(s) sem campo '$field' (anti-padrão 19)"
    done
    # confidence só aceita os dois valores canônicos
    grep -E '^  confidence:' "$sf" | grep -vE 'verified|unverified' >/dev/null && \
      err "$sf: confidence fora de {verified, unverified}"
    # source que é path local deve existir no disco
    # (awk '{print $1}': source pode trazer anotação após o path — "path — nota";
    #  só o primeiro token é o path; PM Jarvis-Teste-Fable: 3 falsos WARN)
    # (#3) tolerante a número de linha: `file.cs:30` / `file.cs:24,29` → strip `:N` antes
    #  do teste no disco (linha pertence ao check, não muda o path; resolve os 14 WARN do INIT)
    grep -E '^  source: ' "$sf" | sed 's/^  source:[[:space:]]*//' | tr -d '"' | awk '{print $1}' | sed 's/:[0-9][0-9,.-]*$//' | while read -r src; do
      case "$src" in
        http*|"") ;;
        */*) [ -e "$src" ] || echo "LINT WARN: $sf: source path inexistente: $src" ;;
      esac
    done
  done
fi

# ---------- v4: STACK_PROFILE — fingerprint de defasagem (aviso, nunca FAIL) ----------
SP=".swarm/state/STACK_PROFILE.yaml"
if [ -f "$SP" ]; then
  grep -q '^source_fingerprint:' "$SP" || err "$SP: sem source_fingerprint (detector de fatia defasada)"
  grep -q '^online_init: false' "$SP" && ! grep -A2 '^degradations:' "$SP" | grep -qE '^\s*-' && \
    err "$SP: INIT offline sem degradação declarada (degradations vazio)"
  if command -v sha256sum >/dev/null 2>&1; then
    inputs=$(grep '^fingerprint_inputs:' "$SP" | grep -oE '"[^"]+"' | tr -d '"')
    if [ -n "$inputs" ]; then
      current=$(cat $inputs 2>/dev/null | sha256sum | cut -d' ' -f1)
      stored=$(grep '^source_fingerprint:' "$SP" | sed 's/#.*//' | sed 's/.*:[[:space:]]*//' | tr -d '" ')
      [ -n "$stored" ] && [ "$current" != "$stored" ] && \
        echo "LINT WARN: $SP: source_fingerprint divergente do lockfile atual — fatias possivelmente defasadas; rode /rescan"
    fi
  fi
fi

# ---------- (fix P4) maestria REAL: o registro prova que a SONDA mediu, nao carimba ----------
#   `mastery.passed:true` virou carimbo (11 agentes passed:true com fatias de 3
#   bullets; A-013 nunca medida). A regra 13 cobra só que o token existe. Aqui:
#   (1) `specialize_mode: roundtable` exige registro da medição A-013 (mesa paga o
#       custo? ADR-F5) no STACK_PROFILE; ausente = FAIL.
#   (2) toda entrada `mastery` com `passed: true` exige `score` E `probed_at` — o
#       formato {probed_at, score, passed} do 2b.6. Sem score = sonda não mediu.
if command -v python3 >/dev/null 2>&1 && [ -f "$SP" ]; then
  python3 - <<'PY' || FAIL=1
import re
t=open(".swarm/state/STACK_PROFILE.yaml", encoding="utf-8", errors="replace").read()
bad=0
mode=re.search(r'''^\s*specialize_mode:\s*["']?([\w-]+)''', t, re.M)  # value pode vir quotado
if mode and mode.group(1).strip()=="roundtable" and not re.search(r'\bA-013\b', t):
    print("LINT FAIL: STACK_PROFILE roundtable sem registro da medicao A-013 (mesa vs single-context) — carimbo sem prova de que a mesa pagou o custo (P4/ADR-F5)")
    bad=1
# bloco mastery (até a próxima chave de topo / fim)
m=re.search(r'(?ms)^mastery:\s*\n(.*?)(?=^\S|\Z)', t)
block=m.group(1) if m else ""
def check(name, body):
    global bad
    if re.search(r'passed:\s*true', body, re.I):   # True/TRUE/true (YAML bool)
        if not re.search(r'\bscore:', body):
            print(f"LINT FAIL: mastery.{name} passed:true sem 'score' — sonda nao mediu profundidade (carimbo); 2b.6 exige {{probed_at, score, passed}} (P4)"); bad=1
        elif not re.search(r'\bprobed_at:', body):
            print(f"LINT FAIL: mastery.{name} passed:true sem 'probed_at' — sem timestamp da sonda (P4)"); bad=1
# entradas inline-flow:  "  dev-api: {…}"
seen=set()
for em in re.finditer(r'^\s{2,}([\w\-]+):\s*\{([^}]*)\}\s*$', block, re.M):
    seen.add(em.group(1)); check(em.group(1), em.group(2))
# entradas block-style:  "  dev-api:\n    passed: true\n    score: …"
lines=block.splitlines(); i=0
while i < len(lines):
    hm=re.match(r'^(\s{2,})([\w\-]+):\s*$', lines[i])
    if hm and hm.group(2) not in seen:
        indent=len(hm.group(1)); name=hm.group(2); j=i+1; sub=[]
        while j < len(lines):
            if lines[j].strip()=="": j+=1; continue
            if len(lines[j])-len(lines[j].lstrip()) > indent: sub.append(lines[j]); j+=1
            else: break
        check(name, "\n".join(sub)); i=j; continue
    i+=1
raise SystemExit(1 if bad else 0)
PY
fi

# ---------- v4: layer rules — seção Critérios idiomáticos ----------
for rd in .claude/rules .cursor/rules rules; do
  [ -d "$rd" ] || continue
  for r in "$rd"/*layer*; do
    [ -f "$r" ] || continue
    if grep -qi 'critérios idiomáticos' "$r"; then
      n=$(awk 'tolower($0) ~ /critérios idiomáticos/{flag=1; next} /^#/{flag=0} flag && /^[-*]/{c++} END{print c+0}' "$r")
      [ "$n" -lt 3 ] && err "$r: seção 'Critérios idiomáticos' com $n item(ns) (<3 — Estágio 2b)"
    else
      err "$r: layer rule sem seção 'Critérios idiomáticos' (v4, Estágio 4)"
    fi
  done
done

# ---------- (fail-closed) territorio-obrigatorio: dev-*/qa-* sem fronteira = falso-OK ----------
#   Sem `trees`/`writes_to`/`allowed_paths` no roster, os guards não escopam a escrita E os
#   gates de fronteira (cobertura-de-contexto, orchestration-map, stack-por-fronteira) PULAM
#   em silêncio → lint dá "OK" mentiroso (achado no INIT real do dev-store: roster com
#   `writes_to` que o parser não lia). Executor sem território é harness quebrado: FAIL.
if [ -f "$ROSTER" ] && command -v python3 >/dev/null 2>&1; then
  _FABLE_LIB="$SCRIPT_DIR" python3 - "$ROSTER" <<'PY' || FAIL=1
import os, sys
sys.path.insert(0, os.environ['_FABLE_LIB'])
from roster_parser import parse_roster
bad = 0
for n, t in parse_roster(sys.argv[1]).items():
    if (n.startswith("dev-") or n.startswith("qa")) and not t:
        print(f"LINT FAIL: agente '{n}' sem territorio (trees/writes_to/allowed_paths) no roster — "
              f"guards nao escopam e os gates de fronteira pulam em silencio, dando falso-OK "
              f"(territorio-obrigatorio)")
        bad = 1
sys.exit(1 if bad else 0)
PY
fi

# ---------- (§8.2) scripts-versionados: o harness sobrevive ao `git clone`? ----------
#   Se o diretório de scripts/hooks do harness cai sob um padrão do .gitignore (ex.: `bin/`
#   do .NET pega `.swarm/bin/`), o E3 (pre-commit + lint) e os guards EVAPORAM no clone/CI —
#   o enforcement se auto-exclui do versionamento. git check-ignore detecta. Não-pulável.
if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
  for d in .swarm/scripts-harness .swarm/bin; do
    [ -e "$d" ] || continue
    if git check-ignore -q "$d" 2>/dev/null; then
      err "$d esta sob .gitignore — o harness (lint + hooks E3 + guards) nao sera commitado e some no clone/CI; renomeie o diretorio OU adicione '!$d' ao .gitignore (scripts-versionados)"
    fi
  done
fi

# ---------- (A2 v6.4-restore) camadas-detectadas: projeto multi-camada tem architecture no PROFILE ----------
#   Algoritmo de sufixo (.csproj/.fsproj com Domain/Application/Infra/Core) → architecture.detected_layers.
#   Só .NET/JVM-layered; no-op para outras stacks. Reprova se o scan não detectou as camadas.
PROFILE=".swarm/state/PROJECT_PROFILE.yaml"
if [ -f "$PROFILE" ] && command -v python3 >/dev/null 2>&1; then
  python3 - "$PROFILE" <<'PY' || FAIL=1
import os, re, sys
profile = sys.argv[1]
LAYER = re.compile(r'\.(Domain|Application|Infra|Infrastructure|Core|Persistence)\b', re.I)
SKIP = {"node_modules","bin","obj",".git","dist","build","target",".venv","venv","__pycache__"}
projs = []
for dp, dirs, files in os.walk("."):
    dirs[:] = [d for d in dirs if d not in SKIP and not d.startswith(".")]
    for fn in files:
        if fn.endswith((".csproj", ".fsproj")) and LAYER.search(fn):
            projs.append(fn)
layers = set(LAYER.search(p).group(1).lower() for p in projs)
if len(projs) >= 2 and len(layers) >= 2:
    txt = open(profile, encoding="utf-8", errors="replace").read()
    if not re.search(r'^\s*(architecture|detected_layers)\s*:', txt, re.M):
        print(f"LINT FAIL: PROJECT_PROFILE sem 'architecture.detected_layers' mas o repo tem "
              f"{len(projs)} projetos multi-camada ({', '.join(sorted(layers))}) — algoritmo de "
              f"sufixo do scan nao rodou (camadas-detectadas; 01-scan Camada B / A2)")
        sys.exit(1)
sys.exit(0)
PY
fi

# ---------- (A1 v6.4-restore) orchestration-map: COMO cada fronteira circula, não só ONDE ----------
#   ARCHITECTURE_TREE dá o ONDE (centralidade/PageRank); ORCHESTRATION_MAP dá o COMO
#   (entry_points + fluxo típico). Toda fronteira de agent_trees precisa de entrada com
#   entry_points + typical_flow não-vazios (01-scan §ORCHESTRATION_MAP). Não-pulável.
OMAP=".swarm/knowledge/ORCHESTRATION_MAP.yaml"
if [ -f "$ROSTER" ] && command -v python3 >/dev/null 2>&1; then
  _FABLE_LIB="$SCRIPT_DIR" python3 - "$ROSTER" "$OMAP" <<'PY' || FAIL=1
import os, re, sys
sys.path.insert(0, os.environ['_FABLE_LIB'])
from roster_parser import parse_roster, rd
roster_path, omap_path = sys.argv[1], sys.argv[2]
frontiers = [n for n, tr in parse_roster(roster_path).items() if tr]  # só agentes com fronteira de escrita
if not frontiers:
    sys.exit(0)                                        # roster sem dev-* (fixture mínima) — nada a cobrar
if not os.path.isfile(omap_path):
    print(f"LINT FAIL: {omap_path} ausente — {len(frontiers)} fronteira(s) sem mapa de orquestracao "
          f"(entry_points + fluxo tipico); ARCHITECTURE_TREE da o ONDE, nao o COMO (orchestration-map)")
    sys.exit(1)
# blocos por '- frontier:'
blocks, cur = {}, None
for line in rd(omap_path).splitlines():
    m = re.match(r'\s*-\s*frontier:\s*(\S+)', line)
    if m:
        cur = m.group(1).strip().strip('"\''); blocks[cur] = []
    elif cur is not None:
        blocks[cur].append(line)
bad = 0
for f in frontiers:
    if f not in blocks:
        print(f"LINT FAIL: ORCHESTRATION_MAP sem entrada para a fronteira '{f}' — agente nao conhece o fluxo (orchestration-map)")
        bad = 1; continue
    lines = blocks[f]
    has_entry, in_ep = False, False
    for ln in lines:
        if re.match(r'\s*entry_points\s*:', ln): in_ep = True; continue
        if in_ep:
            if re.match(r'\s*-\s*\S', ln): has_entry = True; break
            if re.match(r'\s*\w+\s*:', ln): in_ep = False
    has_flow = any(re.match(r'\s*typical_flow\s*:\s*\S', ln) for ln in lines)
    if not has_entry:
        print(f"LINT FAIL: ORCHESTRATION_MAP['{f}'] sem entry_points (porta de entrada) — orchestration-map raso"); bad = 1
    if not has_flow:
        print(f"LINT FAIL: ORCHESTRATION_MAP['{f}'] sem typical_flow (o fluxo que o agente segue) — orchestration-map raso"); bad = 1
    # (v8) verified-flow: o marcador (inferido)/(assumido) e reprovado na varredura GLOBAL apos este loop
for _ln in rd(omap_path).splitlines():
    if re.search(r'\((?:inferido|assumido|inferred|assumed)\)', _ln, re.I):
        print(f"LINT FAIL: ORCHESTRATION_MAP marcador (inferido)/(assumido) na linha: {_ln.strip()[:80]} (orchestration-map verified-flow, v8)"); bad = 1
sys.exit(1 if bad else 0)
PY
fi

# ---------- (v9 F1) orchestration-map verdade-terreno: o fluxo cruza com o graph.json real ----------
#   v8 pegava ignorancia DECLARADA (marcador "(inferido)"). Isto pega conhecimento ERRADO-confiante,
#   cruzando contra a verdade-terreno (graph.json), nao contra a honestidade do scanner:
#     F1.1 entry_point que cita simbolo/arquivo fantasma (o CheckoutController que nao existe);
#     F1.2 depends_on para fronteira inexistente; F1.3 density afirmando arquivos numa fronteira vazia.
#   Conservador (licao v8 — nao falso-positivar): so julga tokens que PARECEM codigo e exige que
#   NENHUMA ancora do entry_point resolva para acusar. So roda com roster+OMAP+graph.json presentes.
GRAPH_TT=".swarm/knowledge/graph.json"
if [ -f "$ROSTER" ] && [ -f "$OMAP" ] && [ -f "$GRAPH_TT" ] && command -v python3 >/dev/null 2>&1; then
  _FABLE_LIB="$SCRIPT_DIR" python3 - "$ROSTER" "$OMAP" "$GRAPH_TT" <<'PY' || FAIL=1
import os, re, sys, json
sys.path.insert(0, os.environ['_FABLE_LIB'])
from roster_parser import parse_roster, rd, norm
roster = parse_roster(sys.argv[1])
frontiers = {n: tr for n, tr in roster.items() if tr}
if not frontiers:
    sys.exit(0)
try:
    g = json.load(open(sys.argv[3], encoding="utf-8", errors="replace"))
except Exception:
    sys.exit(0)                                   # graph ilegivel — outro gate cobre
files = [str(f).replace("\\", "/") for f in g.get("files", [])]
files_low = [f.lower() for f in files]
basenames = {f.rsplit("/", 1)[-1] for f in files_low}
basenoext = {b.rsplit(".", 1)[0] for b in basenames}
symbols = set()
for s in g.get("symbol_owner", {}):
    symbols.add(str(s).lower())
for syms in g.get("defs", {}).values():
    for s in syms:
        symbols.add(str(s).lower())

blocks, cur = {}, None
for line in rd(sys.argv[2]).splitlines():
    m = re.match(r'\s*-\s*frontier:\s*(\S+)', line)
    if m:
        cur = m.group(1).strip().strip('"\''); blocks[cur] = []
    elif cur is not None:
        blocks[cur].append(line)
known = set(blocks) | set(roster)

def is_anchor(tok):
    # so julga tokens que PARECEM codigo: CamelCase, com extensao, ou com _ no meio
    return bool(re.search(r'[A-Z][a-z]', tok) or re.search(r'\.[A-Za-z]{1,6}$', tok) or ('_' in tok and len(tok) > 4))

def resolves(tok):
    low = tok.lower().strip('`"\'').lstrip('/')
    base = low.rsplit('/', 1)[-1]
    stem = base.rsplit('.', 1)[0]
    if base in basenames or stem in basenames or stem in basenoext:
        return True
    if base in symbols or stem in symbols:
        return True
    if stem and len(stem) >= 4 and any(stem in f for f in files_low):
        return True
    return False

def files_under(trees):
    roots = [norm(t).lower() for t in trees if norm(t)]
    return [f for f in files_low if any(f == r or f.startswith(r + "/") for r in roots)]

bad = 0
for fr, trees in frontiers.items():
    if fr not in blocks:
        continue                                  # ausencia ja coberta pelo gate orchestration-map
    lines = blocks[fr]
    eps, in_ep = [], False
    for ln in lines:
        if re.match(r'\s*entry_points\s*:', ln):
            in_ep = True; continue
        if in_ep:
            mm = re.match(r'\s*-\s*(.+)', ln)
            if mm:
                eps.append(mm.group(1).strip())
            elif re.match(r'\s*\w+\s*:', ln):
                in_ep = False
    # F1.1 — entry_point precisa ter >=1 ancora que resolve no grafo (senao e fantasma)
    for ep in eps:
        toks = [t for t in re.findall(r'[A-Za-z_][A-Za-z0-9_./-]{2,}', ep) if is_anchor(t)]
        if toks and not any(resolves(t) for t in toks):
            print(f"LINT FAIL: ORCHESTRATION_MAP['{fr}'] entry_point nao resolve no graph.json: "
                  f"{', '.join(toks)} (simbolo/arquivo fantasma — orchestration-map verdade-terreno, v9 F1.1)")
            bad = 1
    # F1.2 — depends_on aponta para fronteira existente
    for ln in lines:
        md = re.match(r'\s*depends_on\s*:\s*\[(.*)\]', ln)
        if md:
            for d in [x.strip().strip('"\'') for x in md.group(1).split(',') if x.strip()]:
                if d not in known:
                    print(f"LINT FAIL: ORCHESTRATION_MAP['{fr}'] depends_on aponta para fronteira inexistente: "
                          f"'{d}' (dependencia fantasma — orchestration-map verdade-terreno, v9 F1.2)")
                    bad = 1
    # F1.3 — density afirmando arquivos numa fronteira que o grafo mostra vazia = fabricada
    for ln in lines:
        if re.match(r'\s*density\s*:', ln):
            mc = re.search(r'(\d+)\s*arquivo', ln)
            if mc and int(mc.group(1)) >= 1 and len(files_under(trees)) == 0:
                print(f"LINT FAIL: ORCHESTRATION_MAP['{fr}'] density afirma {mc.group(1)} arquivo(s) mas o "
                      f"graph.json mostra 0 na fronteira (trees={trees}) — contagem fabricada "
                      f"(orchestration-map verdade-terreno, v9 F1.3)")
                bad = 1
sys.exit(1 if bad else 0)
PY
fi

# ---------- (v8) integridade-de-ponteiros: todo caminho .swarm/.claude citado por kernel+agentes resolve ----------
#   Ponteiro morto (ex.: memory-cache/ inexistente citado por 15 agentes; core-spec em caminho errado)
#   faz o agente nao achar o conhecimento e cair no fallback de varredura. A regra 6 so cobre ancoras
#   de CODIGO e PULA .md/.json/.yaml — o ponteiro interno morto passava calado.
if command -v python3 >/dev/null 2>&1; then
  python3 - <<'PYPTR' || FAIL=1
import os, re, glob
bad = 0
targets = [k for k in ("CLAUDE.md","AGENTS.md",".cursor/rules/swarm-kernel.mdc") if os.path.isfile(k)]
agdir = next((d for d in (".claude/agents",".cursor/agents","agents") if os.path.isdir(d)), None)
if agdir: targets += sorted(glob.glob(os.path.join(agdir,"*.md")))
ptr = re.compile(r'(\.(?:swarm|claude|cursor)/[A-Za-z0-9_./<>-]+)')
seen = set()
memcache_cited = False
for t in targets:
    txt = open(t, encoding="utf-8", errors="replace").read()
    for m in ptr.finditer(txt):
        raw = m.group(1)
        if '<' in raw or '*' in raw: continue  # (v8) caminho templado (sprint-<N>, <este-agente>) — nao verificavel estaticamente
        p = raw.rstrip('/').rstrip('.,;:)')     # (v9) tira pontuacao final: path no fim de frase nao e ponteiro morto
        if not p: continue
        # (v9 F2.2) memory-cache e on-demand (preenchido por hook em runtime): nao exige arquivo/dir aqui;
        # a cobranca e a PRESENCA do hook produtor, verificada apos o loop.
        if 'memory-cache' in p:
            memcache_cited = True
            continue
        if (t, p) in seen: continue
        seen.add((t, p))
        base = p.rsplit('/',1)[-1]
        is_file = ('.' in base and '/' in p)
        if is_file:
            # (v9 F2.1) exige o ARQUIVO citado, nao so o diretorio — fatia de dominio/ADR/core-spec
            # faltando DENTRO de um dir existente era ponteiro morto que a v8 (so dir) deixava passar.
            if not os.path.isfile(p):
                d = p.rsplit('/',1)[0]
                why = "diretorio tambem nao existe" if not os.path.isdir(d) else f"dir '{d}/' existe, mas o arquivo nao"
                print(f"LINT FAIL: {t} cita arquivo interno inexistente: {p} ({why}) — ponteiro morto; o agente nao acha o conhecimento e re-varre (integridade-de-ponteiros, v9 F2.1)")
                bad = 1
        else:
            if not os.path.isdir(p):
                print(f"LINT FAIL: {t} cita caminho interno cujo diretorio nao existe: {p} (dir '{p}/') — ponteiro morto; o agente nao acha o conhecimento e re-varre (integridade-de-ponteiros, v8)")
                bad = 1
# (v9 F2.2) ponteiro VIVO precisa de PRODUTOR: memory-cache/ citado exige o hook inject-memory instalado —
# senao ninguem preenche o cache (bug real do dev-store: 15 agentes citavam, 0 produtor instalado).
if memcache_cited:
    hookdirs = [d for d in (".claude/hooks",".cursor/hooks","hooks") if os.path.isdir(d)]
    has_producer = any(glob.glob(os.path.join(hd,"*inject-memory*")) for hd in hookdirs)
    for cfg in (".cursor/hooks.json",".claude/settings.json",".claude/settings.local.json"):
        if os.path.isfile(cfg):
            try:
                if 'inject-memory' in open(cfg, encoding="utf-8", errors="replace").read():
                    has_producer = True
            except OSError:
                pass
    if not has_producer:
        print("LINT FAIL: memory-cache/ citado por kernel/agentes mas o hook produtor (inject-memory) nao esta "
              "instalado (.claude/hooks|.cursor/hooks|hooks.json) — ponteiro vivo sem produtor: ninguem preenche o cache (integridade-de-ponteiros, v9 F2.2)")
        bad = 1
raise SystemExit(1 if bad else 0)
PYPTR
fi

# ---------- (B1 v7.5-restore) fatia-embodida: especialista carrega o conhecimento privado no corpo ----------
#   ADR-F7 refinado: conhecimento PÚBLICO de stack fica fora (nos pesos); conhecimento
#   PRIVADO do projeto (footguns/recusas da fatia) fica EMBODIDO no §0 — senão o agente
#   chamado direto, sem brief, regride ao genérico. Especialista com fatia de domínio
#   precisa do bloco "Reconheço neste projeto" com ≥3 bullets (04-generate §2; agent-template §0).
if command -v python3 >/dev/null 2>&1; then
  _FABLE_LIB="$SCRIPT_DIR" python3 - <<'PY' || FAIL=1
import os, re, sys
sys.path.insert(0, os.environ['_FABLE_LIB'])
from roster_parser import rd
agdir = next((d for d in (".claude/agents", ".cursor/agents", "agents") if os.path.isdir(d)), None)
ddir = ".swarm/knowledge/domain"
if not agdir or not os.path.isdir(ddir):
    sys.exit(0)
bad = 0
for fn in sorted(os.listdir(agdir)):
    if not fn.endswith(".md"): continue
    name = fn[:-3]
    if not os.path.isfile(os.path.join(ddir, name + ".yaml")):
        continue   # sem fatia de domínio → não exige bloco embodido (ex.: verifier)
    body = rd(os.path.join(agdir, fn))
    m = re.search(r'(?im)^.*reconhe[cç]o\s+neste\s+projeto.*$', body)
    if not m:
        print(f"LINT FAIL: {agdir}/{fn}: especialista com fatia de dominio sem bloco 'Reconheço neste projeto' "
              f"no corpo — conhecimento privado so por ponteiro; /agente direto fica cego (fatia-embodida)")
        bad = 1; continue
    nbul = 0
    for ln in body[m.end():].splitlines():
        if re.match(r'\s*#{1,3}\s', ln): break        # próxima seção encerra o bloco
        if re.match(r'\s*[-*]\s+\S', ln): nbul += 1
    if nbul < 3:
        print(f"LINT FAIL: {agdir}/{fn}: bloco 'Reconheço neste projeto' com {nbul} bullet(s) (<3) — fatia embodida rasa (fatia-embodida)")
        bad = 1
sys.exit(1 if bad else 0)
PY
fi

# ---------- (P3.1 v7.5) cobertura-de-contexto: fronteira FUNDIDA conhece CADA contexto ----------
#   O antigo limite fixo de dev-* (aposentado na v9) fundia N contextos numa fronteira; a fatia per-fronteira dilui
#   (dev-services: ~4 entradas p/ 6 serviços). A unidade de profundidade é o CONTEXTO:
#   fronteira grande (≥80 arq) com ≥2 contextos (subpastas de produto) precisa de ≥1
#   entrada de fatia por contexto. Token de contexto = subpasta sem o prefixo comum
#   (vendor) e sem sufixo de camada. Não-pulável.
GRAPH_J=".swarm/knowledge/graph.json"
if [ -f "$ROSTER" ] && [ -f "$GRAPH_J" ] && command -v python3 >/dev/null 2>&1; then
  _FABLE_LIB="$SCRIPT_DIR" python3 - "$ROSTER" "$GRAPH_J" <<'PY' || FAIL=1
import os, re, sys, json
sys.path.insert(0, os.environ['_FABLE_LIB'])
from roster_parser import parse_roster, norm, rd
roster = parse_roster(sys.argv[1])
files = [f.replace("\\","/") for f in json.load(open(sys.argv[2])).get("files", [])]
ddir = ".swarm/knowledge/domain"
LAYER = {"api","domain","infra","infrastructure","core","application","app","web","persistence","tests","test","host","worker","grpc"}

def under(trees):
    roots = [norm(t) for t in trees if norm(t)]
    return [f for f in files if any(f == r or f.startswith(r + "/") for r in roots)], roots

def context_tokens(trees):
    fs, roots = under(trees)
    subs = {}
    for f in fs:
        for r in roots:
            if f.startswith(r + "/"):
                top = f[len(r)+1:].split("/")[0]
                if "." in top or "/" not in top:  # subpasta de produto
                    subs[top] = subs.get(top, 0) + 1
                break
    names = [s for s in subs if subs[s] >= 1]
    if len(names) < 2:
        return [], len(fs)
    segs = [s.split(".") for s in names]
    common = 0
    while all(len(g) > common + 1 for g in segs) and len({g[common] for g in segs}) == 1:
        common += 1
    toks = []
    for g in segs:
        rest = [x for x in g[common:] if x.lower() not in LAYER]
        toks.append(rest[0] if rest else g[-1])
    return toks, len(fs)

bad = 0
for name, trees in roster.items():
    if not trees:
        continue
    toks, nfiles = context_tokens(trees)
    if len(set(toks)) < 2 or nfiles < 80:   # só fronteira fundida E grande
        continue
    sf = os.path.join(ddir, name + ".yaml")
    txt = rd(sf) if os.path.isfile(sf) else ""
    for tok in sorted(set(toks)):
        if not re.search(r'\b' + re.escape(tok) + r'\b', txt, re.I):
            print(f"LINT FAIL: fatia de '{name}' nao cobre o contexto '{tok}' "
                  f"(fronteira fundida com {len(set(toks))} contextos, {nfiles} arq) — "
                  f"especialista raso desse contexto (cobertura-de-contexto; P3.1)")
            bad = 1
sys.exit(1 if bad else 0)
PY
fi

# ---------- (anti-padrão-2) anotação [En] do kernel não excede o teto da plataforma ----------
#   05-enforce §60: cada regra anota o nível REALMENTE instalado, não o desejado. Se o kernel
#   afirma [E2]/[E3] mas o CAPABILITY.yaml diz que a plataforma não tem hooks/externo, a garantia
#   é fictícia (anti-padrão 2 — [En] anunciado divergente do instalado). Antes era só prosa;
#   agora bloqueia. Nível PRIMÁRIO = 1º token E\d do bracket ([E2: x | fallback E0] → E2); claim
#   E0 nunca falha (sub-anunciar é sempre seguro). Conservador: não inspeciona níveis secundários.
CAP=".swarm/state/CAPABILITY.yaml"
if command -v python3 >/dev/null 2>&1 && [ -f "$CAP" ]; then
  python3 - "$CAP" <<'PY' || FAIL=1
import re, sys, os
cap = open(sys.argv[1], encoding="utf-8", errors="replace").read()
def flag(name):
    m = re.search(rf'^\s*{name}\s*:\s*(true|false)', cap, re.I | re.M)
    return (m.group(1).lower() == "true") if m else True   # ausente ⇒ não acusa (conservador)
caps = {"E1": flag("E1_config"), "E2": flag("E2_hooks"), "E3": flag("E3_external")}

kernel = next((k for k in ("CLAUDE.md", ".cursor/rules/swarm-kernel.mdc", "AGENTS.md")
               if os.path.isfile(k)), None)
if not kernel:
    sys.exit(0)

bad = 0
for i, line in enumerate(open(kernel, encoding="utf-8", errors="replace"), 1):
    for bracket in re.findall(r'\[E\d[^\]]*\]', line):
        lvl = "E" + re.search(r'E(\d)', bracket).group(1)   # nível primário
        if lvl in ("E1", "E2", "E3") and not caps[lvl]:
            print(f"LINT FAIL: {kernel}:{i} anota {bracket} mas CAPABILITY marca {lvl} "
                  f"indisponivel nesta plataforma — rebaixe ao nivel REALMENTE instalado "
                  f"(05-enforce passo 5; anti-padrao 2)")
            bad = 1
sys.exit(1 if bad else 0)
PY
fi

# ---------- briefs (delegado ao validate do transition) ----------
if command -v python3 >/dev/null 2>&1 && [ -d ".swarm/state/sprints" ]; then
  python3 .swarm/scripts-harness/transition.py --validate-all || FAIL=1
fi

# ---------- (v9 F2.4) validacao estrutural dos 6 YAMLs decisorios ----------
if command -v python3 >/dev/null 2>&1 && [ -d ".swarm/state" ] && [ -f "$SCRIPT_DIR/validate-state.py" ]; then
  _FABLE_LIB="$SCRIPT_DIR" python3 "$SCRIPT_DIR/validate-state.py" . || FAIL=1
fi

[ "$FAIL" = "0" ] && echo "harness-lint: OK" || echo "harness-lint: FALHOU — corrija antes de commitar"
exit $FAIL
