resource "aws_ecr_repository" "wazuh_manager" {
  name                 = "${var.project_name}/wazuh-manager"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project = var.project_name
  }
}

resource "aws_ecr_repository" "wazuh_indexer" {
  name                 = "${var.project_name}/wazuh-indexer"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project = var.project_name
  }
}

resource "aws_ecr_repository" "wazuh_dashboard" {
  name                 = "${var.project_name}/wazuh-dashboard"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project = var.project_name
  }
}