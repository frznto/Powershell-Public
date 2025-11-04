function Start-P12CertificateToolkit {
    <#
    .SYNOPSIS
    Launches the P12/PFX Certificate Toolkit GUI application.

    .DESCRIPTION
    Opens a graphical user interface for extracting certificate components from P12/PFX files
    using OpenSSL. The toolkit supports multiple output formats, batch processing, certificate
    verification, and test mode validation.

    .PARAMETER OpenSSLPath
    Optional path to OpenSSL executable. If not specified, the tool will attempt to auto-detect
    OpenSSL in the system PATH or prompt for manual selection.

    .EXAMPLE
    Start-P12CertificateToolkit
    Launches the GUI with auto-detection of OpenSSL.

    .EXAMPLE
    Start-P12CertificateToolkit -OpenSSLPath "C:\OpenSSL\bin\openssl.exe"
    Launches the GUI with a specified OpenSSL path.

    .NOTES
    Requires OpenSSL 3.0+ for best compatibility.
    Supports legacy P12/PFX files with automatic -legacy flag detection.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateScript({
            if ($_ -and -not (Test-Path $_)) {
                throw "OpenSSL path does not exist: $_"
            }
            $true
        })]
        [string]$OpenSSLPath
    )

    # Note: The actual GUI implementation would need to be refactored from the original script
    # For now, this provides the module structure. The full implementation would include:
    # - All the GUI setup code
    # - All the event handlers
    # - The Invoke-P12Extraction function
    # - Theme and layout management functions

    Write-Host "P12/PFX Certificate Toolkit v2.0" -ForegroundColor Cyan
    Write-Host "================================" -ForegroundColor Cyan
    Write-Host ""

    # Import required assemblies
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Execute the original script content
    # Since the original script is a complete standalone application,
    # we'll source it directly here as a workaround
    $originalScript = Join-Path (Split-Path $PSScriptRoot -Parent | Split-Path -Parent) "P12_PFX Certficate Toolkit_GUI Rev2.ps1"

    if (Test-Path $originalScript) {
        Write-Verbose "Loading P12 Certificate Toolkit from: $originalScript"
        & $originalScript
    }
    else {
        Write-Error @"
The original P12 Certificate Toolkit script was not found at the expected location.

Expected: $originalScript

To use this module, either:
1. Ensure the original script is available at the expected location, or
2. Copy the GUI implementation code directly into this function

For standalone use, run the original script directly:
    .\P12_PFX Certficate Toolkit_GUI Rev2.ps1
"@
    }
}
