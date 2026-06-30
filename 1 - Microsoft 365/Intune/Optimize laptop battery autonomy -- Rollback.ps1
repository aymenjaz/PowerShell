<#
.SYNOPSIS
    Rolls back battery optimization settings to Windows defaults (DC side).
.DESCRIPTION
    Runs in SYSTEM context from Intune. Reverts Energy Saver, CPU throttle,
    and passive cooling settings on battery to their default values.
    Mirrors the optimization script: only DC (on-battery) values are touched.
.NOTES
    Deploy via Intune > Devices > Scripts and remediations > Platform scripts.
    Run as system: Yes | Run in 64-bit PowerShell: Yes
#>

$ErrorActionPreference = "Stop"

try {
    # --- Restore default DC values on the active scheme ---

    # 1. Energy Saver threshold back to Windows default (20%).
    #    Energy Saver re-engages only when the battery drops to 20%.
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_ENERGYSAVER ESBATTTHRESHOLD 20

    # 2. Maximum processor state back to 100% on battery (re-enables Turbo Boost).
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100

    # 3. Minimum processor state back to default (5% is the Windows default,
    #    set explicitly to guarantee a known state).
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5

    # 4. Cooling policy back to Active (0) on battery: fan spins before throttling.
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR SYSCOOLPOL 0

    # --- Commit the changes to the active scheme ---
    powercfg /setactive SCHEME_CURRENT

    # Re-enable background UWP apps (remove the override; default = enabled).
    $bgPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
    if (Get-ItemProperty -Path $bgPath -Name "GlobalUserDisabled" -ErrorAction SilentlyContinue) {
        Remove-ItemProperty -Path $bgPath -Name "GlobalUserDisabled" -ErrorAction SilentlyContinue
    }

    Write-Output "Battery optimization rolled back: defaults restored (DC only)."
    exit 0
}
catch {
    Write-Output "Failed to roll back battery optimization: $($_.Exception.Message)"
    exit 1
}
