# capsule base image — Packer recipe (cirruslabs/tart plugin).
#
# Encodes what the 2026-08-03 bring-up gate PROVED (docs/design.md
# §Gate result). The guest stays toolchain-free: apps are built and
# signed on the HOST and arrive over a read-only virtiofs share at run
# time. peekaboo and the compiled click helper are shipped in as
# binaries — nothing is compiled or brew-installed inside the guest.
#
# TCC grants are NOT baked here (packer talks over SSH; consent needs
# the GUI session) — bake.sh runs provision/30-consent-core.sh against
# the freshly baked image right after this build.

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
  default = "ghcr.io/cirruslabs/macos-tahoe-vanilla:latest" # macOS 26 floor; vanilla suffices (gate-proven)
}

variable "vm_name" {
  type    = string
  default = "capsule-base"
}

# Host public key seeded into the guest so the daily loop (verify.sh)
# and the consent script drive the VM without password auth.
variable "ssh_pubkey" {
  type = string
}

# Host directory holding the peekaboo install to ship in (bake.sh
# resolves it from the host's brew Cellar). The whole directory is
# copied so @rpath-relative dylibs stay next to the binary.
variable "peekaboo_dir" {
  type = string
}

# Host path of the pre-compiled click helper (bake.sh compiles
# helpers/click.swift with the host swiftc — the guest has no CLT).
variable "click_bin" {
  type = string
}

source "tart-cli" "capsule" {
  vm_base_name = var.vm_base_name
  vm_name      = var.vm_name
  cpu_count    = 4
  memory_gb    = 8
  disk_size_gb = 50
  headless     = true # zero host windows — the whole point of capsule
  ssh_username = "admin"
  ssh_password = "admin"
  ssh_timeout  = "300s"
  # 1024x768 deterministic display is the tart default at run time.
}

build {
  sources = ["source.tart-cli.capsule"]

  # scp does not create destination directories — make them first.
  provisioner "shell" {
    inline = ["mkdir -p /Users/admin/peekaboo /Users/admin/capsule-helpers"]
  }

  provisioner "file" {
    source      = "${var.peekaboo_dir}/"
    destination = "/Users/admin/peekaboo/"
  }

  provisioner "file" {
    source      = var.click_bin
    destination = "/Users/admin/capsule-helpers/capsule-click"
  }

  provisioner "shell" {
    environment_vars = ["CAPSULE_PUBKEY=${var.ssh_pubkey}"]
    inline = [
      "mkdir -p /Users/admin/.ssh",
      "grep -qF \"$CAPSULE_PUBKEY\" /Users/admin/.ssh/authorized_keys 2>/dev/null || echo \"$CAPSULE_PUBKEY\" >> /Users/admin/.ssh/authorized_keys",
      "chmod 700 /Users/admin/.ssh && chmod 600 /Users/admin/.ssh/authorized_keys",
      "chmod +x /Users/admin/capsule-helpers/capsule-click /Users/admin/peekaboo/bin/peekaboo",
    ]
  }

  # Window restore would resurrect a Terminal window at every login and
  # park it ON TOP of System Settings, swallowing the consent clicks.
  provisioner "shell" {
    inline = [
      "defaults write -g NSQuitAlwaysKeepsWindows -bool false",
      "defaults write com.apple.loginwindow TALLogoutSavesState -bool false",
      "defaults write com.apple.Terminal NSQuitAlwaysKeepsWindows -bool false",
      "defaults write com.apple.systempreferences NSQuitAlwaysKeepsWindows -bool false",
    ]
  }

  # A verification lab must never idle: a slept display serves the boot
  # splash to `peekaboo image` while the session behind it is fully live
  # (measured 2026-08-03 — AX answered at t+10s, pixels at t+35s).
  provisioner "shell" {
    inline = ["sudo pmset -a displaysleep 0 disksleep 0 sleep 0"]
  }

  provisioner "shell" {
    scripts = [
      "provision/20-display.sh",
      # provision/10-clt.sh is deliberately NOT here — the gate proved
      # the verify loop needs no guest toolchain (build on the host).
      # It stays available as a per-app OPTIONAL step.
    ]
  }
}
