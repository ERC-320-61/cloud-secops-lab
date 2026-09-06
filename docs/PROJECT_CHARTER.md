# CloudGuard — Project Charter

> Long-lived definition of the project. Changes infrequently.
> **Not** a status document — for current status see [CURRENT_STATE.md](CURRENT_STATE.md).

---

## Purpose

CloudGuard is a **reusable AWS cloud security operations lab**. It exists to demonstrate, in a
realistic but inexpensive way, how a security team designs, deploys, operates, and tears down
cloud security capabilities using Infrastructure as Code.

## Problem statement

Building a credible cloud SecOps environment normally requires either:

- a permanently running (and expensive) AWS estate, or
- a pile of manual, undocumented setup that cannot be reproduced.

CloudGuard solves this by making the **repository the persistent artifact** and the **AWS
environment disposable**: everything needed to stand the lab up, prove it works, and destroy
it lives in version control.

## Portfolio / technical objectives

Demonstrate hands-on capability in:

- AWS security architecture and multi-account design
- Centralized security telemetry
- Detection engineering
- Investigation workflows (including CloudTrail analysis)
- AWS-native security findings (Security Hub, GuardDuty)
- Wazuh as an endpoint/security telemetry and analyst platform
- Event-driven security integration
- Selective automated response
- Infrastructure as Code (Terraform + Packer)
- Secure administrative access (no public admin surface)
- Repeatable deployment **and destruction**

## Project goals

1. A private, SSM-administered, single-node Wazuh platform that can be deployed and validated
   from code.
2. Ingestion of AWS-native security findings into Wazuh for analyst investigation.
3. A selective automated-response path for a small set of qualified findings.
4. A temporary lab account for generating telemetry and running security test scenarios.
5. End-to-end detection / investigation / response scenarios with captured evidence.
6. Cost kept low by running environments only while validating, then destroying them.

## Design principles

| Principle | Meaning |
| --- | --- |
| Private by default | No public infrastructure purely for administration. |
| Least reasonable footprint | Minimum infrastructure/code to be secure, clear, maintainable, repeatable. Avoid over-engineering and unnecessary abstractions. |
| Repeatable lifecycle | `deploy → test → validate → document → destroy`. |
| Documentation is memory | The repo must let a contextless human or agent resume work. |
| Decisions are recorded | Accepted architectural choices live in [DECISIONS.md](DECISIONS.md) and are not silently reversed. |

## Security principles

- Administrative access via **AWS Systems Manager** (Session Manager / port forwarding), not
  public SSH or a public dashboard.
- Private networking; no Internet Gateway or NAT Gateway in the current MVP.
- Least-privilege IAM (scoped ECR pull, scoped S3 read).
- Encrypted storage for artifacts and logs.
- **AWS Security Hub remains the authoritative source** for AWS-native findings. Wazuh
  consumes/presents information for analysts; it does not become the AWS findings system of
  record.
- Automated response is **selective** — only qualified, actionable findings, with
  auditability.

## Cost philosophy

Target: **keep the lab inexpensive**. A low-tens-of-dollars-per-month figure has been used
historically as an informal guideline (*not* a hard budget or SLA); prices change, so treat
it as intent rather than a number to defend. The real control is the lifecycle: run an
environment only while validating, then destroy it.

Cost-control levers already baked into the design:

- No NAT Gateway (VPC endpoints instead where practical).
- Private, single-AZ, single-node footprint.
- Temporary deployments — destroy after validation.
- Avoid continuously running services that are not needed.

Standing costs to watch while an environment is deployed: the interface VPC endpoints and
the Wazuh EC2 instance both carry recurring hourly cost. These are acceptable **only** if
environments are actually destroyed between sessions.

## Temporary-environment lifecycle

```text
deploy → test → validate → document → destroy
```

The repository is permanent. Any deployed AWS environment is expected to be short-lived.
See [RUNBOOK.md](RUNBOOK.md).

## Target account model

| Account | Responsibility | State |
| --- | --- | --- |
| **Management** | AWS Organizations, account and guardrail management | Planned |
| **Security** | Wazuh, CloudTrail, Security Hub, GuardDuty, centralized logging storage, EventBridge, Firehose, SQS, Step Functions, Lambda, SNS, selected Config/CloudWatch, Systems Manager, private security VPC/networking | Planned (target placement) |
| **Lab** | Temporary Windows/Linux test hosts, Wazuh agents, workloads that generate telemetry/findings, security test scenarios | Planned |

Today the repository deploys into a **single AWS account** with one Terraform provider — the
Phase 1 private networking, IAM, ECR, S3, and EC2 all live there, **not** in a dedicated
Security account. The multi-account split is target architecture and the transition point is
an open decision ([DECISIONS.md](DECISIONS.md) D-007).

## Wazuh's intended role

- Analyst / security-operations interface.
- Endpoint and security telemetry platform (via Wazuh agents — planned).
- Investigation surface for both endpoint telemetry and (ingested) AWS findings.

Wazuh is **not** intended to replace AWS-native security services as the authoritative
findings source.

## AWS-native security-services role

- **Security Hub**: authoritative aggregation of AWS-native findings.
- **GuardDuty**: threat detection feeding Security Hub.
- **CloudTrail**: authoritative API activity record for investigation.
- **Config / CloudWatch**: selected configuration and operational signal only — not a
  full compliance program.

These are **Planned**; none are implemented yet.

## MVP definition

The CloudGuard MVP is complete when **all** of the following are true:

1. **Private Wazuh platform** deploys from code into the security VPC and is reachable by an
   analyst via SSM port forwarding, with a healthy manager + indexer + dashboard.
2. **AWS security sources** (CloudTrail, GuardDuty, Security Hub; selected Config/CloudWatch)
   are enabled from code.
3. **Findings ingestion** delivers Security Hub findings to Wazuh
   (`Security Hub → EventBridge → Firehose → S3 → SQS → Wazuh`) for analyst investigation.
4. **Selective automated response** handles at least one qualified finding type through a
   Step Functions workflow (with Lambda/SNS as needed), demonstrably *not* firing on every
   finding.
5. **Lab workloads** (at least one Windows and one Linux host with Wazuh agents) generate
   telemetry and support test scenarios.
6. **End-to-end validation**: documented detection, investigation, and response scenarios
   with evidence, plus a clean `terraform destroy` and cost check.

The MVP explicitly does **not** require full malware-analysis or vulnerability-management
pipelines.

## Success criteria

- A new contributor/agent can resume work using only the repository.
- Each phase can be deployed, validated, and destroyed repeatably.
- Monthly cost stays within the cost philosophy when the lifecycle is followed.
- Security principles above hold in the deployed environment.
- Detection/investigation/response scenarios are demonstrable and evidenced.

## Explicit non-goals

- Not a production security platform or a managed service.
- Not a replacement for AWS-native security services as the findings system of record.
- Not a permanently running environment.
- Not a full compliance (Config conformance pack) program.
- Not a full malware-analysis pipeline.
- Not a full vulnerability-management pipeline.
- Not a publicly exposed Wazuh dashboard (for this phase).
- Not a high-availability / multi-AZ / multi-node Wazuh cluster.

## Deferred items

| Item | Why deferred |
| --- | --- |
| Public Wazuh dashboard (ALB + ACM + public DNS) | Not needed for current phase; SSM port forwarding suffices and avoids public exposure + cost. |
| Malware-analysis pipeline | Out of MVP scope; possible future expansion. |
| Vulnerability-management pipeline | Out of MVP scope; possible future expansion. |
| Multi-AZ / HA Wazuh | Unnecessary complexity and cost for a temporary lab. |

Not deferred, but **open decisions** (tracked in [CURRENT_STATE.md](CURRENT_STATE.md) →
Open decisions): artifact bucket encryption SSE-S3 vs. customer-managed KMS key
([DECISIONS.md](DECISIONS.md) D-010); remote Terraform state backend / separate lifecycle for
artifact-bootstrap infrastructure; the multi-account transition point (D-007); and the
Wazuh version to pin.
