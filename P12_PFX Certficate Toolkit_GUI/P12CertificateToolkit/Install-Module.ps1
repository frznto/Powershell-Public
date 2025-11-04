<#
.SYNOPSIS
Installs the P12CertificateToolkit module to the user's PowerShell module directory.

.DESCRIPTION
This script copies the P12CertificateToolkit module to the appropriate PowerShell
module directory and verifies the installation.

.PARAMETER Scope
Specifies the installation scope. Valid values are:
- CurrentUser: Installs for the current user only (default)
- AllUsers: Installs for all users (requires Administrator)

.EXAMPLE
.\Install-Module.ps1
Installs the module for the current user.

.EXAMPLE
.\Install-Module.ps1 -Scope AllUsers
Installs the module for all users (requires Administrator).

.NOTES
Author: FrznDad
Version: 2.0.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('CurrentUser', 'AllUsers')]
    [string]$Scope = 'CurrentUser'
)

# Get the source directory (where this script is located)
$sourceDir = $PSScriptRoot

# Determine target installation directory
if ($Scope -eq 'AllUsers') {
    # Check if running as Administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Error "Installing for AllUsers requires Administrator privileges. Please run PowerShell as Administrator."
        exit 1
    }

    $targetDir = Join-Path $env:ProgramFiles "PowerShell\Modules\P12CertificateToolkit"
}
else {
    # Current user installation
    $documentsPath = [Environment]::GetFolderPath('MyDocuments')
    $targetDir = Join-Path $documentsPath "PowerShell\Modules\P12CertificateToolkit"
}

Write-Host "P12/PFX Certificate Toolkit - Module Installation" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Source:      $sourceDir" -ForegroundColor Yellow
Write-Host "Destination: $targetDir" -ForegroundColor Yellow
Write-Host "Scope:       $Scope" -ForegroundColor Yellow
Write-Host ""

# Confirm installation
$confirmation = Read-Host "Proceed with installation? (Y/N)"
if ($confirmation -ne 'Y' -and $confirmation -ne 'y') {
    Write-Host "Installation cancelled." -ForegroundColor Yellow
    exit 0
}

# Create target directory if it doesn't exist
if (-not (Test-Path $targetDir)) {
    Write-Host "Creating module directory..." -ForegroundColor Green
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

# Copy module files
Write-Host "Copying module files..." -ForegroundColor Green
try {
    Copy-Item -Path "$sourceDir\*" -Destination $targetDir -Recurse -Force -Exclude "Install-Module.ps1"
    Write-Host "Module files copied successfully." -ForegroundColor Green
}
catch {
    Write-Error "Failed to copy module files: $_"
    exit 1
}

# Verify installation
Write-Host ""
Write-Host "Verifying installation..." -ForegroundColor Green

# Remove any cached versions
Remove-Module P12CertificateToolkit -ErrorAction SilentlyContinue

# Import the module
Import-Module P12CertificateToolkit -Force

# Check if module loaded correctly
$module = Get-Module P12CertificateToolkit
if ($module) {
    Write-Host ""
    Write-Host "Installation successful!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Module Information:" -ForegroundColor Cyan
    Write-Host "  Name:        $($module.Name)" -ForegroundColor White
    Write-Host "  Version:     $($module.Version)" -ForegroundColor White
    Write-Host "  Path:        $($module.ModuleBase)" -ForegroundColor White
    Write-Host "  Commands:    $($module.ExportedCommands.Keys -join ', ')" -ForegroundColor White
    Write-Host ""
    Write-Host "To launch the toolkit, run:" -ForegroundColor Yellow
    Write-Host "  Start-P12CertificateToolkit" -ForegroundColor White
    Write-Host ""
    Write-Host "To add to your PowerShell profile (auto-load on startup):" -ForegroundColor Yellow
    Write-Host "  Add-Content -Path `$PROFILE -Value 'Import-Module P12CertificateToolkit'" -ForegroundColor White
}
else {
    Write-Error "Module installation verification failed. The module was not loaded correctly."
    exit 1
}
