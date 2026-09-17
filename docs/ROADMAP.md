# CloudGuard — Roadmap

> **Status labels** (evidence-based — do not upgrade a status without the evidence it names):
>
> | Label | Meaning |
> | --- | --- |
> | **Implemented** | Code exists and the implementation for that item is materially present in the repo. Says nothing about whether it has been run. |
> | **Partial** | Some code/scaffolding exists but the capability is incomplete. |
> | **Validated** | Successfully exercised end-to-end through the documented workflow ([RUNBOOK.md](RUNBOOK.md)), with the run recorded. |
> | **Planned** | Accepted direction, not started. |
> | **Deferred** | Intentionally excluded from the current scope. |
>
> "Code exists but has never been deployed" is **Implemented** or **Partial**, never
> **Validated**. Phase exit criteria require **Validated**.

Current position: **Phase 1 — Private Wazuh Platform — in progress.** The Packer prerequisite
phase (B1, PB-1…PB-4) is COMPLETE. The three-account model is **accepted**
([DECISIONS.md](DECISIONS.md) D-014) and, per the operator, the **build-path migration to
Security has run**: `terraform/packer-build/` is applied in **Security**, a new
Security-owned golden AMI has been built and validated, and it has been **shared to Lab and
smoke-tested there**. This revision also fixed a circular Terraform dependency that the
prior revision's cross-account design had introduced, by splitting the Lab EC2 IAM identity
into its own persistent root applied first (D-018), and hardened the runtime EC2 (D-019).
Still remaining: retire the legacy Management build infrastructure, apply the persistent
identity root + artifact layer in Lab/Security (D-018), B2/B3, and the first runtime
apply/validate in **Lab**. This revision's own changes are **repository-only** — no
Terraform/Packer was run.

| Phase | Title | Status |
| --- | --- | --- |
| 0 | Repository / Project Foundation | Complete (merged) |
| 1 | Private Wazuh Platform | In progress — Packer prerequisite phase complete; three-account build migration to **Security** (D-014) **done, incl. golden AMI + Lab share** (operator-reported); one-directional cross-account dependency + EC2 hardening (D-018/D-019) done in code; persistent identity + artifact root apply, legacy-infra retirement, B2/B3, and runtime apply/validate in Lab remaining |
| 2 | AWS Security Sources | Planned |
| 3 | AWS Findings → Wazuh Integration | Planned |
| 4 | Selective Automated Response | Planned |
| 5 | Lab Workloads / Agents | Planned |
| 6 | End-to-End Validation / Portfolio Completion | Planned |

---

## Phase 0 — Repository / Project Foundation

Goal: the repository is self-describing — a new contributor can orient and resume work from
version control alone.

**Core deliverable — merged to `main`:**

| Item | Status |
| --- | --- |
| `README.md` as a real entry point | Complete |
| `AGENTS.md` (contributor guide: reading order, source-of-truth, continuity rules) | Complete |
| `CLAUDE.md` (tool-specific instruction file, defers to `AGENTS.md`) | Complete |
| `docs/PROJECT_CHARTER.md` | Complete |
| `docs/ARCHITECTURE.md` (current vs target, diagrams) | Complete |
| `docs/CURRENT_STATE.md` (handoff) | Complete — must be kept updated every substantial task |
| `docs/ROADMAP.md` | Complete (this file) |
| `docs/DECISIONS.md` | Complete |
| `docs/RUNBOOK.md` | Complete (runtime steps still *Not yet operational* — that is Phase 1 work, not a Phase 0 gap) |

Engineering-hygiene items below are **backlog**, not Phase 0 blockers — see [Backlog](#backlog).

---

## Phase 1 — Private Wazuh Platform  *(current)*

Goal: **the private single-node Wazuh deployment is deployable and Validated through SSM.**
Nothing in Phase 2+ starts until this is done. Canonical blocker/gap detail:
[CURRENT_STATE.md](CURRENT_STATE.md).

### Foundation (Implemented)

| Item | Status | Evidence |
| --- | --- | --- |
| Private VPC + single private subnet + private route table | Implemented | [networking.tf](../terraform/wazuh-project/networking.tf) |
| No IGW / no NAT | Implemented | absence by design; [DECISIONS.md](DECISIONS.md) D-002 |
| S3 gateway endpoint | Implemented | [endpoints.tf](../terraform/wazuh-project/endpoints.tf) |
| Interface endpoints (`ssm`, `ssmmessages`, `ec2messages`, `ecr.api`, `ecr.dkr`) + endpoint SG | Implemented | [endpoints.tf](../terraform/wazuh-project/endpoints.tf) |
| EC2 IAM role / instance profile / SSM core / scoped cross-account ECR pull + S3 read — Lab-owned, persistent | Implemented | [terraform/wazuh-runtime-identity/iam.tf](../terraform/wazuh-runtime-identity/iam.tf) (moved from `wazuh-project/roles.tf`, D-018); ARNs built from `var.security_account_id`, not owned resources |
| Private ECR repository **definitions** (3, immutable, scan-on-push) — Security-owned | Implemented | [terraform/wazuh-artifacts/ecr.tf](../terraform/wazuh-artifacts/ecr.tf) (moved from `wazuh-project/`, D-016) |
| S3 artifact bucket **definition** (private, SSE-S3, TLS-deny) — Security-owned | Implemented | [terraform/wazuh-artifacts/storage.tf](../terraform/wazuh-artifacts/storage.tf) (moved from `wazuh-project/`, D-016) |
| Packer base-AMI **definition** (Ubuntu 24.04 source, timestamped name) | Implemented | [wazuh-ami.pkr.hcl](../packer/wazuh-ami.pkr.hcl) |
| EC2 instance **definition** + templated user-data | Implemented | [ec2.tf](../terraform/wazuh-project/ec2.tf), [install-wazuh.sh.tftpl](../terraform/wazuh-project/scripts/install-wazuh.sh.tftpl) |

### Packer prerequisite phase — COMPLETE

| Item | Status | Evidence |
| --- | --- | --- |
| Correct base-AMI provisioning (Docker Engine, Compose plugin, AWS CLI v2, `vm.max_map_count`, SSM verify) | **Complete** | **B1** ([DECISIONS.md](DECISIONS.md) D-011) — proven by the successful build + smoke test (2026-09-07) |
| Persistent secure Packer build network (`terraform/packer-build/`: VPC/subnet/IGW/route/SG/SSM instance profile; fail-closed tag selectors; SSM interface; IMDSv2) | **Complete (Validated)** | **PB-1 / [DECISIONS.md](DECISIONS.md) D-012** — implemented, locally validated, `terraform apply`-d, exercised by a successful build |
| Line-ending handling (`.gitattributes` for `*.sh` / `*.tftpl` / `*.tf` / `*.hcl`) | **Complete** | **PB-2** — committed `bcb9013`; no CRLF issues in the build |
| SSM-agent assumption (Canonical Ubuntu 24.04 ships `amazon-ssm-agent`) | **Complete (Validated)** | **PB-3** — the successful build confirmed the agent is present, enabled, and active in the bake and in the AMI smoke test |
| Least-privilege Packer execution IAM (`cloud-secops-lab-packer-execution-role` + inline policy; `CloudGuardOperator` SSO trust; `assume_role`) | **Complete (Validated)** | **PB-4 / [DECISIONS.md](DECISIONS.md) D-013** — applied; first build exposed one missing entry (`ssm:StartSession` on `AWS-StartPortForwardingSession`), corrected narrowly; a subsequent build ran end-to-end through the role |
| Validated base AMI produced by the Packer workflow | **Complete (Validated)** | built + independently smoke-tested via Session Manager (Docker 29.8.0, Compose v5.5.1, AWS CLI v2.36.40, `vm.max_map_count = 262144`, Docker enabled, `ubuntu` in `docker` group, ssm-agent enabled/active, `/var/log/cloudguard-ami-build.txt` present). Evidence AMI `ami-0b1bf8942dfc0daf1` (`us-east-2`) — historical evidence, not a config constant |

### Three-account migration — build path DONE (operator-reported); artifact/runtime path REMAINING (D-014)

| Item | Status | Blocker / note |
| --- | --- | --- |
| Apply `terraform/packer-build/` in **Security** (`security-admin`) | **Done** (operator-reported) | account-agnostic code; ran unchanged |
| Build + validate a **new Security-owned** base AMI (`security`) | **Done** (operator-reported) | supersedes the Management-account `ami-0b1bf8942dfc0daf1` (now historical evidence only) |
| Share the golden AMI to **Lab** by launch permission (`PKR_VAR_lab_account_id`) | **Done** (operator-reported) | **D-015** — `ami_users` / `snapshot_users`; the cross-account IAM actions worked |
| Confirm Lab can launch the shared AMI + SSM smoke test | **Done** (operator-reported) | manual check + smoke test from `lab-admin` |
| Destroy the **legacy** Packer build infrastructure in **Management** | Planned | operator has not run this yet |
| Apply `terraform/wazuh-runtime-identity/` in **Lab** (`lab-admin`) | Planned | **D-018** — new persistent root; must apply **before** `wazuh-artifacts` |
| Apply `terraform/wazuh-artifacts/` in **Security** (`security-admin`), supplying the identity root's role ARN | Planned | **D-016/D-018** — persistent ECR + S3 + unconditional cross-account grant; single apply |

> "Done (operator-reported)" = the operator states these AWS actions succeeded; this repository
> pass made no AWS calls and recorded no independent evidence (no AMI id, no account id). See
> [CURRENT_STATE.md](CURRENT_STATE.md) → Migration status.

### Runtime Wazuh deployment — REMAINING (Planned)

| Item | Status | Blocker / note |
| --- | --- | --- |
| Checked-in Wazuh stack artifacts (Compose + cert-gen + manager/indexer/dashboard config, pinned to **4.14.7**) | Planned | **B3** (D-009) |
| S3 artifact publishing workflow (to the Security artifact bucket) | Planned | **B3**; depends on the publication-ordering decision (Open decision #1) |
| ECR image mirror/publish workflow (to the Security ECR repos, Wazuh **4.14.7**) | Planned | **B2** (D-009) |
| Cross-account access: ECR repo policy + S3 bucket policy for the Lab runtime | **Implemented in code, not applied** | `terraform/wazuh-artifacts/` grants `var.lab_runtime_role_arn` (**required**) unconditionally, in one apply (D-018) — the identity-side IAM lives in the new persistent `terraform/wazuh-runtime-identity/` root, applied first, so no re-apply is needed |
| ~~EC2 hardening: dedicated security group~~ | **Done (D-019)** | [security.tf](../terraform/wazuh-project/security.tf) — zero ingress; egress scoped to the VPC endpoints only |
| ~~EC2 hardening: explicit root volume sizing~~ | **Done (D-019)** | Encrypted `gp3`, 50 GB reference size |
| ~~EC2 hardening: IMDSv2 enforcement~~ | **Done (D-019)** | `http_tokens = "required"`, hop limit 1 |
| ~~Useful Terraform outputs~~ | **Done (D-019)** | `instance_id`, `ssm_start_session_command`, `security_group_id` |
| Publication ordering defined (prereqs → publish artifacts/images → host) | Planned | Open decision #1 in [CURRENT_STATE.md](CURRENT_STATE.md) |
| Runtime `terraform apply` of `terraform/wazuh-project/` in **Lab** (`10.0.0.0/16` VPC + EC2 from the shared AMI) | Planned | not applied — depends on `terraform/wazuh-artifacts/` being applied first (for its outputs), then B2/B3 |
| Remove the superseded `ecr.tf` / `storage.tf` from `terraform/wazuh-project/` | **Done** | resources removed; the root now consumes Security-owned ECR/S3 via explicit variables instead of owning them. `stash@{0}` still exists and now targets a deleted file — do not pop/apply/drop it; see [CURRENT_STATE.md](CURRENT_STATE.md) |
| Working Wazuh dashboard via SSM port forwarding | Planned | depends on the runtime deploy + B2/B3 |
| Full deploy → validate → destroy run of the runtime, recorded | Planned | **Phase-exit** gate |

### Phase 1 exit criteria

**Done:** `terraform apply` of `terraform/packer-build/` in **Security** → `packer build`
(assumes the execution role) → a new **Security-owned** base AMI built and smoke-tested →
shared to **Lab** by launch permission and **smoke-tested there** (operator-reported —
[CURRENT_STATE.md](CURRENT_STATE.md) → Migration status). The original Management-account
run of this same sequence (`ami-0b1bf8942dfc0daf1`, 2026-09-07) is now superseded evidence.

**Also done (this and the prior revision, repository-only):** `terraform/wazuh-project/` no
longer owns the ECR repositories, the S3 artifact bucket, or the EC2 IAM role — it consumes
all three from the Security artifact root and the new persistent Lab identity root
(`terraform/wazuh-runtime-identity/`, D-018) via explicit variables; the cross-account grant
in `terraform/wazuh-artifacts/` is now unconditional (single apply, no re-apply); the runtime
bootstrap no longer derives the ECR registry from its own (Lab) account identity; the runtime
EC2 gained a dedicated SG, IMDSv2, an encrypted root volume, and real outputs (D-019). **No
Terraform/Packer was run for this part.**

**Remaining:** retire the legacy Management build infrastructure → apply
`terraform/wazuh-runtime-identity/` in Lab → apply `terraform/wazuh-artifacts/` in Security
(supplying the identity root's role ARN, single apply) → B3 (artifact set + S3 publish,
Wazuh 4.14.7) → B2 (ECR image mirror) → apply `terraform/wazuh-project/` in Lab (supplying
both earlier roots' outputs — this is the **last** apply in the chain) → SSM shell → SSM
port-forward to a healthy dashboard (manager + indexer + dashboard up) → `terraform destroy`
of the runtime only → verified cleanup — with [RUNBOOK.md](RUNBOOK.md),
[DECISIONS.md](DECISIONS.md), and [CURRENT_STATE.md](CURRENT_STATE.md) updated to the real
commands and decisions.

---

## Phase 2 — AWS Security Sources

Goal: enable AWS-native detection and authoritative findings from code.

| Item | Status |
| --- | --- |
| CloudTrail (org/account trail to encrypted central bucket) | Planned |
| GuardDuty enabled | Planned |
| Security Hub enabled (authoritative aggregator) | Planned |
| Selected AWS Config (targeted rules only — not a conformance pack) | Planned |
| Appropriate logging / retention / encryption | Planned |
| Central security/logging storage layout + prefixes | Planned |

Non-goal for Phase 2: full compliance program; full Config coverage.

---

## Phase 3 — AWS Findings → Wazuh Integration

Goal: `Security Hub → EventBridge → Firehose → S3 → SQS → Wazuh`.

| Item | Status |
| --- | --- |
| EventBridge rule on Security Hub findings | Planned |
| Firehose delivery stream | Planned |
| S3 findings bucket (encrypted, lifecycle) | Planned |
| SQS queue (+ DLQ) | Planned |
| Wazuh-side ingestion of the queued findings | Planned |
| Validation: a real finding appears in Wazuh for analyst investigation | Planned |

Constraint: Wazuh presents findings for analysts; Security Hub stays authoritative
([DECISIONS.md](DECISIONS.md) D-003).

---

## Phase 4 — Selective Automated Response

Goal: `Security Hub/EventBridge → qualification/filter → Step Functions → controlled response`.

| Item | Status |
| --- | --- |
| EventBridge rule(s) for response triggers | Planned |
| Finding qualification / filter (small set of actionable types) | Planned |
| Step Functions workflow | Planned |
| Lambda remediation action(s) | Planned |
| SNS notification / approval path | Planned |
| Audit trail of automated actions | Planned |
| Validation: qualified finding remediated; non-qualified finding takes no automated action | Planned |

Constraint: response is selective, never universal ([DECISIONS.md](DECISIONS.md) D-004).

---

## Phase 5 — Lab Workloads / Agents

Goal: a disposable lab account (or, interim, lab resources) that generates telemetry.

| Item | Status |
| --- | --- |
| Windows test host | Planned |
| Linux test host | Planned |
| Wazuh agents enrolled to the manager | Planned |
| Test scenarios that generate endpoint telemetry and AWS findings | Planned |

---

## Phase 6 — End-to-End Validation / Portfolio Completion

Goal: prove the whole thing and capture portfolio evidence.

| Item | Status |
| --- | --- |
| Detection scenarios (documented + evidenced) | Planned |
| Investigation scenarios (CloudTrail + Wazuh) | Planned |
| Automated-response scenarios (selective) | Planned |
| Cost validation against the cost philosophy | Planned |
| Screenshots / evidence artifacts | Planned |
| Final architecture + portfolio documentation | Planned |

---

## Backlog

Engineering-hygiene work that is **not** a phase blocker. Pick up opportunistically; does not
gate Phase 0 completion or Phase 1 exit.

| Item | Notes |
| --- | --- |
| CI checks (`terraform fmt -check`, `validate`, `tflint`) | Low cost, high value; add when convenient — now **three** roots to cover |
| Contributor guide / PR checklist | Optional |
| Remote Terraform state backend + locking | Local state today; three roots and multiple accounts make this more attractive — revisit when the migration is done |
| S3 artifact bucket: versioning | The TLS-deny policy is now in `terraform/wazuh-artifacts/` (D-010); object versioning is still optional hardening |

---

## Deferred (not scheduled in any phase)

| Item | Reason |
| --- | --- |
| Public Wazuh dashboard (ALB + ACM + public DNS) | Not needed; SSM port forwarding suffices; avoids public exposure and recurring cost ([DECISIONS.md](DECISIONS.md) D-005) |
| Malware-analysis pipeline | Out of MVP scope ([PROJECT_CHARTER.md](PROJECT_CHARTER.md)); possible future expansion |
| Vulnerability-management pipeline | Out of MVP scope; possible future expansion |
| Multi-AZ / HA / multi-node Wazuh | Unnecessary complexity/cost for a temporary lab |

## Open (decision required, not yet Deferred or Planned)

| Item | Tracked in |
| --- | --- |
| Artifact/image **publication ordering** relative to the runtime apply | [CURRENT_STATE.md](CURRENT_STATE.md) Open decision #1 |
| Remote Terraform state backend (now 4 roots, 2 accounts) | [CURRENT_STATE.md](CURRENT_STATE.md) Open decision #2 |
| Artifact/image retention between lab sessions | [CURRENT_STATE.md](CURRENT_STATE.md) Open decision #3 |

**Resolved since the last revision:** multi-account transition → D-014 (was D-007);
separate artifact root/state → D-016; artifact-bucket encryption → D-010 (SSE-S3 + TLS,
CMK deferred); Wazuh version pin → 4.14.7 (D-009); circular Terraform dependency between
`wazuh-artifacts` and `wazuh-project` → D-018 (new persistent identity root, one-directional
apply order); EC2 hardening (SG, root volume, IMDSv2, outputs) → D-019.
