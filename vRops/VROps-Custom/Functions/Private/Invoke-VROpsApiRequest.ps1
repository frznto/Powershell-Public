function Invoke-VROpsApiRequest {
    <#
        Internal helper. Builds and executes an authenticated REST call against
        the vROps Suite API using the OpsToken from the active OMServer session.

        Reference: GET https://<host>/suite-api/api/...
                   Header: Authorization: OpsToken <SessionSecret>
                   Header: Accept: application/json
                   Query:  _no_links=true (always appended)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE')]
        [string]$Method = 'GET',

        [Parameter(Mandatory = $false)]
        [object]$Body,

        [Parameter(Mandatory = $false)]
        [hashtable]$QueryParameters = @{},

        [Parameter(Mandatory = $false)]
        [switch]$SkipCertificateCheck
    )

    $conn      = Get-VROpsActiveConnection -Server $Server
    $vropsHost = $conn.Name
    $token     = $conn.SessionSecret

    if ([string]::IsNullOrEmpty($token)) {
        throw "Unable to retrieve session token from OMServer connection '$vropsHost'. Ensure Connect-OMServer succeeded."
    }

    # Always strip HATEOAS links for cleaner output
    $QueryParameters['_no_links'] = 'true'

    $queryString = ($QueryParameters.GetEnumerator() | ForEach-Object {
        [uri]::EscapeDataString($_.Key) + '=' + [uri]::EscapeDataString($_.Value)
    }) -join '&'

    $uri = "https://$vropsHost/suite-api/api/$Path`?$queryString"

    $headers = @{
        'Authorization' = "OpsToken $token"
        'Accept'        = 'application/json'
        'Content-Type'  = 'application/json'
    }

    $invokeParams = @{
        Uri                  = $uri
        Method               = $Method
        Headers              = $headers
        SkipCertificateCheck = $SkipCertificateCheck.IsPresent
    }

    if ($null -ne $Body) {
        $invokeParams['Body'] = ($Body | ConvertTo-Json -Depth 20 -Compress)
    }

    Write-Verbose "$Method $uri"

    try {
        Invoke-RestMethod @invokeParams
    }
    catch {
        $status  = $_.Exception.Response?.StatusCode.value__ ?? 'N/A'
        $message = $_.ErrorDetails.Message ?? $_.Exception.Message
        throw "vROps API error [$status] on $Method $uri`n$message"
    }
}
