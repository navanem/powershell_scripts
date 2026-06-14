#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Disables Fast Startup (hybrid boot) so Windows performs a full shutdown.
.DESCRIPTION
    Sets HiberbootEnabled to 0 with a native PowerShell call (no reg.exe). Fast
    Startup leaves the kernel session hibernated on shutdown, which causes
    drivers, Windows Update steps and Group Policy to apply inconsistently.
    Disabling it makes "Shut down" a true cold boot. Applies on the next full
    shutdown.
.EXAMPLE
    Disable-WindowsFastBoot
.NOTES
    Author : Emanuel De Almeida - https://www.navanem.com
#>
function Disable-WindowsFastBoot {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'

    try {
        if (-not (Test-Path $path)) {
            Write-Error "Registry path not found: $path"
            return
        }
        Set-ItemProperty -Path $path -Name 'HiberbootEnabled' -Type DWord -Value 0 -Force -ErrorAction Stop
        Write-Host '[ok] Fast Startup disabled. A full shutdown is required to apply it.'
    }
    catch {
        Write-Error "Failed to disable Fast Startup: $($_.Exception.Message)"
    }
}
