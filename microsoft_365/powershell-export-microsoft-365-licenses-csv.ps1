#Requires -Version 5.1
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Identity.DirectoryManagement
<#
.SYNOPSIS
    Exports every Microsoft 365 subscribed SKU (license) to a CSV file.
.DESCRIPTION
    Connects to Microsoft Graph with app-only (certificate) authentication,
    reads all user-facing subscribed SKUs, and writes the SKU id, friendly
    name, purchased (enabled) units and consumed units to a timestamped CSV.
    Logs and the export are written under C:\Temp.

    Fill in your tenant id, application (client) id and certificate thumbprint
    below. The app registration needs the Organization.Read.All application
    permission with admin consent.
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
$Tenant_ID               = '<your-tenant-id>'
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

# Make sure the output folders exist
Function CheckFilePath {
    If (-not (Test-Path -Path 'C:\Temp\Log'))    { New-Item 'C:\Temp\Log'    -ItemType Directory | Out-Null }
    If (-not (Test-Path -Path 'C:\Temp\Export')) { New-Item 'C:\Temp\Export' -ItemType Directory | Out-Null }
}
CheckFilePath

Try {
    Write-Log -Message 'Connecting to Graph' -Type 'Information'
    Connect-MgGraph -ClientId $Application_ID -CertificateThumbprint $Certificate_Thumb_Print -TenantId $Tenant_ID
    Write-Log -Message 'Connected to Graph' -Type 'Success'
} Catch {
    Write-Host "`n`t$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Log -Message "$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -Type 'Error'
    Write-Log -Message 'Unable to connect' -Type 'Error'
    Break
}

Try {
    Write-Log -Message 'Gathering licenses' -Type 'Information'
    $Licenses = Get-MgSubscribedSku -All -Property * |
        Where-Object { $_.AppliesTo -eq 'User' } |
        Sort-Object -Property ConsumedUnits -Descending
    Write-Log -Message "Found $($Licenses.Count) types of licenses" -Type 'Success'
} Catch {
    Write-Host "`n`t$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Log -Message "$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -Type 'Error'
    Write-Log -Message 'Unable to get licenses' -Type 'Error'
}

Try {
    Write-Log -Message 'Exporting information' -Type 'Information'
    Foreach ($License in $Licenses) {
        [PSCustomObject]@{
            TimeStamp     = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            SkuId         = $License.SkuId
            License       = $License.SkuPartNumber
            Available     = $License.PrepaidUnits.Enabled
            ConsumedUnits = $License.ConsumedUnits
        } | Export-Csv -Path "C:\Temp\Export\Licenses-$(Get-Date -Format 'yyyy-MM-dd').csv" -Delimiter ',' -Encoding UTF8 -NoTypeInformation -Append -Force
    }
    Write-Log -Message 'Information exported' -Type 'Success'
} Catch {
    Write-Host "`n`t$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Log -Message "$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -Type 'Error'
    Write-Log -Message 'Unable to export information' -Type 'Error'
}
