# Quick Start Guide

Get started with the P12/PFX Certificate Toolkit in under 5 minutes!

## Installation

### Option 1: Automated Installation (Recommended)

```powershell
# Navigate to the module directory
cd "z:\FrznDad\Github\Personal-Scripts\Certificates\P12CertificateToolkit"

# Run the installation script
.\Install-Module.ps1

# Launch the toolkit
Start-P12CertificateToolkit
```

### Option 2: Manual Installation

```powershell
# Copy to your PowerShell modules directory
$modulePath = "$HOME\Documents\PowerShell\Modules\P12CertificateToolkit"
Copy-Item -Path "z:\FrznDad\Github\Personal-Scripts\Certificates\P12CertificateToolkit" -Destination $modulePath -Recurse

# Import and launch
Import-Module P12CertificateToolkit
Start-P12CertificateToolkit
```

### Option 3: Run Standalone Script

```powershell
# No installation required
cd "z:\FrznDad\Github\Personal-Scripts\Certificates"
.\P12_PFX Certficate Toolkit_GUI Rev2.ps1
```

## First-Time Setup

1. **Launch the toolkit**:
   ```powershell
   Start-P12CertificateToolkit
   ```

2. **Select OpenSSL** (if not auto-detected):
   - Click **"Select OpenSSL Folder..."**
   - Browse to your `openssl.exe` location
   - Click **"Test OpenSSL"** to verify

3. **Ready to use!**

## Basic Workflow

### Extracting Certificates

1. Click **"Browse..."** → Select folder with `.p12` or `.pfx` files
2. Enter the **P12 password**
3. Check desired formats:
   - ☑ Extract PEM
   - ☑ Extract CER
   - ☑ Extract Key
4. Click **"Start Extraction"**
5. Monitor progress in the log window
6. Click **"📂 Open Extracted Folder"** when complete

**Output Location**: `[YourFolder]\Extracted\`

### Testing P12 Files (No Extraction)

1. Click **"Browse..."** → Select folder
2. Enter password
3. Click **"Test P12 Files"**
4. Review validation results in log

## Common Use Cases

### Use Case 1: Extract Everything

```
✓ Extract PEM
✓ Extract CER
✓ Extract Key
```
Click **"Start Extraction"**

### Use Case 2: Extract Only Certificate (No Key)

```
✓ Extract PEM
✓ Extract CER
☐ Extract Key
```

### Use Case 3: Extract with New Key Password

```
✓ Extract PEM
✓ Extract Key
✓ Encrypt Private Key
```
Enter new password when prompted

### Use Case 4: Add CA Chain to Certificate

```
✓ Extract PEM
✓ Append CA certificate to PEM file
```
Click **"Browse CA..."** → Select CA chain file

### Use Case 5: Troubleshooting Mode

```
✓ Verbose Transcript (optional)
✓ Verify extracted certificates
✓ Auto-open transcript when errors occur
```

## Keyboard Shortcuts

- **F5**: Start extraction (when ready)
- **ESC**: Stop extraction (when running)
- **Alt+D**: Toggle dark mode

## Tips

### Batch Processing
- Place all P12 files in one folder
- All files will be processed with the same password
- Use **Stop** button to pause if needed

### Legacy P12 Files
- The toolkit automatically retries with `-legacy` flag
- Works with old/legacy format P12/PFX files
- OpenSSL 3.0+ recommended

### Portable OpenSSL
- Download from: https://wiki.openssl.org/index.php/Binaries
- Extract anywhere
- Point toolkit to `bin\openssl.exe`
- Legacy provider auto-detected

### Output Files
Each P12 file produces:
- `filename.pem` → Certificate in PEM format
- `filename.cer` → Certificate in binary DER format
- `filename.key` → Private key

## Troubleshooting

**Problem**: "OpenSSL not found"
```powershell
# Solution: Manually specify OpenSSL path
Start-P12CertificateToolkit -OpenSSLPath "C:\OpenSSL\bin\openssl.exe"
```

**Problem**: Extraction fails
- Enable **Verbose Transcript**
- Check transcript log for errors
- Verify password is correct

**Problem**: Legacy P12 files fail
- Ensure OpenSSL 3.0+
- Check for `legacy.dll` in OpenSSL folder
- Review transcript for "legacy provider" messages

## Next Steps

- Read full [README.md](README.md) for advanced features
- Check [Examples/Basic-Usage.ps1](Examples/Basic-Usage.ps1) for code examples
- Review [CHANGELOG.md](CHANGELOG.md) for version history

## Support

- **Issues**: [GitHub Issues](https://github.com/FrznDad/Personal-Scripts/issues)
- **Documentation**: [README.md](README.md)

---

**Version**: 2.0.0
**Author**: FrznDad
**License**: MIT
