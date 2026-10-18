locals {
  containers = {
    vaultwarden = {
      vm_id    = 100
      hostname = "vaultwarden"
      cores    = 1
      memory   = 512
      swap     = 256
      disk     = 8
      firewall = true
    }

    vikunja = {
      vm_id    = 101
      hostname = "vikunja"
      cores    = 1
      memory   = 512
      swap     = 512
      disk     = 4
      firewall = true
    }

    adguardhome = {
      vm_id    = 102
      hostname = "adguardhome"
      cores    = 1
      memory   = 256
      swap     = 256
      disk     = 4
      firewall = true
    }

    nginx_proxy_manager = {
      vm_id    = 103
      hostname = "CT103"
      cores    = 1
      memory   = 512
      swap     = 512
      disk     = 4
      firewall = true
    }

    wireguard = {
      vm_id    = 104
      hostname = "wireguard"
      cores    = 1
      memory   = 256
      swap     = 256
      disk     = 2
      firewall = true

      tun_device = true
    }

    uptimekuma = {
      vm_id    = 105
      hostname = "uptimekuma"
      cores    = 1
      memory   = 512
      swap     = 512
      disk     = 8
      firewall = true
    }

    gotify = {
      vm_id    = 106
      hostname = "gotify"
      cores    = 1
      memory   = 256
      swap     = 256
      disk     = 8
      firewall = true
    }

    influxdb = {
      vm_id    = 109
      hostname = "influxdb"
      cores    = 2
      memory   = 1024
      swap     = 512
      disk     = 8
      firewall = false

      keyctl = true
      ipv6   = "auto"

      tags = [
        "community-script",
        "database",
      ]
    }

    grafana = {
      vm_id    = 110
      hostname = "grafana"
      cores    = 1
      memory   = 512
      swap     = 512
      disk     = 2
      firewall = false

      keyctl  = true
      os_type = "alpine"
      tags = [
        "community-script",
        "monitoring",
        "visualization",
      ]
      template = "alpine"
    }

    gitea = {
      vm_id    = 112
      hostname = "gitea"
      cores    = 1
      memory   = 512
      swap     = 512
      disk     = 10
      firewall = true

      startup_order    = 2
      startup_up_delay = 20
    }

    gitea_runner = {
      vm_id    = 114
      hostname = "gitea-runner"
      cores    = 1
      memory   = 512
      swap     = 512
      disk     = 8
      firewall = true

      startup_order    = 3
      startup_up_delay = 0
    }

    openbao = {
      vm_id           = 115
      hostname        = "openbao"
      description     = "OpenBao secrets management"
      ssh_public_keys = [var.ssh_public_key]

      cores  = 1
      memory = 384
      swap   = 256
      disk   = 4

      on_boot  = true
      firewall = true
    }
  }

  vms = {
    postgresql = {
      vm_id  = 113
      name   = "infra-postgresql"
      cores  = 1
      memory = 1024

      disk = {
        size = 15
      }

      cloud_image = null

      startup = {
        order      = 1
        up_delay   = 30
        down_delay = 30
      }
    }

    swarm_01 = {
      vm_id  = 120
      name   = "swarm-01"
      cores  = 2
      memory = 2048

      disk = {
        size = 12
      }

      cloud_image = "debian_13"

      startup = {
        order      = 4
        up_delay   = 30
        down_delay = 30
      }
    }
  }
}
