function Get-VROpsActiveConnection {
    <#
        Internal helper. Returns the active OMServer connection object from
        $DefaultOMServers, optionally filtered by hostname.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Server
    )

    $connections = $global:DefaultOMServers

    if (-not $connections -or $connections.Count -eq 0) {
        throw "No active vROps connection found. Run Connect-OMServer first."
    }

    if ($Server) {
        $conn = $connections | Where-Object { $_.Name -eq $Server } | Select-Object -First 1
        if (-not $conn) {
            throw "No active connection found for server '$Server'. Run Connect-OMServer -Server '$Server' first."
        }
        return $conn
    }

    return $connections[0]
}
