#requires -Version 5.1
<#
.SYNOPSIS
Collect mailbox primary/archive data and selected Exchange configuration.
.DESCRIPTION
Read-only Exchange calls; reports contain sensitive metadata. Collection failures
are written as separate WARN rows, never silently treated as empty collections.
.PARAMETER ConfigPath
Path to a PowerShell data configuration file.
.PARAMETER IncludeDisconnected
Also query disconnected mailbox statistics for configured databases.
.PARAMETER Html
Export HTML alongside CSV.
.EXAMPLE
.\src\Get-ExchangeInventory.ps1 -ConfigPath .\config\local.config.psd1 -IncludeDisconnected -Html
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ConfigPath, [switch]$IncludeDisconnected, [switch]$Html)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common/ExchangeMigration.Common.psm1')
Import-Module (Join-Path $PSScriptRoot 'Common/ExchangeMigration.Data.psm1')
$config = Read-EMTConfig $ConfigPath
Write-EMTLog $config -Event INVENTORY_STARTED
$collection = [Collections.Generic.List[object]]::new()
function Export-Collection {
    param([string]$Name, [scriptblock]$Query)
    try {
        $data = @(& $Query)
        Export-EMTReport $data $config $Name -Html:$Html
        $collection.Add((New-EMTResult $Name 'Environment' INFO "$($data.Count) records collected; review exported values."))
    } catch {
        $collection.Add((New-EMTResult $Name 'Environment' WARN "Collection failed ($($_.Exception.GetType().Name))." 'Verify cmdlet availability and RBAC; rerun this collection.'))
    }
}
try {
    $mailboxes = @(Invoke-EMTCommand Get-Mailbox @{ ResultSize = 'Unlimited'; RecipientTypeDetails = @('UserMailbox','SharedMailbox','RoomMailbox','EquipmentMailbox') })
    $rows = @(foreach ($mailbox in $mailboxes) { Get-EMTMailboxRow $mailbox $config.TargetDatabase $config.ArchiveTargetDatabase })
    Export-EMTReport $rows $config 'MailboxInventory' -Html:$Html
    $collection.Add((New-EMTResult 'MailboxInventory' 'Organization' INFO "$($rows.Count) local user/shared/resource mailboxes collected."))
    foreach ($row in $rows | Where-Object CollectionStatus -eq 'WARN') {
        $collection.Add((New-EMTResult 'MailboxStatistics' $row.Identity WARN $row.CollectionNotes 'Resolve unreadable or remote archive data before planning.'))
    }
} catch {
    Write-EMTLog $config -Level ERROR -Event INVENTORY_FAILED
    throw
}
$servers = @(@($config.SourceExchangeServers) + @($config.TargetExchangeServers) | Select-Object -Unique)
$dbNames = @(@($config.SourceDatabases) + @($config.TargetDatabase) + @($config.ArchiveTargetDatabase) | Where-Object { $_ } | Select-Object -Unique)
Export-Collection 'Servers' {
    foreach ($server in $servers) { Invoke-EMTCommand Get-ExchangeServer @{ Identity = $server } | Select-Object Name,Fqdn,ServerRole,AdminDisplayVersion,Edition }
}
Export-Collection 'Databases' {
    foreach ($db in $dbNames) { Invoke-EMTCommand Get-MailboxDatabase @{ Identity = $db; Status = $true } | Select-Object Name,Guid,Server,Mounted,DatabaseSize,AvailableNewMailboxSpace,EdbFilePath,LogFolderPath,MasterServerOrAvailabilityGroup,ReplicationType,IssueWarningQuota,ProhibitSendQuota,ProhibitSendReceiveQuota }
}
Export-Collection 'DAGs' { Invoke-EMTCommand Get-DatabaseAvailabilityGroup @{ Status = $true } | Select-Object Name,Servers,OperationalServers,PrimaryActiveManager,WitnessServer }
Export-Collection 'DatabaseCopies' {
    foreach ($server in $servers) { Invoke-EMTCommand Get-MailboxDatabaseCopyStatus @{ Server = $server } | Select-Object Name,Status,CopyQueueLength,ReplayQueueLength,ContentIndexState }
}
Export-Collection 'AcceptedDomains' { Invoke-EMTCommand Get-AcceptedDomain | Select-Object Name,DomainName,DomainType,Default }
Export-Collection 'SendConnectors' { Invoke-EMTCommand Get-SendConnector | Select-Object Name,Enabled,AddressSpaces,SmartHosts,DNSRoutingEnabled,SourceTransportServers,RequireTLS,TlsAuthLevel,TlsDomain }
Export-Collection 'ReceiveConnectors' {
    foreach ($server in $servers) { Invoke-EMTCommand Get-ReceiveConnector @{ Server = $server } | Select-Object Identity,Enabled,Bindings,RemoteIPRanges,AuthMechanism,PermissionGroups,Fqdn,TlsCertificateName }
}
Export-Collection 'Certificates' {
    foreach ($server in $servers) { Invoke-EMTCommand Get-ExchangeCertificate @{ Server = $server } | Select-Object @{n='Server';e={$server}},Thumbprint,Subject,CertificateDomains,Services,Status,NotAfter,HasPrivateKey }
}
foreach ($kind in @('Owa','Ecp','WebServices','Mapi','ActiveSync','Oab','Autodiscover','PowerShell')) {
    Export-Collection "$($kind)VirtualDirectories" {
        foreach ($server in $servers) { Invoke-EMTCommand "Get-$($kind)VirtualDirectory" @{ Server = $server } | Select-Object Identity,InternalUrl,ExternalUrl }
    }
}
Export-Collection 'ClientAccessNamespaces' {
    foreach ($server in $servers) { Invoke-EMTCommand Get-ClientAccessService @{ Identity = $server } | Select-Object Name,AutoDiscoverServiceInternalUri }
}
Export-Collection 'OutlookAnywhere' {
    foreach ($server in $servers) { Invoke-EMTCommand Get-OutlookAnywhere @{ Server = $server } | Select-Object Identity,InternalHostname,ExternalHostname,InternalClientsRequireSsl,ExternalClientsRequireSsl }
}
Export-Collection 'ExistingMoveRequests' { Invoke-EMTCommand Get-MoveRequest @{ ResultSize = 'Unlimited' } | Select-Object Identity,ExchangeGuid,Status,BatchName,SourceDatabase,TargetDatabase,Flags }
if ($IncludeDisconnected) {
    Export-Collection 'DisconnectedMailboxes' {
        foreach ($db in $dbNames) { Invoke-EMTCommand Get-MailboxStatistics @{ Database = $db } | Where-Object { $null -ne (Get-EMTProperty $_ DisconnectReason) } | Select-Object DisplayName,MailboxGuid,Database,DisconnectReason,DisconnectDate,TotalItemSize,ItemCount }
    }
}
Export-EMTReport $collection.ToArray() $config 'InventoryCollectionStatus' -Html:$Html
$rows
$collection.ToArray() | Write-Verbose
