#Requires -Version 5.1
#Requires -Modules PnP.PowerShell
<#
.SYNOPSIS
    Sets a maximum major-version limit on document libraries across every
    SharePoint Online site.
.DESCRIPTION
    Connects to the SharePoint admin center with app-only (certificate)
    authentication, enumerates every site collection, and applies a major-
    version limit to each visible document library (skipping Style Library,
    Site Assets and libraries that do not have versioning enabled). This caps
    the version history that quietly consumes SharePoint storage.

    Fill in your tenant, admin URL, application (client) id and certificate
    thumbprint below, and set $Major_Versions. The app registration needs
    SharePoint app-only permissions (Sites.FullControl.All) to change list
    settings tenant-wide.

    This script CHANGES settings on every site. Test it on a pilot site first.
.NOTES
    Author : Emanuel De Almeida - https://www.navanem.com
    Version: 1.0
#>
If ([Net.SecurityProtocolType]::Tls12 -bor $False) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Host "`t Forced TLS 1.2 since it is not the server default"
}
$Global:ErrorActionPreference = 'Stop'

# ─── Connection variables (replace with your own) ───
$Tenant                  = '<your-tenant>.onmicrosoft.com'
$Admin_Url               = 'https://<your-tenant>-admin.sharepoint.com'
$Application_ID          = '<your-application-id>'
$Certificate_Thumb_Print = '<your-certificate-thumbprint>'

# Maximum number of major versions to keep per document library
$Major_Versions = 25

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

# Make sure the log folder exists
Function CheckFilePath {
    If (-not (Test-Path -Path 'C:\Temp\Log')) { New-Item 'C:\Temp\Log' -ItemType Directory | Out-Null }
}
CheckFilePath

Try {
    Write-Log -Message 'Connecting to SharePoint Online' -Type 'Information'
    Connect-PnPOnline -Url $Admin_Url -Tenant $Tenant -ClientId $Application_ID -Thumbprint $Certificate_Thumb_Print
    Write-Log -Message 'Connected' -Type 'Success'
} Catch {
    Write-Host "`n`t$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Log -Message "$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -Type 'Error'
    Write-Log -Message 'Unable to connect to SharePoint Online' -Type 'Error'
    Break
}

Try {
    Write-Log -Message 'Getting all sites' -Type 'Information'
    $Sites = Get-PnPTenantSite
    Write-Log -Message "Retrieved $($Sites.Count) sites" -Type 'Information'
    Write-Log -Message "Applying the max-version policy ($Major_Versions) to all sites" -Type 'Information'

    Foreach ($Site in $Sites) {
        $Site_Connection = Connect-PnPOnline -Url $Site.Url -Tenant $Tenant -ClientId $Application_ID -Thumbprint $Certificate_Thumb_Print -ReturnConnection
        $Document_Libraries = Get-PnPList -Connection $Site_Connection |
            Where-Object { $_.BaseTemplate -eq 101 -and $_.Hidden -eq $false }

        Foreach ($Library in $Document_Libraries) {
            if ($Library.Title -in @('Style Library', 'Site Assets') -or -not $Library.EnableVersioning) {
                Continue
            }
            Write-Log -Message "Setting $Major_Versions major versions on '$($Library.Title)' in $($Site.Url)" -Type 'Information'
            Set-PnPList -Identity $Library -MajorVersions $Major_Versions -Connection $Site_Connection
        }
    }
    Write-Log -Message 'Version policy applied to all sites' -Type 'Success'
} Catch {
    Write-Host "`n`t$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Log -Message "$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -Type 'Error'
}
