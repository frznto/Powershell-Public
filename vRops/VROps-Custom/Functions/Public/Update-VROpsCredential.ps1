function Update-VROpsCredential {
    <#
    .SYNOPSIS
        Updates an existing credential instance in vROps.
    .DESCRIPTION
        Retrieves the credential via GET /suite-api/api/credentials/{id}, applies the
        requested changes, then submits the full updated object via PUT /suite-api/api/credentials.

        Use -Fields to update specific credential fields (e.g. a password rotation) without
        needing to supply all fields. Fields not included in -Fields are left unchanged.

        Note: vROps does not return sensitive field values (e.g. passwords) in GET responses.
        Those fields are preserved opaquely on the server during the PUT.
    .PARAMETER CredentialId
        The ID of the credential instance to update. Accepts pipeline input from
        Get-VROpsCredential.
    .PARAMETER Name
        New display name for the credential. Omit to keep the existing name.
    .PARAMETER Fields
        Hashtable of field name/value pairs to update.
        Example: @{ PASSWORD = 'NewPassword123' }
        Fields not listed here are left unchanged.
    .PARAMETER Server
        vROps hostname. Defaults to $DefaultOMServers[0].
    .PARAMETER SkipCertificateCheck
        Skip TLS certificate validation on the REST call.
    .EXAMPLE
        # Rotate the password on a specific credential
        Update-VROpsCredential -CredentialId '23653104-...' -Fields @{ PASSWORD = 'NewPass!' }
    .EXAMPLE
        # Pipe from Get-VROpsCredential
        Get-VROpsCredential -Name 'My VC Credential' |
            Update-VROpsCredential -Fields @{ PASSWORD = 'NewPass!' }
    .LINK
        https://developer.broadcom.com/xapis/vmware-vrealize-operations-api/latest/api/credentials/put/
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('id')]
        [string]$CredentialId,

        [Parameter(Mandatory = $false)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [hashtable]$Fields,

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

        Write-Verbose "Retrieving credential '$CredentialId' for update..."
        $credential = Invoke-VROpsApiRequest @baseParams -Path "credentials/$CredentialId"

        if ($Name) {
            $credential.name = $Name
        }

        if ($Fields) {
            # Rebuild fields array: update matched entries, preserve the rest.
            # vROps omits the 'value' key on sensitive fields (e.g. PASSWORD) in GET
            # responses — use PSObject.Properties to avoid StrictMode throws.
            $updatedFields = [System.Collections.Generic.List[hashtable]]::new()

            foreach ($f in $credential.fields) {
                $existingValue = $f.PSObject.Properties['value']?.Value
                $newValue      = $Fields.ContainsKey($f.name) ? $Fields[$f.name] : $existingValue
                $entry         = @{ name = $f.name }
                if ($null -ne $newValue) { $entry['value'] = $newValue }
                $updatedFields.Add($entry)
            }

            # Add any brand-new fields not present in the original credential
            foreach ($key in $Fields.Keys) {
                if (-not ($credential.fields | Where-Object { $_.name -eq $key })) {
                    $updatedFields.Add(@{ name = $key; value = $Fields[$key] })
                }
            }

            $credential.fields = $updatedFields.ToArray()
        }

        if ($PSCmdlet.ShouldProcess($CredentialId, 'Update credential')) {
            $result = Invoke-VROpsApiRequest @baseParams `
                -Path   'credentials' `
                -Method 'PUT' `
                -Body   $credential

            return $result | Add-Member -NotePropertyName 'Success' -NotePropertyValue $true -PassThru
        }
    }
}
