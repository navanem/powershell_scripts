#Requires -Version 5.1
#Requires -Modules ExchangeOnlineManagement
<#
.SYNOPSIS
    Exports every Exchange Online mailbox that has forwarding configured.
.DESCRIPTION
    Connects to Exchange Online with app-only (certificate) authentication,
    checks every user mailbox for forwarding (ForwardingAddress for an internal
    recipient, ForwardingSmtpAddress for an external one) and writes the ones
    that forward to a CSV, including whether a local copy is kept. Logs and the
    export are written under C:\Temp.

    Fill in your tenant, application (client) id and certificate thumbprint
    below. The app registration needs the Exchange.ManageAsApp role plus the
    Exchange Administrator (or Global Reader) directory role.
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
    Write-Log -Message 'Connecting to Exchange Online' -Type 'Information'
    Connect-ExchangeOnline -AppId $Application_ID -CertificateThumbprint $Certificate_Thumb_Print -Organization $Tenant -ShowBanner:$false
    Write-Log -Message 'Connected' -Type 'Success'
} Catch {
    Write-Host "`n`t$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Log -Message "$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -Type 'Error'
    Write-Log -Message 'Unable to connect' -Type 'Error'
    Break
}

Try {
    Write-Log -Message 'Checking mailboxes for forwarding' -Type 'Information'
    $Mailboxes = Get-Mailbox -RecipientTypeDetails UserMailbox -ResultSize Unlimited |
        Select-Object UserPrincipalName, PrimarySmtpAddress, DeliverToMailboxAndForward, ForwardingAddress, ForwardingSmtpAddress

    Foreach ($Mailbox in $Mailboxes) {
        if ($Mailbox.ForwardingAddress -or $Mailbox.ForwardingSmtpAddress) {
            [PSCustomObject][Ordered]@{
                'UserPrincipalName'     = $Mailbox.UserPrincipalName
                'PrimarySmtpAddress'    = $Mailbox.PrimarySmtpAddress
                'DeliverAndForward'     = $Mailbox.DeliverToMailboxAndForward
                'ForwardingAddress'     = $Mailbox.ForwardingAddress
                'ForwardingSmtpAddress' = $Mailbox.ForwardingSmtpAddress
            } | Export-Csv -Path 'C:\Temp\Export\Forwarding_Configured.csv' -Delimiter ',' -Encoding UTF8 -NoTypeInformation -Append -Force
        }
    }
    Write-Log -Message 'Exported all information' -Type 'Success'
} Catch {
    Write-Host "`n`t$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Log -Message "$($_.InvocationInfo.InvocationName) [Line:$($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)" -Type 'Error'
    Write-Log -Message 'Unable to export information' -Type 'Error'
}
