#Requires -Version 5.1

<#
.SYNOPSIS
P12/PFX Certificate Toolkit PowerShell Module

.DESCRIPTION
This module provides a comprehensive GUI application for extracting and managing
certificate components from P12/PFX files using OpenSSL.

.NOTES
Author: FrznDad
Version: 2.0.0
#>

# Get the module root path
$ModuleRoot = $PSScriptRoot

# Dot source all private functions
$PrivateFunctions = @(Get-ChildItem -Path "$ModuleRoot\Private\*.ps1" -ErrorAction SilentlyContinue)
foreach ($file in $PrivateFunctions) {
    try {
        . $file.FullName
    }
    catch {
        Write-Error "Failed to import private function $($file.FullName): $_"
    }
}

# Dot source all public functions
$PublicFunctions = @(Get-ChildItem -Path "$ModuleRoot\Public\*.ps1" -ErrorAction SilentlyContinue)
foreach ($file in $PublicFunctions) {
    try {
        . $file.FullName
    }
    catch {
        Write-Error "Failed to import public function $($file.FullName): $_"
    }
}

# Export public functions
Export-ModuleMember -Function 'Start-P12CertificateToolkit'
