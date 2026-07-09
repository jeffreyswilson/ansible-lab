terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "lab" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = "terraform-lab-vpc"
  }
}

resource "aws_subnet" "lab" {
  vpc_id            = aws_vpc.lab.id
  cidr_block        = var.subnet_cidr
  availability_zone = var.availability_zone

  tags = {
    Name = "terraform-lab-subnet"
  }
}

resource "aws_subnet" "imported" {
  vpc_id            = aws_vpc.lab.id
  cidr_block        = "10.100.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "terraform-lab-subnet-imported"
  }
}
