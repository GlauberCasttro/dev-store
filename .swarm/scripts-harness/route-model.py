#!/usr/bin/env python3
"""route-model.py — roteia a task para um TIER de modelo por complexidade (economia de
token — gap d). Heurística léxica por padrão; **bandit Thompson** assume quando já
aprendeu (estado em `learning.db`, tabela `model_router`). Carimba `routedBy`
(proveniência: heuristic | bandit). Stdlib pura, FAIL-SAFE.

Uso:
  route-model.py "<descrição da task>"                          -> tier + routedBy
  route-model.py --outcome success --bucket high --tier strong  -> atualiza o bandit
"""
import sys, os, re, sqlite3, random

TIERS = ["cheap", "mid", "strong"]
BUCKET_TIER = {"low": "cheap", "med": "mid", "high": "strong"}
HIGH = re.compile(r"\b(refactor|migration|migrar|saga|security|seguran\w*|concurren\w*|"
                  r"distribu\w*|arquitetura|architecture|schema|contrato|contract|auth)\b", re.I)
LOW = re.compile(r"\b(typo|rename|renomear|comment|coment\w*|format|lint|docstring|readme|bump)\b", re.I)


def complexity_bucket(task):
    t = task or ""
    if LOW.search(t) and not HIGH.search(t):
        return "low"
    if HIGH.search(t):
        return "high"
    n = len(re.findall(r"\w+", t))
    return "high" if n > 40 else ("low" if n < 8 else "med")


def db_path():
    root = os.environ.get("SWARM_ROOT", ".")
    return os.environ.get("FABLE_LEARNING_DB", os.path.join(root, ".swarm", "state", "learning.db"))


def _connect():
    db = db_path()
    if not os.path.exists(db):
        return None
    c = sqlite3.connect(db)
    c.execute("CREATE TABLE IF NOT EXISTS model_router(bucket TEXT, tier TEXT, "
              "alpha REAL DEFAULT 1, beta REAL DEFAULT 1, PRIMARY KEY(bucket, tier))")
    return c


def bandit_pick(bucket):
    """Thompson sampling sobre os tiers; None se sem db OU sem aprendizado (usa heurística)."""
    try:
        c = _connect()
        if c is None:
            return None
        learned = c.execute("SELECT count(*) FROM model_router WHERE bucket=? AND (alpha<>1 OR beta<>1)",
                            (bucket,)).fetchone()[0]
        if not learned:
            return None
        best, best_s = None, -1.0
        for tier in TIERS:
            row = c.execute("SELECT alpha,beta FROM model_router WHERE bucket=? AND tier=?", (bucket, tier)).fetchone()
            a, b = row if row else (1.0, 1.0)
            s = random.betavariate(a, b)
            if s > best_s:
                best, best_s = tier, s
        return best
    except Exception:
        return None


def record(bucket, tier, outcome):
    try:
        c = _connect()
        if c is None:
            return
        c.execute("INSERT OR IGNORE INTO model_router(bucket,tier) VALUES(?,?)", (bucket, tier))
        col = "alpha" if outcome == "success" else "beta"
        c.execute(f"UPDATE model_router SET {col}={col}+1 WHERE bucket=? AND tier=?", (bucket, tier))
        c.commit()
    except Exception:
        pass


def main():
    args = sys.argv[1:]
    if "--outcome" in args:
        o = args[args.index("--outcome") + 1]
        bucket = args[args.index("--bucket") + 1] if "--bucket" in args else "med"
        tier = args[args.index("--tier") + 1] if "--tier" in args else BUCKET_TIER[bucket]
        record(bucket, tier, o)
        print(f"router: {bucket}/{tier} <- {o}")
        return
    task = args[0] if args else ""
    bucket = complexity_bucket(task)
    picked = bandit_pick(bucket)
    tier = picked or BUCKET_TIER[bucket]
    print(f"tier={tier}  bucket={bucket}  routedBy={'bandit' if picked else 'heuristic'}")


if __name__ == "__main__":
    main()
