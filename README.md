# Windows System Audit

**A local, read-only snapshot of a Windows PC.** Generate a text summary and machine-readable JSON for inventory, troubleshooting, and planning. Collection failures appear as `Unavailable` instead of disappearing silently. Hardware guidance describes observed capabilities; it does not claim a machine is ready for a particular AI model or workload.

**[Quick start](#quick-start) | [What it checks](#what-it-checks) | [Options](#options) | [Privacy](#privacy-and-security) | [Limitations](#limitations) | [Testing](#testing)**

## Quick start

Download or clone this repository, open PowerShell in its directory, and run:

```powershell
.\full_system_audit.ps1
```

The script writes `system_audit_<UTC timestamp>_<random suffix>.txt` and `.json` under `Documents\SystemAudit`. It prints both paths. No administrator elevation is required for the default run, though some sections may be unavailable without it. If your execution policy blocks local scripts, follow your organization's policy; a process-scoped policy can be used where permitted:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\full_system_audit.ps1
```

Review the script before running it. Do not execute downloaded scripts directly from a URL.

## What it checks

| Section | Data collected by default |
| --- | --- |
| System and Windows | Manufacturer, model, installed memory, Windows build, last boot |
| CPU and memory | Processor name and core counts, memory module capacity and speed |
| GPU | Adapter name, driver, reported memory and status |
| Storage | Physical disk type, bus, capacity and reported health; local volume capacity and free space |
| Optional tools | WSL status and NVIDIA GPU query, when their commands are available |
| Guidance | Plain-language observations with explicit uncertainty |

Each JSON section has `Status`, `Data`, and `Note`. `Status` is `OK`, `Unavailable`, or `Skipped`. The script falls back to `Win32_DiskDrive` if `Get-PhysicalDisk` is unavailable; fallback media type and health are marked `Unknown`.

## Options

```powershell
# Save reports elsewhere
.\full_system_audit.ps1 -OutputDirectory 'C:\Reports\SystemAudit'

# Include host, user, domain, device, volume and serial identifiers
.\full_system_audit.ps1 -IncludeIdentifiers

# Explicitly run the WinSAT disk test; may require elevation
.\full_system_audit.ps1 -RunDiskBenchmark
```

`-RunDiskBenchmark` runs `winsat.exe disk -drive <system drive>`. It can generate substantial disk I/O and is skipped by default. The WSL and NVIDIA checks are read-only command queries. No software is installed and no report is uploaded.

## Example output

The following is **synthetic** and does not describe a real host:

```text
WINDOWS SYSTEM AUDIT
Generated (UTC): 2026-01-01T12:00:00.0000000Z
Identifiers included: False

[CPU] OK
Name                      : Example Processor
NumberOfCores             : 8
NumberOfLogicalProcessors : 16

[DiskBenchmark] Skipped
  Note: Use -RunDiskBenchmark to opt in

[Guidance]
Installed memory: 32.0 GiB
CPU cores: 8
Interpret these observations against the requirements of your actual workload.
```

JSON is intended for scripts and inventory systems. `SchemaVersion` is currently `1`; consumers should check each section's `Status` before using `Data`.

## Requirements

- Windows 10 or 11 and Windows PowerShell 5.1 or PowerShell 7.
- CIM access for the relevant hardware sections. Storage cmdlets may be absent or restricted; fallback collection is attempted.
- `wsl.exe`, `nvidia-smi.exe`, and `winsat.exe` are optional. Their absence does not stop the audit.

## Privacy and security

Reports stay in the specified local folder. By default, the tool omits computer name, account and domain, serial and part numbers, device IDs, MAC and IP addresses, volume names, running services, and update history. `-IncludeIdentifiers` adds some device and account identifiers; keep those reports private. Review any report before sharing it. Error notes contain exception types rather than raw paths or command error text.

The tool makes no network requests. Its output can still reveal hardware inventory and Windows version, so treat both files as sensitive. WSL output is reduced to command success or failure; NVIDIA data remains a local tool result and should be reviewed before sharing.

## Limitations

- WMI GPU `AdapterRAM` can be wrong or capped. NVIDIA query success does not prove CUDA compatibility or model performance.
- Reported storage health is not a SMART diagnostic. WinSAT is an optional basic disk test, not a full benchmark.
- Readiness depends on the exact application, model size, memory needs, drivers, thermals, and security requirements. This report does not certify an AI workload.
- Permissions, missing drivers, and Windows variants can make sections unavailable. Check `Status` and `Note` rather than assuming missing data means missing hardware.

## Testing

Run the synthetic tests locally (no host inventory is read):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run.ps1
pwsh -NoProfile -File .\tests\run.ps1
```

The tests mock the collectors and optional commands, check success and failure paths, inspect report schema and privacy defaults, and verify that the benchmark is opt-in. The GitHub Actions workflow runs the same tests on Windows; it uploads no reports.

Parse check:

```powershell
$tokens = $errors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\full_system_audit.ps1), [ref]$tokens, [ref]$errors) | Out-Null
if ($errors) { $errors | Format-List; throw 'Parse failed' }
```

Smoke test locally with a private temporary output folder:

```powershell
.\full_system_audit.ps1 -OutputDirectory (Join-Path $env:TEMP 'system-audit-check')
```

Inspect the generated JSON for the expected `SchemaVersion` and section statuses. Do not commit generated reports. The benchmark option is intentionally excluded from the smoke test.

## License

[MIT](LICENSE)
