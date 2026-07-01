#!/usr/bin/env python3
"""run-checks.py — Fase 3: prova de campo da fatia. A sonda 2b.6 e auto-avaliada
(perguntas vem das fatias, LLM julga — circular). Este script EXECUTA o `check_cmd`
de cada entrada e decide a confidence por fato: passou (exit 0) => verified;
falhou => stale. Entrada so com `check` em prosa (sem check_cmd) fica
'declarado, nao provado' — fluencia declarada, nao provada.

Dry-run por padrao (curador aplica); --apply reescreve a confidence no arquivo.
Stdlib pura. Env: CHECK_TIMEOUT (default 60s)."""
import glob
import os
import re
import subprocess
import sys

ROOT = os.environ.get("SWARM_ROOT", ".")
KNOW = os.path.join(ROOT, ".swarm", "knowledge")
TIMEOUT = int(os.environ.get("CHECK_TIMEOUT", "60"))


def parse(path):
    lines = open(path, encoding="utf-8").read().splitlines()
    entries, cur = [], None
    for i, line in enumerate(lines):
        m = re.match(r"\s*-\s*id:\s*(.+)", line)
        if m:
            if cur:
                entries.append(cur)
            cur = {"id": m.group(1).strip().strip('"'), "check_cmd": None,
                   "conf_idx": None, "conf_indent": "  "}
            continue
        if cur is None:
            continue
        mc = re.match(r"\s*check_cmd:\s*(.+)", line)
        if mc:
            cur["check_cmd"] = mc.group(1).strip().strip('"')
            continue
        mf = re.match(r"(\s*)confidence:\s*(.+)", line)
        if mf:
            cur["conf_idx"] = i
            cur["conf_indent"] = mf.group(1)
    if cur:
        entries.append(cur)
    return entries, lines


def run_cmd(cmd):
    # TRUST BOUNDARY: check_cmd e conteudo de HARNESS, nao input de usuario final.
    # So existe numa fatia se um curador o adicionou (o harvest-rejections gera
    # apenas `check:` em prosa, NUNCA check_cmd). shell=True e intencional e
    # consistente com transition.py (probe_command/verification_command, :257) —
    # o check e, por definicao, uma linha de comando do autor. Nunca alimente esta
    # funcao com texto de origem externa nao revisada.
    try:
        r = subprocess.run(cmd, shell=True, cwd=ROOT,  # noqa: S602 (trusted harness config)
                           capture_output=True, text=True, timeout=TIMEOUT)
        return r.returncode == 0
    except Exception:
        return False


def main():
    apply = "--apply" in sys.argv
    saw = 0
    for sf in (glob.glob(os.path.join(KNOW, "domain", "*.yaml"))
               + glob.glob(os.path.join(KNOW, "stack", "*.yaml"))):
        rel = os.path.relpath(sf, ROOT)
        entries, lines = parse(sf)
        changed = False
        for e in entries:
            if not e["check_cmd"]:
                print("declarado  %s: %s: sem check_cmd — 'declarado, nao provado'" % (rel, e["id"]))
                continue
            saw = 1
            ok = run_cmd(e["check_cmd"])
            verdict = "verified" if ok else "stale"
            print("%s %s: %s: check_cmd %s -> confidence: %s"
                  % ("PROVADO " if ok else "STALE   ", rel, e["id"],
                     "passou" if ok else "FALHOU", verdict))
            if apply and e["conf_idx"] is not None:
                lines[e["conf_idx"]] = '%sconfidence: "%s"' % (e["conf_indent"], verdict)
                changed = True
        if apply and changed:
            with open(sf, "w", encoding="utf-8") as f:
                f.write("\n".join(lines) + "\n")
            print("[fable run-checks] %s atualizado (--apply)." % rel)
    if not saw:
        print("[fable run-checks] nenhuma entrada com check_cmd (fluencia so declarada).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
