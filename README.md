# windows-system-audit

A clean and minimal PowerShell project that gathers full Windows system information for hardware and environment assessment.

---

## What the script does

`scripts/full_system_audit.ps1` collects the following information from a Windows machine and saves two output files:

| Output file | Format | Purpose |
|---|---|---|
| `system_audit_<timestamp>.txt` | Plain text | Human-readable report |
| `system_audit_<timestamp>.json` | JSON | Structured data for further processing |

Both files are written to the directory from which you run the script (configurable with `-OutputDir`).

---

## Requirements

- Windows 10 / Windows 11 (or Windows Server 2016+)
- PowerShell 5.1 or later
- **Must be run as Administrator**
- No external modules or internet access required

---

## How to run

Open **PowerShell as Administrator**, then:

```powershell
# Navigate to the repo
cd path\to\windows-system-audit

# Run with default output directory (current directory)
.\scripts\full_system_audit.ps1

# Run with a custom output directory
.\scripts\full_system_audit.ps1 -OutputDir "C:\AuditReports"
```

If your execution policy blocks unsigned scripts, temporarily allow it for the current session:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\full_system_audit.ps1
```

---

## Output files

After the script finishes you will see a summary like:

```
============================================================
  Audit complete: 2025-06-01 14:32:07
  TXT report : C:\AuditReports\system_audit_20250601_143207.txt
  JSON report: C:\AuditReports\system_audit_20250601_143207.json
============================================================
```

---

## What each section collects

| Section | What is captured |
|---|---|
| **OS** | Edition, version, build number, architecture, install date, last boot time |
| **CPU** | Model name, manufacturer, physical cores, logical processors, max clock speed, L2/L3 cache size, architecture |
| **RAM** | Total installed RAM, per-slot capacity, speed (MHz), memory type (DDR4/DDR5…), manufacturer, part number |
| **Motherboard** | Manufacturer, product name, version, serial number |
| **BIOS** | Manufacturer, name, SMBIOS version, release date |
| **GPU** | Name, VRAM (MB), driver version, current video mode, status |
| **Storage (Physical Disks)** | Model, size (GB), interface type (NVMe/SATA…), media type, serial number, partition count |
| **Logical Drives** | Drive letter, volume name, file system, total size, free space, used percentage |
| **Network Adapters** | Description, MAC address, IP addresses, default gateway, DNS servers, DHCP status |
| **WSL Status** | Whether WSL is installed, and the list of installed distributions |
| **NVIDIA Status** | Whether an NVIDIA GPU is present; if `nvidia-smi` is available: driver version, VRAM, GPU temperature |
| **Disk Performance** | Sequential write and read speed (MB/s) measured against the system temp directory using a 128 MB buffer |
| **Role Recommendation** | Scores the machine for *Development* vs *Local AI Agent Hosting* based on CPU, RAM, GPU, storage speed, WSL, and free disk space |

---

## GPU and VRAM note

The `Win32_VideoController` WMI class reports VRAM via a 32-bit property capped at **4 GB (4096 MB)**. If your GPU has more VRAM (e.g. 8 GB, 12 GB, 24 GB), the WMI figure will be wrong. For NVIDIA cards, the script also runs `nvidia-smi` in section 11, which reports the correct VRAM value — use that as the authoritative source.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `Access denied` or script doesn't run | Right-click PowerShell → **Run as Administrator** |
| `cannot be loaded because running scripts is disabled` | Run `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` first, or use the one-liner in **Example run commands** |
| `nvidia-smi : not found in PATH` | Install NVIDIA drivers and ensure `C:\Windows\System32\DriverStore\FileRepository\…` or the CUDA `bin` folder is in your `PATH` |
| WSL shows "No (wsl.exe not found)" | Enable WSL via `wsl --install` in an Administrator terminal, then reboot |
| Disk performance result seems low | The test runs against `%TEMP%` (typically C:). If your workload drive is different, you can edit `$TestFile` in the script to point elsewhere |
| JSON report contains `null` values | Some hardware (e.g. virtual machines) returns empty WMI fields — this is expected |

---

## Role recommendation

The script assigns weighted scores for two roles and prints a per-factor breakdown in the report:

| Factor | Development points | AI Host points |
|---|---|---|
| CPU cores ≥ 8 | +2 | +1 |
| CPU cores ≥ 4 (but < 8) | +1 | — |
| Logical processors ≥ 16 | +1 | +1 |
| RAM ≥ 64 GB | +2 | +3 |
| RAM ≥ 32 GB (but < 64 GB) | +2 | +2 |
| RAM ≥ 16 GB (but < 32 GB) | +1 | +1 |
| NVIDIA GPU detected | — | +4 |
| `nvidia-smi` available | — | +1 |
| Free space on C: ≥ 100 GB | +1 | +1 |
| Disk read speed ≥ 1000 MB/s | — | +2 |
| Disk read speed ≥ 400 MB/s (but < 1000) | — | +1 |
| WSL installed | +2 | — |

- **Development** — benefits from many CPU cores, ≥16 GB RAM, WSL, and adequate free storage.
- **Local AI Agent Hosting** — benefits heavily from an NVIDIA GPU, ≥32 GB RAM, fast NVMe storage, and ample free space.

The recommendation, both scores, the per-factor breakdown (`Factors` array), and explanatory notes are included in both output files.

---

## Example run commands

```powershell
# Basic run (output saved to current directory)
.\scripts\full_system_audit.ps1

# Save output to a specific folder
.\scripts\full_system_audit.ps1 -OutputDir "D:\Reports"

# One-liner with execution policy bypass
powershell -ExecutionPolicy Bypass -File ".\scripts\full_system_audit.ps1" -OutputDir "C:\Temp"
```

---

## Repository structure

```
windows-system-audit/
├── scripts/
│   └── full_system_audit.ps1   # Main audit script
├── README.md
└── LICENSE
```
