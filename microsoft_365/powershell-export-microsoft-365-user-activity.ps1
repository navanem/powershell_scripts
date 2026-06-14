#Requires -Version 5.1
#Requires -Modules PnP.PowerShell, MicrosoftPowerBIMgmt
<#
.SYNOPSIS
    Exports Microsoft 365 user activity: active-user details, last sign-in per
    user, and Power BI activity events.
.DESCRIPTION
    Uses an app-only (certificate) connection to pull three reports and write
    them to CSV under C:\Temp\Export:
      1. Office 365 active-user detail (Microsoft Graph reports, 180 days).
      2. Last sign-in and days-since-sign-in per user (Graph beta signInActivity).
      3. Power BI activity events for the last N days.

    Fill in your tenant, admin URL, application (client) id and certificate
    thumbprint, and set $Days. The app registration needs Microsoft Graph
    Reports.Read.All and AuditLog.Read.All, plus Power BI service admin rights;
    sign-in activity also requires Microsoft Entra ID P1.
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
$SPO_Source              = 'https://<your-tenant>-admin.sharepoint.com'

# How many days of Power BI activity to export
$Days = 30
$Day  = Get-Date

# Microsoft Graph reporting endpoint and report accumulator
$Uri = "https://graph.microsoft.com/v1.0/reports/getOffice365ActiveUserDetail(period='D180')"
$UsersReport = @()

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
    If (-not (Test-Path -Path 'C:\Temp\Log'))    { New-Item 'C:\Temp\Log'    -ItemType Directory | Out-Null }
    If (-not (Test-Path -Path 'C:\Temp\Export')) { New-Item 'C:\Temp\Export' -ItemType Directory | Out-Null }
}
CheckFilePath

Try {
    Write-Log -Message 'Connecting to PnP Online' -Type 'Information'
    Connect-PnPOnline -Url $SPO_Source -Tenant $Tenant_ID -ClientId $Application_ID -Thumbprint $Certificate_Thumb_Print
    Write-Log -Message 'Connected to PnP' -Type 'Success'
} Catch {
    Write-Host "`n`t$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Log -Message "$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -Type 'Error'
    Write-Log -Message 'Unable to connect' -Type 'Error'
    Break
}

Try {
    Write-Log -Message 'Getting a Graph token from PnP' -Type 'Information'
    $Token  = Get-PnPAccessToken
    $Header = @{ Authorization = "Bearer $($Token)" }
    Write-Log -Message 'Token saved' -Type 'Success'
} Catch {
    Write-Host "`n`t$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Log -Message "$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -Type 'Error'
    Write-Log -Message 'Unable to get the token' -Type 'Error'
}

Try {
    Write-Log -Message 'Getting active-user details' -Type 'Information'
    $Active_Users = Invoke-RestMethod -Uri $Uri -Headers $Header -Method Get -ContentType 'application/json'
    # The report is returned as CSV with a leading BOM; strip the first characters
    $Active_Users = $Active_Users.Substring(3) | ConvertFrom-Csv
    $Active_Users | Export-Csv -Path "C:\Temp\Export\Active_Users_$(Get-Date -Format 'yyyy-MM-dd').csv" -Delimiter ',' -Encoding UTF8 -NoTypeInformation -Append -Force
    Write-Log -Message 'Users gathered and exported' -Type 'Success'
} Catch {
    Write-Host "`n`t$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Log -Message "$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -Type 'Error'
    Write-Log -Message 'Unable to gather and export users' -Type 'Error'
}

Try {
    Write-Log -Message 'Gathering and exporting last sign-in' -Type 'Information'
    $Uri = "https://graph.microsoft.com/beta/users?`$select=displayName,userPrincipalName,signInActivity,createdDateTime,userType&`$top=999"
    $SignIn_Info = Invoke-RestMethod -Uri $Uri -Headers $Header -Method Get -ContentType 'application/json'

    Do {
        Foreach ($User in $SignIn_Info.Value) {
            If ($Null -ne $User.SignInActivity -and $Null -ne $User.SignInActivity.LastSignInDateTime) {
                $LastSignIn      = Get-Date $User.SignInActivity.LastSignInDateTime -Format g
                $DaysSinceSignIn = (New-TimeSpan -Start $LastSignIn).Days
            } Else {
                $LastSignIn      = ''
                $DaysSinceSignIn = ''
            }
            $UsersReport += [PSCustomObject]@{
                UPN             = $User.UserPrincipalName
                DisplayName     = $User.DisplayName
                ObjectId        = $User.Id
                Created         = Get-Date $User.CreatedDateTime -Format g
                LastSignIn      = $LastSignIn
                DaysSinceSignIn = $DaysSinceSignIn
                UserType        = $User.UserType
            }
        }
        $NextLink = $SignIn_Info.'@odata.nextLink'
        If ($NextLink) { $SignIn_Info = Invoke-RestMethod -Uri $NextLink -Headers $Header -Method Get -ContentType 'application/json' }
    } While ($NextLink)

    $UsersReport | Export-Csv -Path "C:\Temp\Export\Last_SignIn_$(Get-Date -Format 'yyyy-MM-dd').csv" -Delimiter ',' -Encoding UTF8 -NoTypeInformation -Append -Force
    Write-Log -Message 'Last sign-in exported' -Type 'Success'
} Catch {
    Write-Host "`n`t$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Log -Message "$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -Type 'Error'
    Write-Log -Message 'Unable to get and export last sign-in' -Type 'Error'
}

Disconnect-PnPOnline

Try {
    Write-Log -Message 'Connecting to Power BI' -Type 'Information'
    Connect-PowerBIServiceAccount -ServicePrincipal -ApplicationId $Application_ID -CertificateThumbprint $Certificate_Thumb_Print -Tenant $Tenant_ID
    Write-Log -Message 'Connected to Power BI' -Type 'Success'
} Catch {
    Write-Host "`n`t$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Log -Message "$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -Type 'Error'
    Write-Log -Message 'Unable to connect to Power BI' -Type 'Error'
    Break
}

Try {
    Write-Log -Message 'Exporting Power BI activity logs' -Type 'Information'
    For ($s = 0; $s -le $Days; $s++) {
        $Period_Start = $Day.AddDays(-$s)
        $Base = $Period_Start.ToString('yyyy-MM-dd')
        $Url = "https://api.powerbi.com/v1.0/myorg/admin/activityevents?startDateTime='$($Base)T00:00:00.000'&endDateTime='$($Base)T23:59:59.999'"
        $Activities = (Invoke-PowerBIRestMethod -Url $Url -Method Get | ConvertFrom-Json).activityEventEntities
        $Activities | Select-Object CreationTime, UserId |
            Export-Csv -Path "C:\Temp\Export\PowerBI_Activity_$(Get-Date -Format 'yyyy-MM-dd').csv" -Delimiter ',' -Encoding UTF8 -NoTypeInformation -Append -Force
    }
    Write-Log -Message 'Activity exported' -Type 'Success'
} Catch {
    Write-Host "`n`t$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Log -Message "$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -Type 'Error'
    Write-Log -Message 'Unable to export Power BI activity' -Type 'Error'
}
