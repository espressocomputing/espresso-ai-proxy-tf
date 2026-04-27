output "iam_role_arn" {
  description = "IAM role ARN for External Secrets Operator IRSA"
  value       = module.this.iam_role_arn
}
