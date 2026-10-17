resource "proxmox_virtual_environment_container" "lxc" {
  for_each = local.containers

  node_name = var.proxmox_node
  vm_id     = each.value.vm_id

  started       = true
  start_on_boot = true
  unprivileged  = true

  tags = try(each.value.tags, [])

  cpu {
    architecture = "amd64"
    cores        = each.value.cores
    limit        = 0
  }

  memory {
    dedicated = each.value.memory
    swap      = each.value.swap
  }

  features {
    nesting = true
    keyctl  = try(each.value.keyctl, false)
  }

  disk {
    datastore_id = "local-lvm"
    size         = each.value.disk
  }

  network_interface {
    name     = "eth0"
    bridge   = "vmbr0"
    firewall = each.value.firewall
  }

  initialization {
    hostname = each.value.hostname

    ip_config {
      ipv4 {
        address = "dhcp"
      }

      dynamic "ipv6" {
        for_each = try(each.value.ipv6, null) != null ? [each.value.ipv6] : []

        content {
          address = ipv6.value
        }
      }
    }
  }

  operating_system {
    template_file_id = proxmox_download_file.lxc_template[try(each.value.template, "debian")].id
    type             = try(each.value.os_type, "debian")
  }

  lifecycle {
    prevent_destroy = true

    ignore_changes = [
      operating_system[0].template_file_id
    ]
  }

  console {
    enabled   = true
    tty_count = 2
    type      = "tty"
  }

  dynamic "device_passthrough" {
    for_each = try(each.value.tun_device, false) ? [1] : []

    content {
      path       = "/dev/net/tun"
      deny_write = false
      gid        = 0
      uid        = 0
      mode       = "0660"
    }
  }

  dynamic "startup" {
    for_each = try(each.value.startup_order, null) != null ? [1] : []

    content {
      order    = each.value.startup_order
      up_delay = try(each.value.startup_up_delay, 0)
    }
  }
}
