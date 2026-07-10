variable "vpc_cidr" {
  description = "CIDR block for the lab VPC"
  type        = string
  default     = "10.100.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the lab subnet"
  type        = string
  default     = "10.100.1.0/24"
}

variable "availability_zone" {
  description = "AZ for the lab subnet"
  type        = string
  default     = "us-east-1a"
}

variable "import_cidr" {
  description = "CIDR block for the import lab subnet"
  type        = string
  default     = "10.100.2.0/24"
}
