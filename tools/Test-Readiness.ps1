[CmdletBinding(SupportsShouldProcess = $false)]
param (
    [Parameter(Position = 0, Mandatory = $false)]
    [System.String[]] $Publishers = @("Citrix*", "uberAgent*", "UniDesk*", "Omnissa*"),

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter] $IgnoreClientApp,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter] $IgnoreOmnissaHorizonClient
)

$logFile = "C:\Packages\Logs\Test-Readiness.log"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    # Only simple ASCII [OK] etc to avoid Unicode
    $cleanMessage = $Message -replace '[\x{2713}\x{2714}]','[OK]'
    $text = "$timestamp $cleanMessage"
    Add-Content -Path $logFile -Value $text
    Write-Output $text
}

Set-Content -Path $logFile -Value "==== Test-Readiness Script Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===="

$Failures = @()

# --- OS architecture check ---
if ($env:PROCESSOR_ARCHITECTURE -ne "AMD64") {
    $fail = "[FAIL] Windows OS is not 64-bit."
    $Failures += $fail
    Write-Log $fail
} else {
    Write-Log "[OK] Windows OS is 64-bit architecture."
}

# --- OS Edition detection: AVD supported only ---
try {
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    $sku = $osInfo.OperatingSystemSKU
} catch {
    $fail = "[FAIL] Failed to retrieve OS SKU: $_"
    $Failures += $fail
    Write-Log $fail
    $sku = -1
}

try {
    $editionId = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "EditionID").EditionID
} catch {
    $fail = "[FAIL] Failed to read EditionID from registry: $_"
    $Failures += $fail
    Write-Log $fail
    $editionId = ""
}

Write-Log "Detected EditionID: $editionId"
Write-Log "Detected OS SKU: $sku"

# Strict AVD-supported EditionIDs only
$supportedEditionIDs = @(
    "Enterprise",
    "EnterpriseMultiSession",
    "ServerDatacenter",
    "ServerStandard",
    "ServerAzureEdition"
)

# Only pass if EditionID is in the AVD supported list
if ($editionId -and ($supportedEditionIDs -contains $editionId)) {
    Write-Log "[OK] Windows OS edition is supported: EditionID='$editionId', SKU=$sku"
} else {
    $fail = "[FAIL] Windows OS edition is NOT supported: EditionID='$editionId', SKU=$sku"
    $Failures += $fail
    Write-Log $fail
}

# --- Conflicting services check ---
Write-Log "Checking for conflicting 3rd-party agents for patterns: $($Publishers -join ', ') ..."

try {
    $allServices = Get-Service
} catch {
    $fail = "[FAIL] Failed to retrieve services: $_"
    $Failures += $fail
    Write-Log $fail
    $allServices = @()
}

$conflictingServices = New-Object System.Collections.Generic.List[string]

foreach ($svc in $allServices) {
    foreach ($pattern in $Publishers) {
        if ($svc.Name -like $pattern -or $svc.DisplayName -like $pattern) {
            $conflictingServices.Add($svc.DisplayName)
            break
        }
    }
}

# Optionally exclude certain Horizon/Workspace App services
$clientAppServices = @("CtxAdpPolicy", "CtxPkm", "CWAUpdaterService", "client_service", "ftnlsv3hv", "ftscanmgrhv", "hznsprrdpwks", "omnKsmNotifier", "ws1etlm")

if ($IgnoreClientApp) {
    $conflictingServices = $conflictingServices | Where-Object { $clientAppServices -notcontains $_ }
}
if ($IgnoreOmnissaHorizonClient) {
    $conflictingServices = $conflictingServices | Where-Object { $_ -notmatch '^omnissa' }
}

if ($conflictingServices.Count -gt 0) {
    $fail = "[FAIL] Conflicting 3rd-party agents found: $($conflictingServices | Sort-Object | Get-Unique -AsString -join ', ')."
    $Failures += $fail
    Write-Log $fail
} else {
    Write-Log "[OK] No conflicting 3rd-party agents found."
}

# --- Output final summary to both log and stdout (for Azure portal) ---
if ($Failures.Count -eq 0) {
    $finalMsg = "All readiness checks passed successfully."
    Write-Log $finalMsg
    Write-Output $finalMsg # Ensures Azure VM extension details has a clear final line
    exit 0
} else {
    $failuresMsg = "Readiness check failed with $($Failures.Count) issue(s): $($Failures -join '; ')"
    Write-Log $failuresMsg
    Write-Output $failuresMsg # Ensures Azure VM extension details has a clear final line
    exit 1
}

Write-Log "==== Test-Readiness Script Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===="
