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
  default = "https://releases.ubuntu.com/24.04.3/ubuntu-24.04.3-live-server-amd64.iso"
}
variable "iso_checksum" {
  type    = string
  default = "sha256:c3514bf0056180d09376462a7a1b4f213c1d6e8ea67fae5c25099c6fd3d8274b"
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

source "virtualbox-iso" "ubuntu24" {
  guest_os_type = "Ubuntu_64"
  vm_name       = "ubuntu24-packer-{{timestamp}}"
  iso_url       = var.iso_url
  iso_checksum  = var.iso_checksum
  cpus          = var.cpus
  memory        = var.memory
  disk_size     = var.disk_size
  gfx_vram_size = 16
  boot_wait     = "10s"
  headless      = var.headless
  http_content = {
    "/user-data" = templatefile("${path.root}/http/user-data", {
      hostname = var.hostname,
      timezone = var.timezone,
      username = var.username,
      password = var.password
    }),
    "/meta-data" = templatefile("${path.root}/http/meta-data", {
      hostname = var.hostname
    })
  }
  boot_command = [
    "c<wait>",
    "linux /casper/vmlinuz --- autoinstall ds=\"nocloud-net;seedfrom=http://{{.HTTPIP}}:{{.HTTPPort}}/\"",
    "<enter><wait>",
    "initrd /casper/initrd",
    "<enter><wait>",
    "boot",
    "<enter>"
  ]
  vboxmanage = [
    ["modifyvm", "{{ .Name }}", "--audio", "none"]
  ]
  ssh_username     = var.username
  ssh_password     = var.password
  ssh_timeout      = "30m"
  output_directory = "output"
  shutdown_command = "echo '${var.password}' | sudo -S /sbin/halt -p"
}

build {
  sources = ["source.virtualbox-iso.ubuntu24"]

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
      "sudo apt-get update",
      "sudo apt-get upgrade -y"
    ]
  }
}
