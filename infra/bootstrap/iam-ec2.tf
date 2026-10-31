# Instance role: write benchmark outputs to carbon-bench-* buckets, nothing else
# (plus SSM Session Manager for emergency access instead of SSH).
# Same policy as docs/iam-policy.json, which the CLI path uses.

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = var.ec2_role_name
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "ec2_write_outputs" {
  statement {
    sid       = "WriteBenchmarkOutputs"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.project_tag}-*/*"]
  }
}

resource "aws_iam_role_policy" "ec2_write_outputs" {
  name   = "write-outputs"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.ec2_write_outputs.json
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = var.ec2_role_name
  role = aws_iam_role.ec2.name
}
