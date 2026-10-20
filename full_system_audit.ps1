[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'SystemAudit'),
    [switch]$IncludeIdentifiers,
    [switch]$RunDiskBenchmark
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') { throw 'This tool requires Windows.' }

function Read-Section {
    param([string]$Name, [scriptblock]$Action)
    try {
        $value = @(& $Action)
        if ($value.Count -eq 0) { return [pscustomobject]@{ Status = 'Unavailable'; Data = @(); Note = 'No data returned' } }
        return [pscustomobject]@{ Status = 'OK'; Data = $value; Note = $null }
    } catch {
        return [pscustomobject]@{ Status = 'Unavailable'; Data = @(); Note = $_.Exception.GetType().Name }
    }
}

function Invoke-OptionalCommand {
    param([string]$Name, [string[]]$Arguments)
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) { return [pscustomobject]@{ Status = 'Unavailable'; Note = "$Name was not found"; Data = @() } }
    try {
        $output = @(& $command.Source @Arguments 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { return [pscustomobject]@{ Status = 'Unavailable'; Note = "$Name exited with code $LASTEXITCODE"; Data = @() } }
        return [pscustomobject]@{ Status = 'OK'; Note = $null; Data = @($output) }
    } catch {
        return [pscustomobject]@{ Status = 'Unavailable'; Note = $_.Exception.GetType().Name; Data = @() }
    }
}

$system = Read-Section 'System' {
    Get-CimInstance Win32_ComputerSystem | ForEach-Object {
        $item = [ordered]@{ Manufacturer = $_.Manufacturer; Model = $_.Model; TotalMemoryBytes = $_.TotalPhysicalMemory }
        if ($IncludeIdentifiers) { $item.ComputerName = $_.Name; $item.Domain = $_.Domain; $item.UserName = $_.UserName }
        [pscustomobject]$item
    }
}
$os = Read-Section 'OperatingSystem' {
    Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, OSArchitecture, LastBootUpTime
}
$cpu = Read-Section 'CPU' {
    Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed
}
$memory = Read-Section 'Memory' {
    Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
        $item = [ordered]@{ CapacityBytes = $_.Capacity; SpeedMTs = $_.Speed; ConfiguredClockSpeedMTs = $_.ConfiguredClockSpeed }
        if ($IncludeIdentifiers) { $item.Manufacturer = $_.Manufacturer; $item.PartNumber = $_.PartNumber; $item.SerialNumber = $_.SerialNumber; $item.DeviceLocator = $_.DeviceLocator }
        [pscustomobject]$item
    }
}
$gpu = Read-Section 'GPU' {
    Get-CimInstance Win32_VideoController | ForEach-Object {
        $item = [ordered]@{ Name = $_.Name; DriverVersion = $_.DriverVersion; AdapterRAMBytes = $_.AdapterRAM; Status = $_.Status }
        if ($IncludeIdentifiers) { $item.PNPDeviceID = $_.PNPDeviceID }
        [pscustomobject]$item
    }
}
$storage = Read-Section 'Storage' {
    $physical = Get-PhysicalDisk -ErrorAction Stop
    foreach ($disk in $physical) {
        $item = [ordered]@{ FriendlyName = $disk.FriendlyName; MediaType = [string]$disk.MediaType; BusType = [string]$disk.BusType; SizeBytes = $disk.Size; HealthStatus = [string]$disk.HealthStatus }
        if ($IncludeIdentifiers) { $item.SerialNumber = $disk.SerialNumber }
        [pscustomobject]$item
    }
}
if ($storage.Status -ne 'OK') {
    $storage = Read-Section 'Storage' {
        Get-CimInstance Win32_DiskDrive | ForEach-Object {
            $item = [ordered]@{ FriendlyName = $_.Model; MediaType = 'Unknown'; BusType = $_.InterfaceType; SizeBytes = $_.Size; HealthStatus = 'Unknown' }
            if ($IncludeIdentifiers) { $item.SerialNumber = $_.SerialNumber }
            [pscustomobject]$item
        }
    }
}
$drives = Read-Section 'Drives' {
    Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
        $item = [ordered]@{ SizeBytes = $_.Size; FreeBytes = $_.FreeSpace; FileSystem = $_.FileSystem }
        if ($IncludeIdentifiers) { $item.DeviceID = $_.DeviceID; $item.VolumeName = $_.VolumeName }
        [pscustomobject]$item
    }
}
$wsl = Invoke-OptionalCommand 'wsl.exe' @('--status')
$nvidia = Invoke-OptionalCommand 'nvidia-smi.exe' @('--query-gpu=name,memory.total,driver_version', '--format=csv,noheader')
$benchmark = [pscustomobject]@{ Status = 'Skipped'; Note = 'Use -RunDiskBenchmark to opt in'; Data = @() }
if ($RunDiskBenchmark) { $benchmark = Invoke-OptionalCommand 'winsat.exe' @('disk', '-drive', $env:SystemDrive.TrimEnd(':')) }

$ramBytes = if ($system.Status -eq 'OK') { $system.Data[0].TotalMemoryBytes } else { $null }
$cores = if ($cpu.Status -eq 'OK') { ($cpu.Data | Measure-Object NumberOfCores -Sum).Sum } else { $null }
$observations = @()
if ($null -ne $ramBytes) { $observations += ('Installed memory: {0:N1} GiB' -f ($ramBytes / 1GB)) }
if ($null -ne $cores) { $observations += "CPU cores: $cores" }
if ($gpu.Status -eq 'OK') { $observations += 'GPU detected; reported adapter memory may be inaccurate. Check workload requirements separately.' }
if ($nvidia.Status -eq 'OK') { $observations += 'NVIDIA query succeeded; this does not verify CUDA or model performance.' }
if ($storage.Status -eq 'OK') { $observations += 'Storage health is a device-reported summary, not a diagnostic test.' }

$report = [ordered]@{
    SchemaVersion = 1
    GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    IdentifiersIncluded = [bool]$IncludeIdentifiers
    System = $system
    OperatingSystem = $os
    CPU = $cpu
    Memory = $memory
    GPU = $gpu
    Storage = $storage
    Drives = $drives
    WSL = $wsl
    NVIDIA = $nvidia
    DiskBenchmark = $benchmark
    Guidance = $observations
}

$resolvedDirectory = [IO.Path]::GetFullPath($OutputDirectory)
[void][IO.Directory]::CreateDirectory($resolvedDirectory)
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmss_fff')
$stem = "system_audit_$stamp"
$jsonPath = Join-Path $resolvedDirectory "$stem.json"
$textPath = Join-Path $resolvedDirectory "$stem.txt"
$json = $report | ConvertTo-Json -Depth 8
$lines = @('WINDOWS SYSTEM AUDIT', "Generated (UTC): $($report.GeneratedAtUtc)", "Identifiers included: $([bool]$IncludeIdentifiers)", '')
foreach ($name in @('System','OperatingSystem','CPU','Memory','GPU','Storage','Drives','WSL','NVIDIA','DiskBenchmark')) {
    $section = $report[$name]
    $lines += "[$name] $($section.Status)"
    if ($section.Note) { $lines += "  Note: $($section.Note)" }
    if ($section.Status -eq 'OK') { $lines += ($section.Data | Format-List | Out-String).TrimEnd() }
    $lines += ''
}
$lines += '[Guidance]'
$lines += $observations
$lines += 'Interpret these observations against the requirements of your actual workload.'
[IO.File]::WriteAllText($jsonPath, $json, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllLines($textPath, [string[]]$lines, [Text.UTF8Encoding]::new($false))
Write-Output "Text report: $textPath"
Write-Output "JSON report: $jsonPath"
