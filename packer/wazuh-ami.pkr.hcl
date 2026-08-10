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
############################################################

source "amazon-ebs" "wazuh" {
  region        = var.aws_region
  instance_type = var.instance_type
  ssh_username  = "ubuntu"

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