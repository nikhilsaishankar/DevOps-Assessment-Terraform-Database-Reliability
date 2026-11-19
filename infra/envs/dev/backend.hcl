# Remote state for dev. Used with:
#
#   terraform init -backend-config=backend.hcl
#
# Create the bucket and lock table first with infra/bootstrap (see README).
bucket       = "hotelbook-tfstate-dev-ap-south-1"
key          = "envs/dev/terraform.tfstate"
region       = "ap-south-1"
encrypt      = true
use_lockfile = true
