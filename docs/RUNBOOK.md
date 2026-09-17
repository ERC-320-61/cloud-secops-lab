# CloudGuard — Runbook

> Operational skeleton for the temporary-lab lifecycle:
> `deploy → test → validate → document → destroy`.
>
> **Reality check (2026-09-16):** the Packer prerequisite phase is **complete**, and — per
> the operator — the **build-path migration has run**: `terraform/packer-build/` is applied
> in **Security**, a new Security-owned golden AMI is built, validated, **shared to Lab**,
> confirmed launchable there, and SSM-smoke-tested (migration steps 1–4). This repository
> pass made **no AWS calls** and recorded no independent evidence (no AMI id / account id).
> The legacy Management build infra + the historical AMI (`ami-0b1bf8942dfc0daf1`) are still
> in **Management**, pending retirement (step 5). `terraform/wazuh-runtime-identity/`
> (step 6), `terraform/wazuh-artifacts/` (step 7), and `terraform/wazuh-project/` (step 9)
> are **not applied anywhere**. This pass also fixed a circular Terraform dependency between
> the last two of those roots (D-018): the Lab EC2 IAM role now lives in a new persistent
> root applied **before** `wazuh-artifacts`, so the cross-account grant is a single,
> unconditional apply — no re-apply of any root is needed. `terraform/wazuh-project/` also
> gained EC2 hardening (dedicated SG, IMDSv2, encrypted root volume, real outputs — D-019).
> Code only. Sections 3–11 (the **runtime** Wazuh deployment in Lab) are still not
> runnable — B2/B3 and the publication-ordering decision remain open. Those steps stay
> marked **⛔**.

All commands assume repo root `cloud-secops-lab/` and AWS credentials for the target account
already configured (`aws sts get-caller-identity` succeeds).

> **⚠️ Runtime deployment ordering is not fully proven.** D-016 gives the persistent
> destinations (ECR repos + artifact bucket) their own Security-account root
> (`terraform/wazuh-artifacts/`), applied **before** the Lab runtime — so the old
> same-root chicken-and-egg is gone. What is still not proven end-to-end: populating those
> destinations (B2/B3), the cross-account ECR/S3 access policies the Lab runtime needs, and
> the first full `apply wazuh-artifacts → publish → apply runtime` run. See
> [CURRENT_STATE.md](CURRENT_STATE.md) → *Open decisions*. Do not treat steps 3–5 as a
> validated order yet.

---

## 0. Prerequisites

| Requirement | Check | Status (operator workstation, 2026-09-06) |
| --- | --- | --- |
| AWS CLI v2 | `aws --version` | **verified — `aws-cli/2.36.37`** |
| AWS Session Manager plugin (required — Packer tunnels the builder over SSM) | `session-manager-plugin --version` | **verified — `1.2.835.0`** |
| Terraform `>= 1.7.0` | `terraform version` | **verified — `v1.16.1`** |
| Packer `>= 1.9` (Amazon plugin `github.com/hashicorp/amazon v1.8.2`) | `packer version` | **verified — installed; `packer init`/`validate` pass** |
| Profiles for the three accounts (IAM Identity Center) | `aws sts get-caller-identity` per profile | `cloudguard-admin` (Management), `security-admin` / `security` (Security), `lab-admin` / `lab` (Lab) |
| Packer execution-role ARN (PB-4 / [DECISIONS.md](DECISIONS.md) D-013) | `terraform -chdir=terraform/packer-build output -raw packer_execution_role_arn` (required Packer var, no default) | created by the Security `terraform apply`; Packer assumes it via `assume_role` |
| Lab account ID (cross-account AMI share — D-015) | `PKR_VAR_lab_account_id` (required Packer var, no default; non-secret account metadata) | operator-supplied at build time |
| Docker (only if publishing Wazuh images locally — blocker B2) | `docker version` | not required for the AMI build |

Region is `us-east-2` (`var.aws_region`) everywhere. All three Terraform roots discover
their account ID at apply time (`data.aws_caller_identity`); **no account ID is committed to
source**. The one cross-account value, the Lab account ID, is a required Packer variable.

**Identity / account model** ([DECISIONS.md](DECISIONS.md) D-014 / D-013):

| Account | Admin permission set | Operator permission set | Runs |
| --- | --- | --- | --- |
| Management | `cloudguard-admin` | — | Organizations, SSO, billing; `terraform destroy` of the legacy Packer build infra |
| Security | `security-admin` | `security` → `CloudGuardOperator` | `terraform apply` of `packer-build/` + `wazuh-artifacts/`; routine `packer build` (assumes `cloud-secops-lab-packer-execution-role`) |
| Lab | `lab-admin` | `lab` → `LabOperator` | `terraform apply` of `wazuh-project/` (the disposable runtime) |

---

## M. Migration to the three-account model (D-014 / D-018)  — steps 1–4 DONE (operator-reported), 5–9 ⛔

> Each numbered step names the profile it runs as. Steps are ordered; do not skip ahead.
> **Steps 1–4 are reported done by the operator** — this repository pass made no AWS calls
> and cannot independently confirm them; treat that status as reported, not verified here.
> **Steps 6–9 are a strictly one-directional sequence (D-018) — no root is ever re-applied.**

**Current reality:** per the operator, the persistent Packer build infrastructure and a new
golden AMI are applied/built in the **Security** account, and the AMI is shared to and
smoke-tested in **Lab**. The historical AMI `ami-0b1bf8942dfc0daf1` and the legacy Packer
build infrastructure are still in **Management**, pending step 5.
`terraform/wazuh-runtime-identity/` (step 6), `terraform/wazuh-artifacts/` (step 7), and
`terraform/wazuh-project/` (step 9) have not been applied anywhere.

```bash
# 1. Apply the persistent Packer build infrastructure in SECURITY.  — DONE (operator-reported)
aws sso login --profile security-admin
terraform -chdir=terraform/packer-build fmt -check
terraform -chdir=terraform/packer-build init          # hashicorp/aws 6.57.1 (committed lock file)
terraform -chdir=terraform/packer-build validate
AWS_PROFILE=security-admin terraform -chdir=terraform/packer-build apply
AWS_PROFILE=security-admin terraform -chdir=terraform/packer-build output

# 2. Build + validate a NEW Security-owned base AMI (section 1). Runs as `security`,
#    Packer assumes the execution role. Requires the Lab account id for the share.
#    — DONE (operator-reported); record the real AMI id here once confirmed directly.
aws sso login --profile security
cd packer
export PKR_VAR_packer_execution_role_arn="$(AWS_PROFILE=security-admin terraform -chdir=../terraform/packer-build output -raw packer_execution_role_arn)"
export PKR_VAR_lab_account_id=<lab account id>          # non-secret; not committed to source
packer fmt -check . && packer init . && packer validate .
AWS_PROFILE=security packer build .
cd ..
#    -> record the new AMI id; smoke-test it (section 2).

# 3. Confirm the AMI is shared to Lab (launch permission only, not public):  — DONE (operator-reported)
AWS_PROFILE=security aws ec2 describe-image-attribute --region us-east-2 \
  --image-id <new ami id> --attribute launchPermission

# 4. From the Lab account, confirm Lab can see / launch the shared AMI + SSM smoke test:
#    — DONE (operator-reported)
AWS_PROFILE=lab-admin aws ec2 describe-images --region us-east-2 --image-ids <new ami id>

# 5. ONLY after independently confirming step 4 — destroy the LEGACY Packer build infra
#    in MANAGEMENT:  — NOT DONE
aws sso login --profile cloudguard-admin
AWS_PROFILE=cloudguard-admin terraform -chdir=terraform/packer-build destroy
#    (the Management-account AMI ami-0b1bf8942dfc0daf1 can be deregistered separately once
#     the Security AMI is proven)

# 6. Apply the persistent Lab runtime identity (D-018). This creates the EC2 role + instance
#    profile that BOTH later roots depend on — must run before step 7.  — NOT DONE
aws sso login --profile lab-admin
terraform -chdir=terraform/wazuh-runtime-identity fmt -check
terraform -chdir=terraform/wazuh-runtime-identity init
terraform -chdir=terraform/wazuh-runtime-identity validate
AWS_PROFILE=lab-admin terraform -chdir=terraform/wazuh-runtime-identity apply \
  -var "security_account_id=<security account id>"
AWS_PROFILE=lab-admin terraform -chdir=terraform/wazuh-runtime-identity output

# 7. Apply the persistent artifact layer in SECURITY (D-016), supplying step 6's role ARN.
#    lab_runtime_role_arn is REQUIRED — this grants cross-account access in this ONE apply,
#    no re-apply needed later.  — NOT DONE
aws sso login --profile security-admin
terraform -chdir=terraform/wazuh-artifacts fmt -check
terraform -chdir=terraform/wazuh-artifacts init
terraform -chdir=terraform/wazuh-artifacts validate
AWS_PROFILE=security-admin terraform -chdir=terraform/wazuh-artifacts apply \
  -var "lab_runtime_role_arn=$(AWS_PROFILE=lab-admin terraform -chdir=terraform/wazuh-runtime-identity output -raw wazuh_runtime_role_arn)"
AWS_PROFILE=security-admin terraform -chdir=terraform/wazuh-artifacts output

# 8. Continue B3 (Wazuh 4.14.7 artifact set + S3 publish) and B2 (ECR image mirror) — sections 3/4.
#    — NOT DONE

# 9. Deploy the disposable Wazuh runtime in LAB, supplying step 6's instance-profile name and
#    step 7's registry/bucket outputs (D-017/D-018) — section 5. This is the LAST step; no
#    earlier root needs to be touched again.  — NOT DONE
```

> **Terraform state.** State is local per root. Keep each root's `.terraform/` + state file
> with the operator who runs it. A remote backend is an open decision (now 4 roots / 2
> accounts) — see [CURRENT_STATE.md](CURRENT_STATE.md). **Do not switch Terraform workspaces
> or touch any root's state file** as part of running these steps — each root uses its
> default workspace and local state as-is.
>
> **Dependency order is one-directional (D-018):** `wazuh-runtime-identity` → `wazuh-artifacts`
> → `wazuh-project`. No root here is ever applied twice for a dependency reason — if you find
> yourself re-applying an earlier root to pick up a later root's output, something is wrong;
> see [CURRENT_STATE.md](CURRENT_STATE.md) → *Dependency order*.

---

## 1. Build the Wazuh base AMI (Packer)  — ✅ Proven; applied in Security (operator-reported)

### 1a. Provision the persistent Packer build infrastructure (one-time per account; bootstrap)

```bash
# Bootstrap: run this apply with the security-admin permission set (AdministratorAccess in
# Security — deliberate, one-off). It creates the build VPC/subnet/IGW/route/SG/instance
# profile AND the Packer execution role — the persistent role Packer uses thereafter.
terraform -chdir=terraform/packer-build fmt -check
terraform -chdir=terraform/packer-build init       # selects hashicorp/aws 6.57.1 (committed lock file)
terraform -chdir=terraform/packer-build validate
AWS_PROFILE=security-admin terraform -chdir=terraform/packer-build apply
terraform -chdir=terraform/packer-build output
```

- Applied **in Management** today; the migration (section M step 1) re-applies it in
  **Security**. Re-run `apply` only when this root's config changes, and only with an
  AdministratorAccess permission set. The account ID is discovered at apply time.
- The execution role has **no** permission over its own IAM role or the build
  VPC/subnet/IGW/SG/route table (bootstrap boundary, D-013) — which is why the `apply`
  uses `security-admin`, not the execution role. Routine `packer build`s (step 1b) run as
  `security` and do **not** touch this root.
- This root is **persistent supporting infrastructure** — do **not** `terraform destroy` it
  as part of the Wazuh runtime deploy→test→validate→destroy cycle
  ([DECISIONS.md](DECISIONS.md) D-012).
- Cost: VPC, subnet, Internet Gateway, route table, security group and IAM only — **no
  hourly or data-processing charge**. Cost is incurred only by the ephemeral builder Packer
  creates during a build.
- Non-overlapping CIDR: build VPC `10.10.0.0/24` vs. Wazuh runtime `10.0.0.0/16`.

### 1b. Build the AMI

Base credentials are a normal `security` (CloudGuardOperator) SSO session; Packer then
`assume_role`s the execution role for all AWS work. **Both** `PKR_VAR_packer_execution_role_arn`
and `PKR_VAR_lab_account_id` are required (no defaults).

```bash
aws sso login --profile security          # CloudGuardOperator in Security — no admin
cd packer

export PKR_VAR_packer_execution_role_arn="$(AWS_PROFILE=security-admin terraform -chdir=../terraform/packer-build output -raw packer_execution_role_arn)"
export PKR_VAR_lab_account_id=<lab account id>   # non-secret account metadata; not committed

packer fmt -check .
packer init .        # installs github.com/hashicorp/amazon v1.8.2
packer validate .    # fails if either PKR_VAR_* is unset (any 12-digit value validates lab_account_id)
AWS_PROFILE=security packer build .
# resulting AMI name: cloud-secops-wazuh-<timestamp>; shared to the Lab account by launch permission (D-015)
```

The equivalent sequence ran end-to-end **in Management** on 2026-09-07 (before the AMI-share
config existed): assume-role → build-VPC/subnet/SG discovery → temp key pair + builder
launch → Session Manager port-forward tunnel → `install-wazuh-base.sh` → AMI register →
source instance terminated → temp key pair deleted. Evidence AMI: `ami-0b1bf8942dfc0daf1`
(`us-east-2`, **Management**) — historical validation evidence, not a config constant, not
the future Security AMI. The first Security build additionally exercises `ami_users` /
`snapshot_users` → if it hits `AccessDenied` on `ec2:DescribeImageAttribute` (or similar),
add **only** that action to the execution-role policy, per D-013 / D-015.

`packer_execution_role_arn` and `lab_account_id` have **no defaults** and **no AWS account
ID is committed** to the Packer config — the operator supplies the role ARN from the
Terraform output above and the Lab account id via `PKR_VAR_lab_account_id`. No keys or
usernames are embedded; the base credentials come entirely from `AWS_PROFILE=security` / an
active SSO session for the `security` permission set.

**How the builder is placed** ([packer/wazuh-ami.pkr.hcl](../packer/wazuh-ami.pkr.hcl)):
Packer first `assume_role`s `cloud-secops-lab-packer-execution-role` (session name
`cloudguard-packer-build`) from the operator's base credentials, then does all AWS work with
that role. It finds the build VPC / subnet / security group by **deterministic tag
filters** —
`tag:Project = cloud-secops-lab` + `tag:Purpose = packer-build` + a resource-specific
`tag:Name` (`cloud-secops-lab-packer-build-{vpc,subnet,sg}`). `subnet_filter` has **no**
`most_free`/`random`, so if a filter ever matched more than one resource the build
**aborts** instead of guessing. It attaches the
`cloud-secops-lab-packer-build-ssm-profile` instance profile, **explicitly** associates a
public IPv4 (egress only — the subnet does not auto-assign), reaches the builder through
**SSM Session Manager** (`ssh_interface = "session_manager"`; no inbound SSH; the SG has no
ingress) — the tunnel is opened with the **`AWS-StartPortForwardingSession`** document
(confirmed by the validated build) — and requires **IMDSv2**.

**Bake-script status** ([packer/scripts/install-wazuh-base.sh](../packer/scripts/install-wazuh-base.sh)):
a true bake-time provisioner (B1 fixed) — base packages, Docker Engine + Compose plugin,
AWS CLI v2, persisted `vm.max_map_count=262144`, Docker enabled at boot, `ubuntu` in the
`docker` group, SSM agent enable, verification block. **No** Wazuh application state
([DECISIONS.md](DECISIONS.md) D-011).

**Packer prerequisite status — all COMPLETE (2026-09-07):**

- **PB-1 / D-012 — COMPLETE.** Build network implemented, locally validated, `apply`-d, and
  exercised by a successful `packer build`. Tag filters resolve to exactly one resource each.
- **PB-2 — COMPLETE.** `.gitattributes` forces `*.sh` / `*.tftpl` / `*.tf` / `*.hcl` to LF;
  exercised by the build.
- **PB-3 — COMPLETE.** The base build confirmed `amazon-ssm-agent` present, enabled and
  active on Canonical Ubuntu 24.04 (the bake script enables it via
  `snap start --enable amazon-ssm-agent`, deb-unit fallback, hard-fail if absent — D-001).
- **PB-4 / D-013 — COMPLETE.** The least-privilege execution role
  ([terraform/packer-build/packer-execution-role.tf](../terraform/packer-build/packer-execution-role.tf))
  is applied; Packer assumes it via `assume_role` (required `packer_execution_role_arn` var
  from `terraform output`). The first build exposed exactly one missing entry —
  `ssm:StartSession` on `AWS-StartPortForwardingSession` — added narrowly; the subsequent
  build succeeded end-to-end. If the `amazon-ebs` config ever changes, re-derive the policy
  and add only the specific denied action/document one at a time — never `ec2:*` / `ssm:*` /
  all documents. Full action list in [CURRENT_STATE.md](CURRENT_STATE.md) PB-4.

---

## 2. Validate the AMI (smoke test)  — ✅ Done in Management (2026-09-07) and again in Security (operator-reported)

The Management-account AMI `ami-0b1bf8942dfc0daf1` was smoke-tested via a manual EC2 instance
reached over Session Manager and **validated** on 2026-09-07. Per the operator, this was
**repeated against the new Security-owned AMI** and the Lab-launched instance
(migration section M steps 2 and 4) — not independently verified in this pass:

- AMI visible: `aws ec2 describe-images --owners self --filters 'Name=name,Values=cloud-secops-wazuh-*' --region us-east-2`
- On a throwaway instance, confirm: `docker --version`, `docker compose version`,
  `aws --version` (`aws-cli/2.*`); `sysctl -n vm.max_map_count` → `262144`;
  `systemctl is-enabled docker` → `enabled`; `systemctl is-active docker` → `active`;
  `snap services amazon-ssm-agent` enabled + active; `ubuntu` in the `docker` group;
  `/var/log/cloudguard-ami-build.txt` present with the expected build marker.
- Terminate the throwaway instance.

Management-account bake output (2026-09-07): Docker 29.8.0, Docker Compose v5.5.1, AWS CLI
v2.36.40, `vm.max_map_count=262144`. `var.wazuh_ami_id` in the runtime root has no default;
supply the **Security-owned, Lab-shared** AMI id at runtime-deploy time (step 5).

---

## Steps 3–5 — runtime deployment (Lab), pending B2/B3

> Order (D-016/D-018), strictly one-directional: **apply `terraform/wazuh-runtime-identity/`
> in Lab first** (migration step 6) → **apply `terraform/wazuh-artifacts/` in Security**,
> supplying step 6's role ARN (migration step 7 — grants cross-account access in that single
> apply) → populate it (B2/B3, steps 3–4 below) → **apply `terraform/wazuh-project/` in
> Lab** (step 5, migration step 9), supplying steps 6 and 7's outputs. No root is re-applied
> for a dependency reason — see [CURRENT_STATE.md](CURRENT_STATE.md) → *Dependency order*.
> If the runtime's `docker compose pull` / `aws s3 sync` ever fail with `AccessDenied`, it
> means step 7 ran before step 6 (or with the wrong role ARN) — not an inherent two-pass
> requirement any more.

### 3. Publish Wazuh application artifacts to S3  — ⛔ Not yet operational (B3)

The runtime bootstrap expects a Wazuh **4.14.7** stack definition ([DECISIONS.md](DECISIONS.md)
D-009) at `s3://<artifact-bucket>/wazuh/` (Compose file, `generate-indexer-certs.yml`,
manager/indexer/dashboard config).

**Blocked:** the repository contains no complete Wazuh artifact set and no publishing
workflow. Add a checked-in `wazuh/` source at 4.14.7 plus a publish path to the
**Security-owned** bucket.

Artifact bucket name pattern (from
[terraform/wazuh-artifacts/storage.tf](../terraform/wazuh-artifacts/storage.tf)):
`cloud-secops-lab-artifacts-<security_account_id>` — get the exact name from
`terraform -chdir=terraform/wazuh-artifacts output -raw artifact_bucket_name`.

**Cross-account (D-018 — implemented, not applied):** `terraform/wazuh-artifacts/storage.tf`
has an unconditional bucket-policy grant (`s3:GetObject` on `wazuh/*`, `s3:ListBucket`
prefix-scoped) for the Lab runtime role, `var.lab_runtime_role_arn` (required). Granted the
moment this root is applied — see the ordering note above.

### 4. Publish Wazuh images to private ECR  — ⛔ Not yet operational (B2)

The three repositories are defined in **Security**
([terraform/wazuh-artifacts/ecr.tf](../terraform/wazuh-artifacts/ecr.tf)):

```
cloud-secops-lab/wazuh-manager
cloud-secops-lab/wazuh-indexer
cloud-secops-lab/wazuh-dashboard
```

**Blocked:** no working workflow publishes images into them. Add a mirror workflow (pull
upstream Wazuh **4.14.7** images → tag → push to the **Security-owned** repos from section M
step 6). The repos are `IMMUTABLE`, so a tag cannot be overwritten once pushed.

**Cross-account (D-018 — implemented, not applied):**
[terraform/wazuh-artifacts/ecr.tf](../terraform/wazuh-artifacts/ecr.tf) has an unconditional
`aws_ecr_repository_policy` per repo granting `ecr:BatchGetImage` /
`ecr:GetDownloadUrlForLayer` / `ecr:BatchCheckLayerAvailability` to the Lab runtime role
(`ecr:GetAuthorizationToken` stays account-local — granted in
`terraform/wazuh-runtime-identity/iam.tf` instead, `Resource = "*"` is an AWS API constraint,
not a broadening). Granted the moment `terraform/wazuh-artifacts/` is applied (section M
step 7) — not conditional, no re-apply.

### 5. Terraform init / plan / apply — the Lab runtime  — ⛔ Not yet operational (depends on M steps 6+7)

```bash
aws sso login --profile lab-admin

# Pull the already-created identity + Security-owned resource identifiers (section M steps
# 6 and 7 must have already run):
export TF_VAR_wazuh_runtime_instance_profile_name="$(AWS_PROFILE=lab-admin terraform -chdir=terraform/wazuh-runtime-identity output -raw wazuh_runtime_instance_profile_name)"
export TF_VAR_wazuh_ecr_registry="$(AWS_PROFILE=security-admin terraform -chdir=terraform/wazuh-artifacts output -raw ecr_registry)"
export TF_VAR_wazuh_artifact_bucket_name="$(AWS_PROFILE=security-admin terraform -chdir=terraform/wazuh-artifacts output -raw artifact_bucket_name)"

terraform -chdir=terraform/wazuh-project init
terraform -chdir=terraform/wazuh-project plan  -var "wazuh_ami_id=<security AMI shared to Lab>"
AWS_PROFILE=lab-admin terraform -chdir=terraform/wazuh-project apply -var "wazuh_ami_id=<security AMI shared to Lab>"
```

This is the **last** step of the dependency chain (D-018) — no earlier root needs a
subsequent re-apply. The runtime can pull images and read config as soon as it boots.

Notes:

- Runs in the **Lab** account (`lab-admin`, or a dedicated runtime execution role later).
- `var.wazuh_ami_id` has **no default** by design. Supply the **Security-owned AMI id that
  was shared to Lab** (section M steps 2–4) via `-var`, a git-ignored `terraform.tfvars`, or
  `TF_VAR_wazuh_ami_id`.
- `var.wazuh_runtime_instance_profile_name` (from `terraform/wazuh-runtime-identity/`) and
  `var.wazuh_ecr_registry` / `var.wazuh_artifact_bucket_name` (from `terraform/wazuh-artifacts/`)
  also have **no defaults** (D-017/D-018) — this root cannot be applied without them; none
  are guessed.
- State is **local** (no remote backend) — do not delete `.terraform/` or the state file
  between plan and destroy. Do not switch this root's Terraform workspace.
- This root **owns none of**: the ECR repos, the S3 bucket (D-017 — `ecr.tf` / `storage.tf`
  removed), or the EC2 IAM role/profile (D-018 — `roles.tf` removed, moved to
  `terraform/wazuh-runtime-identity/`). The `stash@{0}` "preserve ecr comment changes" now
  targets a deleted file; it was left untouched and will conflict if popped, which is
  expected.
- **Hardening done (D-019):** dedicated security group (zero ingress; egress scoped to the
  VPC endpoints), no public IP, IMDSv2 required, encrypted `gp3` root volume (50 GB
  reference), and `instance_id` / `ssm_start_session_command` / `security_group_id` outputs.

---

## 6. Validate EC2 + SSM connectivity  — ⛔ Not yet operational (depends on 5)

All commands here run against the **Lab** account (`AWS_PROFILE=lab-admin` or `lab`).

```bash
# find the instance (or just use the runtime root's own output, D-019):
terraform -chdir=terraform/wazuh-project output -raw instance_id

aws ec2 describe-instances --region us-east-2 \
  --filters 'Name=tag:Project,Values=cloud-secops-lab' 'Name=instance-state-name,Values=running' \
  --query 'Reservations[].Instances[].InstanceId' --output text

# confirm it registered with SSM
aws ssm describe-instance-information --region us-east-2 \
  --query 'InstanceInformationList[].InstanceId' --output text

# open a shell — or just run the ready-to-paste command (D-019):
$(terraform -chdir=terraform/wazuh-project output -raw ssm_start_session_command)
```

On the instance, check the bootstrap log:

```bash
sudo cat /var/log/wazuh-user-data.log
cd /opt/wazuh-docker/single-node && sudo docker compose ps
```

---

## 7. SSM port-forward to the Wazuh dashboard  — ⛔ Not yet operational (depends on 6)

Intended (dashboard listens on 443 inside the instance):

```bash
aws ssm start-session --region us-east-2 \
  --target i-XXXXXXXXXXXXXXXXX \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["443"],"localPortNumber":["8443"]}'
# then browse https://localhost:8443  (self-signed cert)
```

The exact port/parameters should be confirmed against the finalized Wazuh Compose file
(step 3) and captured here once validated. Default Wazuh credentials must be rotated.

---

## 8. Wazuh health validation  — ⛔ Not yet operational

Once reachable, confirm:

- Dashboard loads and login works.
- Indexer cluster health is green/yellow (single node).
- Manager is running and the API responds.
- (Later phases) agents report in; ingested AWS findings appear.

Capture screenshots/notes for portfolio evidence (Phase 6).

---

## 9. Security test validation  — Planned (Phases 2–6)

Not applicable in Phase 1. Will cover detection, investigation (CloudTrail + Wazuh), and
selective automated-response scenarios once those phases are built.

---

## 10. Terraform destroy — the Lab runtime only  — ⛔ Not yet operational (nothing to destroy yet)

```bash
AWS_PROFILE=lab-admin terraform -chdir=terraform/wazuh-project destroy -var "wazuh_ami_id=<security AMI shared to Lab>"
```

Do this after every validation session (per [DECISIONS.md](DECISIONS.md) D-006).

> **Destroy the Lab runtime root only.** With D-016 the persistent artifact layer
> (`terraform/wazuh-artifacts/` — ECR + S3, Security account) is a **separate root/state**
> and is **not** destroyed here — published images and config **persist** between sessions
> by design. The Security Packer build root (`terraform/packer-build/`) also stays up
> (D-012). **Never** `terraform destroy` a Security root as part of the Lab validation
> cycle.
>
> Historical note: `terraform/wazuh-project/` used to define its own ECR repos and S3
> bucket. Those were **removed** (D-017) before this root was ever applied, so a normal
> `terraform destroy` here has nothing Lab-side ECR/S3 to worry about. If an **old** state
> file from before that removal is somehow still in play, check it for stray
> `aws_ecr_repository.*` / `aws_s3_bucket.wazuh_artifacts` entries before destroying and
> remove them from state / the account deliberately rather than relying on this destroy.

The real artifact bucket and ECR repos live in **Security**
(`terraform/wazuh-artifacts/`) and are never touched by this destroy.

---

## 11. Verify cleanup + cost

After destroy, confirm nothing from the **Lab Wazuh runtime** is left running (run as
`lab-admin` / `lab`). The persistent Security infrastructure
(`tag:Purpose = packer-build` / `wazuh-artifacts`) is *expected* to remain and lives in a
different account entirely:

```bash
# Wazuh runtime VPC id (Name tag distinguishes it from the build VPC)
VPC_ID=$(aws ec2 describe-vpcs --region us-east-2 \
  --filters 'Name=tag:Name,Values=cloud-secops-lab-vpc' \
  --query 'Vpcs[].VpcId' --output text)

aws ec2 describe-instances --region us-east-2 \
  --filters 'Name=tag:Name,Values=cloud-secops-lab-wazuh' 'Name=instance-state-name,Values=pending,running,stopping,stopped' \
  --query 'Reservations[].Instances[].[InstanceId,State.Name]' --output text

aws ec2 describe-vpc-endpoints --region us-east-2 \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'VpcEndpoints[].VpcEndpointId' --output text

# only meaningful if VPC_ID is non-empty; the project never creates a NAT GW (D-002)
[ -n "$VPC_ID" ] && aws ec2 describe-nat-gateways --region us-east-2 \
  --filter "Name=vpc-id,Values=$VPC_ID" \
  --query 'NatGateways[].NatGatewayId' --output text
```

Cost watch items while the **Lab** runtime is deployed: the **interface VPC endpoints** and
the **Wazuh EC2 instance** carry recurring hourly (and, for endpoints, data-processing)
cost. `terraform destroy` the runtime root after each session.

The **Security and Lab-identity** roots carry **no hourly cost**: `terraform/packer-build/`
is VPC / subnet / IGW / route table / SG / IAM only; `terraform/wazuh-artifacts/` is ECR
repos + an S3 bucket (storage only); `terraform/wazuh-runtime-identity/` is IAM only.
Published ECR images and S3 objects incur storage cost and **persist by design** (D-016).
Tear any of them down only with a deliberate `terraform -chdir=terraform/<root> destroy` in
the owning account.

---

## Quick reference

| What | Where / value |
| --- | --- |
| Terraform root — Packer build network (persistent, **Security**, D-012/D-014) | [terraform/packer-build/](../terraform/packer-build/) — `security-admin` to apply — **applied, operator-reported** |
| Terraform root — Lab runtime IAM identity (persistent, **Lab**, D-018) | [terraform/wazuh-runtime-identity/](../terraform/wazuh-runtime-identity/) — `lab-admin` to apply — **not applied**; apply **before** `wazuh-artifacts` |
| Terraform root — ECR + S3 artifact layer + cross-account policies (persistent, **Security**, D-016/D-018) | [terraform/wazuh-artifacts/](../terraform/wazuh-artifacts/) — `security-admin` to apply — **not applied**; requires `lab_runtime_role_arn` (from the identity root) |
| Terraform root — Wazuh runtime (disposable, **Lab**, D-006/D-014/D-017/D-019) | [terraform/wazuh-project/](../terraform/wazuh-project/) — `lab-admin` to apply — **not applied**; owns none of ECR/S3/IAM, requires `wazuh_runtime_instance_profile_name` / `wazuh_ecr_registry` / `wazuh_artifact_bucket_name` |
| Packer build (golden AMI, **Security**; shared to Lab per D-015) | [packer/](../packer/) — `security` profile; `PKR_VAR_packer_execution_role_arn` + `PKR_VAR_lab_account_id` required — **built + shared, operator-reported** |
| Runtime bootstrap (user-data) | [terraform/wazuh-project/scripts/install-wazuh.sh.tftpl](../terraform/wazuh-project/scripts/install-wazuh.sh.tftpl) — ECR registry now comes from `${ecr_registry}` (Terraform), not `aws sts get-caller-identity` (D-017) |
| Region | `us-east-2` (all roots) |
| Runtime VPC CIDR | `10.0.0.0/16` · subnet `10.0.1.0/24` (Lab) · build VPC `10.10.0.0/24` (Security) |
| Artifact bucket | `cloud-secops-lab-artifacts-<security_account_id>` (from `wazuh-artifacts` output `artifact_bucket_name`) |
| ECR registry hostname | `<security_account_id>.dkr.ecr.us-east-2.amazonaws.com` (from `wazuh-artifacts` output `ecr_registry`) |
| Cross-account grant | `wazuh-artifacts` `var.lab_runtime_role_arn` (required) — single apply, see section M steps 6–7 |
| Wazuh version | **4.14.7** (D-009) |
| Migration | section **M** above |
| Hard blockers / gaps / open decisions | [CURRENT_STATE.md](CURRENT_STATE.md) |
