#requires -Version 5.1
<#
.SYNOPSIS
Combine explicitly selected CSV reports into one escaped, standalone customer HTML report.
.DESCRIPTION
Does not scan directories or embed external HTML/scripts. HealthChecker summary is
operator-supplied text, clearly labelled as such; attach original HealthChecker evidence.
.PARAMETER CsvPath
Exact CSV files from the same change window. Review timestamps and scope before selection.
.EXAMPLE
.\src\New-ExchangeMigrationReport.ps1 -ConfigPath .\config\local.config.psd1 -CsvPath $reportFiles -HealthCheckerSummary 'Reviewed by technician; see attached HealthChecker report.'
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]]$CsvPath,
    [string]$EnvironmentLabel = 'Exchange migration',
    [string]$HealthCheckerSummary = 'Not supplied; server health is not verified.')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common/ExchangeMigration.Common.psm1')
$config = Read-EMTConfig $ConfigPath
$parts = [Collections.Generic.List[string]]::new()
$parts.Add('<!doctype html><html lang="en"><meta charset="utf-8"><title>Exchange Migration Report</title><style>body{font-family:Arial;margin:2rem}table{border-collapse:collapse;font-size:12px}td,th{border:1px solid #ccc;padding:6px}th{background:#e8edf4}section{overflow:auto;margin-bottom:2rem}</style><body><h1>Exchange Migration Report</h1>')
$parts.Add('<p>Environment: ' + [Net.WebUtility]::HtmlEncode($EnvironmentLabel) + '</p>')
$parts.Add('<p>Generated UTC: ' + [datetime]::UtcNow.ToString('o') + '</p>')
$parts.Add('<h2>HealthChecker — operator summary</h2><p>' + [Net.WebUtility]::HtmlEncode($HealthCheckerSummary) + '</p>')
$warnings = 0; $failures = 0
foreach ($path in $CsvPath) {
    if ([IO.Path]::GetExtension($path) -ne '.csv') { throw 'Only CSV reports are accepted.' }
    $rows = @(Import-Csv -LiteralPath $path -Encoding UTF8 -ErrorAction Stop)
    $parts.Add('<section><h2>' + [Net.WebUtility]::HtmlEncode([IO.Path]::GetFileName($path)) + '</h2><table>')
    if ($rows.Count) {
        $parts.Add('<tr>')
        foreach ($p in $rows[0].PSObject.Properties) { $parts.Add('<th>' + [Net.WebUtility]::HtmlEncode($p.Name) + '</th>') }
        $parts.Add('</tr>')
        foreach ($row in $rows) {
            if ((Get-EMTProperty $row Status) -eq 'WARN' -or (Get-EMTProperty $row CollectionStatus) -eq 'WARN' -or (Get-EMTProperty $row MigrationAction) -eq 'Review') { $warnings++ }
            if ((Get-EMTProperty $row Status) -eq 'FAIL') { $failures++ }
            $parts.Add('<tr>')
            foreach ($p in $row.PSObject.Properties) { $parts.Add('<td>' + [Net.WebUtility]::HtmlEncode([string]$p.Value) + '</td>') }
            $parts.Add('</tr>')
        }
    }
    $parts.Add('</table></section>')
}
$parts.Add("<h2>Warnings and failures</h2><p>Warning/review rows: $warnings. FAIL rows: $failures. Counts cover selected CSV files only; they exclude unstructured HealthChecker findings and do not constitute approval.</p></body></html>")
$null = New-Item -ItemType Directory -Path $config.OutputPath -Force
$output = Join-Path $config.OutputPath ('ExchangeMigrationReport-' + [guid]::NewGuid().ToString('N') + '.html')
Set-Content -LiteralPath $output -Value ($parts -join "`n") -Encoding UTF8
Write-EMTLog $config -Event CUSTOMER_REPORT_CREATED
$output
