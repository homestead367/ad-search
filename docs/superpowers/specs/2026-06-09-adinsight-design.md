# ADInsight — Design Spec
**Written by Dallas Milem**
**Date:** 2026-06-09

---

## Overview

ADInsight is a PowerShell-based Active Directory management tool that allows IT administrators to quickly look up user details, compare users side-by-side, and pull GPO attributes. It supports both on-premises Active Directory (via the ActiveDirectory module) and Entra ID (formerly Azure AD, via Microsoft Graph PowerShell SDK). Results are displayed in the console and can be exported as self-contained HTML reports.

---

## Goals

- Fast, interactive AD/Entra user lookups from a single launcher script
- Side-by-side user comparison with visual diff highlighting
- GPO resultant set reporting for local AD users
- Clean HTML export for all three features
- No external dependencies beyond standard Microsoft PowerShell modules

---

## Non-Goals

- GPO reporting for Entra ID (Entra uses Conditional Access / Intune — out of scope)
- Bulk operations (this tool is single-user/two-user focused)
- Active Directory write operations (read-only tool)

---

## File Structure

```
ADInsight/
├── ADInsight.ps1              # Main launcher — menu, connection selection, routing
└── Modules/
    ├── Connect-Source.ps1     # Connection manager for Local AD and Entra ID
    ├── Search-User.ps1        # Feature 1: single user lookup and display
    ├── Compare-Users.ps1      # Feature 2: side-by-side user comparison
    ├── Get-UserGPO.ps1        # Feature 3: GPO resultant set (local AD only)
    └── Export-HTML.ps1        # Shared HTML report generator
```

---

## Main Launcher — ADInsight.ps1

- Displays the app header: `ADInsight v1.0 — Written by Dallas Milem`
- Dot-sources all five module files at startup
- Prompts user to select a **source** first:
  - `[L]` Local AD — uses the `ActiveDirectory` PowerShell module; checks it's installed and a DC is reachable
  - `[E]` Entra ID — uses Microsoft Graph PowerShell SDK (`Microsoft.Graph`)
- Presents main menu:
  ```
  [1] Search User
  [2] Compare Two Users
  [3] Get GPO Attributes (Local AD only)
  [4] Change Source
  [5] Exit
  ```
- Option 3 is disabled (grayed out with a note) when Entra is the active source
- Loop returns to menu after each operation until user selects Exit

---

## Module: Connect-Source.ps1

Handles all connection logic, keeping it isolated from feature modules.

**Local AD:**
- Verifies `ActiveDirectory` module is installed (`Import-Module ActiveDirectory`)
- Tests DC connectivity with `Test-Connection` or `Get-ADDomainController`
- Stores connection state in a script-scoped variable `$script:ADSource = "LocalAD"`

**Entra ID:**
- Verifies `Microsoft.Graph` module is installed
- Prompts auth method:
  - `[I]` Interactive browser login — calls `Connect-MgGraph -Scopes "User.Read.All","GroupMember.Read.All","Policy.Read.All"`
  - `[S]` Service Principal — prompts for Tenant ID, Client ID, and Client Secret; calls `Connect-MgGraph -ClientSecretCredential`
- Stores connection state in `$script:ADSource = "Entra"`

---

## Module: Search-User.ps1 — Feature 1

**Function: `Invoke-UserSearch`**

Prompts for a username (SAM account name, UPN, or display name). Searches the active source and returns a user object.

**Fields retrieved (both sources where available):**

| Field | Local AD | Entra ID |
|---|---|---|
| Display Name | ✓ | ✓ |
| SAM Account Name | ✓ | ✓ (onPremisesSamAccountName) |
| UPN | ✓ | ✓ |
| Email | ✓ | ✓ |
| Department | ✓ | ✓ |
| Title / Job Title | ✓ | ✓ |
| Manager | ✓ | ✓ |
| Account Enabled | ✓ | ✓ |
| Last Logon | ✓ | ✓ (signInActivity) |
| Password Last Set | ✓ | ✓ |
| Password Expiry | ✓ | — |
| Locked Out | ✓ | — |
| Group Memberships | ✓ | ✓ |
| OU / Distinguished Name | ✓ | ✓ |
| Logon Hours | ✓ | — |

Output is printed as a formatted console table. User is prompted: `Export to HTML? [Y/N]` — if yes, calls `Export-HTML.ps1` with a `SearchResult` report type.

---

## Module: Compare-Users.ps1 — Feature 2

**Function: `Invoke-UserComparison`**

Prompts for two usernames. Fetches both users from the active source. Displays a three-column table:

```
Field                  | User 1 (jsmith)       | User 2 (jdoe)
-----------------------|-----------------------|----------------------
Department             | IT                    | HR              [DIFF]
Title                  | Sysadmin              | HR Analyst      [DIFF]
Account Enabled        | True                  | True
Group Memberships      | IT-Admins, VPN-Users  | HR-Staff        [DIFF]
...
```

- Fields that differ are flagged with `[DIFF]` in the console (and highlighted in red/green in HTML export)
- Same fields display normally
- Prompts for HTML export after display

---

## Module: Get-UserGPO.ps1 — Feature 3 (Local AD only)

**Function: `Invoke-UserGPOReport`**

Prompts for a username. Runs GPO resultant set using:
1. Primary: `Get-GPResultantSetOfPolicy` (requires GPMC / RSAT)
2. Fallback: `gpresult /USER <username> /SCOPE USER /R` parsed from stdout

Displays:
- Applied GPOs (name, precedence order, scope: User/Computer)
- Denied/Filtered GPOs (with reason: Security Filtering, WMI Filter, etc.)
- Loopback processing mode (if active)

Note: `Get-GPResultantSetOfPolicy` requires running on or against a domain-joined machine with RSAT installed. The script checks for this and displays a friendly error if unavailable, falling back to `gpresult`.

Prompts for HTML export after display.

---

## Module: Export-HTML.ps1

**Function: `Export-HTMLReport`**

Accepts:
- `$Data` — hashtable of results
- `$ReportType` — `"SearchResult"`, `"Comparison"`, or `"GPOReport"`
- `$Username` — used in filename and report title

Outputs a self-contained `.html` file to `.\Reports\<username>_<type>_<timestamp>.html`. Creates the `Reports` directory if it doesn't exist.

HTML features:
- Inline CSS (no external dependencies, fully portable)
- Dark header bar with "ADInsight — Written by Dallas Milem"
- Comparison report uses green/red row highlighting for DIFF fields
- GPO report uses a sortable table (pure CSS, no JS)
- Timestamp and source (Local AD / Entra) shown in report footer

---

## Error Handling

- Missing modules (ActiveDirectory, Microsoft.Graph): friendly error with install instructions
- User not found: clear message, returns to menu
- DC unreachable: timeout with fallback message
- GPO tool unavailable: falls back to `gpresult` with a warning
- Entra auth failure: catches and displays the Graph error message

---

## Dependencies

| Dependency | Required For | Install Command |
|---|---|---|
| `ActiveDirectory` module | Local AD features | Installed via RSAT on Windows |
| `Microsoft.Graph` module | Entra ID features | `Install-Module Microsoft.Graph` |
| `GroupPolicy` module | Feature 3 (GPMC) | Installed via RSAT on Windows |

---

## Out of Scope (explicitly excluded)

- Writing or modifying AD/Entra objects
- Entra GPO/Conditional Access reporting
- Bulk user operations
- Scheduling or automation wrappers
- Any GUI beyond console menus
