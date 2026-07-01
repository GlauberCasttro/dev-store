# Sprint Closure Protocol (7 Steps)

**Source:** `.swarm/core-spec.md` §6 (Fable v9, protocol_version 7)

Sprint closure is the **mandatory ceremony** to archive a sprint. The 7 steps are **ordered and non-skippable**. The `/fechar-sprint` skill should automate all 7; currently it only guides.

---

## The 7 Steps

### Step 1: Verify All Tasks Are COMMITTED or CANCELLED

```bash
python3 .swarm/scripts-harness/transition.py --validate-all
```

- No task may be in ACCEPTED, DRAFT, or DISPATCHED
- ACCEPTED without commit = open cycle (blocker)
- `transition.py --sprint X --to ARCHIVED` refuses any other state

**Proof:** `git log --oneline | head -N` shows commits for each COMMITTED task.

---

### Step 2: Run ops-verify (OPS-4/5/6)

Create evidence in `.swarm/state/ops-validation.jsonl`:

```json
{"type": "ops.verify", "scope": "sprint", "id": "SPRINT-NN", "verdict": "PASS", "proof": "..."}
{"type": "ops.verify", "scope": "task", "id": "TASK-NN-XX", "verdict": "PASS", "proof": "..."}
```

**Rubric:**
- **OPS-4 (Objective delivered):** All sprint tasks achieved acceptance criteria
- **OPS-5 (Delegation good):** Right agent, minimal scope, no scope creep
- **OPS-6 (State clean):** No loose files, no merge conflicts, no uncommitted migrations

**Proof format:** Narrative evidence (file:line references, metrics, before/after).

`transition.py --sprint X --to ARCHIVED` **blocks** without this (binding gate).

---

### Step 3: Run consolidate-memory.py

```bash
python3 .swarm/scripts-harness/consolidate-memory.py \
  --events .swarm/state/sprints/SPRINT-NN/events.jsonl \
  --store .swarm/knowledge/memory/conhecimento.jsonl
```

**What it does:**
- Mines `events.jsonl` for failure patterns
- Proposes semantic lessons (episodic → semantic abstraction)
- Suggests decay for unused lessons

**Curator decision:** Accept/reject proposals, commit changes.

---

### Step 4: Run harvest-rejections.py

```bash
python3 .swarm/scripts-harness/harvest-rejections.py
```

**What it does:**
- Collects all REJECTED tasks from the sprint
- Converts to domain slice candidates (`knowledge/domain/<agent>.yaml`)
- Adds `source`, `confidence: unverified`

**Curator decision:** Integrate into domain slices or reject.

---

### Step 5: Transition Sprint to ARCHIVED

```bash
python3 .swarm/scripts-harness/transition.py --sprint SPRINT-NN --to ARCHIVED
```

**Pre-conditions (validated by tool):**
- All tasks COMMITTED or CANCELLED ✓ (Step 1)
- ops-validation.jsonl has PASS verdicts ✓ (Step 2)

**Outcome:**
- `sprint.json` status: ACTIVE → ARCHIVED
- `events.jsonl` logs the transition
- `.swarm/state/sprints/SPRINT-NN/` remains until Step 6

---

### Step 6: Archive Briefs + Logs

Move entire sprint directory to archive and update indices:

```bash
mkdir -p .swarm/archive
mv .swarm/state/sprints/SPRINT-NN .swarm/archive/SPRINT-NN
# Update any sprint indices if they exist
```

**Outcome:**
- `.swarm/archive/SPRINT-NN/` contains:
  - `sprint.json` (ARCHIVED status)
  - `tasks/*.json` (all COMMITTED task briefs)
  - `events.jsonl` (full sprint event log)
- `.swarm/state/sprints/SPRINT-NN/` no longer exists
- Sprint-active tools can no longer reference it

**Indices:** If `.swarm/state/sprints/index.json` or similar exists, remove SPRINT-NN entry.

---

### Step 7: Propose & Commit

Stage and commit all changes:

```bash
git add .swarm/state/ .swarm/knowledge/ .swarm/archive/
git commit -m "chore: archive SPRINT-NN (7-step closure complete)

[ops-verify PASS, memory consolidated, rejections harvested]
[all tasks COMMITTED, state clean]

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

**Approval:** Human (tech-lead) reviews diff and confirms commit.

**Outcome:**
- Closure is now in git history (reversible but requires reset)
- `.accept-ok` may be re-cunhado if harness allows

---

## Implementation Status

| Step | Automated? | Tool | Notes |
|---|---|---|---|
| 1 | ✓ | `transition.py --validate-all` | Blocking gate in step 5 |
| 2 | ✗ (manual) | User creates `ops-validation.jsonl` | Gate for step 5 |
| 3 | ✓ | `consolidate-memory.py` | Curator reviews proposals |
| 4 | ✓ | `harvest-rejections.py` | Curator integrates results |
| 5 | ✓ | `transition.py --sprint X --to ARCHIVED` | Validates steps 1+2 |
| 6 | ✗ (manual) | `mv` + index update | Can be automated |
| 7 | ✗ (manual) | `git add/commit` | Requires human approval |

**TODO:** Integrate steps 1,3,4,5,6 into `/fechar-sprint` skill for single-command execution.

---

## Error Handling

| Error | Cause | Fix |
|---|---|---|
| "ARCHIVED bloqueada — ACCEPTED sem commit" | Step 1 failed | Return ACCEPTED tasks to dev agent |
| "ops-verify ausente/!=PASS" | Step 2 failed | Create/fix `ops-validation.jsonl` |
| "sprint not found" | Step 6 already run | Check `.swarm/archive/` |
| Pre-commit hook fails | Step 7 issue | Fix violations, re-stage, re-commit |

---

## Reference

- Full spec: `.swarm/core-spec.md` §6
- Example closure: `.swarm/archive/SPRINT-00/` (first closure)
- Memory schema: `.swarm/knowledge/memory/MEMORY-SCHEMA.md`
