# AWS EC2 — ISO builder
# Use spot instances to reduce cost (~70-90% cheaper than on-demand)
#
# 1. Create IAM user with EC2 permissions, generate access keys
# 2. Get runner token: https://gitlab.com/groups/openos-project/kde-ecosystem-deving/neon-deving/-/runners/new
# 3. cp providers/aws.tfvars ../terraform.tfvars
# 4. Fill in credentials below
# 5. terraform init && terraform apply

provider_name = "aws"

# Required — fill in
aws_access_key      = ""   # IAM access key ID
aws_secret_key      = ""   # IAM secret access key
gitlab_runner_token = ""   # GitLab group runner token

# VM sizing — t3.xlarge is the recommended minimum
# t3.large   = 2 vCPU / 8 GB   ~$0.083/hr on-demand
# t3.xlarge  = 4 vCPU / 16 GB  ~$0.166/hr on-demand  (recommended)
# t3.2xlarge = 8 vCPU / 32 GB  ~$0.333/hr on-demand
vm_cpu     = 4
vm_ram_gb  = 16
vm_disk_gb = 40

# Region
# eu-west-1 = Ireland  |  us-east-1 = N. Virginia  |  us-west-2 = Oregon
# ap-southeast-1 = Singapore  |  eu-central-1 = Frankfurt
region = "eu-west-1"

# OS image — leave blank to auto-select latest Ubuntu 24.04 LTS AMI
vm_os_image = ""

# Optional: SSH public key for emergency access
# ssh_public_key = "ssh-ed25519 AAAA..."

# Runner settings
runner_name       = ""
runner_concurrent = 1
runner_tags       = "privileged,iso-builder,neon"
gitlab_url        = "https://gitlab.com"
