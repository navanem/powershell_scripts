#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Creates a local administrator account if it does not already exist.
.DESCRIPTION
    Idempotent: checks for the account first, creates it, sets the password to
    never expire, prevents the user from changing it, and adds it to the local
    Administrators group resolved by its well-known SID (S-1-5-32-544) so it
    works on non-English Windows installs.

    Manage the password with Windows LAPS, do not hard-code it.
.PARAMETER Username
    The account name to create.
.PARAMETER Description
    Description set on the new account.
.PARAMETER Password
    The initial password as a SecureString.
.EXAMPLE
    $pwd = Read-Host -AsSecureString 'Initial password'
    New-LocalAdmin -Username 'svc-admin' -Description 'Break-glass admin' -Password $pwd
.NOTES
    Author : Emanuel De Almeida - https://www.navanem.com
#>
function New-LocalAdmin {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]       $Username,
        [Parameter(Mandatory)][string]       $Description,
        [Parameter(Mandatory)][securestring] $Password
    )

    try {
        if (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue) {
            Write-Host "[skip] '$Username' already exists."
            return
        }

        # Resolve the Administrators group by SID (locale-independent).
        $adminGroup = (Get-LocalGroup -SID 'S-1-5-32-544').Name

        $params = @{
            Name                 = $Username
            Password             = $Password
            FullName             = $Username
            Description          = $Description
            PasswordNeverExpires = $true
            AccountNeverExpires  = $true
            ErrorAction          = 'Stop'
        }
        New-LocalUser @params | Out-Null
        Set-LocalUser -Name $Username -UserMayChangePassword $false -ErrorAction Stop
        Write-Host "[ok]   local user '$Username' created."

        if (-not (Get-LocalGroupMember -Group $adminGroup -Member $Username -ErrorAction SilentlyContinue)) {
            Add-LocalGroupMember -Group $adminGroup -Member $Username -ErrorAction Stop
            Write-Host "[ok]   '$Username' added to '$adminGroup'."
        }
    }
    catch {
        Write-Error "Failed to create '$Username': $($_.Exception.Message)"
    }
}
