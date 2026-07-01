#!/usr/bin/env python3
"""repo-map.py — grafo de símbolos + âncoras rankeadas por centralidade, COM
assinaturas e boost por contexto da task (Fable v5).

Unifica o que no Encante/Fable vivia separado:
  - a árvore de Território (Seção 2 do agente): QUAIS âncoras mostrar + sua API
  - a consulta estrutural (/pesquisar-grafo)

Por que (gap "agente raso em codebase denso"): a Seção 2 precisa mostrar os
arquivos que SUSTENTAM o módulo (mais referenciados) E a **assinatura** dos seus
símbolos centrais — o agente vê a API sem abrir o arquivo (é o coração do repomap
do aider). Ranking por centralidade; boost de 10x para arquivos cujos símbolos
são citados no contexto da task (aider: identificador mencionado pesa mais).

ESTADO (v5): portável, sem dependência, RODA HOJE (`method: naive+pagerank`):
  - centralidade = **PageRank** (power-iteration, importância transitiva);
  - assinatura = linha de def, via parser textual;
  - fill por **orçamento de tokens** (`--token-budget`) ou top-N;
  - boost por contexto da task (`--boost`, 10x).
BACKEND tree-sitter (Fase 4 — IMPLEMENTADO): `build --method auto` (default) usa
tree-sitter onde a gramática está instalada e **degrada para naive POR ARQUIVO**
quando falta (declarado em `degradations`). Ganho real e testado: as referências
passam a EXCLUIR comentário/string (só nós identifier), eliminando arestas falsas
do grafo, e os símbolos são exatos em nível de método. `--method naive` força o
parser textual portátil (sem dependência); `--method tree-sitter` exige a gramática
e declara fallback. A INTERFACE CLI e a forma do `graph.json` não mudaram.

CLI:
  repo-map.py build   [--root .] [--out .swarm/knowledge/graph.json]
  repo-map.py anchors --frontier "src/Api/**" [--top 8] [--boost "Pedido status"] [--graph ...]
  repo-map.py query   "termo ou símbolo" [--top 10] [--graph ...]
"""
from __future__ import annotations
import argparse, json, os, re, sys
from collections import defaultdict, Counter

CODE_EXT = {".py", ".ts", ".tsx", ".js", ".jsx", ".cs", ".go", ".rs",
            ".java", ".kt", ".rb", ".php", ".ex", ".exs", ".swift", ".c", ".cpp", ".h"}
IGNORE_DIRS = {".git", "node_modules", "bin", "obj", "dist", "build", "vendor",
               "__pycache__", ".venv", "venv", "target", ".swarm", ".next"}
# Identificador genérico (qualquer caixa) — usado SÓ para refs; vira aresta apenas
# se for um símbolo definido em outro arquivo (interseção com sym_owner). Por isso
# pegar lowercase aqui não gera ruído: tokens comuns que não são def são descartados.
IDENT = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]{2,})\b")
# Linha de definição → assinatura. Cobre C#/TS/Java/Go/Rust/Python/JS (naive).
# Símbolo agora aceita lowercase (def foo, func bar, fn baz) — antes só PascalCase,
# o que cegava o grafo em Python/Go/JS (PM v5: 0 assinaturas no próprio repo-map.py).
DEF_LINE = re.compile(
    r"^\s*(?:export\s+|public\s+|private\s+|internal\s+|protected\s+|sealed\s+"
    r"|abstract\s+|static\s+|final\s+|pub\s+|async\s+|readonly\s+|partial\s+"
    r"|ref\s+|unsafe\s+|virtual\s+|override\s+|function\s+)*"
    r"(class|interface|struct|type|def|func|fn|record|enum|trait|module|function)"
    r"(?:\s+(?:struct|class))?"   # record struct / record class (C#)
    r"\s+([A-Za-z_][A-Za-z0-9_]+)(.*)$")

BOOST = 10  # aider: símbolo mencionado no contexto pesa ~10x


def iter_code_files(root: str):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in IGNORE_DIRS]
        for fn in filenames:
            if os.path.splitext(fn)[1] in CODE_EXT:
                yield os.path.join(dirpath, fn)


def _naive_extract(text: str, path: str):
    """Parser textual (default portátil). refs = TODO identificador, inclusive em
    comentário/string — vira aresta só se interseccionar um símbolo de dono único."""
    idents = set(IDENT.findall(text))
    local_defs, sigmap = set(), {}
    for line in text.splitlines():
        m = DEF_LINE.match(line)
        if m:
            sym = m.group(2)
            local_defs.add(sym)
            sigmap.setdefault(sym, " ".join(line.strip().split())[:120])
    base = os.path.splitext(os.path.basename(path))[0]
    if not local_defs:
        local_defs = {base}
    return local_defs, sigmap, idents


# --- backend tree-sitter (Fase 4): símbolos exatos por linguagem; refs EXCLUEM
#     comentário/string (nós não-identifier) → grafo de referência mais limpo.
#     Degrada para naive POR ARQUIVO se a gramática não estiver instalada. ---
_TS_SPEC = {
    ".py": ("tree_sitter_python", "language"),
    ".js": ("tree_sitter_javascript", "language"), ".jsx": ("tree_sitter_javascript", "language"),
    ".ts": ("tree_sitter_typescript", "language_typescript"),
    ".tsx": ("tree_sitter_typescript", "language_tsx"),
    ".cs": ("tree_sitter_c_sharp", "language"),
    ".go": ("tree_sitter_go", "language"), ".rs": ("tree_sitter_rust", "language"),
    ".java": ("tree_sitter_java", "language"), ".kt": ("tree_sitter_kotlin", "language"),
    ".rb": ("tree_sitter_ruby", "language"), ".php": ("tree_sitter_php", "language_php"),
    ".c": ("tree_sitter_c", "language"), ".cpp": ("tree_sitter_cpp", "language"),
    ".h": ("tree_sitter_cpp", "language"), ".swift": ("tree_sitter_swift", "language"),
}
_TS_CACHE: dict = {}
_REF_NODE_TYPES = {"identifier", "type_identifier", "field_identifier", "scoped_identifier"}
_IDENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]{2,}$")


def _load_ts_language(ext: str):
    if ext in _TS_CACHE:
        return _TS_CACHE[ext]
    lang = None
    spec = _TS_SPEC.get(ext)
    if spec:
        mod_name, fn = spec
        try:
            from tree_sitter import Language
            mod = __import__(mod_name)
            lang = Language(getattr(mod, fn)())
        except Exception:
            lang = None
    _TS_CACHE[ext] = lang
    return lang


def _ts_extract(text: str, path: str):
    """(defs, sigs, refs) via tree-sitter, ou None se a gramática faltar/falhar."""
    ext = os.path.splitext(path)[1]
    lang = _load_ts_language(ext)
    if lang is None:
        return None
    try:
        from tree_sitter import Parser
        try:
            parser = Parser(lang)
        except TypeError:
            parser = Parser(); parser.language = lang
        tree = parser.parse(bytes(text, "utf-8"))
    except Exception:
        return None
    src = text.encode("utf-8")

    def ntext(n):
        return src[n.start_byte:n.end_byte].decode("utf-8", "ignore")

    defs, sigs, refs = set(), {}, set()
    stack = [tree.root_node]
    while stack:
        n = stack.pop()
        t = n.type
        if t.endswith(("definition", "declaration")):
            name = n.child_by_field_name("name")
            if name is not None:
                sym = ntext(name)
                if sym:
                    defs.add(sym)
                    first = (ntext(n).splitlines() or [""])[0].strip()
                    sigs.setdefault(sym, " ".join(first.split())[:120])
        if t in _REF_NODE_TYPES:
            txt = ntext(n)
            if _IDENT_RE.match(txt or ""):
                refs.add(txt)
        for c in n.children:
            stack.append(c)
    base = os.path.splitext(os.path.basename(path))[0]
    if not defs:
        defs = {base}
    return defs, sigs, refs


def _assemble(defs, sigs, refs, root, method, degradations):
    # Dono de símbolo só para nomes quase-únicos: um nome definido em muitos
    # arquivos (main, build, handler…) tem dono ambíguo e geraria centralidade
    # falsa — fica de fora. Result/Error/Pedido (def única) sobrevivem.
    defcount = Counter(s for dset in defs.values() for s in dset)
    sym_owner: dict[str, str] = {}
    for rel, dset in defs.items():
        for s in dset:
            if defcount[s] <= 2 and len(s) >= 3:
                sym_owner.setdefault(s, rel)

    indeg: dict[str, int] = defaultdict(int)
    out_edges: dict[str, set] = defaultdict(set)   # arquivo → arquivos que ele referencia
    for rel, rset in refs.items():
        for s in rset:
            owner = sym_owner.get(s)
            if owner and owner != rel:
                indeg[owner] += 1
                out_edges[rel].add(owner)

    pr = pagerank(list(defs.keys()), out_edges)
    g = {
        "method": method,
        "root": root,
        "files": sorted(defs.keys()),
        "defs": {k: sorted(v) for k, v in defs.items()},
        "signatures": sigs,
        "indegree": dict(indeg),
        "pagerank": pr,
        "symbol_owner": sym_owner,
    }
    if degradations:
        g["degradations"] = sorted(degradations)
    return g


def build_graph(root: str, method: str = "auto") -> dict:
    """method: auto (tree-sitter onde houver gramática, senão naive) | naive | tree-sitter."""
    defs: dict[str, set] = {}
    sigs: dict[str, dict] = {}
    refs: dict[str, set] = {}
    used_ts = used_naive = False
    degradations = []
    for path in iter_code_files(root):
        try:
            text = open(path, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        rel = os.path.relpath(path, root)
        res = _ts_extract(text, path) if method in ("auto", "tree-sitter") else None
        if res is None:
            if method == "tree-sitter":
                degradations.append(rel)   # pedida tree-sitter mas gramática ausente
            res = _naive_extract(text, path)
            used_naive = True
        else:
            used_ts = True
        defs[rel], sigs[rel], refs[rel] = res

    if method == "naive":
        label = "naive+pagerank"
    elif used_ts and used_naive:
        label = "tree-sitter+naive+pagerank"
    elif used_ts:
        label = "tree-sitter+pagerank"
    else:
        label = "naive+pagerank"
    return _assemble(defs, sigs, refs, root, label, degradations)


def pagerank(nodes, out_edges, d=0.85, iters=50):
    """PageRank por power-iteration (puro Python). Importância transitiva: ser
    referenciado por um arquivo central pesa mais que por um periférico.
    Mais fiel que in-degree para escolher a âncora que SUSTENTA o módulo."""
    n = len(nodes)
    if n == 0:
        return {}
    pr = {x: 1.0 / n for x in nodes}
    base = (1 - d) / n
    for _ in range(iters):
        nxt = {x: base for x in nodes}
        dangling = 0.0
        for src in nodes:
            dests = out_edges.get(src)
            if dests:
                share = d * pr[src] / len(dests)
                for dst in dests:
                    nxt[dst] += share
            else:
                dangling += d * pr[src] / n   # massa de nós sem saída, redistribuída
        if dangling:
            for x in nodes:
                nxt[x] += dangling
        pr = nxt
    return pr


def _in_frontier(rel: str, frontier: str) -> bool:
    import fnmatch
    fr = frontier.rstrip("*").rstrip("/")
    return rel.startswith(fr) or fnmatch.fnmatch(rel, frontier)


def _file_terms(graph, f):
    return (f + " " + " ".join(graph["defs"].get(f, []))).lower()


def _est_tokens(file: str, sigs_list) -> int:
    # estimativa barata: ~4 chars/token (regra de bolso). Inclui path + assinaturas.
    chars = len(file) + sum(len(s) for s in sigs_list) + 8
    return max(1, chars // 4)


def anchors(graph: dict, frontier: str, top: int, boost=None, token_budget: int = 0):
    indeg = graph["indegree"]
    pr = graph.get("pagerank", {})
    sigs = graph.get("signatures", {})
    terms = [t.lower() for t in (boost or []) if len(t) >= 3]
    files = [f for f in graph["files"] if _in_frontier(f, frontier)]

    def score(f):
        s = pr.get(f, 0.0)             # centralidade transitiva (PageRank)
        if terms and any(t in _file_terms(graph, f) for t in terms):
            s = s * BOOST              # boost por contexto da task (aider 10x)
        return s

    ranked = sorted(files, key=lambda f: (-score(f), -indeg.get(f, 0), f))

    out, spent = [], 0
    for f in ranked:
        sl = list(sigs.get(f, {}).values())[:2]
        cost = _est_tokens(f, sl)
        # orçamento de tokens vence o top-N quando definido (fill em ordem de rank)
        if token_budget and out and spent + cost > token_budget:
            break
        if not token_budget and len(out) >= top:
            break
        out.append({
            "file": f,
            "centrality": indeg.get(f, 0),         # nº de arquivos que o referenciam (legível)
            "pagerank": round(pr.get(f, 0.0), 5),  # ordenação real
            "boosted": bool(terms and any(t in _file_terms(graph, f) for t in terms)),
            "signatures": sl,                       # a API, sem abrir o arquivo
            "est_tokens": cost,
        })
        spent += cost
    fill = (f"orçamento {token_budget} tokens (gastos ~{spent})" if token_budget
            else f"top {min(top, len(files))}")
    return {
        "method": graph["method"],
        "frontier": frontier,
        "boost_terms": terms,
        "total_files": len(files),     # alimenta o "(+N arquivos)" REAL da Seção 2
        "anchors": out,
        "note": f"{len(files)} arquivos na fronteira; {fill} por PageRank"
                + (" (com boost de contexto)" if terms else ""),
    }


def query(graph: dict, term: str, top: int):
    t = term.lower()
    sigs = graph.get("signatures", {})
    hits = []
    for f in graph["files"]:
        matched = [s for s in graph["defs"].get(f, []) if t in s.lower()]
        if t in f.lower() or matched:
            hits.append({
                "file": f,
                "centrality": graph["indegree"].get(f, 0),
                "symbols": matched,
                "signatures": [sigs.get(f, {}).get(s, s) for s in matched][:3],
            })
    pr = graph.get("pagerank", {})
    hits.sort(key=lambda h: (-pr.get(h["file"], 0.0), -h["centrality"], h["file"]))
    return {"term": term, "results": hits[:top]}


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build"); b.add_argument("--root", default="."); b.add_argument("--out", default=".swarm/knowledge/graph.json"); b.add_argument("--method", default="auto", choices=["auto", "naive", "tree-sitter"])
    a = sub.add_parser("anchors"); a.add_argument("--frontier", required=True); a.add_argument("--top", type=int, default=8); a.add_argument("--boost", default=""); a.add_argument("--token-budget", type=int, default=0); a.add_argument("--graph", default=".swarm/knowledge/graph.json")
    q = sub.add_parser("query"); q.add_argument("term"); q.add_argument("--top", type=int, default=10); q.add_argument("--graph", default=".swarm/knowledge/graph.json")
    args = ap.parse_args()

    if args.cmd == "build":
        g = build_graph(args.root, args.method)
        os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
        json.dump(g, open(args.out, "w"), indent=2)
        nsig = sum(len(v) for v in g["signatures"].values())
        deg = g.get("degradations")
        degnote = f", {len(deg)} arquivo(s) em fallback naive" if deg else ""
        print(f"graph: {len(g['files'])} arquivos, {nsig} assinaturas, method={g['method']}{degnote} → {args.out}")
        return
    g = json.load(open(args.graph))
    if args.cmd == "anchors":
        out = anchors(g, args.frontier, args.top, boost=args.boost.replace(",", " ").split(),
                      token_budget=args.token_budget)
    else:
        out = query(g, args.term, args.top)
    print(json.dumps(out, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    sys.exit(main())
