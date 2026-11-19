provider "aws" {
  region = var.region

  # Plan-only mode. The brief allows a plan-only configuration, and this is the
  # one place it is needed: from provider v6 onwards the AWS provider calls
  # sts:GetCallerIdentity while configuring itself, so `terraform plan` fails
  # with InvalidClientTokenId before it ever looks at a resource unless real
  # credentials are present.
  #
  # With plan_only = true the provider skips that preflight, and the whole
  # configuration can be planned with no AWS account at all:
  #
  #   terraform plan -refresh=false -var plan_only=true
  #
  # It defaults to false, so a real apply still validates its credentials up
  # front rather than failing part-way through.
  skip_credentials_validation = var.plan_only
  skip_requesting_account_id  = var.plan_only
  skip_metadata_api_check     = var.plan_only

  # Applied to every resource that supports tagging, so individual modules only
  # have to add what is specific to them.
  default_tags {
    tags = local.common_tags
  }
}
