# CloudGuard — Runbook

> Operational skeleton for the temporary-lab lifecycle:
> `deploy → test → validate → document → destroy`.
>
> **Reality check (2026-09-06):** the Wazuh deployment is **not end-to-end operational** and
> nothing here has been executed against AWS. Steps that cannot yet succeed are marked
> **⛔** with the blocking issue ID from [CURRENT_STATE.md](CURRENT_STATE.md). The B1 Packer
> provisioner script is fixed in code but has never been built. Update commands to real,
> tested ones as Phase 1 progresses.

All commands assume repo root `cloud-secops-lab/` and AWS credentials for the target account
already configured (`aws sts get-caller-identity` succeeds).

> **⚠️ Deployment ordering is not yet designed.** Steps 3–5 below (publish artifacts →
> publish images → `terraform apply`) are **not** a runnable sequence today: Terraform (in
> the single root module) is what *creates* the S3 artifact bucket and the ECR repositories,
> so those destinations do not exist until `terraform apply` runs — yet the EC2 user-data
> expects them populated at first boot. Resolving this ordering (and whether artifact
> infrastructure gets its own lifecycle/state) is an **open Phase 1 decision** — see
> [CURRENT_STATE.md](CURRENT_STATE.md) → *Unresolved lifecycle issues* / *Open decisions*.
> Do not treat the step numbers as a validated order until that decision is made and this
> runbook is rewritten to match.

---

## 0. Prerequisites

| Requirement | Check |
| --- | --- |
| AWS CLI v2 | `aws --version` |
| AWS Session Manager plugin | `session-manager-plugin --version` |
| Terraform `>= 1.7.0` | `terraform version` |
| Packer `>= 1.9` (Amazon plugin) | `packer version` |
| Credentials for the target AWS account (`us-east-2`) | `aws sts get-caller-identity` |
| Docker (only if publishing Wazuh images locally — blocker B2) | `docker version` |

Region is `us-east-2` (`var.aws_region`). The current Phase 1 implementation deploys into a
**single** AWS account ([DECISIONS.md](DECISIONS.md) D-007).

---

## 1. Build the Wazuh base AMI (Packer)  — ⛔ Not yet run (needs approval; B1 script fixed)

```bash
cd packer
packer init .
packer validate .
packer build .
# resulting AMI name: cloud-secops-wazuh-<timestamp>
```

**Script status:** [packer/scripts/install-wazuh-base.sh](../packer/scripts/install-wazuh-base.sh)
is now a true bake-time provisioner (B1 fixed) — base packages, Docker Engine + Compose
plugin, AWS CLI v2, persisted `vm.max_map_count=262144`, Docker enabled at boot, `ubuntu`
in the `docker` group, SSM agent verify/enable, then a verification block. It bakes **no**
Wazuh application state (see [DECISIONS.md](DECISIONS.md) D-011).

**A build has never been run.** It creates AWS resources and requires explicit approval.

- **PB-1 — builder networking + security group (unresolved).** No `vpc_id` / `subnet_id` /
  `security_group_id` is set. Packer infers a default VPC/subnet; the bake needs outbound
  Internet (Docker apt repo + AWS CLI v2 installer). Packer uses a **public IP for SSH when
  one is available**, otherwise its normal behaviour may select the **private IP** — so the
  host running `packer build` must have a working network path to whichever SSH endpoint
  Packer selects. Packer also creates a **temporary security group** for the builder by
  default; review its SSH ingress before the first build. Decide the builder network + SG
  design before building; do not add networking resources yet.
- **PB-2 — line endings (resolved in code).** Root `.gitattributes` forces `*.sh` and
  `*.tftpl` to LF regardless of `core.autocrlf`. The uploaded-script behaviour is still
  naturally exercised by the first `packer build`.
- **PB-3 — SSM agent (confirm at first build).** The script enables the agent supplied by
  the Canonical base image (`snap start --enable amazon-ssm-agent`, deb-unit fallback) and
  hard-fails if none is present (SSM is the only admin path, D-001). Confirm the snap is
  present on the first real build.

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

After destroy, confirm nothing from this project is left running. Scope every check to the
project's resources (by `Project` tag or the project VPC) — do **not** assume the account /
region otherwise contains nothing:

```bash
# project VPC id (used to scope the checks below)
VPC_ID=$(aws ec2 describe-vpcs --region us-east-2 \
  --filters 'Name=tag:Project,Values=cloud-secops-lab' \
  --query 'Vpcs[].VpcId' --output text)

aws ec2 describe-instances --region us-east-2 \
  --filters 'Name=tag:Project,Values=cloud-secops-lab' 'Name=instance-state-name,Values=pending,running,stopping,stopped' \
  --query 'Reservations[].Instances[].[InstanceId,State.Name]' --output text

aws ec2 describe-vpc-endpoints --region us-east-2 \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'VpcEndpoints[].VpcEndpointId' --output text

# only meaningful if VPC_ID is non-empty; the project never creates a NAT GW (D-002)
[ -n "$VPC_ID" ] && aws ec2 describe-nat-gateways --region us-east-2 \
  --filter "Name=vpc-id,Values=$VPC_ID" \
  --query 'NatGateways[].NatGatewayId' --output text
```

Cost watch items while deployed: the **interface VPC endpoints** and the **Wazuh EC2
instance** carry recurring hourly (and, for endpoints, data-processing) cost. The S3 gateway
endpoint, the ECR repositories (storage only), and an empty artifact bucket are negligible.
Published ECR images incur storage cost — factor that into the persistence decision above.

---

## Quick reference

| What | Where |
| --- | --- |
| Terraform module | [terraform/wazuh-project/](../terraform/wazuh-project/) |
| Packer build | [packer/](../packer/) |
| Runtime bootstrap (user-data) | [terraform/wazuh-project/scripts/install-wazuh.sh.tftpl](../terraform/wazuh-project/scripts/install-wazuh.sh.tftpl) |
| Region | `us-east-2` |
| VPC CIDR | `10.0.0.0/16` · subnet `10.0.1.0/24` |
| Artifact bucket | `cloud-secops-lab-artifacts-<account_id>` |
| Hard blockers | [CURRENT_STATE.md](CURRENT_STATE.md) — B1 fixed in code (build pending), B2–B3 open |
| Pre-build items / completion gaps / open decisions | [CURRENT_STATE.md](CURRENT_STATE.md) |
