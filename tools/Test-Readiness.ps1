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
    # Configure environment
    $ErrorActionPreference = "Stop"
    $InformationPreference = "Continue"
    $ProgressPreference = "SilentlyContinue"

    # Services from Citrix / Horizon client components
    $ClientAppServices = @(
        "CtxAdpPolicy", "CtxPkm", "CWAUpdaterService", "client_service",
        "ftnlsv3hv", "ftscanmgrhv", "hznsprrdpwks", "omnKsmNotifier", "ws1etlm"
    )

    # Supported SKUs (modern mapping for Windows 10/11 & Server)
    $SupportedSkus = @(4, 8, 13, 48, 79, 80, 83, 121, 125, 145, 146, 147, 155, 156, 157, 180, 181, 188)

    # Edition name fallback (in case SKU mapping changes in future builds)
    $SupportedEditions = @(
        "Enterprise", "Enterprise N", "Enterprise multi-session",
        "Windows Server 2016", "Windows Server 2019", "Windows Server 2022", "Windows Server 2025"
    )
}

process {
    # Check if OS is 64-bit
    if ($Env:PROCESSOR_ARCHITECTURE -ne "AMD64") {
        Write-Error "Windows OS is not 64-bit."
        exit 1
    }

    # Gather OS info
    $OS = Get-CimInstance Win32_OperatingSystem
    $Sku = [int]$OS.OperatingSystemSKU
    $Edition = $OS.Caption

    Write-Information "Detected OS: $Edition (SKU $Sku)"

    # Determine if supported (by SKU or Caption)
    $IsSupported = $false
    if ($SupportedSkus -contains $Sku) { $IsSupported = $true }
    elseif ($SupportedEditions | ForEach-Object { $Edition -match $_ }) { $IsSupported = $true }

    if (-not $IsSupported) {
        Write-Error "Windows OS is not supported: $Edition (SKU $Sku)"
        exit 1
    } else {
        Write-Information "Windows OS is supported: $Edition (SKU $Sku)"
    }

    # Detect conflicting 3rd-party agents
    try {
        $Services = Get-Service -ErrorAction SilentlyContinue | Where-Object {
            $Publishers | ForEach-Object { $_Pattern = $_; $_.DisplayName -like $_Pattern }
        }
    } catch {
        $Services = @()
    }

    # Filter out client app services if requested
    if ($IgnoreClientApp) {
        $Services = $Services | Where-Object { $_.Name -notin $ClientAppServices }
    }

    # Check for conflicts
    if ($Services.Count -ge 1) {
        Write-Error "Conflicting 3rd-party agents found: $($Services.DisplayName -join ', ')."
        exit 1
    } else {
        Write-Information "No conflicting 3rd-party agents found."
        exit 0
    }
}
