output "state_bucket" {
  description = "Set as the TF_STATE_BUCKET repository variable"
  value       = aws_s3_bucket.state.bucket
}

output "state_region" {
  description = "Set as the TF_STATE_REGION repository variable"
  value       = var.home_region
}

output "github_role_arn" {
  description = "Set as the AWS_ROLE_ARN repository variable"
  value       = aws_iam_role.github.arn
}

output "ec2_instance_profile" {
  value = aws_iam_instance_profile.ec2.name
}
