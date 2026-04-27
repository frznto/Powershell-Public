function New-VROpsCredential {
    <#
    .SYNOPSIS
        Creates a new credential instance in vROps.
    .DESCRIPTION
        Calls POST /suite-api/api/credentials to create a new credential instance.
        Use Get-VROpsCredentialKind to discover the AdapterKindKey, CredentialKindKey,
        and required field names for your target adapter type.
    .PARAMETER Name
        Display name for the new credential instance.
    .PARAMETER AdapterKindKey
        The adapter kind this credential belongs to (e.g. 'VMWARE', 'NSXT').
    .PARAMETER CredentialKindKey
        The credential kind key (e.g. 'PRINCIPALCREDENTIAL').
    .PARAMETER Fields
        Hashtable of field name/value pairs for the credential.
        Example: @{ USER = 'svc-account@domain.local'; PASSWORD = 'YourPasswordHere' }
    .PARAMETER Server
        vROps hostname. Defaults to $DefaultOMServers[0].
    .PARAMETER SkipCertificateCheck
        Skip TLS certificate validation on the REST call.
    .EXAMPLE
        New-VROpsCredential -Name 'My VC Credential' -AdapterKindKey 'VMWARE' `
            -CredentialKindKey 'PRINCIPALCREDENTIAL' `
            -Fields @{ USER = 'svc-account@domain.local'; PASSWORD = 'YourPasswordHere' }
    .LINK
        https://developer.broadcom.com/xapis/vmware-vrealize-operations-api/latest/api/credentials/post/
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$AdapterKindKey,

        [Parameter(Mandatory = $true)]
        [string]$CredentialKindKey,

        [Parameter(Mandatory = $true)]
        [hashtable]$Fields,

        [Parameter(Mandatory = $false)]
        [string]$Server,

        [Parameter(Mandatory = $false)]
        [switch]$SkipCertificateCheck
    )

    $body = @{
        name              = $Name
        adapterKindKey    = $AdapterKindKey
        credentialKindKey = $CredentialKindKey
        fields            = @($Fields.GetEnumerator() | ForEach-Object {
            @{ name = $_.Key; value = $_.Value }
        })
    }

    if ($PSCmdlet.ShouldProcess($Name, "Create credential ($AdapterKindKey / $CredentialKindKey)")) {
        $result = Invoke-VROpsApiRequest `
            -Server               $Server `
            -SkipCertificateCheck:$SkipCertificateCheck `
            -Path                 'credentials' `
            -Method               'POST' `
            -Body                 $body

        return $result | Add-Member -NotePropertyName 'Success' -NotePropertyValue $true -PassThru
    }
}
