#!/usr/bin/env python3
"""check-slice-drift.py — Fase 2: detecta drift da fatia (dominio + stack) vs codigo.

O source_fingerprint do STACK_PROFILE so cobre lockfile. As fatias de dominio e de
stack apodrecem em silencio quando o codigo sob suas `anchors` muda. Este script
recomputa o sha256 das anchors de cada entrada que declara `anchors_fingerprint` e
sinaliza WARN quando diverge (fatia stale) ou quando a anchor sumiu do disco.

Stdlib pura (sem PyYAML/jq) — parser minimal do formato de fatia, consistente com o
jeito que o harness-lint ja le essas listas. Entrada sem fingerprint = nao rastreada
(degradacao declarada, nao erro).

Advisory por padrao (exit 0, espelha o source_fingerprint do harness-lint);
--strict => exit 1 se houver drift.
"""
import glob
import hashlib
import os
import re
import sys

ROOT = os.environ.get("SWARM_ROOT", ".")
KNOW = os.path.join(ROOT, ".swarm", "knowledge")


def entries(path):
    """Parser minimal: 1 dict por bloco '- id:' com {id, anchors:[...], fp}."""
    cur, out = None, []
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except OSError:
        return out
    for line in lines:
        m = re.match(r"\s*-\s*id:\s*(.+)", line)
        if m:
            if cur:
                out.append(cur)
            cur = {"id": m.group(1).strip().strip('"'), "anchors": [], "fp": None}
            continue
        if cur is None:
            continue
        ma = re.match(r"\s*anchors:\s*\[(.*)\]", line)
        if ma:
            cur["anchors"] = [t.strip().strip("\"'") for t in ma.group(1).split(",") if t.strip()]
            continue
        mf = re.match(r"\s*anchors_fingerprint:\s*(.+)", line)
        if mf:
            cur["fp"] = mf.group(1).strip().strip('"')
    if cur:
        out.append(cur)
    return out


def sha_of(anchors):
    h = hashlib.sha256()
    missing = []
    for a in anchors:
        p = a if os.path.isabs(a) else os.path.join(ROOT, a)
        if not os.path.exists(p):
            missing.append(a)
            continue
        with open(p, "rb") as f:
            h.update(f.read())
    return h.hexdigest(), missing


def main():
    strict = "--strict" in sys.argv
    drift = 0
    files = (glob.glob(os.path.join(KNOW, "domain", "*.yaml"))
             + glob.glob(os.path.join(KNOW, "stack", "*.yaml")))
    for sf in files:
        rel = os.path.relpath(sf, ROOT)
        for e in entries(sf):
            if not e["fp"] or not e["anchors"]:
                continue  # nao rastreada (degradacao declarada)
            cur, missing = sha_of(e["anchors"])
            if missing:
                print(f"DRIFT WARN: {rel}: {e['id']}: ancora sumiu do disco: {missing}")
                drift = 1
            elif cur != e["fp"]:
                print(f"DRIFT WARN: {rel}: {e['id']}: anchors mudaram desde a geracao "
                      f"-> marque confidence: stale e re-sonde (/especializar)")
                drift = 1
    if not drift:
        print("[fable drift] OK — nenhuma fatia stale.")
        return 0
    return 1 if strict else 0


if __name__ == "__main__":
    sys.exit(main())
