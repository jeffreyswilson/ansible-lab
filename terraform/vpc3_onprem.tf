variable "vpc3_cidr" {
  description = "CIDR for simulated on-prem VPC (Phase 4, deliberately outside TGW mesh)"
  type        = string
  default     = "10.50.0.0/16"
}

variable "vpc3_subnet_cidr" {
  description = "Public subnet CIDR for simulated on-prem VPC"
  type        = string
  default     = "10.50.1.0/24"
}

resource "aws_vpc" "onprem" {
  cidr_block           = var.vpc3_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "onprem-sim-vpc"
  }
}

resource "aws_subnet" "onprem_public" {
  vpc_id                  = aws_vpc.onprem.id
  cidr_block               = var.vpc3_subnet_cidr
  availability_zone        = var.availability_zone
  map_public_ip_on_launch  = true

  tags = {
    Name = "onprem-sim-public"
  }
}

resource "aws_internet_gateway" "onprem" {
  vpc_id = aws_vpc.onprem.id

  tags = {
    Name = "onprem-sim-igw"
  }
}

resource "aws_route_table" "onprem_public" {
  vpc_id = aws_vpc.onprem.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.onprem.id
  }

  tags = {
    Name = "onprem-sim-public-rt"
  }
}

resource "aws_route_table_association" "onprem_public" {
  subnet_id      = aws_subnet.onprem_public.id
  route_table_id = aws_route_table.onprem_public.id
}
