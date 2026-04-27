function Get-VROpsAdapterInstance {
    <#
    .SYNOPSIS
        Retrieves vROps adapter instances.
    .DESCRIPTION
        Calls GET /suite-api/api/adapters to return all adapter instances, or
        GET /suite-api/api/adapters/{adapterId} for a single adapter.

        Equivalent curl:
          curl -X GET "https://<host>/suite-api/api/adapters?_no_links=true" \
               -H "accept: application/json" \
               -H "Authorization: OpsToken <token>"
    .PARAMETER AdapterId
        The ID of a specific adapter instance to retrieve.
    .PARAMETER AdapterKindKey
        Filter by adapter kind key (e.g. 'VMWARE', 'VCENTER', 'ep-ops-agent').
    .PARAMETER ResourceName
        Filter by adapter resource/display name.
    .PARAMETER Server
        vROps hostname. Defaults to $DefaultOMServers[0].
    .PARAMETER SkipCertificateCheck
        Skip TLS certificate validation on the REST call.
    .EXAMPLE
        # Get all adapter instances
        Get-VROpsAdapterInstance
    .EXAMPLE
        # Get a single adapter by ID
        Get-VROpsAdapterInstance -AdapterId 'f3a1b2c3-...'
    .EXAMPLE
        # Filter by adapter kind
        Get-VROpsAdapterInstance -AdapterKindKey 'VCENTER'
    .LINK
        https://developer.broadcom.com/xapis/vmware-vrealize-operations-api/8.10.0/adapters/
    #>
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ById', ValueFromPipelineByPropertyName = $true)]
        [string]$AdapterId,

        [Parameter(Mandatory = $false, ParameterSetName = 'All')]
        [string]$AdapterKindKey,

        [Parameter(Mandatory = $false, ParameterSetName = 'All')]
        [string]$ResourceName,

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

        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            $obj = Invoke-VROpsApiRequest @baseParams -Path "adapters/$AdapterId"
            return $obj | Add-Member -NotePropertyName 'Success' -NotePropertyValue $true -PassThru
        }

        $query = @{}
        if ($AdapterKindKey) { $query['adapterKindKey'] = $AdapterKindKey }
        if ($ResourceName)   { $query['name']           = $ResourceName   }

        $result = Invoke-VROpsApiRequest @baseParams -Path 'adapters' -QueryParameters $query
        return $result.adapterInstancesInfoDto | ForEach-Object {
            $_ | Add-Member -NotePropertyName 'Success' -NotePropertyValue $true -PassThru
        }
    }
}
