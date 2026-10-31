# Terraform and GitHub Actions path

The shell scripts (`scripts/launch.sh` …) and Terraform launch the same
instance with the same `scripts/user-data.sh`; pick either. Terraform adds
an explicit egress-only security group, an encrypted root volume, remote
state, and the GitHub Actions workflow.

```
infra/bootstrap/   once per account: state bucket, EC2 instance role, GitHub OIDC role, optional budget
infra/benchmark/   once per region per run: output bucket, security group, instance
.github/workflows/ benchmark.yml (run from the Actions tab), lint.yml (every push)
```

## 1. Bootstrap (once, with admin credentials)

```bash
cd infra/bootstrap
terraform init
# optional: echo 'budget_email = "you@example.com"' > terraform.tfvars
terraform apply
terraform output
```

State for this stack stays local (`terraform.tfstate`, gitignored): it
creates the bucket that holds every other state. Keep the file, or move it
into the bucket afterwards with a `backend "s3"` block and
`terraform init -migrate-state`.

If you already created the instance role by hand (`docs/iam-setup.md`),
import it instead of creating it:

```bash
terraform import aws_iam_role.ec2 carbon-bench-ec2-role
terraform import aws_iam_instance_profile.ec2 carbon-bench-ec2-role
terraform import aws_iam_role_policy.ec2_write_outputs carbon-bench-ec2-role:write-outputs
terraform import aws_iam_role_policy_attachment.ec2_ssm carbon-bench-ec2-role/arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
```

What the GitHub Actions role can do (`infra/bootstrap/iam-github.tf`):

- be assumed only by workflows on `main` of this repository, through
  GitHub's OIDC token: there is no access key anywhere;
- launch EC2 only in `allowed_regions`, only `allowed_instance_types`,
  and only with the `Project=carbon-bench` tag;
- terminate or modify only resources carrying that tag;
- pass only the benchmark instance role, to EC2 only;
- use S3 only on `carbon-bench-*` buckets and the `benchmark/` state prefix.

The trust condition matches the token's `sub` claim. This repository uses
GitHub's immutable subject format, which embeds the owner and repository
IDs (`repo:<owner>@<owner-id>/<name>@<repo-id>:ref:refs/heads/main`), so a
deleted and recreated repository of the same name does not match. For a
fork, set `github_subject_prefix` from
`gh api repos/<owner>/<name>/actions/oidc/customization/sub`.

The state bucket is named `tfstate-carbon-bench-<account>`, outside the
`carbon-bench-*` prefix the instance role may write to.

## 2. One region from your machine

```bash
cd infra/benchmark
cp backend.hcl.example backend.hcl    # fill in from bootstrap outputs
terraform init -backend-config=backend.hcl -backend-config="key=benchmark/eu-north-1.tfstate"
terraform apply -var region=eu-north-1
terraform output next_steps           # wait, pull metrics, destroy
```

Use a different `key` per region so regions apply and destroy
independently. Locking uses S3's native lock file (`use_lockfile`), so no
DynamoDB table is needed.

## 3. From GitHub Actions

Set three repository variables (Settings → Secrets and variables → Actions
→ Variables) from the bootstrap outputs: `AWS_ROLE_ARN`,
`TF_STATE_BUCKET`, `TF_STATE_REGION`. They are identifiers, not secrets.

Then Actions → benchmark → Run workflow, with a space-separated list of
regions. Per region the workflow applies, waits for the instance to upload
its outputs, pulls CloudWatch metrics, uploads the raw data as an artifact
and destroys everything (`if: always()`). A final job computes SCI and the
figures for that run only and uploads them as the `results` artifact.

Notes:

- A 5 × 600 s run keeps a runner busy for about 80 minutes per region.
  On a private repository that counts against the Actions minutes quota
  (2,000 free minutes per month on the Free plan); public repositories
  are not metered.
- AWS cost per region is about 1.2 instance-hours of m5.large plus
  negligible S3 and CloudWatch usage.
- The hourly grid view needs grid readings for the run window and is
  left empty for workflow runs; the annual and market-based views and
  cost are computed.
- If a job is cancelled hard enough that `destroy` does not run, the
  instance still terminates itself and `./scripts/cleanup.sh <region>
  --delete` removes the bucket and the security group.
