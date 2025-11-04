#region Helper Functions

function Get-P12Files {
    <#
    .SYNOPSIS
    Retrieves all .p12 and .pfx files from the specified folder.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $FolderPath,

        [switch]
        $Recurse
    )

    if (-not (Test-Path -LiteralPath $FolderPath)) {
        return @()
    }

    # Primary: fast filters per extension (handles case-insensitivity)
    $common = @{
        LiteralPath = $FolderPath
        File        = $true
        Force       = $true
        ErrorAction = 'SilentlyContinue'
    }

    if ($Recurse) {
        $common.Recurse = $true
    }

    $files = @()
    $files += @(Get-ChildItem @common -Filter '*.p12')
    $files += @(Get-ChildItem @common -Filter '*.pfx')

    # Fallback: filter by Extension (covers weird providers / UNC quirks)
    if ($files.Count -eq 0) {
        $files = Get-ChildItem @common | Where-Object { $_.Extension -match '^\.(p12|pfx)$' }
    }

    return @($files)
}

function Invoke-OpenSSLTest {
    <#
    .SYNOPSIS
    Tests if OpenSSL executable can be invoked and returns version info.
    #>
    param(
        [string]
        $OpenSSLPath
    )

    if (-not $OpenSSLPath -or -not (Test-Path $OpenSSLPath)) {
        return $null
    }

    try {
        & $OpenSSLPath version 2>$null
    }
    catch {
        Write-Verbose "Failed to invoke OpenSSL: $_"
        $null
    }
}

function Test-CAFile {
    <#
    .SYNOPSIS
    Validates that the specified file is a PEM certificate file.
    #>
    param(
        [string]
        $Path
    )

    if (-not (Test-Path $Path)) {
        return $false
    }

    try {
        $firstKB = (Get-Content -Path $Path -TotalCount 50 -ErrorAction Stop)
        return ($firstKB -match '-----BEGIN CERTIFICATE-----')
    }
    catch {
        Write-Verbose "Error reading CA file: $_"
        return $false
    }
}

function Add-Log {
    <#
    .SYNOPSIS
    Adds a log message to the UI and optionally to a log file.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $Message,

        [switch]
        $NoUI
    )

    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $timestampedMessage = "[$ts] $Message"

    # UI sink (ListBox)
    if (-not $NoUI) {
        try {
            if ($null -ne $script:LogBox) {
                [void]$script:LogBox.Items.Add($timestampedMessage)
                $script:LogBox.TopIndex = [Math]::Max(0, $script:LogBox.Items.Count - 1)
            }
        }
        catch {
            Write-Verbose "Error adding to LogBox: $_"
        }
    }

    # File sink
    if ($script:LogToFileEnabled -and $script:LogFilePath) {
        Write-ToLogFile -Message ("[{0}] {1}" -f $ts, $Message)
    }
}

function Write-ToLogFile {
    <#
    .SYNOPSIS
    Writes a message directly to the log file without UI interaction.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $Message
    )

    if ($script:LogFilePath) {
        try {
            Add-Content -LiteralPath $script:LogFilePath -Value $Message -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            Write-Verbose "Error writing to log file: $_"
        }
    }
}

function Limit-PemEnvelope {
    <#
    .SYNOPSIS
    Strips content outside of PEM BEGIN/END markers from a file.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    try {
        $lines = Get-Content -LiteralPath $Path -ErrorAction Stop
        if (-not $lines) {
            return $false
        }

        $beginIdx = $null
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*-----BEGIN\s.+-----\s*$') {
                $beginIdx = $i
                break
            }
        }

        $endIdx = $null
        for ($j = $lines.Count - 1; $j -ge 0; $j--) {
            if ($lines[$j] -match '^\s*-----END\s.+-----\s*$') {
                $endIdx = $j
                break
            }
        }

        if ($beginIdx -eq $null -or $endIdx -eq $null -or $endIdx -lt $beginIdx) {
            return $false
        }

        # Keep only from first BEGIN through last END (inclusive)
        $slice = $lines[$beginIdx..$endIdx]

        # Collapse multiple blank lines at the edges
        while ($slice.Count -gt 0 -and [string]::IsNullOrWhiteSpace($slice[0])) {
            $slice = $slice[1..($slice.Count - 1)]
        }
        while ($slice.Count -gt 0 -and [string]::IsNullOrWhiteSpace($slice[-1])) {
            $slice = $slice[0..($slice.Count - 2)]
        }

        $slice | Set-Content -LiteralPath $Path -Encoding ascii
        return $true
    }
    catch {
        Write-Verbose "Error limiting PEM envelope: $_"
        return $false
    }
}

function Get-OpenSSLVersion {
    <#
    .SYNOPSIS
    Gets the OpenSSL version from the specified executable.
    .OUTPUTS
    Returns a hashtable with Version (string), Major, Minor, Patch (int), and IsValid (bool)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$OpenSSLPath
    )

    try {
        $versionOutput = & $OpenSSLPath version 2>&1 | Out-String

        # Parse version like "OpenSSL 3.0.8 7 Feb 2023" or "OpenSSL 3.6.0 ..."
        if ($versionOutput -match 'OpenSSL\s+(\d+)\.(\d+)\.(\d+)') {
            $major = [int]$matches[1]
            $minor = [int]$matches[2]
            $patch = [int]$matches[3]
            $versionString = "$major.$minor.$patch"

            return @{
                Version = $versionString
                Major = $major
                Minor = $minor
                Patch = $patch
                IsValid = ($major -ge 3)
                FullOutput = $versionOutput.Trim()
            }
        }
    }
    catch {
        Write-Verbose "Error getting OpenSSL version: $_"
    }

    return @{
        Version = "Unknown"
        Major = 0
        Minor = 0
        Patch = 0
        IsValid = $false
        FullOutput = "Unknown"
    }
}

function Test-PEMFile {
    <#
    .SYNOPSIS
    Validates that a file contains valid PEM format markers.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    try {
        $content = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        # Check for PEM markers
        return ($content -match '-----BEGIN [A-Z\s]+-----') -and ($content -match '-----END [A-Z\s]+-----')
    }
    catch {
        Write-Verbose "Error validating PEM file: $_"
        return $false
    }
}

function Test-CertificateFile {
    <#
    .SYNOPSIS
    Verifies an extracted certificate file using OpenSSL.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$OpenSSLPath,

        [Parameter(Mandatory = $true)]
        [ValidateSet('PEM', 'CER', 'KEY')]
        [string]$FileType
    )

    if (-not (Test-Path -LiteralPath $FilePath)) {
        return $false
    }

    try {
        switch ($FileType) {
            'PEM' {
                # Verify X.509 certificate in PEM format
                $null = & $OpenSSLPath x509 -in $FilePath -noout -text 2>&1
                return ($LASTEXITCODE -eq 0)
            }
            'CER' {
                # Verify X.509 certificate in DER format
                $null = & $OpenSSLPath x509 -in $FilePath -inform DER -noout -text 2>&1
                return ($LASTEXITCODE -eq 0)
            }
            'KEY' {
                # Verify private key (RSA or other formats)
                $null = & $OpenSSLPath pkey -in $FilePath -noout -text 2>&1
                return ($LASTEXITCODE -eq 0)
            }
        }
    }
    catch {
        Write-Verbose "Error verifying certificate file: $_"
        return $false
    }

    return $false
}

function Test-P12File {
    <#
    .SYNOPSIS
    Tests if a P12/PFX file is valid and can be read with the given password.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '', Justification='Required for OpenSSL command-line interface')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$OpenSSLPath,

        [Parameter(Mandatory = $true)]
        [string]$Password,

        [string]$ProviderPath = $null
    )

    if (-not (Test-Path -LiteralPath $FilePath)) {
        return @{ IsValid = $false; Message = "File not found" }
    }

    try {
        $passIn = "pass:$Password"

        # Try to list contents without extracting
        if ($ProviderPath) {
            $result = & $OpenSSLPath pkcs12 -in $FilePath -passin $passIn -noout -info -provider-path $ProviderPath 2>&1
        } else {
            $result = & $OpenSSLPath pkcs12 -in $FilePath -passin $passIn -noout -info 2>&1
        }

        if ($LASTEXITCODE -eq 0) {
            return @{ IsValid = $true; Message = "Valid P12 file" }
        }

        # Try with -legacy flag if first attempt failed
        if ($ProviderPath) {
            $result = & $OpenSSLPath pkcs12 -in $FilePath -passin $passIn -noout -info -legacy -provider-path $ProviderPath 2>&1
        } else {
            $result = & $OpenSSLPath pkcs12 -in $FilePath -passin $passIn -noout -info -legacy 2>&1
        }

        if ($LASTEXITCODE -eq 0) {
            return @{ IsValid = $true; Message = "Valid P12 file (legacy format)" }
        }

        $errorMsg = $result | Out-String
        return @{ IsValid = $false; Message = "Invalid P12 file or incorrect password: $errorMsg" }
    }
    catch {
        return @{ IsValid = $false; Message = "Error testing P12 file: $_" }
    }
}

#endregion Helper Functions
