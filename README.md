[README.md](https://github.com/user-attachments/files/32489376/README.md)
# MFA Registration Report

A PowerShell script that uses **Microsoft Graph** to report which users in a Microsoft Entra ID (Azure AD) tenant are registered for multi-factor authentication. It exports a CSV and prints a short summary, and it calls out any **admin accounts without MFA**.

MFA is one of the most effective controls against account takeover, and it's a requirement for cloud services under Cyber Essentials. IT and security teams regularly need evidence of who is actually covered, for access reviews, audits and follow-up with users. This script produces that evidence in one command, using a single read-only permission.

## What it does

- Pulls the authentication methods registration report for every user through Microsoft Graph (`GET /reports/authenticationMethods/userRegistrationDetails`)
- Builds one row per user covering MFA and SSPR registration, registered methods, preferred second factor and admin status
- Sorts unregistered admins to the top, then other unregistered users
- Prints a summary with MFA coverage (%) and a list of admins who aren't registered
- Exports everything to a dated CSV
- Signs out of Microsoft Graph when it finishes

## Requirements

| Requirement | Detail |
|---|---|
| PowerShell | 7+ recommended (Windows PowerShell 5.1 also works) |
| Module | `Microsoft.Graph.Reports` (installs `Microsoft.Graph.Authentication` with it) |
| Graph permission | `AuditLog.Read.All` (delegated): the least-privileged permission for this report |
| Entra role | Reports Reader, Security Reader, Security Administrator or Global Reader |
| Licence | Microsoft Entra ID P1 or P2 (required for the authentication methods reports) |

## Quick start

```powershell
# 1. Install the Graph Reports module (one-off)
Install-Module Microsoft.Graph.Reports -Scope CurrentUser

# 2. Run the report - you'll be asked to sign in and consent to AuditLog.Read.All
.\Get-MfaRegistrationReport.ps1

# Members only, saved somewhere specific
.\Get-MfaRegistrationReport.ps1 -ExcludeGuests -OutputPath .\reports\mfa.csv
```

### Try it without a tenant

The `sample` folder holds fictional data in the same shape Graph returns, so you can see the output without signing in:

```powershell
.\Get-MfaRegistrationReport.ps1 -InputPath .\sample\sample-registration-details.json -OutputPath .\sample\sample-report.csv
```

## Parameters

| Parameter | Purpose |
|---|---|
| `-OutputPath` | CSV location. Defaults to `MfaRegistrationReport_<date>.csv` in the current folder |
| `-ExcludeGuests` | Leave guest (B2B) accounts out of the report |
| `-TenantId` | Tenant to sign in to, if your account can access more than one |
| `-InputPath` | Build the report from a JSON file instead of calling Graph (testing and demos) |
| `-PassThru` | Also return the rows to the pipeline for further filtering |

Run `Get-Help .\Get-MfaRegistrationReport.ps1 -Full` for full help.

## Example output

Console summary from the sample data:

```text
MFA registration summary
  Users in report      : 10
  Registered for MFA   : 7 (70%)
  Not registered       : 3
  Registered for SSPR  : 7

  1 admin account(s) are NOT registered for MFA:
    - Daniel Okafor (daniel.okafor@contoso.onmicrosoft.com)

Report saved to .\sample\sample-report.csv
```

CSV (first rows; full file in [`sample/sample-report.csv`](sample/sample-report.csv)):

| DisplayName | IsAdmin | MfaRegistered | SsprRegistered | MethodsRegistered | PreferredSecondFactor |
|---|---|---|---|---|---|
| Daniel Okafor | True | False | False | | none |
| Lena Fischer | False | False | False | | none |
| Sofia Marin | False | False | True | email | none |
| Amelia Hart | True | True | True | microsoftAuthenticatorPush; fido2SecurityKey | push |

All names in the sample are fictional.

## How it works

1. Checks that `Microsoft.Graph.Reports` is installed, then connects with `Connect-MgGraph -Scopes AuditLog.Read.All`.
2. Calls `Get-MgReportAuthenticationMethodUserRegistrationDetail -All`, which pages through every user.
3. Converts each result into a flat row. A small helper reads properties by name, so the same code handles Graph SDK objects and JSON test data.
4. Optionally removes guests, sorts the rows, exports the CSV and works out the summary figures.
5. Disconnects from Graph in a `finally` block, so the session closes even if the request fails.

## Security notes

- **Read-only:** the script never changes users or policies.
- **Least privilege:** it requests only `AuditLog.Read.All`, and the signed-in account needs only a reader role.
- **Handle the output carefully:** the CSV contains names and email addresses. Store it securely and share it only with people who need it. `.gitignore` blocks report CSVs from being committed (the fictional sample is the only exception).

## Troubleshooting

| Problem | Likely cause |
|---|---|
| `Microsoft.Graph.Reports module isn't installed` | Run `Install-Module Microsoft.Graph.Reports -Scope CurrentUser` |
| `403 Forbidden` / `Authorization_RequestDenied` | The account lacks a supported reader role, or consent to `AuditLog.Read.All` wasn't granted |
| Licence error | The tenant needs Microsoft Entra ID P1 or P2 for authentication methods reports |

## Ideas for next versions

- App-only authentication with a certificate, so the report can run on a schedule
- An HTML summary for non-technical readers
- Tracking coverage over time by comparing each run with the last

## References

- [List userRegistrationDetails (Microsoft Graph)](https://learn.microsoft.com/graph/api/authenticationmethodsroot-list-userregistrationdetails)
- [Get-MgReportAuthenticationMethodUserRegistrationDetail](https://learn.microsoft.com/powershell/module/microsoft.graph.reports/get-mgreportauthenticationmethoduserregistrationdetail)
- [Authentication Methods Activity: licence and role requirements](https://learn.microsoft.com/entra/identity/authentication/howto-authentication-methods-activity)
