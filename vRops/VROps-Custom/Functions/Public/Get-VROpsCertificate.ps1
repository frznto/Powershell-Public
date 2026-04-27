function Get-VROpsCertificate {
    <#
    .SYNOPSIS
        Retrieves certificates stored in vROps.
    .DESCRIPTION
        Calls GET /suite-api/api/certificate to return all certificates known to vROps,
        including thumbprint, subject, issuer, validity dates, and which adapters or
        credential instances reference each certificate.

        Equivalent curl:
          curl -X GET "https://<host>/suite-api/api/certificate?_no_links=true" \
               -H "accept: application/json" \
               -H "Authorization: OpsToken <token>"
    .PARAMETER Thumbprint
        Filter the returned list to a specific certificate by thumbprint.
    .PARAMETER Server
        vROps hostname. Defaults to $DefaultOMServers[0].
    .PARAMETER SkipCertificateCheck
        Skip TLS certificate validation on the REST call.
    .EXAMPLE
        # Get all certificates
        Get-VROpsCertificate
    .EXAMPLE
        # Find a certificate by thumbprint
        Get-VROpsCertificate -Thumbprint 'AA:BB:CC:DD:EE:FF'
    .EXAMPLE
        # Look up certs referenced by adapter instances
        Get-VROpsAdapterInstance | Select-Object -ExpandProperty certificateThumbprint |
            ForEach-Object { Get-VROpsCertificate -Thumbprint $_ }
    .LINK
        https://developer.broadcom.com/xapis/vmware-vrealize-operations-api/8.10.0/certificate/
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Thumbprint,

        [Parameter(Mandatory = $false)]
        [string]$Server,

        [Parameter(Mandatory = $false)]
        [switch]$SkipCertificateCheck
    )

    $result = Invoke-VROpsApiRequest `
        -Server               $Server `
        -SkipCertificateCheck:$SkipCertificateCheck `
        -Path                 'certificate'

    # Normalize: response may wrap certs in a collection property depending on vROps version
    $certs = $result.certificates ?? $result.certificateInfoList ?? $result

    if ($Thumbprint) {
        return ($certs | Where-Object {
            $_.thumbprint -eq $Thumbprint -or $_.certificateThumbprint -eq $Thumbprint
        }) | ForEach-Object {
            $_ | Add-Member -NotePropertyName 'Success' -NotePropertyValue $true -PassThru
        }
    }

    return $certs | ForEach-Object {
        $_ | Add-Member -NotePropertyName 'Success' -NotePropertyValue $true -PassThru
    }
}
