resource "aws_ec2_transit_gateway_route_table" "lab" {
  transit_gateway_id = aws_ec2_transit_gateway.lab.id

  tags = {
    Name = "terraform-lab-tgw-rt"
  }
}

resource "aws_ec2_transit_gateway_route_table_association" "vpc1" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.vpc1.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.lab.id
}

resource "aws_ec2_transit_gateway_route_table_association" "vpc2" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.vpc2.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.lab.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "vpc1" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.vpc1.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.lab.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "vpc2" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.vpc2.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.lab.id
}

resource "aws_route" "private_to_vpc2" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = var.vpc2_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.lab.id
}

resource "aws_route_table" "vpc2" {
  vpc_id = aws_vpc.vpc2.id

  route {
    cidr_block = var.vpc_cidr
    transit_gateway_id = aws_ec2_transit_gateway.lab.id
  }

  tags = {
    Name = "terraform-lab-vpc2-rt"
  }
}

resource "aws_route_table_association" "vpc2" {
  subnet_id = aws_subnet.vpc2.id
  route_table_id = aws_route_table.vpc2.id
}
