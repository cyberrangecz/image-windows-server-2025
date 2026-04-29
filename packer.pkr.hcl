packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1"
    }
    windows-update = {
      version = "v0.18.1"
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

source "qemu" "windows_server_2025" {
  boot_command         = [" <wait2s> <wait2s> <wait2s> <wait2s> <wait2s>"]
  boot_wait            = "1s"
  disk_interface       = "virtio"
  disk_size            = "50000"
  efi_boot             = true
  efi_firmware_code    = "/usr/share/OVMF/OVMF_CODE_4M.fd"
  efi_firmware_vars    = "/usr/share/OVMF/OVMF_VARS_4M.fd"
  vtpm                 = true
  floppy_files         = ["Autounattend.xml", "redhat.cer", "scripts/microsoft-updates.ps1", "scripts/openssh.ps1", "scripts/spiceToolsInstall.ps1", "scripts/fixnetwork.ps1", "scripts/power_plan_tune.cmd"]
  format               = "raw"
  headless             = "true"
  iso_checksum         = "7b052573ba7894c9924e3e87ba732ccd354d18cb75a883efa9b900ea125bfd51"
  iso_url              = "https://software-static.download.prss.microsoft.com/dbazure/998969d5-f34g-4e03-ac9d-1f9786c66749/26100.32230.260111-0550.lt_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"
  machine_type         = "q35"
  output_directory     = "target-qemu"
  qemuargs             = [
      ["-enable-kvm"],
      ["-m", "6144m"],
      ["-smp", "4,sockets=1,cores=4,threads=1"],
      ["-cpu", "host,hv_relaxed,hv_vapic,hv_runtime,hv_time,hv_vpindex,hv_synic,hv_stimer,hv_tlbflush,hv_ipi,hv_frequencies,hv_stimer_direct,hv_xmm_input,hv_spinlocks=0x1fff"],
      ["-no-hpet"],
      ["-global", "kvm-pit.lost_tick_policy=discard"],
      ["-device", "virtio-tablet"],
      ["-cdrom", "virtio-win.iso"]
  ]
  shutdown_command     = "shutdown /s /t 10 /f /d p:4:1 /c \"Packer Shutdown\""
  ssh_private_key_file = "ssh-key"
  ssh_username         = "windows"
  ssh_wait_timeout     = "5h"
  use_default_display  = "true"
  vm_name              = "windows-server-2025"
  vnc_bind_address     = "0.0.0.0"
  vnc_port_max         = "5900"
  vnc_port_min         = "5900"
}

build {
  sources = ["source.qemu.windows_server_2025"]

  provisioner "windows-update" {}

  provisioner "powershell" {
    scripts = [
      # "scripts/configureRemotingForAnsible.ps1",
      # "scripts/spiceToolsInstall.ps1",
      "scripts/enable-rdp.ps1"
    ]
  }

  provisioner "windows-restart" {}

  provisioner "windows-shell" {
    script = "scripts/disable-auto-logon.bat"
  }

  provisioner "powershell" {
    scripts = [
      "scripts/fix.ps1",
      "scripts/Install-CloudBaseInit.ps1",
      "scripts/cleanup.ps1",
      "scripts/remove-recovery-partition.ps1",
      "scripts/shrink-filesystem.ps1",
      "scripts/sysprep.ps1"
    ]
  }

  post-processor "shell-local" {
    inline = [
      "parted -s target-qemu/windows-server-2025 unit b print free",
      "END=$$(parted -sm target-qemu/windows-server-2025 unit b print | grep '^3:' | cut -d: -f3)",
      "NEW_SIZE=$$(($${END%B} + 1048576))",
      "qemu-img resize -f raw --shrink target-qemu/windows-server-2025 $$NEW_SIZE",
      "sgdisk --move-second-header target-qemu/windows-server-2025",
      "qemu-img convert -f raw -O qcow2 target-qemu/windows-server-2025 target-qemu/windows-server-2025.qcow2"
    ]
  }
}
