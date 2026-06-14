#Requires -Version 5.1
#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Exports every user account in a specific Active Directory OU to a CSV file.
.DESCRIPTION
    Reads all user objects under the given organizational unit with Get-ADUser
    and writes their name, user principal name, distinguished name and primary
    mail address to a CSV. Logs and the export are written under C:\Temp.

    Set $Organization_Unit to the distinguished name of the OU you want to
    export. Add or remove fields in $Properties to change the columns.
.NOTES
    Author : Emanuel De Almeida - https://www.navanem.com
    Version: 1.0
#>
$Global:ErrorActionPreference = 'Stop'

# Organizational unit to export (set to your OU's distinguished name)
$Organization_Unit = 'OU=Staff,DC=contoso,DC=com'

# Properties to read and export
$Properties = @(
    'Name',
    'UserPrincipalName',
    'distinguishedName',
    'mail'
)

# Log helper
Function Write-Log {
    Param(
        [Parameter(Mandatory = $true)][String]$Message,
        [Parameter(Mandatory = $true)][String]$Type
    )
    $Date = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$Date - $Type - $Message" |
        Out-File -FilePath "C:\Temp\Log\$(Get-Date -Format 'yyyy-MM-dd').log" -Append -Encoding UTF8
}

# Make sure the output folders exist
Function CheckFilePath {
    If (-not (Test-Path -Path 'C:\Temp\Log'))    { New-Item 'C:\Temp\Log'    -ItemType Directory | Out-Null }
    If (-not (Test-Path -Path 'C:\Temp\Export')) { New-Item 'C:\Temp\Export' -ItemType Directory | Out-Null }
}
CheckFilePath

Try {
    Write-Log -Message 'Collecting all users' -Type 'Information'
    $Users = Get-ADUser -SearchBase $Organization_Unit -Filter * -Properties $Properties |
        Select-Object $Properties
    Write-Log -Message "Collected $($Users.Count) users" -Type 'Success'
} Catch {
    Write-Host "`n`t$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Log -Message "$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -Type 'Error'
    Write-Log -Message 'Unable to collect users' -Type 'Error'
    Break
}

Try {
    Write-Log -Message 'Exporting user information' -Type 'Information'
    Foreach ($User in $Users) {
        [PSCustomObject][Ordered]@{
            'Name'              = $User.Name
            'UserPrincipalName' = $User.UserPrincipalName
            'distinguishedName' = $User.distinguishedName
            'mail'              = $User.mail
        } | Export-Csv -Path 'C:\Temp\Export\Export_Users.csv' -Delimiter ',' -Encoding UTF8 -NoTypeInformation -Append -Force
    }
    Write-Log -Message 'User information exported' -Type 'Success'
} Catch {
    Write-Host "`n`t$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Log -Message "$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -Type 'Error'
    Write-Log -Message 'Unable to export users' -Type 'Error'
}
