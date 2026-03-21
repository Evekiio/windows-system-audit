#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Full Windows System Audit Script
.DESCRIPTION
    Collects hardware and environment information for assessment.
    Generates a human-readable TXT report and a structured JSON report.
    Includes a role recommendation for Development or Local AI Agent Hosting.
.PARAMETER OutputDir
    Directory where the TXT and JSON reports will be saved.
    Defaults to the current working directory.
.EXAMPLE
    .\full_system_audit.ps1
    Runs the audit and saves reports to the current directory.
.EXAMPLE
    .\full_system_audit.ps1 -OutputDir "C:\AuditReports"
    Saves reports to C:\AuditReports.
.NOTES
    Must be run as Administrator.
    Requires PowerShell 5.1 or later.
    No external modules or internet access required.
#>

param (
    [string]$OutputDir = (Get-Location).Path
)

$Timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$TxtReport  = Join-Path $OutputDir "system_audit_$Timestamp.txt"
$JsonReport = Join-Path $OutputDir "system_audit_$Timestamp.json"

$Report = [ordered]@{}

Write-Host ""
Write-Host "  Windows System Audit" -ForegroundColor Cyan
Write-Host "  Output directory : $OutputDir" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------------------
# Helper: write a section header to the TXT stream
# ---------------------------------------------------------------------------
function Write-Section {
    param([string]$Title)
    $line = "=" * 60
    Add-Content -Path $TxtReport -Value "`n$line"
    Add-Content -Path $TxtReport -Value "  $Title"
    Add-Content -Path $TxtReport -Value $line
}

# ---------------------------------------------------------------------------
# Helper: append a key-value pair to TXT
# ---------------------------------------------------------------------------
function Write-KV {
    param([string]$Key, $Value)
    Add-Content -Path $TxtReport -Value ("  {0,-30} {1}" -f "$Key :", $Value)
}

# ---------------------------------------------------------------------------
# 1. OS Information
# ---------------------------------------------------------------------------
Write-Host "  [1/13] Operating System..." -ForegroundColor Gray
Write-Section "Operating System"
$OS = Get-CimInstance Win32_OperatingSystem
$OsData = [ordered]@{
    Caption        = $OS.Caption
    Version        = $OS.Version
    BuildNumber    = $OS.BuildNumber
    Architecture   = $OS.OSArchitecture
    InstallDate    = $OS.InstallDate.ToString("yyyy-MM-dd")
    LastBoot       = $OS.LastBootUpTime.ToString("yyyy-MM-dd HH:mm:ss")
    RegisteredUser = $OS.RegisteredUser
}
foreach ($k in $OsData.Keys) { Write-KV $k $OsData[$k] }
$Report["OS"] = $OsData

# ---------------------------------------------------------------------------
# 2. CPU
# ---------------------------------------------------------------------------
Write-Host "  [2/13] CPU..." -ForegroundColor Gray
Write-Section "CPU"
$CPU = Get-CimInstance Win32_Processor | Select-Object -First 1
$CpuData = [ordered]@{
    Name              = $CPU.Name.Trim()
    Manufacturer      = $CPU.Manufacturer
    Cores             = $CPU.NumberOfCores
    LogicalProcessors = $CPU.NumberOfLogicalProcessors
    MaxClockSpeedMHz  = $CPU.MaxClockSpeed
    Architecture      = switch ($CPU.Architecture) {
        0 { "x86" } 1 { "MIPS" } 2 { "Alpha" } 3 { "PowerPC" }
        5 { "ARM" } 6 { "Itanium" } 9 { "x64" } default { "Unknown" }
    }
    L2CacheKB         = [math]::Round($CPU.L2CacheSize, 0)
    L3CacheKB         = [math]::Round($CPU.L3CacheSize, 0)
}
foreach ($k in $CpuData.Keys) { Write-KV $k $CpuData[$k] }
$Report["CPU"] = $CpuData

# ---------------------------------------------------------------------------
# 3. RAM
# ---------------------------------------------------------------------------
Write-Host "  [3/13] RAM..." -ForegroundColor Gray
Write-Section "RAM"
$RamModules = Get-CimInstance Win32_PhysicalMemory
$TotalRamGB = [math]::Round(($RamModules | Measure-Object -Property Capacity -Sum).Sum / 1GB, 2)
$RamList = @()
foreach ($mod in $RamModules) {
    $entry = [ordered]@{
        BankLabel   = $mod.BankLabel
        DeviceLocator = $mod.DeviceLocator
        CapacityGB  = [math]::Round($mod.Capacity / 1GB, 2)
        SpeedMHz    = $mod.Speed
        MemoryType  = switch ($mod.SMBIOSMemoryType) {
            20 { "DDR" } 21 { "DDR2" } 24 { "DDR3" } 26 { "DDR4" } 34 { "DDR5" } default { "Unknown ($($mod.SMBIOSMemoryType))" }
        }
        Manufacturer = $mod.Manufacturer
        PartNumber   = $mod.PartNumber.Trim()
    }
    $RamList += $entry
    Write-KV "Slot $($mod.DeviceLocator)" "$($entry.CapacityGB) GB  $($entry.SpeedMHz) MHz  $($entry.MemoryType)  $($entry.Manufacturer)"
}
Write-KV "Total RAM" "$TotalRamGB GB"
$Report["RAM"] = [ordered]@{ TotalGB = $TotalRamGB; Modules = $RamList }

# ---------------------------------------------------------------------------
# 4. Motherboard
# ---------------------------------------------------------------------------
Write-Host "  [4/13] Motherboard..." -ForegroundColor Gray
Write-Section "Motherboard"
$MB = Get-CimInstance Win32_BaseBoard | Select-Object -First 1
$MbData = [ordered]@{
    Manufacturer = $MB.Manufacturer
    Product      = $MB.Product
    SerialNumber = $MB.SerialNumber
    Version      = $MB.Version
}
foreach ($k in $MbData.Keys) { Write-KV $k $MbData[$k] }
$Report["Motherboard"] = $MbData

# ---------------------------------------------------------------------------
# 5. BIOS
# ---------------------------------------------------------------------------
Write-Host "  [5/13] BIOS..." -ForegroundColor Gray
Write-Section "BIOS"
$BIOS = Get-CimInstance Win32_BIOS | Select-Object -First 1
$BiosData = [ordered]@{
    Manufacturer = $BIOS.Manufacturer
    Name         = $BIOS.Name
    Version      = $BIOS.SMBIOSBIOSVersion
    ReleaseDate  = $BIOS.ReleaseDate.ToString("yyyy-MM-dd")
}
foreach ($k in $BiosData.Keys) { Write-KV $k $BiosData[$k] }
$Report["BIOS"] = $BiosData

# ---------------------------------------------------------------------------
# 6. GPU
# Note: Win32_VideoController.AdapterRAM is a 32-bit WMI property capped at
# 4 GB (4096 MB). For GPUs with more VRAM, rely on nvidia-smi (section 11).
# ---------------------------------------------------------------------------
Write-Host "  [6/13] GPU..." -ForegroundColor Gray
Write-Section "GPU"
$GPUs = Get-CimInstance Win32_VideoController
$GpuList = @()
foreach ($gpu in $GPUs) {
    $entry = [ordered]@{
        Name            = $gpu.Name
        AdapterRAMMB    = [math]::Round($gpu.AdapterRAM / 1MB, 0)
        DriverVersion   = $gpu.DriverVersion
        VideoModeDesc   = $gpu.VideoModeDescription
        Status          = $gpu.Status
    }
    $GpuList += $entry
    Write-KV "GPU" $entry.Name
    Write-KV "  VRAM (MB)" $entry.AdapterRAMMB
    Write-KV "  Driver" $entry.DriverVersion
    Write-KV "  Status" $entry.Status
}
$Report["GPU"] = $GpuList

# ---------------------------------------------------------------------------
# 7. Storage (Physical Disks)
# ---------------------------------------------------------------------------
Write-Host "  [7/13] Physical Disks..." -ForegroundColor Gray
Write-Section "Storage (Physical Disks)"
$Disks = Get-CimInstance Win32_DiskDrive
$DiskList = @()
foreach ($disk in $Disks) {
    $entry = [ordered]@{
        Model          = $disk.Model
        Index          = $disk.Index
        SizeGB         = [math]::Round($disk.Size / 1GB, 2)
        InterfaceType  = $disk.InterfaceType
        MediaType      = $disk.MediaType
        SerialNumber   = $disk.SerialNumber.Trim()
        Partitions     = $disk.Partitions
    }
    $DiskList += $entry
    Write-KV "Disk $($disk.Index)" "$($entry.Model)  $($entry.SizeGB) GB  $($entry.InterfaceType)"
}
$Report["PhysicalDisks"] = $DiskList

# ---------------------------------------------------------------------------
# 8. Logical Drives
# ---------------------------------------------------------------------------
Write-Host "  [8/13] Logical Drives..." -ForegroundColor Gray
Write-Section "Logical Drives"
$LogicalDrives = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -in 2,3 }
$DriveList = @()
foreach ($drv in $LogicalDrives) {
    $entry = [ordered]@{
        DeviceID    = $drv.DeviceID
        VolumeName  = $drv.VolumeName
        FileSystem  = $drv.FileSystem
        SizeGB      = [math]::Round($drv.Size / 1GB, 2)
        FreeGB      = [math]::Round($drv.FreeSpace / 1GB, 2)
        UsedPercent = if ($drv.Size -gt 0) { [math]::Round((1 - $drv.FreeSpace / $drv.Size) * 100, 1) } else { 0 }
    }
    $DriveList += $entry
    Write-KV "$($drv.DeviceID) $($drv.VolumeName)" "$($entry.FreeGB) GB free / $($entry.SizeGB) GB  ($($entry.UsedPercent)% used)  [$($entry.FileSystem)]"
}
$Report["LogicalDrives"] = $DriveList

# ---------------------------------------------------------------------------
# 9. Network Adapters
# ---------------------------------------------------------------------------
Write-Host "  [9/13] Network Adapters..." -ForegroundColor Gray
Write-Section "Network Adapters"
$Adapters = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true }
$AdapterList = @()
foreach ($nic in $Adapters) {
    $entry = [ordered]@{
        Description  = $nic.Description
        MACAddress   = $nic.MACAddress
        IPAddresses  = ($nic.IPAddress -join ", ")
        DefaultGW    = ($nic.DefaultIPGateway -join ", ")
        DNSServers   = ($nic.DNSServerSearchOrder -join ", ")
        DHCPEnabled  = $nic.DHCPEnabled
    }
    $AdapterList += $entry
    Write-KV "Adapter" $entry.Description
    Write-KV "  MAC" $entry.MACAddress
    Write-KV "  IP" $entry.IPAddresses
    Write-KV "  Gateway" $entry.DefaultGW
}
$Report["NetworkAdapters"] = $AdapterList

# ---------------------------------------------------------------------------
# 10. WSL Status
# ---------------------------------------------------------------------------
Write-Host "  [10/13] WSL Status..." -ForegroundColor Gray
Write-Section "WSL Status"
$WslData = [ordered]@{ Installed = $false; Distributions = @() }
try {
    $wslOutput = & wsl --list --verbose 2>&1
    if ($LASTEXITCODE -eq 0) {
        $WslData.Installed = $true
        # Parse distribution lines (skip header); filter to non-empty lines
        $distros = $wslOutput | Select-Object -Skip 1 | Where-Object { $_ -match '\S' } | ForEach-Object {
            ($_ -replace '^\*?\s+','').Trim()
        }
        $WslData.Distributions = $distros
        $distroString = if ($distros) { $distros -join "; " } else { "(none)" }
        Write-KV "Installed" "Yes"
        Write-KV "Distributions" $distroString
    } else {
        Write-KV "Installed" "No"
    }
} catch {
    # wsl.exe not found or returned a terminating error
    Write-KV "Installed" "No (wsl.exe not found)"
}
$Report["WSL"] = $WslData

# ---------------------------------------------------------------------------
# 11. NVIDIA Status
# ---------------------------------------------------------------------------
Write-Host "  [11/13] NVIDIA Status..." -ForegroundColor Gray
Write-Section "NVIDIA Status"
$NvidiaData = [ordered]@{ Detected = $false; SMIAvailable = $false; GPUs = @() }

$nvidiaGpus = $GPUs | Where-Object { $_.Name -match "NVIDIA" }
if ($nvidiaGpus) {
    $NvidiaData.Detected = $true
    Write-KV "NVIDIA GPU" ($nvidiaGpus | ForEach-Object { $_.Name } | Select-Object -First 1)
}

$nvidiaSmi = Get-Command "nvidia-smi.exe" -ErrorAction SilentlyContinue
if ($nvidiaSmi) {
    $NvidiaData.SMIAvailable = $true
    try {
        $smiOut = & nvidia-smi --query-gpu=name,driver_version,memory.total,temperature.gpu --format=csv,noheader 2>&1
        Write-KV "nvidia-smi" "Available"
        $smiOut | ForEach-Object {
            $parts = $_ -split ","
            if ($parts.Count -ge 4) {
                $gpuEntry = [ordered]@{
                    Name          = $parts[0].Trim()
                    DriverVersion = $parts[1].Trim()
                    MemoryTotal   = $parts[2].Trim()
                    TempC         = $parts[3].Trim()
                }
                $NvidiaData.GPUs += $gpuEntry
                Write-KV "  GPU Name" $gpuEntry.Name
                Write-KV "  Driver" $gpuEntry.DriverVersion
                Write-KV "  VRAM" $gpuEntry.MemoryTotal
                Write-KV "  Temp (C)" $gpuEntry.TempC
            }
        }
    } catch {
        Write-KV "nvidia-smi" "Error running nvidia-smi"
    }
} else {
    Write-KV "nvidia-smi" "Not found in PATH"
}
if (-not $NvidiaData.Detected) { Write-KV "NVIDIA GPU" "Not detected" }
$Report["NVIDIA"] = $NvidiaData

# ---------------------------------------------------------------------------
# 12. Basic Disk Performance
# Measures sequential write and read speed using a 128 MB buffer written to
# $env:TEMP (typically on C:). Results reflect the speed of that volume.
# ---------------------------------------------------------------------------
Write-Host "  [12/13] Disk Performance (128 MB test)..." -ForegroundColor Gray
Write-Section "Basic Disk Performance"
$DiskPerfData = [ordered]@{}
try {
    $TestFile = Join-Path $env:TEMP "audit_disktest.tmp"
    $BlockSizeMB = 128
    $Buffer = [byte[]]::new($BlockSizeMB * 1MB)
    (New-Object System.Random).NextBytes($Buffer)

    # Write test
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    [System.IO.File]::WriteAllBytes($TestFile, $Buffer)
    $sw.Stop()
    $WriteSpeedMBs = [math]::Round($BlockSizeMB / $sw.Elapsed.TotalSeconds, 1)

    # Read test
    $sw.Restart()
    $null = [System.IO.File]::ReadAllBytes($TestFile)
    $sw.Stop()
    $ReadSpeedMBs = [math]::Round($BlockSizeMB / $sw.Elapsed.TotalSeconds, 1)

    Remove-Item $TestFile -Force -ErrorAction SilentlyContinue

    $DiskPerfData = [ordered]@{
        TestSizeMB       = $BlockSizeMB
        WriteSpeedMBs    = $WriteSpeedMBs
        ReadSpeedMBs     = $ReadSpeedMBs
    }
    Write-KV "Test Size" "$BlockSizeMB MB"
    Write-KV "Write Speed" "$WriteSpeedMBs MB/s"
    Write-KV "Read Speed"  "$ReadSpeedMBs MB/s"
} catch {
    Write-KV "Error" "Disk performance test failed: $_"
    $DiskPerfData = [ordered]@{ Error = $_.ToString() }
}
$Report["DiskPerformance"] = $DiskPerfData

# ---------------------------------------------------------------------------
# 13. Role Recommendation
# Weighted scoring: each factor adds points to one or both roles.
# Development:       CPU cores, logical processors, RAM, WSL, free disk
# Local AI Hosting:  NVIDIA GPU (+nvidia-smi), CPU cores, RAM, disk speed, free disk
# ---------------------------------------------------------------------------
Write-Host "  [13/13] Role Recommendation..." -ForegroundColor Gray
Write-Section "Role Recommendation"

$Score = [ordered]@{ Dev = 0; AIHost = 0 }
$Notes = @()
$Factors = @()   # per-factor lines for the TXT report

# CPU score
if ($CpuData.Cores -ge 8) {
    $Score.Dev += 2; $Score.AIHost += 1
    $Factors += "CPU cores ($($CpuData.Cores)) >= 8           Dev +2  AIHost +1"
} elseif ($CpuData.Cores -ge 4) {
    $Score.Dev += 1
    $Factors += "CPU cores ($($CpuData.Cores)) >= 4           Dev +1"
}
if ($CpuData.LogicalProcessors -ge 16) {
    $Score.Dev += 1; $Score.AIHost += 1
    $Factors += "Logical CPUs ($($CpuData.LogicalProcessors)) >= 16    Dev +1  AIHost +1"
}

# RAM score
$TotalRamGB = $Report["RAM"].TotalGB
if ($TotalRamGB -ge 64) {
    $Score.Dev += 2; $Score.AIHost += 3
    $Factors += "RAM ($TotalRamGB GB) >= 64 GB             Dev +2  AIHost +3"
} elseif ($TotalRamGB -ge 32) {
    $Score.Dev += 2; $Score.AIHost += 2
    $Factors += "RAM ($TotalRamGB GB) >= 32 GB             Dev +2  AIHost +2"
} elseif ($TotalRamGB -ge 16) {
    $Score.Dev += 1; $Score.AIHost += 1
    $Factors += "RAM ($TotalRamGB GB) >= 16 GB             Dev +1  AIHost +1"
} else {
    $Notes += "Low RAM (<16 GB) limits both roles."
    $Factors += "RAM ($TotalRamGB GB) < 16 GB              (no points — too low)"
}

# GPU / NVIDIA score
if ($NvidiaData.Detected) {
    $Score.AIHost += 4
    $Factors += "NVIDIA GPU detected                    AIHost +4"
    $Notes += "NVIDIA GPU detected — strong advantage for local AI model inference."
    if ($NvidiaData.SMIAvailable) {
        $Score.AIHost += 1
        $Factors += "nvidia-smi available                   AIHost +1"
    }
} else {
    $Notes += "No NVIDIA GPU — local LLM inference will rely on CPU only."
    $Factors += "No NVIDIA GPU                          (no points)"
}

# Free disk space on C:
$SystemFreeGB = ($DriveList | Where-Object { $_.DeviceID -eq "C:" } | Select-Object -First 1).FreeGB
if ($null -ne $SystemFreeGB) {
    if ($SystemFreeGB -ge 100) {
        $Score.Dev += 1; $Score.AIHost += 1
        $Factors += "Free space on C: ($SystemFreeGB GB) >= 100 GB  Dev +1  AIHost +1"
    } elseif ($SystemFreeGB -lt 20) {
        $Notes += "Low free space on C: ($SystemFreeGB GB) — consider cleanup."
        $Factors += "Free space on C: ($SystemFreeGB GB) < 20 GB   (no points — too low)"
    } else {
        $Factors += "Free space on C: ($SystemFreeGB GB)            (no bonus threshold)"
    }
}

# Disk read speed
if ($DiskPerfData.ReadSpeedMBs -ge 1000) {
    $Score.AIHost += 2
    $Notes += "Fast storage (>1 GB/s read) — beneficial for loading large AI models."
    $Factors += "Read speed ($($DiskPerfData.ReadSpeedMBs) MB/s) >= 1000   AIHost +2"
} elseif ($DiskPerfData.ReadSpeedMBs -ge 400) {
    $Score.AIHost += 1
    $Factors += "Read speed ($($DiskPerfData.ReadSpeedMBs) MB/s) >= 400    AIHost +1"
} else {
    $Factors += "Read speed ($($DiskPerfData.ReadSpeedMBs) MB/s) < 400     (no points)"
}

# WSL
if ($WslData.Installed) {
    $Score.Dev += 2
    $Notes += "WSL installed — good for development workflows."
    $Factors += "WSL installed                          Dev +2"
} else {
    $Factors += "WSL not installed                      (no Dev bonus)"
}

# Determine recommendation
$Recommendation = if ($Score.AIHost -gt $Score.Dev) {
    "LOCAL AI AGENT HOSTING"
} elseif ($Score.Dev -gt $Score.AIHost) {
    "DEVELOPMENT"
} else {
    "BALANCED (suitable for both roles)"
}

$RecommendationData = [ordered]@{
    Recommendation = $Recommendation
    ScoreDev       = $Score.Dev
    ScoreAIHost    = $Score.AIHost
    Notes          = $Notes
    Factors        = $Factors
}

# Per-factor breakdown in TXT
Add-Content -Path $TxtReport -Value ""
Add-Content -Path $TxtReport -Value "  Factor breakdown:"
foreach ($f in $Factors) { Add-Content -Path $TxtReport -Value "    $f" }
Add-Content -Path $TxtReport -Value ""

Write-KV "Development Score"     $Score.Dev
Write-KV "AI Host Score"         $Score.AIHost
Write-KV "Recommendation"        $Recommendation
Add-Content -Path $TxtReport -Value ""
foreach ($note in $Notes) { Add-Content -Path $TxtReport -Value "  * $note" }
$Report["RoleRecommendation"] = $RecommendationData

# ---------------------------------------------------------------------------
# Write JSON report
# ---------------------------------------------------------------------------
$Report | ConvertTo-Json -Depth 10 | Set-Content -Path $JsonReport -Encoding UTF8

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
$Summary = @"

============================================================
  Audit complete: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
  TXT report : $TxtReport
  JSON report: $JsonReport
============================================================
"@
Add-Content -Path $TxtReport -Value $Summary
Write-Host $Summary -ForegroundColor Green
