# CloudGuard — Current State (Development Handoff)

> **This is the primary handoff document.** A new agent/session should read this immediately
> after [PROJECT_CHARTER.md](PROJECT_CHARTER.md), then verify it against actual code and
> `git status` before doing anything.
>
> Update rule: any agent that performs a **substantial** development task must update this
> file before finishing. See [../AGENTS.md](../AGENTS.md).

---

## Snapshot

| Field | Value |
| --- | --- |
| Last updated | 2026-09-05 |
| Updated by | Documentation/continuity baseline task + correction pass (no implementation changes) |
| Active branch | `docs/project-continuity-baseline` |
| Default branch | `main` |
| Most recent substantive commit | `333460c` — *Add Wazuh AWS infrastructure foundation* (2026-08-09) |
| Prior commits | `96670c7` *Terraform work* · `cca2387` *Initial Commit* |
| Current phase | **Phase 1 — Private Wazuh Foundation** |
| Phase status | **IN PROGRESS** — scaffolding present, not end-to-end deployable |
| Validation status | No successful end-to-end deployment or validation is documented in the repository. Treat the current implementation as **unvalidated** until Phase 1 validation is performed. |

### Working-tree changes at last update

```
 M terraform/wazuh-project/ecr.tf
```

- Pre-existing, **not** created by the documentation task.
- Content: comment/banner formatting only (three `####` header blocks added above the
  existing `aws_ecr_repository` resources). No Terraform behavior change. Confirmed via
  `git diff`.
- **Preserve this change.** Do not discard or overwrite it.
- The documentation task adds only: `README.md` (rewrite), `AGENTS.md`, `CLAUDE.md`,
  `docs/*.md`.

---

## Last completed meaningful milestone

**Commit `333460c` — private Wazuh AWS foundation scaffolded in Terraform + Packer.**

That commit:

- Rewrote earlier rough networking/endpoints code into a consistent, tagged module.
- Added `ec2.tf`, `ecr.tf`, `roles.tf`, `storage.tf`.
- Added the `packer/` directory (AMI source + variables + provisioner script).
- Split the old monolithic `install-wazuh.sh` into a Packer provisioner script and a
  Terraform user-data template — **the split is incomplete / incorrect** (see Blocker B1).
- Changed the Wazuh instance type from `t3.large` to `c5a.xlarge` and dropped the explicit
  ~50 GB root-volume configuration.

Since then: only the uncommitted comment-only edit to `ecr.tf`.

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

---

## Incomplete components (Partial)

| Component | What exists | What's missing |
| --- | --- | --- |
| ECR repositories | 3 repos, `IMMUTABLE`, scan-on-push ([ecr.tf](../terraform/wazuh-project/ecr.tf)) | No working workflow publishes Wazuh images into the repos |
| S3 artifact bucket | Bucket, public access block, SSE-S3 AES256 ([storage.tf](../terraform/wazuh-project/storage.tf)) | Bucket is empty; no checked-in Wazuh artifact set; no publish workflow; no versioning; no TLS-only bucket policy |
| Wazuh EC2 instance | Resource with instance profile, private subnet, templated user-data ([ec2.tf](../terraform/wazuh-project/ec2.tf)) | No dedicated security group; no explicit `root_block_device`; no `metadata_options` (IMDSv2). Takes an explicit `var.wazuh_ami_id` (acceptable), but no validated AMI exists to supply |
| Packer AMI build | `amazon-ebs` source, Ubuntu 24.04 filter, timestamped AMI name ([wazuh-ami.pkr.hcl](../packer/wazuh-ami.pkr.hcl)) | Provisioner runs the wrong script (blocker B1); build never validated |
| EC2 user-data | Template does S3 sync + ECR login + `docker compose pull/up` + cert generation ([install-wazuh.sh.tftpl](../terraform/wazuh-project/scripts/install-wazuh.sh.tftpl)) | Depends on ECR images and S3 artifacts that don't exist; no health/wait/verification logic (the deleted `install-wazuh.sh` had a dashboard-wait loop) |
| Terraform outputs | — | [outputs.tf](../terraform/wazuh-project/outputs.tf) and [main.tf](../terraform/wazuh-project/main.tf) are empty placeholders |

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

## Known defects / gaps

### Hard deployment blockers

These prevent a first successful deployment. All must be resolved before Phase 1 validation.

| ID | Blocker | Detail |
| --- | --- | --- |
| **B1** | Packer bake provisioning is incorrect | [packer/scripts/install-wazuh-base.sh](../packer/scripts/install-wazuh-base.sh) is byte-identical to [install-wazuh.sh.tftpl](../terraform/wazuh-project/scripts/install-wazuh.sh.tftpl) and contains runtime startup logic (`aws sts`, `aws s3 sync`, `docker login`, `docker compose up`) plus Terraform-template `${...}`/`$${...}` syntax that Packer will not process. It does **not** install Docker Engine, the Compose plugin, or set `vm.max_map_count`. Correct bake logic exists in the deleted `terraform/wazuh-project/scripts/install-wazuh.sh` (recover: `git show cca2387:terraform/wazuh-project/scripts/install-wazuh.sh`). |
| **B2** | No Wazuh ECR image mirror/publish workflow | The three repos exist but there is no working process to pull the upstream Wazuh manager/indexer/dashboard images at a pinned version and push them into the private repos. Without it, `docker compose pull` on the instance fails. |
| **B3** | No complete Wazuh artifact set / S3 publish workflow | The repo contains no `docker-compose.yml`, `generate-indexer-certs.yml`, or manager/indexer/dashboard config, and nothing publishes such a set to `s3://<bucket>/wazuh/`. The `aws s3 sync` in user-data retrieves nothing and the stack has no definition to run. |

### Phase 1 completion / hardening gaps

Needed to *finish and validate* Phase 1. These are not what stops a first boot; they are what
Phase 1 must still deliver to be considered done.

| Gap | Notes |
| --- | --- |
| No validated AMI from the repaired Packer workflow | `var.wazuh_ami_id` taking an explicit value is fine; the missing capability is a *trusted* AMI (built by a fixed B1 workflow, smoke-tested per [RUNBOOK.md](RUNBOOK.md) step 2) to put in it. |
| Dedicated EC2 security group | [ec2.tf](../terraform/wazuh-project/ec2.tf) sets none — instance would use the VPC default SG. |
| Explicit root volume sizing | No `root_block_device`; defaults to the AMI's size. Revisit the historical ~50 GB figure — it is a reference, not a requirement. |
| IMDSv2 enforcement | No `metadata_options { http_tokens = "required" }`. |
| Useful Terraform outputs | [outputs.tf](../terraform/wazuh-project/outputs.tf) is empty — no instance id / bucket name / ready-to-paste SSM command. |
| Operator conveniences / SSM access runbook wired to real values | [RUNBOOK.md](RUNBOOK.md) currently has placeholder ids and unvalidated commands. |

### Related quality gaps (track for Phase 1 close-out, not blocking)

No remote state backend · no CI checks (`fmt`/`validate`/`tflint`) · S3 bucket has no
versioning / no TLS-only bucket policy · single-AZ subnet named `private_1` with no sibling.

---

## Unresolved lifecycle issues

> These are **not** solved in this documentation baseline. Phase 1 planning must decide them.

### Artifact bootstrap sequencing

Terraform (in the single root module) **creates** the ECR repositories and the S3 artifact
bucket. The Wazuh EC2 user-data expects those destinations to **already be populated** at
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

> **Make the private single-node Wazuh deployment successfully deployable and validate it
> through SSM — before starting any AWS detection/ingestion phase.**

Recommended sub-sequence (one coherent unit of Phase 1 work):

0. **Decide the bootstrap lifecycle** (see *Unresolved lifecycle issues* → Artifact bootstrap
   sequencing) and **pick a Wazuh version to pin** (Open decision #5). Everything below
   depends on these.
1. **Fix the Packer bake script (B1).** Restore proper bake-time setup: Docker Engine +
   Compose plugin, `vm.max_map_count=262144`, add the EC2 user to the `docker` group. Keep
   the runtime `.tftpl` for user-data. Reference (direction only, not a copy target): the
   deleted `install-wazuh.sh`. Then build and smoke-test an AMI.
2. **Provide the Wazuh artifact set (B3).** Add a checked-in `wazuh/` source directory
   (Compose file, `generate-indexer-certs.yml`, manager/indexer/dashboard config) at the
   pinned version, plus a defined publish path to `s3://<bucket>/wazuh/` consistent with the
   bootstrap lifecycle chosen in step 0.
3. **Publish images to ECR (B2).** Add a working mirror workflow for the Wazuh
   manager/indexer/dashboard images at the pinned version.
4. **Phase 1 hardening + outputs.** Dedicated security group, explicit `root_block_device`
   (revisit the ~50 GB reference), `metadata_options { http_tokens = "required" }`, and
   populate `outputs.tf` (instance id, bucket name, ready-to-paste SSM port-forward command).
5. **Validate the lifecycle.** Packer build → set `wazuh_ami_id` →
   `terraform init/plan/apply` → SSM into the instance → SSM port-forward to the dashboard →
   confirm manager + indexer + dashboard healthy → `terraform destroy` → confirm cleanup
   (respecting whatever persistence boundary step 0 defined for ECR/S3).
6. **Update this document, [ROADMAP.md](ROADMAP.md), and [RUNBOOK.md](RUNBOOK.md)** with real,
   validated commands and results, and record the step-0 decisions in
   [DECISIONS.md](DECISIONS.md).

### Prerequisites that already exist

VPC + subnet + route table; all five interface endpoints + S3 gateway endpoint; IAM role with
SSM + scoped ECR pull + scoped S3 read; ECR repos; artifact bucket; the EC2 resource and the
user-data template; the Packer `source` block. The remaining work is filling gaps, not new
architecture.

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
| [terraform/wazuh-project/](../terraform/wazuh-project/) | The only Terraform root module |
| [terraform/wazuh-project/ec2.tf](../terraform/wazuh-project/ec2.tf) | Wazuh instance (hardening gaps here) |
| [terraform/wazuh-project/endpoints.tf](../terraform/wazuh-project/endpoints.tf) | VPC endpoints + endpoint SG |
| [terraform/wazuh-project/roles.tf](../terraform/wazuh-project/roles.tf) | EC2 IAM |
| [terraform/wazuh-project/ecr.tf](../terraform/wazuh-project/ecr.tf) | ECR repos (has the pending comment-only diff) |
| [terraform/wazuh-project/storage.tf](../terraform/wazuh-project/storage.tf) | Artifact bucket |
| [terraform/wazuh-project/outputs.tf](../terraform/wazuh-project/outputs.tf) | Empty — needs outputs |
| [terraform/wazuh-project/scripts/install-wazuh.sh.tftpl](../terraform/wazuh-project/scripts/install-wazuh.sh.tftpl) | EC2 user-data (runtime) |
| [packer/wazuh-ami.pkr.hcl](../packer/wazuh-ami.pkr.hcl) | AMI build |
| [packer/scripts/install-wazuh-base.sh](../packer/scripts/install-wazuh-base.sh) | Provisioner — **wrong content (B1)** |

Reference for the intended bake steps (Docker install, `vm.max_map_count`, docker group) —
direction only, not a copy target; re-evaluate the Wazuh version:

```bash
git show cca2387:terraform/wazuh-project/scripts/install-wazuh.sh
```

---

## Handoff notes

- The repository is the project memory. There is **no** prior chat history to rely on.
- No successful end-to-end deployment or validation is documented in the repository. Treat
  all infrastructure as unvalidated until Phase 1 validation is performed.
- The historical design (`t3.large`, ~50 GB EBS, Wazuh `v4.14.7`, `git clone wazuh-docker`)
  is **partly superseded** by commit `333460c`, which moved to `c5a.xlarge`, dropped the
  explicit root volume, and switched the intended delivery model to "images from private ECR
  + config from S3" (ratified as [DECISIONS.md](DECISIONS.md) D-009). The new model is not
  yet wired up, and the old version number does not carry over automatically (Open
  decision #5).
- Keep cost in mind: the interface VPC endpoints and the EC2 instance carry recurring
  hourly cost while deployed. The environment is temporary by design — always
  `terraform destroy` after validating (D-006), subject to the persistence boundary that
  Open decisions #1–#2 will define.
- When you finish a substantial task, update this file (Snapshot, milestone, blockers/gaps,
  open decisions, next task) and any other doc whose assumptions changed.
