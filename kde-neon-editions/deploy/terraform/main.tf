# main.tf — KDE Neon ISO builder VM
#
# Provisions a single VM on the selected cloud provider, injects cloud-init
# user-data that installs live-build and registers a GitLab runner on boot.
#
# Usage:
#   cp providers/hetzner.tfvars terraform.tfvars   # or digitalocean / aws
#   # edit terraform.tfvars — fill in tokens and runner token
#   terraform init
#   terraform apply
#
# The runner appears in GitLab within ~5 minutes of apply completing.
# Destroy when not needed: terraform destroy

terraform {
  required_version = ">= 1.3"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.36"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ── Cloud-init user-data (rendered from template) ─────────────────────────────

locals {
  runner_name = var.runner_name != "" ? var.runner_name : "${var.provider_name}-${var.region != "" ? var.region : "default"}-iso-builder"

  user_data = templatefile("${path.module}/../cloud-init/user-data.yaml", {
    GITLAB_RUNNER_TOKEN = var.gitlab_runner_token
    RUNNER_NAME         = local.runner_name
    GITLAB_URL          = var.gitlab_url
    RUNNER_CONCURRENT   = tostring(var.runner_concurrent)
    RUNNER_TAGS         = var.runner_tags
  })
}

# ── Hetzner Cloud ─────────────────────────────────────────────────────────────

provider "hcloud" {
  token = var.hetzner_token
}

resource "hcloud_ssh_key" "iso_builder" {
  count      = var.provider_name == "hetzner" && var.ssh_public_key != "" ? 1 : 0
  name       = "${local.runner_name}-key"
  public_key = var.ssh_public_key
}

resource "hcloud_server" "iso_builder" {
  count       = var.provider_name == "hetzner" ? 1 : 0
  name        = local.runner_name
  server_type = local.hetzner_type
  image       = var.vm_os_image != "" ? var.vm_os_image : "ubuntu-24.04"
  location    = var.region != "" ? var.region : "nbg1"
  user_data   = local.user_data

  ssh_keys = var.ssh_public_key != "" ? [hcloud_ssh_key.iso_builder[0].id] : []

  labels = {
    role    = "iso-builder"
    project = "kde-neon"
  }

  lifecycle {
    ignore_changes = [user_data]  # don't reprovision on token rotation
  }
}

locals {
  # Map requested CPU/RAM to nearest Hetzner server type
  hetzner_type = (
    var.vm_cpu >= 8 && var.vm_ram_gb >= 16 ? "cx42" :
    var.vm_cpu >= 4 && var.vm_ram_gb >= 8  ? "cx32" :
    "cx22"  # 2 vCPU / 4 GB — minimum, may be slow
  )
}

# ── DigitalOcean ──────────────────────────────────────────────────────────────

provider "digitalocean" {
  token = var.digitalocean_token
}

resource "digitalocean_ssh_key" "iso_builder" {
  count      = var.provider_name == "digitalocean" && var.ssh_public_key != "" ? 1 : 0
  name       = "${local.runner_name}-key"
  public_key = var.ssh_public_key
}

resource "digitalocean_droplet" "iso_builder" {
  count     = var.provider_name == "digitalocean" ? 1 : 0
  name      = local.runner_name
  size      = local.do_size
  image     = var.vm_os_image != "" ? var.vm_os_image : "ubuntu-24-04-x64"
  region    = var.region != "" ? var.region : "nyc3"
  user_data = local.user_data

  ssh_keys = var.ssh_public_key != "" ? [digitalocean_ssh_key.iso_builder[0].fingerprint] : []

  tags = ["iso-builder", "kde-neon"]
}

locals {
  # Map requested CPU/RAM to nearest DigitalOcean droplet size
  do_size = (
    var.vm_cpu >= 8 && var.vm_ram_gb >= 16 ? "s-8vcpu-16gb" :
    var.vm_cpu >= 4 && var.vm_ram_gb >= 8  ? "s-4vcpu-8gb" :
    "s-2vcpu-4gb"
  )
}

# ── AWS EC2 ───────────────────────────────────────────────────────────────────

provider "aws" {
  region     = var.region != "" ? var.region : "eu-west-1"
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

data "aws_ami" "ubuntu" {
  count       = var.provider_name == "aws" ? 1 : 0
  most_recent = true
  owners      = ["099720109477"]  # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "iso_builder" {
  count      = var.provider_name == "aws" && var.ssh_public_key != "" ? 1 : 0
  key_name   = "${local.runner_name}-key"
  public_key = var.ssh_public_key
}

resource "aws_instance" "iso_builder" {
  count         = var.provider_name == "aws" ? 1 : 0
  ami           = var.vm_os_image != "" ? var.vm_os_image : data.aws_ami.ubuntu[0].id
  instance_type = local.aws_instance_type
  user_data     = local.user_data
  key_name      = var.ssh_public_key != "" ? aws_key_pair.iso_builder[0].key_name : null

  root_block_device {
    volume_size = var.vm_disk_gb
    volume_type = "gp3"
  }

  tags = {
    Name    = local.runner_name
    Role    = "iso-builder"
    Project = "kde-neon"
  }
}

locals {
  aws_instance_type = (
    var.vm_cpu >= 8 && var.vm_ram_gb >= 16 ? "t3.2xlarge" :
    var.vm_cpu >= 4 && var.vm_ram_gb >= 8  ? "t3.xlarge" :
    "t3.large"
  )
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "vm_ip" {
  description = "Public IP of the provisioned ISO builder VM"
  value = (
    var.provider_name == "hetzner"      ? (length(hcloud_server.iso_builder) > 0 ? hcloud_server.iso_builder[0].ipv4_address : "") :
    var.provider_name == "digitalocean" ? (length(digitalocean_droplet.iso_builder) > 0 ? digitalocean_droplet.iso_builder[0].ipv4_address : "") :
    var.provider_name == "aws"          ? (length(aws_instance.iso_builder) > 0 ? aws_instance.iso_builder[0].public_ip : "") :
    "n/a"
  )
}

output "runner_name" {
  description = "Runner name as it will appear in GitLab"
  value       = local.runner_name
}

output "gitlab_runners_url" {
  description = "URL to verify the runner appeared in GitLab"
  value       = "${var.gitlab_url}/groups/openos-project/kde-ecosystem-deving/neon-deving/-/runners"
}
