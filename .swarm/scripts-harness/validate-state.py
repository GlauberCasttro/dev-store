#!/usr/bin/env python3
"""validate-state.py (v9 F2.4) — validacao estrutural dos 6 YAMLs decisorios do Fable.

"Dados estruturados decidem" (P3): se um perfil esta corrompido ou sem campo critico,
o INIT nao pode prosseguir nem o pre-commit passar. Sem pyyaml (nao-portavel): a checagem
e por linha/regex, reusando roster_parser. CONSERVADORA por design (licao da v8 — nao
falso-positivar): so reprova o que e inequivocamente quebrado (vazio, sem chave-ancora,
id ausente). Validacoes de vocabulario de status vivem no accept-check (F4.4), nao aqui.

Uso:  validate-state.py [ROOT]        (default ROOT=.)
Sai 1 com a lista de problemas; 0 se todos os arquivos presentes sao estruturalmente validos
(arquivo ausente nao e erro — outros gates cobram presenca no estagio certo).
"""
import os, re, sys

sys.path.insert(0, os.environ.get("_FABLE_LIB", os.path.dirname(os.path.abspath(__file__))))
from roster_parser import rd, parse_roster, parse_inv

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
STATE = os.path.join(ROOT, ".swarm", "state")
KNOW = os.path.join(ROOT, ".swarm", "knowledge")

errs = []


def need(cond, msg):
    if not cond:
        errs.append(msg)


def body_nonempty(txt):
    return any(ln.strip() and not ln.strip().startswith("#") for ln in txt.splitlines())


def has_key(txt, key):
    return bool(re.search(rf'^\s*{key}\s*:', txt, re.M))


# 1. CAPABILITY.yaml — plataforma + flags de enforcement
p = os.path.join(STATE, "CAPABILITY.yaml")
if os.path.isfile(p):
    t = rd(p)
    need(body_nonempty(t), "CAPABILITY.yaml: vazio / so comentarios")
    need(bool(re.search(r'^\s*platform\s*:\s*\S+', t, re.M)),
         "CAPABILITY.yaml: sem 'platform:' (claude-code|cursor|generic)")
    need(any(re.search(rf'^\s*{f}\s*:\s*(true|false)', t, re.M | re.I)
             for f in ("E1_config", "E2_hooks", "E3_external")),
         "CAPABILITY.yaml: sem flags de enforcement (E1_config/E2_hooks/E3_external)")

# 2. PROJECT_PROFILE.yaml — layout + stacks
p = os.path.join(STATE, "PROJECT_PROFILE.yaml")
if os.path.isfile(p):
    t = rd(p)
    need(body_nonempty(t), "PROJECT_PROFILE.yaml: vazio / so comentarios")
    need(has_key(t, "layout") or "product_dirs" in t,
         "PROJECT_PROFILE.yaml: sem 'layout:' (product_dirs/test_dirs/infra_dirs)")
    need(has_key(t, "stacks"),
         "PROJECT_PROFILE.yaml: sem 'stacks:' (ecossistemas detectados no scan)")

# 3. TEAM_ROSTER.yaml — >=1 agente parseavel
p = os.path.join(STATE, "TEAM_ROSTER.yaml")
if os.path.isfile(p):
    t = rd(p)
    need(body_nonempty(t), "TEAM_ROSTER.yaml: vazio / so comentarios")
    need(len(parse_roster(p)) >= 1, "TEAM_ROSTER.yaml: nenhum agente (- name:) parseavel")

# 4. STACK_PROFILE.yaml — perfil por ecossistema
p = os.path.join(STATE, "STACK_PROFILE.yaml")
if os.path.isfile(p):
    t = rd(p)
    need(body_nonempty(t), "STACK_PROFILE.yaml: vazio / so comentarios")
    need(has_key(t, "stacks") or has_key(t, "mastery"),
         "STACK_PROFILE.yaml: sem 'stacks:' nem 'mastery:' (perfil/sonda por ecossistema)")

# 5. DOMAIN_INVARIANTS.yaml (knowledge/) — >=1 invariante com id + source
p = os.path.join(KNOW, "DOMAIN_INVARIANTS.yaml")
if os.path.isfile(p):
    t = rd(p)
    need(body_nonempty(t), "DOMAIN_INVARIANTS.yaml: vazio / so comentarios")
    has_id = len(parse_inv(p)) >= 1
    need(has_id, "DOMAIN_INVARIANTS.yaml: nenhum invariante '- id: XXX-N'")
    if has_id:
        need(has_key(t, "source"),
             "DOMAIN_INVARIANTS.yaml: invariante(s) sem 'source:' (scan|founder|generic-default)")

# 6. ASSUMPTIONS.yaml — ledger com >=1 suposicao
p = os.path.join(STATE, "ASSUMPTIONS.yaml")
if os.path.isfile(p):
    t = rd(p)
    need(body_nonempty(t), "ASSUMPTIONS.yaml: vazio / so comentarios")
    need(has_key(t, "assumptions"), "ASSUMPTIONS.yaml: sem chave 'assumptions:'")
    need(bool(re.search(r'^\s*-\s*id:\s*A-\d+', t, re.M)),
         "ASSUMPTIONS.yaml: nenhuma suposicao '- id: A-N'")

if errs:
    print("[fable validate-state] FAIL:\n  " + "\n  ".join(errs))
    sys.exit(1)
print("[fable validate-state] OK")
sys.exit(0)
