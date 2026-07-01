#!/usr/bin/env python3
"""seed-learning.py — (re)constrói o learning.db a partir das FONTES QUE VIAJAM com o
projeto: (1) o codebase — fatias de domínio derivadas (.swarm/knowledge/domain/*.yaml) —
e (2) os patterns EARNED em texto commitado (.swarm/knowledge/learned/earned-patterns.jsonl).
NADA hardcoded. O learning.db é índice DERIVADO (gitignored); num clone novo, este script
reconstrói a memória inteira de código + texto. Stdlib pura.
Uso: seed-learning.py <knowledge_dir> <db_path>"""
import sys, os, re, sqlite3, glob, json

CONF = {"verified": 0.85, "declared": 0.60, "assumed": 0.40}


def parse_list_yaml(path):
    """parser stdlib-pure para YAML 'lista de dicts flat' (- chave: valor)."""
    recs, cur = [], None
    for raw in open(path, encoding="utf-8"):
        m = re.match(r"\s*-\s+(\w+):\s*(.*)", raw)
        if m:
            if cur:
                recs.append(cur)
            cur = {m.group(1): m.group(2).strip().strip('"')}
            continue
        m = re.match(r"\s+(\w+):\s*(.*)", raw)
        if m and cur is not None:
            cur[m.group(1)] = m.group(2).strip().strip('"')
    if cur:
        recs.append(cur)
    return recs


def derive(kdir):
    """lê as fatias de domínio DERIVADAS do código e projeta patterns (com source→código)."""
    pats = []
    for f in sorted(glob.glob(os.path.join(kdir, "domain", "*.yaml"))):
        agent = os.path.splitext(os.path.basename(f))[0]
        for r in parse_list_yaml(f):
            claim = r.get("claim")
            if not claim:
                continue
            pats.append({"agent": agent,
                         "condition": r.get("check") or r.get("applies_to") or claim,
                         "action": claim,
                         "confidence": CONF.get(r.get("confidence", "declared"), 0.6),
                         "provenance": "derived:" + r.get("source", "?"),
                         "kind": r.get("kind", "")})
    # (v11 gap#1) invariantes de produto -> patterns 'shared' (cross-cutting; valem p/ qualquer agente)
    inv = os.path.join(kdir, "DOMAIN_INVARIANTS.yaml")
    if os.path.exists(inv):
        for r in parse_list_yaml(inv):
            claim = r.get("invariant")
            if not claim:
                continue
            pats.append({"agent": "shared",
                         "condition": "tocar " + (r.get("evidence") or claim),
                         "action": "respeitar invariante: " + claim,
                         "confidence": 0.85,
                         "provenance": "derived:DOMAIN_INVARIANTS.yaml " + r.get("id", ""),
                         "kind": "invariant"})
    # (v11 gap#1) centralidade do grafo -> âncoras 'shared' (ler antes de mudar o hub)
    gpath = os.path.join(kdir, "graph.json")
    if os.path.exists(gpath):
        try:
            g = json.load(open(gpath, encoding="utf-8"))
            central = g.get("indegree") or g.get("pagerank") or g.get("files") or []
            if isinstance(central, dict):  # indegree/pagerank pode vir como {arquivo: score}
                central = [k for k, _ in sorted(central.items(),
                           key=lambda kv: kv[1] if isinstance(kv[1], (int, float)) else 0, reverse=True)]
            for path in central[:5]:
                pats.append({"agent": "shared",
                             "condition": "tocar " + path,
                             "action": "arquivo de alta centralidade — ler antes de mudar (hub/porta)",
                             "confidence": 0.60,
                             "provenance": "derived:graph.json centrality",
                             "kind": "anchor"})
        except Exception:
            pass
    return pats


def earned_file(db):
    return os.path.normpath(os.path.join(os.path.dirname(db), "..", "knowledge", "learned", "earned-patterns.jsonl"))


def load_earned(c, db):
    """carrega os patterns EARNED do texto commitado — é o que VIAJA com o projeto."""
    ep = earned_file(db)
    if not os.path.exists(ep):
        return 0
    n = 0
    for line in open(ep, encoding="utf-8"):
        line = line.strip()
        if not line:
            continue
        try:
            r = json.loads(line)
        except Exception:
            continue
        c.execute("INSERT INTO patterns(agent,condition,action,confidence,provenance,kind) VALUES(?,?,?,?,?,?)",
                  (r.get("agent"), r.get("condition"), r.get("action"), r.get("confidence", 0.55),
                   r.get("provenance", "earned:trajectory"), r.get("kind", "earned")))
        n += 1
    return n


def main():
    kdir, db = sys.argv[1], sys.argv[2]
    pats = derive(kdir)
    c = sqlite3.connect(db)
    c.execute("CREATE TABLE IF NOT EXISTS patterns(id INTEGER PRIMARY KEY AUTOINCREMENT, "
              "agent, condition, action, confidence REAL, success INTEGER DEFAULT 0, "
              "failure INTEGER DEFAULT 0, provenance, kind)")
    # re-seed idempotente: o db = derivado(código) + earned(texto commitado), ambos reconstruíveis
    c.execute("DELETE FROM patterns WHERE provenance LIKE 'derived:%' OR provenance LIKE 'earned:%'")
    for p in pats:
        c.execute("INSERT INTO patterns(agent,condition,action,confidence,provenance,kind) VALUES(?,?,?,?,?,?)",
                  (p["agent"], p["condition"], p["action"], p["confidence"], p["provenance"], p["kind"]))
    n_earned = load_earned(c, db)
    c.commit()
    print(f"reconstruído {db}: {len(pats)} derivados (do código) + {n_earned} earned (texto commitado)")


if __name__ == "__main__":
    main()
