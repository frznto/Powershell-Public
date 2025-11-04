@{
    # Script module or binary module file associated with this manifest
    RootModule = 'P12CertificateToolkit.psm1'

    # Version number of this module
    ModuleVersion = '2.0.0'

    # ID used to uniquely identify this module
    GUID = 'a1b2c3d4-e5f6-4789-a1b2-c3d4e5f67890'

    # Author of this module
    Author = 'FrznDad'

    # Company or vendor of this module
    CompanyName = 'Personal'

    # Copyright statement for this module
    Copyright = '(c) 2025. All rights reserved.'

    # Description of the functionality provided by this module
    Description = @'
P12/PFX Certificate Toolkit - A comprehensive GUI application for extracting and managing
certificate components from P12/PFX files using OpenSSL.

Features:
- Extract PEM, CER, and KEY files from P12/PFX certificates
- Optional key encryption with custom password support
- CA chain appending for PEM files
- Dark mode UI support
- Batch processing with progress tracking
- Verbose transcript logging
- Test Mode: Validate P12 files without extracting
- Certificate verification after extraction
- Automatic legacy provider detection for portable OpenSSL installations
- OpenSSL version validation and compatibility warnings
'@

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules = @()

    # Assemblies that must be loaded prior to importing this module
    RequiredAssemblies = @(
        'System.Windows.Forms',
        'System.Drawing'
    )

    # Functions to export from this module
    FunctionsToExport = @(
        'Start-P12CertificateToolkit'
    )

    # Cmdlets to export from this module
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData = @{
        PSData = @{
            # Tags applied to this module for discoverability
            Tags = @('Certificate', 'P12', 'PFX', 'OpenSSL', 'GUI', 'Extract', 'Crypto', 'PKI')

            # A URL to the license for this module
            LicenseUri = ''

            # A URL to the main website for this project
            ProjectUri = 'https://github.com/FrznDad/Personal-Scripts'

            # ReleaseNotes of this module
            ReleaseNotes = @'
Version 2.0.0
- Converted standalone script to PowerShell module
- Added proper module structure with manifest
- Improved code organization with Public/Private separation
- Added comprehensive documentation
- Enhanced error handling and validation
- OpenSSL 3.x legacy provider support with auto-detection
- Certificate verification functionality
- Test Mode for P12 file validation
- Auto-open transcript on errors
'@
        }
    }
}
