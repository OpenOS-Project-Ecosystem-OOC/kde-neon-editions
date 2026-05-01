# variables.tf — inputs shared across all provider backends

# ── GitLab ────────────────────────────────────────────────────────────────────

variable "gitlab_runner_token" {
  description = "GitLab group runner authentication token. Get from: https://gitlab.com/groups/openos-project/kde-ecosystem-deving/neon-deving/-/runners/new"
  type        = string
  sensitive   = true
}

variable "gitlab_url" {
  description = "GitLab instance URL"
  type        = string
  default     = "https://gitlab.com"
}

variable "runner_name" {
  description = "Runner description shown in GitLab UI. Defaults to provider+region."
  type        = string
  default     = ""
}

variable "runner_concurrent" {
  description = "Number of concurrent ISO builds on this machine"
  type        = number
  default     = 1
}

variable "runner_tags" {
  description = "Comma-separated GitLab runner tags"
  type        = string
  default     = "privileged,iso-builder,neon"
}

# ── VM sizing ─────────────────────────────────────────────────────────────────

variable "vm_cpu" {
  description = "vCPU count (minimum 4 for live-build)"
  type        = number
  default     = 4
}

variable "vm_ram_gb" {
  description = "RAM in GB (minimum 8)"
  type        = number
  default     = 8
}

variable "vm_disk_gb" {
  description = "Root disk in GB (minimum 40 per concurrent build)"
  type        = number
  default     = 40
}

variable "vm_os_image" {
  description = "OS image slug/ID. Must be Ubuntu 22.04+ or Debian 12+. Provider-specific."
  type        = string
  default     = ""  # each provider tfvars sets a sensible default
}

# ── Network / access ──────────────────────────────────────────────────────────

variable "ssh_public_key" {
  description = "SSH public key to install on the VM for emergency access. Optional."
  type        = string
  default     = ""
}

variable "region" {
  description = "Cloud region. Provider-specific (e.g. nbg1, nyc3, eu-west-1)."
  type        = string
  default     = ""
}

# ── Provider selection ────────────────────────────────────────────────────────

variable "provider_name" {
  description = "Cloud provider backend: hetzner | digitalocean | aws | generic"
  type        = string
  default     = "hetzner"

  validation {
    condition     = contains(["hetzner", "digitalocean", "aws", "generic"], var.provider_name)
    error_message = "provider_name must be one of: hetzner, digitalocean, aws, generic"
  }
}

# ── Provider credentials (only the selected provider needs values) ────────────

variable "hetzner_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
  default     = ""
}

variable "digitalocean_token" {
  description = "DigitalOcean personal access token"
  type        = string
  sensitive   = true
  default     = ""
}

variable "aws_access_key" {
  description = "AWS access key ID"
  type        = string
  sensitive   = true
  default     = ""
}

variable "aws_secret_key" {
  description = "AWS secret access key"
  type        = string
  sensitive   = true
  default     = ""
}
