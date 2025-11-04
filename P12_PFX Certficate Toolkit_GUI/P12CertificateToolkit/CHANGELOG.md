# Changelog

All notable changes to the P12/PFX Certificate Toolkit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2025-01-03

### Added - Module Structure
- **PowerShell Module**: Converted standalone script to proper PowerShell module
- **Module Manifest**: Created `.psd1` with metadata, version info, and dependencies
- **Modular Architecture**: Separated code into Public/Private function directories
- **Installation Script**: Added `Install-Module.ps1` for easy module installation
- **Comprehensive Documentation**:
  - README.md with features, requirements, and troubleshooting
  - CHANGELOG.md for version tracking
  - LICENSE file (MIT License)
  - Examples/Basic-Usage.ps1 with detailed usage examples
- **Repository Files**: Added .gitignore for proper version control

### Added - Features
- **Test Mode Button**: Replaced Test Mode checkbox with dedicated button
  - Validates P12/PFX files without extraction
  - Provides detailed validation results
  - Supports Stop button during testing
- **OpenSSL Version Detection**: Automatic OpenSSL version checking
  - Warns if version < 3.0
  - Displays version in transcript header
  - Validates compatibility before extraction
- **Legacy Provider Auto-Detection**:
  - Automatically locates `legacy.dll` in portable OpenSSL installations
  - Searches multiple common locations
  - Adds `-provider-path` parameter when needed
- **Certificate Verification**:
  - Validates extracted PEM, CER, and KEY files
  - Uses OpenSSL to verify file integrity
  - Shows ✓/✗ indicators in logs
- **Enhanced Transcript Logging**:
  - Timestamps on all log entries
  - OpenSSL version in transcript header
  - Legacy provider status reporting
  - Error count tracking
  - Auto-open transcript on errors
- **CA File Validation**:
  - Validates PEM format before appending
  - Checks for proper BEGIN/END markers
  - Prevents invalid file usage
- **Enhanced Error Handling**:
  - Better error messages for failed extractions
  - File permission error detection
  - P12 file validation before processing

### Changed
- **UI Layout**: Adjusted checkbox positions for better organization
- **Button Panel**: Added Test button between Stop and Exit buttons
- **Log Format**: All log entries now include timestamps
- **Function Organization**: Separated helper functions into dedicated files
- **Code Structure**: Improved code organization and maintainability

### Fixed
- **Portable OpenSSL Support**: Legacy provider now works with portable installations
- **Error Tracking**: Proper error counting throughout processing
- **Transcript Management**: Improved transcript start/stop logic
- **Button States**: Proper enable/disable of Test button

## [1.0.0] - Initial Release

### Added
- **GUI Application**: Windows Forms-based interface
- **Multiple Extraction Formats**: PEM, CER, KEY support
- **Key Encryption**: Optional re-encryption of private keys
- **Header Stripping**: Remove extra content from output files
- **CA Chain Appending**: Append CA certificates to PEM files
- **Dark Mode**: Light and dark theme support
- **Batch Processing**: Process multiple files with progress tracking
- **Log File Support**: Optional file-based logging
- **Stop/Resume**: Ability to stop processing mid-batch
- **Verbose Transcript**: Detailed OpenSSL command logging
- **OpenSSL Integration**:
  - Auto-detection of OpenSSL in PATH
  - Manual OpenSSL path selection
  - OpenSSL version testing
- **UI Features**:
  - Progress bar with file counter
  - Real-time log display
  - "Open Extracted Folder" button
  - Responsive layout with window resizing
  - Theme persistence
- **Error Handling**:
  - Password validation
  - Folder existence checking
  - Format selection validation
  - Overwrite protection with options

### Technical Details
- PowerShell 5.1+ compatibility
- System.Windows.Forms and System.Drawing assemblies
- OpenSSL command-line integration
- Legacy P12 format support with automatic retry

---

## Version Numbering

- **Major version** (X.0.0): Significant changes, possible breaking changes
- **Minor version** (1.X.0): New features, backward compatible
- **Patch version** (1.0.X): Bug fixes, minor improvements

## Links

- [Repository](https://github.com/FrznDad/Personal-Scripts)
- [Issues](https://github.com/FrznDad/Personal-Scripts/issues)
