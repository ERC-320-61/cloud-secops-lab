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

## D-007 — Multi-account transition point (superseded by D-014)

- **Status:** Superseded by **D-014** (2026-09-08)
- **Context:** The charter describes a management / security / lab account model. When this
  entry was written the repository proved only that the Phase 1 implementation was
  single-account, and it did not establish *when* the project should move.
- **Original decision (proposed, not settled):** stay single-account through the Phase 1
  Wazuh repair; treat multi-account as target architecture; do not pull an Organizations
  refactor into the near-term work; leave the transition phase open.
- **Why superseded:** the Management / Security / Lab accounts and their IAM Identity Center
  permission sets now exist, and the project has accepted the concrete placement of every
  CloudGuard component across them. **D-014** records that model and the migration sequence.
- **Consequences:** the "Open decision — multi-account transition point" is closed. The
  remaining Phase 1 runtime work (B2/B3, hardening, first runtime apply) now happens in the
  three-account layout.

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
- **Pinned Wazuh version (2026-09-08):** **4.14.7**. This is the version the B2 image mirror
  and the B3 artifact set target. (It matches the version the original `cca2387`
  `install-wazuh.sh` used; the pin is now a deliberate choice, not carried over by
  accident.) The base AMI stays version-independent (D-011); the version lives only in the
  runtime/artifact layer.
- **Consequences:** The architecture is accepted but the **implementation is incomplete** —
  it requires a working ECR image publish/mirror workflow and an S3 artifact publish
  workflow plus a checked-in Wazuh artifact set at 4.14.7 (hard blockers B2/B3 in
  [CURRENT_STATE.md](CURRENT_STATE.md)). The persistent destinations now live in their own
  Security-account root ([terraform/wazuh-artifacts/](../terraform/wazuh-artifacts/), D-016),
  which resolves the "separate lifecycle/state" question; publication **ordering** vs. the
  runtime apply is still tracked in [CURRENT_STATE.md](CURRENT_STATE.md) → Open Decisions.
  Evidence: [terraform/wazuh-artifacts/ecr.tf](../terraform/wazuh-artifacts/ecr.tf),
  [scripts/install-wazuh.sh.tftpl](../terraform/wazuh-project/scripts/install-wazuh.sh.tftpl).

---

## D-010 — Artifact bucket encryption: SSE-S3 + TLS for Phase 1; CMK deferred

- **Status:** Accepted (2026-09-08) — the resolution is carried and restated in **D-016**
- **Decision:** The persistent Wazuh artifact bucket uses **SSE-S3 (AES256)** at rest and a
  bucket policy that **denies any request with `aws:SecureTransport = false`** (TLS enforced
  in transit). A customer-managed KMS key (SSE-KMS / CMK) is **deferred** as a later
  hardening exercise.
- **Rationale:** The bucket holds non-secret Wazuh Compose/config, not credentials or
  findings data. SSE-S3 + enforced TLS is adequate for Phase 1 and has no key management or
  key charges. A CMK becomes relevant only if the bucket must enforce key-policy-based
  cross-account access, or when Phase 2 central/cross-account logging sets its own
  encryption requirements — at which point a superseding decision is expected.
- **Consequences:** Implemented in the new artifact root
  [terraform/wazuh-artifacts/storage.tf](../terraform/wazuh-artifacts/storage.tf)
  (`aws_s3_bucket_server_side_encryption_configuration` + `aws_s3_bucket_policy` deny-non-TLS).
  The legacy bucket definition in
  [terraform/wazuh-project/storage.tf](../terraform/wazuh-project/storage.tf) has SSE-S3 but
  **no** TLS-deny policy yet; it is superseded (D-016) and slated for removal.

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
- **Validated (2026-09-07):** the first successful build + AMI smoke test confirmed the base
  image carries exactly the intended host prerequisites (Docker 29.8.0, Docker Compose
  v5.5.1, AWS CLI v2.36.40, `vm.max_map_count = 262144`, Docker enabled, `ubuntu` in the
  `docker` group, `amazon-ssm-agent` enabled + active) and no Wazuh deployment state.

---

## D-012 — Persistent dedicated Packer build network; ephemeral builder via SSM

- **Status:** Accepted
- **Resolves:** pre-build item **PB-1** (temporary-builder networking) — **COMPLETE**:
  implemented, locally validated, `terraform apply`-d, and exercised by a successful
  `packer build`.
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
    second Terraform root. (A **third** root for the persistent ECR/S3 artifact layer was
    later justified on the same lifecycle grounds plus cross-account ownership — see
    **D-016**.)
- **Account placement (D-014):** this root belongs in the **Security** account. Bootstrap
  apply uses the `security-admin` permission set; routine builds run as `security`
  (CloudGuardOperator). The code is account-agnostic (account discovered at apply time), so
  the migration is "apply it in Security, then destroy the legacy copy in Management" — no
  code change. The historical build that produced `ami-0b1bf8942dfc0daf1` ran against the
  **Management-account** copy and is validation evidence only.
- **Consequences:**
  - `terraform/packer-build/` must be `terraform apply`-d before the first `packer build`.
  - The Packer **caller** runs as a dedicated least-privilege execution role — see **D-013**
    (PB-4, COMPLETE). It is scoped to: the amazon-ebs builder EC2/AMI lifecycle this config
    uses; the describe/discovery calls the source-AMI and vpc/subnet/sg filters make;
    **`iam:PassRole` restricted to `cloud-secops-lab-packer-build-ssm-role`**; SSM session
    use for the tunnel via the `AWS-StartPortForwardingSession` and `AWS-StartSSHSession`
    documents. **Not** `AdministratorAccess` or `ec2:*`.
  - The workstation running Packer needs Terraform, Packer, AWS CLI v2 and the **AWS
    Session Manager plugin** on PATH — verified present on the operator workstation
    (2026-09-06).
  - `terraform/packer-build/.terraform.lock.hcl` is committed. The build network is
    **applied** in AWS and a successful `packer build` used it end-to-end (VPC/subnet/SG
    selected by tag, ephemeral builder launched, reached over Session Manager, AMI produced,
    builder + key pair cleaned up).
  - Evidence: [terraform/packer-build/](../terraform/packer-build/),
    [packer/wazuh-ami.pkr.hcl](../packer/wazuh-ami.pkr.hcl).

---

## D-013 — Least-privilege IAM identity for running Packer (PB-4)

- **Status:** Accepted
- **Resolves:** pre-build item **PB-4** (least-privilege Packer execution IAM) —
  **COMPLETE**: implemented, `terraform apply`-d, and validated by a successful `packer build`
  that ran entirely through the assumed execution role (the first build exposed exactly one
  missing entry — `ssm:StartSession` on `AWS-StartPortForwardingSession` — which was added
  narrowly).
- **Context:** Human access to the CloudGuard AWS account is via **IAM Identity Center**
  (instance in `us-east-2`). The normal CLI identity is the **`CloudGuardOperator`**
  permission set, which resolves to an `AWSReservedSSO_CloudGuardOperator_<suffix>` role
  whose suffix is regenerated on every permission-set re-provisioning. Packer needs more
  than SSM but far less than the operator's day-to-day access, and the credentials it uses
  must be attributable and bounded. No AWS account ID is committed to source — Terraform
  discovers it (`data.aws_caller_identity`).
- **Decision:**
  - **Access model:**

    | Layer | Identity (Security account — D-014) |
    | --- | --- |
    | Human access | IAM Identity Center |
    | Normal CloudGuard access | `security` permission set → `CloudGuardOperator` |
    | Privileged build workflow | `CloudGuardOperator` → `cloud-secops-lab-packer-execution-role` |
    | Bootstrap administration | `security-admin` permission set (AdministratorAccess in Security) — deliberate, one-off use only |

  - **`cloud-secops-lab-packer-execution-role`** (new, in
    [terraform/packer-build/packer-execution-role.tf](../terraform/packer-build/packer-execution-role.tf))
    is the identity `packer build` assumes. Its **trust policy** uses the AWS-recommended
    resilient Identity Center pattern: `Principal` = `arn:aws:iam::<account>:root` (account
    from `data.aws_caller_identity.current.account_id`) with a `Condition ArnLike` on
    `aws:PrincipalArn` matching
    `…:role/aws-reserved/sso.amazonaws.com/<identity_center_region>/AWSReservedSSO_<operator_permission_set_name>_*`.
    The generated suffix is **never hard-coded**; the account ID is **discovered at apply
    time** (no account ID in source); `identity_center_region` and
    `operator_permission_set_name` are Terraform variables (defaults `us-east-2` /
    `CloudGuardOperator`). It does **not** trust arbitrary users, `AdministratorAccess`, all
    account roles, or external accounts.
  - Its **inline permission policy** is derived from the actual `amazon-ebs` config
    ([packer/wazuh-ami.pkr.hcl](../packer/wazuh-ami.pkr.hcl)) — EC2 discovery, one-builder
    lifecycle, EBS-AMI creation, a temporary SSH key pair, `iam:PassRole` **only** on
    `cloud-secops-lab-packer-build-ssm-role` (`iam:PassedToService = ec2.amazonaws.com`),
    `iam:GetInstanceProfile` on the builder profile, SSM SSH-session actions, and — added
    for **D-015** — `ec2:ModifyImageAttribute` + `ec2:ModifySnapshotAttribute` scoped to
    this region's `image/*` and `snapshot/*` (the launch-permission share to Lab; these
    cannot make an image or snapshot public). **Not** granted: `ec2:*`, security-group
    create/modify/authorize, spot/fleet, KMS, ECR/S3 application access, Security
    Hub/GuardDuty, Terraform-management, AMI copy/deregister, or IAM role create/delete.
    Full action list in [CURRENT_STATE.md](CURRENT_STATE.md) PB-4.
  - **The builder instance role** (`cloud-secops-lab-packer-build-ssm-role`,
    `AmazonSSMManagedInstanceCore` only) stays **separate** from the execution role.
  - **Packer wiring:** `packer/wazuh-ami.pkr.hcl` has an `assume_role` block referencing
    `var.packer_execution_role_arn`, which is **required and has no default** — the operator
    supplies it from the Terraform output
    (`PKR_VAR_packer_execution_role_arn="$(terraform -chdir=terraform/packer-build output -raw packer_execution_role_arn)"`).
    Base credentials come from the operator's Security-account profile
    (`AWS_PROFILE=security` / active SSO session for the `security` permission set). A second
    required var, `lab_account_id`, carries the Lab account id for the AMI share (D-015). No
    keys, secrets, usernames, or account IDs are embedded.
- **Bootstrap boundary:** the execution role has **no** permission to create or modify its
  own IAM role, or the build VPC / subnet / IGW / SG / route table. `terraform apply` of
  `terraform/packer-build/` (which creates all of that, including the execution role) is
  bootstrap infrastructure and may be run deliberately with the `security-admin` permission
  set (AdministratorAccess in the Security account — D-014). After that, normal Packer
  execution uses the dedicated role. This task does **not** create a general
  Terraform-execution role.
- **Consequences:** Implemented / **AWS-applied** / **validated by a successful build**.
  The first build reached the SSM tunnel and showed Packer's `session_manager` interface
  opens the tunnel with **`AWS-StartPortForwardingSession`** (not `AWS-StartSSHSession`);
  `ssm:StartSession` now allows that document (both are kept, scoped to the builder instance
  + the two named documents). A subsequent build ran end-to-end through the assumed role and
  produced a validated AMI. If the Packer config later changes (new source options, new
  interface), re-derive: add only the specific denied action per real `AccessDenied` — never
  widen to `ssm:*` / `ec2:*` / all documents.
- **Evidence:**
  [terraform/packer-build/packer-execution-role.tf](../terraform/packer-build/packer-execution-role.tf),
  [terraform/packer-build/variables.tf](../terraform/packer-build/variables.tf),
  [packer/build-identity.pkr.hcl](../packer/build-identity.pkr.hcl),
  [packer/wazuh-ami.pkr.hcl](../packer/wazuh-ami.pkr.hcl).

---

## D-014 — Adopt the three-account model (Management / Security / Lab)

- **Status:** Accepted (2026-09-08) — supersedes **D-007**
- **Context:** The charter always described a Management / Security / Lab account model as
  the target. That model is now real: the three accounts exist under AWS Organizations, and
  IAM Identity Center (in Management) provisions permission sets into each. CloudGuard has
  outgrown the single-account placement — the persistent Packer build infrastructure and a
  validated base AMI currently sit in the Management account, which is the wrong home for
  workload/security tooling.
- **Decision — component placement:**

  | Account | Owns |
  | --- | --- |
  | **Management** | AWS Organizations, IAM Identity Center, billing / cost / governance. **No** normal workload or security tooling after migration. (It temporarily still holds the legacy Packer build infrastructure and the historical AMI until the migration retires them.) |
  | **Security** | Persistent Packer build infrastructure (`terraform/packer-build/`) and the Packer execution role; **owner of the golden Wazuh AMI**; persistent Wazuh artifact layer (`terraform/wazuh-artifacts/` — ECR + S3, D-016); future centralized security tooling (CloudTrail, Security Hub, GuardDuty, ingestion + response pipelines, central logging). |
  | **Lab** | Disposable Wazuh runtime (`terraform/wazuh-project/`); security-test workloads and Wazuh agents; SprintOps Tracker dev/test. |

- **Decision — access model (IAM Identity Center permission sets):**

  | Account | Permission sets |
  | --- | --- |
  | Management | `cloudguard-admin` → AdministratorAccess |
  | Security | `security-admin` → AdministratorAccess · `security` → `CloudGuardOperator` |
  | Lab | `lab-admin` → AdministratorAccess · `lab` → `LabOperator` |

  Routine Packer runs use `security`; bootstrap/`terraform apply` of the Security roots uses
  `security-admin`; the Lab runtime uses `lab-admin` (or a dedicated runtime execution role
  later).
- **Decision — Terraform code stays account-agnostic.** No account IDs are committed. Each
  root discovers its account at apply time (`data.aws_caller_identity`); "which account"
  is chosen entirely by which profile/permission set runs the apply. The one genuine
  cross-account value — the Lab account ID for AMI sharing — is an explicit required Packer
  variable with no default (`PKR_VAR_lab_account_id`), documented as non-secret account
  metadata (**D-015**).
- **Migration sequence:**
  1. Apply `terraform/packer-build/` in **Security** (`security-admin`). — **Done** (operator-reported, 2026-09-16)
  2. Build and validate a **new** Security-owned base AMI (`security`, Packer assumes the
     execution role). — **Done** (operator-reported)
  3. Share that AMI to **Lab** by launch permission (**D-015**). — **Done** (operator-reported)
  4. Confirm Lab can launch the shared AMI (and SSM smoke test). — **Done** (operator-reported)
  5. Destroy the **legacy** Packer build infrastructure in **Management**. — Planned
  6. Apply `terraform/wazuh-artifacts/` in **Security** (`security-admin`). — Planned
  7. Continue B3 (artifact set + S3 publish) and B2 (ECR image mirror). — Planned
  8. Deploy the disposable Wazuh runtime in **Lab**. — Planned
- **Current reality (2026-09-16):** per the operator, steps 1–4 above have run: the Packer
  build infrastructure is applied in **Security**, a new Security-owned golden AMI has been
  built + validated, shared to **Lab**, and confirmed launchable there with a passing SSM
  smoke test. This entry records that as reported — **this repository pass made no AWS
  calls and captured no independent evidence** (no AMI id / account id recorded here). The
  historical AMI (`ami-0b1bf8942dfc0daf1`) and the legacy Packer build infrastructure remain
  in **Management** pending step 5. **`terraform/wazuh-artifacts/` and
  `terraform/wazuh-project/` are still not applied anywhere** (steps 6–8).
- **Consequences:** [ARCHITECTURE.md](ARCHITECTURE.md) target account model moves from
  Planned to Accepted (migration pending). [PROJECT_CHARTER.md](PROJECT_CHARTER.md) target
  account model is updated. The multi-account transition is now Phase 1 work, tracked in
  [CURRENT_STATE.md](CURRENT_STATE.md) and [ROADMAP.md](ROADMAP.md). D-007's open decision is
  closed.

---

## D-015 — Golden AMI owned by Security, shared to Lab by launch permission

- **Status:** Accepted (2026-09-08)
- **Context:** The base AMI is built in the Security account (D-014). The disposable Wazuh
  runtime runs in the Lab account and must launch from that AMI. The options were: (a) copy
  the AMI into Lab, (b) make the AMI public, (c) share launch permission with the specific
  Lab account.
- **Decision:**
  - The **Security account owns** the AMI. **Lab receives launch permission only** — no
    copy into Lab in this work, the AMI is **never made public**, and **no wildcard account
    sharing** is used.
  - Sharing is done with the **supported Packer `amazon-ebs` mechanism**:
    `ami_users = [var.lab_account_id]` and `snapshot_users = [var.lab_account_id]` in
    [packer/wazuh-ami.pkr.hcl](../packer/wazuh-ami.pkr.hcl). AWS requires **both** the AMI
    launch permission and the backing-snapshot `createVolumePermission` for another account
    to launch an EBS-backed AMI it does not own; `snapshot_users` covers the latter. This is
    not "making the snapshot public" — it is a named-account grant.
  - `lab_account_id` is a **required Packer variable with no default**
    ([packer/ami-sharing.pkr.hcl](../packer/ami-sharing.pkr.hcl)), supplied via
    `PKR_VAR_lab_account_id`. It is **non-secret account metadata** (a 12-digit account
    number), but is still not committed to source.
  - A Terraform-managed `aws_ami_launch_permission` step was **rejected**: it would have to
    reference a Packer-built AMI id, coupling Terraform state to a Packer artifact — the
    fragile coupling the design avoids. Packer already owns the AMI lifecycle, so the share
    belongs there.
  - The Packer execution role (D-013) gains exactly two narrowly scoped actions —
    `ec2:ModifyImageAttribute` and `ec2:ModifySnapshotAttribute` on this region's
    `image/*` / `snapshot/*` — which is the whole mechanism and cannot publish or copy.
- **EBS snapshot / KMS implications:**
  - The AMI boot volume is **unencrypted today** (no `encrypt_boot` / `kms_key_id`), so
    cross-account launch works with the snapshot `createVolumePermission` grant alone — **no
    KMS is involved**.
  - **If boot-volume encryption is added later**, cross-account launch additionally requires
    a **customer-managed KMS key** shared with the Lab account (the default `aws/ebs` key
    **cannot** be shared). Introducing that CMK is **deferred** — out of scope here, and not
    added unless/until boot encryption is adopted.
- **Consequences:** `packer build` in Security now needs `PKR_VAR_lab_account_id` set (and
  `packer validate` needs any 12-digit value). The first cross-account build is the real
  test of the two new IAM actions; if it surfaces one more required describe permission
  (e.g. `ec2:DescribeImageAttribute`), add **only** that one, per the D-013 rule. Evidence:
  [packer/wazuh-ami.pkr.hcl](../packer/wazuh-ami.pkr.hcl),
  [packer/ami-sharing.pkr.hcl](../packer/ami-sharing.pkr.hcl),
  [terraform/packer-build/packer-execution-role.tf](../terraform/packer-build/packer-execution-role.tf).

---

## D-016 — Persistent Wazuh artifact infrastructure is its own Terraform root in Security

- **Status:** Accepted (2026-09-08)
- **Resolves:** the former open decision "does the artifact/bootstrap infrastructure need a
  separate Terraform lifecycle/state from the ephemeral runtime?" (**yes**), and narrows the
  artifact-persistence-vs-`terraform destroy` question — see
  [CURRENT_STATE.md](CURRENT_STATE.md) → Open decisions.
- **Context:** The ECR repositories and the S3 artifact bucket were defined inside
  `terraform/wazuh-project/` — the same root/state as the disposable VPC/EC2 — so a plain
  `terraform destroy` of a validation session would take the registry and bucket (and any
  images/artifacts) with it. They are also now Security-account-owned (D-014) while the
  runtime is Lab-account-owned, so they cannot stay in the same root.
- **Decision:**
  - A **third Terraform root**, [terraform/wazuh-artifacts/](../terraform/wazuh-artifacts/),
    owns the **persistent** artifact layer in the **Security** account: the three private
    ECR repositories (`wazuh-manager` / `wazuh-indexer` / `wazuh-dashboard`, `IMMUTABLE`
    tags, scan-on-push) and the S3 artifact/config bucket (block-public-access, SSE-S3,
    bucket policy denying non-TLS — D-010). Tags: `Project = cloud-secops-lab`,
    `Purpose = wazuh-artifacts`. Region `us-east-2`. Separate state from
    `terraform/wazuh-project/`.
  - This root is **persistent** — it is **not** part of the runtime
    deploy → test → validate → destroy cycle (like `terraform/packer-build/`, D-012).
  - **Scope is the persistent infrastructure only.** It deliberately does **not** contain
    the B2 image-mirror workflow, the B3 Wazuh Compose/config artifact set, certificate
    generation, runtime bootstrap, runtime EC2, or any Security Hub / EventBridge wiring.
  - The **legacy** `ecr.tf` / `storage.tf` in `terraform/wazuh-project/` are **removed**
    (superseded by this root — see **D-017**). An unrelated stash ("preserve ecr comment
    changes") still modifies the now-deleted `ecr.tf`; it was left untouched (not popped,
    applied, or dropped) — popping it later will conflict on a deleted file, which is
    expected. See [CURRENT_STATE.md](CURRENT_STATE.md).
  - Cross-account access (an ECR repository policy and an S3 bucket policy letting the Lab
    runtime pull images / read config) is now **implemented in code** — see **D-017**. It
    has not been applied.
- **Relationship to D-008:** the third root is justified by the same materially-different
  lifecycle argument as D-012, plus cross-account ownership. Not speculative abstraction.
- **Consequences:** the runbook gains a "apply `terraform/wazuh-artifacts/` in Security"
  step. `terraform/wazuh-project/` no longer owns the ECR/S3 resources it used to — see
  **D-017**. Evidence: [terraform/wazuh-artifacts/](../terraform/wazuh-artifacts/).

---

## D-017 — Lab consumes Security-owned ECR/S3 via explicit variables + narrow resource-based cross-account grants

- **Status:** Accepted (2026-09-16); **IAM ownership and apply ordering revised by D-018**
  (same day) — the Lab EC2 role moved out of `terraform/wazuh-project/` into a new
  persistent root, and the two-pass apply this entry describes is **no longer the design**.
  This entry is kept for the record of *why* explicit variables replace resource ownership
  and *why* `data.aws_caller_identity` is avoided — both of those points still hold. Read
  D-018 for the current apply order and IAM ownership.
- **Context:** D-016 moved the persistent ECR repositories and S3 bucket to
  `terraform/wazuh-artifacts/` in **Security**, but left the original resource definitions in
  `terraform/wazuh-project/` (Lab) untouched, and left cross-account pull/read access
  unimplemented. Two problems needed closing: (1) `terraform/wazuh-project/` still *owned*
  (would re-create) ECR repos and a bucket it should only *consume*; (2) even with the
  resources correctly owned by Security, cross-account access requires an explicit grant on
  **both** sides (the caller's identity-based policy AND the resource's resource-based
  policy) — neither existed.
- **Decision — `terraform/wazuh-project/` no longer owns these resources:**
  - `ecr.tf` and `storage.tf` (and the `aws_s3_bucket_public_access_block` /
    `aws_s3_bucket_server_side_encryption_configuration` resources in the latter) are
    **removed** from this root.
  - Three explicit, required (no-default) variables replace them:
    `wazuh_ecr_registry` (string — the Security ECR registry hostname, format-validated),
    `wazuh_ecr_repository_arns` (map(string), exactly 3 entries — the Security repository
    ARNs), `wazuh_artifact_bucket_name` (string — the Security bucket name). Each is sourced
    from the corresponding `terraform/wazuh-artifacts/` output; **none is discovered via
    `data.aws_caller_identity`**, which would resolve to Lab's own account, not Security's.
  - [roles.tf](../terraform/wazuh-project/roles.tf)'s ECR-pull and S3-read identity policies
    now reference these variables (`values(var.wazuh_ecr_repository_arns)`,
    `arn:aws:s3:::${var.wazuh_artifact_bucket_name}`) instead of local resource references.
    `ecr:GetAuthorizationToken` stays `Resource = "*"` — an unavoidable AWS API constraint
    (it is always an account-local call; the resulting token is then used to authenticate
    against Security's registry, authorized by the resource-based policy below), not a
    broadening.
  - ~~A new output, `wazuh_runtime_role_arn`, exposes the Lab EC2 role's ARN~~ — **superseded
    by D-018**: this root no longer creates that role at all, so it has no such output any
    more (see D-018 for where the role lives now).
- ~~**Decision — narrow, conditional cross-account grants in `terraform/wazuh-artifacts/`**~~
  **— superseded by D-018.** The original design gated the grant on an optional, default-null
  `lab_runtime_role_arn` and required re-applying `terraform/wazuh-artifacts/` after
  `terraform/wazuh-project/` created the role (a **two-pass apply** with a circular
  dependency between the two roots). D-018 replaced this with a required variable and a
  single, unconditional grant — read that entry for the current mechanism.
- **Rejected alternative (at the time):** deriving the ECR ARNs / registry from a
  `security_account_id` variable plus the repo-naming convention already used in
  `terraform/wazuh-artifacts/ecr.tf`. Rejected for *this* direction (Lab consuming Security's
  outputs) because passing the real outputs is more explicit and cannot silently drift — that
  reasoning still holds for `wazuh_ecr_registry` / `wazuh_artifact_bucket_name`. D-018 later
  accepted the same deterministic-construction pattern for a *different* purpose (breaking
  the circular dependency in the other direction) — see that entry for why the trade-off
  differs there.
- **AMI boundary unaffected.** No Wazuh application state was added to
  [packer/scripts/install-wazuh-base.sh](../packer/scripts/install-wazuh-base.sh) or
  `packer/wazuh-ami.pkr.hcl`; D-011 still holds.
- **Consequences (as later amended by D-018):** `terraform/wazuh-project/` requires
  `wazuh_ecr_registry` and `wazuh_artifact_bucket_name` (no longer
  `wazuh_ecr_repository_arns` — that scoping moved to the identity root) on every apply.
  **Implemented in code only.** Evidence:
  [terraform/wazuh-project/variables.tf](../terraform/wazuh-project/variables.tf),
  [terraform/wazuh-project/outputs.tf](../terraform/wazuh-project/outputs.tf),
  [terraform/wazuh-artifacts/variables.tf](../terraform/wazuh-artifacts/variables.tf),
  [terraform/wazuh-artifacts/ecr.tf](../terraform/wazuh-artifacts/ecr.tf),
  [terraform/wazuh-artifacts/storage.tf](../terraform/wazuh-artifacts/storage.tf),
  [terraform/wazuh-artifacts/outputs.tf](../terraform/wazuh-artifacts/outputs.tf).

---

## D-018 — Break the wazuh-artifacts ↔ wazuh-project circular dependency with a persistent Lab identity root

- **Status:** Accepted (2026-09-16)
- **Context:** D-017 left a genuine circular Terraform dependency: `terraform/wazuh-artifacts/`
  (Security) needed the Lab runtime role's ARN to grant it cross-account access, but that
  role was created by `terraform/wazuh-project/` (Lab), which in turn needed
  `terraform/wazuh-artifacts/`'s outputs (registry, bucket) to configure the runtime. Neither
  root could be applied first without the other having already run — hence the two-pass
  apply D-017 described (apply artifacts → apply runtime → re-apply artifacts). This is not
  an acceptable long-term shape: it is fragile (any redeploy of the disposable runtime that
  recreates the role invalidates the grant until re-applied) and it obscures the real
  dependency direction.
- **Decision — split the IAM identity into its own persistent root:**
  - A **fourth Terraform root**, [terraform/wazuh-runtime-identity/](../terraform/wazuh-runtime-identity/),
    owns the Wazuh EC2's `aws_iam_role` and `aws_iam_instance_profile` — moved out of
    `terraform/wazuh-project/`, which no longer creates any IAM role (**do not duplicate the
    role in both places**).
  - It is **persistent**, applied in the **Lab** account, and — unlike the disposable
    runtime — is **not** part of the deploy → test → validate → destroy cycle (D-006): the
    identity, and Security's grant to it, survive redeploying the disposable runtime.
  - Its own least-privilege ECR-pull / S3-read inline policy is built **deterministically**
    from an explicit, required, format-validated `security_account_id` variable (the same
    kind of non-secret, explicit account-id pattern already used as `lab_account_id` for the
    AMI share, D-015) plus the **known, shared naming convention** already fixed in
    `terraform/wazuh-artifacts/ecr.tf` / `storage.tf` (`"${project_name}/<repo>"` for ECR
    repos, `"${project_name}-artifacts-${account_id}"` for the bucket) — **not** from a live
    `terraform/wazuh-artifacts/` output. This is the one deliberate exception to D-017's
    "pass real outputs, don't derive from naming convention" preference: deriving is the
    only way to give this root zero Terraform dependency on `wazuh-artifacts`, which is the
    entire point. The coupling is explicit, commented in both roots' code, and scoped to
    exactly 3 repository names + 1 bucket-naming pattern — a small, reviewable surface.
- **Decision — accepted dependency order (one-directional):**

  ```
  1. terraform/wazuh-runtime-identity/   (Lab, persistent)     — creates the role + profile
  2. terraform/wazuh-artifacts/          (Security, persistent) — grants that role ARN
                                                                    cross-account access,
                                                                    single apply, no re-apply
  3. terraform/wazuh-project/            (Lab, disposable)      — consumes both: the
                                                                    instance profile (root 1)
                                                                    and the registry/bucket
                                                                    (root 2)
  ```

  No root depends on one applied *after* it. `terraform/wazuh-artifacts/`'s
  `lab_runtime_role_arn` variable is now **required, no default** (it is always safe to
  require — the role always exists by the time this root is applied) and its
  `aws_ecr_repository_policy` / `aws_s3_bucket_policy` Lab-read statements are now
  **unconditional** (no more `var.lab_runtime_role_arn != null ? ... : ...`).
- **Decision — `terraform/wazuh-project/` consumes, never creates, the identity:** a new
  required variable, `wazuh_runtime_instance_profile_name` (from
  `terraform/wazuh-runtime-identity/` output `wazuh_runtime_instance_profile_name`), is used
  directly as `aws_instance.wazuh`'s `iam_instance_profile`. The `wazuh_ecr_repository_arns`
  variable D-017 added to this root is **removed** — no longer needed here, since this root
  creates no IAM policy any more.
- **Rejected alternative:** keep the role in `terraform/wazuh-project/` and have
  `terraform/wazuh-artifacts/` construct its ARN deterministically too (skip the identity
  root entirely). Rejected because the role would still be re-created (and briefly not exist)
  on every disposable-runtime redeploy, so `terraform/wazuh-artifacts/`'s grant would still
  need to reference a role whose lifecycle it doesn't control — the *dependency* would be
  one-directional but the *identity's lifecycle* would still be wrong (tied to disposable
  infrastructure). Separating it into its own persistent root fixes both problems at once.
- **Least privilege preserved.** No permission was broadened to make this work: the ECR-pull
  and S3-read grants are exactly as narrow as under D-017 (3 named repos, one bucket prefix),
  just computed differently and owned by a different root.
- **AMI boundary unaffected.** No Wazuh application state was added to
  [packer/scripts/install-wazuh-base.sh](../packer/scripts/install-wazuh-base.sh) or
  `packer/wazuh-ami.pkr.hcl`; D-011 still holds. Wazuh stays pinned to **4.14.7** (D-009).
- **Consequences:** one more persistent root to track (justified per D-008/D-012/D-016 by a
  materially different lifecycle — identity outlives the disposable runtime). RUNBOOK.md's
  migration section is rewritten to the 3-step order above; no step re-applies a root it
  already applied. **Implemented in code only — no root has been applied under this
  decision.** Evidence: [terraform/wazuh-runtime-identity/](../terraform/wazuh-runtime-identity/),
  [terraform/wazuh-artifacts/variables.tf](../terraform/wazuh-artifacts/variables.tf),
  [terraform/wazuh-artifacts/ecr.tf](../terraform/wazuh-artifacts/ecr.tf),
  [terraform/wazuh-artifacts/storage.tf](../terraform/wazuh-artifacts/storage.tf),
  [terraform/wazuh-project/variables.tf](../terraform/wazuh-project/variables.tf),
  [terraform/wazuh-project/ec2.tf](../terraform/wazuh-project/ec2.tf).

---

## D-019 — Wazuh runtime EC2 hardening: dedicated SG, encrypted gp3 root volume, IMDSv2, outputs

- **Status:** Accepted (2026-09-16)
- **Context:** the Phase 1 completion gaps tracked in [CURRENT_STATE.md](CURRENT_STATE.md)
  included: the Wazuh EC2 had no dedicated security group (so it would have used the VPC's
  default SG), no explicit root volume (AMI default size/type, not necessarily encrypted by
  policy), no IMDSv2 enforcement, and no useful Terraform outputs.
- **Decision:**
  - **Dedicated security group** ([terraform/wazuh-project/security.tf](../terraform/wazuh-project/security.tf)):
    **zero ingress** rules (administration is SSM-only, D-001 — the SSM agent initiates
    outbound; no inbound rule is needed). Egress limited to exactly two purposes: HTTPS to
    the VPC interface endpoints via an SG-to-SG rule referencing
    `aws_security_group.vpc_endpoints`, and HTTPS to the S3 gateway endpoint via its prefix
    list (`aws_vpc_endpoint.s3_gateway.prefix_list_id`) — gateway endpoints have no ENI/SG,
    so a prefix-list rule is the correct mechanism, not a CIDR or SG rule. No `0.0.0.0/0`
    egress; this VPC has no IGW/NAT (D-002) so nothing else is reachable anyway, but the
    explicit scoping documents intent.
  - **No public IP:** `associate_public_ip_address = false` set explicitly on the instance
    (the subnet already defaults to no auto-assigned public IPs; this makes the intent
    explicit rather than implicit).
  - **IMDSv2 required:** `metadata_options { http_tokens = "required", http_put_response_hop_limit = 1 }`,
    matching the pattern already used for the Packer builder
    ([packer/wazuh-ami.pkr.hcl](../packer/wazuh-ami.pkr.hcl)).
  - **Encrypted gp3 root volume:** `root_block_device { volume_type = "gp3", volume_size = 50, encrypted = true }`.
    50 GB is a reference size (manager + indexer), not a hard requirement — the historical
    ~50 GB note in [ARCHITECTURE.md](ARCHITECTURE.md) is now backed by an explicit block
    instead of relying on the AMI's default size. Encryption uses the default AWS-managed
    key — no CMK introduced (matches the D-015 EBS/KMS deferral: no customer-managed key
    until there is a concrete reason).
  - **Outputs:** [terraform/wazuh-project/outputs.tf](../terraform/wazuh-project/outputs.tf)
    now exposes `instance_id`, `ssm_start_session_command` (ready to paste), and
    `security_group_id`.
- **Consequences:** closes the "EC2 hardening" and "useful runtime outputs" Phase 1
  completion gaps in [CURRENT_STATE.md](CURRENT_STATE.md). Root volume sizing remains a
  judgment call to revisit once real indexer storage behavior is observed.
  **Implemented in code only — not applied.**
