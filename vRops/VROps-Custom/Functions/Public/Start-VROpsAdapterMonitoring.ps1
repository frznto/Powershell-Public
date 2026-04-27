function Start-VROpsAdapterMonitoring {
    <#
    .SYNOPSIS
        Starts monitoring for a vROps adapter instance.
    .DESCRIPTION
        Calls PUT /suite-api/api/adapters/{adapterId}/monitoringstate/start.
    .PARAMETER AdapterId
        The ID of the adapter instance.
    .PARAMETER Server
        vROps hostname. Defaults to $DefaultOMServers[0].
    .PARAMETER SkipCertificateCheck
        Skip TLS certificate validation on the REST call.
    .EXAMPLE
        Start-VROpsAdapterMonitoring -AdapterId 'f3a1b2c3-...'
    .EXAMPLE
        Get-VROpsAdapterInstance -AdapterKindKey 'VCENTER' | Start-VROpsAdapterMonitoring
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
        if ($PSCmdlet.ShouldProcess($AdapterId, 'Start adapter monitoring')) {
            $result = Invoke-VROpsApiRequest -Server $Server -SkipCertificateCheck:$SkipCertificateCheck `
                -Path   "adapters/$AdapterId/monitoringstate/start" `
                -Method 'PUT'
            return $result | Add-Member -NotePropertyName 'Success' -NotePropertyValue $true -PassThru
        }
    }
}
