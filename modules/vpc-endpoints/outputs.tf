output "endpoints_security_group_id" {
  description = "ID of the security group fronting the interface VPC endpoints (pool nodes reach this on 443)"
  value       = aws_security_group.endpoints.id
}

output "interface_endpoint_ids" {
  description = "Map of interface endpoint short service name to endpoint ID"
  value       = { for svc, ep in aws_vpc_endpoint.interface : svc => ep.id }
}

output "s3_gateway_endpoint_id" {
  description = "ID of the S3 gateway endpoint"
  value       = aws_vpc_endpoint.s3.id
}
