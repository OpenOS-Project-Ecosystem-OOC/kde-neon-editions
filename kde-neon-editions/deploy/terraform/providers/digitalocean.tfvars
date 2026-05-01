# DigitalOcean — ISO builder
#
# 1. Create token: https://cloud.digitalocean.com/account/api/tokens
# 2. Get runner token: https://gitlab.com/groups/openos-project/kde-ecosystem-deving/neon-deving/-/runners/new
# 3. cp providers/digitalocean.tfvars ../terraform.tfvars
# 4. Fill in the two tokens below
# 5. terraform init && terraform apply

provider_name = "digitalocean"

# Required — fill in
digitalocean_token  = ""   # DigitalOcean personal access token
gitlab_runner_token = ""   # GitLab group runner token

# VM sizing — s-4vcpu-8gb is the recommended minimum
# s-2vcpu-4gb  = ~$24/mo  (slow, not recommended)
# s-4vcpu-8gb  = ~$48/mo  (recommended)
# s-8vcpu-16gb = ~$96/mo  (for concurrent builds)
vm_cpu     = 4
vm_ram_gb  = 8
vm_disk_gb = 40   # note: DO droplet disk is fixed by size slug, this sets the volume if added

# Region
# nyc3 = New York  |  sfo3 = San Francisco  |  ams3 = Amsterdam
# sgp1 = Singapore |  lon1 = London         |  fra1 = Frankfurt
region = "nyc3"

# OS image slug
vm_os_image = "ubuntu-24-04-x64"

# Optional: SSH public key for emergency access
# ssh_public_key = "ssh-ed25519 AAAA..."

# Runner settings
runner_name       = ""
runner_concurrent = 1
runner_tags       = "privileged,iso-builder,neon"
gitlab_url        = "https://gitlab.com"
