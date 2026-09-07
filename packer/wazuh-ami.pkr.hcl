############################################################
# Configure the Amazon plugin required for building AWS AMIs
############################################################

packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
  }
}


############################################################
# Define the temporary EC2 build instance and resulting Wazuh AMI
#
# Builder networking (PB-1, decided — docs/DECISIONS.md D-012):
#   - The builder runs in the dedicated PERSISTENT build network defined by
#     `terraform/packer-build/` (apply that root before `packer build`).
#   - It is located by DETERMINISTIC tag filters — Project + Purpose identify the
#     packer-build lifecycle boundary and a resource-specific Name pins each
#     lookup to one resource. No generated vpc-/subnet-/sg- IDs in source
#     control. Fail-closed: the Amazon builder errors if a filter matches more
#     than one resource (subnet_filter has no most_free / random fallback).
#   - The build subnet does not auto-assign public IPs; this builder
#     explicitly opts in (`associate_public_ip_address = true`) for outbound
#     access to the Docker repo and the AWS CLI v2 installer. No NAT Gateway.
#   - No inbound access: the builder SG has zero ingress. Packer reaches the
#     builder through AWS Systems Manager Session Manager
#     (`ssh_interface = "session_manager"`), which tunnels the SSH communicator.
#   - IMDSv2 is required on the temporary builder.
############################################################

source "amazon-ebs" "wazuh" {
  region        = var.aws_region
  instance_type = var.instance_type
  ssh_username  = "ubuntu"

  # Start from the operator's normal credentials (an active CloudGuardOperator
  # IAM Identity Center session — e.g. AWS_PROFILE=cloudguard), then assume the
  # dedicated least-privilege execution role (terraform/packer-build/, PB-4) for
  # every AWS operation. No keys or human usernames are embedded. See
  # packer/build-identity.pkr.hcl and docs/DECISIONS.md D-013.
  assume_role {
    role_arn     = var.packer_execution_role_arn
    session_name = "cloudguard-packer-build"
  }

  ami_name = "cloud-secops-wazuh-{{timestamp}}"

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-*-24.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }

    owners      = ["099720109477"]
    most_recent = true
  }

  # Persistent build network from terraform/packer-build/, located by
  # deterministic tag filters. Keep these values in sync with that root's
  # locals (common_tags + name_vpc / name_subnet / name_sg). Fail-closed: each
  # filter must resolve to exactly one resource or the build errors.
  vpc_filter {
    filters = {
      "tag:Project" = "cloud-secops-lab"
      "tag:Purpose" = "packer-build"
      "tag:Name"    = "cloud-secops-lab-packer-build-vpc"
    }
  }

  # No most_free / random: this architecture defines one build subnet, so a
  # filter matching more than one must fail rather than pick one.
  subnet_filter {
    filters = {
      "tag:Project" = "cloud-secops-lab"
      "tag:Purpose" = "packer-build"
      "tag:Name"    = "cloud-secops-lab-packer-build-subnet"
    }
  }

  security_group_filter {
    filters = {
      "tag:Project" = "cloud-secops-lab"
      "tag:Purpose" = "packer-build"
      "tag:Name"    = "cloud-secops-lab-packer-build-sg"
    }
  }

  iam_instance_profile        = "cloud-secops-lab-packer-build-ssm-profile"
  associate_public_ip_address = true

  # Reach the builder over SSM Session Manager, not public SSH. The SSH
  # communicator is retained; Packer tunnels it through Session Manager.
  communicator  = "ssh"
  ssh_interface = "session_manager"

  # Require IMDSv2 on the temporary builder.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name    = "cloud-secops-wazuh-base"
    Project = "cloud-secops-lab"
    BuiltBy = "Packer"
  }
}


############################################################
# Build the Wazuh AMI and run the base installation script with root privileges
############################################################

build {
  sources = [
    "source.amazon-ebs.wazuh"
  ]

  provisioner "shell" {
    script          = "scripts/install-wazuh-base.sh"
    execute_command = "sudo -E bash '{{ .Path }}'"
  }
}