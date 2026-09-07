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
| Last updated | 2026-09-07 |
| Updated by | Phase 1 — Packer prerequisite phase finalization: recorded the successful build + AMI smoke test, marked PB-1…PB-4 COMPLETE, merged the branch |
| Active branch | `feat/phase1-packer-iam` → merged to `main` |
| Default branch | `main` |
| Recent milestones | *(this)* finalize Packer prerequisite validation · `19ce7a8` least-privilege Packer execution role (PB-4/D-013) · `d790992` secure Packer build infrastructure (PB-1/D-012) · `bcb9013` base-AMI provisioning (B1) |
| Current phase | **Phase 1 — Private Wazuh Platform** |
| Phase status | **IN PROGRESS** — the **Packer prerequisite phase (B1, PB-1…PB-4) is COMPLETE** and a **validated base AMI** exists. Persistent Packer build infrastructure is **applied** in AWS. The **runtime Wazuh environment is NOT applied** (B2, B3, `terraform/wazuh-project/` apply, end-to-end SSM validation remain). |
| Validation status | **Base AMI = VALIDATED** (built + independently smoke-tested via Session Manager, 2026-09-07). Build network + execution role = **applied and build-validated**. Runtime Wazuh infrastructure = **not applied / not validated**. |

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

Evidence AMI: `ami-0b1bf8942dfc0daf1` (`us-east-2`). *Historical validation evidence only —
not a config constant; `var.wazuh_ami_id` takes an explicit value chosen at deploy time.*
The smoke-test instance is disposable and not part of the persistent architecture.

`terraform/packer-build/.terraform.lock.hcl` is committed and is intentional
**source-controlled dependency metadata**. `terraform/packer-build/.terraform/` and provider
binaries stay git-ignored.

### Repository / working-tree note

The Packer prerequisite phase is merged to `main`: the `terraform/packer-build/` build
network + execution role, the fixed bake script + `.gitattributes`, and the narrow
`ssm:StartSession` fix (`AWS-StartPortForwardingSession`) that the first build required.

**Known unrelated working-tree changes** — CRLF→LF renormalization only, deliberately left
alone and **not** part of the Packer finalization commit:
`terraform/wazuh-project/{ec2,ecr,roles,storage}.tf` and `packer/variables.pkr.hcl`. The
historical ECR comment-only change is in `git stash@{0}` — do not restore it.

---

## Last completed meaningful milestone

**Packer prerequisite phase — COMPLETE, with a validated base AMI.**

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

## Currently implemented components (Current)

| Component | File(s) |
| --- | --- |
| VPC `10.0.0.0/16`, private subnet `10.0.1.0/24` (`us-east-2a`), private route table + association | [networking.tf](../terraform/wazuh-project/networking.tf) |
| S3 gateway endpoint on the private route table | [endpoints.tf](../terraform/wazuh-project/endpoints.tf) |
| Interface endpoints: `ssm`, `ssmmessages`, `ec2messages`, `ecr.api`, `ecr.dkr` + endpoint SG (443 from subnet) | [endpoints.tf](../terraform/wazuh-project/endpoints.tf) |
| EC2 IAM role, instance profile, `AmazonSSMManagedInstanceCore`, scoped ECR pull, scoped S3 read (`wazuh/*`) | [roles.tf](../terraform/wazuh-project/roles.tf) |
| Provider pinning: `hashicorp/aws ~> 6.57.0`, Terraform `>= 1.7.0`, region from `var.aws_region` | [providers.tf](../terraform/wazuh-project/providers.tf) |
| Input variables (`project_name`, `aws_region`, `availability_zone`, `vpc_cidr`, `subnet_cidr`, `wazuh_ami_id`, `wazuh_instance_type`) | [variables.tf](../terraform/wazuh-project/variables.tf) |

### Persistent Packer build infrastructure — `terraform/packer-build/` (D-012 / D-013) — **APPLIED**

| Component | File(s) |
| --- | --- |
| Build VPC `10.10.0.0/24` (isolated from the runtime `10.0.0.0/16` — no peering / TGW), DNS support + hostnames | [network.tf](../terraform/packer-build/network.tf) |
| One build subnet, `map_public_ip_on_launch = false` | [network.tf](../terraform/packer-build/network.tf) |
| Internet Gateway + `0.0.0.0/0` route + association | [network.tf](../terraform/packer-build/network.tf) |
| Builder security group — **no ingress**; egress TCP 80 + 443 to `0.0.0.0/0` only | [network.tf](../terraform/packer-build/network.tf) |
| Builder IAM role (`cloud-secops-lab-packer-build-ssm-role`) + `AmazonSSMManagedInstanceCore` **only** + instance profile | [iam.tf](../terraform/packer-build/iam.tf) |
| **Packer execution role** (`cloud-secops-lab-packer-execution-role`) + least-privilege inline policy (`CloudGuardOperator` SSO trust; account ID via `data.aws_caller_identity`) | [packer-execution-role.tf](../terraform/packer-build/packer-execution-role.tf) |
| Outputs (vpc/subnet/sg ids, instance-profile name, builder role ARN, **`packer_execution_role_arn`**, selector tags) | [outputs.tf](../terraform/packer-build/outputs.tf) |

Status: **applied in AWS and exercised by a successful `packer build`.** This root is
**persistent supporting infrastructure** — it is deliberately outside the Wazuh runtime
deploy→…→destroy cycle and carries no hourly cost (control-plane objects only). Re-apply only
when the code changes.

---

## Incomplete components (Partial)

| Component | What exists | What's missing |
| --- | --- | --- |
| ECR repositories | 3 repos, `IMMUTABLE`, scan-on-push ([ecr.tf](../terraform/wazuh-project/ecr.tf)) | No working workflow publishes Wazuh images into the repos |
| S3 artifact bucket | Bucket, public access block, SSE-S3 AES256 ([storage.tf](../terraform/wazuh-project/storage.tf)) | Bucket is empty; no checked-in Wazuh artifact set; no publish workflow; no versioning; no TLS-only bucket policy |
| Wazuh **runtime** EC2 instance | Resource with instance profile, private subnet, templated user-data ([ec2.tf](../terraform/wazuh-project/ec2.tf)) | Runtime not applied. No dedicated security group; no explicit `root_block_device`; no `metadata_options` (IMDSv2). `var.wazuh_ami_id` now has a **validated** base AMI to point at |
| EC2 user-data | Template does S3 sync + ECR login + `docker compose pull/up` + cert generation ([install-wazuh.sh.tftpl](../terraform/wazuh-project/scripts/install-wazuh.sh.tftpl)) | Depends on ECR images and S3 artifacts that don't exist (B2/B3); no health/wait/verification logic |
| Terraform outputs (runtime root) | — | [outputs.tf](../terraform/wazuh-project/outputs.tf) is an empty placeholder |

---

## Not implemented (Planned)

CloudTrail · GuardDuty · Security Hub · AWS Config · CloudWatch (log groups/alarms) ·
EventBridge · Firehose · SQS · Step Functions · Lambda · SNS ·
`Security Hub → EventBridge → Firehose → S3 → SQS → Wazuh` ingestion ·
`Security Hub/EventBridge → Step Functions → selective response` ·
multi-account model (management / security / lab) · Wazuh agents · lab test workloads ·
CI (fmt/validate/lint) · detection/investigation/response scenarios and evidence.

(Remote Terraform state backend and artifact-bucket CMK are **open decisions**, not simply
Planned — see below.)

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

### Runtime deployment — REMAINING

| ID | Blocker | Detail |
| --- | --- | --- |
| **B2** | No Wazuh ECR image mirror/publish workflow | The 3 repos exist but nothing pulls the upstream Wazuh manager/indexer/dashboard images at a pinned version and pushes them to the private repos. `docker compose pull` on the runtime instance would fail. |
| **B3** | No complete Wazuh artifact set / S3 publish workflow | No `docker-compose.yml`, `generate-indexer-certs.yml`, or manager/indexer/dashboard config in the repo, and nothing publishes such a set to `s3://<bucket>/wazuh/`. |

### Runtime completion / hardening gaps

These finish Phase 1 once B2/B3 and the bootstrap decision are settled.

| Gap | Notes |
| --- | --- |
| Runtime `terraform apply` not run | `terraform/wazuh-project/` (VPC `10.0.0.0/16`, EC2 from the validated base AMI) has never been applied. |
| Dedicated EC2 security group | [ec2.tf](../terraform/wazuh-project/ec2.tf) sets none. |
| Explicit root volume sizing | No `root_block_device`. ~50 GB is a reference, not a requirement. |
| IMDSv2 enforcement on the runtime instance | No `metadata_options { http_tokens = "required" }`. |
| Useful runtime Terraform outputs | [outputs.tf](../terraform/wazuh-project/outputs.tf) is empty — no instance id / bucket name / SSM command. |
| RUNBOOK runtime steps use placeholder ids | Steps 3–11 still have `ami-XXXX` / `i-XXXX` placeholders. |

### Related quality gaps (track for Phase 1 close-out, not blocking)

No remote state backend · no CI checks (`fmt`/`validate`/`tflint`) · S3 bucket has no
versioning / no TLS-only bucket policy · single-AZ subnet named `private_1` with no sibling.

---

## Unresolved lifecycle issues

> These are **not** solved in this documentation baseline. Phase 1 planning must decide them.

### Artifact bootstrap sequencing

Terraform (the Wazuh runtime root, `terraform/wazuh-project/`) **creates** the ECR
repositories and the S3 artifact bucket. The Wazuh EC2 user-data expects those destinations
to **already be populated** at
first boot (`aws s3 sync s3://<bucket>/wazuh/`, `docker compose pull` from the private
registry). So the destinations cannot be populated until Terraform has created them, but the
instance should not first-boot until the artifacts/images are present.

The current [RUNBOOK.md](RUNBOOK.md) ordering therefore has an unresolved
dependency/ordering problem. Phase 1 must define a clean lifecycle for:

```
infrastructure prerequisite creation  →  artifact / image publication  →  Wazuh host creation
```

Do **not** pick the mechanism here (targeted applies, a split module/state, a separate
bootstrap step, image build baked differently, etc. are all open options).

### Artifact persistence vs. destroy lifecycle

The project wants **both**:

- `terraform destroy` after each validation session (D-006); and
- potentially **retaining** ECR images / S3 artifacts between sessions so redeploy is fast
  and cheap.

Today the ECR repositories and the S3 bucket live in the **same Terraform root/state** as the
ephemeral runtime infrastructure (VPC, EC2), so a plain `terraform destroy` would remove
them too. The desired persistence boundary — what is durable vs. what is disposable, and
whether durable artifact infrastructure needs its own Terraform lifecycle/state — **has not
been decided**.

---

## Open decisions / open questions

| # | Question | Related |
| --- | --- | --- |
| 1 | Artifact persistence between lab sessions — keep ECR images / S3 artifacts, or destroy and rebuild each time? | D-006, D-009 |
| 2 | Does artifact/bootstrap infrastructure (ECR, artifact bucket, publish workflow) eventually need a **separate Terraform lifecycle/state** from ephemeral runtime infra? | Artifact bootstrap sequencing (above) |
| 3 | Exact phase at which the project transitions from single-account to the management/security/lab model. Not asserted that Phases 2–3 must stay single-account. | D-007 (Proposed) |
| 4 | Phase 1 artifact bucket encryption: keep SSE-S3 (AES256) or introduce a customer-managed KMS key? | D-010 (Proposed) |
| 5 | Which Wazuh version to pin when the artifact set + images are (re)built. The historical `v4.14.7` (from the deleted `install-wazuh.sh`) is **evidence of the previous direction only** and must not automatically become the new pin — choose deliberately. | B2, B3, D-009 |

---

## Exact next logical task

> **The Packer prerequisite phase is done. Next is the runtime Wazuh deployment path.**
> Do NOT start Phase 2+ (detection/ingestion/response). No further "PB" work is needed.

Recommended sequence (one coherent unit of Phase 1 work):

1. **Decide the bootstrap lifecycle** (see *Unresolved lifecycle issues* → Artifact bootstrap
   sequencing) and **pick a Wazuh version to pin** (Open decision #5). Everything below
   depends on these; record the decisions in [DECISIONS.md](DECISIONS.md).
2. **B3 — Wazuh artifact set + S3 publish.** Check in a `wazuh/` source directory (Compose
   file, `generate-indexer-certs.yml`, manager/indexer/dashboard config) at the pinned
   version, plus a defined publish path to `s3://<bucket>/wazuh/` consistent with the
   bootstrap lifecycle from step 1.
3. **B2 — ECR image mirror.** A working workflow to pull the Wazuh manager/indexer/dashboard
   images at the pinned version → tag → push to the 3 private repos.
4. **Runtime EC2 hardening + outputs.** Dedicated security group, explicit `root_block_device`
   (revisit the ~50 GB reference), `metadata_options { http_tokens = "required" }`, and
   populate the runtime `outputs.tf` (instance id, bucket name, ready-to-paste SSM
   port-forward command).
5. **Deploy + validate the runtime.** `terraform apply` `terraform/wazuh-project/` with
   `wazuh_ami_id` = the validated base AMI → SSM shell into the instance → SSM port-forward
   to the dashboard → confirm manager + indexer + dashboard healthy → `terraform destroy`
   of the **runtime only** → verified cleanup (leave `terraform/packer-build/` up — D-012).
6. **Update [ROADMAP.md](ROADMAP.md), [RUNBOOK.md](RUNBOOK.md), and this file** with the real
   commands, results, and the step-1 decisions.

### Prerequisites that already exist

Validated base AMI · applied + validated Packer build infrastructure (build network +
execution role) · runtime VPC/subnet/route-table/endpoints/IAM/ECR-defs/S3-def/EC2-def all
in code. The remaining work is B2/B3 + the bootstrap decision + hardening + the runtime
apply — **filling gaps, not new architecture**.

### Do NOT work on yet

- Any AWS-native detection service (CloudTrail, GuardDuty, Security Hub, Config, CloudWatch).
- Any ingestion-pipeline component (EventBridge, Firehose, S3 events, SQS).
- Any response-pipeline component (Step Functions, Lambda, SNS).
- Multi-account / provider-alias refactor.
- ALB / ACM / any public exposure.
- Lab-account workloads or Wazuh agents.
- Remote state backend migration and CI setup (worth doing, but separable; not blocking a
  first validation).

---

## Relevant source files

| Path | Role |
| --- | --- |
| [terraform/wazuh-project/](../terraform/wazuh-project/) | Terraform root — **disposable Wazuh runtime** |
| [terraform/packer-build/](../terraform/packer-build/) | Terraform root — **persistent Packer build infrastructure** (D-012), **applied**; do not destroy with the runtime |
| [terraform/packer-build/packer-execution-role.tf](../terraform/packer-build/packer-execution-role.tf) | **Packer execution role** + least-privilege policy (PB-4 / D-013), applied + build-validated |
| [packer/build-identity.pkr.hcl](../packer/build-identity.pkr.hcl) | `packer_execution_role_arn` var; `assume_role` is in `wazuh-ami.pkr.hcl` |
| [terraform/wazuh-project/ec2.tf](../terraform/wazuh-project/ec2.tf) | Wazuh instance (hardening gaps here) |
| [terraform/wazuh-project/endpoints.tf](../terraform/wazuh-project/endpoints.tf) | VPC endpoints + endpoint SG |
| [terraform/wazuh-project/roles.tf](../terraform/wazuh-project/roles.tf) | EC2 IAM |
| [terraform/wazuh-project/ecr.tf](../terraform/wazuh-project/ecr.tf) | ECR repository definitions |
| [terraform/wazuh-project/storage.tf](../terraform/wazuh-project/storage.tf) | Artifact bucket |
| [terraform/wazuh-project/outputs.tf](../terraform/wazuh-project/outputs.tf) | Empty — needs outputs |
| [terraform/wazuh-project/scripts/install-wazuh.sh.tftpl](../terraform/wazuh-project/scripts/install-wazuh.sh.tftpl) | EC2 user-data (runtime) |
| [packer/wazuh-ami.pkr.hcl](../packer/wazuh-ami.pkr.hcl) | AMI build definition (build-network filters + `assume_role` for the execution role) |
| [packer/scripts/install-wazuh-base.sh](../packer/scripts/install-wazuh-base.sh) | Bake-time host provisioner — **B1 done**, proven by the validated build |

The pre-`333460c` combined bootstrap (`git show cca2387:terraform/wazuh-project/scripts/install-wazuh.sh`)
is kept only as historical reference for the Docker/kernel steps; it also contains runtime
logic and an old Wazuh version and must not be copied wholesale.

---

## Handoff notes

- The repository is the project record. Everything needed to resume work is in version
  control; do not rely on any context from outside it.
- **Layering (keep this distinction):** build infrastructure (`terraform/packer-build/`) =
  **persistent** and applied; the temporary Packer builder = **ephemeral** (Packer creates
  and destroys it per build); the base AMI = a **reusable artifact** (persists after a
  build); the runtime Wazuh environment (`terraform/wazuh-project/`) = **still pending** and
  disposable-by-design when it does exist.
- **The runtime Wazuh VPC (`10.0.0.0/16`) does not exist in AWS.** Only the build VPC
  (`10.10.0.0/24`) is applied. The two are isolated — no peering, no transit gateway.
- The historical design (`t3.large`, ~50 GB EBS, Wazuh `v4.14.7`, `git clone wazuh-docker`)
  is **partly superseded** by `333460c` (→ `c5a.xlarge`, no explicit root volume, delivery
  via private ECR + S3 — [DECISIONS.md](DECISIONS.md) D-009). The delivery model is not yet
  wired up (B2/B3) and the old version number does not carry over automatically (Open
  decision #5).
- Cost: `terraform/packer-build/` carries **no hourly cost** (control-plane objects only).
  The runtime, once deployed, carries endpoint + EC2 hourly cost — `terraform destroy` the
  runtime after validating (D-006), subject to the persistence boundary Open decisions
  #1–#2 will define. Never `terraform destroy` the build root as part of that cycle.
- **Two Terraform roots** — the first justified split (D-008 → D-012). This does **not**
  license moving the ECR/S3 resources or resolving the artifact-persistence /
  bootstrap-ordering open decisions.
- **PB-4 / D-013:** the execution role's least-privilege policy is derived from the *current*
  `amazon-ebs` config. If that config changes (new source options, new communicator/interface),
  re-derive — add only the specific denied action per real `AccessDenied`, never `ec2:*` /
  `ssm:*` / all documents. No AWS account ID is in source (Terraform discovers it); Packer
  gets the role ARN from `terraform output`.
- When you finish a substantial task, update this file (Snapshot, milestone, blockers/gaps,
  open decisions, next task) and any other doc whose assumptions changed.
