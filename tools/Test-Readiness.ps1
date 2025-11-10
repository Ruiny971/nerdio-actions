[CmdletBinding(SupportsShouldProcess = $false)]
param (
    [Parameter(Position = 0, Mandatory = $false)]
    [string[]] $Publishers = @("Citrix*", "uberAgent*", "UniDesk*", "Omnissa*"),

    [Parameter(Mandatory = $false)]
    [switch] $IgnoreClientApp
)

begin {
    # Configure environment and log file
    $ErrorActionPreference = 'Stop'
    $InformationPreference = 'Continue'
    $ProgressPreference = 'SilentlyContinue'
    $LogPath = "C:\Packages\Logs\Test-Readiness.log"
    $LogMessages = @()
    $Failures = @()

    # Ensure log folder exists
    $logDir = Split-Path -Path $LogPath -Parent
    if (!(Test-Path -Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    # List Citrix Workspace App and Omnissa Horizon Client services for exclusion
    $ClientAppServices = @(
        "CtxAdpPolicy", "CtxPkm", "CWAUpdaterService", "client_service",
        "ftnlsv3hv", "ftscanmgrhv", "hznsprrdpwks", "omnKsmNotifier", "ws1etlm"
    )

    # Supported Windows SKUs: Enterprise, multi-session, Server 2016–2025
    $SupportedSkus = 4,8,13,48,79,80,121,145,146,155,180,181
}

process {
    # 1) Architecture check
    if ($Env:PROCESSOR_ARCHITECTURE -ne "AMD64") {
        $Failures += "Windows OS is not 64-bit."
    }

    # 2) OS SKU check (language-agnostic)
    try {
        $OS = Get-CimInstance -ClassName Win32_OperatingSystem
        $Sku = [int]$OS.OperatingSystemSKU
        $Caption = $OS.Caption
    } catch {
        $Failures += "Unable to query OS SKU information."
        $Sku = $null
        $Caption = "Unknown"
    }

    if ($Sku -ne $null -and ($SupportedSkus -contains $Sku)) {
        $msg = "Windows OS SKU is supported: $Sku ($Caption)"
        Write-Information -MessageData $msg
        $LogMessages += $msg
    } else {
        $msg = "Windows OS SKU is not supported: $Sku ($Caption)"
        $Failures += $msg
        $LogMessages += $msg
    }

    # 3) Third-party agent service detection with wildcard matching on Name and DisplayName
    $AllServices = Get-Service -ErrorAction SilentlyContinue
    $MatchedServices = @()

    foreach ($Pattern in $Publishers) {
        $MatchedServices += $AllServices | Where-Object {
            $_.DisplayName -like $Pattern -or $_.Name -like $Pattern
        }
    }

    # De-duplicate by Service Name
    if ($MatchedServices) {
        $MatchedServices = $MatchedServices | Sort-Object Name -Unique
    }

    if ($IgnoreClientApp -and $MatchedServices) {
        $MatchedServices = $MatchedServices | Where-Object { $ClientAppServices -notcontains $_.Name }
    }

    if ($MatchedServices -and $MatchedServices.Count -gt 0) {
        $displayNames = $MatchedServices | ForEach-Object { $_.DisplayName }
        $msg = "Conflicting 3rd-party agents found: $($displayNames -join ', ')."
        $Failures += $msg
        $LogMessages += $msg
    } else {
        $msg = "No conflicting 3rd-party agents found."
        Write-Information -MessageData $msg
        $LogMessages += $msg
    }

    # 4) Summary output and log writing
    if ($Failures.Count -gt 0) {
        foreach ($fail in $Failures) {
            Write-Error -Message $fail
        }
        $msg = "Readiness check failed with $($Failures.Count) issue(s)."
        $LogMessages += $msg
        Set-Content -Path $LogPath -Value ($LogMessages -join "`r`n")
        exit 1
    } else {
        $msg = "All checks passed successfully."
        Write-Information -MessageData $msg
        $LogMessages += $msg
        Set-Content -Path $LogPath -Value ($LogMessages -join "`r`n")
        exit 0
    }
}
