variable "proxmox_node" {
  type    = string
  default = "proxmox"
}

variable "proxmox_token" {
  type        = string
  description = "proxmox api token"
}

variable "proxmox_endpoint" {
  type        = string
  description = "proxmox api endpoint"
}

variable "lxc_debian_template_url" {
  type        = string
  description = "Direct URL to the Debian 13 LXC template"
  default     = "http://download.proxmox.com/images/system/debian-13-standard_13.1-2_amd64.tar.zst"
}

variable "lxc_alpine_template_url" {
  type        = string
  description = "Direct URL to the Alpine LXC template"
  default     = "http://download.proxmox.com/images/system/alpine-3.24-default_20260714_amd64.tar.xz"
}

variable "vm_debian_image_url" {
  type        = string
  description = "Direct URL to the Debian VM image"
  default     = "https://cloud.debian.org/images/cloud/trixie/20261015-2632/debian-13-genericcloud-amd64-20261015-2632.qcow2"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for cloud-init VMs"
}
