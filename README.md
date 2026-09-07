# CloudGuard (`cloud-secops-lab`)

A **reusable AWS cloud security operations lab** for detection engineering, investigation,
and selective automated response — built with Infrastructure as Code so an AWS environment
can be **deployed, tested, validated, documented, and destroyed** on demand.

The **repository is the permanent artifact**. Deployed AWS environments are **temporary and
cost-controlled** by design.

> **Status:** Phase 1 — Private Wazuh Platform — **IN PROGRESS**.
> The Packer prerequisite phase is **complete** and a **validated base AMI** exists; the
> persistent Packer build infrastructure is applied in AWS. The runtime Wazuh environment
> (VPC `10.0.0.0/16`, image/artifact publishing, `terraform apply`) is **not yet deployed** —
> that is the remaining Phase 1 work. See [docs/CURRENT_STATE.md](docs/CURRENT_STATE.md).

---

## What exists today vs. what is planned

| Layer | State | Notes |
| --- | --- | --- |
| Private VPC, single private subnet, private route table | **Current** | `us-east-2`, `10.0.0.0/16`, no IGW, no NAT |
| VPC endpoints: S3 gateway + `ssm`/`ssmmessages`/`ec2messages`/`ecr.api`/`ecr.dkr` | **Current** | Endpoint security group allows 443 from the subnet only |
| EC2 IAM role / instance profile (SSM core + scoped ECR pull + scoped S3 read) | **Current** | `roles.tf` |
| 3 private immutable ECR repos (manager / indexer / dashboard) | **Partial** | Created empty; nothing publishes images |
| Private S3 artifact bucket (SSE-S3, public access blocked) | **Partial** | Created empty; no Wazuh artifact set checked in / published |
| Wazuh EC2 Terraform definition + templated user-data | **Partial** | No security group, no root-volume sizing, no IMDSv2 enforcement, no outputs; **runtime not applied** |
| Persistent Packer build network + least-privilege execution role (`terraform/packer-build/`) | **Current (applied)** | VPC `10.10.0.0/24`, subnet, IGW, no-ingress SG, SSM builder profile, execution role (D-012/D-013) — `terraform apply`-d, isolated from the runtime VPC |
| Packer base AMI (Ubuntu 24.04 + Docker/Compose/AWS CLI v2/`vm.max_map_count`/SSM) | **Validated** | Built + smoke-tested 2026-09-07 (evidence AMI `ami-0b1bf8942dfc0daf1`, `us-east-2` — historical evidence, not a config constant) |
| End-to-end **runtime** Wazuh deploy validated via SSM | **Not done** | Runtime VPC / instance not applied; B2/B3 and the bootstrap decision remain |
| Multi-account model (management / security / lab) | **Planned** | Single account, single provider today |
| CloudTrail, Security Hub, GuardDuty, Config, CloudWatch | **Planned** | Not present |
| `Security Hub → EventBridge → Firehose → S3 → SQS → Wazuh` ingestion | **Planned** | Not present |
| `Security Hub/EventBridge → Step Functions → selective response` (Lambda/SNS) | **Planned** | Not present |
| Lab-account workloads + Wazuh agents | **Planned** | Not present |
| Public dashboard (ALB + ACM) | **Deferred** | SSM port forwarding is the intended access path |
| Malware-analysis / vulnerability-management pipelines | **Deferred** | Explicitly out of MVP scope |

Legend: **Current** = implementation proves it exists (not necessarily deployed) · **Partial**
= scaffolding exists but the capability is incomplete/unvalidated · **Validated** = exercised
end-to-end and recorded · **Planned** = accepted direction, not implemented · **Deferred** =
intentionally excluded from the current phase. The Packer build path (build network,
execution role, base AMI) is Validated; the runtime Wazuh deployment is not. See
[docs/ROADMAP.md](docs/ROADMAP.md).

---

## Design principles

- **Private administrative access.** The Wazuh host is not publicly exposed for administration;
  AWS Systems Manager (Session Manager / port forwarding) is the access path.
- **No NAT Gateway for the current MVP.** Use VPC endpoints where practical — cheaper for a
  temporary lab.
- **Public Wazuh dashboard deferred.** ALB + ACM is not required for this phase.
- **AWS Security Hub stays authoritative** for AWS-native findings. Wazuh is the analyst /
  investigation surface, not the system of record for AWS findings.
- **Automated response is selective.** Not every finding triggers remediation.
- **Temporary environments.** `deploy → test → validate → document → destroy`.
- **Keep it reasonable.** The least infrastructure and code needed to be secure, clear,
  maintainable, and repeatable. Avoid unnecessary abstractions.

Decision records: [docs/DECISIONS.md](docs/DECISIONS.md).

---

## High-level architecture

```mermaid
flowchart LR

    subgraph Current["Current - Phase 1 (in progress)"]
        A["Private VPC + VPC endpoints"] --> B["Wazuh EC2 reached via SSM"]
        B --> C["Private ECR images + S3 artifacts"]
    end

    subgraph Planned["Planned - Phases 2 to 5"]
        CT["CloudTrail"] --> LOG["Central logging / investigation"]

        GD["GuardDuty"] --> SH["Security Hub<br/>authoritative AWS findings"]

        SH --> ING["EventBridge / Firehose / S3 / SQS"]
        ING --> WZ["Wazuh analyst view"]

        SH --> RESP["Step Functions<br/>selective response"]
    end

    Current -. "foundation for" .-> Planned
```

Detailed diagrams (current + target): [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

## Current phase summary

**Phase 1 — Private Wazuh Platform.** Goal: make the single-node Wazuh deployment
successfully deployable and validate it through SSM **before** starting any AWS
detection/ingestion work.

**Done:** the Packer prerequisite phase — a secure, isolated, persistent Packer build
network; a least-privilege execution role (`CloudGuardOperator` → `assume_role`); the fixed
bake script; and a **validated base AMI** built and smoke-tested through Session Manager.

**Remaining Phase 1 work:** publish Wazuh images to ECR (B2), check in the Wazuh artifact
set + S3 publish workflow (B3), decide the **artifact bootstrap ordering** and **persistence
vs. `terraform destroy`**, EC2 hardening + runtime outputs, then `terraform apply` the
runtime (`terraform/wazuh-project/`) and validate it end-to-end via SSM.

Canonical breakdown — remaining work, completion gaps, open decisions, and the exact next
task: **[docs/CURRENT_STATE.md](docs/CURRENT_STATE.md)** (kept current; not duplicated here).

---

## Documentation map

| Document | Purpose |
| --- | --- |
| [docs/PROJECT_CHARTER.md](docs/PROJECT_CHARTER.md) | Long-lived purpose, goals, principles, MVP definition, non-goals. |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Current vs. target architecture, with diagrams. |
| [docs/CURRENT_STATE.md](docs/CURRENT_STATE.md) | **Primary development-handoff document.** Phase status, blockers, next task. |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Phased plan (Phase 0–6) with status labels. |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Lightweight architecture decision log. |
| [docs/RUNBOOK.md](docs/RUNBOOK.md) | Operational skeleton for deploy/validate/destroy (steps marked *Not yet operational* where applicable). |

Before contributing, read [AGENTS.md](AGENTS.md) — it defines the documentation reading
order, the source-of-truth hierarchy, and the handoff requirements every change must follow.

---

## Repository layout

```text
README.md                     project entry point (this file)
AGENTS.md                     contributor guide — reading order, source-of-truth, handoff rules
CLAUDE.md                     tool-specific instruction file (defers to AGENTS.md)
docs/                         project record (charter, architecture, state, roadmap, decisions, runbook)
packer/                       Ubuntu 24.04 Wazuh base AMI build (Validated 2026-09-07)
  wazuh-ami.pkr.hcl                 source: build-network filters + assume_role (D-012/D-013)
  build-identity.pkr.hcl            required packer_execution_role_arn var (from TF output)
  variables.pkr.hcl
  scripts/install-wazuh-base.sh     bake-time host provisioner (B1 done)
terraform/wazuh-project/      Terraform root - disposable Wazuh runtime (NOT applied)
  providers.tf variables.tf networking.tf endpoints.tf roles.tf ecr.tf storage.tf ec2.tf
  outputs.tf                        (empty placeholder)
  scripts/install-wazuh.sh.tftpl    EC2 user-data template
terraform/packer-build/       Terraform root - persistent Packer build network (APPLIED, D-012)
  providers.tf variables.tf network.tf iam.tf packer-execution-role.tf outputs.tf
```
