#!/usr/bin/env python3
"""recall-learning.py — recupera patterns do learning.db para um agente + task.
Filtra pelo agente, rankeia por relevância × confiança, emite bloco markdown pronto
para o §4 do cartão. Stdlib pura, FAIL-SAFE: sem db => sem saída (hook segue igual v9).
Uso: recall-learning.py "<descrição da task>" <agente> [k]"""
import sys, os, re, sqlite3


def tok(s):
    return set(re.findall(r"\w+", (s or "").lower(), re.UNICODE))


def main():
    task = sys.argv[1] if len(sys.argv) > 1 else ""
    agent = sys.argv[2] if len(sys.argv) > 2 else "all"
    k = int(sys.argv[3]) if len(sys.argv) > 3 else 3
    root = os.environ.get("SWARM_ROOT", ".")
    db = os.environ.get("FABLE_LEARNING_DB", os.path.join(root, ".swarm", "state", "learning.db"))
    if not os.path.exists(db):
        return
    try:
        c = sqlite3.connect(db)
        rows = c.execute(
            "SELECT agent, condition, action, confidence, provenance FROM patterns "
            "WHERE agent = ? OR agent = 'shared' OR ? = 'all'", (agent, agent)).fetchall()
    except Exception:
        return  # store corrompido/indisponível => degrada silenciosamente
    tt = tok(task)
    scored = []
    for ag, cond, act, conf, prov in rows:
        ov = len(tt & tok(cond))
        if ov:
            scored.append(((ov / max(1, len(tt))) * (conf or 0.5), cond, act, conf, prov))
    if not scored:
        return
    scored.sort(reverse=True)
    print("## Padrões aprendidos (learning.db — derivado do codebase + trajetórias)")
    for s, cond, act, conf, prov in scored[:k]:
        print(f"- **{act}**  ·  quando: {cond}  ·  conf {conf:.2f}  ·  _{prov}_")


if __name__ == "__main__":
    main()
