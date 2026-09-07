#requires -Version 5.1
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'ExchangeMigration.Common.psm1')

function ConvertTo-EMTBytes {
    [CmdletBinding()]
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [long] -or $Value -is [int]) { return [long]$Value }
    if ($null -ne $Value.PSObject.Methods['ToBytes']) { return [long]$Value.ToBytes() }
    # Remoting removes ByteQuantifiedSize methods. Only parse the exact byte count
    # in parentheses; never guess from rounded GB/MB display values.
    if ([string]$Value -match '\(([\d\s,\.\u00A0\u202F]+)\s+[^)]+\)') {
        $digits = $Matches[1] -replace '\D',''
        $bytes = 0L
        if ([long]::TryParse($digits, [ref]$bytes)) { return $bytes }
    }
    return $null
}

function Get-EMTMailboxRow {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Mailbox, [string]$TargetDatabase, [string]$ArchiveTargetDatabase)
    $errors = [Collections.Generic.List[string]]::new()
    $id = [string](Get-EMTProperty $Mailbox ExchangeGuid)
    $stats = $null; $archiveStats = $null
    try { $stats = Invoke-EMTCommand Get-MailboxStatistics @{ Identity = $id } }
    catch { $errors.Add('PrimaryStatisticsUnavailable') }
    $archiveDb = [string](Get-EMTProperty $Mailbox ArchiveDatabase)
    $archiveGuid = [string](Get-EMTProperty $Mailbox ArchiveGuid)
    $hasArchive = -not [string]::IsNullOrWhiteSpace($archiveGuid) -and $archiveGuid -ne [guid]::Empty.ToString()
    $remoteArchive = [string](Get-EMTProperty $Mailbox RemoteRecipientType) -match 'Archive' -and -not $archiveDb
    if ($hasArchive -and $archiveDb) {
        try { $archiveStats = Invoke-EMTCommand Get-MailboxStatistics @{ Identity = $id; Archive = $true } }
        catch { $errors.Add('ArchiveStatisticsUnavailable') }
    } elseif ($hasArchive -or $remoteArchive) { $errors.Add('NonLocalArchiveRequiresReview') }
    $primaryBytes = ConvertTo-EMTBytes (Get-EMTProperty $stats TotalItemSize)
    $archiveBytes = if ($hasArchive -or $remoteArchive) { ConvertTo-EMTBytes (Get-EMTProperty $archiveStats TotalItemSize) } else { 0L }
    if ($null -eq $primaryBytes) { $errors.Add('PrimarySizeUnknown') }
    if ($null -eq $archiveBytes) { $errors.Add('ArchiveSizeUnknown') }
    $totalBytes = if ($null -ne $primaryBytes -and $null -ne $archiveBytes) { $primaryBytes + $archiveBytes } else { $null }
    [pscustomobject][ordered]@{
        DisplayName = Get-EMTProperty $Mailbox DisplayName
        PrimarySmtpAddress = [string](Get-EMTProperty $Mailbox PrimarySmtpAddress)
        Identity = $id; MailboxType = [string](Get-EMTProperty $Mailbox RecipientTypeDetails)
        PrimaryDatabase = [string](Get-EMTProperty $Mailbox Database)
        PrimaryServer = [string](Get-EMTProperty $stats ServerName)
        PrimarySize = [string](Get-EMTProperty $stats TotalItemSize)
        PrimaryBytes = $primaryBytes; PrimaryItemCount = Get-EMTProperty $stats ItemCount
        PrimaryDeletedItemSize = [string](Get-EMTProperty $stats TotalDeletedItemSize)
        ArchiveEnabled = ($hasArchive -or $remoteArchive)
        ArchiveStatus = [string](Get-EMTProperty $Mailbox ArchiveStatus)
        ArchiveDatabase = $archiveDb; ArchiveServer = [string](Get-EMTProperty $archiveStats ServerName)
        ArchiveSize = [string](Get-EMTProperty $archiveStats TotalItemSize)
        ArchiveBytes = $archiveBytes; ArchiveItemCount = Get-EMTProperty $archiveStats ItemCount
        ArchiveDeletedItemSize = [string](Get-EMTProperty $archiveStats TotalDeletedItemSize)
        TotalBytes = $totalBytes
        UseDatabaseQuotaDefaults = Get-EMTProperty $Mailbox UseDatabaseQuotaDefaults
        IssueWarningQuota = [string](Get-EMTProperty $Mailbox IssueWarningQuota)
        ProhibitSendQuota = [string](Get-EMTProperty $Mailbox ProhibitSendQuota)
        ProhibitSendReceiveQuota = [string](Get-EMTProperty $Mailbox ProhibitSendReceiveQuota)
        ArchiveQuota = [string](Get-EMTProperty $Mailbox ArchiveQuota)
        ArchiveWarningQuota = [string](Get-EMTProperty $Mailbox ArchiveWarningQuota)
        TargetDatabase = $TargetDatabase; ArchiveTargetDatabase = $ArchiveTargetDatabase
        MigrationAction = 'Review'; CollectionStatus = $(if ($errors.Count) { 'WARN' } else { 'PASS' })
        CollectionNotes = $errors -join '; '
    }
}

function Get-EMTPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Identity, [Parameter(Mandatory)][string]$TargetDatabase,
        [string]$ArchiveTargetDatabase, [ValidateSet('Primary','Archive','Both')][string]$Mode = 'Primary')
    # A failed query is never treated as an empty move-request list.
    $requests = @(Invoke-EMTCommand Get-MoveRequest @{ ResultSize = 'Unlimited' })
    $target = Invoke-EMTCommand Get-MailboxDatabase @{ Identity = $TargetDatabase; Status = $true }
    if ((Get-EMTProperty $target Mounted) -ne $true) { throw 'Primary target database is not mounted or its state is unknown.' }
    $archiveTarget = $null
    if ($Mode -ne 'Primary') {
        if ([string]::IsNullOrWhiteSpace($ArchiveTargetDatabase)) { throw 'ArchiveTargetDatabase is required for Archive/Both.' }
        $archiveTarget = Invoke-EMTCommand Get-MailboxDatabase @{ Identity = $ArchiveTargetDatabase; Status = $true }
        if ((Get-EMTProperty $archiveTarget Mounted) -ne $true) { throw 'Archive target database is not mounted or its state is unknown.' }
    }
    $seen = @{}
    foreach ($id in $Identity) {
        $mailboxes = @(Invoke-EMTCommand Get-Mailbox @{ Identity = $id })
        if ($mailboxes.Count -ne 1) { throw 'Each identity must resolve to exactly one mailbox.' }
        $mailbox = $mailboxes[0]
        $row = Get-EMTMailboxRow $mailbox ([string]$target.Name) ([string](Get-EMTProperty $archiveTarget Name))
        if ([string]::IsNullOrWhiteSpace($row.Identity) -or $row.Identity -eq [guid]::Empty.ToString()) { throw 'Mailbox ExchangeGuid is unavailable.' }
        if ($seen.ContainsKey($row.Identity)) { continue }
        $seen[$row.Identity] = $true
        $reason = ''; $action = 'Review'; $payload = $null
        $source = Invoke-EMTCommand Get-MailboxDatabase @{ Identity = $row.PrimaryDatabase }
        $primarySame = [string]$source.Guid -eq [string]$target.Guid
        $archiveSame = $false
        if ($Mode -ne 'Primary' -and $row.ArchiveDatabase) {
            $archiveSource = Invoke-EMTCommand Get-MailboxDatabase @{ Identity = $row.ArchiveDatabase }
            $archiveSame = [string]$archiveSource.Guid -eq [string]$archiveTarget.Guid
        }
        $existing = @($requests | Where-Object {
            [string](Get-EMTProperty $_ ExchangeGuid) -eq $row.Identity -or
            [string](Get-EMTProperty $_ Identity) -eq [string](Get-EMTProperty $mailbox Identity)
        })
        if ($row.MailboxType -notin @('UserMailbox','SharedMailbox','RoomMailbox','EquipmentMailbox')) { $reason = 'Unsupported mailbox type.' }
        elseif ($existing.Count) { $reason = 'Existing move request; review and explicitly manage it first.' }
        elseif ($null -eq $row.PrimaryBytes -and $Mode -ne 'Archive') { $reason = 'Primary statistics or exact byte count unavailable.' }
        elseif ($Mode -ne 'Primary' -and (-not $row.ArchiveDatabase -or $null -eq $row.ArchiveBytes)) { $reason = 'A readable local archive is required.' }
        elseif ($Mode -eq 'Primary' -and $primarySame) { $action = 'No Migration'; $payload = 0L }
        elseif ($Mode -eq 'Archive' -and $archiveSame) { $action = 'No Migration'; $payload = 0L }
        elseif ($Mode -eq 'Both' -and ($primarySame -or $archiveSame)) { $reason = 'One or both components already on target; select Primary or Archive explicitly.' }
        else {
            switch ($Mode) {
                Primary { $action = 'Move Primary'; $payload = $row.PrimaryBytes }
                Archive { $action = 'Move Archive Only'; $payload = $row.ArchiveBytes }
                Both { $action = 'Move Primary + Archive'; $payload = $row.PrimaryBytes + $row.ArchiveBytes }
            }
        }
        $row.MigrationAction = $action
        $row | Add-Member NoteProperty PlanReason $reason
        $row | Add-Member NoteProperty EstimatedPayloadBytes $payload
        $row | Add-Member NoteProperty PlanMode $Mode
        $row
    }
}
Export-ModuleMember -Function *-EMT*
