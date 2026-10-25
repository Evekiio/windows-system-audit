$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'full_system_audit.ps1'
$testRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'TestDrive'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-CimInstance {
    param([string]$ClassName, [string]$Filter)
    if ($global:AuditTestMode -eq 'Denied') { throw 'Synthetic access denied' }
    switch ($ClassName) {
        'Win32_ComputerSystem' { [pscustomobject]@{ Manufacturer='Example Corp'; Model='Synthetic PC'; TotalPhysicalMemory=34359738368L; Name='SYNTHETIC-HOST'; Domain='example.invalid'; UserName='synthetic-user' } }
        'Win32_OperatingSystem' { [pscustomobject]@{ Caption='Synthetic Windows'; Version='10.0'; BuildNumber='99999'; OSArchitecture='64-bit'; LastBootUpTime=[datetime]'2026-01-01' } }
        'Win32_Processor' { [pscustomobject]@{ Name='Synthetic CPU'; NumberOfCores=8; NumberOfLogicalProcessors=16; MaxClockSpeed=3200 } }
        'Win32_PhysicalMemory' { [pscustomobject]@{ Capacity=34359738368L; Speed=3200; ConfiguredClockSpeed=3200; Manufacturer='Example Corp'; PartNumber='SYNTHETIC-PART'; SerialNumber='SYNTHETIC-RAM-SERIAL'; DeviceLocator='Synthetic slot' } }
        'Win32_VideoController' { [pscustomobject]@{ Name='Synthetic GPU'; DriverVersion='1.0'; AdapterRAM=1073741824; Status='OK'; PNPDeviceID='SYNTHETIC-PNP' } }
        'Win32_DiskDrive' { [pscustomobject]@{ Model='Synthetic fallback disk'; InterfaceType='SATA'; Size=107374182400L; SerialNumber='SYNTHETIC-DISK-SERIAL' } }
        'Win32_LogicalDisk' { [pscustomobject]@{ Size=107374182400L; FreeSpace=53687091200L; FileSystem='NTFS'; DeviceID='Z:'; VolumeName='Synthetic volume' } }
        default { throw "Unexpected synthetic class: $ClassName" }
    }
}

function Get-PhysicalDisk {
    if ($global:AuditTestMode -eq 'Denied' -or $global:AuditTestMode -eq 'Fallback') { throw 'Synthetic physical disk unavailable' }
    [pscustomobject]@{ FriendlyName='Synthetic SSD'; MediaType='SSD'; BusType='NVMe'; Size=107374182400L; HealthStatus='Healthy'; SerialNumber='SYNTHETIC-DISK-SERIAL' }
}

function Get-Command {
    param([string]$Name)
    $leaf = Split-Path $Name -Leaf
    if ($leaf -in @('wsl.exe','nvidia-smi.exe','winsat.exe') -and $global:AuditTestMode -eq 'Denied') { return $null }
    if ($leaf -eq 'winsat.exe' -and $global:AuditTestMode -eq 'MissingBenchmark') { return $null }
    Microsoft.PowerShell.Core\Get-Command $leaf -ErrorAction SilentlyContinue
}

function wsl.exe { param([string]$Arg) $global:LASTEXITCODE=0; 'Synthetic WSL status' }
function nvidia-smi.exe { $global:LASTEXITCODE=0; 'Synthetic GPU, 4096 MiB, 1.0' }
function winsat.exe {
    $global:BenchmarkCalls++
    $global:LASTEXITCODE=0
    'Synthetic benchmark result'
}

function Invoke-TestAudit {
    param([string]$Case, [string]$Mode, [switch]$Identifiers, [switch]$Benchmark)
    $global:AuditTestMode = $Mode
    $dir = Join-Path $testRoot $Case
    & $scriptPath -OutputDirectory $dir -IncludeIdentifiers:$Identifiers -RunDiskBenchmark:$Benchmark | Out-Null
    $jsonFile = @(Get-ChildItem -LiteralPath $dir -Filter '*.json')
    $textFile = @(Get-ChildItem -LiteralPath $dir -Filter '*.txt')
    Assert-True ($jsonFile.Count -eq 1 -and $textFile.Count -eq 1) "$Case did not write both reports"
    $raw = [IO.File]::ReadAllText($jsonFile[0].FullName)
    $report = $raw | ConvertFrom-Json
    Assert-True ($report.SchemaVersion -eq 1) "$Case schema version"
    foreach ($name in @('System','OperatingSystem','CPU','Memory','GPU','Storage','Drives','WSL','NVIDIA','DiskBenchmark')) {
        Assert-True ($report.$name.Status -in @('OK','Unavailable','Skipped')) "$Case invalid $name status"
        Assert-True ($null -ne $report.$name.Data) "$Case missing $name data"
    }
    return [pscustomobject]@{ Report=$report; Raw=$raw; Text=[IO.File]::ReadAllText($textFile[0].FullName) }
}

try {
    $global:BenchmarkCalls = 0
    $ok = Invoke-TestAudit 'default' 'Success'
    Assert-True ($ok.Report.System.Status -eq 'OK' -and $ok.Report.Storage.Status -eq 'OK') 'Synthetic collection failed'
    Assert-True ($ok.Report.System.Data[0].Model -eq 'Synthetic PC') 'Synthetic model mismatch'
    Assert-True ($ok.Report.Guidance -contains 'CPU cores: 8') 'Guidance missing core count'
    Assert-True ($ok.Report.WSL.Data[0] -eq 'WSL command responded successfully') 'WSL output was not summarized'
    Assert-True ($ok.Report.DiskBenchmark.Status -eq 'Skipped' -and $global:BenchmarkCalls -eq 0) 'Benchmark ran without opt-in'
    foreach ($private in @('SYNTHETIC-HOST','synthetic-user','SYNTHETIC-RAM-SERIAL','SYNTHETIC-DISK-SERIAL','SYNTHETIC-PNP','Synthetic volume')) {
        Assert-True (-not $ok.Raw.Contains($private) -and -not $ok.Text.Contains($private)) "Default report leaked $private"
    }
    $ids = Invoke-TestAudit 'identifiers' 'Success' -Identifiers
    Assert-True ($ids.Report.IdentifiersIncluded -and $ids.Raw.Contains('SYNTHETIC-RAM-SERIAL')) 'Identifier opt-in failed'
    $fallback = Invoke-TestAudit 'fallback' 'Fallback'
    Assert-True ($fallback.Report.Storage.Status -eq 'OK' -and $fallback.Report.Storage.Data[0].MediaType -eq 'Unknown') 'Storage fallback failed'
    $denied = Invoke-TestAudit 'denied' 'Denied'
    Assert-True ($denied.Report.System.Status -eq 'Unavailable' -and $denied.Report.WSL.Status -eq 'Unavailable') 'Denied queries did not degrade gracefully'
    Assert-True (-not $denied.Raw.Contains('Synthetic access denied')) 'Error message leaked into JSON'
    $bench = Invoke-TestAudit 'benchmark' 'Success' -Benchmark
    Assert-True ($bench.Report.DiskBenchmark.Status -eq 'OK' -and $global:BenchmarkCalls -eq 1) 'Benchmark opt-in failed'
    $missingBench = Invoke-TestAudit 'missing-benchmark' 'MissingBenchmark' -Benchmark
    Assert-True ($missingBench.Report.DiskBenchmark.Status -eq 'Unavailable' -and $global:BenchmarkCalls -eq 1) 'Missing benchmark dependency was not reported'
    $rejected = $false
    try { & $scriptPath -OutputDirectory '\\example.invalid\share' | Out-Null } catch { $rejected = $_.Exception.Message -like '*Network and device output paths*' }
    Assert-True $rejected 'UNC output path was accepted'
    'PASS: synthetic collection, fallback, denied and missing dependencies, privacy, benchmark opt-in, schema'
} finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
    Remove-Variable AuditTestMode, BenchmarkCalls -Scope Global -ErrorAction SilentlyContinue
}
