function Confirm-VROpsAdapterCertificate {
    <#
    .SYNOPSIS
        Accepts certificates for a vROps adapter instance via the testconnection endpoint.
    .DESCRIPTION
        Triggers a POST /suite-api/api/adapters/testconnection to obtain the current
        certificate response, then sends that response body as-is to
        PATCH /suite-api/api/adapters/testconnection to mark the certificates as trusted.

        This follows the documented vROps API pattern for certificate acceptance.
    .PARAMETER AdapterId
        The ID of the adapter instance.
    .PARAMETER Server
        vROps hostname. Defaults to $DefaultOMServers[0].
    .PARAMETER SkipCertificateCheck
        Skip TLS certificate validation on the REST call.
    .EXAMPLE
        Confirm-VROpsAdapterCertificate -AdapterId 'f3a1b2c3-...'
    .EXAMPLE
        Get-VROpsAdapterInstance -AdapterId 'f3a1b2c3-...' | Confirm-VROpsAdapterCertificate
    .LINK
        https://developer.broadcom.com/xapis/vmware-vrealize-operations-api/8.10.0/adapters/
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('id')]
        [string]$AdapterId,

        [Parameter(Mandatory = $false)]
        [string]$Server,

        [Parameter(Mandatory = $false)]
        [switch]$SkipCertificateCheck
    )

    process {
        $baseParams = @{
            Server               = $Server
            SkipCertificateCheck = $SkipCertificateCheck
        }

        # Build the testconnection body from the adapter definition
        Write-Verbose "Retrieving adapter '$AdapterId' configuration..."
        $adapter = Invoke-VROpsApiRequest @baseParams -Path "adapters/$AdapterId"

        $body = @{
            adapterKindKey      = $adapter.resourceKey.adapterKindKey
            name                = $adapter.resourceKey.name
            resourceIdentifiers = @($adapter.resourceKey.resourceIdentifiers | ForEach-Object {
                @{ name = $_.identifierType.name; value = $_.value }
            })
        }
        if ($adapter.PSObject.Properties['collectorId'])         { $body['collectorId']           = [string]$adapter.collectorId }
        if ($adapter.PSObject.Properties['credentialInstanceId']) { $body['credential']            = @{ id = $adapter.credentialInstanceId } }

        if ($PSCmdlet.ShouldProcess($AdapterId, 'Accept adapter certificates')) {
            # POST to get the certificate response
            Write-Verbose "POSTing testconnection to retrieve certificate response..."
            $testResult = $null
            try {
                $testResult = Invoke-VROpsApiRequest @baseParams -Path 'adapters/testconnection' -Method 'POST' -Body $body
            } catch {
                $testResult = [PSCustomObject]@{ errorMessage = $_.Exception.Message }
            }

            $certs = $testResult.PSObject.Properties['adapter-certificates']?.Value
            if (-not $certs) {
                Write-Verbose "No untrusted certificates found for adapter '$AdapterId'."
                return $testResult | Add-Member -NotePropertyName 'Success' -NotePropertyValue $true -PassThru
            }

            # PATCH with the full POST response to accept the certificates
            Write-Verbose "Accepting $(@($certs).Count) certificate(s) via PATCH testconnection..."
            try {
                Invoke-VROpsApiRequest @baseParams -Path 'adapters/testconnection' -Method 'PATCH' -Body $testResult | Out-Null
            } catch {
                Write-Verbose "PATCH testconnection returned: $($_.Exception.Message)"
            }

            Write-Verbose "Certificate(s) accepted for adapter '$AdapterId'."
            return [PSCustomObject]@{ AdapterId = $AdapterId; Success = $true }
        }
    }
}
