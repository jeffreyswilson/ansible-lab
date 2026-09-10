# phase4_vpn_cgw.tf

resource "aws_customer_gateway" "onprem" {
  bgp_asn    = 65000 # placeholder -- unused with static_routes_only, required by schema regardless
  ip_address = aws_instance.onprem.public_ip
  type       = "ipsec.1"

  tags = {
    Name = "onprem-sim-cgw"
  }
}

resource "aws_vpn_connection" "onprem" {
  customer_gateway_id = aws_customer_gateway.onprem.id
  transit_gateway_id  = aws_ec2_transit_gateway.lab.id
  type                = "ipsec.1"
  static_routes_only  = true

  tags = {
    Name = "onprem-sim-vpn"
  }
}

resource "aws_ec2_transit_gateway_route" "onprem" {
  destination_cidr_block        = var.vpc3_cidr
  transit_gateway_attachment_id = aws_vpn_connection.onprem.transit_gateway_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.lab.id
}

resource "aws_ec2_transit_gateway_route_table_association" "onprem" {
  transit_gateway_attachment_id  = aws_vpn_connection.onprem.transit_gateway_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.lab.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "onprem" {
  transit_gateway_attachment_id  = aws_vpn_connection.onprem.transit_gateway_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.lab.id
}

resource "aws_route" "private_to_onprem" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = var.vpc3_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.lab.id
}
