# One benchmark instance in one region: the Terraform equivalent of
# scripts/launch.sh, running the same scripts/user-data.sh. One state file per
# region (and per run), so regions apply and destroy independently.
#
#   terraform init -backend-config=backend.hcl -backend-config="key=benchmark/eu-north-1.tfstate"
#   terraform apply -var region=eu-north-1

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
  backend "s3" {
    use_lockfile = true # S3-native locking, no DynamoDB table
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = var.project_tag
      ManagedBy = "terraform"
    }
  }
}

data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

data "aws_vpc" "default" {
  default = true
}

resource "random_id" "suffix" {
  byte_length = 2
}

# --- outputs bucket (same region, so no cross-region data movement) ------------

resource "aws_s3_bucket" "outputs" {
  bucket        = "${var.project_tag}-${var.region}-${random_id.suffix.hex}"
  force_destroy = true # raw outputs are pulled into the repo before destroy
}

resource "aws_s3_bucket_public_access_block" "outputs" {
  bucket                  = aws_s3_bucket.outputs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- network: outbound only (apt, S3, SSM); nothing can connect in -------------

resource "aws_security_group" "bench" {
  name        = "${var.project_tag}-${random_id.suffix.hex}"
  description = "carbon-bench instance: egress only"
  vpc_id      = data.aws_vpc.default.id

  egress {
    description = "package install, S3 upload, SSM"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- the benchmark instance ---------------------------------------------------------

locals {
  # user-data.sh uses __X__ placeholders (shared with launch.sh), not ${} templating
  user_data = replace(replace(replace(replace(replace(replace(replace(
    file("${path.module}/../../scripts/user-data.sh"),
    "__REGION__", var.region),
    "__BUCKET__", aws_s3_bucket.outputs.bucket),
    "__RUNS__", tostring(var.runs)),
    "__RUN_SECONDS__", tostring(var.run_seconds)),
    "__IDLE_SECONDS__", tostring(var.idle_seconds)),
    "__THREADS__", tostring(var.threads)),
  "__MAX_PRIME__", tostring(var.max_prime))
}

resource "aws_instance" "bench" {
  ami                    = data.aws_ssm_parameter.ubuntu.insecure_value
  instance_type          = var.instance_type
  iam_instance_profile   = var.instance_profile
  vpc_security_group_ids = [aws_security_group.bench.id]
  monitoring             = true # 1-minute CloudWatch metrics

  # The instance shuts itself down after uploading; shutdown means terminate.
  instance_initiated_shutdown_behavior = "terminate"

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only
  }

  root_block_device {
    encrypted             = true
    delete_on_termination = true
  }

  user_data                   = local.user_data
  user_data_replace_on_change = true

  tags = {
    Name = "${var.project_tag}-${var.region}"
  }

  depends_on = [aws_s3_bucket_public_access_block.outputs]
}
