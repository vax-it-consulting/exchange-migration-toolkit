#requires -Version 5.1
Set-StrictMode -Version Latest

function Get-EMTProperty {
    [CmdletBinding()]
    param([AllowNull()][object]$InputObject, [Parameter(Mandatory)][string]$Name, $Default = $null)
    if ($null -eq $InputObject) { return $Default }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Read-EMTConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Path)
    $config = Import-PowerShellDataFile -LiteralPath $Path -ErrorAction Stop
    $required = @('SourceExchangeServers','TargetExchangeServers','SourceDatabases',
        'TargetDatabase','ArchiveTargetDatabase','PrimaryNamespace','AutodiscoverNamespace',
        'AcceptedDomains','OutputPath','LogPath','DiskSpaceThreshold',
        'CertificateExpiryWarningDays','WarningThresholds','ReachabilityPorts','EnableMailFlowTest')
    foreach ($key in $required) {
        if (-not $config.ContainsKey($key)) { throw "Required configuration key missing: $key" }
    }
    foreach ($key in @('SourceExchangeServers','TargetExchangeServers','SourceDatabases','AcceptedDomains')) {
        if ($config[$key] -isnot [array] -or @($config[$key]).Count -eq 0) { throw "$key must be a nonempty array." }
        foreach ($value in $config[$key]) {
            if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)) { throw "$key contains an invalid value." }
        }
    }
    foreach ($key in @('TargetDatabase','PrimaryNamespace','AutodiscoverNamespace','OutputPath','LogPath')) {
        if ($config[$key] -isnot [string] -or [string]::IsNullOrWhiteSpace($config[$key])) { throw "$key must be a nonempty string." }
    }
    if ($config.ArchiveTargetDatabase -isnot [string]) { throw 'ArchiveTargetDatabase must be a string (empty is allowed).' }
    foreach ($key in @('DiskSpaceThreshold','CertificateExpiryWarningDays')) {
        if ($config[$key] -isnot [int] -or $config[$key] -lt 1) { throw "$key must be a positive integer." }
    }
    if ($config.DiskSpaceThreshold -gt 100) { throw 'DiskSpaceThreshold must be 1..100.' }
    if ($config.WarningThresholds -isnot [hashtable]) { throw 'WarningThresholds must be a hashtable.' }
    foreach ($key in @('QueueMessageCount','EventLookbackHours','EventMaxEvents')) {
        if (-not $config.WarningThresholds.ContainsKey($key) -or $config.WarningThresholds[$key] -isnot [int] -or $config.WarningThresholds[$key] -lt 1) {
            throw "WarningThresholds.$key must be a positive integer."
        }
    }
    if ($config.EnableMailFlowTest -isnot [bool]) { throw 'EnableMailFlowTest must be boolean.' }
    if ($config.ReachabilityPorts -isnot [array] -or $config.ReachabilityPorts.Count -eq 0) { throw 'ReachabilityPorts must be a nonempty array.' }
    foreach ($port in $config.ReachabilityPorts) {
        if ($port -isnot [int] -or $port -lt 1 -or $port -gt 65535) { throw 'Invalid TCP port.' }
    }
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    foreach ($key in @('OutputPath','LogPath')) {
        if (-not [IO.Path]::IsPathRooted($config[$key])) { $config[$key] = Join-Path $repoRoot $config[$key] }
        $config[$key] = [IO.Path]::GetFullPath($config[$key])
    }
    return $config
}

function Invoke-EMTCommand {
    <# .SYNOPSIS
    Single boundary for Exchange/Windows dependencies; unit tests mock this function.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Command, [hashtable]$Parameters = @{})
    $null = Get-Command -Name $Command -ErrorAction Stop
    $arguments = @{} + $Parameters
    $arguments.ErrorAction = 'Stop'
    & $Command @arguments
}

function Write-EMTLog {
    <# .SYNOPSIS
    Writes only fixed event codes and counters; never raw mailbox or exception text.
    #>
    [CmdletBinding()]
    param([hashtable]$Config, [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO',
        [ValidatePattern('^[A-Z0-9_]+$')][string]$Event, [int]$Count = 0)
    $null = New-Item -ItemType Directory -Path $Config.LogPath -Force -ErrorAction Stop
    $line = '{0} {1} {2} count={3}' -f [datetime]::UtcNow.ToString('o'), $Level, $Event, $Count
    Add-Content -LiteralPath (Join-Path $Config.LogPath 'toolkit.log') -Value $line -Encoding UTF8 -ErrorAction Stop
}

function New-EMTResult {
    [CmdletBinding()]
    param([string]$Check, [string]$Target, [ValidateSet('PASS','WARN','FAIL','INFO')][string]$Status,
        [string]$Detail, [string]$Recommendation = '')
    $severities = @{ PASS = 'None'; INFO = 'Informational'; WARN = 'Medium'; FAIL = 'High' }
    [pscustomobject][ordered]@{
        TimestampUtc = [datetime]::UtcNow.ToString('o'); Check = $Check; Target = $Target
        Status = $Status; Severity = $severities[$Status]; Detail = $Detail; Recommendation = $Recommendation
    }
}

function ConvertTo-EMTSafeCell {
    [CmdletBinding()]
    param([AllowNull()]$Value)
    $text = if ($null -eq $Value) { '' } elseif ($Value -is [array]) { ($Value | ForEach-Object { [string]$_ }) -join '; ' } else { [string]$Value }
    # Neutralize formula-like cells, including leading whitespace/control characters.
    if ($text -match '^\s*[=+@-]' -or $text -match '^[\t\r\n]') { return "'$text" }
    return $text
}

function Export-EMTReport {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory)][hashtable]$Config, [ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Name,
        [switch]$Html)
    $null = New-Item -ItemType Directory -Path $Config.OutputPath -Force -ErrorAction Stop
    $stem = '{0}-{1}-{2}' -f $Name, [datetime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'), ([guid]::NewGuid().ToString('N').Substring(0,8))
    $csvPath = Join-Path $Config.OutputPath "$stem.csv"
    $safe = @(foreach ($row in $Rows) {
        $record = [ordered]@{}
        foreach ($p in $row.PSObject.Properties) { $record[$p.Name] = ConvertTo-EMTSafeCell $p.Value }
        [pscustomobject]$record
    })
    if ($safe.Count -gt 0) { $safe | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop }
    else { Set-Content -LiteralPath $csvPath -Value '"Information"' -Encoding UTF8 -ErrorAction Stop }
    if ($Html) {
        $htmlPath = Join-Path $Config.OutputPath "$stem.html"
        $parts = [Collections.Generic.List[string]]::new()
        $parts.Add('<!doctype html><html lang="en"><meta charset="utf-8"><title>Exchange report</title><body><h1>Exchange report</h1><table border="1">')
        if ($Rows.Count -gt 0) {
            $parts.Add('<tr>')
            foreach ($p in $Rows[0].PSObject.Properties) { $parts.Add('<th>' + [Net.WebUtility]::HtmlEncode($p.Name) + '</th>') }
            $parts.Add('</tr>')
            foreach ($row in $Rows) {
                $parts.Add('<tr>')
                foreach ($p in $row.PSObject.Properties) { $parts.Add('<td>' + [Net.WebUtility]::HtmlEncode([string]$p.Value) + '</td>') }
                $parts.Add('</tr>')
            }
        }
        $parts.Add('</table></body></html>')
        Set-Content -LiteralPath $htmlPath -Value ($parts -join "`n") -Encoding UTF8 -ErrorAction Stop
        Write-Verbose "HTML report: $htmlPath"
    }
    Write-Verbose "CSV report: $csvPath"
    Write-EMTLog -Config $Config -Event REPORT_EXPORTED -Count $Rows.Count
}

function Resolve-EMTMailboxList {
    [CmdletBinding()]
    param([string[]]$Identity, [string]$CsvPath)
    if ($Identity -and $CsvPath) { throw 'Choose Identity or CsvPath, not both.' }
    $items = @($Identity)
    if ($CsvPath) {
        $rows = @(Import-Csv -LiteralPath $CsvPath -Encoding UTF8 -ErrorAction Stop)
        if ($rows.Count -eq 0 -or $null -eq $rows[0].PSObject.Properties['Identity']) { throw 'CSV requires an Identity header and at least one row.' }
        $items = @($rows | ForEach-Object { $_.Identity })
    }
    if ($items.Count -eq 0) { throw 'Explicit mailbox identities are required.' }
    $seen = @{}
    foreach ($item in $items) {
        if ([string]::IsNullOrWhiteSpace($item)) { throw 'Empty mailbox identity is not permitted.' }
        $id = $item.Trim()
        if ($id -match '[*?\[\]\r\n]') { throw 'Wildcards and multiline identities are not permitted.' }
        if (-not $seen.ContainsKey($id)) { $seen[$id] = $true; $id }
    }
}

function Get-EMTExitCode {
    [CmdletBinding()]
    param([object[]]$Results)
    if (@($Results | Where-Object Status -eq 'FAIL').Count -gt 0) { return 2 }
    if (@($Results | Where-Object Status -eq 'WARN').Count -gt 0) { return 1 }
    return 0
}

Export-ModuleMember -Function *-EMT*
