packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1"
    }
    windows-update = {
      version = "0.17.1"
      source  = "github.com/rgl/windows-update"
    }
    external = {
      version = "> 0.0.2"
      source  = "github.com/joomcode/external"
    }
  }
}

data "external-raw" "virtio" {
  program = [
    "bash", "-c",
    "if [ ! -f virtio-win.iso ]; then wget -nv https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso -O virtio-win.iso ; fi"
  ]
}

source "qemu" "windows_server_2019" {
  boot_wait            = "5s"
  disk_interface       = "virtio"
  disk_size            = "51200"
  floppy_files         = ["Autounattend.xml", "redhat.cer", "scripts/microsoft-updates.ps1", "scripts/openssh.ps1", "scripts/configureRemotingForAnsible.ps1"]
  format               = "raw"
  headless             = "true"
  iso_checksum         = "6dae072e7f78f4ccab74a45341de0d6e2d45c39be25f1f5920a2ab4f51d7bcbb"
  iso_url              = "https://software-static.download.prss.microsoft.com/dbazure/988969d5-f34g-4e03-ac9d-1f9786c66749/17763.3650.221105-1748.rs5_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"
  output_directory     = "target-qemu"
  qemuargs             = [["-m", "4096m"], ["-smp", "cpus=4,maxcpus=16,cores=4"], ["-cdrom", "virtio-win.iso"]]
  shutdown_command     = "shutdown /s /t 10 /f /d p:4:1 /c \"Packer Shutdown\""
  ssh_private_key_file = "vagrant-key"
  ssh_username         = "windows"
  ssh_wait_timeout     = "5h"
  use_default_display  = "true"
  vm_name              = "windows-server-2019"
  vnc_bind_address     = "0.0.0.0"
  vnc_port_max         = "5900"
  vnc_port_min         = "5900"
}

build {
  sources = ["source.qemu.windows_server_2019"]

  provisioner "windows-update" {}

  provisioner "powershell" {
    scripts = ["scripts/configureRemotingForAnsible.ps1"]
  }

  provisioner "windows-shell" {
    script = "scripts/disableAutoLogon.bat"
  }

  provisioner "file" {
    destination = "C:/Windows/Temp/"
    source      = "scripts/spice-guest-tools.exe"
  }

  provisioner "powershell" {
    scripts = [
      "scripts/spiceTools.ps1",
      "scripts/Install-CloudBaseInit.ps1"
    ]
  }

  provisioner "powershell" {
    scripts = ["scripts/fixes.ps1"]
  }

  provisioner "windows-restart" {}

  provisioner "powershell" {
    scripts = [
      "scripts/cleanup.ps1",
      "scripts/shrink-filesystem.ps1"
    ]
  }

  provisioner "powershell" {
    script = "scripts/sysprep.ps1"
  }

  post-processor "shell-local" {
    inline = [
      "parted -s target-qemu/* print free",
      "NEW_SIZE=$(parted -sm target-qemu/* unit b print free | grep free | awk -F ':' '{print $2}' | sort -rh | head -n 1)",
      "qemu-img resize -f raw --shrink target-qemu/* $NEW_SIZE",
      "qemu-img convert -f raw -O qcow2 target-qemu/windows-server-2019 target-qemu/windows-server-2019.qcow2"
    ]
  }
}
