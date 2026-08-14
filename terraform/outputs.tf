output "vpc_id" {
  description = "ID of the lab VPC"
  value       = aws_vpc.lab.id
}

output "subnet_id" {
  description = "ID of the lab subnet"
  value       = aws_subnet.lab.id
}

output "public_subnet_id" {
  description = "ID of the imported public subnet"
  value       = aws_subnet.imported.id
}

output "igw_id" {
  description = "ID of the internet gateway"
  value       = aws_internet_gateway.lab.id
}

output "nat_gateway_id" {
  description = "ID of the NAT gateway"
  value       = aws_nat_gateway.lab.id
}

output "nat_eip_id" {
  description = "Allocation ID of the NAT EIP"
  value       = aws_eip.nat.id
}

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "ID of the private route table"
  value       = aws_route_table.private.id
}

output "security_group_id" {
  description = "ID of the lab security group"
  value       = aws_security_group.lab.id
}

output "instance_id" {
  description = "ID of the test EC2 instance"
  value       = aws_instance.test.id
}

output "vpc2_id" {
  description = "ID of the second lab VPC (TGW peer)"
  value       = aws_vpc.vpc2.id
}

output "vpc2_subnet_id" {
  description = "ID of the second VPC's subnet"
  value       = aws_subnet.vpc2.id
}

output "tgw_id" {
  description = "ID of the transit gateway"
  value       = aws_ec2_transit_gateway.lab.id
}

output "tgw_attachment_vpc1_id" {
  description = "ID of the VPC1 TGW attachment"
  value       = aws_ec2_transit_gateway_vpc_attachment.vpc1.id
}

output "tgw_attachment_vpc2_id" {
  description = "ID of the VPC2 TGW attachment"
  value       = aws_ec2_transit_gateway_vpc_attachment.vpc2.id
}
