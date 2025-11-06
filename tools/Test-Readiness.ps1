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
    # Configure the environment
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $InformationPreference = [System.Management.Automation.ActionPreference]::Continue
    $ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

    # Services that are part of the Citrix Workspace App or the Omnissa Horizon Client
    $ClientAppServices = @("CtxAdpPolicy", "CtxPkm", "CWAUpdaterService", "client_service",
        "ftnlsv3hv", "ftscanmgrhv", "hznsprrdpwks", "omnKsmNotifier", "ws1etlm")

    # Get OS SKU
    $Sku = (Get-CimInstance -ClassName Win32_OperatingSystem).OperatingSystemSKU
    
    # Supported SKUs (IDs for allowed OS editions)
    $SupportedSkus = @(4, 8, 13, 48, 79, 80, 121, 145, 146, 155, 180, 181)
    
    # Check if OS is supported
    if ($SupportedSkus -contains $Sku) {
        Write-Information -MessageData "Windows OS SKU is supported: $Sku."
    } else {
        Write-Error -Message "Windows OS SKU is not supported: $Sku."
        exit 1
    }
}

    # Start log
    $LogPath = "C:\Packages\Logs\Test-Readiness.log"
    if (!(Test-Path -Path (Split-Path $LogPath))) {
        New-Item -ItemType Directory -Path (Split-Path $LogPath) -Force | Out-Null
    }
    Add-Content -Path $LogPath -Value "=== Test-Readiness run started at $(Get-Date -Format 'u') ==="

process {
    # Check if OS is 64-bit
    if ($Env:PROCESSOR_ARCHITECTURE -ne "AMD64") {
        Write-Error -Message "Windows OS is not 64-bit."
        exit 1
    }

    # Get OS SKU
    $Sku = (Get-CimInstance -ClassName Win32_OperatingSystem).OperatingSystemSKU
    
    # Supported SKUs (IDs for allowed OS editions)
    $SupportedSkus = @(4, 8, 13, 48, 79, 80, 121, 145, 146, 155, 180, 181)
    
    # Check if OS is supported
    if ($SupportedSkus -contains $Sku) {
        Write-Information -MessageData "Windows OS SKU is supported: $Sku."
    } else {
        Write-Error -Message "Windows OS SKU is not supported: $Sku."
        exit 1
    }

    # Check if any of the specified 3rd party agents are installed by looking for their services
    $Services = Get-Service -DisplayName $Publishers

    # Filter out Citrix Workspace App services or the Omnissa Horizon Client if requested
    if ($IgnoreClientApp) {
        $Services = $Services | Where-Object { $_.Name -notin $ClientAppServices }
    }

    # If no services are found, return 0; otherwise, return 1
    if ($Services.Count -ge 1) {
        Write-Error -Message "Conflicting 3rd party agents found: $($Services.DisplayName -join ', ')."
        exit 1
    }
    else {
        Write-Information -MessageData "No conflicting 3rd party agents found."
        exit 0
    }
}
