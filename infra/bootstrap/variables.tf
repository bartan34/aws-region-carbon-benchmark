variable "home_region" {
  description = "Region for the state bucket and the provider's global (IAM) calls"
  type        = string
  default     = "eu-west-1"
}

variable "project_tag" {
  description = "Value of the Project tag and prefix of every bucket the benchmark creates"
  type        = string
  default     = "carbon-bench"
}

variable "ec2_role_name" {
  description = "Instance role and profile name; launch.sh and infra/benchmark expect this name"
  type        = string
  default     = "carbon-bench-ec2-role"
}

variable "github_repo" {
  description = "owner/name of the repository whose main-branch workflows may assume the role"
  type        = string
  default     = "bartan34/aws-region-carbon-benchmark"
}

variable "allowed_regions" {
  description = "Regions the GitHub Actions role may launch EC2 in"
  type        = list(string)
  default     = ["us-east-1", "us-west-2", "eu-west-1", "eu-north-1", "ap-south-1"]
}

variable "allowed_instance_types" {
  description = "Instance types the GitHub Actions role may launch"
  type        = list(string)
  default     = ["m5.large", "m6i.large"]
}

variable "budget_email" {
  description = "If set, create a monthly cost budget that emails this address at 80%"
  type        = string
  default     = ""
}

variable "budget_usd" {
  description = "Monthly budget limit in USD"
  type        = string
  default     = "10"
}
