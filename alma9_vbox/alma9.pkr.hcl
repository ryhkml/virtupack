packer {
  required_plugins {
    virtualbox = {
      source  = "github.com/hashicorp/virtualbox"
      version = "~> 1"
    }
  }
}

variable "iso_url" {
  type    = string
  default = "https://repo.almalinux.org/almalinux/9.6/isos/x86_64/AlmaLinux-9.6-x86_64-minimal.iso"
}
variable "iso_checksum" {
  type    = string
  default = "27a346c74d8755516a4ad2057ea29c2450454f1a928628734f26e12b0b8120d7"
}

variable "cpus" {
  type    = number
  default = 2
}
variable "memory" {
  type    = number
  default = 2048
}
variable "disk_size" {
  type    = number
  default = 20480 // 20 * 1024MB
}
variable "hostname" {
  type    = string
  default = "alma9-packer"
}
variable "timezone" {
  type    = string
  default = "Asia/Jakarta"
}

variable "username" {
  type        = string
  default     = "adminalma9"
  description = "Username for the default user in the image"
}
variable "password" {
  type        = string
  default     = "adminalma9passwd"
  description = "Password for root and default users"
}
variable "ssh_public_key_path" {
  type        = string
  default     = "~/.ssh/id_ed25519.pub" // This will throw an error if the value is undefined
  description = "Path to the public SSH key file to be installed in the image. Use absolute paths, not ~/"
}

source "virtualbox-iso" "alma9" {
  guest_os_type = "RedHat_64"
  vm_name       = "alma9-packer-{{timestamp}}"
  iso_url       = var.iso_url
  iso_checksum  = var.iso_checksum
  cpus          = var.cpus
  memory        = var.memory
  disk_size     = var.disk_size
  gfx_vram_size = 16
  headless      = true
  http_content = {
    "/ks.cfg" = templatefile("${path.root}/start.cfg", {
      hostname = var.hostname,
      timezone = var.timezone,
      username = var.username,
      password = var.password,
    })
  }
  boot_command = [
    "<tab>",
    " inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg",
    "<enter>"
  ]
  ssh_username     = var.username
  ssh_password     = var.password
  ssh_timeout      = "30m"
  output_directory = "output"
  shutdown_command = "echo 'packer' | sudo -S /sbin/halt -p"
}

build {
  sources = ["source.virtualbox-iso.alma9"]

  provisioner "file" {
    source      = var.ssh_public_key_path
    destination = "/tmp/authorized_keys"
  }

  provisioner "shell" {
    inline = [
      "sudo mkdir -p /home/${var.username}/.ssh",
      "sudo mv /tmp/authorized_keys /home/${var.username}/.ssh/authorized_keys",
      "sudo chown -R ${var.username}:${var.username} /home/${var.username}/.ssh",
      "sudo chmod 700 /home/${var.username}/.ssh",
      "sudo chmod 600 /home/${var.username}/.ssh/authorized_keys"
    ]
  }

  provisioner "shell" {
    environment_vars = [
      "BANDWHICH=N",
      "FAIL2BAN=N",
      "ZELLIJ=N",
      "FIREWALL_ZONE=public",
      "HTTP_HTTPS=N"
    ]
    script = "install.sh"
  }
}
