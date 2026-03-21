# full_system_audit.ps1
# Generates a complete Windows system audit report for workstation role planning.
# Outputs:
#   1. Human-readable TXT report
#   2. Structured JSON report

[CmdletBinding()]
param(
    [string]$OutputDirectory = "$env:USERPROFILE\Desktop\SystemAudit"
)

$ErrorActionPreference = "SilentlyContinue"

# ---------------------------------------------------------
# Helpers
# ---------------------------------------------------------

function New-Section {
    param([string]$Title)
    return "`r`n===== $Title =====`r`n"
}

function Format-Bytes {
    param([Nullable[UInt64]]$Bytes)

    if ($null -eq $Bytes) { return "N/A" }

    if ($Bytes -ge 1TB) { return ("{0:N2} TB" -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ("{0:N2} GB" -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ("{0:N2} MB" -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ("{0:N2} KB" -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

function Format-DateSafe {
    param($DateValue)

    if ($null -eq $DateValue) { return "N/A" }

    try {
        return ([datetime]$DateValue).ToString("yyyy-MM-dd HH:mm:ss")
    }
    catch {
        return "$DateValue"
    }
}

function Write-KeyValue {
    param(
        [string]$Key,
        [string]$Value
    )
    return ("{0,-35}: {1}" -f $Key, $Value)
}

function Get-CommandOutput {
    param(
        [string]$FilePath,
        [string[]]$Arguments = @()
    )

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $FilePath
        $psi.Arguments = ($Arguments -join " ")
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()

        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut   = $stdout.Trim()
            StdErr   = $stderr.Trim()
        }
    }
    catch {
        return [pscustomobject]@{
            ExitCode = -1
            StdOut   = ""
            StdErr   = $_.Exception.Message
        }
    }
}

function Add-TextBlock {
    param(
        [System.Text.StringBuilder]$Builder,
        [string]$Text
    )
    [void]$Builder.AppendLine($Text)
}

function Add-Lines {
    param(
        [System.Text.StringBuilder]$Builder,
        [object[]]$Lines
    )
    foreach ($line in $Lines) {
        [void]$Builder.AppendLine([string]$line)
    }
}

# ---------------------------------------------------------
# Prep output paths
# ---------------------------------------------------------

if (-not (Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$computerName = $env:COMPUTERNAME
$txtPath = Join-Path $OutputDirectory "${computerName}_system_audit_${timestamp}.txt"
$jsonPath = Join-Path $OutputDirectory "${computerName}_system_audit_${timestamp}.json"

# ---------------------------------------------------------
# Collect data
# ---------------------------------------------------------

$computerSystem = Get-CimInstance Win32_ComputerSystem
$operatingSystem = Get-CimInstance Win32_OperatingSystem
$bios = Get-CimInstance Win32_BIOS
$baseBoard = Get-CimInstance Win32_BaseBoard
$processor = Get-CimInstance Win32_Processor
$physicalMemory = Get-CimInstance Win32_PhysicalMemory
$videoControllers = Get-CimInstance Win32_VideoController
$logicalDisks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
$diskDrives = Get-CimInstance Win32_DiskDrive
$networkAdapters = Get-NetAdapter
$ipConfig = Get-NetIPConfiguration
$hotfixes = Get-HotFix | Sort-Object InstalledOn -Descending
$services = Get-Service | Sort-Object Name

$physicalDisks = Get-PhysicalDisk
$partitions = Get-Partition
$volumes = Get-Volume

$ramTotalBytes = ($physicalMemory | Measure-Object -Property Capacity -Sum).Sum
$ramModules = $physicalMemory | ForEach-Object {
    [pscustomobject]@{
        Manufacturer = $_.Manufacturer
        CapacityBytes = $_.Capacity
        Capacity = Format-Bytes $_.Capacity
        SpeedMTs = $_.Speed
        ConfiguredClockSpeed = $_.ConfiguredClockSpeed
        PartNumber = $_.PartNumber
        SerialNumber = $_.SerialNumber
        DeviceLocator = $_.DeviceLocator
        BankLabel = $_.BankLabel
    }
}

$cpuData = $processor | ForEach-Object {
    [pscustomobject]@{
        Name = $_.Name
        Manufacturer = $_.Manufacturer
        Cores = $_.NumberOfCores
        LogicalProcessors = $_.NumberOfLogicalProcessors
        MaxClockMHz = $_.MaxClockSpeed
        Socket = $_.SocketDesignation
        L2CacheKB = $_.L2CacheSize
        L3CacheKB = $_.L3CacheSize
        VirtualizationFirmwareEnabled = $computerSystem.HypervisorPresent
    }
}

$gpuData = $videoControllers | ForEach-Object {
    [pscustomobject]@{
        Name = $_.Name
        DriverVersion = $_.DriverVersion
        VideoProcessor = $_.VideoProcessor
        AdapterRAMBytes = $_.AdapterRAM
        AdapterRAM = Format-Bytes $_.AdapterRAM
        Resolution = if ($_.CurrentHorizontalResolution -and $_.CurrentVerticalResolution) {
            "$($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)"
        } else {
            "N/A"
        }
        Status = $_.Status
        PNPDeviceID = $_.PNPDeviceID
    }
}

$storageData = @()

if ($physicalDisks) {
    $storageData = $physicalDisks | ForEach-Object {
        [pscustomobject]@{
            FriendlyName = $_.FriendlyName
            MediaType = $_.MediaType
            BusType = $_.BusType
            SizeBytes = $_.Size
            Size = Format-Bytes $_.Size
            HealthStatus = $_.HealthStatus
            OperationalStatus = ($_.OperationalStatus -join ", ")
            SerialNumber = $_.SerialNumber
            FirmwareVersion = $_.FirmwareVersion
        }
    }
}
else {
    $storageData = $diskDrives | ForEach-Object {
        [pscustomobject]@{
            FriendlyName = $_.Model
            MediaType = "Unknown"
            BusType = $_.InterfaceType
            SizeBytes = $_.Size
            Size = Format-Bytes $_.Size
            HealthStatus = "Unknown"
            OperationalStatus = "Unknown"
            SerialNumber = $_.SerialNumber
            FirmwareVersion = $_.FirmwareRevision
        }
    }
}

$logicalDriveData = $logicalDisks | ForEach-Object {
    [pscustomobject]@{
        DeviceID = $_.DeviceID
        VolumeName = $_.VolumeName
        FileSystem = $_.FileSystem
        SizeBytes = $_.Size
        FreeBytes = $_.FreeSpace
        UsedBytes = ($_.Size - $_.FreeSpace)
        Size = Format-Bytes $_.Size
        Free = Format-Bytes $_.FreeSpace
        Used = Format-Bytes ($_.Size - $_.FreeSpace)
    }
}

$netData = $networkAdapters | ForEach-Object {
    $cfg = $ipConfig | Where-Object { $_.InterfaceAlias -eq $_.Name }
    [pscustomobject]@{
        Name = $_.Name
        InterfaceDescription = $_.InterfaceDescription
        Status = $_.Status
        MacAddress = $_.MacAddress
        LinkSpeed = $_.LinkSpeed
        DriverInformation = $_.DriverInformation
        InterfaceIndex = $_.ifIndex
    }
}

# ---------------------------------------------------------
# External command checks
# ---------------------------------------------------------

$wslStatus = Get-CommandOutput -FilePath "wsl.exe" -Arguments @("--status")
$wslList = Get-CommandOutput -FilePath "wsl.exe" -Arguments @("-l", "-v")
$nvidiaSmi = Get-CommandOutput -FilePath "nvidia-smi.exe"

# Basic disk benchmark
$winsatDisk = Get-CommandOutput -FilePath "winsat.exe" -Arguments @("disk", "-drive", "c")

# ---------------------------------------------------------
# Role inference
# ---------------------------------------------------------

$hasNvidia = $false
$gpuNames = @($gpuData | ForEach-Object { $_.Name })
if ($gpuNames -match "NVIDIA") { $hasNvidia = $true }

$nvmePresent = $false
foreach ($disk in $storageData) {
    if ("$($disk.BusType)" -match "NVMe") {
        $nvmePresent = $true
        break
    }
}

$totalRamGB = 0
if ($ramTotalBytes) {
    $totalRamGB = [math]::Round(($ramTotalBytes / 1GB), 2)
}

$totalLogicalProcessors = ($processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
$totalCores = ($processor | Measure-Object -Property NumberOfCores -Sum).Sum

$agentScore = 0
if ($hasNvidia) { $agentScore += 3 }
if ($nvmePresent) { $agentScore += 2 }
if ($totalRamGB -ge 64) { $agentScore += 3 }
elseif ($totalRamGB -ge 32) { $agentScore += 2 }
elseif ($totalRamGB -ge 16) { $agentScore += 1 }

if ($totalCores -ge 16) { $agentScore += 3 }
elseif ($totalCores -ge 8) { $agentScore += 2 }
elseif ($totalCores -ge 4) { $agentScore += 1 }

$roleRecommendation = if ($agentScore -ge 8) {
    "Strong candidate for Agent PC"
}
elseif ($agentScore -ge 5) {
    "Possible Agent PC, validate model size expectations carefully"
}
else {
    "Better suited for Dev / Personal Control PC"
}

# ---------------------------------------------------------
# Structured object for JSON
# ---------------------------------------------------------

$auditObject = [pscustomobject]@{
    AuditTimestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    ComputerName = $computerName
    System = [pscustomobject]@{
        Manufacturer = $computerSystem.Manufacturer
        Model = $computerSystem.Model
        SystemType = $computerSystem.SystemType
        Domain = $computerSystem.Domain
        TotalPhysicalMemoryBytes = $computerSystem.TotalPhysicalMemory
        TotalPhysicalMemory = Format-Bytes $computerSystem.TotalPhysicalMemory
        Username = $computerSystem.UserName
    }
    OperatingSystem = [pscustomobject]@{
        Caption = $operatingSystem.Caption
        Version = $operatingSystem.Version
        BuildNumber = $operatingSystem.BuildNumber
        InstallDate = Format-DateSafe $operatingSystem.InstallDate
        LastBootUpTime = Format-DateSafe $operatingSystem.LastBootUpTime
        Architecture = $operatingSystem.OSArchitecture
        SerialNumber = $operatingSystem.SerialNumber
    }
    BIOS = [pscustomobject]@{
        Manufacturer = $bios.Manufacturer
        SMBIOSBIOSVersion = $bios.SMBIOSBIOSVersion
        ReleaseDate = Format-DateSafe $bios.ReleaseDate
        SerialNumber = $bios.SerialNumber
        Version = ($bios.BIOSVersion -join ", ")
    }
    Motherboard = [pscustomobject]@{
        Manufacturer = $baseBoard.Manufacturer
        Product = $baseBoard.Product
        SerialNumber = $baseBoard.SerialNumber
        Version = $baseBoard.Version
    }
    CPU = $cpuData
    Memory = [pscustomobject]@{
        TotalBytes = $ramTotalBytes
        Total = Format-Bytes $ramTotalBytes
        Modules = $ramModules
    }
    GPU = $gpuData
    Storage = $storageData
    LogicalDrives = $logicalDriveData
    NetworkAdapters = $netData
    WSL = [pscustomobject]@{
        StatusExitCode = $wslStatus.ExitCode
        StatusOutput = $wslStatus.StdOut
        StatusError = $wslStatus.StdErr
        DistrosExitCode = $wslList.ExitCode
        DistrosOutput = $wslList.StdOut
        DistrosError = $wslList.StdErr
    }
    NVIDIA = [pscustomobject]@{
        ExitCode = $nvidiaSmi.ExitCode
        Output = $nvidiaSmi.StdOut
        Error = $nvidiaSmi.StdErr
    }
    WinSAT = [pscustomobject]@{
        ExitCode = $winsatDisk.ExitCode
        Output = $winsatDisk.StdOut
        Error = $winsatDisk.StdErr
    }
    Services = $services | Select-Object Name, DisplayName, Status, StartType
    Hotfixes = $hotfixes | Select-Object HotFixID, Description, InstalledOn
    RoleAssessment = [pscustomobject]@{
        AgentScore = $agentScore
        HasNVIDIA = $hasNvidia
        NVMePresent = $nvmePresent
        TotalRAMGB = $totalRamGB
        TotalCores = $totalCores
        TotalLogicalProcessors = $totalLogicalProcessors
        Recommendation = $roleRecommendation
    }
}

# ---------------------------------------------------------
# Build TXT report
# ---------------------------------------------------------

$sb = New-Object System.Text.StringBuilder

Add-TextBlock -Builder $sb -Text "FULL SYSTEM AUDIT REPORT"
Add-TextBlock -Builder $sb -Text "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Add-TextBlock -Builder $sb -Text "Computer Name: $computerName"

Add-TextBlock -Builder $sb -Text (New-Section -Title "SYSTEM")
Add-Lines -Builder $sb -Lines @(
    (Write-KeyValue "Manufacturer" $computerSystem.Manufacturer),
    (Write-KeyValue "Model" $computerSystem.Model),
    (Write-KeyValue "System Type" $computerSystem.SystemType),
    (Write-KeyValue "Domain" $computerSystem.Domain),
    (Write-KeyValue "Current User" $computerSystem.UserName),
    (Write-KeyValue "Total Physical Memory" (Format-Bytes $computerSystem.TotalPhysicalMemory))
)

Add-TextBlock -Builder $sb -Text (New-Section -Title "OPERATING SYSTEM")
Add-Lines -Builder $sb -Lines @(
    (Write-KeyValue "Caption" $operatingSystem.Caption),
    (Write-KeyValue "Version" $operatingSystem.Version),
    (Write-KeyValue "Build Number" $operatingSystem.BuildNumber),
    (Write-KeyValue "Architecture" $operatingSystem.OSArchitecture),
    (Write-KeyValue "Install Date" (Format-DateSafe $operatingSystem.InstallDate)),
    (Write-KeyValue "Last Boot" (Format-DateSafe $operatingSystem.LastBootUpTime))
)

Add-TextBlock -Builder $sb -Text (New-Section -Title "BIOS")
Add-Lines -Builder $sb -Lines @(
    (Write-KeyValue "Manufacturer" $bios.Manufacturer),
    (Write-KeyValue "Version" (($bios.BIOSVersion -join ", "))),
    (Write-KeyValue "SMBIOS Version" $bios.SMBIOSBIOSVersion),
    (Write-KeyValue "Release Date" (Format-DateSafe $bios.ReleaseDate)),
    (Write-KeyValue "Serial Number" $bios.SerialNumber)
)

Add-TextBlock -Builder $sb -Text (New-Section -Title "MOTHERBOARD")
Add-Lines -Builder $sb -Lines @(
    (Write-KeyValue "Manufacturer" $baseBoard.Manufacturer),
    (Write-KeyValue "Product" $baseBoard.Product),
    (Write-KeyValue "Version" $baseBoard.Version),
    (Write-KeyValue "Serial Number" $baseBoard.SerialNumber)
)

Add-TextBlock -Builder $sb -Text (New-Section -Title "CPU")
foreach ($cpu in $cpuData) {
    Add-Lines -Builder $sb -Lines @(
        (Write-KeyValue "Name" $cpu.Name),
        (Write-KeyValue "Manufacturer" $cpu.Manufacturer),
        (Write-KeyValue "Cores" "$($cpu.Cores)"),
        (Write-KeyValue "Logical Processors" "$($cpu.LogicalProcessors)"),
        (Write-KeyValue "Max Clock MHz" "$($cpu.MaxClockMHz)"),
        (Write-KeyValue "Socket" $cpu.Socket),
        (Write-KeyValue "L2 Cache KB" "$($cpu.L2CacheKB)"),
        (Write-KeyValue "L3 Cache KB" "$($cpu.L3CacheKB)")
    )
    Add-TextBlock -Builder $sb -Text ""
}

Add-TextBlock -Builder $sb -Text (New-Section -Title "MEMORY")
Add-Lines -Builder $sb -Lines @(
    (Write-KeyValue "Total Installed RAM" (Format-Bytes $ramTotalBytes))
)
foreach ($ram in $ramModules) {
    Add-Lines -Builder $sb -Lines @(
        (Write-KeyValue "Module Locator" $ram.DeviceLocator),
        (Write-KeyValue "Bank Label" $ram.BankLabel),
        (Write-KeyValue "Manufacturer" $ram.Manufacturer),
        (Write-KeyValue "Capacity" $ram.Capacity),
        (Write-KeyValue "Speed MT/s" "$($ram.SpeedMTs)"),
        (Write-KeyValue "Configured Clock" "$($ram.ConfiguredClockSpeed)"),
        (Write-KeyValue "Part Number" $ram.PartNumber),
        (Write-KeyValue "Serial Number" $ram.SerialNumber)
    )
    Add-TextBlock -Builder $sb -Text ""
}

Add-TextBlock -Builder $sb -Text (New-Section -Title "GPU")
foreach ($gpu in $gpuData) {
    Add-Lines -Builder $sb -Lines @(
        (Write-KeyValue "Name" $gpu.Name),
        (Write-KeyValue "Driver Version" $gpu.DriverVersion),
        (Write-KeyValue "Video Processor" $gpu.VideoProcessor),
        (Write-KeyValue "Adapter RAM" $gpu.AdapterRAM),
        (Write-KeyValue "Resolution" $gpu.Resolution),
        (Write-KeyValue "Status" $gpu.Status),
        (Write-KeyValue "PNP Device ID" $gpu.PNPDeviceID)
    )
    Add-TextBlock -Builder $sb -Text ""
}

Add-TextBlock -Builder $sb -Text (New-Section -Title "PHYSICAL STORAGE")
foreach ($disk in $storageData) {
    Add-Lines -Builder $sb -Lines @(
        (Write-KeyValue "Friendly Name" $disk.FriendlyName),
        (Write-KeyValue "Media Type" "$($disk.MediaType)"),
        (Write-KeyValue "Bus Type" "$($disk.BusType)"),
        (Write-KeyValue "Size" $disk.Size),
        (Write-KeyValue "Health Status" "$($disk.HealthStatus)"),
        (Write-KeyValue "Operational Status" "$($disk.OperationalStatus)"),
        (Write-KeyValue "Serial Number" "$($disk.SerialNumber)"),
        (Write-KeyValue "Firmware Version" "$($disk.FirmwareVersion)")
    )
    Add-TextBlock -Builder $sb -Text ""
}

Add-TextBlock -Builder $sb -Text (New-Section -Title "LOGICAL DRIVES")
foreach ($drive in $logicalDriveData) {
    Add-Lines -Builder $sb -Lines @(
        (Write-KeyValue "Drive" $drive.DeviceID),
        (Write-KeyValue "Volume Name" $drive.VolumeName),
        (Write-KeyValue "File System" $drive.FileSystem),
        (Write-KeyValue "Total Size" $drive.Size),
        (Write-KeyValue "Used" $drive.Used),
        (Write-KeyValue "Free" $drive.Free)
    )
    Add-TextBlock -Builder $sb -Text ""
}

Add-TextBlock -Builder $sb -Text (New-Section -Title "NETWORK ADAPTERS")
foreach ($net in $netData) {
    Add-Lines -Builder $sb -Lines @(
        (Write-KeyValue "Name" $net.Name),
        (Write-KeyValue "Description" $net.InterfaceDescription),
        (Write-KeyValue "Status" $net.Status),
        (Write-KeyValue "Link Speed" $net.LinkSpeed),
        (Write-KeyValue "MAC Address" $net.MacAddress),
        (Write-KeyValue "Interface Index" "$($net.InterfaceIndex)")
    )
    Add-TextBlock -Builder $sb -Text ""
}

Add-TextBlock -Builder $sb -Text (New-Section -Title "WSL STATUS")
Add-Lines -Builder $sb -Lines @(
    (Write-KeyValue "WSL Status Exit Code" "$($wslStatus.ExitCode)"),
    (Write-KeyValue "WSL Status Output" $wslStatus.StdOut),
    (Write-KeyValue "WSL Status Error" $wslStatus.StdErr),
    "",
    (Write-KeyValue "WSL Distro Exit Code" "$($wslList.ExitCode)"),
    (Write-KeyValue "WSL Distros Output" $wslList.StdOut),
    (Write-KeyValue "WSL Distros Error" $wslList.StdErr)
)

Add-TextBlock -Builder $sb -Text (New-Section -Title "NVIDIA STATUS")
Add-Lines -Builder $sb -Lines @(
    (Write-KeyValue "nvidia-smi Exit Code" "$($nvidiaSmi.ExitCode)"),
    (Write-KeyValue "Output" $nvidiaSmi.StdOut),
    (Write-KeyValue "Error" $nvidiaSmi.StdErr)
)

Add-TextBlock -Builder $sb -Text (New-Section -Title "DISK PERFORMANCE")
Add-Lines -Builder $sb -Lines @(
    (Write-KeyValue "WinSAT Exit Code" "$($winsatDisk.ExitCode)"),
    (Write-KeyValue "Output" $winsatDisk.StdOut),
    (Write-KeyValue "Error" $winsatDisk.StdErr)
)

Add-TextBlock -Builder $sb -Text (New-Section -Title "RECENT HOTFIXES")
foreach ($hf in ($hotfixes | Select-Object -First 15)) {
    Add-Lines -Builder $sb -Lines @(
        (Write-KeyValue "HotFix ID" $hf.HotFixID),
        (Write-KeyValue "Description" $hf.Description),
        (Write-KeyValue "Installed On" (Format-DateSafe $hf.InstalledOn))
    )
    Add-TextBlock -Builder $sb -Text ""
}

Add-TextBlock -Builder $sb -Text (New-Section -Title "ROLE ASSESSMENT")
Add-Lines -Builder $sb -Lines @(
    (Write-KeyValue "Has NVIDIA GPU" "$hasNvidia"),
    (Write-KeyValue "Has NVMe Storage" "$nvmePresent"),
    (Write-KeyValue "Total RAM GB" "$totalRamGB"),
    (Write-KeyValue "Total CPU Cores" "$totalCores"),
    (Write-KeyValue "Total Logical Processors" "$totalLogicalProcessors"),
    (Write-KeyValue "Agent Score" "$agentScore"),
    (Write-KeyValue "Recommendation" $roleRecommendation)
)

Add-TextBlock -Builder $sb -Text (New-Section -Title "FINAL NOTE")
Add-Lines -Builder $sb -Lines @(
    "Use this report on both Windows PCs.",
    "Compare GPU, RAM, CPU cores, storage bus type, and WSL or NVIDIA readiness.",
    "The stronger machine should become the isolated Agent PC.",
    "The weaker but still stable machine should become the Dev / Personal Control PC."
)

# ---------------------------------------------------------
# Write files
# ---------------------------------------------------------

$sb.ToString() | Out-File -FilePath $txtPath -Encoding UTF8
$auditObject | ConvertTo-Json -Depth 6 | Out-File -FilePath $jsonPath -Encoding UTF8

Write-Host ""
Write-Host "Audit complete."
Write-Host "TXT Report : $txtPath"
Write-Host "JSON Report: $jsonPath"
Write-Host ""
