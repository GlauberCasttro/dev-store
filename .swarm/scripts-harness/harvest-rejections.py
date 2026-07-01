#!/usr/bin/env python3
"""harvest-rejections.py — ciclo de aprendizado (Fase 1 da camada de epistemologia).

Cada REJECT do verifier é a prova mais forte de um buraco de especializacao. Hoje
isso vira so memoria (conhecimento.jsonl); este script transforma em CANDIDATO de
fatia de dominio (knowledge/domain/<agent>.yaml), o lugar certo da especializacao.

Le os briefs (gate_report persistido pelo transition.py --gate) na arvore canonica
de sprints, extrai os criterios REPROVADOS (pass:false, com proof) de cada
gate_report FAIL, e PROPOE entradas `kind: lesson` (confidence: unverified,
source = task+gate). NAO auto-escreve — apresenta para curadoria, mesma disciplina
do consolidate-memory. Dedup por id contra a fatia existente.

Uso:  harvest-rejections.py            # imprime candidatos agrupados por agente
Env:  SWARM_ROOT (default ".")
"""
import glob
import json
import os
import sys

ROOT = os.environ.get("SWARM_ROOT", ".")
STATE = os.path.join(ROOT, ".swarm", "state")
DOMAIN = os.path.join(ROOT, ".swarm", "knowledge", "domain")


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def briefs():
    return sorted(glob.glob(os.path.join(STATE, "sprints", "*", "tasks", "*.json")))


def existing_ids(agent):
    ids = set()
    p = os.path.join(DOMAIN, f"{agent}.yaml")
    if os.path.exists(p):
        try:
            for line in open(p, encoding="utf-8"):
                s = line.strip()
                if s.startswith("- id:"):
                    ids.add(s.split(":", 1)[1].strip().strip('"'))
        except OSError:
            pass
    return ids


def slug(text, n=70):
    return " ".join(str(text).split())[:n]


def candidates():
    """Lista de (agent, entry-dict) derivada de cada criterio reprovado."""
    out = []
    for bp in briefs():
        b = load(bp)
        if not b:
            continue
        gr = b.get("gate_report") or {}
        if gr.get("verdict") != "FAIL":
            continue
        agent = b.get("agent") or "shared"
        tid = b.get("id") or os.path.basename(bp)
        seq = 0
        for c in (gr.get("criteria") or []):
            if c.get("pass") is True:
                continue
            seq += 1
            crit = c.get("criterion") or c.get("name") or c.get("proof") or "criterio sem nome"
            proof = c.get("proof") or crit
            out.append((agent, {
                "id": f"DOMAIN-{agent.upper()}-R{tid}-{seq}",
                "kind": "lesson",
                "claim": f"Licao de rejeicao: {slug(crit)}",
                "applies_to": f"{agent} - {tid}",
                "source": f"{tid} gate FAIL",
                "confidence": "unverified",
                "check": slug(proof, 140),
            }))
    return out


def to_yaml(entry):
    lines = [f"- id: {entry['id']}"]
    for k in ("kind", "claim", "applies_to", "source", "confidence", "check"):
        v = str(entry[k]).replace('"', "'")
        lines.append(f'  {k}: "{v}"')
    return "\n".join(lines)


def main():
    fresh = [(a, e) for (a, e) in candidates() if e["id"] not in existing_ids(a)]
    if not fresh:
        print("[fable harvest] nenhuma rejeicao nova para destilar.")
        return
    print(f"[fable harvest] {len(fresh)} candidato(s) de fatia de dominio "
          f"(curadoria aplica em knowledge/domain/<agent>.yaml; nada e auto-escrito):\n")
    by_agent = {}
    for agent, e in fresh:
        by_agent.setdefault(agent, []).append(e)
    for agent, entries in by_agent.items():
        print(f"# -> .swarm/knowledge/domain/{agent}.yaml")
        for e in entries:
            print(to_yaml(e))
        print()


if __name__ == "__main__":
    main()
