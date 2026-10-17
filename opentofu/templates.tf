locals {
  lxc_templates = {
    debian = {
      file_name = "debian-13-standard_13.1-2_amd64.tar.zst"
      os_type   = "debian"
      url       = var.lxc_debian_template_url
    }

    alpine = {
      file_name = "alpine-3.24-default_20260714_amd64.tar.xz"
      os_type   = "alpine"
      url       = var.lxc_alpine_template_url
    }
  }

  vm_images = {
    debian_13 = {
      file_name = "debian-13-genericcloud-amd64.qcow2"
      url       = var.vm_debian_image_url
    }
  }
}

resource "proxmox_download_file" "lxc_template" {
  for_each = local.lxc_templates

  node_name    = var.proxmox_node
  datastore_id = "local"
  content_type = "vztmpl"

  file_name = each.value.file_name
  url       = each.value.url

  overwrite           = false
  overwrite_unmanaged = false

  lifecycle {
    prevent_destroy = true

    ignore_changes = [
      url
    ]
  }
}

resource "proxmox_download_file" "vm_image" {
  for_each = local.vm_images

  node_name    = var.proxmox_node
  datastore_id = "local"
  content_type = "import"

  file_name = each.value.file_name
  url       = each.value.url

  overwrite           = false
  overwrite_unmanaged = false

  lifecycle {
    prevent_destroy = true

    ignore_changes = [
      url
    ]
  }
}
