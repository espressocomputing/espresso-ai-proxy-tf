output "iam_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller IRSA"
  value       = module.this.iam_role_arn
}
