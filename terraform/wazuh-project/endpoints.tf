# Create the S3 gateway Endpoint and associate it with the Route Table
resource "aws_vpc_endpoint" "s3_gateway" {
  vpc_id                    = aws_vpc.secops_lab_vpc
  service_name              = var.s3_prefix
  vpc_endpoint_type         = var.s3_vpc_endpoint_type 
  route_table_ids           = aws_route_table.private_1_rt

  tags = {
    Name = "s3-gateway-endpoint"
  }
}


# Create the SSM interface Endpoint

locals {
  ssm_services = [
    "com.amazonaws.us-east-1.ssm",      # 1. Core SSM functionality
    "com.amazonaws.us-east-1.ssmmessages", # 2. Required for interactive Session Manager shells
    "com.amazonaws.us-east-1.ec2messages" # 3. Required for core EC2-to-SSM agent communication
  ]
}
resource "aws_vpc_endpoint" "ssm_interfaces" {
    for_each                = toset(local.ssm_services)
    
    vpc_id                  = aws_vpc.secops_lab_vpc
    service_name            = each.value
    vpc_endpoint_type       = var.ssm_vpc_endpoint_type
}