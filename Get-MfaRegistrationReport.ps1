<#
.SYNOPSIS
    Reports every user's MFA registration status in a Microsoft Entra ID tenant.

.DESCRIPTION
    Reads the Microsoft Graph authentication methods registration report
    (Get-MgReportAuthenticationMethodUserRegistrationDetail) and produces:

      * a CSV with one row per user: MFA and SSPR registration, the methods they
        have registered, their preferred second factor and whether they hold an
        admin role
      * a short console summary, listing any admins who are NOT registered for MFA

    The script is read-only. It asks for a single delegated permission,
    AuditLog.Read.All, and disconnects from Microsoft Graph when it finishes.

    Requirements
      * PowerShell 7+ (Windows PowerShell 5.1 also works)
      * The Microsoft.Graph.Reports module
      * A signed-in account with Reports Reader, Security Reader,
        Security Administrator or Global Reader
      * A Microsoft Entra ID P1 or P2 licence in the tenant (needed for the
        authentication methods reports)

.PARAMETER OutputPath
    Where to save the CSV. Defaults to MfaRegistrationReport_<date>.csv in the
    current folder. The folder is created if it doesn't exist.

.PARAMETER ExcludeGuests
    Leave guest (B2B) accounts out of the report and the summary.

.PARAMETER TenantId
    Tenant to sign in to, if your account can access more than one.

.PARAMETER InputPath
    Build the report from a JSON file instead of calling Microsoft Graph. The file
    must hold registration details in the same shape Graph returns (an array, or an
    object with a "value" array). Useful for testing and demos - see the sample folder.

.PARAMETER PassThru
    Also write the report rows to the pipeline, so you can filter or sort them further.

.EXAMPLE
    .\Get-MfaRegistrationReport.ps1

    Signs in, pulls the registration report for every user and saves a dated CSV.

.EXAMPLE
    .\Get-MfaRegistrationReport.ps1 -ExcludeGuests -OutputPath .\reports\mfa.csv

    Members only, saved to a specific path.

.EXAMPLE
    .\Get-MfaRegistrationReport.ps1 -InputPath .\sample\sample-registration-details.json

    Runs offline against the fictional sample data, with no tenant needed.

.NOTES
    Author: Ryan Njualem
    Graph API: GET /reports/authenticationMethods/userRegistrationDetails
#>
[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path -Path (Get-Location) -ChildPath ('MfaRegistrationReport_{0:yyyy-MM-dd}.csv' -f (Get-Date))),
    [switch]$ExcludeGuests,
    [string]$TenantId,
    [string]$InputPath,
    [switch]$PassThru
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Get-PropertyValue {
    # Reads a property by name whether it came from the Graph SDK (PascalCase)
    # or from JSON (camelCase), and returns $null if it isn't there.
    param([Parameter(Mandatory)] $Object, [Parameter(Mandatory)] [string]$Name)
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Get-RegistrationDetail {
    param([string]$InputPath, [string]$TenantId)

    if ($InputPath) {
        Write-Verbose "Reading registration details from $InputPath"
        $data = Get-Content -Path $InputPath -Raw | ConvertFrom-Json
        if ($data -isnot [array] -and $data.PSObject.Properties['value']) { $data = $data.value }
        return @($data)
    }

    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Reports)) {
        throw "The Microsoft.Graph.Reports module isn't installed. Install it with: Install-Module Microsoft.Graph.Reports -Scope CurrentUser"
    }
    Import-Module Microsoft.Graph.Authentication, Microsoft.Graph.Reports

    $connectParams = @{ Scopes = 'AuditLog.Read.All'; NoWelcome = $true }
    if ($TenantId) { $connectParams['TenantId'] = $TenantId }
    Connect-MgGraph @connectParams

    try {
        Write-Verbose 'Requesting the authentication methods registration report'
        return @(Get-MgReportAuthenticationMethodUserRegistrationDetail -All)
    }
    catch {
        throw ("Couldn't read the registration report: {0}`nCheck that your account has Reports Reader, Security Reader or Global Reader, and that the tenant has a Microsoft Entra ID P1 or P2 licence." -f $_.Exception.Message)
    }
    finally {
        Disconnect-MgGraph | Out-Null
    }
}

function ConvertTo-ReportRow {
    param([Parameter(Mandatory)] $Detail)

    $lastUpdated = Get-PropertyValue $Detail 'lastUpdatedDateTime'
    if ($lastUpdated -is [datetime]) { $lastUpdated = $lastUpdated.ToString('yyyy-MM-dd HH:mm') }

    [pscustomobject]@{
        DisplayName              = Get-PropertyValue $Detail 'userDisplayName'
        UserPrincipalName        = Get-PropertyValue $Detail 'userPrincipalName'
        UserType                 = Get-PropertyValue $Detail 'userType'
        IsAdmin                  = [bool](Get-PropertyValue $Detail 'isAdmin')
        MfaRegistered            = [bool](Get-PropertyValue $Detail 'isMfaRegistered')
        MfaCapable               = [bool](Get-PropertyValue $Detail 'isMfaCapable')
        PasswordlessCapable      = [bool](Get-PropertyValue $Detail 'isPasswordlessCapable')
        SsprRegistered           = [bool](Get-PropertyValue $Detail 'isSsprRegistered')
        MethodsRegistered        = (@(Get-PropertyValue $Detail 'methodsRegistered') | Where-Object { $_ }) -join '; '
        PreferredSecondFactor    = Get-PropertyValue $Detail 'userPreferredMethodForSecondaryAuthentication'
        LastUpdated              = $lastUpdated
    }
}

function Get-ReportSummary {
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Rows)

    $total = $Rows.Count
    $registered = @($Rows | Where-Object { $_.MfaRegistered }).Count
    [pscustomobject]@{
        TotalUsers           = $total
        MfaRegistered        = $registered
        MfaNotRegistered     = $total - $registered
        MfaCoveragePercent   = if ($total) { [math]::Round(($registered / $total) * 100, 1) } else { 0 }
        SsprRegistered       = @($Rows | Where-Object { $_.SsprRegistered }).Count
        AdminsWithoutMfa     = @($Rows | Where-Object { $_.IsAdmin -and -not $_.MfaRegistered })
    }
}

# --- Main ---------------------------------------------------------------------

$details = Get-RegistrationDetail -InputPath $InputPath -TenantId $TenantId
$rows = @($details | ForEach-Object { ConvertTo-ReportRow -Detail $_ })

if ($ExcludeGuests) {
    $rows = @($rows | Where-Object { $_.UserType -ne 'guest' })
}

# Unregistered admins first, then other unregistered users, then everyone else.
$rows = @($rows | Sort-Object -Property @{ Expression = 'MfaRegistered'; Ascending = $true },
                                        @{ Expression = 'IsAdmin'; Descending = $true },
                                        @{ Expression = 'DisplayName'; Ascending = $true })

$folder = Split-Path -Path $OutputPath -Parent
if ($folder -and -not (Test-Path -Path $folder)) {
    New-Item -Path $folder -ItemType Directory | Out-Null
}
$rows | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding utf8

$summary = Get-ReportSummary -Rows $rows
Write-Host ''
Write-Host 'MFA registration summary' -ForegroundColor Cyan
Write-Host ('  Users in report      : {0}' -f $summary.TotalUsers)
Write-Host ('  Registered for MFA   : {0} ({1}%)' -f $summary.MfaRegistered, $summary.MfaCoveragePercent)
Write-Host ('  Not registered       : {0}' -f $summary.MfaNotRegistered)
Write-Host ('  Registered for SSPR  : {0}' -f $summary.SsprRegistered)

if ($summary.AdminsWithoutMfa.Count -gt 0) {
    Write-Host ''
    Write-Host ('  {0} admin account(s) are NOT registered for MFA:' -f $summary.AdminsWithoutMfa.Count) -ForegroundColor Red
    foreach ($admin in $summary.AdminsWithoutMfa) {
        Write-Host ('    - {0} ({1})' -f $admin.DisplayName, $admin.UserPrincipalName) -ForegroundColor Red
    }
}
else {
    Write-Host '  Every admin account is registered for MFA.' -ForegroundColor Green
}

Write-Host ''
Write-Host ('Report saved to {0}' -f (Resolve-Path -Path $OutputPath))

if ($PassThru) { $rows }
