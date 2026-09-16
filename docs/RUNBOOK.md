# CloudGuard — Runbook

> Operational skeleton for the temporary-lab lifecycle:
> `deploy → test → validate → document → destroy`.
>
> **Reality check (2026-09-08):** the Packer prerequisite phase is **complete** — but it was
> built and validated in the **Management** account (`ami-0b1bf8942dfc0daf1`, `us-east-2` —
> historical evidence, not a config constant). CloudGuard has adopted the
> Management / Security / Lab model ([DECISIONS.md](DECISIONS.md) D-014). **Nothing has been
> applied in the Security or Lab accounts.** The immediate work is the **Migration**
> (section M below): re-apply the Packer build root in Security, build a Security-owned AMI,
> share it to Lab, retire the Management copy, apply the persistent artifact root in
> Security. Sections 3–11 (the **runtime** Wazuh deployment in Lab) are still not runnable —
> B2/B3, cross-account ECR/S3 policies, and the publication-ordering decision remain open.
> Those steps stay marked **⛔**.

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

## M. Migration to the three-account model (D-014)  — ⛔ Not yet run

> One-time. Nothing below has happened. Do not claim otherwise. Each numbered step names the
> profile it runs as. Steps are ordered; do not skip ahead.

**Current reality:** the validated AMI `ami-0b1bf8942dfc0daf1` and the persistent Packer
build infrastructure exist **only in the Management account**. The Security and Lab accounts
and their SSO permission sets exist; **no CloudGuard infrastructure has been applied there.**

```bash
# 1. Apply the persistent Packer build infrastructure in SECURITY.
aws sso login --profile security-admin
terraform -chdir=terraform/packer-build fmt -check
terraform -chdir=terraform/packer-build init          # hashicorp/aws 6.57.1 (committed lock file)
terraform -chdir=terraform/packer-build validate
AWS_PROFILE=security-admin terraform -chdir=terraform/packer-build apply
AWS_PROFILE=security-admin terraform -chdir=terraform/packer-build output

# 2. Build + validate a NEW Security-owned base AMI (section 1). Runs as `security`,
#    Packer assumes the execution role. Requires the Lab account id for the share.
aws sso login --profile security
cd packer
export PKR_VAR_packer_execution_role_arn="$(AWS_PROFILE=security-admin terraform -chdir=../terraform/packer-build output -raw packer_execution_role_arn)"
export PKR_VAR_lab_account_id=<lab account id>          # non-secret; not committed to source
packer fmt -check . && packer init . && packer validate .
AWS_PROFILE=security packer build .
cd ..
#    -> record the new AMI id; smoke-test it (section 2).

# 3. Confirm the AMI is shared to Lab (launch permission only, not public):
AWS_PROFILE=security aws ec2 describe-image-attribute --region us-east-2 \
  --image-id <new ami id> --attribute launchPermission

# 4. From the Lab account, confirm Lab can see / launch the shared AMI:
AWS_PROFILE=lab-admin aws ec2 describe-images --region us-east-2 --image-ids <new ami id>

# 5. ONLY after step 4 passes — destroy the LEGACY Packer build infra in MANAGEMENT:
aws sso login --profile cloudguard-admin
AWS_PROFILE=cloudguard-admin terraform -chdir=terraform/packer-build destroy
#    (the Management-account AMI ami-0b1bf8942dfc0daf1 can be deregistered separately once
#     the Security AMI is proven)

# 6. Apply the persistent artifact layer in SECURITY (D-016):
aws sso login --profile security-admin
terraform -chdir=terraform/wazuh-artifacts fmt -check
terraform -chdir=terraform/wazuh-artifacts init
terraform -chdir=terraform/wazuh-artifacts validate
AWS_PROFILE=security-admin terraform -chdir=terraform/wazuh-artifacts apply
AWS_PROFILE=security-admin terraform -chdir=terraform/wazuh-artifacts output

# 7. Continue B3 (Wazuh 4.14.7 artifact set + S3 publish) and B2 (ECR image mirror) — sections 3/4.
# 8. Deploy the disposable Wazuh runtime in LAB — section 5.
```

> **Terraform state.** State is local per root. Keep each root's `.terraform/` + state file
> with the operator who runs it. A remote backend is an open decision (now 3 roots / 2
> accounts) — see [CURRENT_STATE.md](CURRENT_STATE.md).

---

## 1. Build the Wazuh base AMI (Packer)  — ✅ Proven (in Management 2026-09-07); re-home to Security

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

## 2. Validate the AMI (smoke test)  — ✅ Done once in Management; repeat for the Security AMI

The Management-account AMI `ami-0b1bf8942dfc0daf1` was smoke-tested via a manual EC2 instance
reached over Session Manager and **validated** on 2026-09-07. **Repeat this against the new
Security-owned AMI** (migration section M step 2):

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

## Steps 3–5 — runtime deployment (Lab), pending the migration + B2/B3

> Order to resolve first (Open decision #1): **the Security artifact root
> (`terraform/wazuh-artifacts/`) must be applied and the ECR repos + `s3://<bucket>/wazuh/`
> populated before the Lab runtime first-boots.** With D-016 the destinations are now a
> separate, earlier apply — but the population steps (B2/B3) and the cross-account access
> policies are still missing. Do not treat steps 3–5 as a validated order yet.

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

**Cross-account:** the Lab runtime instance role needs an S3 bucket policy on the
Security-owned bucket granting `s3:GetObject` on `wazuh/*` (and `s3:ListBucket` with that
prefix). Not implemented — next work.

### 4. Publish Wazuh images to private ECR  — ⛔ Not yet operational (B2)

The three repository **definitions** exist ([ecr.tf](../terraform/wazuh-project/ecr.tf)):

```
cloud-secops-lab/wazuh-manager
cloud-secops-lab/wazuh-indexer
cloud-secops-lab/wazuh-dashboard
```

**Blocked:** no working workflow publishes images into them. Add a mirror workflow (pull
upstream Wazuh **4.14.7** images → tag → push to the **Security-owned** repos from section M
step 6). The repos are `IMMUTABLE`, so a tag cannot be overwritten once pushed.

**Cross-account:** the Lab runtime instance role needs an ECR repository policy on each
Security-owned repo granting `ecr:BatchGetImage` / `ecr:GetDownloadUrlForLayer` /
`ecr:BatchCheckLayerAvailability` (auth token is account-local). Not implemented — next work.

### 5. Terraform init / plan / apply — the Lab runtime  — ⛔ Not yet operational (depends on M + 3 + 4)

```bash
aws sso login --profile lab-admin
terraform -chdir=terraform/wazuh-project init
terraform -chdir=terraform/wazuh-project plan  -var "wazuh_ami_id=<security AMI shared to Lab>"
AWS_PROFILE=lab-admin terraform -chdir=terraform/wazuh-project apply -var "wazuh_ami_id=<security AMI shared to Lab>"
```

Notes:

- Runs in the **Lab** account (`lab-admin`, or a dedicated runtime execution role later).
- `var.wazuh_ami_id` has **no default** by design. Supply the **Security-owned AMI id that
  was shared to Lab** (section M steps 2–4) via `-var`, a git-ignored `terraform.tfvars`, or
  `TF_VAR_wazuh_ami_id`.
- State is **local** (no remote backend) — do not delete `.terraform/` or the state file
  between plan and destroy.
- **Known gaps** before this is a clean run: the legacy `ecr.tf` / `storage.tf` are still in
  this root (superseded by `terraform/wazuh-artifacts/`, removal blocked by `stash@{0}`) —
  applying this root as-is would re-create ECR repos / a bucket **in Lab**, which is wrong;
  resolve the stash and remove them first. Also: no dedicated security group, no explicit
  root volume, no IMDSv2 enforcement, no outputs; and `install-wazuh.sh.tftpl` derives the
  ECR registry host from the Lab account id, not the Security one. See
  [CURRENT_STATE.md](CURRENT_STATE.md).

---

## 6. Validate EC2 + SSM connectivity  — ⛔ Not yet operational (depends on 5)

All commands here run against the **Lab** account (`AWS_PROFILE=lab-admin` or `lab`).

```bash
# find the instance
aws ec2 describe-instances --region us-east-2 \
  --filters 'Name=tag:Project,Values=cloud-secops-lab' 'Name=instance-state-name,Values=running' \
  --query 'Reservations[].Instances[].InstanceId' --output text

# confirm it registered with SSM
aws ssm describe-instance-information --region us-east-2 \
  --query 'InstanceInformationList[].InstanceId' --output text

# open a shell
aws ssm start-session --region us-east-2 --target i-XXXXXXXXXXXXXXXXX
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
> Caveat during migration: the superseded `ecr.tf` / `storage.tf` are still in
> `terraform/wazuh-project/` (stash-blocked removal). If this root was applied before they
> were removed, its state holds an ECR/bucket in **Lab** — remove those from state / the
> account deliberately, don't rely on this destroy.

If the runtime ever created objects in the (Lab-side, legacy) bucket, empty it first
(`aws s3 rm ... --recursive`) — the real artifact bucket in Security is managed separately
and is not touched by this destroy.

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

The **Security** roots carry **no hourly cost**: `terraform/packer-build/` is VPC / subnet /
IGW / route table / SG / IAM only; `terraform/wazuh-artifacts/` is ECR repos + an S3 bucket
(storage only). Published ECR images and S3 objects incur storage cost and **persist by
design** (D-016). Tear either down only with a deliberate
`terraform -chdir=terraform/<root> destroy` in the Security account.

---

## Quick reference

| What | Where / value |
| --- | --- |
| Terraform root — Packer build network (persistent, **Security**, D-012/D-014) | [terraform/packer-build/](../terraform/packer-build/) — `security-admin` to apply |
| Terraform root — ECR + S3 artifact layer (persistent, **Security**, D-016) | [terraform/wazuh-artifacts/](../terraform/wazuh-artifacts/) — `security-admin` to apply |
| Terraform root — Wazuh runtime (disposable, **Lab**, D-006/D-014) | [terraform/wazuh-project/](../terraform/wazuh-project/) — `lab-admin` to apply |
| Packer build (golden AMI, **Security**; shared to Lab per D-015) | [packer/](../packer/) — `security` profile; `PKR_VAR_packer_execution_role_arn` + `PKR_VAR_lab_account_id` required |
| Runtime bootstrap (user-data) | [terraform/wazuh-project/scripts/install-wazuh.sh.tftpl](../terraform/wazuh-project/scripts/install-wazuh.sh.tftpl) |
| Region | `us-east-2` (all roots) |
| Runtime VPC CIDR | `10.0.0.0/16` · subnet `10.0.1.0/24` (Lab) · build VPC `10.10.0.0/24` (Security) |
| Artifact bucket | `cloud-secops-lab-artifacts-<security_account_id>` (from `wazuh-artifacts` output) |
| Wazuh version | **4.14.7** (D-009) |
| Migration | section **M** above |
| Hard blockers / gaps / open decisions | [CURRENT_STATE.md](CURRENT_STATE.md) |
