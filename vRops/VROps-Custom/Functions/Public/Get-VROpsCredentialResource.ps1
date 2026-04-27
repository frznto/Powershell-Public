function Get-VROpsCredentialResource {
    <#
    .SYNOPSIS
        Gets the resource objects using a given credential.
    .DESCRIPTION
        Calls GET /suite-api/api/credentials/{id}/resources to return all resources
        (monitored objects) that reference the specified credential instance.
    .PARAMETER CredentialId
        The ID of the credential instance. Accepts pipeline input from Get-VROpsCredential.
    .PARAMETER Server
        vROps hostname. Defaults to $DefaultOMServers[0].
    .PARAMETER SkipCertificateCheck
        Skip TLS certificate validation on the REST call.
    .EXAMPLE
        Get-VROpsCredentialResource -CredentialId '23653104-79c1-4943-8f90-532bdc0021da'
    .EXAMPLE
        Get-VROpsCredential -Name 'My VC Credential' | Get-VROpsCredentialResource
    .LINK
        https://developer.broadcom.com/xapis/vmware-vrealize-operations-api/latest/api/credentials/id/resources/get/
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('id')]
        [string]$CredentialId,

        [Parameter(Mandatory = $false)]
        [string]$Server,

        [Parameter(Mandatory = $false)]
        [switch]$SkipCertificateCheck
    )

    process {
        $result    = Invoke-VROpsApiRequest `
            -Server               $Server `
            -SkipCertificateCheck:$SkipCertificateCheck `
            -Path                 "credentials/$CredentialId/resources"

        $resources = $result.resourceList ?? $result.resources ?? $result

        return $resources | ForEach-Object {
            $_ | Add-Member -NotePropertyName 'Success' -NotePropertyValue $true -PassThru
        }
    }
}
