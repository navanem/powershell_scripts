#Requires -Version 5.1

<#
.SYNOPSIS
    Restarts one or more Windows services on one or more remote servers, pinging
    first and emailing the outcome (or any failure). Honours -WhatIf / -Confirm.
.DESCRIPTION
    For each target the script tests connectivity, restarts the named service(s),
    and sends an email report on success or failure. It accepts pipeline input,
    so you can feed it a list of server/service pairs and let it work through
    them. Email is optional: omit the mail parameters to just restart and log.
.PARAMETER ComputerName
    The remote server. Pipeline-bindable (alias: Server).
.PARAMETER ServiceName
    One or more service names to restart on that server (alias: Service).
.PARAMETER To / From / SmtpServer
    Supply all three to receive an email report per action.
.EXAMPLE
    Restart-RemoteService -ComputerName SQL01 -ServiceName MSSQLSERVER -To it@example.com -From noreply@example.com -SmtpServer smtp.example.local
.EXAMPLE
    # Dry run a batch from the pipeline
    @(
        [pscustomobject]@{ ComputerName = 'SQL01'; ServiceName = 'MSSQLSERVER' }
        [pscustomobject]@{ ComputerName = 'WEB01'; ServiceName = @('W3SVC', 'WAS') }
    ) | Restart-RemoteService -To it@example.com -From noreply@example.com -SmtpServer smtp.example.local -WhatIf
.NOTES
    Author : Emanuel De Almeida - https://www.navanem.com
    Test before production.
#>

function Send-Notification {
    param(
        [string[]] $To,
        [string]   $From,
        [string]   $Subject,
        [string]   $Body,
        [string]   $SmtpServer
    )
    if (-not ($To -and $From -and $SmtpServer)) { return }   # email is optional
    $msg = New-Object Net.Mail.MailMessage
    $smtp = New-Object Net.Mail.SmtpClient($SmtpServer)
    try {
        $msg.From = $From
        foreach ($addr in $To) { $msg.To.Add($addr) }
        $msg.Subject = $Subject
        $msg.IsBodyHtml = $true
        $msg.Body = $Body
        $smtp.Send($msg)
    }
    catch {
        Write-Warning "Could not send notification: $($_.Exception.Message)"
    }
    finally {
        $msg.Dispose()
        $smtp.Dispose()
    }
}

function Restart-RemoteService {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('Server')]
        [string] $ComputerName,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('Service')]
        [string[]] $ServiceName,

        [string[]] $To,
        [string]   $From,
        [string]   $SmtpServer
    )

    process {
        $mail = @{ To = $To; From = $From; SmtpServer = $SmtpServer }

        if (-not (Test-Connection -ComputerName $ComputerName -Count 2 -Quiet)) {
            Write-Warning "$ComputerName is not responding to ping; skipping."
            Send-Notification @mail -Subject "Server: $ComputerName - Status" -Body "$ComputerName is not responding to ping. Please investigate."
            return
        }

        foreach ($svc in $ServiceName) {
            if (-not $PSCmdlet.ShouldProcess("$ComputerName\$svc", 'Restart service')) { continue }
            try {
                $service = Get-Service -ComputerName $ComputerName -Name $svc -ErrorAction Stop
                Restart-Service -InputObject $service -Force -ErrorAction Stop
                Write-Output "Restarted $ComputerName\$svc."
                Send-Notification @mail -Subject "Server: $ComputerName - Restart" -Body "$ComputerName\$svc has been restarted."
            }
            catch {
                Write-Error "Failed to restart $ComputerName\$svc : $($_.Exception.Message)"
                Send-Notification @mail -Subject "Server: $ComputerName - Error" -Body "$ComputerName\$svc restart failed. Details: $($_.Exception.Message)"
            }
        }
    }
}

# ── Edit and uncomment, or dot-source this file (. .\Restart-RemoteService.ps1) and call the function. ──
# Restart-RemoteService -ComputerName 'Server1' -ServiceName 'ServiceName1' -To 'it@example.com' -From 'noreply@example.com' -SmtpServer 'smtp.example.local'
# Restart-RemoteService -ComputerName 'Server2' -ServiceName 'ServiceName2' -To 'it@example.com' -From 'noreply@example.com' -SmtpServer 'smtp.example.local'
