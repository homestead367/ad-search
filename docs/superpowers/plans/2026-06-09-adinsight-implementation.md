# ADInsight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build ADInsight — a modular PowerShell tool for AD/Entra user search, comparison, and GPO reporting with HTML export.

**Architecture:** Modular scripts dot-sourced by a central launcher. A shared HTML exporter handles all three report types. Connection management is isolated in its own module so feature scripts never handle auth directly.

**Tech Stack:** PowerShell 5.1+, ActiveDirectory module (RSAT), Microsoft.Graph PowerShell SDK, GroupPolicy module (RSAT), no external dependencies.

---

## File Map

| File | Responsibility |
|---|---|
| `ADInsight.ps1` | Entry point — dot-sources modules, shows menu, routes user input |
| `Modules/Connect-Source.ps1` | Auth logic for Local AD and Entra ID (interactive + SPN) |
| `Modules/Export-HTML.ps1` | Shared HTML report generator for all three report types |
| `Modules/Search-User.ps1` | Single-user lookup and console display |
| `Modules/Compare-Users.ps1` | Two-user side-by-side diff display |
| `Modules/Get-UserGPO.ps1` | GPO resultant set pull (local AD only) |

---

## Task 1: Export-HTML.ps1 — Shared Report Generator

**Files:**
- Create: `Modules/Export-HTML.ps1`

- [ ] **Step 1: Create Export-HTML.ps1 with the `Export-HTMLReport` function**

```powershell
# Modules/Export-HTML.ps1
# Written by Dallas Milem

function Export-HTMLReport {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Data,

        [Parameter(Mandatory)]
        [ValidateSet("SearchResult","Comparison","GPOReport")]
        [string]$ReportType,

        [Parameter(Mandatory)]
        [string]$Username,

        [string]$Source = "Unknown"
    )

    $reportsDir = Join-Path $PSScriptRoot "..\Reports"
    if (-not (Test-Path $reportsDir)) {
        New-Item -ItemType Directory -Path $reportsDir | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $filename  = "${Username}_${ReportType}_${timestamp}.html"
    $filepath  = Join-Path $reportsDir $filename

    $css = @"
<style>
  body { font-family: Segoe UI, Arial, sans-serif; background: #f4f6f8; margin: 0; padding: 0; }
  header { background: #1a1a2e; color: #fff; padding: 18px 32px; }
  header h1 { margin: 0; font-size: 1.5em; letter-spacing: 1px; }
  header p  { margin: 4px 0 0; font-size: 0.85em; color: #aaa; }
  .container { padding: 24px 32px; }
  table { border-collapse: collapse; width: 100%; background: #fff;
          box-shadow: 0 1px 4px rgba(0,0,0,0.08); border-radius: 6px; overflow: hidden; }
  th { background: #1a1a2e; color: #fff; padding: 10px 14px; text-align: left; font-size: 0.9em; }
  td { padding: 9px 14px; border-bottom: 1px solid #e8ecf0; font-size: 0.9em; }
  tr:last-child td { border-bottom: none; }
  tr.diff td { background: #fff3f3; }
  tr.diff td.val1 { color: #c0392b; }
  tr.diff td.val2 { color: #27ae60; }
  tr.same td { background: #fff; }
  .badge-diff  { background: #e74c3c; color: #fff; border-radius: 3px;
                 padding: 1px 6px; font-size: 0.75em; margin-left: 6px; }
  .badge-applied  { background: #27ae60; color: #fff; border-radius: 3px; padding: 1px 6px; font-size: 0.75em; }
  .badge-denied   { background: #e74c3c; color: #fff; border-radius: 3px; padding: 1px 6px; font-size: 0.75em; }
  footer { padding: 16px 32px; color: #888; font-size: 0.8em; border-top: 1px solid #e0e0e0; margin-top: 24px; }
  h2 { color: #1a1a2e; margin-bottom: 12px; }
</style>
"@

    $header = @"
<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>ADInsight — $ReportType</title>$css</head>
<body>
<header>
  <h1>ADInsight</h1>
  <p>Written by Dallas Milem &nbsp;|&nbsp; Report: $ReportType &nbsp;|&nbsp; User: $Username &nbsp;|&nbsp; Source: $Source</p>
</header>
<div class="container">
"@

    $footer = @"
</div>
<footer>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') &nbsp;|&nbsp; Source: $Source &nbsp;|&nbsp; ADInsight v1.0</footer>
</body></html>
"@

    switch ($ReportType) {
        "SearchResult" { $body = Build-SearchHTML -Data $Data }
        "Comparison"   { $body = Build-ComparisonHTML -Data $Data }
        "GPOReport"    { $body = Build-GPOHTML -Data $Data }
    }

    $html = $header + $body + $footer
    $html | Out-File -FilePath $filepath -Encoding UTF8
    return $filepath
}

function Build-SearchHTML {
    param([hashtable]$Data)
    $rows = ""
    foreach ($key in $Data.Keys) {
        $val = if ($null -eq $Data[$key]) { "<em>N/A</em>" } else { [System.Web.HttpUtility]::HtmlEncode($Data[$key].ToString()) }
        $rows += "<tr><td><strong>$key</strong></td><td>$val</td></tr>`n"
    }
    return "<h2>User Details</h2><table><thead><tr><th>Field</th><th>Value</th></tr></thead><tbody>$rows</tbody></table>"
}

function Build-ComparisonHTML {
    param([hashtable]$Data)
    # Data keys: Fields (ordered array), User1Name, User2Name, Rows (array of [Field, Val1, Val2, IsDiff])
    $u1 = [System.Web.HttpUtility]::HtmlEncode($Data.User1Name)
    $u2 = [System.Web.HttpUtility]::HtmlEncode($Data.User2Name)
    $rows = ""
    foreach ($row in $Data.Rows) {
        $cssClass = if ($row.IsDiff) { "diff" } else { "same" }
        $badge    = if ($row.IsDiff) { '<span class="badge-diff">DIFF</span>' } else { "" }
        $v1class  = if ($row.IsDiff) { ' class="val1"' } else { "" }
        $v2class  = if ($row.IsDiff) { ' class="val2"' } else { "" }
        $v1 = if ($null -eq $row.Val1) { "<em>N/A</em>" } else { [System.Web.HttpUtility]::HtmlEncode($row.Val1.ToString()) }
        $v2 = if ($null -eq $row.Val2) { "<em>N/A</em>" } else { [System.Web.HttpUtility]::HtmlEncode($row.Val2.ToString()) }
        $rows += "<tr class='$cssClass'><td><strong>$($row.Field)</strong>$badge</td><td$v1class>$v1</td><td$v2class>$v2</td></tr>`n"
    }
    return "<h2>User Comparison</h2><table><thead><tr><th>Field</th><th>$u1</th><th>$u2</th></tr></thead><tbody>$rows</tbody></table>"
}

function Build-GPOHTML {
    param([hashtable]$Data)
    $applied = ""
    foreach ($gpo in $Data.AppliedGPOs) {
        $name = [System.Web.HttpUtility]::HtmlEncode($gpo.Name)
        $applied += "<tr><td>$($gpo.Order)</td><td>$name</td><td>$($gpo.Scope)</td><td><span class='badge-applied'>Applied</span></td></tr>`n"
    }
    $denied = ""
    foreach ($gpo in $Data.DeniedGPOs) {
        $name   = [System.Web.HttpUtility]::HtmlEncode($gpo.Name)
        $reason = [System.Web.HttpUtility]::HtmlEncode($gpo.Reason)
        $denied += "<tr><td>—</td><td>$name</td><td>$($gpo.Scope)</td><td><span class='badge-denied'>$reason</span></td></tr>`n"
    }
    $loopback = if ($Data.LoopbackMode -and $Data.LoopbackMode -ne "None") {
        "<p><strong>Loopback Processing Mode:</strong> $($Data.LoopbackMode)</p>"
    } else { "" }
    return @"
<h2>GPO Resultant Set — $([System.Web.HttpUtility]::HtmlEncode($Data.Username))</h2>
$loopback
<table>
  <thead><tr><th>#</th><th>Policy Name</th><th>Scope</th><th>Status</th></tr></thead>
  <tbody>$applied$denied</tbody>
</table>
"@
}
```

- [ ] **Step 2: Verify PowerShell syntax**

```powershell
pwsh -NoProfile -Command "
  \$errors = \$null
  \$null = [System.Management.Automation.Language.Parser]::ParseFile(
    '/project/ADUser/Modules/Export-HTML.ps1', [ref]\$null, [ref]\$errors
  )
  if (\$errors.Count -gt 0) { \$errors | ForEach-Object { Write-Host \$_.Message -ForegroundColor Red }; exit 1 }
  Write-Host 'Syntax OK' -ForegroundColor Green
"
```
Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add Modules/Export-HTML.ps1
git commit -m "feat: add Export-HTML module with SearchResult, Comparison, GPO report builders"
```

---

## Task 2: Connect-Source.ps1 — Connection Manager

**Files:**
- Create: `Modules/Connect-Source.ps1`

- [ ] **Step 1: Create Connect-Source.ps1**

```powershell
# Modules/Connect-Source.ps1
# Written by Dallas Milem

$script:ADSource = $null

function Connect-LocalAD {
    Write-Host "`nChecking ActiveDirectory module..." -ForegroundColor Cyan

    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Write-Host "[ERROR] ActiveDirectory module not found." -ForegroundColor Red
        Write-Host "Install RSAT: Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0" -ForegroundColor Yellow
        return $false
    }

    Import-Module ActiveDirectory -ErrorAction SilentlyContinue

    Write-Host "Testing domain controller connectivity..." -ForegroundColor Cyan
    try {
        $dc = Get-ADDomainController -Discover -ErrorAction Stop
        Write-Host "[OK] Connected to domain: $($dc.Domain) via $($dc.HostName)" -ForegroundColor Green
        $script:ADSource = "LocalAD"
        return $true
    }
    catch {
        Write-Host "[ERROR] Cannot reach a domain controller: $_" -ForegroundColor Red
        return $false
    }
}

function Connect-EntraID {
    Write-Host "`nChecking Microsoft.Graph module..." -ForegroundColor Cyan

    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        Write-Host "[ERROR] Microsoft.Graph module not found." -ForegroundColor Red
        Write-Host "Install it: Install-Module Microsoft.Graph -Scope CurrentUser" -ForegroundColor Yellow
        return $false
    }

    Write-Host ""
    Write-Host "Select authentication method:" -ForegroundColor Cyan
    Write-Host "  [I] Interactive browser login (MFA supported)"
    Write-Host "  [S] Service Principal (Client ID + Secret)"
    Write-Host ""
    $authChoice = Read-Host "Choice"

    try {
        switch ($authChoice.ToUpper()) {
            "I" {
                Write-Host "Opening browser for authentication..." -ForegroundColor Cyan
                Connect-MgGraph -Scopes "User.Read.All","GroupMember.Read.All","Policy.Read.All" -ErrorAction Stop | Out-Null
            }
            "S" {
                $tenantId    = Read-Host "Tenant ID"
                $clientId    = Read-Host "Client ID"
                $clientSecret = Read-Host "Client Secret" -AsSecureString
                $credential  = New-Object System.Management.Automation.PSCredential($clientId, $clientSecret)
                Connect-MgGraph -TenantId $tenantId -ClientSecretCredential $credential -ErrorAction Stop | Out-Null
            }
            default {
                Write-Host "[ERROR] Invalid choice." -ForegroundColor Red
                return $false
            }
        }

        $ctx = Get-MgContext
        Write-Host "[OK] Connected to Entra tenant: $($ctx.TenantId)" -ForegroundColor Green
        $script:ADSource = "Entra"
        return $true
    }
    catch {
        Write-Host "[ERROR] Entra authentication failed: $_" -ForegroundColor Red
        return $false
    }
}

function Get-ADSource {
    return $script:ADSource
}
```

- [ ] **Step 2: Verify syntax**

```powershell
pwsh -NoProfile -Command "
  \$errors = \$null
  \$null = [System.Management.Automation.Language.Parser]::ParseFile(
    '/project/ADUser/Modules/Connect-Source.ps1', [ref]\$null, [ref]\$errors
  )
  if (\$errors.Count -gt 0) { \$errors | ForEach-Object { Write-Host \$_.Message -ForegroundColor Red }; exit 1 }
  Write-Host 'Syntax OK' -ForegroundColor Green
"
```
Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add Modules/Connect-Source.ps1
git commit -m "feat: add Connect-Source module for Local AD and Entra ID auth"
```

---

## Task 3: Search-User.ps1 — Single User Lookup

**Files:**
- Create: `Modules/Search-User.ps1`

- [ ] **Step 1: Create Search-User.ps1**

```powershell
# Modules/Search-User.ps1
# Written by Dallas Milem

function Invoke-UserSearch {
    $query = Read-Host "`nEnter username (SAM, UPN, or Display Name)"
    if ([string]::IsNullOrWhiteSpace($query)) {
        Write-Host "[ERROR] No input provided." -ForegroundColor Red
        return
    }

    $source = Get-ADSource
    Write-Host "`nSearching $source for '$query'..." -ForegroundColor Cyan

    $userData = $null
    switch ($source) {
        "LocalAD" { $userData = Search-LocalADUser -Query $query }
        "Entra"   { $userData = Search-EntraUser   -Query $query }
    }

    if ($null -eq $userData) {
        Write-Host "[NOT FOUND] No user matching '$query'." -ForegroundColor Yellow
        return
    }

    Show-UserTable -Data $userData
    Prompt-HTMLExport -Data $userData -ReportType "SearchResult" -Username $userData["SAM Account Name"]
}

function Search-LocalADUser {
    param([string]$Query)
    try {
        $props = @(
            "DisplayName","SamAccountName","UserPrincipalName","EmailAddress",
            "Department","Title","Manager","Enabled","LastLogonDate",
            "PasswordLastSet","PasswordNeverExpires","PasswordExpired",
            "LockedOut","MemberOf","DistinguishedName","LogonHours","AccountExpirationDate"
        )
        $user = Get-ADUser -Filter {
            SamAccountName -eq $Query -or UserPrincipalName -eq $Query -or DisplayName -eq $Query
        } -Properties $props -ErrorAction Stop | Select-Object -First 1

        if ($null -eq $user) { return $null }

        $managerName = "N/A"
        if ($user.Manager) {
            try { $managerName = (Get-ADUser $user.Manager).DisplayName } catch {}
        }

        $groups = @()
        if ($user.MemberOf) {
            $groups = $user.MemberOf | ForEach-Object {
                try { (Get-ADGroup $_).Name } catch { $_ }
            }
        }

        $pwExpiry = "N/A"
        if ($user.PasswordLastSet -and -not $user.PasswordNeverExpires) {
            try {
                $policy = Get-ADDefaultDomainPasswordPolicy
                if ($policy.MaxPasswordAge.TotalDays -gt 0) {
                    $pwExpiry = $user.PasswordLastSet.AddDays($policy.MaxPasswordAge.TotalDays).ToString("yyyy-MM-dd HH:mm")
                }
            } catch {}
        } elseif ($user.PasswordNeverExpires) {
            $pwExpiry = "Never Expires"
        }

        $logonHours = "Not Restricted"
        if ($user.LogonHours -and ($user.LogonHours -ne ([byte[]]@(255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255)))) {
            $logonHours = "Custom Schedule Set"
        }

        return [ordered]@{
            "Display Name"        = $user.DisplayName
            "SAM Account Name"    = $user.SamAccountName
            "UPN"                 = $user.UserPrincipalName
            "Email"               = $user.EmailAddress
            "Department"          = $user.Department
            "Title"               = $user.Title
            "Manager"             = $managerName
            "Account Enabled"     = $user.Enabled
            "Locked Out"          = $user.LockedOut
            "Last Logon"          = if ($user.LastLogonDate) { $user.LastLogonDate.ToString("yyyy-MM-dd HH:mm") } else { "Never" }
            "Password Last Set"   = if ($user.PasswordLastSet) { $user.PasswordLastSet.ToString("yyyy-MM-dd HH:mm") } else { "N/A" }
            "Password Expiry"     = $pwExpiry
            "Logon Hours"         = $logonHours
            "Group Memberships"   = if ($groups.Count -gt 0) { $groups -join ", " } else { "None" }
            "Distinguished Name"  = $user.DistinguishedName
        }
    }
    catch {
        Write-Host "[ERROR] AD query failed: $_" -ForegroundColor Red
        return $null
    }
}

function Search-EntraUser {
    param([string]$Query)
    try {
        Import-Module Microsoft.Graph.Users -ErrorAction SilentlyContinue
        Import-Module Microsoft.Graph.Groups -ErrorAction SilentlyContinue

        $filter = "displayName eq '$Query' or userPrincipalName eq '$Query' or onPremisesSamAccountName eq '$Query'"
        $selectProps = "id,displayName,userPrincipalName,onPremisesSamAccountName,mail,department,jobTitle,manager,accountEnabled,lastPasswordChangeDateTime,signInActivity,onPremisesDistinguishedName"
        $user = Get-MgUser -Filter $filter -Property $selectProps -Top 1 -ErrorAction Stop | Select-Object -First 1

        if ($null -eq $user) { return $null }

        $managerName = "N/A"
        try {
            $mgr = Get-MgUserManager -UserId $user.Id -ErrorAction SilentlyContinue
            if ($mgr) { $managerName = $mgr.AdditionalProperties["displayName"] }
        } catch {}

        $groups = @()
        try {
            $groups = (Get-MgUserMemberOf -UserId $user.Id -ErrorAction SilentlyContinue) |
                Where-Object { $_.'@odata.type' -eq '#microsoft.graph.group' } |
                ForEach-Object { $_.AdditionalProperties["displayName"] }
        } catch {}

        $lastLogon = "N/A"
        if ($user.SignInActivity) {
            $lastLogon = $user.SignInActivity.LastSignInDateTime
        }

        return [ordered]@{
            "Display Name"        = $user.DisplayName
            "SAM Account Name"    = $user.OnPremisesSamAccountName
            "UPN"                 = $user.UserPrincipalName
            "Email"               = $user.Mail
            "Department"          = $user.Department
            "Title"               = $user.JobTitle
            "Manager"             = $managerName
            "Account Enabled"     = $user.AccountEnabled
            "Last Logon"          = $lastLogon
            "Password Last Set"   = $user.LastPasswordChangeDateTime
            "Group Memberships"   = if ($groups.Count -gt 0) { $groups -join ", " } else { "None" }
            "Distinguished Name"  = $user.OnPremisesDistinguishedName
        }
    }
    catch {
        Write-Host "[ERROR] Entra query failed: $_" -ForegroundColor Red
        return $null
    }
}

function Show-UserTable {
    param([System.Collections.Specialized.OrderedDictionary]$Data)
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
    Write-Host " USER DETAILS" -ForegroundColor White
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
    foreach ($key in $Data.Keys) {
        $val = if ($null -eq $Data[$key]) { "N/A" } else { $Data[$key].ToString() }
        Write-Host ("  {0,-25} {1}" -f "$key :", $val)
    }
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
    Write-Host ""
}

function Prompt-HTMLExport {
    param(
        [System.Collections.Specialized.OrderedDictionary]$Data,
        [string]$ReportType,
        [string]$Username
    )
    $choice = Read-Host "Export to HTML report? [Y/N]"
    if ($choice -match "^[Yy]") {
        $path = Export-HTMLReport -Data $Data -ReportType $ReportType -Username $Username -Source (Get-ADSource)
        Write-Host "[OK] Report saved: $path" -ForegroundColor Green
    }
}
```

- [ ] **Step 2: Verify syntax**

```powershell
pwsh -NoProfile -Command "
  \$errors = \$null
  \$null = [System.Management.Automation.Language.Parser]::ParseFile(
    '/project/ADUser/Modules/Search-User.ps1', [ref]\$null, [ref]\$errors
  )
  if (\$errors.Count -gt 0) { \$errors | ForEach-Object { Write-Host \$_.Message -ForegroundColor Red }; exit 1 }
  Write-Host 'Syntax OK' -ForegroundColor Green
"
```
Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add Modules/Search-User.ps1
git commit -m "feat: add Search-User module for Local AD and Entra user lookup"
```

---

## Task 4: Compare-Users.ps1 — Side-by-Side User Comparison

**Files:**
- Create: `Modules/Compare-Users.ps1`

- [ ] **Step 1: Create Compare-Users.ps1**

```powershell
# Modules/Compare-Users.ps1
# Written by Dallas Milem

function Invoke-UserComparison {
    $query1 = Read-Host "`nEnter first username (SAM, UPN, or Display Name)"
    $query2 = Read-Host "Enter second username (SAM, UPN, or Display Name)"

    if ([string]::IsNullOrWhiteSpace($query1) -or [string]::IsNullOrWhiteSpace($query2)) {
        Write-Host "[ERROR] Both usernames are required." -ForegroundColor Red
        return
    }

    $source = Get-ADSource
    Write-Host "`nFetching both users from $source..." -ForegroundColor Cyan

    switch ($source) {
        "LocalAD" {
            $user1 = Search-LocalADUser -Query $query1
            $user2 = Search-LocalADUser -Query $query2
        }
        "Entra" {
            $user1 = Search-EntraUser -Query $query1
            $user2 = Search-EntraUser -Query $query2
        }
    }

    if ($null -eq $user1) { Write-Host "[NOT FOUND] '$query1' not found." -ForegroundColor Yellow; return }
    if ($null -eq $user2) { Write-Host "[NOT FOUND] '$query2' not found." -ForegroundColor Yellow; return }

    $comparisonRows = Build-ComparisonRows -User1 $user1 -User2 $user2 -User1Name $query1 -User2Name $query2
    Show-ComparisonTable -Rows $comparisonRows -User1Name $query1 -User2Name $query2

    $exportData = @{
        User1Name = $query1
        User2Name = $query2
        Rows      = $comparisonRows
    }

    $choice = Read-Host "Export to HTML report? [Y/N]"
    if ($choice -match "^[Yy]") {
        $path = Export-HTMLReport -Data $exportData -ReportType "Comparison" -Username "${query1}_vs_${query2}" -Source (Get-ADSource)
        Write-Host "[OK] Report saved: $path" -ForegroundColor Green
    }
}

function Build-ComparisonRows {
    param(
        [System.Collections.Specialized.OrderedDictionary]$User1,
        [System.Collections.Specialized.OrderedDictionary]$User2,
        [string]$User1Name,
        [string]$User2Name
    )
    $rows = @()
    $allKeys = ($User1.Keys + $User2.Keys) | Select-Object -Unique

    foreach ($key in $allKeys) {
        $v1 = if ($User1.Contains($key)) { $User1[$key] } else { $null }
        $v2 = if ($User2.Contains($key)) { $User2[$key] } else { $null }
        $v1str = if ($null -eq $v1) { "" } else { $v1.ToString() }
        $v2str = if ($null -eq $v2) { "" } else { $v2.ToString() }
        $isDiff = $v1str -ne $v2str

        $rows += [PSCustomObject]@{
            Field  = $key
            Val1   = $v1str
            Val2   = $v2str
            IsDiff = $isDiff
        }
    }
    return $rows
}

function Show-ComparisonTable {
    param(
        [PSCustomObject[]]$Rows,
        [string]$User1Name,
        [string]$User2Name
    )
    $colW = 28
    $line = ("=" * ($colW * 3 + 10))

    Write-Host ""
    Write-Host $line -ForegroundColor DarkCyan
    Write-Host (" USER COMPARISON") -ForegroundColor White
    Write-Host $line -ForegroundColor DarkCyan
    Write-Host ("  {0,-25} {1,-28} {2}" -f "Field", $User1Name.ToUpper(), $User2Name.ToUpper()) -ForegroundColor Gray
    Write-Host ("-" * ($colW * 3 + 10)) -ForegroundColor DarkGray

    foreach ($row in $Rows) {
        $v1 = if ([string]::IsNullOrEmpty($row.Val1)) { "N/A" } else { $row.Val1 }
        $v2 = if ([string]::IsNullOrEmpty($row.Val2)) { "N/A" } else { $row.Val2 }

        if ($row.IsDiff) {
            Write-Host ("  {0,-25}" -f "$($row.Field) :") -NoNewline -ForegroundColor Yellow
            Write-Host (" {0,-28}" -f $v1) -NoNewline -ForegroundColor Red
            Write-Host (" $v2  [DIFF]") -ForegroundColor Green
        } else {
            Write-Host ("  {0,-25} {1,-28} {2}" -f "$($row.Field) :", $v1, $v2)
        }
    }
    Write-Host $line -ForegroundColor DarkCyan
    Write-Host ""
}
```

- [ ] **Step 2: Verify syntax**

```powershell
pwsh -NoProfile -Command "
  \$errors = \$null
  \$null = [System.Management.Automation.Language.Parser]::ParseFile(
    '/project/ADUser/Modules/Compare-Users.ps1', [ref]\$null, [ref]\$errors
  )
  if (\$errors.Count -gt 0) { \$errors | ForEach-Object { Write-Host \$_.Message -ForegroundColor Red }; exit 1 }
  Write-Host 'Syntax OK' -ForegroundColor Green
"
```
Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add Modules/Compare-Users.ps1
git commit -m "feat: add Compare-Users module with diff highlighting"
```

---

## Task 5: Get-UserGPO.ps1 — GPO Resultant Set

**Files:**
- Create: `Modules/Get-UserGPO.ps1`

- [ ] **Step 1: Create Get-UserGPO.ps1**

```powershell
# Modules/Get-UserGPO.ps1
# Written by Dallas Milem

function Invoke-UserGPOReport {
    $username = Read-Host "`nEnter username for GPO report (SAM account name)"
    if ([string]::IsNullOrWhiteSpace($username)) {
        Write-Host "[ERROR] No username provided." -ForegroundColor Red
        return
    }

    Write-Host "`nPulling GPO Resultant Set for '$username'..." -ForegroundColor Cyan

    $gpoData = $null

    # Try GPMC module first
    if (Get-Module -ListAvailable -Name GroupPolicy) {
        $gpoData = Get-GPOResultantSet -Username $username
    }

    # Fall back to gpresult
    if ($null -eq $gpoData) {
        Write-Host "[INFO] GPMC module unavailable, falling back to gpresult..." -ForegroundColor Yellow
        $gpoData = Get-GPResultFallback -Username $username
    }

    if ($null -eq $gpoData) {
        Write-Host "[ERROR] Could not retrieve GPO data. Ensure this machine is domain-joined and RSAT is installed." -ForegroundColor Red
        return
    }

    Show-GPOTable -Data $gpoData
    Prompt-GPOHTMLExport -Data $gpoData -Username $username
}

function Get-GPOResultantSet {
    param([string]$Username)
    try {
        Import-Module GroupPolicy -ErrorAction Stop

        # Get-GPResultantSetOfPolicy writes an XML report to a temp file
        $tempFile = [System.IO.Path]::GetTempFileName() + ".xml"
        $null = Get-GPResultantSetOfPolicy -User $Username -ReportType XML -Path $tempFile -ErrorAction Stop

        [xml]$rsop = Get-Content $tempFile -ErrorAction Stop
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

        $applied = @()
        $denied  = @()
        $order   = 1

        $gpoNodes = $rsop.SelectNodes("//GPO")
        foreach ($gpo in $gpoNodes) {
            $name  = $gpo.Name
            $scope = if ($gpo.ParentNode.LocalName -eq "UserResults") { "User" } else { "Computer" }

            $linkNodes = $gpo.SelectNodes("LinkOrder") | Select-Object -First 1
            $applied += [PSCustomObject]@{
                Order = $order++
                Name  = $name
                Scope = $scope
            }
        }

        $filteredNodes = $rsop.SelectNodes("//FilteredGPO")
        foreach ($fgpo in $filteredNodes) {
            $name   = $fgpo.Name
            $reason = $fgpo.FilterStatus
            $denied += [PSCustomObject]@{
                Name   = $name
                Scope  = "User"
                Reason = $reason
            }
        }

        $loopback = "None"
        $loopNode = $rsop.SelectSingleNode("//LoopbackMode")
        if ($loopNode) { $loopback = $loopNode.InnerText }

        return @{
            Username    = $Username
            AppliedGPOs = $applied
            DeniedGPOs  = $denied
            LoopbackMode = $loopback
            Source      = "GPMC"
        }
    }
    catch {
        Write-Host "[WARN] GPMC method failed: $_" -ForegroundColor Yellow
        return $null
    }
}

function Get-GPResultFallback {
    param([string]$Username)
    try {
        $output = & gpresult /USER $Username /SCOPE USER /R 2>&1
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
            Write-Host "[WARN] gpresult returned exit code $LASTEXITCODE" -ForegroundColor Yellow
        }

        $applied = @()
        $denied  = @()
        $inApplied = $false
        $inDenied  = $false
        $order = 1

        foreach ($line in $output) {
            if ($line -match "Applied Group Policy Objects") { $inApplied = $true; $inDenied = $false; continue }
            if ($line -match "The following GPOs were not applied") { $inDenied = $true; $inApplied = $false; continue }
            if ($line -match "^\s*$" -and ($inApplied -or $inDenied)) { continue }
            if ($line -match "^(COMPUTER SETTINGS|USER SETTINGS|Resultant Set)") { $inApplied = $false; $inDenied = $false }

            if ($inApplied -and $line -match "^\s+(.+)$") {
                $name = $Matches[1].Trim()
                if ($name -ne "" -and $name -notmatch "^-+$") {
                    $applied += [PSCustomObject]@{ Order = $order++; Name = $name; Scope = "User" }
                }
            }

            if ($inDenied -and $line -match "^\s+(.+)$") {
                $name = $Matches[1].Trim()
                if ($name -ne "" -and $name -notmatch "^-+$") {
                    $denied += [PSCustomObject]@{ Name = $name; Scope = "User"; Reason = "Filtered" }
                }
            }
        }

        return @{
            Username     = $Username
            AppliedGPOs  = $applied
            DeniedGPOs   = $denied
            LoopbackMode = "None"
            Source       = "gpresult"
        }
    }
    catch {
        Write-Host "[ERROR] gpresult fallback failed: $_" -ForegroundColor Red
        return $null
    }
}

function Show-GPOTable {
    param([hashtable]$Data)
    $line = ("=" * 72)

    Write-Host ""
    Write-Host $line -ForegroundColor DarkCyan
    Write-Host " GPO RESULTANT SET — $($Data.Username.ToUpper())  [via $($Data.Source)]" -ForegroundColor White
    Write-Host $line -ForegroundColor DarkCyan

    if ($Data.LoopbackMode -and $Data.LoopbackMode -ne "None") {
        Write-Host "  Loopback Mode: $($Data.LoopbackMode)" -ForegroundColor Magenta
        Write-Host ""
    }

    Write-Host "  APPLIED POLICIES" -ForegroundColor Green
    Write-Host ("-" * 72) -ForegroundColor DarkGray
    if ($Data.AppliedGPOs.Count -eq 0) {
        Write-Host "  (none)" -ForegroundColor Gray
    } else {
        Write-Host ("  {0,-4} {1,-45} {2}" -f "#", "Policy Name", "Scope") -ForegroundColor Gray
        foreach ($gpo in $Data.AppliedGPOs) {
            Write-Host ("  {0,-4} {1,-45} {2}" -f $gpo.Order, $gpo.Name, $gpo.Scope)
        }
    }

    Write-Host ""
    Write-Host "  DENIED / FILTERED POLICIES" -ForegroundColor Red
    Write-Host ("-" * 72) -ForegroundColor DarkGray
    if ($Data.DeniedGPOs.Count -eq 0) {
        Write-Host "  (none)" -ForegroundColor Gray
    } else {
        Write-Host ("  {0,-45} {1,-12} {2}" -f "Policy Name", "Scope", "Reason") -ForegroundColor Gray
        foreach ($gpo in $Data.DeniedGPOs) {
            Write-Host ("  {0,-45} {1,-12} {2}" -f $gpo.Name, $gpo.Scope, $gpo.Reason) -ForegroundColor Yellow
        }
    }

    Write-Host $line -ForegroundColor DarkCyan
    Write-Host ""
}

function Prompt-GPOHTMLExport {
    param([hashtable]$Data, [string]$Username)
    $choice = Read-Host "Export to HTML report? [Y/N]"
    if ($choice -match "^[Yy]") {
        $path = Export-HTMLReport -Data $Data -ReportType "GPOReport" -Username $Username -Source "LocalAD"
        Write-Host "[OK] Report saved: $path" -ForegroundColor Green
    }
}
```

- [ ] **Step 2: Verify syntax**

```powershell
pwsh -NoProfile -Command "
  \$errors = \$null
  \$null = [System.Management.Automation.Language.Parser]::ParseFile(
    '/project/ADUser/Modules/Get-UserGPO.ps1', [ref]\$null, [ref]\$errors
  )
  if (\$errors.Count -gt 0) { \$errors | ForEach-Object { Write-Host \$_.Message -ForegroundColor Red }; exit 1 }
  Write-Host 'Syntax OK' -ForegroundColor Green
"
```
Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add Modules/Get-UserGPO.ps1
git commit -m "feat: add Get-UserGPO module with GPMC and gpresult fallback"
```

---

## Task 6: ADInsight.ps1 — Main Launcher

**Files:**
- Create: `ADInsight.ps1`

- [ ] **Step 1: Create ADInsight.ps1**

```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    ADInsight — Active Directory & Entra ID User Management Tool
.DESCRIPTION
    Search users, compare users, and pull GPO attributes from Local AD or Entra ID.
    Written by Dallas Milem
.NOTES
    Version: 1.0
    Author:  Dallas Milem
#>

# Dot-source all modules
$modulePath = Join-Path $PSScriptRoot "Modules"
. (Join-Path $modulePath "Connect-Source.ps1")
. (Join-Path $modulePath "Export-HTML.ps1")
. (Join-Path $modulePath "Search-User.ps1")
. (Join-Path $modulePath "Compare-Users.ps1")
. (Join-Path $modulePath "Get-UserGPO.ps1")

function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║              ADInsight  v1.0                             ║" -ForegroundColor Cyan
    Write-Host "  ║         Written by Dallas Milem                         ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Select-Source {
    Write-Host "  Select data source:" -ForegroundColor White
    Write-Host "    [L]  Local AD Domain Controller"
    Write-Host "    [E]  Entra ID (Azure AD)"
    Write-Host ""
    $choice = Read-Host "  Choice"

    switch ($choice.ToUpper()) {
        "L" { return Connect-LocalAD }
        "E" { return Connect-EntraID }
        default {
            Write-Host "  [ERROR] Invalid choice. Enter L or E." -ForegroundColor Red
            return $false
        }
    }
}

function Show-Menu {
    $source = Get-ADSource
    Write-Host ""
    Write-Host "  ──────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ("  Active Source: {0}" -f $(if ($source) { $source } else { "None" })) -ForegroundColor $(if ($source) { "Green" } else { "Red" })
    Write-Host "  ──────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    [1]  Search User"
    Write-Host "    [2]  Compare Two Users"
    if ($source -eq "Entra") {
        Write-Host "    [3]  Get GPO Attributes  " -NoNewline
        Write-Host "(Local AD only — unavailable)" -ForegroundColor DarkGray
    } else {
        Write-Host "    [3]  Get GPO Attributes"
    }
    Write-Host "    [4]  Change Source"
    Write-Host "    [5]  Exit"
    Write-Host ""
}

# ── Main loop ─────────────────────────────────────────────────────────────────
Show-Banner

# Initial source selection
$connected = $false
while (-not $connected) {
    $connected = Select-Source
    if (-not $connected) {
        Write-Host "  Connection failed. Try again." -ForegroundColor Yellow
        Write-Host ""
    }
}

# Menu loop
$running = $true
while ($running) {
    Show-Menu
    $choice = Read-Host "  Select option"

    switch ($choice) {
        "1" { Invoke-UserSearch }
        "2" { Invoke-UserComparison }
        "3" {
            if ((Get-ADSource) -eq "Entra") {
                Write-Host "  [INFO] GPO reporting is only available with Local AD." -ForegroundColor Yellow
            } else {
                Invoke-UserGPOReport
            }
        }
        "4" {
            Show-Banner
            $connected = $false
            while (-not $connected) {
                $connected = Select-Source
                if (-not $connected) {
                    Write-Host "  Connection failed. Try again." -ForegroundColor Yellow
                    Write-Host ""
                }
            }
        }
        "5" {
            Write-Host "`n  Goodbye.`n" -ForegroundColor Cyan
            $running = $false
        }
        default {
            Write-Host "  [ERROR] Invalid option. Enter 1-5." -ForegroundColor Red
        }
    }
}
```

- [ ] **Step 2: Verify syntax**

```powershell
pwsh -NoProfile -Command "
  \$errors = \$null
  \$null = [System.Management.Automation.Language.Parser]::ParseFile(
    '/project/ADUser/ADInsight.ps1', [ref]\$null, [ref]\$errors
  )
  if (\$errors.Count -gt 0) { \$errors | ForEach-Object { Write-Host \$_.Message -ForegroundColor Red }; exit 1 }
  Write-Host 'Syntax OK' -ForegroundColor Green
"
```
Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add ADInsight.ps1
git commit -m "feat: add ADInsight main launcher with menu and source selection"
```

---

## Task 7: Final Integration — Syntax Check All Files and Push

- [ ] **Step 1: Verify all files parse cleanly**

```powershell
pwsh -NoProfile -Command "
  \$files = @(
    '/project/ADUser/ADInsight.ps1',
    '/project/ADUser/Modules/Connect-Source.ps1',
    '/project/ADUser/Modules/Export-HTML.ps1',
    '/project/ADUser/Modules/Search-User.ps1',
    '/project/ADUser/Modules/Compare-Users.ps1',
    '/project/ADUser/Modules/Get-UserGPO.ps1'
  )
  \$allOk = \$true
  foreach (\$f in \$files) {
    \$errors = \$null
    \$null = [System.Management.Automation.Language.Parser]::ParseFile(\$f, [ref]\$null, [ref]\$errors)
    if (\$errors.Count -gt 0) {
      Write-Host \"FAIL: \$f\" -ForegroundColor Red
      \$errors | ForEach-Object { Write-Host \"  \$(\$_.Message)\" -ForegroundColor Red }
      \$allOk = \$false
    } else {
      Write-Host \"OK:   \$f\" -ForegroundColor Green
    }
  }
  if (-not \$allOk) { exit 1 }
"
```
Expected: all six lines `OK`.

- [ ] **Step 2: Push to GitHub**

```bash
git push origin main
```

Expected: `main -> main` with no errors.
