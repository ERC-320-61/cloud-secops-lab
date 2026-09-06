# AGENTS.md — Start Here (AI Coding Agents)

You are working in **CloudGuard** (`cloud-secops-lab`): a reusable AWS cloud security
operations lab. **The repository is the project memory.** Do not assume any previous
ChatGPT / Claude / Codex / other conversation history is available. Everything you need is in
version control.

---

## 1. Required reading order

Read these before making any change:

1. [README.md](README.md) — what the project is, current vs. target at a glance
2. [docs/PROJECT_CHARTER.md](docs/PROJECT_CHARTER.md) — purpose, scope, MVP, non-goals
3. [docs/CURRENT_STATE.md](docs/CURRENT_STATE.md) — **development handoff: phase, blockers, exact next task**
4. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — current vs. target architecture + diagrams
5. [docs/ROADMAP.md](docs/ROADMAP.md) — phased plan and status labels
6. [docs/DECISIONS.md](docs/DECISIONS.md) — accepted architectural decisions
7. [docs/RUNBOOK.md](docs/RUNBOOK.md) — deploy/validate/destroy steps (many marked *Not yet operational*)

Then inspect the live repository:

```bash
git status
git log --oneline -10
git diff            # understand any existing working-tree changes before touching them
```

And read the implementation files relevant to your task, primarily under
[terraform/wazuh-project/](terraform/wazuh-project/) and [packer/](packer/).

---

## 2. Source-of-truth precedence

When sources disagree, trust them in this order:

1. **Actual code / implementation** — for what currently exists.
2. **Git history / working tree** — for recent development state.
3. **[docs/CURRENT_STATE.md](docs/CURRENT_STATE.md)** — for project handoff / status / next task.
4. **[docs/PROJECT_CHARTER.md](docs/PROJECT_CHARTER.md)** — for purpose / scope.
5. **[docs/DECISIONS.md](docs/DECISIONS.md)** — for accepted architectural decisions.
6. **[docs/ROADMAP.md](docs/ROADMAP.md)** — for intended future sequencing.

**Do not assume a roadmap or architecture item is implemented just because it is written
down.** Verify against code. Documentation describes intent and known state; code is the
truth for what exists.

---

## 3. Rules of engagement

- **Verify current repository state before implementing.** Re-run `git status` / `git diff`;
  do not rely on a stale mental model.
- **Preserve existing unrelated working-tree changes.** There may be an uncommitted edit
  (e.g. `terraform/wazuh-project/ecr.tf`). Do not discard, revert, or overwrite changes you
  did not make. If they conflict with your task, stop and ask.
- **Stay in phase.** Work only on the current phase's next task
  ([CURRENT_STATE.md](docs/CURRENT_STATE.md)) unless explicitly told otherwise. Do not start
  Phase 2+ (CloudTrail, GuardDuty, Security Hub, Config, EventBridge, Firehose, SQS, Step
  Functions, Lambda, SNS, agents, lab workloads) while Phase 1 is incomplete.
- **Do not silently reverse an Accepted decision** in [DECISIONS.md](docs/DECISIONS.md). To
  change one, add a superseding entry and update affected docs.
- **Distinguish implementation from planned architecture** in everything you write.
- **Avoid unnecessary AWS cost.** No NAT Gateway; no always-on services that aren't needed;
  destroy environments after validation.
- **Do not make public infrastructure the default.** No ALB / public IP / public dashboard
  for administration. SSM is the access path.
- **Avoid unnecessary abstractions.** One Terraform root module until there's a concrete
  reason to split. No speculative modules/wrappers.
- **Do not deploy or spend without being asked.** No `terraform apply`/`destroy`, Packer
  build, ECR push, or other AWS mutation unless the task explicitly calls for it.

---

## 4. End-of-work requirement (continuity)

Before you finish a **substantial** development task, you **must** update
[docs/CURRENT_STATE.md](docs/CURRENT_STATE.md) so the next contextless agent is not misled.
Update its Snapshot plus:

- work completed;
- work left incomplete;
- new or resolved blockers;
- relevant changed files;
- the next logical task and its prerequisites;
- any assumptions another agent needs to know.

Also update, when applicable:

| If you changed... | Update |
| --- | --- |
| An architectural decision (or made a new one) | [docs/DECISIONS.md](docs/DECISIONS.md) |
| The architecture materially (new components, changed data flow) | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Phase scope or item status | [docs/ROADMAP.md](docs/ROADMAP.md) |
| Operational steps (a step became operational, commands changed) | [docs/RUNBOOK.md](docs/RUNBOOK.md) |
| The high-level project summary or current/target split | [README.md](README.md) |

You do **not** need doc updates for trivial edits (typos, formatting, comments). You **do**
need them whenever skipping the update could cause the next agent to misunderstand project
state.

Do not commit unless the human explicitly asks. When you do, keep documentation updates in
the same commit/PR as the implementation change they describe.

---

## 5. Fast facts

Stable facts only. **Volatile state — current phase, exact next task, active blockers, open
decisions — lives solely in [docs/CURRENT_STATE.md](docs/CURRENT_STATE.md); do not copy it
here.**

| | |
| --- | --- |
| Project | CloudGuard / `cloud-secops-lab` — reusable AWS SecOps lab |
| Region | `us-east-2` · VPC `10.0.0.0/16` · private subnet `10.0.1.0/24` |
| Access model | AWS Systems Manager (Session Manager + port forwarding); no public admin |
| Lifecycle | deploy → test → validate → document → destroy |
| Only Terraform module | [terraform/wazuh-project/](terraform/wazuh-project/) |
| Current phase / next task / blockers / open decisions | **See [docs/CURRENT_STATE.md](docs/CURRENT_STATE.md)** |
| Roadmap + status model | [docs/ROADMAP.md](docs/ROADMAP.md) |
| Not part of the MVP at all | malware-analysis pipeline, vulnerability-management pipeline (possible future expansion — [docs/PROJECT_CHARTER.md](docs/PROJECT_CHARTER.md)) |
| Deferred for the current phase (may return later) | public Wazuh dashboard (ALB/ACM), multi-AZ/HA Wazuh — [docs/DECISIONS.md](docs/DECISIONS.md) |
