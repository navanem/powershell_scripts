#Requires -Version 5.1
#Requires -Modules PnP.PowerShell
<#
.SYNOPSIS
    Deletes ALL previous file versions from every document library on every
    SharePoint Online site.
.DESCRIPTION
    Connects to the SharePoint admin center with app-only (certificate)
    authentication, enumerates every site, and for each file in every visible
    document library deletes the entire version history with CSOM
    (Versions.DeleteAll). This reclaims the storage consumed by old versions.

    WARNING: this is destructive and irreversible. Deleted versions cannot be
    recovered. Apply a sane max-version policy first, test on a pilot site, and
    confirm your backup strategy before running it tenant-wide.

    The app registration needs SharePoint app-only permissions
    (Sites.FullControl.All).
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
    Write-Log -Message 'Getting all sites from SharePoint Online' -Type 'Information'
    $Sites = Get-PnPTenantSite
    Write-Log -Message "Sites found: $($Sites.Count)" -Type 'Information'

    Foreach ($Site in $Sites) {
        Connect-PnPOnline -Url $Site.Url -Tenant $Tenant -ClientId $Application_ID -Thumbprint $Certificate_Thumb_Print
        $Context = Get-PnPContext
        $Document_Libraries = Get-PnPList | Where-Object { $_.BaseType -eq 'DocumentLibrary' -and $_.Hidden -eq $false }
        $i = 1
        $Total = [math]::Max($Document_Libraries.Count, 1)
        Foreach ($Library in $Document_Libraries) {
            Write-Progress -Activity 'Cleaning versions' -Status "Library $i of $Total in $($Site.Url)" -PercentComplete (($i / $Total) * 100)
            $List_Items = Get-PnPListItem -List $Library -PageSize 2000 | Where-Object { $_.FileSystemObjectType -eq 'File' }
            Foreach ($Item in $List_Items) {
                $File = $Item.File
                $Versions = $File.Versions
                $Context.Load($File)
                $Context.Load($Versions)
                $Context.ExecuteQuery()
                If ($Versions.Count -gt 0) {
                    $Versions.DeleteAll()
                    Invoke-PnPQuery
                }
            }
            $i++
        }
    }
    Write-Log -Message 'All sites processed' -Type 'Success'
} Catch {
    Write-Host "`n`t$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Log -Message "$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -Type 'Error'
    Write-Log -Message 'Unable to process all sites' -Type 'Error'
}
