# VirtuPack

Ready to use virtual machine images. The goal is to provide a fully automated process to build a base image from an official ISO, apply essential configurations, and produce an importable appliance.

## Directory Structure

Each distro has its own directory to keep its configuration isolated and organized.

```
├── [distro]
│   ├── image.pkr.hcl           # Packer's main definition
│   └── local.auto.pkrvars.hcl  # Local variables
└── [another distro]
```

## Prerequisites

Before you begin, ensure the following software is installed on your machine:

1. [Packer](https://developer.hashicorp.com/packer/install)
1. QEMU **or** VirtualBox **or** authenticate to AWS **or** authenticate to GCP **or** [more](https://developer.hashicorp.com/packer/integrations)
1. Client SSH. Usually pre-installed on Linux, macOS, and Windows (via WSL or Git Bash)

## Configuration

Inside the directory of the distro you want to build, create a file named `local.auto.pkrvars.hcl`. Packer will load this file automatically.

```hcl
cpus      = 2
memory    = 2048
disk_size = 20480
hostname  = "rocky9"
timezone  = "Asia/Jakarta"
headless  = false

username            = "remote"
password            = "remotepasswd"
ssh_public_key_path = "/home/your-username/.ssh/id_ed25519.pub"
```

## Usage

1. Navigate to a distro directory
1. Create the `local.auto.pkrvars.hcl` file as described in the Configuration section above. If you skip this, the default values from the template will be used
1. Initialize Packer and run the build

```bash
packer init .
packer fmt .
packer validate .
packer build -force -color=false .
```

> [!NOTE]
>
> The build process takes about 10 to 15 minutes. If the ISO file hasn't been downloaded yet, this process will take longer. So, just wait!
