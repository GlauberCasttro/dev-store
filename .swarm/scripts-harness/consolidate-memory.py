#!/usr/bin/env python3
"""consolidate-memory.py — o passe de consolidação (episódica → semântica).

A analogia do "sono": experiências episódicas (events.jsonl) consolidam em
conhecimento semântico (lições) em lote, na fronteira de sprint. Não é o Curator
destilando a narrativa da sessão — é minerar o histórico ESTRUTURADO de falhas e
abstrair o padrão recorrente, COM os episódios como evidência.

Read-only: PROPÕE lições candidatas (validated:false) no stdout. Quem escreve o
store é o Curator/humano (anti-padrão 24). Também propõe DECAY de lições cuja
evidência sumiu — esquecer é parte do aprender.

Uso:
  consolidate-memory.py [--events PATH] [--store PATH] [--min N] [--stale-sprints N]
  default: .swarm/state/sprints/*/events.jsonl  +  .swarm/knowledge/memory/conhecimento.jsonl
"""
from __future__ import annotations
import argparse, json, glob, os, sys, re
from collections import defaultdict


def load_events(paths):
    evs = []
    for p in paths:
        try:
            for line in open(p, encoding="utf-8"):
                line = line.strip()
                if line:
                    try: evs.append(json.loads(line))
                    except json.JSONDecodeError: pass
        except OSError:
            pass
    return evs


def mine(events, min_count):
    """Padrões recorrentes de rejeição por (agente, motivo) → lições candidatas."""
    task_agent = {}
    for e in events:
        if e.get("type") == "task.dispatched" and e.get("task") and e.get("agent"):
            task_agent.setdefault(e["task"], e["agent"])
    # agrupar rejeições por (agente, motivo); guardar tasks como evidência
    groups = defaultdict(list)
    for e in events:
        if e.get("type") == "task.rejected":
            agent = task_agent.get(e.get("task"), "shared")
            reason = (e.get("reason") or "unspecified").strip()
            groups[(agent, reason)].append(e.get("task"))
    candidates = []
    seq = 1
    for (agent, reason), tasks in sorted(groups.items(), key=lambda kv: -len(kv[1])):
        uniq = sorted(set(t for t in tasks if t))
        if len(tasks) < min_count:
            continue
        kw = [w for w in re.split(r"[^a-z0-9]+", reason.lower()) if len(w) >= 3]
        candidates.append({
            "id": f"CONS-{seq}",
            "text": f"recorrente: {agent} rejeitado {len(tasks)}x por '{reason}' — tratar antes de submeter",
            "detail": f"Padrão minerado de events.jsonl. Episódios: {', '.join(uniq)}. "
                      f"Promover a lição/critério de aceite se ainda recorre.",
            "applies_to": list(dict.fromkeys([agent, *kw])),
            "agent": agent,
            "validated": False,                 # candidato — curadoria humana decide
            "source": "consolidation:events.jsonl",
            "evidence": uniq,                   # episódios que sustentam a lição
            "occurrences": len(tasks),
        })
        seq += 1
    return candidates


def decay(store_path, stale_sprints):
    """Lições cuja evidência sumiu (nunca consultadas, score baixo) → propor decay."""
    props = []
    try:
        lines = [l for l in open(store_path, encoding="utf-8") if l.strip()]
    except OSError:
        return props
    for l in lines:
        try: e = json.loads(l)
        except json.JSONDecodeError: continue
        if e.get("superseded_by"):
            continue
        consultado = e.get("consultado_em")
        score = e.get("score", 1)
        # heurística conservadora: nunca consultada E score mínimo ⇒ candidata a decay
        if (consultado in (None, "", "null")) and score <= 1 and e.get("validated"):
            props.append({"id": e.get("id"), "action": "decay",
                          "reason": "nunca consultada e score mínimo — evidência de uso ausente"})
    return props


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--events", default="")
    ap.add_argument("--store", default=".swarm/knowledge/memory/conhecimento.jsonl")
    ap.add_argument("--min", type=int, default=2)
    ap.add_argument("--stale-sprints", type=int, default=3)
    a = ap.parse_args()

    ev_paths = [a.events] if a.events else glob.glob(".swarm/state/sprints/*/events.jsonl")
    events = load_events(ev_paths)
    candidates = mine(events, a.min)
    decays = decay(a.store, a.stale_sprints)

    out = {
        "consolidation_candidates": candidates,   # lições novas (validated:false)
        "decay_proposals": decays,                # lições a aposentar
        "summary": f"{len(candidates)} lição(ões) candidata(s) de {len(events)} eventos; "
                   f"{len(decays)} proposta(s) de decay. Curadoria humana decide (anti-padrão 24).",
    }
    print(json.dumps(out, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    sys.exit(main())
