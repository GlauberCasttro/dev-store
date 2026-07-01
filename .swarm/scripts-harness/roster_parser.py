"""
roster_parser.py — funções compartilhadas de parsing do TEAM_ROSTER.yaml.
Importado pelos três blocos Python do harness-lint.sh via _FABLE_LIB env var.
Fonte única: qualquer fix ao parse_roster aplica a todos os gates de uma vez.
"""
import re


def rd(p):
    # utf-8-sig antes de utf-8: captura BOM do Windows sem garbling.
    # utf-16 antes do fallback: csproj/.sln do Visual Studio são UTF-16-LE por padrão.
    for enc in ("utf-8-sig", "utf-16", "utf-8"):
        try:
            return open(p, encoding=enc).read()
        except Exception:
            continue
    return ""


def parse_roster(path):
    """Lê TEAM_ROSTER.yaml e retorna {nome_agente: [lista_de_trees]}.

    Campo de território: aceita `trees`, `writes_to`, `allowed_paths` ou `allowed`
    como ALIASES — o gerador (LLM) varia o nome e ler só `trees` fazia os gates de
    fronteira pularem em silêncio (falso-OK; achado no INIT real do dev-store).
    """
    # alias do campo de território
    FIELD = r'(?:trees|writes_to|allowed_paths|allowed)'
    inline = re.compile(r'\s*' + FIELD + r':\s*\[(.*)\]')
    header = re.compile(r'\s*' + FIELD + r':\s*(#.*)?$')
    agents = {}
    cur = None
    intrees = False
    for line in rd(path).splitlines():
        m = re.match(r'\s*-\s*name:\s*(\S+)', line)
        if m:
            cur = m.group(1).strip().strip('"')
            agents[cur] = []
            intrees = False
            continue
        if cur is None:
            continue
        mi = inline.match(line)
        if mi:
            agents[cur] = [t.strip().strip("\"'") for t in mi.group(1).split(',') if t.strip()]
            intrees = False
            continue
        # campo de território em linha própria (com ou sem comentário inline)
        if header.match(line):
            intrees = True
            continue
        if intrees:
            mt = re.match(r'\s*-\s*([^\s#]+)', line)
            if mt:
                agents[cur].append(mt.group(1).strip().strip("\"'"))
            else:
                intrees = False
    return agents


def norm(t):
    return t.replace("\\", "/").rstrip("*").rstrip("/")


def in_tree(path, trees):
    p = path.replace("\\", "/")
    return any(norm(t) and (p == norm(t) or p.startswith(norm(t) + "/")) for t in trees)


def parse_inv(path):
    """Lê DOMAIN_INVARIANTS.yaml e retorna [{id, ev}]."""
    out = []
    cur = None
    for line in rd(path).splitlines():
        m = re.match(r'\s*-\s*id:\s*([A-Za-z]+-\d+)', line)
        if m:
            cur = {"id": m.group(1), "ev": None}
            out.append(cur)
            continue
        if cur is None:
            continue
        me = re.match(r'\s*evidence:\s*(\S+)', line)
        if me:
            cur["ev"] = me.group(1).strip()
    return out
