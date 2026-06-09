# ADInsight
**Written by Dallas Milem**

A PowerShell-based Active Directory management tool for IT administrators. Quickly search user details, compare users side-by-side, and pull GPO attributes — all from a single interactive launcher. Supports both on-premises Active Directory and Entra ID (formerly Azure AD).

---

## Features

- **User Search** — Look up any user by SAM account name, UPN, or display name. Displays all key attributes including group memberships, account status, last logon, password info, and more.
- **User Comparison** — Compare two users side-by-side with visual diff highlighting. Quickly identify differences in groups, departments, permissions, and account settings.
- **GPO Attribute Report** — Pull the full GPO resultant set for any user on a local AD domain. Shows applied policies, denied/filtered GPOs, precedence order, and loopback status.
- **HTML Export** — Export any result to a clean, self-contained HTML report saved to the `Reports\` folder.
- **Dual Source Support** — Switch between Local AD and Entra ID at runtime.

---

## Requirements

| Requirement | Details |
|---|---|
| PowerShell | 5.1 or later (PowerShell 7+ recommended) |
| OS | Windows (domain-joined for Local AD features) |
| RSAT | Required for Local AD and GPO features |
| Microsoft.Graph | Required for Entra ID features |

### Installing RSAT (Windows 10/11)
```powershell
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
Add-WindowsCapability -Online -Name Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0
```

### Installing Microsoft Graph PowerShell SDK
```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

---

## File Structure

```
ADInsight/
├── ADInsight.ps1              # Main launcher — run this
├── README.md                  # This file
├── Modules/
│   ├── Connect-Source.ps1     # Connection manager (Local AD / Entra ID)
│   ├── Search-User.ps1        # Feature 1: single user lookup
│   ├── Compare-Users.ps1      # Feature 2: side-by-side user comparison
│   ├── Get-UserGPO.ps1        # Feature 3: GPO resultant set (Local AD only)
│   └── Export-HTML.ps1        # Shared HTML report generator
└── Reports/                   # HTML reports saved here (auto-created)
```

---

## Usage

Run the launcher from PowerShell:

```powershell
.\ADInsight.ps1
```

You will be prompted to select a source:

```
ADInsight v1.0 — Written by Dallas Milem
=========================================
Select Source:
  [L] Local AD Domain Controller
  [E] Entra ID (Azure AD)
```

Then choose from the main menu:

```
[1] Search User
[2] Compare Two Users
[3] Get GPO Attributes  (Local AD only)
[4] Change Source
[5] Exit
```

---

## Entra ID Authentication

When connecting to Entra ID, you will be prompted for an authentication method:

**Interactive Login** — Opens a browser window for sign-in. Supports MFA. Recommended for interactive use.
```
[I] Interactive Browser Login
```

**Service Principal** — Non-interactive authentication using an App Registration. Recommended for automation or shared admin machines.
```
[S] Service Principal (Client ID + Secret)
```

Required Graph API permissions for the App Registration:
- `User.Read.All`
- `GroupMember.Read.All`
- `Policy.Read.All`

---

## HTML Reports

After any search or comparison, you will be prompted to export an HTML report. Reports are saved to:

```
.\Reports\<username>_<type>_<timestamp>.html
```

Reports are fully self-contained (no external dependencies) and can be shared via email or Teams.

---

## Notes

- **GPO reporting** requires RSAT Group Policy Management Tools and must be run on or against a domain-joined machine. If unavailable, the tool falls back to `gpresult /R`.
- **Entra ID** does not support GPO reporting (Entra uses Conditional Access and Intune policies, which are out of scope for this tool).
- This tool is **read-only** — it makes no changes to AD or Entra.

---

## Changelog

| Version | Date | Notes |
|---|---|---|
| 1.0 | 2026-06-09 | Initial release |
