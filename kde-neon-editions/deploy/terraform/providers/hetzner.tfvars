# Hetzner Cloud — ISO builder
# Cheapest option for persistent build machines (~€4-14/mo)
#
# 1. Create API token: https://console.hetzner.cloud/projects → Security → API Tokens
# 2. Get runner token: https://gitlab.com/groups/openos-project/kde-ecosystem-deving/neon-deving/-/runners/new
# 3. cp providers/hetzner.tfvars ../terraform.tfvars
# 4. Fill in the two tokens below
# 5. terraform init && terraform apply

provider_name = "hetzner"

# Required — fill in
hetzner_token       = ""   # Hetzner Cloud API token
gitlab_runner_token = ""   # GitLab group runner token

# VM sizing — cx32 (4 vCPU / 8 GB / SSD) is the recommended minimum
# cx22 = 2 vCPU / 4 GB  ~€4/mo   (slow, not recommended)
# cx32 = 4 vCPU / 8 GB  ~€8/mo   (recommended)
# cx42 = 8 vCPU / 16 GB ~€14/mo  (for concurrent builds)
vm_cpu     = 4
vm_ram_gb  = 8
vm_disk_gb = 40

# Region — pick closest to your team
# nbg1 = Nuremberg, DE  |  fsn1 = Falkenstein, DE
# hel1 = Helsinki, FI   |  ash  = Ashburn, US  |  hil = Hillsboro, US
region = "nbg1"

# OS image — ubuntu-24.04 is the default, no need to change
vm_os_image = "ubuntu-24.04"

# Optional: SSH public key for emergency access
# ssh_public_key = "ssh-ed25519 AAAA..."

# Runner settings
runner_name       = ""   # leave blank to auto-generate from provider+region
runner_concurrent = 1    # increase if vm_cpu >= 8 and vm_disk_gb >= 80
runner_tags       = "privileged,iso-builder,neon"
gitlab_url        = "https://gitlab.com"
