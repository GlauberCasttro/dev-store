#!/usr/bin/env python3
"""gen-zones.py (v9 F3.1) — gera .swarm/scripts-harness/zones.conf do PROJECT_PROFILE.layout.

Tese do Fable: o harness nasce do codebase. Os guards (guard-zones / cursor-guard-pretool /
cursor-guard-shell) leem zones.conf como FONTE PRIMARIA do que e "produto"; a regex fixa vira
fallback. Assim um repo com produto em modules/Orders fica protegido — nao so quem usa src/.
Sem pyyaml (nao-portavel): parse por regex do layout.

Uso:  gen-zones.py [ROOT] [--write]
  sem --write: imprime zones.conf no stdout (revisavel)
  --write: grava em ROOT/.swarm/scripts-harness/zones.conf
"""
import os, re, sys

ROOT = "."
WRITE = False
for a in sys.argv[1:]:
    if a == "--write":
        WRITE = True
    else:
        ROOT = a

PROFILE = os.path.join(ROOT, ".swarm", "state", "PROJECT_PROFILE.yaml")

# fallback unico (espelha o default dos guards) — usado quando o PROFILE nao traz product_dirs
DEFAULT_PRODUCT = ["src", "app", "lib", "frontend", "backend", "tests", "test", "pkg",
                   "internal", "cmd", "packages", "components", "pages", "server", "client"]


def read(p):
    for enc in ("utf-8-sig", "utf-16", "utf-8"):
        try:
            return open(p, encoding=enc).read()
        except Exception:
            continue
    return ""


def dirs_from(txt, key):
    """Le `key: [a, b]` (inline) ou `key:\n  - a\n  - b` (bloco)."""
    m = re.search(rf'{key}\s*:\s*\[([^\]]*)\]', txt)
    if m:
        items = m.group(1).split(',')
    else:
        m2 = re.search(rf'{key}\s*:\s*\n((?:\s*-\s*\S.*\n?)+)', txt)
        items = re.findall(r'-\s*(\S[^\n]*)', m2.group(1)) if m2 else []
    out = []
    for it in items:
        d = it.strip().strip('"\'').replace("\\", "/").rstrip("/")
        if d:
            out.append(d)
    return out


txt = read(PROFILE) if os.path.isfile(PROFILE) else ""
product = dirs_from(txt, "product_dirs")
tests = dirs_from(txt, "test_dirs")
infra = dirs_from(txt, "infra_dirs")

from_profile = bool(product)
if not product:
    product = DEFAULT_PRODUCT

prod_and_test = product + [t for t in tests if t not in product]
prod_glob = "|".join(f"{d}/*" for d in prod_and_test)
prod_re = "^(" + "|".join(re.escape(d) for d in prod_and_test) + ")/"
test_glob = "|".join(f"{d}/*" for d in tests) or "tests/*|test/*|spec/*"
infra_glob = "|".join(f"{d}/*" for d in infra) or ".github/*|infra/*|deploy/*|Dockerfile|docker-compose.yml"

conf = f"""# zones.conf — GERADO por gen-zones.py do PROJECT_PROFILE.layout (v9 F3.1). NAO editar a mao.
# Fonte: {"PROJECT_PROFILE.layout" if from_profile else "DEFAULT (PROFILE sem product_dirs — fallback)"}
PRODUCT_GLOBS="{prod_glob}"
PRODUCT_RE="{prod_re}"
TEST_GLOBS="{test_glob}"
INFRA_GLOBS="{infra_glob}"
STATE_GLOBS=".swarm/state/*|.swarm/logs/*|.swarm/knowledge/*|.swarm/archive/*"
KNOWLEDGE_GLOBS=".swarm/knowledge/*"
HARNESS_GLOBS=".claude/*|.cursor/*|.swarm/scripts-harness/*|CLAUDE.md|AGENTS.md|Makefile"
"""

if WRITE:
    outdir = os.path.join(ROOT, ".swarm", "scripts-harness")
    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, "zones.conf"), "w") as f:
        f.write(conf)
    print(f"[fable] zones.conf gravado ({'PROFILE' if from_profile else 'DEFAULT'}) em {outdir}/zones.conf")
else:
    sys.stdout.write(conf)
