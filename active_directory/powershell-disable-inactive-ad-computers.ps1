#Requires -Version 5.1
#Requires -Modules ActiveDirectory
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Disables AD computer accounts inactive beyond a threshold, using a last-logon
    value reconciled across every domain controller. Honours -WhatIf / -Confirm.
.DESCRIPTION
    LastLogon is not replicated between DCs, and lastLogonTimestamp lags by up to
    ~14 days, so this queries every domain controller and keeps the most recent
    logon per computer before deciding. Computers in the exclusion group(s) are
    never touched. Objects an admin has re-enabled get a grace window so they are
    not immediately disabled again.

    Disabled objects are stamped in ExtensionAttribute3 ("INACTIVE SINCE <date>").
    WARNING: do not use ExtensionAttribute3 for anything else.

    This is a full refactor of the original (parallel jobs + dynamic Set-Variable
    + hash-table comparison) into a single, readable per-DC reconciliation. It is
    safe to dry-run: -WhatIf shows every change without making it.
.PARAMETER DaysThreshold
    Inactivity, in days, before a computer is disabled. Default 90.
.PARAMETER ExclusionGroup
    One or more AD groups whose (recursive) members are never disabled.
.PARAMETER GraceDays
    How long a re-enabled computer is protected. Defaults to DaysThreshold.
.PARAMETER OutputDirectory
    If set, a CSV report of the inactive computers is written here.
.PARAMETER To / From / SmtpServer / Subject
    If all mail parameters are supplied, the CSV is emailed.
.EXAMPLE
    # Dry run, see what would be disabled
    .\Disable-InactiveADComputers.ps1 -DaysThreshold 90 -ExclusionGroup 'Auto-Disable Exclusions' -WhatIf
.EXAMPLE
    # Scheduled, non-interactive, with an emailed report
    .\Disable-InactiveADComputers.ps1 -DaysThreshold 90 -OutputDirectory C:\ScriptLogs -To it@example.com -From noreply@example.com -SmtpServer smtp.example.local -Confirm:$false
.NOTES
    Author : Emanuel De Almeida - https://www.navanem.com
    Refactored from a script by Andrew Ellis. Test in a lab before production use.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [int]      $DaysThreshold = 90,
    [string[]] $ExclusionGroup,
    [int]      $GraceDays = $DaysThreshold,
    [string]   $OutputDirectory,
    [string[]] $To,
    [string]   $From,
    [string]   $SmtpServer,
    [string]   $Subject = 'Inactive computer cleanup report'
)

$ErrorActionPreference = 'Stop'
$now = Get-Date

function ConvertFrom-FileTimeValue {
    param($Value)
    if ($Value -and [int64]$Value -gt 0) { [DateTime]::FromFileTime([int64]$Value) } else { $null }
}

$props = 'LastLogon', 'LastLogonTimestamp', 'whenCreated', 'Description', 'ExtensionAttribute3'

# 1. Reconcile the most recent LastLogon per computer across all DCs.
$dcs = (Get-ADDomainController -Filter *).HostName
if (-not $dcs) { throw 'No domain controllers found.' }
Write-Verbose ("Reconciling last logon across {0} DC(s): {1}" -f @($dcs).Count, ($dcs -join ', '))

$map = @{}
foreach ($dc in $dcs) {
    Write-Verbose "Querying $dc ..."
    foreach ($c in Get-ADComputer -Server $dc -Filter { Enabled -eq $true } -Properties $props) {
        $logon = ConvertFrom-FileTimeValue $c.LastLogon
        $entry = $map[$c.DistinguishedName]
        if (-not $entry) {
            $map[$c.DistinguishedName] = [pscustomobject]@{ Computer = $c; Logon = $logon }
        }
        elseif ($logon -and (-not $entry.Logon -or $logon -gt $entry.Logon)) {
            $entry.Logon = $logon
        }
    }
}

# 2. Resolve exclusions (recursive group membership).
$excluded = @{}
foreach ($g in $ExclusionGroup) {
    Write-Verbose "Reading exclusion group '$g'..."
    foreach ($m in Get-ADGroupMember -Identity $g -Recursive) { $excluded[$m.distinguishedName] = $true }
}

# 3. Compute the effective last logon and days inactive for each computer.
$report = foreach ($entry in $map.Values) {
    $c = $entry.Computer
    $effective = $entry.Logon

    $stamp = ConvertFrom-FileTimeValue $c.LastLogonTimestamp
    if ($stamp -and (-not $effective -or $stamp -gt $effective)) { $effective = $stamp }

    if ($c.ExtensionAttribute3 -like 'RE-ENABLED ON *') {
        $reEnabled = $null
        if ([datetime]::TryParse(($c.ExtensionAttribute3 -replace '^RE-ENABLED ON ', ''), [ref]$reEnabled) -and
            (-not $effective -or $reEnabled -gt $effective)) { $effective = $reEnabled }
    }
    if (-not $effective) { $effective = $c.whenCreated }

    [pscustomobject]@{
        Name              = $c.Name
        SamAccountName    = $c.SamAccountName
        LastLogon         = $effective
        DaysInactive      = [int][math]::Floor((New-TimeSpan -Start $effective -End $now).TotalDays)
        WhenCreated       = $c.whenCreated
        DistinguishedName = $c.DistinguishedName
        Description       = $c.Description
        Excluded          = [bool]$excluded[$c.DistinguishedName]
    }
}

$inactive = @($report | Where-Object { $_.DaysInactive -ge $DaysThreshold -and -not $_.Excluded } | Sort-Object DaysInactive -Descending)
Write-Output ("{0} computer(s) inactive >= {1} days ({2} protected by exclusion)." -f $inactive.Count, $DaysThreshold, @($report | Where-Object Excluded).Count)

# 4. Disable + stamp (ShouldProcess-gated).
foreach ($item in $inactive) {
    if ($PSCmdlet.ShouldProcess($item.SamAccountName, "Disable account and stamp ExtensionAttribute3 ($($item.DaysInactive) days inactive)")) {
        Disable-ADAccount -Identity $item.SamAccountName
        Set-ADComputer -Identity $item.SamAccountName -Replace @{ ExtensionAttribute3 = "INACTIVE SINCE " + $item.LastLogon.ToString('yyyy-MM-dd') }
        Write-Output ("Disabled {0} ({1} days inactive)." -f $item.SamAccountName, $item.DaysInactive)
    }
}

# 5. Maintenance: flag manually re-enabled objects, clear expired flags.
foreach ($c in Get-ADComputer -Filter { Enabled -eq $true } -Properties ExtensionAttribute3 |
        Where-Object { $_.ExtensionAttribute3 -like 'INACTIVE SINCE *' -or $_.ExtensionAttribute3 -like 'DISABLED ON *' }) {
    if ($PSCmdlet.ShouldProcess($c.SamAccountName, 'Flag as RE-ENABLED')) {
        Set-ADComputer -Identity $c.SamAccountName -Replace @{ ExtensionAttribute3 = "RE-ENABLED ON " + $now.ToString('yyyy-MM-dd') }
    }
}
foreach ($c in Get-ADComputer -Filter { Enabled -eq $true } -Properties ExtensionAttribute3 |
        Where-Object { $_.ExtensionAttribute3 -like 'RE-ENABLED ON *' }) {
    $d = $null
    if ([datetime]::TryParse(($c.ExtensionAttribute3 -replace '^RE-ENABLED ON ', ''), [ref]$d) -and $d -lt $now.AddDays(-$GraceDays)) {
        if ($PSCmdlet.ShouldProcess($c.SamAccountName, 'Clear expired RE-ENABLED flag')) {
            Set-ADComputer -Identity $c.SamAccountName -Clear ExtensionAttribute3
        }
    }
}

# 6. Optional CSV + email.
if ($OutputDirectory) {
    if (-not (Test-Path $OutputDirectory)) { New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null }
    $csv = Join-Path $OutputDirectory ("InactiveComputers-{0:yyyyMMdd}.csv" -f $now)
    $inactive | Export-Csv -Path $csv -NoTypeInformation -Force
    Write-Output "Report written to $csv"

    if ($To -and $From -and $SmtpServer) {
        $body = "{0} computer(s) were inactive >= {1} days. See the attached report." -f $inactive.Count, $DaysThreshold
        Send-MailMessage -To $To -From $From -SmtpServer $SmtpServer -Subject $Subject -Body $body -Attachments $csv
        Write-Output "Report emailed to $($To -join ', ')."
    }
}
