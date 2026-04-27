function Remove-VROpsCredential {
    <#
    .SYNOPSIS
        Deletes a credential instance from vROps.
    .DESCRIPTION
        Calls DELETE /suite-api/api/credentials/{id}.
        vROps will refuse to delete a credential that is actively referenced by an
        adapter instance. Use Get-VROpsCredentialAdapter to check references first.
    .PARAMETER CredentialId
        The ID of the credential instance to delete. Accepts pipeline input from
        Get-VROpsCredential.
    .PARAMETER Server
        vROps hostname. Defaults to $DefaultOMServers[0].
    .PARAMETER SkipCertificateCheck
        Skip TLS certificate validation on the REST call.
    .EXAMPLE
        Remove-VROpsCredential -CredentialId '23653104-79c1-4943-8f90-532bdc0021da'
    .EXAMPLE
        Get-VROpsCredential -Name 'Old Credential' | Remove-VROpsCredential
    .LINK
        https://developer.broadcom.com/xapis/vmware-vrealize-operations-api/latest/api/credentials/id/delete/
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('id')]
        [string]$CredentialId,

        [Parameter(Mandatory = $false)]
        [string]$Server,

        [Parameter(Mandatory = $false)]
        [switch]$SkipCertificateCheck,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    process {
        if ($Force -or $PSCmdlet.ShouldProcess($CredentialId, 'Delete credential')) {
            $null = Invoke-VROpsApiRequest `
                -Server               $Server `
                -SkipCertificateCheck:$SkipCertificateCheck `
                -Path                 "credentials/$CredentialId" `
                -Method               'DELETE'

            Write-Host "Credential '$CredentialId' deleted."
            [PSCustomObject]@{
                CredentialId = $CredentialId
                Success      = $true
            }
        }
    }
}
