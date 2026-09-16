# CloudGuard — Current State (Development Handoff)

> **This is the primary handoff document.** Read it immediately after
> [PROJECT_CHARTER.md](PROJECT_CHARTER.md), then verify it against actual code and
> `git status` before doing anything.
>
> Update rule: anyone who performs a **substantial** development task must update this
> file before finishing. See [../AGENTS.md](../AGENTS.md).

---

## Snapshot

| Field | Value |
| --- | --- |
| Last updated | 2026-09-08 |
| Updated by | Multi-account restructure: adopted the three-account model (D-014), added Security-owned golden-AMI sharing to Lab (D-015), created the persistent artifact root `terraform/wazuh-artifacts/` (D-016), pinned Wazuh 4.14.7, resolved D-010. **Repository changes only — no AWS mutation.** |
| Active branch | `feat/multi-account-cloudguard` (not merged) |
| Default branch | `main` |
| Recent milestones | *(this)* three-account restructure (D-014/D-015/D-016) · `8e5e72d` finalize Packer prerequisite validation · `19ce7a8` least-privilege Packer execution role (PB-4/D-013) · `d790992` secure Packer build infrastructure (PB-1/D-012) · `bcb9013` base-AMI provisioning (B1) |
| Current phase | **Phase 1 — Private Wazuh Platform** |
| Phase status | **IN PROGRESS.** Packer prerequisite phase (B1, PB-1…PB-4) is **COMPLETE** and a **validated base AMI** exists — **but in the Management account** (legacy placement). The three-account model is now **accepted** (D-014) and Phase 1 now also covers: migrate the build path to **Security**, build a new Security-owned AMI + share to **Lab**, retire the Management copy, apply the persistent artifact layer in Security, then B2/B3, hardening, and the first runtime apply in **Lab**. **Nothing has been applied in Security or Lab.** |
| Validation status | **Base AMI = VALIDATED** in Management (`ami-0b1bf8942dfc0daf1`, built + smoke-tested 2026-09-07). Packer build network + execution role = applied and build-validated **in Management**. Everything Security-side and Lab-side (including the new `wazuh-artifacts` root and the AMI-sharing config) = **implemented in code, not applied, not exercised**. |

### Validation record

**Local static checks (operator workstation)** — Terraform `v1.16.1`, AWS CLI `2.36.37`,
Session Manager Plugin `1.2.835.0`, Packer (Amazon plugin `v1.8.2`). `terraform -chdir=terraform/packer-build fmt -check / init / validate`
and `packer fmt -check . / init . / validate .` all pass.

**Successful Packer build (2026-09-07).** Base credentials `CloudGuardOperator` →
`sts:AssumeRole` `cloud-secops-lab-packer-execution-role` → selected the dedicated build
VPC/subnet/SG by tag → launched a temporary builder → connected over **Session Manager port
forwarding** (`AWS-StartPortForwardingSession`) → ran `scripts/install-wazuh-base.sh` →
created an AMI → terminated the temporary instance → deleted the temporary key pair. The
first build had exposed exactly one missing IAM entry (`ssm:StartSession` on
`AWS-StartPortForwardingSession`), which was added narrowly; the next build succeeded.

Bake output: **Docker 29.8.0 · Docker Compose v5.5.1 · AWS CLI v2.36.40 ·
`vm.max_map_count = 262144` · Docker enabled · `ubuntu` in `docker` group ·
`amazon-ssm-agent` enabled + active**.

**AMI smoke test (2026-09-07).** A manual EC2 instance launched from the new AMI and
independently verified via Session Manager: `docker --version`, `docker compose version`,
`aws --version` all work; `sysctl -n vm.max_map_count` → `262144`; `systemctl is-enabled docker`
→ `enabled`; `systemctl is-active docker` → `active`; `snap services amazon-ssm-agent` →
enabled/active; `ubuntu` in the `docker` group; `/var/log/cloudguard-ami-build.txt` present
with the expected build marker. → **AMI = VALIDATED.**

Evidence AMI: `ami-0b1bf8942dfc0daf1` (`us-east-2`, **Management account**). *Historical
validation evidence only — not a config constant, not the future Security-owned AMI.* Under
D-014 a **new AMI must be built in the Security account** and shared to Lab; this id is not
carried forward. `var.wazuh_ami_id` takes an explicit value chosen at deploy time. The
smoke-test instance is disposable and not part of the persistent architecture.

`terraform/packer-build/.terraform.lock.hcl` is committed and is intentional
**source-controlled dependency metadata**. `terraform/packer-build/.terraform/` and provider
binaries stay git-ignored.

### Repository / working-tree note

The Packer prerequisite phase is on `main` (`8e5e72d`). The current branch
`feat/multi-account-cloudguard` adds the three-account restructure (this pass):
`terraform/packer-build/` comments + the AMI-sharing IAM statement, the Packer `ami_users` /
`snapshot_users` config + `packer/ami-sharing.pkr.hcl`, the new
`terraform/wazuh-artifacts/` root, a `terraform/wazuh-project/providers.tf` placement note,
and the doc updates. **No `terraform apply` / `packer build` / AWS mutation.**

**Known unrelated working-tree changes** — CRLF→LF renormalization only, deliberately left
alone and **not** to be absorbed into this branch's commit:
`terraform/wazuh-project/{ec2,ecr,roles,storage}.tf` and `packer/variables.pkr.hcl`.

**`git stash@{0}` ("preserve ecr comment changes")** — a comment-only change to
`terraform/wazuh-project/ecr.tf`. Do not pop/apply/drop it. It **blocks** removing the
superseded `terraform/wazuh-project/ecr.tf` (and, for reference-integrity,
`storage.tf` + the ECR/S3 references in `roles.tf`/`ec2.tf`): deleting `ecr.tf` would make
the stash un-appliable. The legacy ECR/S3 definitions therefore stay in `wazuh-project/` for
now — superseded by `terraform/wazuh-artifacts/` (D-016) but not yet removed.

---

## Last completed meaningful milestone

**Three-account restructure — repository changes only (D-014 / D-015 / D-016).** This pass:
adopted the Management / Security / Lab model with named permission sets (D-014); made
`terraform/packer-build/` explicitly Security-targeted (comments only — the code was already
account-agnostic); added Security→Lab golden-AMI sharing by launch permission
(`ami_users` / `snapshot_users` = required `var.lab_account_id`, `packer/ami-sharing.pkr.hcl`,
+ two narrow IAM actions on the execution role) (D-015); created the persistent
`terraform/wazuh-artifacts/` root (ECR + S3, SSE-S3 + TLS-deny, Security account) (D-016);
pinned Wazuh **4.14.7** (D-009); resolved the artifact-encryption question (D-010). **No AWS
mutation. Nothing applied in Security or Lab.**

### Prior milestone: Packer prerequisite phase — COMPLETE, with a validated base AMI (in Management)

- **B1** — the bake script (`packer/scripts/install-wazuh-base.sh`) installs stable host
  prerequisites only; proven by the successful build + smoke test (D-011).
- **PB-1 / D-012** — a persistent, isolated, secure Packer build network
  (`terraform/packer-build/`): VPC `10.10.0.0/24`, one subnet (`map_public_ip_on_launch = false`),
  IGW + default route, builder SG with **no ingress** + egress TCP 80/443 only, builder SSM
  role/profile. **Applied** and exercised by a real build.
- **PB-2** — `.gitattributes` forces LF for `*.sh` / `*.tftpl` / `*.tf` / `*.hcl`; no CRLF
  issues in the build.
- **PB-3** — Canonical Ubuntu 24.04 ships `amazon-ssm-agent`; the successful build + smoke
  test confirmed it is present, enabled, and active.
- **PB-4 / D-013** — least-privilege Packer **execution role**
  (`cloud-secops-lab-packer-execution-role`), assumed from `CloudGuardOperator`, separate
  from the builder role. **Applied.** The first build exposed one missing IAM entry
  (`ssm:StartSession` on `AWS-StartPortForwardingSession`); corrected narrowly; a subsequent
  build ran end-to-end through the role.
- **Base AMI** — built and independently smoke-tested via Session Manager → **VALIDATED**
  (see *Validation record*).

---

## Components in code

> "In code" = implementation present in the repo. Applied state is called out per section.
> **Only** the legacy `terraform/packer-build/` + AMI in **Management** are applied anywhere.

### Wazuh runtime — `terraform/wazuh-project/` (Lab account) — **NOT APPLIED**

| Component | File(s) |
| --- | --- |
| VPC `10.0.0.0/16`, private subnet `10.0.1.0/24` (`us-east-2a`), private route table + association | [networking.tf](../terraform/wazuh-project/networking.tf) |
| S3 gateway endpoint on the private route table | [endpoints.tf](../terraform/wazuh-project/endpoints.tf) |
| Interface endpoints: `ssm`, `ssmmessages`, `ec2messages`, `ecr.api`, `ecr.dkr` + endpoint SG (443 from subnet) | [endpoints.tf](../terraform/wazuh-project/endpoints.tf) |
| EC2 IAM role, instance profile, `AmazonSSMManagedInstanceCore`, scoped ECR pull, scoped S3 read (`wazuh/*`) | [roles.tf](../terraform/wazuh-project/roles.tf) |
| Provider pinning: `hashicorp/aws ~> 6.57.0`, Terraform `>= 1.7.0`, region from `var.aws_region` | [providers.tf](../terraform/wazuh-project/providers.tf) |
| Input variables (`project_name`, `aws_region`, `availability_zone`, `vpc_cidr`, `subnet_cidr`, `wazuh_ami_id`, `wazuh_instance_type`) | [variables.tf](../terraform/wazuh-project/variables.tf) |

### Persistent Packer build infrastructure — `terraform/packer-build/` (D-012 / D-013) — **APPLIED IN MANAGEMENT; migrate to Security**

| Component | File(s) |
| --- | --- |
| Build VPC `10.10.0.0/24` (isolated from the runtime `10.0.0.0/16` — no peering / TGW), DNS support + hostnames | [network.tf](../terraform/packer-build/network.tf) |
| One build subnet, `map_public_ip_on_launch = false` | [network.tf](../terraform/packer-build/network.tf) |
| Internet Gateway + `0.0.0.0/0` route + association | [network.tf](../terraform/packer-build/network.tf) |
| Builder security group — **no ingress**; egress TCP 80 + 443 to `0.0.0.0/0` only | [network.tf](../terraform/packer-build/network.tf) |
| Builder IAM role (`cloud-secops-lab-packer-build-ssm-role`) + `AmazonSSMManagedInstanceCore` **only** + instance profile | [iam.tf](../terraform/packer-build/iam.tf) |
| **Packer execution role** (`cloud-secops-lab-packer-execution-role`) + least-privilege inline policy (`CloudGuardOperator` SSO trust; account ID via `data.aws_caller_identity`) | [packer-execution-role.tf](../terraform/packer-build/packer-execution-role.tf) |
| Outputs (vpc/subnet/sg ids, instance-profile name, builder role ARN, **`packer_execution_role_arn`**, selector tags) | [outputs.tf](../terraform/packer-build/outputs.tf) |

Status: **applied in the Management account** and exercised by a successful `packer build`.
This root is **persistent supporting infrastructure** — deliberately outside the Wazuh
runtime deploy→…→destroy cycle, no hourly cost (control-plane objects only). **D-014
migration: re-apply this in the Security account (`security-admin`), then destroy the
Management copy.** The code needs no change; only comments were updated this pass.

### Persistent Wazuh artifact layer — `terraform/wazuh-artifacts/` (D-016) — **NOT APPLIED**

| Component | File(s) |
| --- | --- |
| 3 private ECR repos (`wazuh-manager` / `-indexer` / `-dashboard`, `IMMUTABLE`, scan-on-push, `for_each`) | [ecr.tf](../terraform/wazuh-artifacts/ecr.tf) |
| S3 artifact bucket (`${project}-artifacts-${account_id}`), block-public-access, SSE-S3 AES256, bucket policy **denying non-TLS** (D-010) | [storage.tf](../terraform/wazuh-artifacts/storage.tf) |
| Outputs (ECR repo URL/ARN maps, bucket name/ARN) | [outputs.tf](../terraform/wazuh-artifacts/outputs.tf) |
| Provider pin `hashicorp/aws ~> 6.57.0`, Terraform `>= 1.7.0`, region `us-east-2` | [providers.tf](../terraform/wazuh-artifacts/providers.tf) |

Status: **implemented in code, never applied.** Belongs in the **Security** account
(`security-admin`). Persistent — not part of the runtime destroy cycle. Scope is the
persistent infrastructure only: **no** image-mirror workflow (B2), **no** Wazuh artifact set
(B3), **no** cross-account ECR/S3 policy yet.

### Golden-AMI cross-account share (D-015) — **NOT EXERCISED**

`packer/wazuh-ami.pkr.hcl` sets `ami_users` / `snapshot_users` to `[var.lab_account_id]`;
`packer/ami-sharing.pkr.hcl` declares the required (no-default) `lab_account_id` variable;
`terraform/packer-build/packer-execution-role.tf` adds `ec2:ModifyImageAttribute` +
`ec2:ModifySnapshotAttribute` scoped to this region's `image/*` / `snapshot/*`. Never run.
Boot volume is unencrypted → no KMS involved (a CMK would be needed only if boot encryption
is added later — deferred).

---

## Incomplete components (Partial)

| Component | What exists | What's missing |
| --- | --- | --- |
| ECR repositories (persistent) | New root [terraform/wazuh-artifacts/ecr.tf](../terraform/wazuh-artifacts/ecr.tf) — 3 repos, `IMMUTABLE`, scan-on-push. Legacy superseded copy still in [wazuh-project/ecr.tf](../terraform/wazuh-project/ecr.tf) | Not applied; no image-mirror workflow (B2); no cross-account pull policy; legacy copy not yet removed (stash-blocked) |
| S3 artifact bucket (persistent) | New root [terraform/wazuh-artifacts/storage.tf](../terraform/wazuh-artifacts/storage.tf) — bucket + block-public-access + SSE-S3 + TLS-deny policy. Legacy superseded copy still in [wazuh-project/storage.tf](../terraform/wazuh-project/storage.tf) | Not applied; empty; no checked-in Wazuh artifact set (B3); no publish workflow; no cross-account read policy; no object versioning; legacy copy not yet removed |
| Wazuh **runtime** EC2 instance (Lab) | Resource with instance profile, private subnet, templated user-data ([ec2.tf](../terraform/wazuh-project/ec2.tf)) | Runtime not applied. No dedicated security group; no explicit `root_block_device`; no `metadata_options` (IMDSv2). Must consume the **shared Security-owned AMI** (D-015) |
| EC2 user-data | Template does S3 sync + ECR login + `docker compose pull/up` + cert generation ([install-wazuh.sh.tftpl](../terraform/wazuh-project/scripts/install-wazuh.sh.tftpl)) | Depends on ECR images and S3 artifacts that don't exist (B2/B3), now **cross-account** (Security-owned); `aws sts get-caller-identity` for the registry host will resolve to the **Lab** account and needs the Security registry id instead; no health/wait/verification logic |
| Terraform outputs (runtime root) | — | [outputs.tf](../terraform/wazuh-project/outputs.tf) is an empty placeholder |

---

## Not implemented (Planned)

CloudTrail · GuardDuty · Security Hub · AWS Config · CloudWatch (log groups/alarms) ·
EventBridge · Firehose · SQS · Step Functions · Lambda · SNS ·
`Security Hub → EventBridge → Firehose → S3 → SQS → Wazuh` ingestion ·
`Security Hub/EventBridge → Step Functions → selective response` ·
Wazuh agents · lab test workloads · SprintOps Tracker · CI (fmt/validate/lint) ·
detection/investigation/response scenarios and evidence.

The **three-account model** is now **accepted** (D-014) but **not applied** — nothing exists
in Security or Lab. Cross-account ECR/S3 access policies for the Lab runtime are **not**
implemented (next work). A remote Terraform state backend is an **open decision** — see
below.

## Explicitly deferred (Deferred)

Public Wazuh dashboard (ALB + ACM) · malware-analysis pipeline · vulnerability-management
pipeline · multi-AZ / HA Wazuh. See [DECISIONS.md](DECISIONS.md).

---

## Status of blockers and prerequisites

### Packer prerequisite phase — COMPLETE

| ID | Item | Status |
| --- | --- | --- |
| ~~**B1**~~ | Correct bake-time provisioning | **DONE** — [packer/scripts/install-wazuh-base.sh](../packer/scripts/install-wazuh-base.sh) (committed `bcb9013`) installs host prerequisites only; proven by the successful build + smoke test (D-011). |
| ~~**PB-1**~~ | Secure persistent Packer build network | **DONE** — [terraform/packer-build/](../terraform/packer-build/) (D-012). Fail-closed tag selectors, no-ingress SG, IMDSv2, isolated VPC. Applied and build-validated. |
| ~~**PB-2**~~ | Line-ending handling | **DONE** — `.gitattributes` forces LF for `*.sh` / `*.tftpl` / `*.tf` / `*.hcl`; no CRLF issues in the build. |
| ~~**PB-3**~~ | SSM-agent assumption | **DONE** — Canonical Ubuntu 24.04 ships `amazon-ssm-agent`; the successful build **and** the AMI smoke test confirmed it present, enabled, and active. |
| ~~**PB-4**~~ | Least-privilege Packer execution IAM | **DONE** — `cloud-secops-lab-packer-execution-role` + inline policy ([packer-execution-role.tf](../terraform/packer-build/packer-execution-role.tf), D-013), assumed from `CloudGuardOperator`, separate from the builder role. The first build exposed one missing entry (`ssm:StartSession` on `AWS-StartPortForwardingSession`); added narrowly; a subsequent build ran end-to-end. Allowed actions and the "add only on real `AccessDenied`, never `ec2:*` / `ssm:*` / all documents" rule are recorded in D-013. |
| ~~AMI~~ | Validated base AMI | **DONE — VALIDATED** (see *Validation record*). |

### Three-account migration — REMAINING (D-014)

| Step | Item | Detail |
| --- | --- | --- |
| 1 | Apply `terraform/packer-build/` in **Security** | `AWS_PROFILE=security-admin`. Code is account-agnostic; no change needed. |
| 2 | Build + validate a **new Security-owned** base AMI | `AWS_PROFILE=security`, `PKR_VAR_packer_execution_role_arn=…`, `PKR_VAR_lab_account_id=…`. Supersedes `ami-0b1bf8942dfc0daf1`. |
| 3 | Golden AMI shared to **Lab** | Automatic via `ami_users` / `snapshot_users` (D-015); first cross-account build tests `ec2:ModifyImageAttribute` / `ec2:ModifySnapshotAttribute`. |
| 4 | Confirm Lab can launch the shared AMI | Manual check from `lab-admin`. |
| 5 | Destroy the **legacy** Packer build infra in **Management** | `AWS_PROFILE=cloudguard-admin` (`terraform -chdir=terraform/packer-build destroy`), only after step 4 passes. |
| 6 | Apply `terraform/wazuh-artifacts/` in **Security** | `AWS_PROFILE=security-admin` (D-016). |

### Runtime deployment — REMAINING

| ID | Blocker | Detail |
| --- | --- | --- |
| **B2** | No Wazuh ECR image mirror/publish workflow | Nothing pulls the upstream Wazuh manager/indexer/dashboard images at **4.14.7** (D-009) and pushes them to the Security ECR repos. `docker compose pull` on the runtime instance would fail. |
| **B3** | No complete Wazuh artifact set / S3 publish workflow | No `docker-compose.yml`, `generate-indexer-certs.yml`, or manager/indexer/dashboard config (Wazuh **4.14.7**) in the repo, and nothing publishes such a set to `s3://<security-artifact-bucket>/wazuh/`. |
| **X-ACCT** | No cross-account ECR/S3 access for the Lab runtime | The Security ECR repos and artifact bucket have no repository/bucket policy granting the Lab runtime instance role pull/read. Needed before the Lab runtime can boot. |

### Runtime completion / hardening gaps

These finish Phase 1 once the migration, B2/B3, and the publication-ordering decision are settled.

| Gap | Notes |
| --- | --- |
| Runtime `terraform apply` not run | `terraform/wazuh-project/` (VPC `10.0.0.0/16`, EC2) has never been applied — now targets the **Lab** account. |
| Runtime must consume the **shared** AMI | `var.wazuh_ami_id` = the Security-owned AMI id shared to Lab (step 2/3 above). |
| EC2 user-data registry host | `install-wazuh.sh.tftpl` derives the ECR registry from `aws sts get-caller-identity` — in Lab that is the **Lab** account id, not the Security account that owns the repos. Needs the Security registry id passed in. |
| Legacy `ecr.tf` / `storage.tf` removal from `wazuh-project/` | **Blocked** by `stash@{0}`. Resolve the stash, then delete the superseded files and the ECR/S3 references in `roles.tf` (D-016). |
| Dedicated EC2 security group | [ec2.tf](../terraform/wazuh-project/ec2.tf) sets none. |
| Explicit root volume sizing | No `root_block_device`. ~50 GB is a reference, not a requirement. |
| IMDSv2 enforcement on the runtime instance | No `metadata_options { http_tokens = "required" }`. |
| Useful runtime Terraform outputs | [outputs.tf](../terraform/wazuh-project/outputs.tf) is empty — no instance id / bucket name / SSM command. |
| RUNBOOK runtime steps use placeholder ids | Steps 3–11 still have `ami-XXXX` / `i-XXXX` placeholders. |

### Related quality gaps (track for Phase 1 close-out, not blocking)

No remote state backend (now 3 roots / 2 accounts) · no CI checks (`fmt`/`validate`/`tflint`)
· S3 artifact bucket has no object versioning · single-AZ subnet named `private_1` with no
sibling.

---

## Unresolved lifecycle issues

> Narrowed by D-016 (separate persistent artifact root) but not fully closed. Phase 1 must
> still settle the items below.

### Artifact/image publication ordering (still open)

The persistent destinations (ECR repos + artifact bucket) now live in
`terraform/wazuh-artifacts/` in the **Security** account (D-016), so they are created by a
**separate, earlier apply** than the Lab runtime — the "same-root chicken-and-egg" is gone.
What remains open is the **ordering of the first end-to-end run**:

```
apply wazuh-artifacts (Security)  →  publish images (B2) + config (B3)  →  apply runtime (Lab)  →  first boot
```

The Wazuh EC2 user-data still expects `s3://<bucket>/wazuh/` populated and the ECR repos to
hold images at first boot. Phase 1 must confirm this ordering in [RUNBOOK.md](RUNBOOK.md)
and decide whether B2/B3 are manual steps or automated. Do **not** pick the automation
mechanism here.

### Artifact/image retention vs. destroy lifecycle (narrowed by D-016)

D-016 puts the ECR repos and the bucket in a **persistent** root that is **not** destroyed
with the runtime, so images/config **do** survive between Lab sessions by default. What is
still open: whether to ever prune them, and the exact `terraform destroy` scope check in the
runbook (must target only `terraform/wazuh-project/` in Lab).

---

## Open decisions / open questions

| # | Question | Related |
| --- | --- | --- |
| 1 | Artifact/image **publication ordering** for the first end-to-end run, and whether B2/B3 are manual or automated. | D-009, D-016, RUNBOOK |
| 2 | Remote Terraform state backend + locking — now **3 roots across 2 accounts**; local state is getting risky. | ROADMAP backlog |
| 3 | Whether to ever prune retained ECR images / S3 artifacts between lab sessions. | D-006, D-016 |

**Closed since last revision:** multi-account transition point → **D-014** (was open #3 /
D-007); separate artifact root/state → **D-016** (was open #2); artifact-bucket encryption →
**D-010** Accepted (SSE-S3 + TLS, CMK deferred) (was open #4); Wazuh version pin → **4.14.7**
(D-009) (was open #5).

---

## Exact next logical task

> Still Phase 1. This pass was **repository changes only** — the next actions are the
> operator-run **migration**, then B2/B3 + the runtime deploy. Do NOT start Phase 2+
> (detection/ingestion/response). No further "PB" work is needed.

**First: the operator runs the D-014 migration** (see [RUNBOOK.md](RUNBOOK.md) → Migration):

1. `AWS_PROFILE=security-admin` → `terraform -chdir=terraform/packer-build apply`.
2. `AWS_PROFILE=security` + `PKR_VAR_packer_execution_role_arn=…` + `PKR_VAR_lab_account_id=…`
   → `packer build .` → smoke-test the **new Security-owned** AMI. Record its id.
3. Confirm the AMI shows the Lab account under launch permissions; from `lab-admin` confirm
   Lab can launch it.
4. `AWS_PROFILE=cloudguard-admin` → `terraform -chdir=terraform/packer-build destroy` of the
   **legacy Management** copy.
5. `AWS_PROFILE=security-admin` → `terraform -chdir=terraform/wazuh-artifacts apply`.

**Then the runtime path** (unchanged in intent, now Lab-account + Security artifacts):

6. **B3 — Wazuh 4.14.7 artifact set + S3 publish** to the Security artifact bucket.
7. **B2 — ECR image mirror** (Wazuh 4.14.7) to the Security ECR repos.
8. **Cross-account access** — ECR repository policy + S3 bucket policy letting the Lab
   runtime instance role pull images / read `wazuh/*`.
9. **Runtime EC2 hardening + outputs** (Lab) — dedicated SG, explicit `root_block_device`,
   `metadata_options { http_tokens = "required" }`, populate `outputs.tf`; fix the user-data
   registry-host derivation to use the Security account id.
10. **Deploy + validate the runtime** — `AWS_PROFILE=lab-admin`
    `terraform -chdir=terraform/wazuh-project apply -var wazuh_ami_id=<shared AMI>` → SSM
    shell → SSM port-forward to the dashboard → manager + indexer + dashboard healthy →
    `terraform destroy` of the **runtime only** → verified cleanup.
11. **Resolve `stash@{0}`**, then remove the superseded `wazuh-project/ecr.tf` +
    `storage.tf` + their references in `roles.tf` (D-016).
12. **Update [ROADMAP.md](ROADMAP.md), [RUNBOOK.md](RUNBOOK.md), and this file** with real
    commands / results / ids.

### Prerequisites that already exist

Account structure + SSO permission sets (Management / Security / Lab) · a **validated base
AMI in Management** (evidence only — a new Security one is built in step 2) · all three
Terraform roots in code (`packer-build`, `wazuh-artifacts`, `wazuh-project`) · the Packer
AMI-sharing config. The remaining work is the migration + B2/B3 + cross-account policies +
hardening + the runtime apply — **plus the stash-blocked cleanup**.

### Do NOT work on yet

- Any AWS-native detection service (CloudTrail, GuardDuty, Security Hub, Config, CloudWatch).
- Any ingestion-pipeline component (EventBridge, Firehose, S3 events, SQS).
- Any response-pipeline component (Step Functions, Lambda, SNS).
- Provider-alias / single-apply-across-accounts refactor — each root is applied with its own
  account's credentials; do not add `assume_role` provider blocks.
- ALB / ACM / any public exposure.
- Lab-account test workloads, Wazuh agents, SprintOps Tracker.
- Remote state backend migration and CI setup (worth doing, but separable).
- `terraform apply` / `packer build` / any AWS mutation as part of *this* documentation
  branch — that is the operator's migration run.

---

## Relevant source files

| Path | Role |
| --- | --- |
| [terraform/packer-build/](../terraform/packer-build/) | Terraform root — **persistent Packer build infrastructure** (D-012). Applied **in Management**; migrate to **Security** (D-014). Do not destroy with the runtime |
| [terraform/packer-build/packer-execution-role.tf](../terraform/packer-build/packer-execution-role.tf) | Packer execution role + least-privilege policy (PB-4 / D-013). This pass added `ec2:ModifyImageAttribute` / `ec2:ModifySnapshotAttribute` (region-scoped) for the Lab AMI share (D-015) |
| [terraform/wazuh-artifacts/](../terraform/wazuh-artifacts/) | **NEW** Terraform root — **persistent ECR + S3 artifact layer** (D-016), Security account. Not applied |
| [terraform/wazuh-project/](../terraform/wazuh-project/) | Terraform root — **disposable Wazuh runtime**, **Lab** account (D-014). Not applied |
| [terraform/wazuh-project/providers.tf](../terraform/wazuh-project/providers.tf) | Provider pin + this pass's Lab-placement / legacy-ECR-superseded note |
| [terraform/wazuh-project/ec2.tf](../terraform/wazuh-project/ec2.tf) | Wazuh instance (hardening gaps here); must use the shared Security AMI |
| [terraform/wazuh-project/roles.tf](../terraform/wazuh-project/roles.tf) | EC2 IAM; references the legacy ECR/S3 resources — untangle when the stash is resolved |
| [terraform/wazuh-project/ecr.tf](../terraform/wazuh-project/ecr.tf) | **Superseded** by `wazuh-artifacts/ecr.tf`. `stash@{0}` touches this file — do not delete yet |
| [terraform/wazuh-project/storage.tf](../terraform/wazuh-project/storage.tf) | **Superseded** by `wazuh-artifacts/storage.tf` |
| [terraform/wazuh-project/scripts/install-wazuh.sh.tftpl](../terraform/wazuh-project/scripts/install-wazuh.sh.tftpl) | EC2 user-data (runtime); registry-host derivation needs the Security account id |
| [packer/wazuh-ami.pkr.hcl](../packer/wazuh-ami.pkr.hcl) | AMI build definition — build-network filters, `assume_role`, and **`ami_users` / `snapshot_users`** for the Lab share (D-015) |
| [packer/ami-sharing.pkr.hcl](../packer/ami-sharing.pkr.hcl) | **NEW** — required (no-default) `lab_account_id` variable |
| [packer/build-identity.pkr.hcl](../packer/build-identity.pkr.hcl) | `packer_execution_role_arn` var |
| [packer/scripts/install-wazuh-base.sh](../packer/scripts/install-wazuh-base.sh) | Bake-time host provisioner — **B1 done**, proven by the validated build |

The pre-`333460c` combined bootstrap (`git show cca2387:terraform/wazuh-project/scripts/install-wazuh.sh`)
is kept only as historical reference for the Docker/kernel steps; it also contains runtime
logic and an old Wazuh version and must not be copied wholesale.

---

## Handoff notes

- The repository is the project record. Everything needed to resume work is in version
  control; do not rely on any context from outside it.
- **Account layering (D-014):** **Management** = Organizations / SSO / billing only.
  **Security** = `terraform/packer-build/` + `terraform/wazuh-artifacts/` + the golden AMI +
  future security tooling — all **persistent**. **Lab** = `terraform/wazuh-project/` runtime
  (disposable, D-006) + test workloads + SprintOps Tracker. Terraform is account-agnostic;
  which account an apply lands in is decided by the profile/permission set that runs it.
- **Lifecycle layering (keep this distinction):** persistent build/artifact infra
  (`packer-build/`, `wazuh-artifacts/`) — never in the destroy cycle · the temporary Packer
  builder — ephemeral, per build · the golden AMI — a reusable artifact owned by Security,
  shared to Lab by launch permission only (D-015) · the Lab runtime — disposable.
- **Nothing is applied in Security or Lab.** The only CloudGuard infrastructure in AWS is
  the *legacy* `packer-build` + the AMI `ami-0b1bf8942dfc0daf1` in **Management**. The
  runtime VPC (`10.0.0.0/16`) has never existed anywhere.
- The historical design (`t3.large`, ~50 GB EBS, `git clone wazuh-docker`) is **partly
  superseded** by `333460c` (→ `c5a.xlarge`, no explicit root volume, delivery via private
  ECR + S3 — [DECISIONS.md](DECISIONS.md) D-009). Wazuh is now **pinned to 4.14.7** (D-009);
  B2/B3 target that version.
- Cost: `packer-build/` and `wazuh-artifacts/` carry **no hourly cost** (control-plane +
  empty bucket + empty repos). The Lab runtime carries endpoint + EC2 hourly cost —
  `terraform destroy` the **runtime root only** after validating (D-006). Never destroy the
  Security roots as part of that cycle. ECR images / S3 config **persist** between sessions
  by design (D-016).
- **Three Terraform roots now** (D-008 → D-012 → D-016). Each split is justified by a
  materially different lifecycle (and, for `wazuh-artifacts/`, cross-account ownership). Do
  not add a fourth speculatively.
- **PB-4 / D-013 + D-015:** the execution-role policy is derived from the *current*
  `amazon-ebs` config, which now includes `ami_users` / `snapshot_users` → it grants
  `ec2:ModifyImageAttribute` / `ec2:ModifySnapshotAttribute` scoped to this region's
  `image/*` / `snapshot/*` (cannot publish, cannot copy). If the config changes again,
  re-derive — add only the specific denied action per real `AccessDenied`, never `ec2:*` /
  `ssm:*` / all documents / all resources. No AWS account ID is in source. `lab_account_id`
  is a **required** Packer var (no default), non-secret, supplied via `PKR_VAR_lab_account_id`.
- **Do not touch `stash@{0}`.** It blocks removing the superseded `wazuh-project/ecr.tf`
  (and, for reference integrity, `storage.tf` + the `roles.tf` references). That cleanup is
  explicitly deferred until the stash is resolved.
- When you finish a substantial task, update this file (Snapshot, milestone, blockers/gaps,
  open decisions, next task) and any other doc whose assumptions changed.
