# vpc3_onprem_sg.tf

resource "aws_security_group" "onprem" {
  name        = "onprem-sim-sg"
  description = "strongSwan on-prem simulation -- IPsec + admin access"
  vpc_id      = aws_vpc.onprem.id

  # IKE (phase 1/2 negotiation)
  ingress {
    description = "IKE from AWS VPN endpoints"
    from_port   = 500
    to_port     = 500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # IKE NAT-T (also carries ESP when NAT-T is in play)
  ingress {
    description = "IKE NAT-T from AWS VPN endpoints"
    from_port   = 4500
    to_port     = 4500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ESP (protocol 50) -- used only when NAT-T is NOT negotiated
  ingress {
    description = "ESP from AWS VPN endpoints"
    protocol    = "50"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Admin access, restricted to your current IP
  ingress {
    description = "SSH from admin IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.my_ip.response_body)}/32"]
  }

  egress {
    description = "all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "onprem-sim-sg"
  }
}
