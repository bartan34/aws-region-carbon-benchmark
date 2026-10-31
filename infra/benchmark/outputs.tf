output "region" {
  value = var.region
}

output "instance_id" {
  value = aws_instance.bench.id
}

output "bucket" {
  value = aws_s3_bucket.outputs.bucket
}

output "next_steps" {
  value = <<-EOT
    ./scripts/wait-done.sh ${var.region} ${aws_instance.bench.id} ${aws_s3_bucket.outputs.bucket}
    ./scripts/pull-cloudwatch.sh ${var.region} ${aws_instance.bench.id} ${aws_s3_bucket.outputs.bucket}
    terraform destroy -var region=${var.region}
  EOT
}
