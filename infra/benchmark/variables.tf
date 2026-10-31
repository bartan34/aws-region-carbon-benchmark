variable "region" {
  description = "AWS region to benchmark; must be listed in data/coefficients/regions.csv for the analysis"
  type        = string
}

variable "instance_type" {
  description = "Instance type; needs a power curve in data/coefficients/power.csv"
  type        = string
  default     = "m5.large"
}

variable "runs" {
  description = "Number of benchmark runs"
  type        = number
  default     = 5
}

variable "run_seconds" {
  description = "Length of each run in seconds"
  type        = number
  default     = 600
}

variable "idle_seconds" {
  description = "Idle baseline before the runs, in seconds"
  type        = number
  default     = 600
}

variable "threads" {
  description = "sysbench threads (one per vCPU)"
  type        = number
  default     = 2
}

variable "max_prime" {
  description = "sysbench --cpu-max-prime"
  type        = number
  default     = 20000
}

variable "instance_profile" {
  description = "Instance profile created by infra/bootstrap (or docs/iam-setup.md)"
  type        = string
  default     = "carbon-bench-ec2-role"
}

variable "project_tag" {
  description = "Project tag and bucket prefix; must match infra/bootstrap"
  type        = string
  default     = "carbon-bench"
}
