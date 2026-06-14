#Requires -Version 5.1
#Requires -Modules ActiveDirectory
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Restarts the DFSR service on every domain controller and enables DFSR
    auto-recovery (disabled on DCs by default). Honours -WhatIf / -Confirm.
.DESCRIPTION
    Auto-recovery is off by default on DCs, so after a dirty shutdown SYSVOL
    replication can stay stuck pending a manual decision. This enables it on
    every DC and gives DFSR a clean restart. It uses CIM (Get-/Set-CimInstance)
    over the existing remote session, replacing the deprecated wmic.exe utility
    that the original relied on (wmic is removed from recent Windows builds).
.PARAMETER RestartService
    Also restart the DFSR service (default true). Use -RestartService:$false to
    only flip auto-recovery without an interruption.
.EXAMPLE
    .\Restart-DFSRAndEnableAutoRecovery.ps1 -WhatIf
.EXAMPLE
    .\Restart-DFSRAndEnableAutoRecovery.ps1 -Confirm:$false
.NOTES
    Author : Emanuel De Almeida - https://www.navanem.com
    Refactored from a script by Andrew Ellis. Needs WinRM to each DC. Test in a
    lab before production use.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [bool] $RestartService = $true
)

$ErrorActionPreference = 'Stop'

$dcs = (Get-ADDomainController -Filter *).HostName
if (-not $dcs) { throw 'No domain controllers found.' }
Write-Verbose ("Targeting {0} DC(s): {1}" -f @($dcs).Count, ($dcs -join ', '))

foreach ($dc in $dcs) {
    try {
        if ($RestartService -and $PSCmdlet.ShouldProcess($dc, 'Restart DFSR service')) {
            Invoke-Command -ComputerName $dc -ScriptBlock {
                Restart-Service -Name DFSR -Force -ErrorAction Stop
            }
            Start-Sleep -Seconds 5
            Write-Output "Restarted DFSR on $dc."
        }

        if ($PSCmdlet.ShouldProcess($dc, 'Enable DFSR auto-recovery (StopReplicationOnAutoRecovery = false)')) {
            Invoke-Command -ComputerName $dc -ScriptBlock {
                Get-CimInstance -Namespace 'root/MicrosoftDFS' -ClassName 'DfsrMachineConfig' -ErrorAction Stop |
                    Set-CimInstance -Property @{ StopReplicationOnAutoRecovery = $false } -ErrorAction Stop
            }
            Write-Output "Enabled DFSR auto-recovery on $dc."
        }
    }
    catch {
        Write-Error ("Failed on {0}: {1}" -f $dc, $_.Exception.Message)
    }
}
