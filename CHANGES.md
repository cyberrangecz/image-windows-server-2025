# UEFI + TPM Rewrite — Summary of Changes

## Goal

Rewrite Windows Server 2025 image build to produce a proper UEFI + TPM image
for OpenStack deployment. Eliminate BIOS/MBR legacy layout and LabConfig bypass
hacks. Minimize system interrupts CPU consumption during nested builds.

## Partition Layout (UEFI/GPT, OS last for shrinking)

| # | Type | Size | Format | Notes |
|---|------|------|--------|-------|
| 1 | EFI | 260 MB | FAT32 | UEFI boot partition |
| 2 | MSR | 16 MB | — | Required by Windows on GPT |
| 3 | C: | Extend | NTFS | OS partition, last = shrinkable |

No recovery partition. LabConfig bypass registry hacks removed (real UEFI+TPM
provided via OVMF + swtpm).

## Files Changed

### NEW — `Dockerfile`

Extends `ghcr.io/cyberrangecz/docker-image-builder:latest` with missing
packages for UEFI+TPM builds:

- `ovmf` — OVMF_CODE.fd / OVMF_VARS.fd
- `swtpm` + `swtpm-tools` — software TPM for `vtpm = true`
- `gdisk` — `sgdisk --move-second-header` for GPT repair after shrink
- `parted` — partition inspection/resize

### MODIFIED — `Autounattend.xml`

- DiskConfiguration rewritten: MBR → GPT (EFI + MSR + Primary)
- Removed all 5 LabConfig `RunSynchronousCommand` entries (TPM, SecureBoot,
  RAM, CPU, Storage bypass)
- `InstallTo` remains partition 3

### MODIFIED — `packer.pkr.hcl`

- Added `efi_boot = true`
- Added `efi_firmware_code` / `efi_firmware_vars` (OVMF paths)
- Added `vtpm = true`
- Kept `format = "raw"` (needed for host-side GPT shrink pipeline)
- Kept `disk_interface = "virtio"` (works with OpenStack)
- CPU tuning: added `-no-hpet`, `-global kvm-pit.lost_tick_policy=discard`
- Post-processor rewritten for GPT-aware shrink:
  1. `parted` to find end of partition 3
  2. `qemu-img resize --shrink` with margin for backup GPT
  3. `sgdisk --move-second-header` to fix secondary GPT header
  4. `qemu-img convert` raw → qcow2

### MODIFIED — `terraform.tf`

- Added `image_properties_override` to module call:
  - `hw_firmware_type = "uefi"`
  - `hw_machine_type = "q35"`

## Files Unchanged

- `scripts/shrink-filesystem.ps1` — diskpart shrink works the same on GPT
- `scripts/sysprep.ps1`, `scripts/cleanup.ps1`, `scripts/fix.ps1`
- VirtIO drivers and provisioner scripts
- `run_guestfish.sh` (diagnostic only)

## CPU Tuning (System Interrupts Reduction)

Targets: Debian 12 (primary), WSL2 Ubuntu 6.6

- `-no-hpet` — prevents Windows from using high-precision event timer
- `-global kvm-pit.lost_tick_policy=discard` — prevents timer catch-up storms
- Existing Hyper-V enlightenments retained (hv_relaxed, hv_vapic, hv_time, etc.)
- `hv_avic` skipped (hardware-dependent, not safe to assume)
- `kernel_irqchip=split` skipped (Packer controls -machine flag)

## Post-Processing Pipeline (GPT-aware)

```bash
# 1. Inspect layout
parted -s <img> unit b print free

# 2. Find end of partition 3 (Windows C:)
END=$(parted -sm <img> unit b print | grep '^3:' | cut -d: -f3)

# 3. Add 1MB margin for secondary GPT header
NEW_SIZE=$((${END%B} + 1048576))

# 4. Shrink raw image
qemu-img resize -f raw --shrink <img> ${NEW_SIZE}

# 5. Fix secondary GPT header
sgdisk --move-second-header <img>

# 6. Convert to qcow2
qemu-img convert -f raw -O qcow2 <img> <img>.qcow2
```
