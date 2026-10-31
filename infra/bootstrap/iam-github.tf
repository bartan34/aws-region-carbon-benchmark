# GitHub Actions -> AWS without stored access keys. The workflow exchanges its
# OIDC token for short-lived credentials of this role, and only workflows on the
# main branch of this repository can assume it.

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${var.github_subject_prefix}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github" {
  name                 = "${var.project_tag}-github-actions"
  assume_role_policy   = data.aws_iam_policy_document.github_assume.json
  max_session_duration = 4 * 3600 # a full 5-run benchmark takes ~75 min plus waits
}

# What a benchmark run needs, and no more:
# - EC2 only in allowed regions and only allowed instance types
# - create/delete only resources tagged Project=<project_tag>
# - S3 only on carbon-bench-* buckets and this project's state prefix
data "aws_iam_policy_document" "github_benchmark" {
  statement {
    sid       = "DenyOtherRegions"
    effect    = "Deny"
    actions   = ["ec2:*"]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = var.allowed_regions
    }
  }

  statement {
    sid       = "ReadOnly"
    actions   = ["ec2:Describe*", "cloudwatch:GetMetricStatistics"]
    resources = ["*"]
  }

  statement {
    sid       = "LaunchAllowedTypesTagged"
    actions   = ["ec2:RunInstances"]
    resources = ["arn:aws:ec2:*:${local.account_id}:instance/*"]
    condition {
      test     = "StringEquals"
      variable = "ec2:InstanceType"
      values   = var.allowed_instance_types
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_tag]
    }
  }

  statement {
    sid     = "LaunchSupportingResources"
    actions = ["ec2:RunInstances"]
    resources = [
      "arn:aws:ec2:*::image/*",
      "arn:aws:ec2:*:${local.account_id}:volume/*",
      "arn:aws:ec2:*:${local.account_id}:network-interface/*",
      "arn:aws:ec2:*:${local.account_id}:security-group/*",
      "arn:aws:ec2:*:${local.account_id}:subnet/*",
    ]
  }

  statement {
    sid       = "CreateSecurityGroupTagged"
    actions   = ["ec2:CreateSecurityGroup"]
    resources = ["arn:aws:ec2:*:${local.account_id}:security-group/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_tag]
    }
  }

  statement {
    sid       = "CreateSecurityGroupInVpc"
    actions   = ["ec2:CreateSecurityGroup"]
    resources = ["arn:aws:ec2:*:${local.account_id}:vpc/*"]
  }

  statement {
    sid       = "TagOnCreate"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:aws:ec2:*:${local.account_id}:*/*"]
    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["RunInstances", "CreateSecurityGroup"]
    }
  }

  statement {
    sid = "ManageOwnResources"
    actions = [
      "ec2:TerminateInstances",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["arn:aws:ec2:*:${local.account_id}:*/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_tag]
    }
  }

  statement {
    sid       = "PassInstanceRole"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.ec2.arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  statement {
    sid       = "ReadInstanceProfile"
    actions   = ["iam:GetInstanceProfile"]
    resources = [aws_iam_instance_profile.ec2.arn]
  }

  statement {
    sid       = "UbuntuAmiParameter"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["arn:aws:ssm:*::parameter/aws/service/canonical/*"]
  }

  statement {
    sid     = "OutputBuckets"
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::${var.project_tag}-*",
      "arn:aws:s3:::${var.project_tag}-*/*",
    ]
  }

  statement {
    sid       = "StateList"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["benchmark/*"]
    }
  }

  statement {
    sid       = "StateObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/benchmark/*"]
  }
}

resource "aws_iam_role_policy" "github_benchmark" {
  name   = "run-benchmark"
  role   = aws_iam_role.github.id
  policy = data.aws_iam_policy_document.github_benchmark.json
}
