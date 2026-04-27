function Remove-VROpsCertificate {
    <#
    .SYNOPSIS
        Deletes a certificate from vROps by thumbprint.
    .DESCRIPTION
        Calls DELETE /suite-api/api/certificate?thumbprint=<thumbprint>&force=<true|false>.

        By default vROps will refuse to delete a certificate that is actively referenced
        by an adapter instance or credential. Use -Force to override this and delete the
        certificate regardless.

        Equivalent curl:
          curl -X DELETE "https://<host>/suite-api/api/certificate?force=false&thumbprint=<thumb>&_no_links=true" \
               -H "accept: */*" \
               -H "Authorization: OpsToken <token>"
    .PARAMETER Thumbprint
        The thumbprint of the certificate to delete. Accepts pipeline input from
        Get-VROpsCertificate.
    .PARAMETER Force
        Delete the certificate even if it is currently in use by an adapter instance
        or credential. Defaults to $false.
    .PARAMETER Server
        vROps hostname. Defaults to $DefaultOMServers[0].
    .PARAMETER SkipCertificateCheck
        Skip TLS certificate validation on the REST call.
    .EXAMPLE
        # Delete a specific certificate (safe -- fails if in use)
        Remove-VROpsCertificate -Thumbprint 'AA:BB:CC:DD:EE:FF'
    .EXAMPLE
        # Force-delete even if an adapter is using the certificate
        Remove-VROpsCertificate -Thumbprint 'AA:BB:CC:DD:EE:FF' -Force
    .EXAMPLE
        # Pipeline: delete a cert matched by thumbprint
        Get-VROpsCertificate | Where-Object { $_.thumbprint -eq 'AA:BB:CC:DD:EE:FF' } |
            Remove-VROpsCertificate -Force
    .LINK
        https://developer.broadcom.com/xapis/vmware-vrealize-operations-api/8.10.0/certificate/
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('certificateThumbprint')]
        [string]$Thumbprint,

        [Parameter(Mandatory = $false)]
        [switch]$Force,

        [Parameter(Mandatory = $false)]
        [string]$Server,

        [Parameter(Mandatory = $false)]
        [switch]$SkipCertificateCheck
    )

    process {
        $query = @{
            thumbprint = $Thumbprint
            force      = $Force.IsPresent ? 'true' : 'false'
        }

        $action = $Force.IsPresent ? 'Force-delete certificate' : 'Delete certificate'

        if ($PSCmdlet.ShouldProcess($Thumbprint, $action)) {
            # DELETE returns no body on success (204); suppress null pipeline output
            $null = Invoke-VROpsApiRequest `
                -Server               $Server `
                -SkipCertificateCheck:$SkipCertificateCheck `
                -Path                 'certificate' `
                -Method               'DELETE' `
                -QueryParameters      $query

            Write-Host "Certificate '$Thumbprint' deleted$($Force.IsPresent ? ' (forced)' : '')."
            [PSCustomObject]@{
                Thumbprint = $Thumbprint
                Success    = $true
            }
        }
    }
}
