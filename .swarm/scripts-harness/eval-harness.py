#!/usr/bin/env python3
"""eval-harness.py — Fase 5: prova (ADR-F5) que harness-LIGADO bate modelo-PURO,
por agente. Separa explicitamente duas coisas:

  1) PRODUCAO de resultados (passo de AMBIENTE, precisa do runtime do agente):
     rodar cada task de controle 2x — mode 'on' (com fatia/brief) e mode 'off'
     (modelo nu) — e coletar {task, agent, mode, verdict, attempts, lead_ms}.
     Orquestrado pelo comando /benchmark-harness; pode sair de gate.report events.

  2) SCORE (este script — deterministico, testavel SEM LLM): consome o results.json
     e emite o comparativo on x off por agente + veredito de retirada (ADR-F5:
     componente que nao paga o custo sai).

Uso:  eval-harness.py --results results.json [--min-gain 0.10] [--strict] [--json]
"""
import argparse
import json
import os
import re
import sys
from collections import defaultdict


def rate(rows, mode):
    sub = [r for r in rows if r.get("mode") == mode]
    if not sub:
        return None
    passed = sum(1 for r in sub if str(r.get("verdict", "")).upper() == "PASS")
    return passed / len(sub)


def avg(rows, mode, key):
    sub = [r for r in rows if r.get("mode") == mode and isinstance(r.get(key), (int, float))]
    return (sum(r[key] for r in sub) / len(sub)) if sub else None


def evaluate(results, min_gain):
    by_agent = defaultdict(list)
    for r in results:
        by_agent[r.get("agent", "?")].append(r)
    report = []
    for agent in sorted(by_agent):
        rows = by_agent[agent]
        on, off = rate(rows, "on"), rate(rows, "off")
        if on is None or off is None:
            report.append({"agent": agent, "verdict": "incomparavel",
                           "reason": "faltam resultados em 'on' ou 'off'"})
            continue
        gain = round(on - off, 4)
        report.append({
            "agent": agent,
            "pass_on": round(on, 4), "pass_off": round(off, 4), "gain": gain,
            "attempts_on": avg(rows, "on", "attempts"), "attempts_off": avg(rows, "off", "attempts"),
            "lead_on": avg(rows, "on", "lead_ms"), "lead_off": avg(rows, "off", "lead_ms"),
            "verdict": "harness_wins" if gain >= min_gain else "no_gain (candidato a retired, ADR-F5)",
        })
    return report


def score_flow_probe(probes, max_reads):
    """(v9 Fase 5) Backstop COMPORTAMENTAL: mede o sintoma real, nao um proxy estatico.
    O architect deve mapear um fluxo `verified` lendo do conhecimento pre-computado
    (ORCHESTRATION_MAP), NAO varrendo src/. Cada probe e {frontier, verified, src_reads:[paths]}
    (a contagem de arquivos de src/ que o agente abriu — a reproducao que mediu a degradacao da v8).
    Limiar: verified com leituras de src/ acima de max_reads = re-varredura (o defeito).
    Deterministico: consome o log, nao dispara LLM (a PRODUCAO do log e passo de ambiente)."""
    out = []
    for p in probes:
        verified = bool(p.get("verified"))
        n = len([r for r in (p.get("src_reads") or []) if r])
        failed = verified and n > max_reads
        if failed:
            verdict = f"FAIL (verified, {n} leituras de src/ > {max_reads} — agente re-varreu o codigo)"
        elif verified:
            verdict = f"PASS ({n} leitura(s) de src/ <= {max_reads})"
        else:
            verdict = f"skip (frontier nao-verified; {n} leituras toleradas)"
        out.append({"frontier": p.get("frontier", "?"), "verified": verified,
                    "src_reads": n, "verdict": verdict, "fail": failed})
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--results")
    ap.add_argument("--flow-probe", help="(Fase 5) log {frontier,verified,src_reads[]} do dispatch")
    ap.add_argument("--reads", help="(Fase 5 produtor) arquivo com 1 path aberto por linha (do dispatch vivo)")
    ap.add_argument("--frontier", default="?")
    ap.add_argument("--verified", action="store_true")
    ap.add_argument("--zones", help="zones.conf p/ classificar 'produto' (senao heuristica)")
    ap.add_argument("--max-src-reads", type=int, default=1)
    ap.add_argument("--min-gain", type=float, default=0.10)
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    # (Fase 5 produtor) transforma a lista de arquivos abertos pelo agente em flow-probe e pontua.
    # O UNICO passo nao-mecanico e CAPTURAR essa lista (dispatch vivo do agente, INIT-time).
    if a.reads:
        try:
            opened = [ln.strip() for ln in open(a.reads, encoding="utf-8") if ln.strip()]
        except Exception as e:
            sys.exit(f"[fable eval] --reads invalido: {e}")
        prod_re = r"^(src|app|lib|frontend|backend|tests?|pkg|internal|cmd|packages|components|pages|server|client|modules|services)/"
        if a.zones and os.path.isfile(a.zones):
            m = re.search(r'^\s*PRODUCT_RE\s*=\s*"([^"]+)"', open(a.zones, encoding="utf-8", errors="replace").read(), re.M)
            if m:
                prod_re = m.group(1)
        rx = re.compile(prod_re)
        src_reads = [p for p in opened if rx.search(p.replace("\\", "/").lstrip("./"))]
        fp = score_flow_probe([{"frontier": a.frontier, "verified": a.verified, "src_reads": src_reads}], a.max_src_reads)
        if a.json:
            print(json.dumps(fp, indent=2, ensure_ascii=False))
        else:
            print(f"[fable eval] {a.frontier}: {fp[0]['verdict']} ({fp[0]['src_reads']} de {len(opened)} leituras eram produto)")
        return 1 if fp[0]["fail"] else 0

    if a.flow_probe:
        try:
            probes = json.load(open(a.flow_probe, encoding="utf-8"))
        except Exception as e:
            sys.exit(f"[fable eval] flow-probe invalido: {e}")
        if not isinstance(probes, list) or not probes:
            sys.exit("[fable eval] flow-probe deve ser lista nao-vazia de {frontier,verified,src_reads[]}")
        fp = score_flow_probe(probes, a.max_src_reads)
        if a.json:
            print(json.dumps(fp, indent=2, ensure_ascii=False))
        else:
            print(f"[fable eval] backstop comportamental (max {a.max_src_reads} leitura(s) de src/ p/ verified):\n")
            for r in fp:
                print(f"  {r['frontier']:<16} {r['verdict']}")
        return 1 if any(r["fail"] for r in fp) else 0

    if not a.results:
        sys.exit("[fable eval] informe --results <file> ou --flow-probe <file>")
    try:
        results = json.load(open(a.results, encoding="utf-8"))
    except Exception as e:
        sys.exit(f"[fable eval] results invalido: {e}")
    if not isinstance(results, list) or not results:
        sys.exit("[fable eval] results.json deve ser lista nao-vazia de {agent,mode,verdict,...}")

    report = evaluate(results, a.min_gain)
    if a.json:
        print(json.dumps(report, indent=2, ensure_ascii=False))
    else:
        print(f"[fable eval] harness-on x off (min-gain {a.min_gain:+.0%}):\n")
        for r in report:
            if r["verdict"] == "incomparavel":
                print(f"  {r['agent']:<16} INCOMPARAVEL — {r['reason']}")
            else:
                print(f"  {r['agent']:<16} on={r['pass_on']:.0%} off={r['pass_off']:.0%} "
                      f"gain={r['gain']:+.0%}  -> {r['verdict']}")
    losers = [r for r in report if r["verdict"].startswith("no_gain")]
    if losers and a.strict:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
