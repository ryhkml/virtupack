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
  default = "https://download.rockylinux.org/pub/rocky/8/isos/x86_64/Rocky-8.10-x86_64-minimal.iso"
}
variable "iso_checksum" {
  type    = string
  default = "sha256:2c735d3b0de921bd671a0e2d08461e3593ac84f64cdaef32e3ed56ba01f74f4b"
}

variable "cpus" {
  type    = number
  default = 2
}
variable "memory" {
  type        = number
  default     = 2048
  description = "Memory in MB"
}
variable "disk_size" {
  type        = number
  default     = 20480
  description = "Disk size in MB"

}
variable "hostname" {
  type    = string
  default = "vbox"
}
variable "timezone" {
  type    = string
  default = "Asia/Jakarta"
}
variable "headless" {
  type    = bool
  default = true
}

variable "username" {
  type        = string
  default     = "admin"
  description = "Username for the default user in the image"
}
variable "password" {
  type        = string
  default     = "adminpasswd"
  description = "Password for root and default user"
}
variable "ssh_public_key_path" {
  type        = string
  default     = "~/.ssh/id_ed25519.pub" // This will throw an error if the value is undefined
  description = "Path to the public SSH key file to be installed in the image. Use absolute paths, not ~/"
}

source "virtualbox-iso" "rocky8" {
  guest_os_type = "RedHat_64"
  vm_name       = "rocky8-packer-{{timestamp}}"
  iso_url       = var.iso_url
  iso_checksum  = var.iso_checksum
  cpus          = var.cpus
  memory        = var.memory
  disk_size     = var.disk_size
  gfx_vram_size = 16
  boot_wait     = "10s"
  headless      = var.headless
  http_content = {
    "/ks.cfg" = templatefile("${path.root}/http/ks.cfg", {
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
  vboxmanage = [
    ["modifyvm", "{{ .Name }}", "--audio", "none"],
  ]
  ssh_username     = var.username
  ssh_password     = var.password
  ssh_timeout      = "30m"
  output_directory = "output"
  shutdown_command = "echo '${var.password}' | sudo -S /sbin/halt -p"
}

build {
  sources = ["source.virtualbox-iso.rocky8"]

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
      "sudo chmod 600 /home/${var.username}/.ssh/authorized_keys",
      "sudo dnf update -y",
      "sudo dnf install -y dnf-utils epel-release",
      "sudo /usr/bin/crb enable",
      "sudo dnf install -y ncurses-term"
    ]
  }
}
