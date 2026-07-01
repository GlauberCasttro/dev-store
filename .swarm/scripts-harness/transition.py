#!/usr/bin/env python3
"""transition.py — única porta de mudança de estado de task (Fable, protocol 7).

Uso:
  transition.py TASK-NN-XX --to STATE [--reason "..."] [--actor tech-lead]
  transition.py TASK-NN-XX --gate '<json>' (ou @arquivo)  # persiste gate_report do verifier
  transition.py --sprint SPRINT-NN --to STATE   # máquina de sprint (DRAFT→ACTIVE→ARCHIVED)
  transition.py --validate-all            # E3: pre-commit (briefs + coerência + sprints)

Valida a máquina canônica, exige gate_report PASS para ACCEPTED, mantém
.active-task.json (consumido pelo guard-allowed-paths) e grava events.jsonl.
"""
import argparse, json, sys, glob, os, subprocess
from datetime import datetime, timezone

MACHINE = {
    "DRAFT": ["READY", "CANCELLED"],
    "READY": ["DISPATCHED", "DEFERRED", "CANCELLED"],
    "DISPATCHED": ["IN_PROGRESS", "READY"],
    "IN_PROGRESS": ["SUBMITTED", "BLOCKED"],
    "SUBMITTED": ["VERIFYING"],
    "VERIFYING": ["ACCEPTED", "REJECTED", "BLOCKED"],
    "ACCEPTED": ["COMMITTED"],
    "REJECTED": ["READY"],
    "BLOCKED": ["READY", "DEFERRED", "CANCELLED"],
    "DEFERRED": ["READY"],
    "COMMITTED": [], "CANCELLED": [],
}
SPRINT_MACHINE = {"DRAFT": ["ACTIVE"], "ACTIVE": ["ARCHIVED"], "ARCHIVED": []}
SPRINT_DONE = ("COMMITTED", "CANCELLED")
REQUIRED = ["id", "sprint", "agent", "status", "dependencies", "allowed_paths",
            "acceptance_criteria", "verification_command", "status_history"]
ROOT = os.environ.get("SWARM_ROOT", ".")
STATE = os.path.join(ROOT, ".swarm", "state")
MAX_ATTEMPTS = 3


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def find_brief(task_id):
    hits = glob.glob(os.path.join(STATE, "sprints", "*", "tasks", f"{task_id}.json"))
    if len(hits) != 1:
        sys.exit(f"[fable] brief de {task_id}: {'não encontrado' if not hits else 'duplicado'}")
    return hits[0]


def load(path):
    with open(path) as f:
        return json.load(f)


def save(path, data):
    with open(path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")


def current_git_branch():
    try:
        inside = subprocess.run(
            ["git", "rev-parse", "--is-inside-work-tree"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=10,
        )
        if inside.returncode != 0 or inside.stdout.strip() != "true":
            return None
        branch = subprocess.run(
            ["git", "branch", "--show-current"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=10,
        )
        if branch.returncode != 0:
            return None
        return branch.stdout.strip() or None
    except (OSError, subprocess.TimeoutExpired):
        return None


def event(brief_path, payload):
    ev = os.path.join(os.path.dirname(os.path.dirname(brief_path)), "events.jsonl")
    with open(ev, "a") as f:
        f.write(json.dumps(payload, ensure_ascii=False) + "\n")


def check_state_invariants(b):
    """(v9 F2.2) Regras que dependem do ESTADO atual do brief — campos exigidos por fase.
    Validado em todo --validate-all e antes de toda transição (porta única)."""
    errs = []
    st = b.get("status")
    if st in ("SUBMITTED", "VERIFYING", "ACCEPTED", "COMMITTED"):
        sub = b.get("submission")
        ss = sub.get("status") if isinstance(sub, dict) else None
        if not ss:
            errs.append(f"status {st} exige submission.status preenchido (executor reporta SUBMITTED/PARTIAL)")
        elif not (str(ss) == "SUBMITTED" or str(ss).startswith("PARTIAL")):
            errs.append(f"submission.status invalido: '{ss}' (esperado 'SUBMITTED' ou 'PARTIAL - motivo')")
    if st in ("ACCEPTED", "COMMITTED") and (b.get("gate_report") or {}).get("verdict") != "PASS":
        errs.append(f"status {st} sem gate_report PASS persistido")
    if st == "COMMITTED" and not any(h.get("to") == "ACCEPTED" for h in (b.get("status_history") or [])):
        errs.append("COMMITTED sem ACCEPTED previo no status_history — ciclo pulado/aberto")
    return errs


def check_brief(b, path):
    errs = [f"campo obrigatório ausente: {k}" for k in REQUIRED if k not in b or b[k] in (None, "")]
    # (v9 F2.1) brief raso nao despacha: objective/context_inline/anchors exigidos NAO-VAZIOS
    # (alinha o validador ao schema canonico do brief, core-spec §3); submission/gate_report
    # devem EXISTIR como chave (podem ser null ate o estado certo, mas a chave nao some).
    for k in ("objective", "context_inline", "anchors"):
        v = b.get(k)
        if v in (None, "", [], {}) or (isinstance(v, str) and not v.strip()):
            errs.append(f"{k} ausente/vazio — brief raso, subagente nasce cego (v9 F2.1)")
    for k in ("submission", "gate_report"):
        if k not in b:
            errs.append(f"chave '{k}' ausente — schema do brief incompleto (deve existir, pode ser null) (v9 F2.1)")
    ap = b.get("allowed_paths")
    if not ap or not isinstance(ap, list):
        errs.append("allowed_paths nulo/vazio")
    elif any(p.strip() in ("**", "*", "src/**", ".") for p in ap):
        errs.append(f"allowed_paths amplo demais: {ap}")
    if b.get("status") not in MACHINE:
        errs.append(f"estado não-canônico: {b.get('status')}")
    hist = b.get("status_history") or []
    if hist and b.get("status") != hist[-1].get("to"):
        errs.append(f"status '{b.get('status')}' != último status_history.to "
                    f"'{hist[-1].get('to')}' — edição manual detectada")
    errs += check_state_invariants(b)
    return [f"{os.path.basename(path)}: {e}" for e in errs]


def validate_all():
    errors = []
    for path in glob.glob(os.path.join(STATE, "sprints", "*", "tasks", "*.json")):
        try:
            errors += check_brief(load(path), path)
        except json.JSONDecodeError as e:
            errors.append(f"{os.path.basename(path)}: JSON inválido — {e}")
    SPRINT_VOCAB = ("DRAFT", "ACTIVE", "ARCHIVED")
    for sp in glob.glob(os.path.join(STATE, "sprints", "*", "sprint.json")):
        try:
            sj = load(sp)
            if sj.get("status") not in SPRINT_VOCAB and not sj.get("pre_migration"):
                errors.append(f"{os.path.basename(os.path.dirname(sp))}/sprint.json: "
                              f"status '{sj.get('status')}' fora de {'|'.join(SPRINT_VOCAB)}")
            if sj.get("status") == "ARCHIVED" and not sj.get("pre_migration"):
                for t in glob.glob(os.path.join(os.path.dirname(sp), "tasks", "*.json")):
                    st = load(t).get("status")
                    if st not in SPRINT_DONE:
                        errors.append(f"{os.path.basename(os.path.dirname(sp))}: "
                                      f"ARCHIVED com {os.path.basename(t)} em {st} "
                                      f"— edição manual de sprint?")
        except json.JSONDecodeError as e:
            errors.append(f"{sp}: JSON inválido — {e}")
    # (fix F3) sprint plano fora do layout canônico = órfão silencioso: o validate
    # globava só sprints/*/sprint.json e IGNORAVA um sprints/SPRINT-NN.json solto.
    for flat in glob.glob(os.path.join(STATE, "sprints", "*.json")):
        errors.append(f"{os.path.basename(flat)}: sprint plano fora do layout canônico — "
                      "migre para sprints/<ID>/sprint.json (+ tasks/*.json); arquivo solto é "
                      "ignorado pela máquina de estados (transition.py)")
    # (fix F3) events.jsonl: toda linha é JSON com 'type' no vocabulário §10. Schema
    # legado {event: ...} quebra /metricas e a trilha de auditoria — agora reprova.
    for ev in (glob.glob(os.path.join(STATE, "events.jsonl"))
               + glob.glob(os.path.join(STATE, "sprints", "*", "events.jsonl"))):
        try:
            with open(ev, encoding="utf-8") as fh:
                for i, line in enumerate(fh, 1):
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        obj = json.loads(line)
                    except json.JSONDecodeError:
                        errors.append(f"{os.path.relpath(ev, STATE)}:{i}: linha não é JSON")
                        continue
                    t = obj.get("type")
                    if not t or not any(str(t).startswith(p) for p in ("task.", "sprint.", "gate.")):
                        errors.append(f"{os.path.relpath(ev, STATE)}:{i}: evento sem 'type' canônico "
                                      f"(esperado task.*|sprint.*|gate.*; veio "
                                      f"{obj.get('type') or list(obj.keys())})")
        except OSError:
            pass
    if errors:
        print("[fable validate] FAIL:\n  " + "\n  ".join(errors))
        sys.exit(1)
    print("[fable validate] OK — todos os briefs canônicos.")


def find_sprint(sprint_id):
    p = os.path.join(STATE, "sprints", sprint_id, "sprint.json")
    if not os.path.exists(p):
        sys.exit(f"[fable] sprint {sprint_id} não encontrada em {p}")
    return p


def ops_ledger_map():
    led = os.path.join(STATE, "ops-validation.jsonl")
    seen = {}
    if os.path.isfile(led):
        for ln in open(led, encoding="utf-8", errors="replace"):
            ln = ln.strip()
            if not ln:
                continue
            try:
                d = json.loads(ln)
            except Exception:
                continue
            seen[(d.get("scope"), str(d.get("id")))] = d
    return led, seen


def audit_ops(sprint_id, sdir):
    """(v9-fix B / ops-verify) A sprint so fecha com PROVA de qualidade da operacao no ledger
    .swarm/state/ops-validation.jsonl: veredito ops-verify PASS+proof por SPRINT e por TASK COMMITTED.
    Espelha o accept-check --audit do INIT: sem o registro com evidencia, ARCHIVED e bloqueado."""
    led, seen = ops_ledger_map()
    if not os.path.isfile(led):
        return ["ledger de operacao ausente (.swarm/state/ops-validation.jsonl) — ops-verify nunca rodou"]
    bad = []
    e = seen.get(("sprint", str(sprint_id)))
    if not e or e.get("verdict") != "PASS":
        bad.append(f"sprint {sprint_id}: veredito ops-verify ausente/!=PASS (delegacao/objetivo/estado nao validados)")
    elif not str(e.get("proof") or "").strip():
        bad.append(f"sprint {sprint_id}: ops-verify PASS sem 'proof' — veredito sem evidencia (shallow)")
    for t in sorted(glob.glob(os.path.join(sdir, "tasks", "*.json"))):
        try:
            tj = load(t)
        except Exception:
            continue
        tid = str(tj.get("id") or os.path.basename(t)[:-5])
        if tj.get("status") != "COMMITTED":
            continue
        te = seen.get(("task", tid))
        if not te or te.get("verdict") != "PASS":
            bad.append(f"task {tid}: veredito ops-verify ausente/!=PASS (entrega/handoff nao validados)")
        elif not str(te.get("proof") or "").strip():
            bad.append(f"task {tid}: ops-verify PASS sem 'proof'")
    return bad


def transition_sprint(a):
    path = find_sprint(a.sprint)
    sj = load(path)
    cur, dst = sj.get("status"), a.to.upper()
    if dst not in SPRINT_MACHINE.get(cur, []):
        sys.exit(f"[fable] sprint: transição ilegal {cur} → {dst}. "
                 f"Permitidas: {SPRINT_MACHINE.get(cur)}")
    sdir = os.path.dirname(path)
    if dst == "ARCHIVED":
        bad = []
        for t in sorted(glob.glob(os.path.join(sdir, "tasks", "*.json"))):
            st = load(t).get("status")
            if st not in SPRINT_DONE:
                bad.append(f"{os.path.basename(t)}={st}")
        if bad:
            sys.exit("[fable] sprint ARCHIVED bloqueada — ACCEPTED sem commit é "
                     "ciclo aberto. Tasks fora de COMMITTED/CANCELLED:\n  "
                     + "\n  ".join(bad))
        opsbad = audit_ops(a.sprint, sdir)
        if opsbad:
            sys.exit("[fable] sprint ARCHIVED bloqueada — ops-verify (qualidade da operacao) "
                     "incompleto/sem prova:\n  " + "\n  ".join(opsbad)
                     + "\n  Rode o ops-verify (rubrica references/ops-verifier.md) por task e por "
                     "sprint e grave PASS+proof em .swarm/state/ops-validation.jsonl.")
    if dst == "ACTIVE":
        for other in glob.glob(os.path.join(STATE, "sprints", "*", "sprint.json")):
            if os.path.abspath(other) == os.path.abspath(path):
                continue
            o = load(other)
            if o.get("status") != "ARCHIVED" and not o.get("pre_migration"):
                sys.exit(f"[fable] sprint ACTIVE bloqueada: {o.get('id')} está "
                         f"{o.get('status')} — feche a anterior primeiro "
                         f"(--sprint {o.get('id')} --to ARCHIVED).")
    sj["status"] = dst
    save(path, sj)
    with open(os.path.join(sdir, "events.jsonl"), "a") as f:
        f.write(json.dumps({"type": f"sprint.{dst.lower()}",
                            "sprint": sj.get("id", a.sprint),
                            "actor": a.actor, "at": now()}, ensure_ascii=False) + "\n")
    print(f"[fable] {a.sprint}: {cur} → {dst}")


def record_learning(b, gr):
    """(v11) Veredito do verifier -> trajetória no learning.db. FAIL-SAFE por design:
    qualquer erro (sqlite ausente, I/O, store inexistente) é engolido e a transição
    segue IDÊNTICA ao v9. A memória é camada aditiva — nunca quebra o núcleo. A
    destilação trajetória->pattern roda no consolidate (/fechar-sprint), não aqui."""
    try:
        if os.environ.get("FABLE_LEARNING", "on").lower() == "off":
            return
        import sqlite3, time
        c = sqlite3.connect(os.path.join(STATE, "learning.db"))
        c.execute("CREATE TABLE IF NOT EXISTS trajectories("
                  "id TEXT PRIMARY KEY, agent TEXT, task TEXT, verdict TEXT, at INTEGER)")
        c.execute("INSERT OR REPLACE INTO trajectories VALUES(?,?,?,?,?)",
                  (b["id"], b.get("agent", "?"), (b.get("objective") or "")[:200],
                   "success" if gr.get("verdict") == "PASS" else "failure", int(time.time())))
        c.commit(); c.close()
    except Exception:
        pass  # degrada pro comportamento v9 — a memória nunca quebra a transição


def persist_gate(a):
    path = find_brief(a.task)
    b = load(path)
    if b["status"] != "VERIFYING":
        sys.exit(f"[fable] --gate exige status VERIFYING (atual: {b['status']}).")
    raw = open(a.gate[1:]).read() if a.gate.startswith("@") else a.gate
    try:
        gr = json.loads(raw)
    except json.JSONDecodeError as e:
        sys.exit(f"[fable] gate_report não é JSON válido: {e}")
    if gr.get("verdict") not in ("PASS", "FAIL"):
        sys.exit("[fable] gate_report.verdict deve ser PASS ou FAIL")
    crits = gr.get("criteria")
    if not isinstance(crits, list) or not crits or not all("pass" in c and "proof" in c for c in crits):
        sys.exit("[fable] gate_report.criteria: lista não-vazia, cada item com pass+proof")
    b["gate_report"] = gr
    save(path, b)
    event(path, {"type": "gate.report", "task": b["id"], "verdict": gr["verdict"],
                 "actor": a.actor, "at": now()})
    record_learning(b, gr)  # (v11) alimenta a memória com o veredito do verifier — fail-safe
    print(f"[fable] {b['id']}: gate_report {gr['verdict']} persistido")


def arbitrate(a):
    """(v9 F2.3 / D7) Registra a arbitragem do architect e libera REJECTED→READY."""
    path = find_brief(a.task)
    b = load(path)
    if b.get("status") != "REJECTED":
        sys.exit(f"[fable] --arbitrate exige status REJECTED (atual: {b.get('status')}).")
    arb = b.get("arbitration") or {}
    if not arb.get("required"):
        sys.exit("[fable] --arbitrate: nenhuma arbitragem pendente (nenhum criterio reprovado 2x).")
    if not str(a.arbitrate).strip():
        sys.exit("[fable] --arbitrate exige um relatorio nao-vazio do architect.")
    arb["architect_report"] = a.arbitrate
    arb["resolved"] = True
    b["arbitration"] = arb
    save(path, b)
    event(path, {"type": "task.arbitrated", "task": b["id"],
                 "criterion": arb.get("criterion_id"), "actor": a.actor, "at": now()})
    print(f"[fable] {b['id']}: arbitragem registrada ({arb.get('criterion_id')}) — REJECTED→READY liberado.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("task", nargs="?")
    ap.add_argument("--to")
    ap.add_argument("--gate", help="JSON do gate_report do verifier (ou @arquivo)")
    ap.add_argument("--sprint", help="máquina de sprint: --sprint SPRINT-NN --to STATE")
    ap.add_argument("--reason", default="")
    ap.add_argument("--actor", default="tech-lead")
    ap.add_argument("--validate-all", action="store_true")
    ap.add_argument("--audit-ops", action="store_true", help="(ops-verify) audita .swarm/state/ops-validation.jsonl de uma sprint")
    ap.add_argument("--arbitrate", help="(D7) registra arbitragem do architect e libera REJECTED→READY")
    a = ap.parse_args()

    if a.validate_all:
        return validate_all()
    if a.audit_ops:
        if not a.sprint:
            ap.error("--audit-ops exige --sprint SPRINT-NN")
        sdir = os.path.dirname(find_sprint(a.sprint))
        bad = audit_ops(a.sprint, sdir)
        if bad:
            print("[fable] ops-audit FALHOU:\n  " + "\n  ".join(bad)); sys.exit(1)
        print("[fable] ops-audit OK — operacao validada (task + sprint, com prova)"); return
    if a.sprint:
        if a.task or a.gate or not a.to:
            ap.error("--sprint acompanha --to STATE, sem TASK/--gate")
        return transition_sprint(a)
    if a.gate:
        if not a.task or a.to:
            ap.error("--gate acompanha TASK, sem --to (persistir e decidir são atos separados)")
        return persist_gate(a)
    if a.arbitrate is not None:
        if not a.task or a.to:
            ap.error("--arbitrate acompanha TASK, sem --to")
        return arbitrate(a)
    if not (a.task and a.to):
        ap.error("informe TASK e --to STATE, TASK e --gate, ou --validate-all")

    path = find_brief(a.task)
    b = load(path)
    errs = check_brief(b, path)
    if errs:
        sys.exit("[fable] brief inválido — corrija antes de transicionar:\n  " + "\n  ".join(errs))

    cur, dst = b["status"], a.to.upper()
    if dst not in MACHINE.get(cur, []):
        sys.exit(f"[fable] transição ilegal: {cur} → {dst}. Permitidas: {MACHINE.get(cur)}")

    if dst == "ACCEPTED":
        gr = b.get("gate_report") or {}
        if gr.get("verdict") != "PASS":
            sys.exit("[fable] ACCEPTED exige gate_report.verdict PASS (despache o verifier).")
    if dst == "DISPATCHED":
        branch = current_git_branch()
        if branch in ("main", "master"):
            sys.exit(f"[fable] DISPATCHED bloqueado na branch {branch}. "
                     "Crie/aprove uma branch de sprint antes de despachar.")
        # dependências precisam estar ACCEPTED/COMMITTED
        for dep in b.get("dependencies", []):
            d = load(find_brief(dep))
            if d["status"] not in ("ACCEPTED", "COMMITTED"):
                sys.exit(f"[fable] dependência {dep} em {d['status']} — não despachável.")
        # D6: runnability do verification_command — probe NÃO-MUTANTE antes do despacho.
        # probe_command vem do PROJECT_PROFILE.stacks[].probe_cmd (escopado à task).
        # Presente → E2 (roda e recusa em falha). Ausente → degradação E0 declarada.
        probe = b.get("probe_command")
        if probe:
            try:
                r = subprocess.run(probe, shell=True, cwd=ROOT,
                                   capture_output=True, text=True, timeout=120)
            except subprocess.TimeoutExpired:
                sys.exit(f"[fable] D6: probe de runnability estourou timeout — brief não despachável.\n  $ {probe}")
            if r.returncode != 0:
                tail = ((r.stderr or "") + (r.stdout or "")).strip()[-400:]
                sys.exit(f"[fable] D6: verification_command NÃO roda (probe exit {r.returncode}). "
                         f"Brief volta a DRAFT — corrija antes de despachar.\n  $ {probe}\n  {tail}")
            print("[fable] D6: probe de runnability OK")
        else:
            print("[fable] D6: brief sem probe_command — runnability não checada (degradação E0 nesta task).")
    if cur == "REJECTED" and dst == "READY":
        # (v9 F2.3 / D7) 2 rejeicoes no MESMO criterio exigem arbitragem do architect antes de re-tentar.
        arb = b.get("arbitration") or {}
        if arb.get("required") and not arb.get("resolved"):
            sys.exit(f"[fable] D7: REJECTED→READY bloqueado — criterio {arb.get('criterion_id')} reprovado "
                     f"2x sem arbitragem. Rode: transition.py {a.task} --arbitrate '<decisao>' --actor architect")
    if dst == "REJECTED":
        b["attempts"] = b.get("attempts", 0) + 1
        # (v9 F2.3 / D7) rastreia criterio reprovado pelo gate_report; 2x no mesmo criterio liga a
        # arbitragem obrigatoria (antes era so um aviso de tentativas — nao bloqueava nada).
        log = b.get("rejection_log") or {}
        repeat = None
        for i, c in enumerate((b.get("gate_report") or {}).get("criteria") or []):
            if isinstance(c, dict) and c.get("pass") is False:
                cid = str(c.get("id") or c.get("criterion") or c.get("name") or f"C{i+1}")
                log[cid] = log.get(cid, 0) + 1
                if log[cid] >= 2:
                    repeat = cid
        b["rejection_log"] = log
        if repeat:
            prev = b.get("arbitration") or {}
            b["arbitration"] = {"required": True, "criterion_id": repeat,
                                "architect_report": prev.get("architect_report"),
                                "resolved": bool(prev.get("architect_report"))}
            print(f"[fable] D7: criterio {repeat} reprovado {log[repeat]}x — arbitragem do architect "
                  f"obrigatoria antes de REJECTED→READY (use --arbitrate).")
        if b["attempts"] >= MAX_ATTEMPTS:
            print(f"[fable] atenção: {a.task} atingiu {b['attempts']} tentativas — "
                  f"próxima falha deve virar BLOCKED + decisão do usuário.")

    b["status"] = dst
    b["status_history"].append({"at": now(), "from": cur, "to": dst,
                                "actor": a.actor, "reason": a.reason})
    save(path, b)

    active = os.path.join(STATE, ".active-task.json")
    if dst in ("DISPATCHED", "IN_PROGRESS"):
        # (fix F5) propaga forbidden_explore + anchors para o guard de shell ler
        save(active, {"task_id": b["id"], "agent": b["agent"],
                      "allowed_paths": b["allowed_paths"],
                      "forbidden_explore": bool(b.get("forbidden_explore")),
                      "anchors": b.get("anchors") or [],
                      "brief_path": os.path.relpath(path, ROOT)})
    elif os.path.exists(active):
        os.remove(active)

    event(path, {"type": f"task.{dst.lower()}", "task": b["id"], "agent": b["agent"],
                 "actor": a.actor, "attempt": b.get("attempts", 0), "at": now()})
    print(f"[fable] {b['id']}: {cur} → {dst}")


if __name__ == "__main__":
    main()
