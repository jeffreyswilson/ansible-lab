# vpc3_onprem_ec2.tf

#data "aws_ami" "al2023_onprem" {
#  most_recent = true
#  owners      = ["amazon"]
#
#  filter {
#    name   = "name"
#    values = ["al2023-ami-*-x86_64"]
#  }
#
#  filter {
#    name   = "virtualization-type"
#    values = ["hvm"]
#  }
#}

variable "onprem_key_name" {
  description = "EC2 key pair name for SSH access to the on-prem-sim instance (must pre-exist in AWS)"
  type        = string
}

resource "aws_instance" "onprem" {
  ami                         = data.aws_ami.al2023_onprem.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.onprem_public.id
  vpc_security_group_ids      = [aws_security_group.onprem.id]
  key_name                    = var.onprem_key_name
  associate_public_ip_address = true

  # Base strongSwan install only -- ipsec.conf/ipsec.secrets need
  # AWS-side values (tunnel outside IPs, PSKs) that don't exist until
  # the aws_vpn_connection resource (checklist step 2) is applied.
  # Config population is a post-VPN-creation step, not part of this apply.
  user_data = <<-EOF
    #!/bin/bash
    dnf install -y strongswan
    systemctl enable strongswan
  EOF

  tags = {
    Name = "onprem-sim-instance"
  }
}

output "onprem_public_ip" {
  value = aws_instance.onprem.public_ip
}
