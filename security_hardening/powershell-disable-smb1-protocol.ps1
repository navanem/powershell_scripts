#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Fully disables the SMBv1 protocol (server, client and Windows feature).
.DESCRIPTION
    SMBv1 is obsolete and the vector behind WannaCry / EternalBlue. Disabling the
    server share alone is not enough, so this also removes the optional Windows
    feature where present, falling back to the legacy registry key on Windows 7 /
    Server 2008 R2.
.EXAMPLE
    Disable-SMB1
.NOTES
    Author : Emanuel De Almeida - https://www.navanem.com
    A reboot is recommended to fully unload the SMB1 driver.
#>
function Disable-SMB1 {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host 'Disabling SMBv1...'

        if (Get-Command Set-SmbServerConfiguration -ErrorAction SilentlyContinue) {
            Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction Stop
            Write-Host '[ok] SMB1 server protocol disabled.'
        }
        else {
            # Windows 7 / Server 2008 R2 fallback
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' -Name 'SMB1' -Type DWord -Value 0 -Force -ErrorAction Stop
            Write-Host '[ok] SMB1 server disabled via registry (legacy OS).'
        }

        # Remove the optional Windows feature (client OS / where present).
        $feature = Get-WindowsOptionalFeature -Online -FeatureName 'SMB1Protocol' -ErrorAction SilentlyContinue
        if ($feature -and $feature.State -ne 'Disabled') {
            Disable-WindowsOptionalFeature -Online -FeatureName 'SMB1Protocol' -NoRestart -ErrorAction Stop | Out-Null
            Write-Host '[ok] SMB1 Windows feature removed.'
        }

        Write-Host 'Complete. Reboot to fully unload the SMB1 driver.'
    }
    catch {
        Write-Error "Failed to disable SMB1: $($_.Exception.Message)"
    }
}
