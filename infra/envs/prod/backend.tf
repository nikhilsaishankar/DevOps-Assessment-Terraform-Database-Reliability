###############################################################################
# Backend state configuration
#
# The S3 backend below is left commented out on purpose, so that a reviewer can
# run the exact commands in the brief
#
#   terraform fmt && terraform init && terraform validate && terraform plan
#
# with no AWS account, no state bucket and no credentials. With no backend
# block, Terraform uses the local backend and init succeeds offline.
#
# To use real remote state, uncomment the block and initialise with the
# per-environment settings in backend.hcl (bucket, key, region, locking):
#
#   terraform init -backend-config=backend.hcl
#
# The bucket and the DynamoDB-free S3 native lock are created by
# infra/bootstrap, which keeps its own state locally and is applied once per
# account. Each environment has its own bucket and its own state key, so dev
# and prod can never write to the same object.
#
# terraform {
#   backend "s3" {}
# }
###############################################################################
