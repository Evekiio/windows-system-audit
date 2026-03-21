#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Full Windows System Audit Script
.DESCRIPTION
    Collects hardware and environment information for assessment.
    Generates a human-readable TXT report and a structured JSON report.
    Includes a role recommendation for Development or Local AI Agent Hosting.
.NOTES
    Run as Administrator in PowerShell.
    Output files are saved to the current directory by default.
#>

param (
    [string]$OutputDir = (Get-Location).Path
)

$Timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$TxtReport  = Join-Path $OutputDir "system_audit_$Timestamp.txt"
$JsonReport = Join-Path $OutputDir "system_audit_$Timestamp.json"

$Report = [ordered]@{}

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
# ---------------------------------------------------------------------------
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
Write-Section "WSL Status"
$WslData = [ordered]@{ Installed = $false; Version = "N/A"; Distributions = @() }
try {
    $wslOutput = & wsl --list --verbose 2>&1
    if ($LASTEXITCODE -eq 0 -or ($wslOutput -join "" ) -match '\S') {
        $WslData.Installed = $true
        # Parse distribution lines (skip header)
        $distros = $wslOutput | Select-Object -Skip 1 | Where-Object { $_ -match '\S' } | ForEach-Object {
            ($_ -replace '^\*?\s+','').Trim()
        }
        $WslData.Distributions = $distros
        Write-KV "Installed" "Yes"
        Write-KV "Distributions" ($distros -join "; ")
    }
} catch {
    Write-KV "Installed" "No (wsl.exe not found)"
}
if (-not $WslData.Installed) { Write-KV "Installed" "No" }
$Report["WSL"] = $WslData

# ---------------------------------------------------------------------------
# 11. NVIDIA Status
# ---------------------------------------------------------------------------
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
# 12. Basic Disk Performance (measure write speed on system drive)
# ---------------------------------------------------------------------------
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
# ---------------------------------------------------------------------------
Write-Section "Role Recommendation"

$Score = [ordered]@{ Dev = 0; AIHost = 0 }
$Notes = @()

# CPU score
if ($CpuData.Cores -ge 8)         { $Score.Dev += 2; $Score.AIHost += 1 }
elseif ($CpuData.Cores -ge 4)     { $Score.Dev += 1 }
if ($CpuData.LogicalProcessors -ge 16) { $Score.Dev += 1; $Score.AIHost += 1 }

# RAM score
if ($Report.RAM.TotalGB -ge 64)   { $Score.Dev += 2; $Score.AIHost += 3 }
elseif ($Report.RAM.TotalGB -ge 32) { $Score.Dev += 2; $Score.AIHost += 2 }
elseif ($Report.RAM.TotalGB -ge 16) { $Score.Dev += 1; $Score.AIHost += 1 }
else { $Notes += "Low RAM (<16 GB) limits both roles." }

# GPU / NVIDIA score (AI hosting benefits greatly from NVIDIA GPU)
if ($NvidiaData.Detected) {
    $Score.AIHost += 4
    $Notes += "NVIDIA GPU detected — strong advantage for local AI model inference."
    if ($NvidiaData.SMIAvailable) { $Score.AIHost += 1 }
} else {
    $Notes += "No NVIDIA GPU — local LLM inference will rely on CPU only."
}

# Storage score
$SystemFreeGB = ($DriveList | Where-Object { $_.DeviceID -eq "C:" } | Select-Object -First 1).FreeGB
if ($null -ne $SystemFreeGB) {
    if ($SystemFreeGB -ge 100) { $Score.Dev += 1; $Score.AIHost += 1 }
    elseif ($SystemFreeGB -lt 20) { $Notes += "Low free space on C: ($SystemFreeGB GB) — consider cleanup." }
}

# Disk speed score (AI model loading benefits from fast storage)
if ($DiskPerfData.ReadSpeedMBs -ge 1000) { $Score.AIHost += 2; $Notes += "Fast storage (>1 GB/s read) — beneficial for loading large AI models." }
elseif ($DiskPerfData.ReadSpeedMBs -ge 400) { $Score.AIHost += 1 }

# WSL score (development)
if ($WslData.Installed) { $Score.Dev += 2; $Notes += "WSL installed — good for development workflows." }

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
}

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
Write-Host $Summary
