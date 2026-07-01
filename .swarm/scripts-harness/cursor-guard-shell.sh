#!/bin/bash
# cursor-guard-shell.sh — Cursor hook: beforeShellExecution (E2).
# Contrato Cursor (2026): stdin = JSON {command, cwd, ...}; stdout = JSON
#   {"permission":"allow"|"deny"|"ask","user_message":...,"agent_message":...}.
# failClosed:true no hooks.json => bloqueio em falha (default do Cursor é fail-open;
# bug conhecido: JSON malformado no beforeShellExecution libera em silêncio).
# Papel: imutabilidade de harness, escopo de produto por allowed_paths, e protocolo
# git/commit. Shell é a maior superfície de bypass; por isso mutações com paths
# explícitos passam pelo mesmo contrato do preToolUse.
# Escape de diagnóstico: SWARM_GUARD_OFF=1. Manutenção aprovada: SWARM_MAINT=1.
set -u
INPUT=$(cat)
allow(){ echo '{"permission":"allow"}'; exit 0; }
deny(){ printf '{"permission":"deny","user_message":%s,"agent_message":%s}\n' "$1" "$2"; exit 0; }
[ "${SWARM_GUARD_OFF:-0}" = "1" ] && allow

# Sem parser ⇒ fail-closed (o failClosed do hooks.json também cobre, defesa em profundidade).
command -v python3 >/dev/null 2>&1 || deny '"fable: guard-shell sem python3 (fail-closed)"' '"Instale python3 (rode .swarm/scripts-harness/doctor.sh)."'

DECISION=$(HOOK_INPUT="$INPUT" python3 - <<'PY'
import glob
import json
import os
import re
import shlex
import sys

def decision(permission, user_message=None, agent_message=None):
    payload = {"permission": permission}
    if user_message:
        payload["user_message"] = user_message
    if agent_message:
        payload["agent_message"] = agent_message
    print(json.dumps(payload, ensure_ascii=False))
    sys.exit(0)

raw = os.environ.get("HOOK_INPUT", "")
try:
    data = json.loads(raw)
except Exception:
    decision(
        "deny",
        "fable E2: payload beforeShellExecution invalido",
        "Hook recebeu JSON invalido; acao bloqueada fail-closed. Confirme o contrato do Cursor no Estagio 0.",
    )

cmd = data.get("command") or data.get("shell_command") or ""
if not isinstance(cmd, str) or not cmd.strip():
    decision(
        "deny",
        "fable E2: shell sem command reconhecido",
        "Payload beforeShellExecution sem command; bloqueado fail-closed.",
    )

roots = data.get("workspace_roots") if isinstance(data.get("workspace_roots"), list) else []
root = (
    os.environ.get("CURSOR_PROJECT_DIR")
    or os.environ.get("CURSOR_WORKSPACE_ROOT")
    or (roots[0] if roots else "")
    or data.get("cwd")
    or os.getcwd()
)
cwd = data.get("cwd") or root
root = os.path.abspath(root)
cwd = os.path.abspath(cwd)
maint = os.environ.get("SWARM_MAINT") == "1"
active_path = os.path.join(root, ".swarm", "state", ".active-task.json")

lower = cmd.lower()

def deny(msg, agent):
    decision("deny", msg, agent)

def is_active():
    return os.path.exists(active_path)

def task_files():
    return glob.glob(os.path.join(root, ".swarm", "state", "sprints", "*", "tasks", "*.json"))

def load_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None

def has_task_id_before_to(command):
    try:
        toks = shlex.split(command)
    except Exception:
        toks = command.split()
    for i, tok in enumerate(toks):
        if tok.endswith("transition.py"):
            if i + 1 < len(toks) and not toks[i + 1].startswith("-"):
                return True
            return False
    return True

# (fix F5) Anti-exploração em MODO EXECUÇÃO: com task ativa cujo brief marca
# forbidden_explore, varredura ampla read-only (find/rg/grep -r/Get-ChildItem
# -Recurse/dir /s/ls -R) é violação de protocolo — o brief é a verdade
# (context_complete). Fora de task ativa, ou sem o flag, exploração é PERMITIDA
# (preserva a consultoria do architect/po — agent-template §capacidade de sistema).
if is_active():
    _active = load_json(active_path) or {}
    if _active.get("forbidden_explore"):
        explore_res = [
            r"get-childitem\b[^|;&]*-recurse",
            r"\bgci\b[^|;&]*-recurse",
            r"\bls\b[^|;&]*\s-[a-z]*r",
            r"(^|[\s;&|(])find\s+\S",
            r"\bgrep\s+-[a-z]*r",
            r"(^|[\s;&|(])rg\b",
            r"\bdir\b[^|;&]*\s/s\b",
        ]
        for _pat in explore_res:
            if re.search(_pat, lower):
                deny(
                    "fable E2: exploracao ampla bloqueada (task forbidden_explore)",
                    "O brief e a verdade (context_complete). Leia apenas os paths em anchors/allowed_paths; "
                    "nao varra o repositorio. Falta contexto? Retorne PARTIAL ao tech-lead.",
                )

# Git operations are shell-only and need explicit protocol checks.
if re.search(r"(^|[;&|()\s])git\s+add\s+(\.($|\s)|-a\b|--all\b)", lower):
    deny(
        "fable E2: git add amplo bloqueado",
        "Nunca use git add . / -A / --all. Adicione produto + estado explicitamente apos transition.py --to COMMITTED.",
    )

if re.search(r"(^|[;&|()\s])git\s+commit\b", lower):
    if is_active():
        deny(
            "fable E2: git commit com task ativa bloqueado",
            "Finalize o ciclo: SUBMITTED -> VERIFYING -> ACCEPTED -> transition.py --to COMMITTED antes do commit.",
        )
    for path in task_files():
        brief = load_json(path)
        if not brief:
            continue
        status = brief.get("status")
        if status == "ACCEPTED":
            deny(
                "fable E2: commit antes de COMMITTED bloqueado",
                f"{brief.get('id') or os.path.basename(path)} esta ACCEPTED. Rode transition.py <TASK> --to COMMITTED antes de git add/commit.",
            )
        if status in ("ACCEPTED", "COMMITTED") and (brief.get("gate_report") or {}).get("verdict") != "PASS":
            deny(
                "fable E2: commit sem gate_report PASS bloqueado",
                f"{brief.get('id') or os.path.basename(path)} nao tem gate_report PASS persistido.",
            )

if "transition.py" in lower and re.search(r"\s--to\s+", lower) and not has_task_id_before_to(cmd):
    deny(
        "fable E2: transition.py sem TASK bloqueado",
        "Use transition.py <TASK-ID> --to STATE ou transition.py --sprint <SPRINT-ID> --to STATE.",
    )

def mutating_shell(command):
    if re.search(r"(^|[;&|()\s])(rm|mv|cp|tee|touch|mkdir|rmdir|truncate|install)\b", command, re.I):
        return True
    if re.search(r"\bsed\s+-[^\s]*i\b|\bperl\s+-[^\s]*i\b", command, re.I):
        return True
    if re.search(r"(^|[^<>])>{1,2}([^=>]|$)", command):
        return True
    if re.search(r"\b(python3?|node|ruby|perl|php)\b[\s\S]*\b(open|writeFile|write_file|File\.write|fs\.write)", command):
        return True
    return False

def extract_paths(command):
    paths = set()
    try:
        toks = shlex.split(command)
    except Exception:
        toks = command.split()
    for tok in toks:
        t = tok.strip(" '\"\t\r\n,;")
        if not t or t in {">", ">>", "2>", "1>", "<"} or "://" in t:
            continue
        if t == "AGENTS.md" or "/" in t or t.startswith("."):
            paths.add(t)
    for m in re.finditer(r"(?<![A-Za-z0-9_.-])(?:\./|\../|/|\.cursor/|\.swarm/|AGENTS\.md\b|[A-Za-z0-9_.-]+/)[A-Za-z0-9_./@%+=:-]*", command):
        p = m.group(0).strip(" '\"\t\r\n,;")
        if p and "://" not in p:
            paths.add(p)
    return sorted(paths)

def rel_path(path):
    if path in {">", ">>", "<"}:
        return None
    if path.startswith("/"):
        abs_path = os.path.abspath(path)
    else:
        abs_path = os.path.abspath(os.path.join(cwd, path))
    try:
        rel = os.path.relpath(abs_path, root)
    except ValueError:
        return None
    if rel == "." or rel.startswith(".."):
        return None
    return rel.replace(os.sep, "/")

def is_harness(rel):
    return (
        rel == "AGENTS.md"
        or rel == ".cursor"
        or rel == ".swarm/scripts-harness"
        or rel == ".cursor/hooks.json"
        or rel == ".swarm/core-spec.md"
        or rel.startswith(".cursor/agents/")
        or rel.startswith(".cursor/rules/")
        or rel.startswith(".cursor/skills/")
        or rel.startswith(".cursor/hooks/")
        or rel.startswith(".swarm/scripts-harness/")
    )

# (v9 F3.2) zones.conf gerado do PROJECT_PROFILE e a fonte PRIMARIA do que e "produto"; regex fixa = fallback.
_PRODUCT_RE_DEFAULT = r"^(src|app|lib|frontend|backend|tests?|pkg|internal|cmd|packages|components|pages|server|client)/"
_zconf = os.path.join(root, ".swarm", "scripts-harness", "zones.conf")
_re_str = _PRODUCT_RE_DEFAULT
if os.path.isfile(_zconf):
    try:
        _m = re.search(r'^\s*PRODUCT_RE\s*=\s*"([^"]+)"', open(_zconf, encoding="utf-8", errors="replace").read(), re.M)
        if _m:
            _re_str = _m.group(1)
    except OSError:
        pass
PRODUCT_RE = re.compile(_re_str)

def is_state_free(rel):
    return rel.startswith((".swarm/state/", ".swarm/logs/", ".swarm/knowledge/", ".swarm/archive/"))

def allowed_paths():
    active = load_json(active_path) or {}
    return active.get("task_id") or "", active.get("allowed_paths") or []

def in_allowed(rel, allowed):
    for raw in allowed:
        a = str(raw).strip()
        if not a:
            continue
        a = a.replace("\\", "/").lstrip("./").rstrip("/")
        if a.endswith("/**"):
            a = a[:-3].rstrip("/")
        if rel == a or rel.startswith(a + "/"):
            return True
    return False

if mutating_shell(cmd):
    rels = [rel_path(p) for p in extract_paths(cmd)]
    rels = [r for r in rels if r]

    if not maint:
        for rel in rels:
            if is_harness(rel):
                deny(
                    "fable E2: escrita em harness via shell bloqueada",
                    f"{rel} e harness imutavel em runtime. Use SWARM_MAINT=1 com aprovacao humana.",
                )

    # (v9 F3.3) knowledge por papel tambem no shell (espelha o preToolUse)
    if is_active():
        _ag = (load_json(active_path) or {}).get("agent") or ""
        for rel in rels:
            if not rel.startswith(".swarm/knowledge/"):
                continue
            if _ag.startswith("architect"):
                if not rel.startswith(".swarm/knowledge/ADR/"):
                    deny("fable E2: architect escreve so ADR", f"{rel} fora de .swarm/knowledge/ADR/.")
            elif _ag.startswith("curator"):
                if not rel.startswith(".swarm/knowledge/memory/"):
                    deny("fable E2: curator escreve so memoria", f"{rel} fora de .swarm/knowledge/memory/.")
            elif _ag.startswith("verifier"):
                deny("fable E2: verifier e readonly", "verifier nao escreve arquivos.")
            elif _ag.startswith("dev-") or _ag.startswith("qa-"):
                deny("fable E2: dev/qa nao escrevem knowledge global",
                     f"{rel}: conhecimento global nao e escrito por dev/qa (vira proposta ao curator).")

    product_rels = [r for r in rels if PRODUCT_RE.search(r) and not is_state_free(r)]
    if product_rels:
        if is_active():
            task, allowed = allowed_paths()
            for rel in product_rels:
                if not in_allowed(rel, allowed):
                    deny(
                        "fable E2: escrita shell fora do allowed_paths",
                        f"{rel} esta fora do escopo da task {task}. Retorne PARTIAL ao tech-lead; nao contorne via shell.",
                    )
        else:
            deny(
                "fable E2: tech-lead shell nao escreve produto",
                f"Comando mutante toca produto ({', '.join(product_rels[:4])}). Despache o especialista apos brief e task ativa.",
            )

# (v9 F3.4) comandos GLOBAIS de stack mutam manifestos/deps SEM path explicito — escapavam do
# mutating_shell (que so pega rm/redirect/etc). Sem task = main nao roda; com task, exige
# allowed_paths cobrindo o manifesto/raiz (senao o comando reformata/instala fora do escopo).
STACK_MUT = re.compile(
    r"(^|[;&|()\s])(npm|pnpm|yarn)\s+(install|i|add|update|ci)\b"
    r"|(^|[;&|()\s])go\s+(mod\s+tidy|get)\b"
    r"|(^|[;&|()\s])dotnet\s+(format|add)\b"
    r"|(^|[;&|()\s])cargo\s+(fix|add|update)\b"
    r"|(^|[;&|()\s])(pip3?|poetry|pipenv)\s+(install|add)\b"
    r"|(^|[;&|()\s])(bundle|composer)\s+(install|update)\b"
    r"|(^|[;&|()\s])npm\s+version\b",
    re.I,
)
if STACK_MUT.search(cmd):
    if not is_active():
        deny(
            "fable E2: comando global de stack sem task ativa",
            "Comando muta deps/manifestos do projeto. Rode dentro de uma task com allowed_paths "
            "cobrindo o manifesto — nao como main/tech-lead.",
        )
    _task, _allowed = allowed_paths()
    _covers = False
    for _raw in _allowed:
        _a = str(_raw).strip().replace("\\", "/").lstrip("./").rstrip("/")
        if _a in ("", ".", "**") or re.search(
            r"(package\.json|go\.mod|Cargo\.toml|pyproject\.toml|requirements\.txt|Gemfile|composer\.json|\.csproj|\.sln)$", _a):
            _covers = True
            break
    if not _covers:
        deny(
            "fable E2: comando global de stack fora do allowed_paths",
            f"'{cmd.strip()[:60]}' muta manifestos/deps fora do escopo da task {_task}. "
            "Inclua o manifesto no allowed_paths ou retorne PARTIAL.",
        )

decision("allow")
PY
)

printf '%s\n' "$DECISION"
exit 0
