function Test-VROpsAdapterConnection {
    <#
    .SYNOPSIS
        Tests the connection for an existing vROps adapter instance.
    .DESCRIPTION
        Looks up the adapter via GET /api/adapters/{adapterId}, builds the
        create-adapter-instance body from its definition, then calls
        POST /api/adapters/testConnection.

        HTTP 201 = connection succeeded.
        HTTP 400 = connection failed (bad credentials, unreachable host, etc.).

        If the response includes untrusted certificates in 'adapter-certificates',
        use -AcceptCertificate to automatically accept them and re-test.

        Equivalent curl:
          curl -X POST "https://<host>/api/adapters/testConnection?_no_links=true" \
               -H "accept: application/json" \
               -H "Authorization: OpsToken <token>" \
               -H "Content-Type: application/json" \
               -d '{"adapterKindKey":"...","name":"...","resourceIdentifiers":[...]}'
    .PARAMETER AdapterId
        The ID of the existing adapter instance to test. Accepts pipeline input
        from Get-VROpsAdapterInstance.
    .PARAMETER AcceptCertificate
        Automatically accept any untrusted certificates returned by the connection
        test and re-submit.
    .PARAMETER Server
        vROps hostname. Defaults to $DefaultOMServers[0].
    .PARAMETER SkipCertificateCheck
        Skip TLS certificate validation on the REST call.
    .EXAMPLE
        # Test a specific adapter
        Test-VROpsAdapterConnection -AdapterId 'f3a1b2c3-...'
    .EXAMPLE
        # Test all VCENTER adapters, auto-accepting any untrusted certificates
        Get-VROpsAdapterInstance -AdapterKindKey 'VCENTER' |
            Test-VROpsAdapterConnection -AcceptCertificate
    .LINK
        https://developer.broadcom.com/xapis/vmware-vrealize-operations-api/latest/api/adapters/testConnection/post/
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('id')]
        [string]$AdapterId,

        [Parameter(Mandatory = $false)]
        [switch]$AcceptCertificate,

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

        Write-Verbose "Retrieving adapter '$AdapterId' configuration..."
        $adapter = Invoke-VROpsApiRequest @baseParams -Path "adapters/$AdapterId"

        # Build create-adapter-instance body from the existing adapter definition.
        # resourceIdentifiers: transform GET format { identifierType.name, value }
        #                                to POST format { name, value }
        $body = @{
            adapterKindKey      = $adapter.resourceKey.adapterKindKey
            name                = $adapter.resourceKey.name
            resourceIdentifiers = @($adapter.resourceKey.resourceIdentifiers | ForEach-Object {
                @{ name = $_.identifierType.name; value = $_.value }
            })
        }
        if ($adapter.PSObject.Properties['collectorId']) {
            $body['collectorId'] = [string]$adapter.collectorId
        }
        if ($adapter.PSObject.Properties['credentialInstanceId']) {
            $body['credential'] = @{ id = $adapter.credentialInstanceId }
        }

        Write-Verbose "Testing connection for adapter '$AdapterId' (kind: $($body.adapterKindKey))..."

        $result    = $null
        $succeeded = $false

        try {
            $result    = Invoke-VROpsApiRequest @baseParams -Path 'adapters/testConnection' -Method 'POST' -Body $body
            $succeeded = $true
        }
        catch {
            $succeeded = $false
            $result    = [PSCustomObject]@{ errorMessage = $_.Exception.Message }
        }

        # Handle untrusted certificates returned in the response (adapter-certificates field)
        $certs = $result.PSObject.Properties['adapter-certificates']?.Value

        if ($certs -and $AcceptCertificate) {
            # PATCH /api/adapters/testconnection with the full POST response body.
            # This is the documented way to tell vROps the returned certs are trusted.
            Write-Verbose "Accepting $(@($certs).Count) certificate(s) via PATCH testconnection..."
            try {
                Invoke-VROpsApiRequest @baseParams -Path 'adapters/testconnection' -Method 'PATCH' -Body $result | Out-Null
            }
            catch {
                Write-Verbose "PATCH testconnection returned: $($_.Exception.Message)"
            }

            # Re-test to confirm the connection now succeeds with the accepted certs
            try {
                $result    = Invoke-VROpsApiRequest @baseParams -Path 'adapters/testConnection' -Method 'POST' -Body $body
                $succeeded = $true
            }
            catch {
                $succeeded = $false
                $result    = [PSCustomObject]@{ errorMessage = $_.Exception.Message }
            }
        }
        elseif ($certs -and -not $AcceptCertificate) {
            $thumbprints = ($certs | ForEach-Object { $_.thumbprint ?? $_.certificateThumbprint }) -join ', '
            Write-Warning ("Untrusted certificate(s) found for adapter '$AdapterId'. " +
                           "Thumbprint(s): $thumbprints. " +
                           "Re-run with -AcceptCertificate to accept automatically.")
        }

        $result | Add-Member -NotePropertyName 'Success' -NotePropertyValue $succeeded -Force
        return $result
    }
}
