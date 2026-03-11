output "fqdn" {
  description = "FQDN of the created Route53 record"
  value       = try(aws_route53_record.this[0].fqdn, null)
}
