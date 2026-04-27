function Update-VROpsAdapterInstance {
    <#
    .SYNOPSIS
        Updates properties on a vROps adapter instance.
    .DESCRIPTION
        Retrieves the current adapter via GET /suite-api/api/adapters/{adapterId},
        applies the provided property changes, then submits the updated object via
        PUT /suite-api/api/adapters.
    .PARAMETER AdapterId
        The ID of the adapter instance to update.
    .PARAMETER Properties
        A hashtable of top-level adapter resource properties to set.
        Example: @{ collectorId = 2; 'resourceKey.name' = 'NewName' }
    .PARAMETER Server
        vROps hostname. Defaults to $DefaultOMServers[0].
    .PARAMETER SkipCertificateCheck
        Skip TLS certificate validation on the REST call.
    .EXAMPLE
        Update-VROpsAdapterInstance -AdapterId 'f3a1b2c3-...' -Properties @{ collectorId = 2 }
    .LINK
        https://developer.broadcom.com/xapis/vmware-vrealize-operations-api/8.10.0/adapters/
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('id')]
        [string]$AdapterId,

        [Parameter(Mandatory = $true)]
        [hashtable]$Properties,

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

        Write-Verbose "Retrieving adapter '$AdapterId' for update..."
        $adapter = Invoke-VROpsApiRequest @baseParams -Path "adapters/$AdapterId"

        foreach ($key in $Properties.Keys) {
            $adapter.$key = $Properties[$key]
        }

        if ($PSCmdlet.ShouldProcess($AdapterId, 'Update adapter instance')) {
            $result = Invoke-VROpsApiRequest @baseParams `
                -Path   'adapters' `
                -Method 'PUT' `
                -Body   $adapter
            return $result | Add-Member -NotePropertyName 'Success' -NotePropertyValue $true -PassThru
        }
    }
}
