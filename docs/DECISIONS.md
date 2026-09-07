# CloudGuard — Decision Log

> Lightweight architecture decision records. Not a formal ADR framework.
>
> Structure per entry: **ID · Decision · Status · Context · Rationale · Consequences.**
> Status is one of: Accepted · Superseded · Reversed · Proposed.
>
> An **Accepted** decision must not be silently reversed. To change one, add a new entry
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
- **Rationale:** Readability and continuity — a new contributor should grasp the whole module
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

---

## D-011 — Custom AMI = stable host prerequisites; runtime = Wazuh deployment state

- **Status:** Accepted
- **Context:** The single `install-wazuh.sh` from `cca2387` mixed host setup (Docker,
  kernel tuning) with deployment actions (image pulls, cert generation, `docker compose up`).
  Commit `333460c` split it into a Packer provisioner and a Terraform user-data template but
  left the *same* runtime content in both (hard blocker B1). B1 repair makes the boundary
  explicit.
- **Decision:**
  - **The custom AMI** (`packer/scripts/install-wazuh-base.sh`) contains only stable,
    deployment-independent host prerequisites: Ubuntu 24.04 base, Docker Engine + Compose
    plugin, AWS CLI v2, supporting utilities, persisted `vm.max_map_count=262144`, Docker
    enabled at boot, the `ubuntu` user in the `docker` group, and a verified SSM agent. It is
    **Wazuh-version-independent** and carries no Wazuh images, compose file, config, or
    certificates.
  - **Runtime** (`terraform/wazuh-project/scripts/install-wazuh.sh.tftpl`, plus the B2/B3
    workflows) owns everything deployment-specific: the Wazuh version, image pulls from
    private ECR, the compose file and config from S3, certificate generation, and
    `docker compose up`.
- **Rationale:** A generic base image is reusable across Wazuh versions and deployments,
  builds rarely, and keeps deployment state in the layer that is meant to be disposable
  (D-006). Consistent with D-002 (no runtime internet) and D-009 (ECR + S3 delivery).
- **Consequences:** No Wazuh-version variable belongs in Packer. B2/B3 must supply the
  runtime pieces the AMI intentionally omits. Evidence:
  [packer/scripts/install-wazuh-base.sh](../packer/scripts/install-wazuh-base.sh),
  [scripts/install-wazuh.sh.tftpl](../terraform/wazuh-project/scripts/install-wazuh.sh.tftpl).

---

## D-012 — Persistent dedicated Packer build network; ephemeral builder via SSM

- **Status:** Accepted
- **Resolves:** the open pre-build item **PB-1** (temporary-builder networking) in
  [CURRENT_STATE.md](CURRENT_STATE.md) — it is no longer an unresolved design question
  (implementation and apply/validation still pending).
- **Context:** The Packer source previously relied on the account's default VPC and on
  ambient public-IP / temporary-security-group behaviour. That is undependable (many
  accounts have no default VPC) and gives the builder an implicit public SSH surface. The
  AMI bake needs outbound Internet (Docker apt repo, AWS CLI v2 installer); D-002 keeps the
  Wazuh *runtime* private with no NAT.
- **Decision:**
  - **A dedicated, persistent Packer build network** exists as its **own Terraform root** at
    [terraform/packer-build/](../terraform/packer-build/), separate from the disposable
    Wazuh runtime root. Persistent resources: one build VPC (`10.10.0.0/24`, non-overlapping
    with the runtime `10.0.0.0/16`), one build subnet, an Internet Gateway + default route,
    a dedicated builder security group, and a dedicated EC2 IAM role / instance profile for
    SSM. These stay between builds and are **not** part of the Wazuh
    deploy→test→validate→destroy cycle.
  - **The build subnet does not auto-assign public IPs** (`map_public_ip_on_launch = false`).
  - **The ephemeral builder is Packer-managed**: Packer launches it, it receives an
    ephemeral public IPv4 **explicitly requested** by the Packer config
    (`associate_public_ip_address = true`) for outbound access only, and Packer terminates
    it after the AMI is produced.
  - **No public administrative ingress.** The builder security group has **zero ingress
    rules**. Packer manages the builder through **AWS Systems Manager Session Manager**
    (`ssh_interface = "session_manager"`; the SSH communicator is tunnelled through SSM).
  - **IMDSv2 is required** on the temporary builder.
  - Packer locates the persistent resources by **deterministic tag filters** — `Project` +
    `Purpose` identify the packer-build lifecycle boundary, and a **resource-specific
    `Name`** (`cloud-secops-lab-packer-build-vpc` / `-subnet` / `-sg`) pins each lookup to
    one resource — and the instance profile by its exact name
    (`cloud-secops-lab-packer-build-ssm-profile`). No generated `vpc-…` / `subnet-…` /
    `sg-…` IDs in source control. These filters **identify** the intended resources; they
    are not a uniqueness guarantee, so the design is **fail-closed**: `subnet_filter` has no
    `most_free` / `random` fallback and the Amazon builder errors if any filter matches more
    than one resource rather than silently choosing.
- **Secure-by-design properties** (controls-aligned language, not a compliance claim):
  least-privilege builder identity (SSM-only); controlled, minimal external egress
  (TCP 80/443 only, no all-protocol rule); no unnecessary inbound administrative exposure;
  a dedicated build segment separate from runtime; ephemeral build compute; an explicit,
  documented infrastructure lifecycle; and an auditable, reproducible build path.
- **Relationship to other decisions:**
  - **D-002 (no NAT):** unaffected. The IGW here is confined to the isolated build VPC and
    carries no hourly/data-processing charge; the Wazuh runtime subnet still has no IGW/NAT.
  - **D-006 (temporary lifecycle):** the Wazuh runtime is still deploy→test→validate→destroy.
    The build network is a **deliberate, bounded exception** — it is only no-hourly-cost
    control-plane objects (VPC/subnet/IGW/route table/SG/IAM); the cost-bearing pieces
    (builder EC2, its EBS, its temporary public IPv4, the resulting AMI/snapshot storage)
    remain ephemeral or are normal AMI storage.
  - **D-008 (minimal footprint / one root until a concrete reason):** this is that concrete
    reason. The materially different lifecycle (persistent vs. disposable) justifies the
    second Terraform root. It does **not** license splitting the still-open ECR/S3
    artifact-persistence question.
- **Consequences:**
  - `terraform/packer-build/` must be `terraform apply`-d before the first `packer build`.
  - The Packer **caller** (whichever user/role eventually runs `packer build`) needs a
    **least-privilege policy that must be reviewed before build authorization (PB-4)** —
    scoped to: the amazon-ebs builder EC2/AMI/snapshot lifecycle this config uses; the
    describe/discovery calls the source-AMI and vpc/subnet/sg filters make; **`iam:PassRole`
    restricted to `cloud-secops-lab-packer-build-ssm-role`**; SSM SSH-session use via the
    `AWS-StartSSHSession` document (`ssm:StartSession` + a clean `ssm:TerminateSession`);
    and `ec2:DescribeInstanceStatus` (Packer uses it when closing the Session Manager
    tunnel). **Not** `AdministratorAccess` or `ec2:*`. It is **not defined in this repo** —
    there is no designated caller principal in repository evidence. See
    [RUNBOOK.md](RUNBOOK.md) and [CURRENT_STATE.md](CURRENT_STATE.md) (PB-4).
  - The workstation running Packer needs Terraform, Packer, AWS CLI v2 and the **AWS
    Session Manager plugin** on PATH — verified present on the operator workstation
    (2026-09-06).
  - Implemented in code and **statically validated** — `terraform fmt/init/validate` and
    `packer fmt/init/validate` all pass locally; `terraform/packer-build/.terraform.lock.hcl`
    is present and intended for source control with the PB-1 commit. **Not yet applied or
    built** — no `terraform apply`, no `packer build`.
  - Evidence: [terraform/packer-build/](../terraform/packer-build/),
    [packer/wazuh-ami.pkr.hcl](../packer/wazuh-ami.pkr.hcl).
