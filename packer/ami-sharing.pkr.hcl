############################################################
# Cross-account golden-AMI sharing (D-014 / D-015)
#
# The Wazuh base AMI is built and OWNED in the Security account. The disposable
# Wazuh runtime runs in the Lab account and launches from that AMI through an
# explicit launch-permission share (Packer `ami_users` / `snapshot_users` in
# packer/wazuh-ami.pkr.hcl). No copy is made into Lab; the AMI is never made
# public; no wildcard account sharing is used.
#
# lab_account_id is a true cross-account relationship, so it is an explicit
# REQUIRED input with NO default. It is non-secret account metadata (a 12-digit
# AWS account number), not a credential — but it is still not committed to
# source. Supply it at build time, e.g.:
#
#     export PKR_VAR_lab_account_id=<lab account id>
#     AWS_PROFILE=security packer build .
#
# `packer validate` also needs it set (any 12-digit value works for validation).
############################################################

variable "lab_account_id" {
  type        = string
  description = "AWS account ID of the Lab account that receives launch permission on the golden AMI. Required — no default. Non-secret account metadata; supply via PKR_VAR_lab_account_id."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.lab_account_id))
    error_message = "Lab account ID must be a 12-digit AWS account ID."
  }
}
