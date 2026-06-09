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
  .badge-diff    { background: #e74c3c; color: #fff; border-radius: 3px;
                   padding: 1px 6px; font-size: 0.75em; margin-left: 6px; }
  .badge-applied { background: #27ae60; color: #fff; border-radius: 3px; padding: 1px 6px; font-size: 0.75em; }
  .badge-denied  { background: #e74c3c; color: #fff; border-radius: 3px; padding: 1px 6px; font-size: 0.75em; }
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
    $u1 = [System.Web.HttpUtility]::HtmlEncode($Data.User1Name)
    $u2 = [System.Web.HttpUtility]::HtmlEncode($Data.User2Name)
    $rows = ""
    foreach ($row in $Data.Rows) {
        $cssClass = if ($row.IsDiff) { "diff" } else { "same" }
        $badge    = if ($row.IsDiff) { '<span class="badge-diff">DIFF</span>' } else { "" }
        $v1class  = if ($row.IsDiff) { ' class="val1"' } else { "" }
        $v2class  = if ($row.IsDiff) { ' class="val2"' } else { "" }
        $v1 = if ([string]::IsNullOrEmpty($row.Val1)) { "<em>N/A</em>" } else { [System.Web.HttpUtility]::HtmlEncode($row.Val1.ToString()) }
        $v2 = if ([string]::IsNullOrEmpty($row.Val2)) { "<em>N/A</em>" } else { [System.Web.HttpUtility]::HtmlEncode($row.Val2.ToString()) }
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
