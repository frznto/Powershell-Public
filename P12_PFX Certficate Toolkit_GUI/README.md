# P12/PFX Certificate Toolkit

A comprehensive PowerShell GUI application for extracting and managing certificate components from P12/PFX files using OpenSSL.

## Features

- **Multiple Output Formats**: Extract PEM, CER, and KEY files
- **Key Encryption**: Optional key encryption with custom password support; key password auto-populates from P12 password
- **CA Chain Management**: Append CA certificate chains to PEM files
- **Append Private Key to PEM**: Optionally combine the private key directly into the PEM file
- **Dark Mode**: User-friendly dark and light theme support
- **Batch Processing**: Process multiple P12/PFX files with progress tracking
- **Verbose Logging**: Timestamped transcript logging for troubleshooting; separate log files for extraction and test runs
- **Test Mode**: Validate P12 files without extracting
- **Certificate Verification**: Verify extracted certificates using OpenSSL with inline per-file results
- **Legacy Support**: Automatic detection and support for legacy P12/PFX formats with enhanced retry logic
- **Portable OpenSSL**: Auto-detection of legacy provider in portable OpenSSL installations (checks three locations)
- **Version Validation**: OpenSSL version checking with compatibility warnings
- **Output Folder Conflict Handling**: Prompts to overwrite, create a timestamped folder, or cancel when the output folder already exists
- **Open Extracted Folder**: Button appears after extraction completes to open the output folder directly
- **Responsive UI**: Auto-scaling button layout and form title updates during operations

## Requirements

- **PowerShell**: Version 5.1 or higher
- **OpenSSL**: Version 3.0+ recommended (legacy formats supported)
- **Windows**: Windows Forms and .NET Framework

## Installation

### Option 1: Module Installation (Recommended)

1. Clone or download this repository
2. Copy the `P12CertificateToolkit` folder to one of your PowerShell module paths:
   ```powershell
   # View your module paths
   $env:PSModulePath -split ';'

   # Recommended location (current user)
   Copy-Item -Path ".\P12CertificateToolkit" -Destination "$HOME\Documents\PowerShell\Modules\" -Recurse
   ```

3. Import the module:
   ```powershell
   Import-Module P12CertificateToolkit
   ```

4. Launch the toolkit:
   ```powershell
   Start-P12CertificateToolkit
   ```

### Option 2: Standalone Script

Simply run the original script directly:
```powershell
.\P12_PFX Certficate Toolkit_GUI.ps1
```

## Usage

### Basic Usage

```powershell
# Import the module
Import-Module P12CertificateToolkit

# Launch the GUI
Start-P12CertificateToolkit

# Launch with specific OpenSSL path
Start-P12CertificateToolkit -OpenSSLPath "C:\OpenSSL\bin\openssl.exe"
```

### GUI Workflow

1. **Select OpenSSL**: The toolkit will auto-detect OpenSSL or prompt you to select it manually
2. **Choose Folder**: Select the folder containing your P12/PFX files
3. **Enter Password**: Provide the P12/PFX file password
4. **Configure Options**:
   - Select extraction formats (PEM, CER, KEY)
   - Enable key encryption if desired (key password auto-populates from P12 password)
   - Append private key to PEM file (optional)
   - Strip headers from output files (optional)
   - Append CA chain to PEM files (optional)
   - Enable verbose transcript logging
   - Enable certificate verification
   - Auto-open transcript on errors
5. **Start Extraction** or **Test P12 Files**: Begin processing or validation
6. **Monitor Progress**: View real-time progress and detailed logs
7. **Open Extracted Folder**: Click the button that appears after extraction to open the output folder

### Test Mode

Test Mode validates P12/PFX files without extracting contents:

1. Configure folder and password
2. Click **Test P12 Files** button
3. Review validation results in the log

This is useful for:
- Verifying P12 file integrity
- Checking password correctness
- Identifying legacy format files

### Certificate Verification

Enable **Verify extracted certificates** to automatically validate extracted files using OpenSSL:
- PEM files: Validated as X.509 certificates
- CER files: Validated as DER-format certificates
- KEY files: Validated as private keys

Verification results appear in the log with ✓ (success) or ✗ (failure) indicators.

## Configuration Options

### Extraction Formats

- **PEM**: Privacy-Enhanced Mail format (Base64-encoded, human-readable)
- **CER**: Binary DER format (machine-readable)
- **KEY**: Private key file

### Advanced Options

- **Encrypt Private Key**: Re-encrypt extracted keys with a different password (auto-populates with P12 password)
- **Append Private Key to PEM**: Combine the private key into the PEM file before any CA chain
- **Strip Headers**: Remove extra headers/footers from output files (keep only BEGIN/END markers)
- **Append CA Chain**: Append CA certificate chain to PEM certificate files
- **Dark Mode**: Toggle between light and dark UI themes
- **Log to File**: Save extraction log to a text file
- **Verbose Transcript**: Create timestamped transcript of all OpenSSL operations (separate files for extraction and test runs)
- **Auto-open Transcript**: Automatically open transcript in Notepad when errors occur
- **Output Folder Conflict**: When an `Extracted` folder already exists, choose to overwrite it, create a new timestamped folder (`Extracted_yyyy-MM-dd_HH-mm-ss`), or cancel

## OpenSSL Compatibility

### Version Requirements

- **OpenSSL 3.0+**: Recommended for full feature support
- **OpenSSL 1.x**: Supported but legacy P12 files may have issues
- **Warnings**: The toolkit will warn if OpenSSL version < 3.0 is detected

### Legacy Provider Support

For old P12/PFX files that require the legacy provider:

1. The toolkit automatically detects the `legacy.dll` module in:
   - `openssl.exe` directory
   - Parent directory
   - `../lib/ossl-modules` (typical installation structure)

2. If detected, `-provider-path` is automatically added to OpenSSL commands

3. The toolkit retries failed extractions with `-legacy` flag automatically, with status messages indicating when legacy mode was used

### Portable OpenSSL

Portable OpenSSL installations are fully supported. Place `openssl.exe` in:
```
openssl-VERSION/
├── x64/
│   ├── bin/
│   │   └── openssl.exe
│   └── lib/
│       └── ossl-modules/
│           └── legacy.dll
```

The toolkit will auto-detect the legacy provider location.

## Troubleshooting

### OpenSSL Not Found

**Problem**: "OpenSSL not found in PATH"

**Solutions**:
1. Install OpenSSL and add to system PATH
2. Click "Select OpenSSL Folder..." and browse to `openssl.exe`
3. Use portable OpenSSL and point to the executable

### Legacy P12 Files Fail

**Problem**: "Error extracting, retrying with -legacy flag..."

**Solutions**:
1. Ensure OpenSSL 3.0+ is installed
2. Verify `legacy.dll` exists in `ossl-modules` folder
3. Check the verbose transcript for detailed error messages
4. Enable "Verbose Transcript" and "Auto-open Transcript" for debugging

### Empty Output Files

**Problem**: Extraction succeeds but files are empty

**Solutions**:
1. Verify the password is correct
2. Check the P12 file integrity (use Test Mode)
3. Review the transcript log for OpenSSL errors
4. Ensure the P12 file contains the requested components

### Permission Errors

**Problem**: "Cannot write to output folder"

**Solutions**:
1. Run PowerShell as Administrator
2. Select a different output location
3. Check folder permissions

## Module Structure

```
P12CertificateToolkit/
├── P12CertificateToolkit.psd1          # Module manifest
├── P12CertificateToolkit.psm1          # Main module file
├── Public/
│   └── Start-P12CertificateToolkit.ps1 # Main GUI function
├── Private/
│   └── Helper-Functions.ps1            # Helper functions
├── Examples/
│   └── Basic-Usage.ps1                 # Usage examples
└── README.md                           # This file
```

## Examples

See [Examples/Basic-Usage.ps1](Examples/Basic-Usage.ps1) for detailed usage examples.

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

This project is provided as-is for personal use. See repository for license details.

## Author

Matthew Blakeslee-Hisel
GitHub: [Personal-Scripts](https://github.com/frznto/Powershell-Public)

## Version History

### Version 2.0.0 (11/3/2025)
- Converted standalone script to PowerShell module
- Added proper module structure with manifest
- Improved code organization
- Enhanced error handling and validation
- OpenSSL 3.x legacy provider auto-detection (checks three locations)
- Certificate verification with inline per-file results
- Test Mode for P12 file validation with separate transcript logs
- Auto-open transcript on errors
- Append private key to PEM option
- Key password auto-populates from P12 password
- Output folder conflict handling (overwrite / timestamped / cancel)
- Open Extracted Folder button after extraction completes
- Responsive UI layout with auto-scaling buttons
- Form title reflects current operation state ([Running] / [Testing])
- Comprehensive documentation

### Version 1.0 (Initial Release)
- Initial GUI implementation
- Basic PEM/CER/KEY extraction
- Dark mode support
- Batch processing
- Log file support
