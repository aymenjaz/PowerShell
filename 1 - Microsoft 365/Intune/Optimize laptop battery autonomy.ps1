<#
.SYNOPSIS
    Optimizes laptop battery autonomy by tuning the active power plan (DC side only).
.DESCRIPTION
    Runs in SYSTEM context from Intune. Applies Energy Saver, CPU throttle, and
    passive cooling settings on battery. AC (plugged-in) performance is untouched.
.NOTES
    You can deploy the script via Intune > Devices > Scripts and remediations > Platform scripts.
    Run as system: Yes | Run in 64-bit PowerShell: Yes
#>

$ErrorActionPreference = "Stop"

try {
    # --- Use the active power scheme as the target ---
    # SCHEME_CURRENT always points to whatever plan is active on the device.

    # 1. Energy Saver always ON when on battery.
    #    Threshold 100% = Energy Saver is engaged across the entire battery range,
    #    instead of waiting for the default 20% trigger.
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_ENERGYSAVER ESBATTTHRESHOLD 100

    # 2. Cap maximum processor state at 99% on battery.
    #    This disables Turbo Boost on DC, usually the biggest single battery win.
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 99

    # 3. Allow the processor to idle deeper on battery (minimum state 5%).
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5

    # 4. Passive cooling policy on battery: throttle the CPU before spinning the fan.
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR SYSCOOLPOL 1

    # --- Commit the changes to the active scheme ---
    powercfg /setactive SCHEME_CURRENT

    Write-Output "Battery optimization applied: Energy Saver ON, Turbo OFF, passive cooling (DC only)."
    exit 0
}
catch 
{
    Write-Output "Failed to apply battery optimization: $($_.Exception.Message)"
    exit 1
}
