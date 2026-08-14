resource "aws_ec2_transit_gateway" "lab" {
  description                     = "AWS Tier 1 lab TGW"
  amazon_side_asn                 = 64512
  auto_accept_shared_attachments  = "disable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = {
    Name = "terraform-lab-tgw"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "vpc1" {
  transit_gateway_id = aws_ec2_transit_gateway.lab.id
  vpc_id             = aws_vpc.lab.id
  subnet_ids         = [aws_subnet.lab.id]

  tags = {
    Name = "tgw-attach-vpc1"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "vpc2" {
  transit_gateway_id = aws_ec2_transit_gateway.lab.id
  vpc_id             = aws_vpc.vpc2.id
  subnet_ids         = [aws_subnet.vpc2.id]

  tags = {
    Name = "tgw-attach-vpc2"
  }
}
