# Remote state for prod. Used with:
#
#   terraform init -backend-config=backend.hcl
#
# Kept in a different bucket from dev so that a dev credential cannot read or
# corrupt production state.
bucket       = "hotelbook-tfstate-prod-ap-south-1"
key          = "envs/prod/terraform.tfstate"
region       = "ap-south-1"
encrypt      = true
use_lockfile = true
