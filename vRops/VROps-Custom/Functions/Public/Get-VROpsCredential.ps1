function Get-VROpsCredential {
    <#
    .SYNOPSIS
        Retrieves credential instances from vROps.
    .DESCRIPTION
        Calls GET /suite-api/api/credentials to list all credentials, or
        GET /suite-api/api/credentials/{id} to retrieve a specific one.
    .PARAMETER CredentialId
        The ID of a specific credential instance to retrieve.
    .PARAMETER AdapterKindKey
        Filter results to credentials for a specific adapter type (e.g. 'VMWARE').
    .PARAMETER Name
        Filter results by credential name (exact match).
    .PARAMETER Server
        vROps hostname. Defaults to $DefaultOMServers[0].
    .PARAMETER SkipCertificateCheck
        Skip TLS certificate validation on the REST call.
    .EXAMPLE
        Get-VROpsCredential
    .EXAMPLE
        Get-VROpsCredential -CredentialId '23653104-79c1-4943-8f90-532bdc0021da'
    .EXAMPLE
        Get-VROpsCredential -AdapterKindKey 'VMWARE' -Name 'My VC Credential'
    .LINK
        https://developer.broadcom.com/xapis/vmware-vrealize-operations-api/latest/api/credentials/get/
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$CredentialId,

        [Parameter(Mandatory = $false)]
        [string]$AdapterKindKey,

        [Parameter(Mandatory = $false)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$Server,

        [Parameter(Mandatory = $false)]
        [switch]$SkipCertificateCheck
    )

    $baseParams = @{
        Server               = $Server
        SkipCertificateCheck = $SkipCertificateCheck
    }

    if ($CredentialId) {
        $result = Invoke-VROpsApiRequest @baseParams -Path "credentials/$CredentialId"
        return $result | Add-Member -NotePropertyName 'Success' -NotePropertyValue $true -PassThru
    }

    $result = Invoke-VROpsApiRequest @baseParams -Path 'credentials'
    $creds  = $result.credentialInstances ?? $result.credential ?? $result

    if ($AdapterKindKey) {
        $creds = $creds | Where-Object { $_.adapterKindKey -eq $AdapterKindKey }
    }
    if ($Name) {
        $creds = $creds | Where-Object { $_.name -eq $Name }
    }

    return $creds | ForEach-Object {
        $_ | Add-Member -NotePropertyName 'Success' -NotePropertyValue $true -PassThru
    }
}
