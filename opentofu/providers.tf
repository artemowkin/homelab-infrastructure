provider "proxmox" {
  insecure  = true
  api_token = var.proxmox_token
  endpoint  = var.proxmox_endpoint
}
