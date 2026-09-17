# CloudGuard (`cloud-secops-lab`)

A **reusable AWS cloud security operations lab** for detection engineering, investigation,
and selective automated response — built with Infrastructure as Code so an AWS environment
can be **deployed, tested, validated, documented, and destroyed** on demand.

The **repository is the permanent artifact**. Deployed AWS environments are **temporary and
cost-controlled** by design.

> **Status:** Phase 1 — Private Wazuh Platform — **IN PROGRESS**.
> The Packer prerequisite phase is **complete**. CloudGuard has adopted the
> **Management / Security / Lab** account model ([docs/DECISIONS.md](docs/DECISIONS.md)
> D-014), and per the operator the **build-path migration has run**: the Packer build
> infrastructure is applied in **Security**, a new Security-owned golden AMI has been built,
> validated, and **shared to Lab** (confirmed launchable, SSM smoke test passed). The
> repository has also been refactored so the Lab runtime **consumes** Security-owned ECR/S3
> resources instead of owning its own. Remaining Phase 1 work: retire the legacy Management
> build infrastructure, apply the persistent ECR/S3 artifact layer in Security, publish the
> Wazuh **4.14.7** images/config, grant the runtime cross-account access, and deploy +
> validate the disposable runtime in **Lab**. See [docs/CURRENT_STATE.md](docs/CURRENT_STATE.md).

---

## What exists today vs. what is planned

| Layer | State | Notes |
| --- | --- | --- |
| Private VPC, single private subnet, private route table | **Current** | `us-east-2`, `10.0.0.0/16`, no IGW, no NAT |
| VPC endpoints: S3 gateway + `ssm`/`ssmmessages`/`ec2messages`/`ecr.api`/`ecr.dkr` | **Current** | Endpoint security group allows 443 from the subnet only |
| EC2 IAM role / instance profile (SSM core + scoped ECR pull + scoped S3 read) | **Current** | `roles.tf` |
| 3 private immutable ECR repos (manager / indexer / dashboard) | **In `terraform/wazuh-artifacts/`** | Persistent, Security-owned (D-016); not applied; nothing publishes images (B2). `terraform/wazuh-project/` no longer defines these (D-017) |
| Private S3 artifact bucket (SSE-S3, block-public-access, TLS-deny policy) | **In `terraform/wazuh-artifacts/`** | Persistent, Security-owned (D-016); not applied; no Wazuh 4.14.7 artifact set published (B3) |
| Lab EC2 IAM role + instance profile | **In `terraform/wazuh-runtime-identity/`** | Persistent, Lab-owned (D-018); not applied; `terraform/wazuh-project/` no longer creates this role |
| Wazuh EC2 Terraform definition + templated user-data (Lab) | **Partial (hardened)** | Dedicated SG, IMDSv2, encrypted `gp3` root volume, real outputs all done (D-019); **runtime not applied**; consumes the shared Security AMI, the Lab identity, and Security ECR/S3 via explicit variables |
| Persistent Packer build network + least-privilege execution role (`terraform/packer-build/`) | **Applied in Security (operator-reported)** | VPC `10.10.0.0/24`, subnet, IGW, no-ingress SG, SSM builder profile, execution role (D-012/D-013). Code is account-agnostic; originally applied in Management |
| Packer base AMI (Ubuntu 24.04 + Docker/Compose/AWS CLI v2/`vm.max_map_count`/SSM) | **Validated in Security (operator-reported)** | New Security-owned build + smoke test (2026-09-16, operator-reported, not independently verified). The Management build (`ami-0b1bf8942dfc0daf1`, 2026-09-07) is superseded evidence |
| Golden-AMI cross-account share Security → Lab (`ami_users` / `snapshot_users`) | **Exercised (operator-reported)** | Launch permission only, not public, no copy (D-015); Lab confirmed launch + SSM smoke test |
| Persistent ECR + S3 artifact layer + cross-account access (`terraform/wazuh-artifacts/`, Security) | **Implemented, not applied** | 3 private `IMMUTABLE` ECR repos + artifact bucket (block-public-access, SSE-S3, TLS-deny policy) — D-016; **plus** unconditional cross-account ECR/S3 policies granted to the Lab identity root's role, single apply (D-018) |
| End-to-end **runtime** Wazuh deploy validated via SSM (Lab) | **Not done** | Runtime VPC / instance not applied; identity-root + artifact-root apply + B2/B3 remain — one-directional (D-018), no re-apply |
| Multi-account model (Management / Security / Lab) | **Accepted (D-014); build path applied (operator-reported)** | Accounts + SSO permission sets exist; Security has the build infra + AMI; artifact layer + Lab runtime not applied yet |
| CloudTrail, Security Hub, GuardDuty, Config, CloudWatch | **Planned** | Not present |
| `Security Hub → EventBridge → Firehose → S3 → SQS → Wazuh` ingestion | **Planned** | Not present |
| `Security Hub/EventBridge → Step Functions → selective response` (Lambda/SNS) | **Planned** | Not present |
| Lab-account workloads + Wazuh agents + SprintOps Tracker | **Planned** | Not present |
| Public dashboard (ALB + ACM) | **Deferred** | SSM port forwarding is the intended access path |
| Malware-analysis / vulnerability-management pipelines | **Deferred** | Explicitly out of MVP scope |

Legend: **Current** = implementation proves it exists (not necessarily deployed) · **Partial**
= scaffolding exists but the capability is incomplete/unvalidated · **Validated** = exercised
end-to-end and recorded · **Planned** = accepted direction, not implemented · **Deferred** =
intentionally excluded from the current phase. The Packer build path (build network,
execution role, base AMI, Lab share) is Validated **in Security** (operator-reported); the
persistent artifact layer and the runtime Wazuh deployment are not. See
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

    subgraph Sec["Security account (Phase 1 — pending apply)"]
        PB["Packer build network<br/>+ golden AMI (owner)"]
        ART["Persistent ECR images + S3 config"]
    end

    subgraph Lab["Lab account (Phase 1 — pending apply)"]
        RT["Private VPC + VPC endpoints<br/>Wazuh EC2 reached via SSM"]
    end

    subgraph Planned["Planned - Phases 2 to 5 (Security account)"]
        CT["CloudTrail"] --> LOG["Central logging / investigation"]
        GD["GuardDuty"] --> SH["Security Hub<br/>authoritative AWS findings"]
        SH --> ING["EventBridge / Firehose / S3 / SQS"]
        ING --> WZ["Wazuh analyst view"]
        SH --> RESP["Step Functions<br/>selective response"]
    end

    PB -. "AMI launch permission (D-015)" .-> RT
    ART -. "images + config (cross-account)" .-> RT
    Lab -. "foundation for" .-> Planned
```

Detailed diagrams (current + target): [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

## Current phase summary

**Phase 1 — Private Wazuh Platform.** Goal: make the single-node Wazuh deployment
successfully deployable and validate it through SSM **before** starting any AWS
detection/ingestion work.

**Done:** the Packer prerequisite phase — a secure, isolated, persistent Packer build
network; a least-privilege execution role; the fixed bake script; and a **validated base
AMI**. The repository restructure for the three-account model (D-014/D-015/D-016/D-017),
including making the Lab runtime consume Security-owned ECR/S3 instead of owning its own —
then a follow-up pass (D-018/D-019) that split the Lab EC2 IAM identity into its own
persistent root (fixing a circular Terraform dependency the first pass had introduced) and
hardened the runtime EC2 (dedicated SG, IMDSv2, encrypted root volume, real outputs). Per the
operator, the **build-path migration has also run**: build infra applied and a new golden
AMI built + validated in Security, shared to and smoke-tested in Lab.

**Remaining Phase 1 work:** retire the legacy Management build infrastructure; apply
`terraform/wazuh-runtime-identity/` in Lab, then `terraform/wazuh-artifacts/` in Security
(single apply — no re-apply, D-018); publish the Wazuh **4.14.7** images to ECR (B2) and the
artifact set to S3 (B3); apply `terraform/wazuh-project/` in Lab (the last step in the
chain); validate end-to-end via SSM.

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
packer/                       Ubuntu 24.04 Wazuh base AMI build — owned by the Security account (D-014)
  wazuh-ami.pkr.hcl                 source: build-network filters + assume_role + ami_users/snapshot_users (D-012/13/15)
  ami-sharing.pkr.hcl              required lab_account_id var (cross-account AMI share — D-015)
  build-identity.pkr.hcl           required packer_execution_role_arn var (from TF output)
  variables.pkr.hcl
  scripts/install-wazuh-base.sh    bake-time host provisioner (B1 done)
terraform/packer-build/       Terraform root - persistent Packer build network — SECURITY account (D-012/D-014)
  providers.tf variables.tf network.tf iam.tf packer-execution-role.tf outputs.tf   APPLIED (Security, operator-reported)
terraform/wazuh-runtime-identity/  Terraform root - persistent Lab EC2 IAM identity — LAB account (D-018)   NOT applied
  providers.tf variables.tf iam.tf outputs.tf                                       apply BEFORE wazuh-artifacts
terraform/wazuh-artifacts/    Terraform root - persistent ECR + S3 artifact layer + cross-account policies — SECURITY account (D-016/D-018)   NOT applied
  providers.tf variables.tf ecr.tf storage.tf outputs.tf                            apply AFTER wazuh-runtime-identity
terraform/wazuh-project/      Terraform root - disposable Wazuh runtime — LAB account (D-006/D-014/D-017/D-019)   NOT applied
  providers.tf variables.tf networking.tf endpoints.tf security.tf ec2.tf outputs.tf  apply LAST; owns no IAM/ECR/S3
  scripts/install-wazuh.sh.tftpl    EC2 user-data template — ECR registry passed in explicitly (D-017)
```

No longer present: `terraform/wazuh-project/roles.tf` — moved to
`terraform/wazuh-runtime-identity/iam.tf` (D-018), so this root creates no IAM role of its
own.

No longer present: `terraform/wazuh-project/ecr.tf` / `storage.tf` — removed (D-017); those
resources now live only in `terraform/wazuh-artifacts/`. `git stash@{0}` still references
the deleted `ecr.tf` — left untouched, will conflict if popped (expected).
