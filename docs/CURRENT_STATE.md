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
| Last updated | 2026-09-16 |
| Updated by | **Circular-dependency fix + runtime hardening (D-018/D-019), code only.** Split the Wazuh EC2 IAM role/profile out of `terraform/wazuh-project/` into a new persistent root, `terraform/wazuh-runtime-identity/` (Lab), applied before `terraform/wazuh-artifacts/`. That root's cross-account grant is now a required variable + a single, unconditional apply — no more two-pass re-apply. `terraform/wazuh-project/` gained a dedicated SG, encrypted gp3 root volume, IMDSv2 enforcement, and real outputs (D-019). **No AWS calls made in this pass.** |
| Active branch | `feat/multi-account-cloudguard` (not merged) |
| Default branch | `main` |
| Recent milestones | *(this)* one-directional cross-account dependency + EC2 hardening (D-018/D-019) · Lab/Security cross-account refactor (D-017) · `634d362` three-account restructure (D-014/D-015/D-016) · `8e5e72d` finalize Packer prerequisite validation · `19ce7a8` least-privilege Packer execution role (PB-4/D-013) |
| Current phase | **Phase 1 — Private Wazuh Platform** |
| Phase status | **IN PROGRESS.** Packer prerequisite phase (B1, PB-1…PB-4) is **COMPLETE**. Per the operator, the **build-path migration to Security is done**: build infra applied in Security, a new Security-owned golden AMI built + validated + shared to Lab + smoke-tested. **Still pending:** retire the legacy Management build infra, apply `terraform/wazuh-runtime-identity/` → `terraform/wazuh-artifacts/` → `terraform/wazuh-project/` (in that order, D-018), B2/B3. |
| Validation status | **Build path (Security-owned AMI, shared to Lab, Lab smoke test): reported DONE by the operator** — not independently verified in this session (no AWS calls made; no AMI id / account id recorded here). **`terraform/wazuh-runtime-identity/`, `terraform/wazuh-artifacts/`, `terraform/wazuh-project/`: implemented in code, including the one-directional cross-account access structure and EC2 hardening, NOT applied.** The historical Management-account AMI `ami-0b1bf8942dfc0daf1` (built + smoke-tested 2026-09-07) is superseded evidence only. |

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
validation evidence only — not a config constant, superseded by the new Security-owned AMI
reported below.* `var.wazuh_ami_id` takes an explicit value chosen at deploy time. The
smoke-test instance is disposable and not part of the persistent architecture.

`terraform/packer-build/.terraform.lock.hcl` is committed and is intentional
**source-controlled dependency metadata**. `terraform/packer-build/.terraform/` and provider
binaries stay git-ignored.

### Migration status (operator-reported, 2026-09-16)

> **Attribution:** the items below are stated by the operator as having happened outside
> this session. This session made **no AWS calls** (no `terraform apply`, no `packer build`,
> no `aws` mutation) and recorded **no independent evidence** — no new AMI id, no account
> id. Treat this section as operator report, not as evidence captured by this repository
> pass. Update it with real ids/outputs the next time someone verifies it directly.

| Migration step (D-014) | Status |
| --- | --- |
| 1. `terraform apply` of `terraform/packer-build/` in **Security** | **Done** (operator-reported) |
| 2. Build + validate a new **Security-owned** base AMI | **Done** (operator-reported) |
| 3. Share the AMI to **Lab** by launch permission (D-015) | **Done** (operator-reported) |
| 4. Confirm Lab can launch the AMI + SSM smoke test | **Done** (operator-reported) |
| 5. Destroy the legacy Packer build infrastructure in **Management** | **Not done** |
| 6. `terraform apply` of `terraform/wazuh-runtime-identity/` in **Lab** | **Not done** (new step — D-018) |
| 7. `terraform apply` of `terraform/wazuh-artifacts/` in **Security** | **Not done** |
| 8. B3 (artifact set + S3 publish) / B2 (ECR image mirror) | **Not done** |
| 9. `terraform apply` of `terraform/wazuh-project/` in **Lab** | **Not done** |

> Step numbering above matches [RUNBOOK.md](RUNBOOK.md) → Migration (section M), which was
> renumbered when D-018 inserted the identity-root step. There is no longer a "re-apply
> wazuh-artifacts" step — see *Dependency order* below.

### Repository / working-tree note

The Packer prerequisite phase and the three-account restructure (D-014/D-015/D-016) are on
the current branch (`634d362`). **This pass** (circular-dependency fix + hardening, D-018/D-019):

- **New persistent root** [terraform/wazuh-runtime-identity/](../terraform/wazuh-runtime-identity/)
  (Lab account) — owns `aws_iam_role.wazuh_ec2` + `aws_iam_instance_profile.wazuh_ec2` (moved
  out of `terraform/wazuh-project/`, D-018). Its own ECR-pull/S3-read policy is built
  deterministically from a required `security_account_id` variable + the naming convention
  shared with `terraform/wazuh-artifacts/` — not from a live cross-root output, so this root
  has zero Terraform dependency on `wazuh-artifacts`.
- `terraform/wazuh-artifacts/`'s `lab_runtime_role_arn` variable is now **required** (no
  default); its `aws_ecr_repository_policy` and the S3 bucket policy's Lab-read statements
  are now **unconditional** — a single apply grants cross-account access, no re-apply.
- `terraform/wazuh-project/` no longer creates any IAM role (`roles.tf` **removed**); it
  consumes the identity root's instance profile via a new required
  `wazuh_runtime_instance_profile_name` variable, and no longer needs
  `wazuh_ecr_repository_arns` (removed — that scoping lives in the identity root now).
- `terraform/wazuh-project/` hardening (D-019): new [security.tf](../terraform/wazuh-project/security.tf)
  (dedicated SG, zero ingress, egress scoped to the VPC endpoints); `ec2.tf` gained
  `associate_public_ip_address = false`, `metadata_options` (IMDSv2 required), and an
  encrypted `gp3` `root_block_device`; `outputs.tf` now has `instance_id`,
  `ssm_start_session_command`, `security_group_id`.
- **No `terraform apply` / `packer build` / AWS mutation in this pass.**

**Known unrelated working-tree changes** — CRLF→LF renormalization only, deliberately left
alone and **not** absorbed into this pass's changes: `packer/variables.pkr.hcl`.

**`git stash@{0}` ("preserve ecr comment changes")** — a comment-only change that used to
apply cleanly to `terraform/wazuh-project/ecr.tf`. That file **no longer exists** (removed
this pass, D-017). The stash itself was **not** popped, applied, dropped, or modified — per
instruction. Popping it later **will conflict** (it modifies a file that is now deleted);
that conflict is expected. The operator can resolve it by dropping the stash (its content —
comment formatting on resources that no longer exist in this root — has no remaining value)
or manually reconciling if any of its content is still wanted elsewhere.

---

## Last completed meaningful milestone

**Circular-dependency fix + runtime hardening — D-018 / D-019 (this pass, code only).**
The cross-account design D-017 introduced required a two-pass apply
(`wazuh-artifacts` → `wazuh-project` → re-apply `wazuh-artifacts`) because of a genuine
circular Terraform dependency between the two roots. This pass eliminates it: a new
persistent root, `terraform/wazuh-runtime-identity/` (Lab account), now owns the Wazuh EC2's
IAM role + instance profile — split out of `terraform/wazuh-project/`, which no longer
creates any IAM role. That identity root has **zero** dependency on `terraform/wazuh-artifacts/`
(its own ECR-pull/S3-read policy is built from an explicit `security_account_id` variable +
a shared naming convention, not a live output). `terraform/wazuh-artifacts/` now requires the
identity root's role ARN and grants cross-account access **unconditionally in one apply** — no
re-apply. `terraform/wazuh-project/` also gained EC2 hardening: a dedicated security group
(zero ingress, egress scoped to the VPC endpoints only), `associate_public_ip_address = false`,
IMDSv2 enforcement, an encrypted `gp3` root volume, and real outputs (instance id, SSM
command, security-group id). **No Terraform/Packer run; no AWS resources touched.**

### Prior milestone: Lab/Security cross-account refactor (D-017)

`terraform/wazuh-project/` stopped owning the Wazuh ECR repositories / S3 bucket, consuming
the Security-owned ones via explicit variables instead. Superseded in part by the milestone
above — see D-017's status line in [DECISIONS.md](DECISIONS.md).

### Prior milestone: three-account restructure (D-014 / D-015 / D-016)

Adopted the Management / Security / Lab model with named permission sets (D-014); added
Security→Lab golden-AMI sharing by launch permission (D-015); created the persistent
`terraform/wazuh-artifacts/` root (D-016); pinned Wazuh **4.14.7** (D-009); resolved the
artifact-encryption question (D-010). Repository changes only at the time.

**Since that milestone, per the operator:** the build-path migration (steps 1–4) has run in
AWS — see *Migration status* above.

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
> Per the operator, `terraform/packer-build/` + the golden AMI are now applied in
> **Security** (this session did not verify that independently). Nothing else is applied
> anywhere.

### Lab runtime identity — `terraform/wazuh-runtime-identity/` (D-018) — **NOT APPLIED**

| Component | File(s) |
| --- | --- |
| `aws_iam_role.wazuh_ec2` (EC2 trust) + `aws_iam_instance_profile.wazuh_ec2` | [iam.tf](../terraform/wazuh-runtime-identity/iam.tf) |
| `AmazonSSMManagedInstanceCore` attachment | [iam.tf](../terraform/wazuh-runtime-identity/iam.tf) |
| Cross-account ECR-pull / S3-read inline policies, ARNs built deterministically from `var.security_account_id` + the naming convention shared with `terraform/wazuh-artifacts/` (not a live output — see D-018) | [iam.tf](../terraform/wazuh-runtime-identity/iam.tf) |
| Required `security_account_id` variable (12-digit-validated, non-secret) | [variables.tf](../terraform/wazuh-runtime-identity/variables.tf) |
| Outputs: `wazuh_runtime_role_arn`, `wazuh_runtime_role_name`, `wazuh_runtime_instance_profile_name` | [outputs.tf](../terraform/wazuh-runtime-identity/outputs.tf) |

Status: **implemented in code, never applied.** New in this pass (D-018). Belongs in the
**Lab** account (`lab-admin`). **Persistent** — not part of the disposable-runtime destroy
cycle; the identity (and Security's grant to it) survives redeploying
`terraform/wazuh-project/`. Applied **first**, before `terraform/wazuh-artifacts/` — see
*Dependency order* below.

### Wazuh runtime — `terraform/wazuh-project/` (Lab account) — **NOT APPLIED**

| Component | File(s) |
| --- | --- |
| VPC `10.0.0.0/16`, private subnet `10.0.1.0/24` (`us-east-2a`), private route table + association | [networking.tf](../terraform/wazuh-project/networking.tf) |
| S3 gateway endpoint on the private route table | [endpoints.tf](../terraform/wazuh-project/endpoints.tf) |
| Interface endpoints: `ssm`, `ssmmessages`, `ec2messages`, `ecr.api`, `ecr.dkr` + endpoint SG (443 from subnet) | [endpoints.tf](../terraform/wazuh-project/endpoints.tf) |
| **New (D-019):** dedicated Wazuh EC2 security group — zero ingress; egress 443 to the VPC interface endpoints (SG-to-SG) + the S3 gateway endpoint (prefix list) | [security.tf](../terraform/wazuh-project/security.tf) |
| Provider pinning: `hashicorp/aws ~> 6.57.0`, Terraform `>= 1.7.0`, region from `var.aws_region`; calls no `data.aws_caller_identity` and creates no IAM role (D-017/D-018) | [providers.tf](../terraform/wazuh-project/providers.tf) |
| Input variables (`project_name`, `aws_region`, `availability_zone`, `vpc_cidr`, `subnet_cidr`, `wazuh_ami_id`, `wazuh_instance_type`, `wazuh_ecr_registry`, `wazuh_artifact_bucket_name` — D-017, + **new** `wazuh_runtime_instance_profile_name` — D-018) | [variables.tf](../terraform/wazuh-project/variables.tf) |
| EC2 instance: no public IP, IMDSv2 required, encrypted `gp3` root volume (50 GB reference), dedicated SG, existing instance profile by name (D-019) | [ec2.tf](../terraform/wazuh-project/ec2.tf) |
| Outputs: `instance_id`, `ssm_start_session_command`, `security_group_id` (D-019) | [outputs.tf](../terraform/wazuh-project/outputs.tf) |

**No longer present:** `ecr.tf` / `storage.tf` (removed, D-017 — moved to
`terraform/wazuh-artifacts/`); `roles.tf` (removed, D-018 — moved to
`terraform/wazuh-runtime-identity/`). This root does not own or create the Wazuh ECR
repositories, the S3 artifact bucket, or the EC2 IAM role/profile — it only consumes them.

### Persistent Packer build infrastructure — `terraform/packer-build/` (D-012 / D-013) — **APPLIED IN SECURITY, operator-reported**

| Component | File(s) |
| --- | --- |
| Build VPC `10.10.0.0/24` (isolated from the runtime `10.0.0.0/16` — no peering / TGW), DNS support + hostnames | [network.tf](../terraform/packer-build/network.tf) |
| One build subnet, `map_public_ip_on_launch = false` | [network.tf](../terraform/packer-build/network.tf) |
| Internet Gateway + `0.0.0.0/0` route + association | [network.tf](../terraform/packer-build/network.tf) |
| Builder security group — **no ingress**; egress TCP 80 + 443 to `0.0.0.0/0` only | [network.tf](../terraform/packer-build/network.tf) |
| Builder IAM role (`cloud-secops-lab-packer-build-ssm-role`) + `AmazonSSMManagedInstanceCore` **only** + instance profile | [iam.tf](../terraform/packer-build/iam.tf) |
| **Packer execution role** (`cloud-secops-lab-packer-execution-role`) + least-privilege inline policy (`CloudGuardOperator` SSO trust; account ID via `data.aws_caller_identity`) | [packer-execution-role.tf](../terraform/packer-build/packer-execution-role.tf) |
| Outputs (vpc/subnet/sg ids, instance-profile name, builder role ARN, **`packer_execution_role_arn`**, selector tags) | [outputs.tf](../terraform/packer-build/outputs.tf) |

Status: applied in **Management** originally; per the operator, **now applied in Security**
and exercised by a successful `packer build` there (this session did not independently
verify). This root is **persistent supporting infrastructure** — deliberately outside the
Wazuh runtime deploy→…→destroy cycle, no hourly cost (control-plane objects only). **D-014
migration step 5 (destroy the Management copy) is still outstanding.** The code needs no
further change for this part; only comments were updated in the prior pass.

### Persistent Wazuh artifact layer — `terraform/wazuh-artifacts/` (D-016 / D-017 / D-018) — **NOT APPLIED**

| Component | File(s) |
| --- | --- |
| 3 private ECR repos (`wazuh-manager` / `-indexer` / `-dashboard`, `IMMUTABLE`, scan-on-push, `for_each`) | [ecr.tf](../terraform/wazuh-artifacts/ecr.tf) |
| S3 artifact bucket (`${project}-artifacts-${account_id}`), block-public-access, SSE-S3 AES256, bucket policy **denying non-TLS** (D-010) | [storage.tf](../terraform/wazuh-artifacts/storage.tf) |
| `aws_ecr_repository_policy` (one per repo) + two S3 bucket-policy statements granting `var.lab_runtime_role_arn` pull/read access, scoped to `wazuh/*` — **unconditional, single apply** (D-018, revised from D-017's conditional design) | [ecr.tf](../terraform/wazuh-artifacts/ecr.tf), [storage.tf](../terraform/wazuh-artifacts/storage.tf) |
| `lab_runtime_role_arn` variable — **required, no default** (D-018; was optional/default-`null` under D-017) | [variables.tf](../terraform/wazuh-artifacts/variables.tf) |
| Outputs (ECR repo URL/ARN maps, bucket name/ARN, `ecr_registry`) | [outputs.tf](../terraform/wazuh-artifacts/outputs.tf) |
| Provider pin `hashicorp/aws ~> 6.57.0`, Terraform `>= 1.7.0`, region `us-east-2` | [providers.tf](../terraform/wazuh-artifacts/providers.tf) |

Status: **implemented in code, never applied.** Belongs in the **Security** account
(`security-admin`). Persistent — not part of the runtime destroy cycle. Scope is the
persistent infrastructure plus its own narrow cross-account grants only: **no** image-mirror
workflow (B2), **no** Wazuh artifact set (B3). Applied **after**
`terraform/wazuh-runtime-identity/` and **before** `terraform/wazuh-project/` — see
*Dependency order* below. As of D-018 this is a **single apply** — no conditional grant, no
re-apply.

### Golden-AMI cross-account share (D-015) — **DONE, operator-reported**

`packer/wazuh-ami.pkr.hcl` sets `ami_users` / `snapshot_users` to `[var.lab_account_id]`;
`packer/ami-sharing.pkr.hcl` declares the required (no-default) `lab_account_id` variable;
`terraform/packer-build/packer-execution-role.tf` adds `ec2:ModifyImageAttribute` +
`ec2:ModifySnapshotAttribute` scoped to this region's `image/*` / `snapshot/*`. Per the
operator, this has now run: the Security-owned AMI is shared to Lab, Lab confirmed it can
launch it, and an SSM smoke test passed (not independently verified in this session — no id
recorded here). Boot volume is unencrypted → no KMS involved (a CMK would be needed only if
boot encryption is added later — deferred).

### Dependency order (D-018 — one-directional; no more two-pass apply)

Earlier (D-017), `terraform/wazuh-artifacts/`'s cross-account grant needed the Lab runtime
role's ARN, but that role was created by `terraform/wazuh-project/`, which itself needed
`terraform/wazuh-artifacts/`'s outputs — a circular dependency requiring a two-pass apply.
**D-018 removes this entirely** by splitting the Lab IAM identity into its own persistent
root, applied first:

```
1. terraform/wazuh-runtime-identity/   (Lab, persistent)
     -> creates the EC2 role + instance profile.
     -> Its own ECR/S3 policy is built from var.security_account_id + a naming
        convention shared with wazuh-artifacts — NOT a live output, so this
        root depends on nothing else.

2. terraform/wazuh-artifacts/          (Security, persistent)
     -> var.lab_runtime_role_arn is now REQUIRED — supply step 1's
        wazuh_runtime_role_arn output.
     -> grants cross-account ECR pull + S3 read to exactly that role,
        in ONE apply. No re-apply needed, ever, for this reason.

3. terraform/wazuh-project/            (Lab, disposable)
     -> consumes step 1's wazuh_runtime_instance_profile_name and
        step 2's ecr_registry / artifact_bucket_name.
```

No root depends on one applied *after* it — the ordering is strictly 1 → 2 → 3. Destroying
and redeploying the disposable runtime (root 3) at any point does **not** require touching
roots 1 or 2 again, and does **not** invalidate the cross-account grant (the role it points
to isn't being recreated).

---

## Incomplete components (Partial)

| Component | What exists | What's missing |
| --- | --- | --- |
| ECR repositories (persistent, Security-owned) | [terraform/wazuh-artifacts/ecr.tf](../terraform/wazuh-artifacts/ecr.tf) — 3 repos, `IMMUTABLE`, scan-on-push, **plus** an unconditional cross-account repository policy (D-018) | Not applied; no image-mirror workflow (B2) |
| S3 artifact bucket (persistent, Security-owned) | [terraform/wazuh-artifacts/storage.tf](../terraform/wazuh-artifacts/storage.tf) — bucket + block-public-access + SSE-S3 + TLS-deny policy, **plus** unconditional Lab-read statements (D-018) | Not applied; empty; no checked-in Wazuh artifact set (B3); no object versioning |
| Wazuh **runtime** EC2 instance (Lab) | Resource with dedicated SG, encrypted `gp3` root volume, IMDSv2, no public IP, existing instance profile, templated user-data (D-019) ([ec2.tf](../terraform/wazuh-project/ec2.tf)) | Runtime not applied. Must consume the **shared Security-owned AMI** (D-015), the `wazuh_runtime_instance_profile_name` (identity root), and the `wazuh_ecr_registry` / `wazuh_artifact_bucket_name` vars (artifact root) |
| EC2 user-data | Template does S3 sync + ECR login (registry passed in explicitly — D-017) + `docker compose pull/up` + cert generation ([install-wazuh.sh.tftpl](../terraform/wazuh-project/scripts/install-wazuh.sh.tftpl)) | Depends on ECR images and S3 artifacts that don't exist (B2/B3); no health/wait/verification logic |
| Terraform outputs (runtime root) | [outputs.tf](../terraform/wazuh-project/outputs.tf) now has `instance_id`, `ssm_start_session_command`, `security_group_id` (D-019) | Complete for the known gaps |

---

## Not implemented (Planned)

CloudTrail · GuardDuty · Security Hub · AWS Config · CloudWatch (log groups/alarms) ·
EventBridge · Firehose · SQS · Step Functions · Lambda · SNS ·
`Security Hub → EventBridge → Firehose → S3 → SQS → Wazuh` ingestion ·
`Security Hub/EventBridge → Step Functions → selective response` ·
Wazuh agents · lab test workloads · SprintOps Tracker · CI (fmt/validate/lint) ·
detection/investigation/response scenarios and evidence.

The **three-account model** is **accepted** (D-014); per the operator the build path is
applied in Security and Lab has a shared, smoke-tested AMI, but `terraform/wazuh-runtime-identity/`,
`terraform/wazuh-artifacts/`, and `terraform/wazuh-project/` are **not applied** anywhere.
Cross-account ECR/S3 access policies for the Lab runtime are now **implemented in code**
(D-018), single-apply, no longer conditional. A remote Terraform state backend is an **open
decision** — see below.

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

### Three-account migration — steps 1–4 DONE (operator-reported); 5–9 REMAINING (D-014 / D-018)

| Step | Item | Status / Detail |
| --- | --- | --- |
| 1 | Apply `terraform/packer-build/` in **Security** | **Done** (operator-reported). `AWS_PROFILE=security-admin`. Code was account-agnostic; no change needed. |
| 2 | Build + validate a **new Security-owned** base AMI | **Done** (operator-reported). Supersedes `ami-0b1bf8942dfc0daf1`, which is now historical evidence only. |
| 3 | Golden AMI shared to **Lab** | **Done** (operator-reported). `ami_users` / `snapshot_users` (D-015); the cross-account `ec2:ModifyImageAttribute` / `ec2:ModifySnapshotAttribute` actions worked. |
| 4 | Confirm Lab can launch the shared AMI + SSM smoke test | **Done** (operator-reported). |
| 5 | Destroy the **legacy** Packer build infra in **Management** | **Not done.** `AWS_PROFILE=cloudguard-admin` (`terraform -chdir=terraform/packer-build destroy`). |
| 6 | Apply `terraform/wazuh-runtime-identity/` in **Lab** | **Not done.** `AWS_PROFILE=lab-admin` (D-018) — new step, must run before step 7. |
| 7 | Apply `terraform/wazuh-artifacts/` in **Security**, supplying step 6's role ARN | **Not done.** `AWS_PROFILE=security-admin` (D-016/D-018) — single apply, grants cross-account access immediately. |
| 8 | B2/B3 (image mirror + artifact publish) | **Not done.** |
| 9 | Apply `terraform/wazuh-project/` in **Lab**, supplying steps 6 + 7's outputs | **Not done.** No further re-apply of any earlier root is needed (D-018). |

### Runtime deployment — REMAINING

| ID | Blocker | Detail |
| --- | --- | --- |
| **B2** | No Wazuh ECR image mirror/publish workflow | Nothing pulls the upstream Wazuh manager/indexer/dashboard images at **4.14.7** (D-009) and pushes them to the Security ECR repos. `docker compose pull` on the runtime instance would fail. |
| **B3** | No complete Wazuh artifact set / S3 publish workflow | No `docker-compose.yml`, `generate-indexer-certs.yml`, or manager/indexer/dashboard config (Wazuh **4.14.7**) in the repo, and nothing publishes such a set to `s3://<security-artifact-bucket>/wazuh/`. |
| ~~**X-ACCT**~~ | Cross-account ECR/S3 access for the Lab runtime | **Implemented in code (D-018)** — an unconditional ECR repository policy + S3 bucket policy statements in `terraform/wazuh-artifacts/`, granted to the identity root's role in a single apply. **Not yet applied** — just needs the 3-root apply order (steps 6→7→9), no re-apply. |

### Runtime completion / hardening gaps

These finish Phase 1 once the migration, B2/B3, and the publication-ordering decision are settled.

| Gap | Notes |
| --- | --- |
| Runtime `terraform apply` not run | `terraform/wazuh-project/` (VPC `10.0.0.0/16`, EC2) has never been applied — now targets the **Lab** account. |
| Runtime must consume the **shared** AMI | `var.wazuh_ami_id` = the Security-owned AMI id shared to Lab (step 2/3 above). |
| ~~EC2 user-data registry host~~ | **Fixed (D-017).** `install-wazuh.sh.tftpl` now takes `${ecr_registry}` from Terraform (`var.wazuh_ecr_registry`, sourced from `terraform/wazuh-artifacts/` output `ecr_registry`) instead of deriving it from `aws sts get-caller-identity`. |
| ~~Legacy `ecr.tf` / `storage.tf` removal from `wazuh-project/`~~ | **Done (D-017).** Both files removed; `terraform/wazuh-project/` now consumes Security's ECR/S3 via explicit variables. `stash@{0}` now targets a deleted file — expect a conflict if it is ever popped; it was left untouched. |
| ~~Circular dependency between `wazuh-artifacts` and `wazuh-project`~~ | **Fixed (D-018).** Lab EC2 IAM role/profile moved to the new persistent `terraform/wazuh-runtime-identity/` root, applied before `wazuh-artifacts`. No more two-pass apply. |
| ~~Dedicated EC2 security group~~ | **Done (D-019).** [security.tf](../terraform/wazuh-project/security.tf) — zero ingress; egress scoped to the VPC endpoints only. |
| ~~Explicit root volume sizing~~ | **Done (D-019).** `root_block_device { volume_type = "gp3", volume_size = 50, encrypted = true }` — 50 GB is a reference size, not a hard requirement; revisit under real indexer load. |
| ~~IMDSv2 enforcement on the runtime instance~~ | **Done (D-019).** `metadata_options { http_tokens = "required", http_put_response_hop_limit = 1 }`. |
| ~~Useful runtime Terraform outputs~~ | **Done (D-019).** `instance_id`, `ssm_start_session_command`, `security_group_id`. |
| RUNBOOK runtime steps use placeholder ids | Steps 3–11 still have `ami-XXXX` / `i-XXXX` placeholders. |

### Related quality gaps (track for Phase 1 close-out, not blocking)

No remote state backend (now 4 roots / 2 accounts) · no CI checks (`fmt`/`validate`/`tflint`)
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
apply wazuh-runtime-identity (Lab)  →  apply wazuh-artifacts (Security)  →
  publish images (B2) + config (B3)  →  apply runtime (Lab)  →  first boot
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
| 2 | Remote Terraform state backend + locking — now **4 roots across 2 accounts**; local state is getting risky. | ROADMAP backlog |
| 3 | Whether to ever prune retained ECR images / S3 artifacts between lab sessions. | D-006, D-016 |

**Closed since last revision:** multi-account transition point → **D-014** (was open #3 /
D-007); separate artifact root/state → **D-016** (was open #2); artifact-bucket encryption →
**D-010** Accepted (SSE-S3 + TLS, CMK deferred) (was open #4); Wazuh version pin → **4.14.7**
(D-009) (was open #5).

---

## Exact next logical task

> Still Phase 1. Migration steps 1–4 are **done, operator-reported**. This pass was
> **repository changes only** (D-018/D-019) — the next actions are the operator-run
> remainder of the migration (now a strictly one-directional 3-root apply, no re-apply),
> then B2/B3 + the runtime deploy. Do NOT start Phase 2+ (detection/ingestion/response). No
> further "PB" work is needed.

**Remaining operator sequence** (see [RUNBOOK.md](RUNBOOK.md) → Migration):

1. `AWS_PROFILE=cloudguard-admin` → `terraform -chdir=terraform/packer-build destroy` of the
   **legacy Management** copy (migration step 5) — only after independently confirming the
   Security build + Lab share (steps 1–4) really are in the state reported.
2. `AWS_PROFILE=lab-admin` → `terraform -chdir=terraform/wazuh-runtime-identity apply`
   (supplying `security_account_id`) → migration step 6. Creates the Lab EC2 role/profile.
3. `AWS_PROFILE=security-admin` → `terraform -chdir=terraform/wazuh-artifacts apply`
   (supplying `lab_runtime_role_arn` from step 2's `wazuh_runtime_role_arn` output) →
   migration step 7. **Single apply** — grants cross-account access immediately, no re-apply.
4. **B3 — Wazuh 4.14.7 artifact set + S3 publish** to the Security artifact bucket
   (`terraform -chdir=terraform/wazuh-artifacts output -raw artifact_bucket_name`).
5. **B2 — ECR image mirror** (Wazuh 4.14.7) to the Security ECR repos
   (`terraform -chdir=terraform/wazuh-artifacts output -raw ecr_registry`).
6. `AWS_PROFILE=lab-admin` → `terraform -chdir=terraform/wazuh-project apply` supplying
   `wazuh_ami_id` (the shared AMI), `wazuh_runtime_instance_profile_name` (step 2's output),
   `wazuh_ecr_registry`, `wazuh_artifact_bucket_name` (step 3's outputs) — migration step 9.
   The runtime can pull images / read config immediately — no further root needs a re-apply.
7. SSM shell (`terraform -chdir=terraform/wazuh-project output -raw ssm_start_session_command`)
   → SSM port-forward to the dashboard → manager + indexer + dashboard healthy →
   `terraform destroy` of the **runtime root only** → verified cleanup.
8. **Resolve `stash@{0}`** (it now targets a deleted file — dropping it is expected once
   confirmed nothing else in it is needed).
9. **Update [ROADMAP.md](ROADMAP.md), [RUNBOOK.md](RUNBOOK.md), and this file** with real
   commands / results / ids (including the new AMI id, which is not recorded anywhere in
   this repository yet).

### Prerequisites that already exist

Account structure + SSO permission sets (Management / Security / Lab) · Packer build infra
+ a validated Security-owned golden AMI, shared to Lab and smoke-tested (operator-reported)
· all four Terraform roots in code, including the D-018 one-directional cross-account
structure and the D-019 runtime hardening (`packer-build`, `wazuh-runtime-identity`,
`wazuh-artifacts`, `wazuh-project`) · the Packer AMI-sharing config. The remaining work is:
retire the legacy Management build infra, apply the 3 dependent roots in order (identity →
artifacts → runtime), B2/B3, and the runtime apply/validate.

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
| [terraform/packer-build/](../terraform/packer-build/) | Terraform root — **persistent Packer build infrastructure** (D-012). Applied **in Security** per the operator (originally Management). Do not destroy with the runtime |
| [terraform/packer-build/packer-execution-role.tf](../terraform/packer-build/packer-execution-role.tf) | Packer execution role + least-privilege policy (PB-4 / D-013), incl. `ec2:ModifyImageAttribute` / `ec2:ModifySnapshotAttribute` (region-scoped) for the Lab AMI share (D-015) |
| [terraform/wazuh-runtime-identity/](../terraform/wazuh-runtime-identity/) | **NEW this pass.** Terraform root — **persistent Lab EC2 IAM role + instance profile** (D-018), Lab account. Applied **first**, before `wazuh-artifacts`. Not applied |
| [terraform/wazuh-runtime-identity/iam.tf](../terraform/wazuh-runtime-identity/iam.tf) | `aws_iam_role.wazuh_ec2` + `aws_iam_instance_profile.wazuh_ec2` (moved from `wazuh-project/roles.tf`) + deterministic cross-account ECR/S3 policy built from `var.security_account_id` |
| [terraform/wazuh-runtime-identity/variables.tf](../terraform/wazuh-runtime-identity/variables.tf) | Required `security_account_id` (12-digit-validated) |
| [terraform/wazuh-runtime-identity/outputs.tf](../terraform/wazuh-runtime-identity/outputs.tf) | `wazuh_runtime_role_arn` (→ `wazuh-artifacts`), `wazuh_runtime_instance_profile_name` (→ `wazuh-project`) |
| [terraform/wazuh-artifacts/](../terraform/wazuh-artifacts/) | Terraform root — **persistent ECR + S3 artifact layer + unconditional cross-account grants** (D-016 / D-018), Security account. Applied **second**. Not applied |
| [terraform/wazuh-artifacts/variables.tf](../terraform/wazuh-artifacts/variables.tf) | **This pass:** `lab_runtime_role_arn` is now **required** (was optional/default-`null` under D-017) |
| [terraform/wazuh-artifacts/ecr.tf](../terraform/wazuh-artifacts/ecr.tf) | **This pass:** `aws_ecr_repository_policy.lab_pull` is now unconditional (`for_each = local.ecr_repositories`) |
| [terraform/wazuh-artifacts/storage.tf](../terraform/wazuh-artifacts/storage.tf) | **This pass:** bucket policy's Lab-read statements are now unconditional (no more `concat()` with a conditional list) |
| [terraform/wazuh-artifacts/outputs.tf](../terraform/wazuh-artifacts/outputs.tf) | **This pass:** removed `lab_cross_account_access_granted` (no longer meaningful — always true now) |
| [terraform/wazuh-project/](../terraform/wazuh-project/) | Terraform root — **disposable Wazuh runtime**, **Lab** account (D-014). Applied **third/last**. Not applied |
| [terraform/wazuh-project/providers.tf](../terraform/wazuh-project/providers.tf) | **This pass:** header rewritten for the 3-root dependency order; documents that this root creates no IAM role any more |
| [terraform/wazuh-project/variables.tf](../terraform/wazuh-project/variables.tf) | **This pass:** removed `wazuh_ecr_repository_arns` (no longer needed — IAM moved out); added required `wazuh_runtime_instance_profile_name` |
| [terraform/wazuh-project/ec2.tf](../terraform/wazuh-project/ec2.tf) | **This pass (D-019):** dedicated SG, `associate_public_ip_address = false`, IMDSv2 `metadata_options`, encrypted `gp3` `root_block_device`, `iam_instance_profile` by variable, not local resource |
| [terraform/wazuh-project/security.tf](../terraform/wazuh-project/security.tf) | **NEW this pass (D-019).** Dedicated Wazuh EC2 security group |
| [terraform/wazuh-project/outputs.tf](../terraform/wazuh-project/outputs.tf) | **This pass:** `wazuh_runtime_role_arn` removed (role no longer created here); added `instance_id`, `ssm_start_session_command`, `security_group_id` |
| ~~terraform/wazuh-project/roles.tf~~ | **Removed this pass (D-018).** Moved to `terraform/wazuh-runtime-identity/iam.tf` |
| ~~terraform/wazuh-project/ecr.tf~~ / ~~storage.tf~~ | **Removed (D-017).** Superseded by `wazuh-artifacts/`. `stash@{0}` still modifies the (now-deleted) `ecr.tf` — left untouched; will conflict if popped |
| [terraform/wazuh-project/scripts/install-wazuh.sh.tftpl](../terraform/wazuh-project/scripts/install-wazuh.sh.tftpl) | `ECR_REGISTRY` comes from `${ecr_registry}` (Terraform), not `aws sts get-caller-identity` (D-017) |
| [packer/wazuh-ami.pkr.hcl](../packer/wazuh-ami.pkr.hcl) | AMI build definition — build-network filters, `assume_role`, and **`ami_users` / `snapshot_users`** for the Lab share (D-015) |
| [packer/ami-sharing.pkr.hcl](../packer/ami-sharing.pkr.hcl) | Required (no-default) `lab_account_id` variable |
| [packer/build-identity.pkr.hcl](../packer/build-identity.pkr.hcl) | `packer_execution_role_arn` var |
| [packer/scripts/install-wazuh-base.sh](../packer/scripts/install-wazuh-base.sh) | Bake-time host provisioner — **B1 done**; host-prerequisites-only boundary (D-011) unchanged this pass |

The pre-`333460c` combined bootstrap (`git show cca2387:terraform/wazuh-project/scripts/install-wazuh.sh`)
is kept only as historical reference for the Docker/kernel steps; it also contains runtime
logic and an old Wazuh version and must not be copied wholesale.

---

## Handoff notes

- The repository is the project record. Everything needed to resume work is in version
  control; do not rely on any context from outside it.
- **Account layering (D-014):** **Management** = Organizations / SSO / billing only.
  **Security** = `terraform/packer-build/` + `terraform/wazuh-artifacts/` + the golden AMI +
  future security tooling — all **persistent**. **Lab** = `terraform/wazuh-runtime-identity/`
  (persistent, D-018) + `terraform/wazuh-project/` runtime (disposable, D-006) + test
  workloads + SprintOps Tracker. Terraform is account-agnostic; which account an apply lands
  in is decided by the profile/permission set that runs it.
- **Lifecycle layering (keep this distinction):** persistent build/artifact/identity infra
  (`packer-build/`, `wazuh-artifacts/`, `wazuh-runtime-identity/`) — never in the destroy
  cycle · the temporary Packer builder — ephemeral, per build · the golden AMI — a reusable
  artifact owned by Security, shared to Lab by launch permission only (D-015) · the Lab
  runtime — disposable.
- **Per the operator, `packer-build` + the golden AMI are now applied in Security**, shared
  to Lab and smoke-tested — this session did not verify that independently and recorded no
  new AMI id or account id. **`wazuh-runtime-identity`, `wazuh-artifacts`, and
  `wazuh-project` are not applied anywhere.** The legacy `packer-build` + AMI
  `ami-0b1bf8942dfc0daf1` still sit in **Management**, pending retirement. The runtime VPC
  (`10.0.0.0/16`) has never existed anywhere.
- The historical design (`t3.large`, ~50 GB EBS, `git clone wazuh-docker`) is **partly
  superseded** by `333460c` (→ `c5a.xlarge`, no explicit root volume, delivery via private
  ECR + S3 — [DECISIONS.md](DECISIONS.md) D-009). Wazuh is now **pinned to 4.14.7** (D-009);
  B2/B3 target that version.
- Cost: `packer-build/`, `wazuh-artifacts/`, and `wazuh-runtime-identity/` carry **no hourly
  cost** (control-plane / IAM only, empty bucket + empty repos). The Lab runtime carries
  endpoint + EC2 hourly cost — `terraform destroy` the **runtime root only** after validating
  (D-006). Never destroy the two persistent Security roots or the persistent Lab identity
  root as part of that cycle. ECR images / S3 config **persist** between sessions by design
  (D-016); the Lab identity (and Security's grant to it) **also persists** across disposable
  runtime redeploys by design (D-018).
- **Four Terraform roots now** (D-008 → D-012 → D-016 → D-018). Each split is justified by a
  materially different lifecycle (and, for `wazuh-artifacts/` / `wazuh-runtime-identity/`,
  cross-account ownership). Do not add a fifth speculatively.
- **PB-4 / D-013 + D-015:** the execution-role policy is derived from the *current*
  `amazon-ebs` config, which now includes `ami_users` / `snapshot_users` → it grants
  `ec2:ModifyImageAttribute` / `ec2:ModifySnapshotAttribute` scoped to this region's
  `image/*` / `snapshot/*` (cannot publish, cannot copy). If the config changes again,
  re-derive — add only the specific denied action per real `AccessDenied`, never `ec2:*` /
  `ssm:*` / all documents / all resources. No AWS account ID is in source. `lab_account_id`
  is a **required** Packer var (no default), non-secret, supplied via `PKR_VAR_lab_account_id`.
- **D-018 (this pass): the circular dependency is gone; apply order is strictly
  one-directional.** `terraform/wazuh-runtime-identity/` (Lab, persistent) owns the EC2
  role/profile and is applied **first** — its own ECR/S3 policy is built deterministically
  from a required `security_account_id` variable + the naming convention shared with
  `wazuh-artifacts`, not a live output, so it depends on nothing. `terraform/wazuh-artifacts/`
  (Security) is applied **second**, now requiring `lab_runtime_role_arn` (no default) and
  granting cross-account access **unconditionally in one apply** — no more re-apply.
  `terraform/wazuh-project/` (Lab, disposable) is applied **third**, consuming both earlier
  roots' outputs and creating no IAM role of its own. See *Dependency order* above before
  assuming any two-pass sequence is still needed — it is not.
- **`git stash@{0}` now targets a file that no longer exists** (`wazuh-project/ecr.tf`,
  removed by D-017). It was **not** popped, applied, dropped, or modified — per instruction —
  but popping it later will conflict on the deleted file; that is expected, not a bug to
  silently work around.
- **Operator-reported vs. this session's own evidence.** This session made zero AWS calls.
  Everywhere this file says a migration step is "Done (operator-reported)", that is the
  operator's statement, recorded because they asked for it, not something this session
  observed or can cite an id for. The next person who touches AWS directly should replace
  those with real evidence (AMI id, `terraform output` values) the first chance they get.
- When you finish a substantial task, update this file (Snapshot, milestone, blockers/gaps,
  open decisions, next task) and any other doc whose assumptions changed.
