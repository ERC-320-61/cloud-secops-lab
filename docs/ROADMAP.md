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

Current position: **Phase 1 — Private Wazuh Platform — in progress. The Packer prerequisite
phase (B1, PB-1…PB-4) is COMPLETE and a validated base AMI exists. The runtime Wazuh
deployment (VPC `10.0.0.0/16`, B2, B3, end-to-end SSM validation) is the remaining work.**

| Phase | Title | Status |
| --- | --- | --- |
| 0 | Repository / Project Foundation | Complete (merged) |
| 1 | Private Wazuh Platform | In progress — Packer prerequisite phase + validated base AMI **complete**; runtime Wazuh deployment (B2/B3/apply/validate) remaining |
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
| EC2 IAM role / instance profile / SSM core / scoped ECR pull / scoped S3 read | Implemented | [roles.tf](../terraform/wazuh-project/roles.tf) |
| Private ECR repository **definitions** (3, immutable, scan-on-push) | Implemented | [ecr.tf](../terraform/wazuh-project/ecr.tf) |
| S3 artifact bucket **definition** (private, SSE-S3) | Implemented | [storage.tf](../terraform/wazuh-project/storage.tf) |
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

### Runtime Wazuh deployment — REMAINING (Planned)

| Item | Status | Blocker / note |
| --- | --- | --- |
| Checked-in Wazuh stack artifacts (Compose + cert-gen + manager/indexer/dashboard config, deliberately pinned version) | Planned | **B3** |
| S3 artifact publishing workflow | Planned | **B3**; depends on the bootstrap-lifecycle decision (Open decision #1/#2) |
| ECR image mirror/publish workflow | Planned | **B2**; depends on the pinned version (Open decision #5) |
| EC2 hardening: dedicated security group | Planned | Phase 1 completion gap |
| EC2 hardening: explicit root volume sizing | Planned | Phase 1 completion gap (~50 GB is a reference, not a requirement) |
| EC2 hardening: IMDSv2 enforcement (`http_tokens = "required"`) | Planned | Phase 1 completion gap |
| Useful Terraform outputs (runtime instance id, bucket, SSM command) | Planned | [outputs.tf](../terraform/wazuh-project/outputs.tf) empty |
| Bootstrap lifecycle defined (prereqs → publish artifacts/images → host) | Planned | Open decision #1/#2 in [CURRENT_STATE.md](CURRENT_STATE.md) |
| Runtime `terraform apply` of `terraform/wazuh-project/` (`10.0.0.0/16` VPC + EC2 from the base AMI) | Planned | not applied — depends on B2/B3 + the bootstrap decision |
| Working Wazuh dashboard via SSM port forwarding | Planned | depends on the runtime deploy + B2/B3 |
| Full deploy → validate → destroy run of the runtime, recorded | Planned | **Phase-exit** gate |

### Phase 1 exit criteria

**Done:** `terraform apply` of `terraform/packer-build/` (persistent) → `packer build`
(assumes the execution role) → base AMI built and smoke-tested.

**Remaining:** decide the bootstrap lifecycle + Wazuh version → B3 (artifact set + S3
publish) → B2 (ECR image mirror) → EC2 hardening + runtime outputs → `terraform apply` of
`terraform/wazuh-project/` with the validated AMI → SSM shell into the instance → SSM
port-forward to a healthy dashboard (manager + indexer + dashboard up) → `terraform destroy`
of the runtime only → verified cleanup — with [RUNBOOK.md](RUNBOOK.md), [DECISIONS.md](DECISIONS.md),
and [CURRENT_STATE.md](CURRENT_STATE.md) updated to the real commands and decisions.

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
| CI checks (`terraform fmt -check`, `validate`, `tflint`) | Low cost, high value; add when convenient |
| Contributor guide / PR checklist | Optional |
| Remote Terraform state backend + locking | Acceptable as local state for a single operator; revisit if multiple operators or if state must be shared |
| S3 artifact bucket: versioning + TLS-only bucket policy | Hardening; fold into Phase 1 completion if cheap |

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
| Artifact/image persistence between lab sessions vs. `terraform destroy` | [CURRENT_STATE.md](CURRENT_STATE.md) Open decision #1 |
| Separate Terraform lifecycle/state for artifact-bootstrap infrastructure | Open decision #2 |
| Multi-account transition point | [DECISIONS.md](DECISIONS.md) D-007 (Proposed) |
| Phase 1 artifact bucket encryption — SSE-S3 vs. customer-managed KMS key | [DECISIONS.md](DECISIONS.md) D-010 (Proposed) |
| Wazuh version to pin when artifacts/images are (re)built | Open decision #5 |
