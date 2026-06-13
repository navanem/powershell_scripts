#Requires -Version 5.1
#Requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Gets BitLocker recovery information escrowed in Active Directory, by computer
    name or by the 8-character recovery password ID.
.DESCRIPTION
    Reads msFVE-RecoveryInformation objects stored under AD computer accounts and
    returns the recovery password, password ID, escrow date and whether TPM
    recovery information is present. Look up named computers, pipe in
    Get-ADComputer results for a whole OU, or search by the password ID a user
    reads from the BitLocker recovery screen.

    This is a refactor of the classic raw-ADSI script onto the ActiveDirectory
    module: far less code, native pipeline and -Server support. (It therefore
    needs RSAT / the AD module, unlike the pure-ADSI original.)

    Reading recovery passwords is privileged. If RecoveryPassword comes back
    empty, your account can see the object but not the secret: rerun as, or
    delegate to, an account with the right to read msFVE-RecoveryInformation.
.PARAMETER Name
    One or more computer names (no wildcards).
.PARAMETER PasswordID
    The first 8 characters (0-9, A-F) of a recovery password ID.
.PARAMETER Server
    A specific domain controller to query.
.EXAMPLE
    .\Get-ADBitLockerRecovery.ps1 PC001,PC002
.EXAMPLE
    Get-ADComputer -Filter * -SearchBase 'OU=Laptops,DC=corp,DC=local' | .\Get-ADBitLockerRecovery.ps1
.EXAMPLE
    .\Get-ADBitLockerRecovery.ps1 -PasswordID 1A2B3C4D
.NOTES
    Author : Emanuel De Almeida - https://www.navanem.com
    Refactored from the BitLocker AD recovery script by Bill Stewart (windowsitpro).
#>
[CmdletBinding(DefaultParameterSetName = 'Name')]
param(
    [Parameter(ParameterSetName = 'Name', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [Alias('ComputerName')]
    [string[]] $Name,

    [Parameter(ParameterSetName = 'PasswordID', Mandatory)]
    [ValidatePattern('^[0-9A-Fa-f]{8}$')]
    [string] $PasswordID,

    [string] $Server
)

begin {
    $common = @{}
    if ($Server) { $common['Server'] = $Server }
    $fveProps = 'msFVE-RecoveryPassword', 'msFVE-RecoveryGuid', 'whenCreated'

    function Get-PasswordIdFromGuid {
        param($GuidBytes)
        if (-not $GuidBytes) { return $null }
        ([Guid][Byte[]]$GuidBytes).Guid.Split('-')[0].ToUpper()
    }

    # Emits one row per recovery object found under a computer.
    function Get-RecoveryForComputer {
        param($Computer)
        $tpm = [bool]($Computer.'msTPM-OwnerInformation' -or $Computer.'msTPM-TpmInformationForComputer')
        $found = $false
        Get-ADObject -SearchBase $Computer.DistinguishedName -SearchScope Subtree `
            -LDAPFilter '(objectClass=msFVE-RecoveryInformation)' -Properties $fveProps @common |
            ForEach-Object {
                $found = $true
                [pscustomobject]@{
                    Computer               = $Computer.Name
                    DistinguishedName      = $Computer.DistinguishedName
                    TPMRecoveryInformation = $tpm
                    Date                   = $_.whenCreated
                    PasswordID             = Get-PasswordIdFromGuid $_.'msFVE-RecoveryGuid'
                    RecoveryPassword       = $_.'msFVE-RecoveryPassword'
                }
            }
        if (-not $found) {
            [pscustomobject]@{
                Computer               = $Computer.Name
                DistinguishedName      = $Computer.DistinguishedName
                TPMRecoveryInformation = $tpm
                Date                   = $null
                PasswordID             = $null
                RecoveryPassword       = $null
            }
        }
    }
}

process {
    $tpmProps = 'msTPM-OwnerInformation', 'msTPM-TpmInformationForComputer'

    if ($PSCmdlet.ParameterSetName -eq 'Name') {
        foreach ($n in $Name) {
            $c = Get-ADComputer -Identity $n -Properties $tpmProps @common -ErrorAction SilentlyContinue
            if (-not $c) { Write-Error "Computer '$n' not found." -Category ObjectNotFound; continue }
            Get-RecoveryForComputer -Computer $c
        }
    }
    else {
        # Search every recovery object whose ID starts with the supplied 8 chars.
        $matches = Get-ADObject -LDAPFilter "(&(objectClass=msFVE-RecoveryInformation)(name=*{$PasswordID-*}))" -Properties $fveProps @common
        foreach ($m in $matches) {
            $parentDN = ($m.DistinguishedName -split ',', 2)[1]
            $c = Get-ADComputer -Identity $parentDN -Properties $tpmProps @common -ErrorAction SilentlyContinue
            if (-not $c) { continue }
            $tpm = [bool]($c.'msTPM-OwnerInformation' -or $c.'msTPM-TpmInformationForComputer')
            [pscustomobject]@{
                Computer               = $c.Name
                DistinguishedName      = $c.DistinguishedName
                TPMRecoveryInformation = $tpm
                Date                   = $m.whenCreated
                PasswordID             = Get-PasswordIdFromGuid $m.'msFVE-RecoveryGuid'
                RecoveryPassword       = $m.'msFVE-RecoveryPassword'
            }
        }
    }
}
