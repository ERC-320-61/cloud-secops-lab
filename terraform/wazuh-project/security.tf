############################################################
# Dedicated security group for the Wazuh EC2 instance
#
# Private-only, SSM-administered runtime (D-001):
#   - Ingress: NONE. No public IP (see ec2.tf), no bastion, no inbound SSH.
#     Session Manager needs no inbound rule — the SSM agent initiates
#     outbound connections to the ssm/ssmmessages/ec2messages endpoints.
#   - Egress: limited to exactly what this instance needs to reach inside the
#     VPC — the interface endpoints (SG-to-SG rule, matching the pattern in
#     terraform/packer-build/network.tf) and the S3 gateway endpoint (which has
#     no ENI/SG of its own, so it is referenced by its prefix list instead).
#     No 0.0.0.0/0 egress: this root has no IGW/NAT (D-002), so a broader rule
#     would not reach anywhere additional — but scoping it explicitly documents
#     intent and survives that changing later.
############################################################

resource "aws_security_group" "wazuh_ec2" {
  name        = "${var.project_name}-wazuh-ec2-sg"
  description = "Wazuh EC2: no ingress (SSM-only administration); egress limited to the VPC endpoints"
  vpc_id      = aws_vpc.secops_lab_vpc.id

  egress {
    description     = "HTTPS to the VPC interface endpoints (ssm, ssmmessages, ec2messages, ecr.api, ecr.dkr)"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.vpc_endpoints.id]
  }

  egress {
    description     = "HTTPS to the S3 gateway endpoint (prefix-list based; gateway endpoints have no ENI/SG)"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [aws_vpc_endpoint.s3_gateway.prefix_list_id]
  }

  tags = {
    Name    = "${var.project_name}-wazuh-ec2-sg"
    Project = var.project_name
  }
}
