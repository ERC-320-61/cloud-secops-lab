# CloudGuard — Decision Log

> Lightweight architecture decision records. Not a formal ADR framework.
>
> Structure per entry: **ID · Decision · Status · Context · Rationale · Consequences.**
> Status is one of: Accepted · Superseded · Reversed · Proposed.
>
> Agents must not silently reverse an **Accepted** decision. To change one, add a new entry
> that supersedes it and update [ARCHITECTURE.md](ARCHITECTURE.md) / [ROADMAP.md](ROADMAP.md)
> as needed.

---

## D-001 — Private administrative access via AWS Systems Manager

- **Status:** Accepted
- **Context:** The Wazuh host runs in a private subnet with no public IP. Operators still
  need shell and dashboard access.
- **Decision:** Administrative access is via AWS Systems Manager — Session Manager for
  shell, SSM port forwarding for the dashboard. No public SSH, no bastion, no public admin
  endpoint.
- **Rationale:** Removes a public attack surface; no key management; auditable; works with
  the private-subnet + VPC-endpoint design.
- **Consequences:** Requires `ssm`, `ssmmessages`, `ec2messages` interface endpoints
  (present) and `AmazonSSMManagedInstanceCore` on the instance role (present). Operators need
  AWS credentials + the SSM plugin. Evidence: [endpoints.tf](../terraform/wazuh-project/endpoints.tf),
  [roles.tf](../terraform/wazuh-project/roles.tf).

---

## D-002 — No NAT Gateway for the current MVP

- **Status:** Accepted
- **Context:** The private subnet needs access to a limited set of AWS services (SSM, ECR,
  S3). A NAT Gateway would provide general egress but carries recurring hourly and
  data-processing cost that is unnecessary for a temporary lab.
- **Decision:** No NAT Gateway. Use VPC endpoints (S3 gateway + `ssm`/`ssmmessages`/
  `ec2messages`/`ecr.api`/`ecr.dkr` interface endpoints) for the required services.
- **Rationale:** Matches the temporary, cost-conscious lab model; keeps egress explicitly
  scoped to named services.
- **Consequences:** Anything the instance needs from the internet (e.g. pulling Wazuh
  container images or OS packages at runtime) must instead be pre-baked into the AMI or
  staged in ECR/S3. This is a direct cause of the hard deployment blockers in
  [CURRENT_STATE.md](CURRENT_STATE.md). Interface endpoints themselves carry recurring
  hourly and data-processing cost, so the environment is temporary by design and should be
  destroyed after each validation session (see D-006).

---

## D-003 — AWS Security Hub is authoritative for AWS-native findings

- **Status:** Accepted
- **Context:** Wazuh can ingest and display many signal types. It would be tempting to make
  it the single pane for everything, including AWS findings.
- **Decision:** AWS Security Hub (fed by GuardDuty, etc.) remains the authoritative system of
  record for AWS-native findings. Wazuh receives a copy of findings for analyst
  investigation only.
- **Rationale:** Keeps AWS-native tooling authoritative and well-integrated; avoids building
  a fragile reimplementation of AWS security services inside Wazuh; clearer portfolio story.
- **Consequences:** The Phase 3 ingestion path
  (`Security Hub → EventBridge → Firehose → S3 → SQS → Wazuh`) is one-directional into
  Wazuh. Wazuh is not expected to write findings back or to be queried as the source of
  truth.

---

## D-004 — Automated response is selective, not universal

- **Status:** Accepted
- **Context:** Every Security Hub finding could theoretically trigger automation.
- **Decision:** Only a small, explicitly qualified set of actionable finding types flows to
  an automated response workflow. Everything else is left for analyst handling.
- **Rationale:** Safety (automation acting on noisy/low-confidence findings is dangerous);
  auditability; realistic operations practice.
- **Consequences:** Phase 4 must include a qualification/filter stage before Step Functions,
  plus an audit trail and (where appropriate) SNS notification/approval. Response actions
  should be reversible or clearly bounded.

---

## D-005 — Public Wazuh dashboard (ALB + ACM) is deferred

- **Status:** Accepted
- **Context:** A public HTTPS dashboard (ALB + ACM certificate + public DNS) is a common
  Wazuh pattern.
- **Decision:** Deferred. For the current phase the dashboard is reached only via SSM port
  forwarding.
- **Rationale:** No public exposure; no ALB/ACM cost; sufficient for a single-analyst lab.
- **Consequences:** No `aws_lb*` / `aws_acm_*` / public subnet resources. If multi-user
  access is later needed, revisit with a new decision.

---

## D-006 — Temporary environment lifecycle

- **Status:** Accepted
- **Context:** Running the full lab continuously is expensive and unnecessary.
- **Decision:** Operate on `deploy → test → validate → document → destroy`. The repository is
  permanent; deployed environments are short-lived.
- **Rationale:** Cost control while retaining a realistic architecture.
- **Consequences:** All infrastructure must be reproducible from code and safe to
  `terraform destroy`. Validation results and any manual steps must be written into the docs
  (especially [RUNBOOK.md](RUNBOOK.md) and [CURRENT_STATE.md](CURRENT_STATE.md)) because the
  environment itself will not persist.

---

## D-007 — Multi-account transition point (open)

- **Status:** Proposed
- **Context:** The charter describes a management / security / lab account model. The
  repository proves only that the **current Phase 1 implementation is single-account** (one
  AWS provider, no aliases, no `assume_role`). It does not establish *when* the project
  should move to the three-account model.
- **Decision (proposed, not settled):**
  - The current Phase 1 implementation stays single-account.
  - Multi-account (management / security / lab) remains the **target architecture**.
  - The immediate Phase 1 Wazuh repair work **must not** introduce a multi-account refactor.
  - The exact phase at which the transition happens is an **open decision** — it is *not*
    asserted here that Phases 2 or 3 must remain single-account.
- **Rationale:** Avoids pulling AWS Organizations complexity into the Wazuh-foundation
  repair; keeps the near-term work small and reversible.
- **Consequences:** [ARCHITECTURE.md](ARCHITECTURE.md) marks account separation as Planned
  and target diagrams note that current resources live in a single account. Code should
  avoid hard-coding a single-account assumption where staying account-agnostic is cheap. The
  transition point is tracked in [CURRENT_STATE.md](CURRENT_STATE.md) → Open Decisions.

---

## D-008 — Keep implementation minimal and maintainable

- **Status:** Accepted
- **Context:** Security labs tend to accumulate modules, wrappers, and abstractions.
- **Decision:** Prefer the least reasonable amount of code and infrastructure to be secure,
  clear, maintainable, and repeatable. One Terraform root module until there is a concrete
  reason to split. Avoid speculative abstraction.
- **Rationale:** Readability and continuity — a new agent should grasp the whole module
  quickly.
- **Consequences:** Resist premature `modules/`, multi-env scaffolding, or generic wrappers.
  Revisit only when duplication or multi-account work makes it clearly worthwhile.

---

## D-009 — Wazuh delivery via private ECR + S3 config (not runtime internet pull)

- **Status:** Accepted
- **Context:** The original `install-wazuh.sh` (commit `cca2387`) did a runtime
  `git clone` of `wazuh/wazuh-docker@v4.14.7` and pulled images from the internet. That is
  incompatible with D-002 (no NAT). Commit `333460c` moved toward an ECR + S3 delivery
  model; this entry explicitly ratifies that architecture.
- **Decision:** The Wazuh stack is delivered with **no runtime internet dependency** for the
  private host:
  - Wazuh **container images** come from **private ECR**;
  - the Wazuh **Compose file + configuration** come from the **S3 artifact bucket**;
  - both are pulled over VPC endpoints.
- **Rationale:** Consistent with the no-NAT private design; immutable, scannable images;
  reproducible.
- **Consequences:** The architecture is accepted but the **implementation is incomplete** —
  it requires a working ECR image publish/mirror workflow and an S3 artifact publish
  workflow plus a checked-in Wazuh artifact set with a pinned version (hard blockers B2/B3
  in [CURRENT_STATE.md](CURRENT_STATE.md)). It also raises unresolved lifecycle questions
  (artifact/image publication ordering vs. Terraform-created destinations; persistence of
  ECR/S3 vs. `terraform destroy`) tracked in [CURRENT_STATE.md](CURRENT_STATE.md) → Open
  Decisions. Evidence: [ecr.tf](../terraform/wazuh-project/ecr.tf),
  [scripts/install-wazuh.sh.tftpl](../terraform/wazuh-project/scripts/install-wazuh.sh.tftpl).

---

## D-010 — Artifact bucket encryption: SSE-S3 vs. CMK (open)

- **Status:** Proposed
- **Current implementation (fact):** the artifact bucket is encrypted with **SSE-S3
  (AES256)** — `aws_s3_bucket_server_side_encryption_configuration` in
  [storage.tf](../terraform/wazuh-project/storage.tf). This is what the code does today; it
  is not, on its own, a ratified architecture decision.
- **Open question:** whether Phase 1 keeps SSE-S3 for the artifact bucket or introduces a
  customer-managed KMS key (CMK).
- **Considerations:**
  - SSE-S3 has fewer moving parts and no key charges — adequate for a temporary,
    single-account artifact bucket holding non-secret Compose/config.
  - A CMK becomes relevant if the bucket must enforce key-policy-based access, or when
    Phase 2 introduces central/cross-account logging, which may carry different encryption
    requirements.
- **Consequences:** Tracked in [CURRENT_STATE.md](CURRENT_STATE.md) → Open Decisions.
  Phase 2 central logging is expected to make its own encryption decision and may supersede
  this entry.
