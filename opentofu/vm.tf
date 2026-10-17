resource "proxmox_virtual_environment_vm" "vm" {
  for_each = local.vms

  node_name = var.proxmox_node
  vm_id     = each.value.vm_id
  name      = each.value.name

  started         = true
  on_boot         = true
  stop_on_destroy = true

  bios          = "seabios"
  scsi_hardware = "virtio-scsi-single"

  cpu {
    cores = each.value.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = each.value.disk.size

    import_from = each.value.cloud_image != null ? proxmox_download_file.vm_image[each.value.cloud_image].id : null

    iothread = true
    aio      = "io_uring"
    cache    = "none"
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  dynamic "initialization" {
    for_each = each.value.cloud_image != null ? [1] : []

    content {
      datastore_id = "local-lvm"

      ip_config {
        ipv4 {
          address = "dhcp"
        }
      }

      user_account {
        username = "debian"
        keys     = [var.ssh_public_key]
      }
    }
  }

  operating_system {
    type = "l26"
  }

  startup {
    order      = each.value.startup.order
    up_delay   = each.value.startup.up_delay
    down_delay = each.value.startup.down_delay
  }

  lifecycle {
    prevent_destroy = true
  }
}
