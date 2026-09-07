# CloudGuard — Runbook

> Operational skeleton for the temporary-lab lifecycle:
> `deploy → test → validate → document → destroy`.
>
> **Reality check (2026-09-06):** the B1 Packer provisioner and the persistent build
> network (D-012) are implemented in code and **pass local `fmt`/`init`/`validate`
> (Terraform + Packer)**, but **nothing has been applied or built against AWS**. Steps that
> cannot yet succeed are marked **⛔** with the blocking issue ID from
> [CURRENT_STATE.md](CURRENT_STATE.md). Update commands to real, tested ones as Phase 1
> progresses.

All commands assume repo root `cloud-secops-lab/` and AWS credentials for the target account
already configured (`aws sts get-caller-identity` succeeds).

> **⚠️ Deployment ordering is not yet designed.** Steps 3–5 below (publish artifacts →
> publish images → `terraform apply`) are **not** a runnable sequence today: Terraform (the
> Wazuh runtime root) is what *creates* the S3 artifact bucket and the ECR repositories,
> so those destinations do not exist until `terraform apply` runs — yet the EC2 user-data
> expects them populated at first boot. Resolving this ordering (and whether artifact
> infrastructure gets its own lifecycle/state) is an **open Phase 1 decision** — see
> [CURRENT_STATE.md](CURRENT_STATE.md) → *Unresolved lifecycle issues* / *Open decisions*.
> Do not treat the step numbers as a validated order until that decision is made and this
> runbook is rewritten to match.

---

## 0. Prerequisites

| Requirement | Check | Status (operator workstation, 2026-09-06) |
| --- | --- | --- |
| AWS CLI v2 | `aws --version` | **verified — `aws-cli/2.36.37`** |
| AWS Session Manager plugin (required — Packer tunnels the builder over SSM) | `session-manager-plugin --version` | **verified — `1.2.835.0`** |
| Terraform `>= 1.7.0` | `terraform version` | **verified — `v1.16.1`** |
| Packer `>= 1.9` (Amazon plugin `github.com/hashicorp/amazon v1.8.2`) | `packer version` | **verified — installed; `packer init`/`validate` pass** |
| Credentials for the target AWS account (`us-east-2`) | `aws sts get-caller-identity` | operator-supplied at build time |
| Packer-caller least-privilege IAM policy (PB-4) — reviewed **before** build authorization; not in this repo | reviewed against the operator principal's policy | **OPEN** — required scope in [CURRENT_STATE.md](CURRENT_STATE.md) PB-4 (builder EC2 lifecycle, AMI/snapshot ops, source-AMI + VPC/subnet/SG discovery, `iam:PassRole` limited to `cloud-secops-lab-packer-build-ssm-role`, `AWS-StartSSHSession` session use + clean `TerminateSession`, `ec2:DescribeInstanceStatus`) |
| Docker (only if publishing Wazuh images locally — blocker B2) | `docker version` | not required for the AMI build |

Region is `us-east-2` (`var.aws_region`). The current Phase 1 implementation deploys into a
**single** AWS account ([DECISIONS.md](DECISIONS.md) D-007).

---

## 1. Build the Wazuh base AMI (Packer)  — ⛔ Not yet run (needs approval)

### 1a. Provision the persistent Packer build network (one-time; D-012)

```bash
terraform -chdir=terraform/packer-build init      # already run locally — selects hashicorp/aws 6.57.1
terraform -chdir=terraform/packer-build validate  # already passes locally
terraform -chdir=terraform/packer-build apply      # NOT yet run — creates the persistent VPC/subnet/IGW/route/SG/instance profile
terraform -chdir=terraform/packer-build output
```

- `fmt -check`, `init`, and `validate` were **run successfully on the operator workstation
  (2026-09-06)**; `terraform/packer-build/.terraform.lock.hcl` pins `hashicorp/aws 6.57.1`
  and is present and intended for source control with the PB-1 commit. Only `apply`
  remains, and it has **not** been run.
- This root is **persistent supporting infrastructure**. It has a **different lifecycle**
  from `terraform/wazuh-project/` — do **not** `terraform destroy` it as part of the Wazuh
  runtime deploy→test→validate→destroy cycle ([DECISIONS.md](DECISIONS.md) D-012).
- Cost: VPC, subnet, Internet Gateway, route table, security group and IAM only — **no
  hourly or data-processing charge**. Cost is incurred only by the ephemeral builder Packer
  creates during a build.
- Non-overlapping CIDR: build VPC `10.10.0.0/24` vs. Wazuh runtime `10.0.0.0/16`.

### 1b. Build the AMI

```bash
cd packer
packer init .       # already run locally — installs github.com/hashicorp/amazon v1.8.2
packer validate .   # already passes locally
packer build .      # NOT yet run — creates the ephemeral builder + AMI
# resulting AMI name: cloud-secops-wazuh-<timestamp>
```

`fmt -check`, `init`, and `validate` were **run successfully on the operator workstation
(2026-09-06)**. Only `packer build` remains, and it has **not** been run.

**How the builder is placed** ([packer/wazuh-ami.pkr.hcl](../packer/wazuh-ami.pkr.hcl)):
it finds the build VPC / subnet / security group by **deterministic tag filters** —
`tag:Project = cloud-secops-lab` + `tag:Purpose = packer-build` + a resource-specific
`tag:Name` (`cloud-secops-lab-packer-build-{vpc,subnet,sg}`). `subnet_filter` has **no**
`most_free`/`random`, so if a filter ever matched more than one resource the build
**aborts** instead of guessing. It attaches the
`cloud-secops-lab-packer-build-ssm-profile` instance profile, **explicitly** associates a
public IPv4 (egress only — the subnet does not auto-assign), reaches the builder through
**SSM Session Manager** (`ssh_interface = "session_manager"`; no inbound SSH; the SG has no
ingress), and requires **IMDSv2**.

**Bake-script status** ([packer/scripts/install-wazuh-base.sh](../packer/scripts/install-wazuh-base.sh)):
a true bake-time provisioner (B1 fixed) — base packages, Docker Engine + Compose plugin,
AWS CLI v2, persisted `vm.max_map_count=262144`, Docker enabled at boot, `ubuntu` in the
`docker` group, SSM agent enable, verification block. **No** Wazuh application state
([DECISIONS.md](DECISIONS.md) D-011).

**A build has never been run.** It creates AWS resources and requires explicit approval.
Confirm first:

- **PB-1 / D-012 (resolved; `fmt`/`init`/`validate` pass locally).** Run step 1a `apply`
  first so the tag filters resolve.
- **PB-4 (open — the only remaining pre-build blocker).** Local toolchain is **done**
  (Terraform `v1.16.1`, AWS CLI `2.36.37`, SSM plugin `1.2.835.0`, Packer — all verified).
  Still required: define and review a least-privilege **Packer-caller IAM policy** (see
  [CURRENT_STATE.md](CURRENT_STATE.md) PB-4) — builder EC2 lifecycle, AMI/snapshot ops,
  source-AMI + VPC/subnet/SG discovery, `iam:PassRole` limited to
  `cloud-secops-lab-packer-build-ssm-role`, `AWS-StartSSHSession` session use
  (`ssm:StartSession` + clean `ssm:TerminateSession`), and `ec2:DescribeInstanceStatus`.
  Not `AdministratorAccess`/`ec2:*`; not written in this repo (no designated principal).
- **PB-2 — line endings (resolved in code).** `.gitattributes` forces `*.sh` / `*.tftpl` to
  LF; still naturally exercised by the first build.
- **PB-3 — SSM agent (confirm at first build).** The bake script enables the agent supplied
  by the Canonical base image (`snap start --enable amazon-ssm-agent`, deb-unit fallback)
  and hard-fails if none is present (D-001). Confirm the snap is present on the first build.

---

## 2. Validate the AMI  — ⛔ Not yet operational (depends on step 1)

Intended checks once step 1 is fixed:

- New AMI visible: `aws ec2 describe-images --owners self --filters 'Name=name,Values=cloud-secops-wazuh-*' --region us-east-2`
- Launch a throwaway instance from it and confirm: `docker --version`, `docker compose version`,
  `sysctl vm.max_map_count` → `262144`, EC2 user in the `docker` group.
- Terminate the throwaway instance.

Record the AMI id for step 5.

---

## Steps 3–5 — sequence pending Phase 1 bootstrap/lifecycle decision

> The three steps below describe *what* must happen, not a validated *order*. The dependency
> to resolve first: **ECR repositories and the S3 artifact bucket must exist before they can
> be populated, but the EC2 instance must not first-boot until the artifacts and images are
> available.** Terraform currently creates the destinations and the instance in the same
> apply. Phase 1 must design a clean flow
> (`prereq infra → publish artifacts/images → create host`) — the mechanism is an open
> decision ([CURRENT_STATE.md](CURRENT_STATE.md)). This task does **not** choose one.

### 3. Publish Wazuh application artifacts to S3  — ⛔ Not yet operational (B3)

The runtime bootstrap expects a Wazuh stack definition at `s3://<artifact-bucket>/wazuh/`
(Compose file, `generate-indexer-certs.yml`, manager/indexer/dashboard config).

**Blocked:** the repository contains no complete Wazuh artifact set and no publishing
workflow. Phase 1 must add a checked-in `wazuh/` source at a deliberately chosen version plus
a publish path — consistent with the ordering decision above.

Artifact bucket name pattern (from [storage.tf](../terraform/wazuh-project/storage.tf)):
`cloud-secops-lab-artifacts-<aws_account_id>` (created by Terraform — see the ordering note).

### 4. Publish Wazuh images to private ECR  — ⛔ Not yet operational (B2)

The three repository **definitions** exist ([ecr.tf](../terraform/wazuh-project/ecr.tf)):

```
cloud-secops-lab/wazuh-manager
cloud-secops-lab/wazuh-indexer
cloud-secops-lab/wazuh-dashboard
```

**Blocked:** no working workflow publishes images into them. Phase 1 must add a mirror
workflow (pull upstream Wazuh images at the chosen version → tag → push). The repos are
`IMMUTABLE`, so a tag cannot be overwritten once pushed. The repos are created by Terraform —
see the ordering note.

### 5. Terraform init / plan / apply  — ⛔ Not yet operational (depends on 1–4 + the ordering decision)

```bash
cd terraform/wazuh-project
terraform init
terraform plan  -var "wazuh_ami_id=ami-XXXXXXXXXXXXXXXXX"
terraform apply -var "wazuh_ami_id=ami-XXXXXXXXXXXXXXXXX"
```

Notes:

- `var.wazuh_ami_id` has **no default** — this is acceptable by design. Supply the AMI id
  from step 2 via `-var`, a git-ignored `terraform.tfvars`, or `TF_VAR_wazuh_ami_id`. The
  real precondition is that the id points at a **validated** AMI from the repaired Packer
  workflow.
- State is **local** (no remote backend) — do not delete `.terraform/` or the state file
  between plan and destroy.
- Even once B1–B3 are fixed, the instance still has **no dedicated security group, no
  explicit root volume, and no IMDSv2 enforcement**, and there are **no Terraform outputs**
  (Phase 1 completion gaps in [CURRENT_STATE.md](CURRENT_STATE.md)). Expect to look resource
  attributes up via the console / `aws` CLI until outputs are added.

---

## 6. Validate EC2 + SSM connectivity  — ⛔ Not yet operational (depends on 5)

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

## 10. Terraform destroy  — ⛔ Not yet operational (nothing to destroy yet)

```bash
cd terraform/wazuh-project
terraform destroy -var "wazuh_ami_id=ami-XXXXXXXXXXXXXXXXX"
```

Do this after every validation session (per [DECISIONS.md](DECISIONS.md) D-006).

> **Persistence boundary is undecided.** The ECR repositories and the S3 artifact bucket
> currently live in the **same Terraform root/state** as the ephemeral VPC/EC2, so a plain
> `terraform destroy` removes them **and any images/artifacts in them** too. You cannot both
> "keep published ECR images between sessions" and rely on the current single-root
> `terraform destroy` to clean everything up — those goals conflict until Phase 1 defines
> what is durable vs. disposable (see [CURRENT_STATE.md](CURRENT_STATE.md) → Open decisions
> #1/#2). Do not assume either behaviour until that decision is recorded here.

The S3 artifact bucket must be empty for destroy to succeed (no `force_destroy` set) — remove
objects first if it was populated:

```bash
aws s3 rm "s3://cloud-secops-lab-artifacts-<account_id>/" --recursive
```

---

## 11. Verify cleanup + cost

After destroy, confirm nothing from the **Wazuh runtime** is left running. Both Terraform
roots tag `Project = cloud-secops-lab`, so scope runtime checks to the runtime VPC by its
`Name` tag (the persistent build network is `tag:Purpose = packer-build` and is *expected*
to remain):

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

Cost watch items while the runtime is deployed: the **interface VPC endpoints** and the
**Wazuh EC2 instance** carry recurring hourly (and, for endpoints, data-processing) cost.
The S3 gateway endpoint, the ECR repositories (storage only), and an empty artifact bucket
are negligible. Published ECR images incur storage cost.

The **persistent build network** (`terraform/packer-build/`) is expected to stay up between
builds and carries **no hourly cost** — VPC, subnet, IGW, route table, SG and IAM only. If
you want it gone entirely, `terraform -chdir=terraform/packer-build destroy` it explicitly;
it is never removed by the runtime lifecycle.

---

## Quick reference

| What | Where |
| --- | --- |
| Terraform root — Wazuh runtime (disposable) | [terraform/wazuh-project/](../terraform/wazuh-project/) |
| Terraform root — Packer build network (persistent, D-012) | [terraform/packer-build/](../terraform/packer-build/) |
| Packer build | [packer/](../packer/) |
| Runtime bootstrap (user-data) | [terraform/wazuh-project/scripts/install-wazuh.sh.tftpl](../terraform/wazuh-project/scripts/install-wazuh.sh.tftpl) |
| Region | `us-east-2` |
| VPC CIDR | `10.0.0.0/16` · subnet `10.0.1.0/24` |
| Artifact bucket | `cloud-secops-lab-artifacts-<account_id>` |
| Hard blockers | [CURRENT_STATE.md](CURRENT_STATE.md) — B1 fixed in code (build pending), B2–B3 open |
| Pre-build items / completion gaps / open decisions | [CURRENT_STATE.md](CURRENT_STATE.md) |
