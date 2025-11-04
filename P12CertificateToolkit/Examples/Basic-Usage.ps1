<#
.SYNOPSIS
Basic usage examples for the P12/PFX Certificate Toolkit module.

.DESCRIPTION
This script demonstrates various ways to use the P12CertificateToolkit module
for extracting and managing certificate components from P12/PFX files.
#>

# Example 1: Basic launch with auto-detection
# ============================================
Write-Host "Example 1: Launch with auto-detection" -ForegroundColor Cyan
Write-Host "--------------------------------------" -ForegroundColor Cyan
Import-Module P12CertificateToolkit -Force
Start-P12CertificateToolkit


# Example 2: Launch with specific OpenSSL path
# =============================================
Write-Host "`nExample 2: Launch with specific OpenSSL path" -ForegroundColor Cyan
Write-Host "---------------------------------------------" -ForegroundColor Cyan
Import-Module P12CertificateToolkit -Force
Start-P12CertificateToolkit -OpenSSLPath "C:\OpenSSL\bin\openssl.exe"


# Example 3: Launch with portable OpenSSL
# ========================================
Write-Host "`nExample 3: Launch with portable OpenSSL" -ForegroundColor Cyan
Write-Host "---------------------------------------" -ForegroundColor Cyan
Import-Module P12CertificateToolkit -Force
$portableOpenSSL = "C:\Tools\openssl-3.0.8\x64\bin\openssl.exe"
if (Test-Path $portableOpenSSL) {
    Start-P12CertificateToolkit -OpenSSLPath $portableOpenSSL
} else {
    Write-Warning "Portable OpenSSL not found at: $portableOpenSSL"
}


# Example 4: Verify module is loaded correctly
# =============================================
Write-Host "`nExample 4: Verify module information" -ForegroundColor Cyan
Write-Host "------------------------------------" -ForegroundColor Cyan
Get-Module P12CertificateToolkit | Format-List Name, Version, Description, ExportedCommands


# Example 5: Get help for the main function
# ==========================================
Write-Host "`nExample 5: View command help" -ForegroundColor Cyan
Write-Host "----------------------------" -ForegroundColor Cyan
Get-Help Start-P12CertificateToolkit -Full


# Example 6: Check if OpenSSL is available in PATH
# =================================================
Write-Host "`nExample 6: Check OpenSSL availability" -ForegroundColor Cyan
Write-Host "-------------------------------------" -ForegroundColor Cyan
$opensslCmd = Get-Command openssl -ErrorAction SilentlyContinue
if ($opensslCmd) {
    Write-Host "OpenSSL found in PATH: $($opensslCmd.Source)" -ForegroundColor Green
    & openssl version
} else {
    Write-Warning "OpenSSL not found in PATH. You'll need to specify the path manually."
}


# Workflow Example
# ================
<#
Typical workflow for using the toolkit:

1. Launch the toolkit:
   Start-P12CertificateToolkit

2. In the GUI:
   a. Click "Select OpenSSL Folder..." if needed
   b. Click "Browse..." to select folder with P12/PFX files
   c. Enter the P12 password
   d. Select desired extraction formats:
      - [x] Extract PEM (certificate + chain)
      - [x] Extract CER (binary certificate)
      - [x] Extract Key (private key)

   e. Optional settings:
      - [x] Encrypt Private Key (with new password)
      - [x] Strip Headers (clean output)
      - [x] Append CA Chain (for PEM)
      - [x] Verbose Transcript (detailed logging)
      - [x] Verify extracted certificates
      - [x] Auto-open transcript when errors occur

   f. Choose action:
      - Click "Start Extraction" to extract certificates
      - Click "Test P12 Files" to validate without extracting

   g. Monitor progress in the log window

   h. Click "Open Extracted Folder" when complete

3. Output location:
   - All extracted files are placed in: [SourceFolder]\Extracted\
   - Transcript logs: [SourceFolder]\Extracted\Transcript_YYYY-MM-DD_HH-mm-ss.log
   - Extraction logs: [SourceFolder]\Extracted\ExtractLog_YYYY-MM-DD_HH-mm-ss.txt
#>


# Advanced Example: Module Installation
# ======================================
<#
To install the module for all users:

# Run PowerShell as Administrator
$modulePath = "C:\Program Files\PowerShell\Modules\P12CertificateToolkit"
Copy-Item -Path ".\P12CertificateToolkit" -Destination $modulePath -Recurse -Force

# Verify installation
Get-Module -ListAvailable P12CertificateToolkit

To install for current user only:

$modulePath = "$HOME\Documents\PowerShell\Modules\P12CertificateToolkit"
Copy-Item -Path ".\P12CertificateToolkit" -Destination $modulePath -Recurse -Force

# Add to profile for auto-loading (optional)
Add-Content -Path $PROFILE -Value "`nImport-Module P12CertificateToolkit"
#>


# Troubleshooting Example
# ========================
<#
If you encounter issues:

1. Check PowerShell version (requires 5.1+):
   $PSVersionTable.PSVersion

2. Verify OpenSSL installation:
   & "C:\Path\To\openssl.exe" version

3. Test OpenSSL 3.x legacy provider:
   & "C:\Path\To\openssl.exe" list -providers

4. Check for legacy.dll:
   Test-Path "C:\Path\To\ossl-modules\legacy.dll"

5. Enable verbose transcript in the GUI for detailed logs

6. Check transcript file for OpenSSL command details
#>
