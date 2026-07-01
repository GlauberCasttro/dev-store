#!/usr/bin/env python3
"""distill-learning.py — destila trajetórias de SUCESSO em patterns (episódico→semântico).
Roda no /fechar-sprint. Reforça o pattern do agente que casa, ou cria um 'earned' NOVO.

Patterns earned são gravados TAMBÉM em texto commitado
(.swarm/knowledge/learned/earned-patterns.jsonl) — é o que VIAJA com o projeto e com o
time (o learning.db é índice gitignored). Idempotente, stdlib pura, FAIL-SAFE.
Uso: distill-learning.py [db]"""
import sys, os, re, sqlite3, json


def tok(s):
    return set(re.findall(r"\w+", (s or "").lower(), re.UNICODE))


def col_exists(c, table, col):
    try:
        return any(r[1] == col for r in c.execute(f"PRAGMA table_info({table})"))
    except Exception:
        return False


def earned_file(db):
    # learning.db mora em .swarm/state/ ; o texto earned mora em .swarm/knowledge/learned/ (commitado)
    return os.path.normpath(os.path.join(os.path.dirname(db), "..", "knowledge", "learned", "earned-patterns.jsonl"))


def append_earned(db, rec):
    ep = earned_file(db)
    os.makedirs(os.path.dirname(ep), exist_ok=True)
    with open(ep, "a", encoding="utf-8") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")


def main():
    root = os.environ.get("SWARM_ROOT", ".")
    db = sys.argv[1] if len(sys.argv) > 1 else os.environ.get(
        "FABLE_LEARNING_DB", os.path.join(root, ".swarm", "state", "learning.db"))
    if not os.path.exists(db):
        return
    try:
        c = sqlite3.connect(db)
        c.execute("CREATE TABLE IF NOT EXISTS patterns(id INTEGER PRIMARY KEY AUTOINCREMENT, "
                  "agent, condition, action, confidence REAL, success INTEGER DEFAULT 0, "
                  "failure INTEGER DEFAULT 0, provenance, kind)")
        if not col_exists(c, "trajectories", "distilled"):
            c.execute("ALTER TABLE trajectories ADD COLUMN distilled INTEGER DEFAULT 0")
        trs = c.execute("SELECT id, agent, task FROM trajectories "
                        "WHERE verdict = 'success' AND COALESCE(distilled, 0) = 0").fetchall()
    except Exception:
        return
    reinforced = created = 0
    for tid, agent, task in trs:
        best = None
        for pid, cond in c.execute("SELECT id, condition FROM patterns WHERE agent = ?", (agent,)):
            if len(tok(task) & tok(cond)) >= 2:
                best = pid
                break
        if best is not None:
            c.execute("UPDATE patterns SET confidence = min(1.0, confidence + 0.1), "
                      "success = success + 1 WHERE id = ?", (best,))
            reinforced += 1
        else:
            rec = {"agent": agent, "condition": task, "action": task, "confidence": 0.55,
                   "provenance": "earned:trajectory", "kind": "earned"}
            c.execute("INSERT INTO patterns(agent,condition,action,confidence,success,provenance,kind) "
                      "VALUES(?,?,?,?,1,?,?)", (rec["agent"], rec["condition"], rec["action"],
                                               rec["confidence"], rec["provenance"], rec["kind"]))
            try:
                append_earned(db, rec)   # (v11) grava no TEXTO commitado que viaja com o projeto
            except Exception:
                pass
            created += 1
        c.execute("UPDATE trajectories SET distilled = 1 WHERE id = ?", (tid,))
    c.commit()
    print(f"destiladas {len(trs)} trajetórias: {reinforced} reforços, {created} earned "
          f"(gravados no learning.db + earned-patterns.jsonl commitado)")


if __name__ == "__main__":
    main()
