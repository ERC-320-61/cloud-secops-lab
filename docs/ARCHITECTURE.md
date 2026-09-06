# CloudGuard — Architecture

> Distinguishes **Current** (implementation proves it exists), **Partial** (scaffolding exists,
> capability incomplete/unvalidated), **Planned** (accepted direction, not implemented), and
> **Deferred** (intentionally excluded from the current phase).
>
> Diagrams that show planned components label them explicitly. Do not read a planned box as
> existing infrastructure.

---

## 1. Current architecture (Phase 1 foundation)

**Scope:** a single AWS account, region `us-east-2`, one Terraform root module
([terraform/wazuh-project/](../terraform/wazuh-project/)) and one Packer build
([packer/](../packer/)).

### 1.1 Component status

| Component | State | Evidence |
| --- | --- | --- |
| AWS account model | **Current: single account** | one `provider "aws"` in [providers.tf](../terraform/wazuh-project/providers.tf); no provider aliases / `assume_role` |
| Region `us-east-2` | **Current** | `var.aws_region` default in [variables.tf](../terraform/wazuh-project/variables.tf); Packer default in [variables.pkr.hcl](../packer/variables.pkr.hcl) |
| VPC `10.0.0.0/16` (DNS support + hostnames) | **Current** | `aws_vpc.secops_lab_vpc` in [networking.tf](../terraform/wazuh-project/networking.tf) |
| One private subnet `10.0.1.0/24` (`us-east-2a`) | **Current** | `aws_subnet.private_1` in [networking.tf](../terraform/wazuh-project/networking.tf) |
| Private route table + association | **Current** | `aws_route_table.private_1_rt`, `aws_route_table_association.private_1` |
| No Internet Gateway | **Current (by design)** | no `aws_internet_gateway` anywhere |
| No NAT Gateway | **Current (by design)** | no `aws_nat_gateway` anywhere — see [DECISIONS.md](DECISIONS.md) D-002 |
| S3 gateway VPC endpoint (on the private route table) | **Current** | `aws_vpc_endpoint.s3_gateway` in [endpoints.tf](../terraform/wazuh-project/endpoints.tf) |
| Interface endpoints: `ssm`, `ssmmessages`, `ec2messages`, `ecr.api`, `ecr.dkr` | **Current** | `aws_vpc_endpoint.interface_endpoints` (`for_each` over `local.interface_services`) |
| Endpoint security group (443 from `subnet_cidr` only) | **Current** | `aws_security_group.vpc_endpoints` in [endpoints.tf](../terraform/wazuh-project/endpoints.tf) |
| EC2 IAM role + instance profile | **Current** | `aws_iam_role.wazuh_ec2`, `aws_iam_instance_profile.wazuh_ec2` in [roles.tf](../terraform/wazuh-project/roles.tf) |
| `AmazonSSMManagedInstanceCore` attached | **Current** | `aws_iam_role_policy_attachment.wazuh_ssm` |
| Scoped ECR pull policy (auth `*`; pull scoped to 3 repo ARNs) | **Current** | `aws_iam_role_policy.wazuh_ecr_pull` |
| Scoped S3 read policy (`wazuh/*` prefix of the artifact bucket) | **Current** | `aws_iam_role_policy.wazuh_s3_config_read` |
| 3 private ECR repos, `IMMUTABLE`, scan-on-push | **Partial** | [ecr.tf](../terraform/wazuh-project/ecr.tf) — repos created but **no workflow publishes images** |
| S3 artifact bucket (`...-artifacts-<account_id>`, public access blocked, SSE-S3 AES256) | **Partial** | [storage.tf](../terraform/wazuh-project/storage.tf) — bucket created but **empty**; no versioning, no bucket policy |
| Wazuh EC2 instance (`c5a.xlarge`, private subnet, instance profile, templated user-data) | **Partial** | [ec2.tf](../terraform/wazuh-project/ec2.tf) — no security group, no `root_block_device`, no `metadata_options` (IMDSv2), depends on `var.wazuh_ami_id` (no default) |
| Packer Ubuntu 24.04 AMI (`cloud-secops-wazuh-{{timestamp}}`, `c5a.xlarge` builder) | **Partial** | [wazuh-ami.pkr.hcl](../packer/wazuh-ami.pkr.hcl) — provisioner script holds runtime logic, not bake-time setup |
| EC2 user-data bootstrap (`aws s3 sync` config, ECR login, `docker compose pull`/`up`) | **Partial** | [scripts/install-wazuh.sh.tftpl](../terraform/wazuh-project/scripts/install-wazuh.sh.tftpl) — depends on ECR/S3 content that does not exist |
| Wazuh Compose / configuration artifact set (checked in) | **Not present** | no `docker-compose.yml`, `generate-indexer-certs.yml`, or `ossec.conf`/manager config in the repo |
| Terraform outputs | **Not present** | [outputs.tf](../terraform/wazuh-project/outputs.tf) is an empty placeholder; [main.tf](../terraform/wazuh-project/main.tf) also empty |
| Remote state backend | **Not present** | no `backend` block; local state (git-ignored) |
| `terraform apply` / Packer build ever run and validated | **No evidence** | nothing in git history or working tree indicates a successful deploy |

### 1.2 Current foundation diagram

```mermaid
flowchart TB
    Analyst["Analyst workstation<br/>aws ssm start-session"]

    subgraph ACC["AWS account (single) - us-east-2"]
        SSM["AWS Systems Manager<br/>Session Manager / port forwarding<br/>(Current)"]

        subgraph VPC["VPC 10.0.0.0/16 (Current)"]
            RT["Private route table<br/>no IGW, no NAT (Current)"]
            S3E["S3 gateway endpoint (Current)"]
            IE["Interface endpoints (Current)<br/>ssm, ssmmessages, ec2messages<br/>ecr.api, ecr.dkr"]

            subgraph SUB["Private subnet 10.0.1.0/24 (Current)"]
                EC2["Wazuh EC2 - c5a.xlarge (Partial)<br/>instance profile: SSM + ECR pull + S3 read<br/>user-data: install-wazuh.sh.tftpl<br/>no SG / no root-vol / no IMDSv2 enforcement"]
            end
        end

        ECR["ECR repos (Partial - empty)<br/>wazuh-manager / wazuh-indexer / wazuh-dashboard"]
        S3B["S3 artifact bucket (Partial - empty)<br/>cloud-secops-lab-artifacts-ACCOUNT"]
    end

    Analyst --> SSM --> EC2
    EC2 -->|"pull images"| IE --> ECR
    EC2 -->|"sync wazuh/ config"| S3E --> S3B
    EC2 -. "AMI from Packer (Partial / unvalidated)" .-> PACKER["Packer AMI build"]
```

### 1.3 Known-incomplete parts of the current Wazuh path

[CURRENT_STATE.md](CURRENT_STATE.md) is canonical for the blocker/gap model. Summary:

**Hard deployment blockers** (the deployment cannot succeed until these are resolved):

| ID | Gap | Effect |
| --- | --- | --- |
| B1 | [packer/scripts/install-wazuh-base.sh](../packer/scripts/install-wazuh-base.sh) is byte-identical to the runtime user-data template and contains startup logic, not bake-time setup | No validated AMI with Docker Engine, the Docker Compose plugin, or `vm.max_map_count=262144`; user-data then fails |
| B2 | No working workflow publishes Wazuh images into the 3 ECR repos | `docker compose pull` from the private registry fails |
| B3 | No complete Wazuh Compose/config artifact set in the repo, and no workflow publishes it to `s3://<bucket>/wazuh/` | `aws s3 sync` retrieves nothing; the stack has no definition to run |

**Phase 1 completion / hardening gaps** (needed to *finish and validate* Phase 1, not to get a first boot):

| Gap | Effect |
| --- | --- |
| No validated AMI produced by the repaired Packer workflow (feeds `var.wazuh_ami_id`) | `var.wazuh_ami_id` taking an explicit value is acceptable; the missing capability is a *trusted* AMI to put there |
| EC2 has no dedicated security group | Agent/dashboard traffic rules undefined |
| EC2 has no explicit `root_block_device` | Root volume defaults to the AMI size; may be undersized for the indexer |
| EC2 has no `metadata_options` | IMDSv2 not enforced |
| [outputs.tf](../terraform/wazuh-project/outputs.tf) empty | No machine-readable instance ID / bucket name for the SSM access runbook |

Historical note: an earlier design used `t3.large` with an explicit ~50 GB EBS root volume.
Current Terraform uses `c5a.xlarge` and **no** explicit root-volume block (AMI default size
applies). Root-volume sizing is an open Phase 1 completion item.

---

## 2. Target architecture

Everything in this section is **Planned** unless a box is explicitly marked otherwise.

### 2.1 Target account model

> **Target placement.** The boxes below describe where components are *intended* to live.
> The current Phase 1 implementation (VPC, endpoints, IAM, ECR, S3, EC2) runs in a
> **single-account environment** — see [DECISIONS.md](DECISIONS.md) D-007. Nothing has been
> deployed into a dedicated Security or Lab account yet.

```mermaid
flowchart TB
    subgraph MGMT["Management account (Planned)"]
        ORG["AWS Organizations<br/>account + guardrail management"]
    end

    subgraph SEC["Security account (target placement)"]
        WZ["Wazuh stack (Planned placement)<br/>Phase 1 code exists today in a single account"]
        NATIVE["CloudTrail, Security Hub, GuardDuty,<br/>selected Config + CloudWatch (Planned)"]
        PIPE["EventBridge, Firehose, SQS,<br/>Step Functions, Lambda, SNS (Planned)"]
        LOG["Central security / logging storage (Planned)"]
        NET["Private security VPC / networking (Planned placement)<br/>Phase 1 VPC exists today in a single account"]
    end

    subgraph LAB["Lab account (Planned)"]
        WIN["Windows test host(s)"]
        LIN["Linux test host(s)"]
        AG["Wazuh agents + security test scenarios"]
    end

    ORG --> SEC
    ORG --> LAB
    AG -->|"agent telemetry"| WZ
    NATIVE --> PIPE
    PIPE --> WZ
    NATIVE --> LOG
```

Logical responsibilities:

| Account | Responsibility |
| --- | --- |
| Management | Organization structure, account provisioning, org-level guardrails. |
| Security | All centralized security tooling: Wazuh, AWS-native detection, ingestion pipeline, response workflows, central logging, security VPC. |
| Lab | Disposable workloads that generate telemetry and findings; Wazuh agents; attack/test scenarios. |

### 2.2 Target findings ingestion

```mermaid
flowchart LR
    SH["Security Hub<br/>(Planned - authoritative)"] --> EB["EventBridge rule<br/>(Planned)"]
    EB --> FH["Firehose delivery stream<br/>(Planned)"]
    FH --> S3F["S3 findings bucket<br/>(Planned)"]
    S3F --> SQSq["SQS queue<br/>(Planned)"]
    SQSq --> WZ["Wazuh ingestion<br/>(Planned integration)<br/>analyst investigation surface"]
```

Purpose: give analysts AWS findings inside Wazuh **without** making Wazuh authoritative for
those findings. Security Hub remains the system of record — see [DECISIONS.md](DECISIONS.md)
D-003.

### 2.3 Target selective automated response

```mermaid
flowchart LR
    SRC["Security Hub / EventBridge<br/>(Planned)"] --> QUAL["Finding qualification / filter<br/>(Planned)<br/>match a small set of actionable finding types"]
    QUAL -->|"selected findings only"| SFN["Step Functions workflow<br/>(Planned)"]
    SFN --> LAM["Lambda remediation actions<br/>(Planned)"]
    SFN --> SNSn["SNS notifications / approvals<br/>(Planned)"]
    QUAL -->|"everything else"| NOOP["No automated action<br/>(analyst handles in Wazuh / Security Hub)"]
```

Response is **selective** by design — see [DECISIONS.md](DECISIONS.md) D-004.

### 2.4 Target end-state (conceptual)

> All boxes **Planned** unless noted. Account placement is target placement — today's
> Phase 1 resources are single-account (D-007).
>
> Note the finding paths: **CloudTrail feeds central logging / investigation**, not Security
> Hub directly. **GuardDuty** (and other supported finding integrations) feed Security Hub.
> Security Hub stays authoritative for AWS-native findings (D-003) and is the source for both
> the Wazuh ingestion pipeline and the selective-response pipeline.

```mermaid
flowchart TB
    subgraph LABX["Lab account (Planned placement)"]
        HOSTS["Windows + Linux hosts<br/>Wazuh agents"]
    end
    subgraph SECX["Security account (target placement)"]
        CT["CloudTrail (Planned)"]
        GD["GuardDuty (Planned)"]
        INTEG["Other supported finding<br/>integrations (Planned)"]
        SHX["Security Hub (Planned)<br/>authoritative for AWS-native findings"]
        INGEST["Ingestion pipeline (Planned)<br/>EventBridge -> Firehose -> S3 -> SQS"]
        RESP["Selective response pipeline (Planned)<br/>EventBridge -> qualify -> Step Functions -> Lambda / SNS"]
        WZX["Wazuh platform (Planned placement)<br/>Phase 1: private networking only, single account"]
        LOGX["Central logging / investigation storage (Planned)"]
    end

    HOSTS -->|"agent telemetry"| WZX
    CT --> LOGX
    GD --> SHX
    INTEG --> SHX
    SHX --> INGEST --> WZX
    SHX --> RESP
    RESP -->|"action outcomes / notifications"| WZX
    LOGX -.->|"investigation queries"| WZX
```

---

## 3. Cross-cutting architectural decisions

See [DECISIONS.md](DECISIONS.md) for full records. Summary:

| ID | Decision | Status |
| --- | --- | --- |
| D-001 | Private administrative access via AWS Systems Manager; no public admin surface. | Accepted |
| D-002 | No NAT Gateway for the current MVP; use VPC endpoints where practical. | Accepted |
| D-003 | AWS Security Hub is authoritative for AWS-native findings; Wazuh is analyst/investigation only. | Accepted |
| D-004 | Automated response is selective, not universal. | Accepted |
| D-005 | Public Wazuh dashboard (ALB/ACM) deferred; SSM port forwarding is the access path. | Accepted |
| D-006 | Temporary environment lifecycle: deploy → test → validate → document → destroy. | Accepted |
| D-007 | Multi-account transition point — Phase 1 stays single-account; when to adopt the management/security/lab model is open. | Proposed |
| D-008 | Keep implementation minimal and maintainable; avoid unnecessary abstractions. | Accepted |
| D-009 | Wazuh delivery via private ECR + S3 config, no runtime internet dependency (implementation incomplete). | Accepted |
| D-010 | Artifact bucket encryption — SSE-S3 today; SSE-S3 vs. CMK for Phase 1 is open. | Proposed |
