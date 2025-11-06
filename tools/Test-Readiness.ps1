<#
.SYNOPSIS
    Validates a Citrix-based or imported VM to ensure it's ready to be converted
    into an Azure Virtual Desktop (AVD) image.

.DESCRIPTION
    This script performs three main readiness checks:
      1. Confirms that the OS architecture is 64-bit.
      2. Verifies that the OS edition or SKU is supported for AVD.
      3. Detects conflicting 3rd-party agent services (Citrix, Omnissa, etc.).

    It writes all findings to:
        C:\Packages\Logs\Test-Readiness.log

    Designed for execution via Nerdio Scripted Actions (CustomScriptExtension),
    but can also be run locally during manual image validation.

.PARAMETER Publishers
    List of software publisher patterns to look for when scanning for agent services.

.PARAMETER IgnoreClientApp
    Excludes Citrix Workspace App or Omnissa Horizon Client services from the check.

.NOTES
    Exit Codes:
        0 = All checks passed; image ready for migration.
        1 = One or more checks failed.
#>

[CmdletBinding(SupportsShouldProcess = $false)]
param (
    [Parameter(Position = 0, Mandatory = $false)]
    [System.String[]] $Publishers = @("Citrix*", "uberAgent*", "UniDesk*", "Omnissa*"),

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter] $IgnoreClientApp,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter] $IgnoreOmnissaHorizonClient
)

begin {
    # --- Runtime environment setup ---
    $ErrorActionPreference  = "Stop"
    $InformationPreference  = "Continue"
    $ProgressPreference     = "SilentlyContinue"
    $HasErrors              = $false

    # --- Retrieve Nerdio runtime variables (if available) ---
    try {
        if (-not $VMName) {
            try {
                $VMParams = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Virtual Machine\Guest\Parameters" -ErrorAction SilentlyContinue
                $VMName = $VMParams.Hostname
            } catch {
                $VMName = $env:COMPUTERNAME
            }
        }

        if (-not $ResourceGroupName -and (Get-Command Get-AzVM -ErrorAction SilentlyContinue)) {
            $VMObject = Get-AzVM -Status -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $VMName }
            $ResourceGroupName = if ($VMObject) { $VMObject.ResourceGroupName } else { "Unknown" }
        } else {
            $ResourceGroupName = "Unknown"
        }
    } catch {
        $VMName = $env:COMPUTERNAME
        $ResourceGroupName = "Unknown"
    }

    # --- Logging configuration ---
    $LogPath = "C:\Packages\Logs\Test-Readiness.log"
    if (!(Test-Path -Path (Split-Path $LogPath))) {
        New-Item -ItemType Directory -Path (Split-Path $LogPath) -Force | Out-Null
    }
    Add-Content -Path $LogPath -Value "=== Test-Readiness run started at $(Get-Date -Format 'u') ==="
    Add-Content -Path $LogPath -Value "VM: $VMName | Resource Group: $ResourceGroupName"

    # --- Known services part of client-only agents ---
    $ClientAppServices = @(
        "CtxAdpPolicy", "CtxPkm", "CWAUpdaterService", "client_service",
        "ftnlsv3hv", "ftscanmgrhv", "hznsprrdpwks", "omnKsmNotifier", "ws1etlm"
    )

    # --- Supported SKUs ---
    $SupportedSkus = @(4, 8, 13, 79, 80, 121, 145, 146, 155, 180, 181)

    # --- Supported Edition keywords (for localized builds) ---
    $SupportedEditions = @(
        "Enterprise", "Enterprise N", "Enterprise multi-session",
        "Windows Server 2016", "Windows Server 2019", "Windows Server 2022", "Windows Server 2025"
    )
}

process {
    # --- 1️⃣ OS Architecture Validation ---
    if ($Env:PROCESSOR_ARCHITECTURE -ne "AMD64") {
        $Message = "Windows OS is not 64-bit."
        Write-Error $Message
        Add-Content -Path $LogPath -Value ("{0} - {1}" -f (Get-Date -Format 'u'), $Message)
        $HasErrors = $true
    }

    # --- 2️⃣ OS SKU and Edition Check ---
    $OS      = Get-CimInstance Win32_OperatingSystem
    $Sku     = [int]$OS.OperatingSystemSKU
    $Edition = $OS.Caption

    Write-Information "Detected OS: $Edition (SKU $Sku)"
    Add-Content -Path $LogPath -Value ("{0} - Detected OS: {1} (SKU {2})" -f (Get-Date -Format 'u'), $Edition, $Sku)

    $IsSupported = $false
    if ($SupportedSkus -contains $Sku) { $IsSupported = $true }
    elseif ($SupportedEditions | ForEach-Object { $Edition -match $_ }) { $IsSupported = $true }

    if (-not $IsSupported) {
        $Message = "OS validation failed. Unsupported edition: $Edition (SKU $Sku)"
        Write-Error $Message
        Add-Content -Path $LogPath -Value ("{0} - {1}" -f (Get-Date -Format 'u'), $Message)
        $HasErrors = $true
    } else {
        $Message = "Windows OS is supported: $Edition (SKU $Sku)"
        Write-Information $Message
        Add-Content -Path $LogPath -Value ("{0} - {1}" -f (Get-Date -Format 'u'), $Message)
    }

    # --- 3️⃣ Check for conflicting 3rd-party services ---
    try {
        $AllServices = Get-Service -ErrorAction SilentlyContinue
        $Services = foreach ($Pattern in $Publishers) {
            $AllServices | Where-Object { $_.DisplayName -like $Pattern }
        }
    } catch {
        $Services = @()
    }

    if ($IgnoreClientApp) {
        $Services = $Services | Where-Object { $_.Name -notin $ClientAppServices }
    }

    if ($Services.Count -ge 1) {
        $Message = "Conflicting 3rd-party agents found: $($Services.DisplayName -join ', ')."
        Write-Error $Message
        Add-Content -Path $LogPath -Value ("{0} - {1}" -f (Get-Date -Format 'u'), $Message)
        $HasErrors = $true
    } else {
        $Message = "No conflicting 3rd-party agents found."
        Write-Information $Message
        Add-Content -Path $LogPath -Value ("{0} - {1}" -f (Get-Date -Format 'u'), $Message)
    }

    # --- 4️⃣ Final Decision and Exit Code ---
    if ($HasErrors) {
        $Summary = "Readiness check failed - see previous messages or log file for details."
        Write-Error $Summary
        Add-Content -Path $LogPath -Value ("{0} - {1}" -f (Get-Date -Format 'u'), $Summary)
        exit 1
    }
    else {
        $Summary = "Readiness check completed successfully - system is ready for conversion."
        Write-Information $Summary
        Add-Content -Path $LogPath -Value ("{0} - {1}" -f (Get-Date -Format 'u'), $Summary)
        exit 0
    }
}
