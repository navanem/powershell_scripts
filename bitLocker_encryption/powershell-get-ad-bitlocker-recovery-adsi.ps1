#Requires -Version 2

<#
.SYNOPSIS
    Gets BitLocker recovery information from Active Directory using pure ADSI,
    with no dependency on RSAT or the ActiveDirectory module.
.DESCRIPTION
    The no-RSAT companion to the ActiveDirectory-module version. It uses raw
    ADSI / DirectorySearcher, so it runs on any domain-joined machine (PowerShell
    2.0+), which is exactly the box you are often standing at during a recovery.
    Look up BitLocker recovery passwords by computer name or by an 8-character
    recovery password ID.

    If you get no output for a valid password ID, your account lacks permission
    to read BitLocker recovery information: use -Credential, or run the session
    as an account that has it.
.PARAMETER Name
    One or more computer names. Wildcards are not supported.
.PARAMETER PasswordID
    The first 8 characters of a recovery password ID (0-9, A-F).
.PARAMETER Domain
    Read from computer objects in the specified domain.
.PARAMETER Server
    A specific domain controller to query.
.PARAMETER Credential
    Credentials with permission to read BitLocker recovery information.
.OUTPUTS
    PSObjects: distinguishedName, name, TPMRecoveryInformation, Date,
    PasswordID, RecoveryPassword ("N/A" when present but unreadable).
.EXAMPLE
    .\Get-ADBitLockerRecovery-ADSI.ps1 "computer1","computer2"
.EXAMPLE
    .\Get-ADBitLockerRecovery-ADSI.ps1 -PasswordID 1A2B3C4D
.NOTES
    Author : Emanuel De Almeida - https://www.navanem.com
    Based on the well-known BitLocker AD recovery script by Bill Stewart (windowsitpro).
.LINK
    https://www.navanem.com/scripts
    http://technet.microsoft.com/en-us/library/dd875529.aspx
#>

[CmdletBinding(DefaultParameterSetName="Name")]
param(
  [parameter(ParameterSetName="Name",Position=0,Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
    [alias("ComputerName")]
    [String[]] $Name,
  [parameter(ParameterSetName="PasswordID",Mandatory=$true)]
    [String] $PasswordID,
    [String] $Domain,
    [String] $Server,
    [Management.Automation.PSCredential] $Credential
)

begin {
  # Validate -PasswordID parameter; we use this rather than the ValidatePattern
  # attribute of the parameter to give a better error message
  if ( $PSCmdlet.ParameterSetName -eq "PasswordID" ) {
    if ( $PasswordID -notmatch '^[0-9A-F]{8}$' ) {
      throw "Cannot validate argument on parameter 'PasswordID'. This argument must be exactly 8 characters long and must contain only the characters 0 through 9 and A through F."
    }
  }

  # Pathname object contstants
  $ADS_SETTYPE_DN = 4
  $ADS_FORMAT_X500_PARENT = 8
  $ADS_DISPLAY_VALUE_ONLY = 2

  # Pathname object used by Get-ParentPath function
  $Pathname = New-Object -ComObject "Pathname"

  # Returns the parent path of a distinguished name
  function Get-ParentPath {
    param(
      [String] $distinguishedName
    )
    [Void] $Pathname.GetType().InvokeMember("Set", "InvokeMethod", $null, $Pathname, ($distinguishedName, $ADS_SETTYPE_DN))
    $Pathname.GetType().InvokeMember("Retrieve", "InvokeMethod", $null, $Pathname, $ADS_FORMAT_X500_PARENT)
  }

  # Returns only the name of the first element of a distinguished name
  function Get-NameElement {
    param(
      [String] $distinguishedName
    )
    [Void] $Pathname.GetType().InvokeMember("Set", "InvokeMethod", $null, $Pathname, ($distinguishedName, $ADS_SETTYPE_DN))
    [Void] $Pathname.GetType().InvokeMember("SetDisplayType", "InvokeMethod", $null, $Pathname, $ADS_DISPLAY_VALUE_ONLY)
    $Pathname.GetType().InvokeMember("GetElement", "InvokeMethod", $null, $Pathname, 0)
  }

  # Outputs a custom object based on a list of hash tables
  function Out-Object {
    param(
      [System.Collections.Hashtable[]] $hashData
    )
    $order = @()
    $result = @{}
    $hashData | ForEach-Object {
      $order += ($_.Keys -as [Array])[0]
      $result += $_
    }
    New-Object PSObject -Property $result | Select-Object $order
  }

  # Create and initialize DirectorySearcher object that finds computers
  $ComputerSearcher = [ADSISearcher] ""
  function Initialize-ComputerSearcher {
    if ( $Domain ) {
      if ( $Server ) {
        $path = "LDAP://$Server/$Domain"
      }
      else {
        $path = "LDAP://$Domain"
      }
    }
    else {
      if ( $Server ) {
        $path = "LDAP://$Server"
      }
      else {
        $path = ""
      }
    }
    if ( $Credential ) {
      $networkCredential = $Credential.GetNetworkCredential()
      $dirEntry = New-Object DirectoryServices.DirectoryEntry(
        $path,
        $networkCredential.UserName,
        $networkCredential.Password
      )
    }
    else {
      $dirEntry = [ADSI] $path
    }
    $ComputerSearcher.SearchRoot = $dirEntry
    $ComputerSearcher.Filter = "(objectClass=domain)"
    try {
      [Void] $ComputerSearcher.FindOne()
    }
    catch [Management.Automation.MethodInvocationException] {
      throw $_.Exception.InnerException
    }
  }
  Initialize-ComputerSearcher

  # Create and initialize DirectorySearcher for finding
  # msFVE-RecoveryInformation objects
  $RecoverySearcher = [ADSISearcher] ""
  $RecoverySearcher.PageSize = 100
  $RecoverySearcher.PropertiesToLoad.AddRange(@("distinguishedName","msFVE-RecoveryGuid","msFVE-RecoveryPassword","name"))

  # Gets the DirectoryEntry object for a specified computer
  function Get-ComputerDirectoryEntry {
    param(
      [String] $name
    )
    $ComputerSearcher.Filter = "(&(objectClass=computer)(name=$name))"
    try {
      $searchResult = $ComputerSearcher.FindOne()
      if ( $searchResult ) {
        $searchResult.GetDirectoryEntry()
      }
    }
    catch [Management.Automation.MethodInvocationException] {
      Write-Error -Exception $_.Exception.InnerException
    }
  }

  # Outputs $true if the piped DirectoryEntry has the specified property set,
  # or $false otherwise
  function Test-DirectoryEntryProperty {
    param(
      [String] $property
    )
    process {
      try {
        $_.Get($property) -ne $null
      }
      catch [Management.Automation.MethodInvocationException] {
        $false
      }
    }
  }

  # Gets a property from a ResultPropertyCollection; specify $propertyName
  # in lowercase to remain compatible with PowerShell v2
  function Get-SearchResultProperty {
    param(
      [DirectoryServices.ResultPropertyCollection] $properties,
      [String] $propertyName
    )
    if ( $properties[$propertyName] ) {
      $properties[$propertyName][0]
    }
  }

  # Gets BitLocker recovery information for the specified computer
  function GetBitLockerRecovery {
    param(
      $name
    )
    $domainName = $ComputerSearcher.SearchRoot.dc
    $computerDirEntry = Get-ComputerDirectoryEntry $name
    if ( -not $computerDirEntry ) {
      Write-Error "Unable to find computer '$name' in domain '$domainName'" -Category ObjectNotFound
      return
    }
    # If the msTPM-OwnerInformation (Vista/Server 2008/7/Server 2008 R2) or
    # msTPM-TpmInformationForComputer (Windows 8/Server 2012 or later)
    # attribute is set, then TPM recovery information is stored in AD
    $tpmRecoveryInformation = $computerDirEntry | Test-DirectoryEntryProperty "msTPM-OwnerInformation"
    if ( -not $tpmRecoveryInformation ) {
      $tpmRecoveryInformation = $computerDirEntry | Test-DirectoryEntryProperty "msTPM-TpmInformationForComputer"
    }
    $RecoverySearcher.SearchRoot = $computerDirEntry
    $searchResults = $RecoverySearcher.FindAll()
    foreach ( $searchResult in $searchResults ) {
      $properties = $searchResult.Properties
      $recoveryPassword = Get-SearchResultProperty $properties "msfve-recoverypassword"
      if ( $recoveryPassword ) {
        $recoveryDate = ([DateTimeOffset] ((Get-SearchResultProperty $properties "name") -split '{')[0]).DateTime
        $passwordID = ([Guid] [Byte[]] (Get-SearchResultProperty $properties "msfve-recoveryguid")).Guid
      }
      else {
        $tpmRecoveryInformation = $recoveryDate = $passwordID = $recoveryPassword = "N/A"
      }
      Out-Object `
        @{"distinguishedName"      = $computerDirEntry.Properties["distinguishedname"][0]},
        @{"name"                   = $computerDirEntry.Properties["name"][0]},
        @{"TPMRecoveryInformation" = $tpmRecoveryInformation},
        @{"Date"                   = $recoveryDate},
        @{"PasswordID"             = $passwordID.ToUpper()},
        @{"RecoveryPassword"       = $recoveryPassword.ToUpper()}
    }
    $searchResults.Dispose()
  }

  # Searches for BitLocker recovery information for the specified password ID
  function SearchBitLockerRecoveryByPasswordID {
    param(
      [String] $passwordID
    )
    $RecoverySearcher.Filter = "(&(objectClass=msFVE-RecoveryInformation)(name=*{$passwordID-*}))"
    $searchResults = $RecoverySearcher.FindAll()
    foreach ( $searchResult in $searchResults ) {
      $properties = $searchResult.Properties
      $computerName = Get-NameElement (Get-ParentPath (Get-SearchResultProperty $properties "distinguishedname"))
      $RecoverySearcher.Filter = "(objectClass=msFVE-RecoveryInformation)"
      GetBitLockerRecovery $computerName | Where-Object { $_.PasswordID -match "^$passwordID-" }
    }
    $searchResults.Dispose()
  }
}

process {
  if ( $PSCmdlet.ParameterSetName -eq "Name" ) {
    $RecoverySearcher.Filter = "(objectClass=msFVE-RecoveryInformation)"
    foreach ( $nameItem in $Name ) {
      GetBitLockerRecovery $nameItem
    }
  }
  elseif ( $PSCmdlet.ParameterSetName -eq "PasswordID" ) {
    SearchBitLockerRecoveryByPasswordID $PasswordID
  }
}
