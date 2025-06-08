
# ============================================================================================
# Script Name  : Get-PublicIP-Info.ps1
# Description  : Retrieves your current public IP address and detailed geolocation data 
#                using the ipinfo.io API.
# Requirements : Internet access
# ============================================================================================


# -------------------------------------------
# STEP 1: Get Your Current Public IP Address
# -------------------------------------------
# This command queries ipinfo.io without parameters to return your machine's public IP and related metadata.
Invoke-RestMethod -Uri https://ipinfo.io

# Output includes fields like:
# ip        => Public IP address
# city      => Geolocation city
# region    => State or region
# country   => Country code
# loc       => GPS coordinates (latitude,longitude)
# org       => ISP or Organization
# timezone  => Local timezone
# ...

# -------------------------------------------
# STEP 2: Query a Specific External IP for Detailed Information
# -------------------------------------------

# Replace with any IP address you want to investigate
$ExternalIP = "216.250.240.99"

# Query ipinfo.io for details about the specified external IP address
# Only select relevant fields and re-label them for readability
Invoke-RestMethod -Uri "https://ipinfo.io/$ExternalIP" | Select-Object `
    ip, 
    hostname, 
    city, 
    region, 
    country, 
    @{Label = "GPS"; Expression = { $_.loc }}, 
    @{Label = "Company"; Expression = { $_.org }}, 
    @{Label = "Postal Code"; Expression = { $_.postal }}, 
    timezone
