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
    Write-Host "  +============================================================+" -ForegroundColor Cyan
    Write-Host "  |              ADInsight  v1.0                               |" -ForegroundColor Cyan
    Write-Host "  |         Written by Dallas Milem                           |" -ForegroundColor Cyan
    Write-Host "  +============================================================+" -ForegroundColor Cyan
    Write-Host ""
}

function Confirm-RunAsCurrentUser {
    $currentUser = "$env:USERDOMAIN\$env:USERNAME"
    Write-Host "  Detected current user: " -NoNewline
    Write-Host $currentUser -ForegroundColor Yellow
    Write-Host ""

    $deadline  = (Get-Date).AddSeconds(30)
    $answered  = $false
    $useCurrentUser = $true

    while ((Get-Date) -lt $deadline -and -not $answered) {
        $remaining = [math]::Ceiling(($deadline - (Get-Date)).TotalSeconds)
        Write-Host "`r  Run as current user? [Y/N]  (auto-yes in ${remaining}s)  " -NoNewline

        if ($Host.UI.RawUI.KeyAvailable) {
            $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            if ($key.Character -in @('Y','y')) {
                $useCurrentUser = $true
                $answered = $true
            } elseif ($key.Character -in @('N','n')) {
                $useCurrentUser = $false
                $answered = $true
            }
        }
        Start-Sleep -Milliseconds 200
    }

    Write-Host ""

    if ($useCurrentUser) {
        Write-Host "  Connecting as $currentUser..." -ForegroundColor Cyan
        # ActiveDirectory module uses current session credentials by default
        if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
            Write-Host "  [ERROR] ActiveDirectory module not found." -ForegroundColor Red
            Write-Host "  Install RSAT: Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0" -ForegroundColor Yellow
            return $false
        }
        Import-Module ActiveDirectory -ErrorAction SilentlyContinue
        try {
            $dc = Get-ADDomainController -Discover -ErrorAction Stop
            Write-Host "  [OK] Connected to domain: $($dc.Domain) via $($dc.HostName)" -ForegroundColor Green
            $script:ADSource = "LocalAD"
            return $true
        } catch {
            Write-Host "  [ERROR] Cannot reach a domain controller: $_" -ForegroundColor Red
            Write-Host "  Falling through to manual source selection..." -ForegroundColor Yellow
            return $false
        }
    }

    return $false
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
    Write-Host "  ----------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ("  Active Source: {0}" -f $(if ($source) { $source } else { "None" })) -ForegroundColor $(if ($source) { "Green" } else { "Red" })
    Write-Host "  ----------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    [1]  Search User"
    Write-Host "    [2]  Compare Two Users"
    if ($source -eq "Entra") {
        Write-Host "    [3]  Get GPO Attributes  " -NoNewline
        Write-Host "(Local AD only -- unavailable)" -ForegroundColor DarkGray
    } else {
        Write-Host "    [3]  Get GPO Attributes"
    }
    Write-Host "    [4]  Change Source"
    Write-Host "    [5]  Exit"
    Write-Host ""
}

# ── Main loop ─────────────────────────────────────────────────────────────────
Show-Banner

# Offer current-user fast path; fall through to manual selection if declined or fails
$connected = Confirm-RunAsCurrentUser

if (-not $connected) {
    Write-Host ""
    while (-not $connected) {
        $connected = Select-Source
        if (-not $connected) {
            Write-Host "  Connection failed. Try again." -ForegroundColor Yellow
            Write-Host ""
        }
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
