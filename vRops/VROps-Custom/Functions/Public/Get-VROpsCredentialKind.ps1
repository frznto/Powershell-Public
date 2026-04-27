function Get-VROpsCredentialKind {
    <#
    .SYNOPSIS
        Retrieves credential kinds available in vROps.
    .DESCRIPTION
        Calls GET /suite-api/api/credentialkinds to return all credential types
        known to vROps, including the field definitions required for each kind.
    .PARAMETER AdapterKindKey
        Filter results to credential kinds for a specific adapter type (e.g. 'VMWARE').
    .PARAMETER Server
        vROps hostname. Defaults to $DefaultOMServers[0].
    .PARAMETER SkipCertificateCheck
        Skip TLS certificate validation on the REST call.
    .EXAMPLE
        Get-VROpsCredentialKind
    .EXAMPLE
        Get-VROpsCredentialKind -AdapterKindKey 'VMWARE'
    .LINK
        https://developer.broadcom.com/xapis/vmware-vrealize-operations-api/latest/api/credentialkinds/get/
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$AdapterKindKey,

        [Parameter(Mandatory = $false)]
        [string]$Server,

        [Parameter(Mandatory = $false)]
        [switch]$SkipCertificateCheck
    )

    $result = Invoke-VROpsApiRequest `
        -Server               $Server `
        -SkipCertificateCheck:$SkipCertificateCheck `
        -Path                 'credentialkinds'

    $kinds = $result.PSObject.Properties['credentialTypes']?.Value ?? $result

    if ($AdapterKindKey) {
        $kinds = $kinds | Where-Object { $_.adapterKindKey -eq $AdapterKindKey }
    }

    return $kinds | ForEach-Object {
        $_ | Add-Member -NotePropertyName 'Success' -NotePropertyValue $true -PassThru
    }
}

