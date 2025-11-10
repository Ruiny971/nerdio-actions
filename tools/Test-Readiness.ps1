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
    $timestampedMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
    Add-Content -Path $logFile -Value $timestampedMessage
    Write-Output $timestampedMessage
}

Set-Content -Path $logFile -Value "==== Test-Readiness Script Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===="

$Failures = @()

# Check OS Architecture
if ($env:PROCESSOR_ARCHITECTURE -ne "AMD64") {
    $fail = "❌ Windows OS is not 64-bit."
    $Failures += $fail
    Write-Log $fail
} else {
    Write-Log "✅ Windows OS is 64-bit architecture."
}

# Get OS SKU and EditionID from registry
try {
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    $sku = $osInfo.OperatingSystemSKU
} catch {
    $fail = "❌ Failed to retrieve OS SKU: $_"
    $Failures += $fail
    Write-Log $fail
    $sku = -1
}

try {
    $editionId = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "EditionID").EditionID
} catch {
    $fail = "❌ Failed to read EditionID from registry: $_"
    $Failures += $fail
    Write-Log $fail
    $editionId = ""
}

Write-Log "Detected EditionID: $editionId"
Write-Log "Detected OS SKU: $sku"

# Define supported EditionIDs (language agnostic)
$supportedEditionIDs = @(
    "Enterprise",
    "EnterpriseMultiSession",
    "ServerDatacenter",
    "ServerStandard",
    "ServerSemiAnnual",
    "ServerAzureEdition",
    "EnterpriseG"
)

# Define supported SKUs as a fallback
$supportedSKUs = @(4,7,8,10,48,50,98,101,118,121,125,155,156,175,178,188,191,192,328)

# Determine support based on EditionID or SKU
$supported = $false

if ($editionId -and ($supportedEditionIDs -contains $editionId)) {
    $supported = $true
} elseif ($sku -in $supportedSKUs) {
    $supported = $true
}

if ($supported) {
    Write-Log "✅ Windows OS edition/SKU is supported: EditionID='$editionId', SKU=$sku"
} else {
    $fail = "❌ Windows OS edition/SKU is NOT supported: EditionID='$editionId', SKU=$sku"
    $Failures += $fail
    Write-Log $fail
}

# Check for conflicting services
Write-Log "Checking for conflicting 3rd-party agents for patterns: $($Publishers -join ', ') ..."

try {
    $allServices = Get-Service
} catch {
    $fail = "❌ Failed to retrieve services: $_"
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

# Optionally exclude client app services if flags set
$clientAppServices = @("CtxAdpPolicy", "CtxPkm", "CWAUpdaterService", "client_service", "ftnlsv3hv", "ftscanmgrhv", "hznsprrdpwks", "omnKsmNotifier", "ws1etlm")

if ($IgnoreClientApp) {
    $conflictingServices = $conflictingServices | Where-Object { $clientAppServices -notcontains $_ }
}
if ($IgnoreOmnissaHorizonClient) {
    $conflictingServices = $conflictingServices | Where-Object { $_ -notmatch '^omnissa' }
}

if ($conflictingServices.Count -gt 0) {
    $fail = "❌ Conflicting 3rd-party agents found: $($conflictingServices | Sort-Object | Get-Unique -AsString -join ', ')."
    $Failures += $fail
    Write-Log $fail
} else {
    Write-Log "✅ No conflicting 3rd-party agents found."
}

# Output final summary
if ($Failures.Count -eq 0) {
    Write-Log "All checks passed successfully."
} else {
    Write-Log "Readiness check failed with $($Failures.Count) issue(s)."
    foreach ($f in $Failures) {
        Write-Log $f
    }
}

Write-Log "==== Test-Readiness Script Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===="
