# capsule base image — Packer recipe (cirruslabs/tart plugin).
#
# ┌─────────────────────────────────────────────────────────────────┐
# │ DRAFT — UNVERIFIED. `packer` is not installed yet and this has    │
# │ never baked. Do NOT treat as working. The bring-up gate           │
# │ (docs/design.md) proves the manual steps first; this file then    │
# │ encodes what actually worked. Shape follows                       │
# │ cirruslabs/macos-image-templates.                                 │
# └─────────────────────────────────────────────────────────────────┘

packer {
  required_plugins {
    tart = {
      version = ">= 1.20.0"
      source  = "github.com/cirruslabs/tart"
    }
  }
}

variable "vm_base_name" {
  type    = string
  default = "ghcr.io/cirruslabs/macos-tahoe-base:latest" # macOS 26 floor
}

variable "vm_name" {
  type    = string
  default = "capsule-base"
}

source "tart-cli" "capsule" {
  vm_base_name = var.vm_base_name
  vm_name      = var.vm_name
  cpu_count    = 4
  memory_gb    = 8
  disk_size_gb = 50
  ssh_username = "admin"
  ssh_password = "admin"
  ssh_timeout  = "120s"
  # 1024x768 deterministic display is set at `tart run` time.
}

build {
  sources = ["source.tart-cli.capsule"]

  # Shared core only. Keep the image toolchain-light: build on the host,
  # share the product read-only. TCC grants + signing cert are baked by
  # the manual bake-by-consent step (provision/30), NOT here.
  provisioner "file" {
    source      = "helpers/"
    destination = "/Users/admin/capsule-helpers/"
  }

  provisioner "shell" {
    scripts = [
      "provision/10-clt.sh",
      "provision/20-display.sh",
      # provision/40-signing-cert.sh runs against an rsync'd wand tree;
      # provision/30-tcc-consent.md is the manual pre-snapshot step.
    ]
  }
}
