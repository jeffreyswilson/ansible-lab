resource "aws_vpc" "vpc2" {
  cidr_block           = var.vpc2_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "terraform-lab-vpc2"
  }
}

resource "aws_subnet" "vpc2" {
  vpc_id = aws_vpc.vpc2.id
  cidr_block = var.vpc2_subnet_cidr
  availability_zone = var.availability_zone

  tags = {
    Name = "terraform-lab-vpc2-subnet"
  }
}
