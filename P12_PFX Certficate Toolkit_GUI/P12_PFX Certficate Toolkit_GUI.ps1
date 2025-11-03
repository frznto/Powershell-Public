<#
.SYNOPSIS
  P12/PFX Certificate Toolkit (GUI): extract PEM, CER, and KEY from .p12/.pfx using OpenSSL
  with optional key encryption, header stripping, CA chain append (PEM only),
  dark mode, progress, logs, start/stop, fixed bottom button panel,
  "Open Extracted Folder" button, and a status bar showing processed counts.

.DESCRIPTION
  This GUI application provides a user-friendly interface for extracting certificate
  components from P12/PFX files using OpenSSL. Features include:
  - Multiple output formats (PEM, CER, KEY)
  - Optional key encryption
  - CA chain appending for PEM files
  - Dark mode support
  - Progress tracking and logging
  - Batch processing with stop/resume capability

.NOTES
  Version:        2.0
  Author:         Refactored for PowerShell Best Practices
  Requirements:   OpenSSL must be installed and accessible
  
  OpenSSL portable link: https://kb.firedaemon.com/support/solutions/articles/4000121705
  Latest version as of 10/27/2025: "OpenSSL 3.6.0 ZIP x86+x64+ARM64"

.EXAMPLE
  .\P12_PFX_Certificate_Toolkit_GUI.ps1
  Launches the GUI application for certificate extraction.
#>

[CmdletBinding()]
param()

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

#region Constants
$script:FlashCount = 4
$script:FlashDelayMs = 150
$script:MinButtonScale = 0.7
$script:ProgressRefreshMs = 40
#endregion Constants

#region Helper Functions

function Test-OpenSSL {
    <#
    .SYNOPSIS
    Tests if OpenSSL is available in the system PATH.
    #>
    try { 
        (Get-Command openssl.exe -ErrorAction Stop).Source 
    } 
    catch { 
        Write-Verbose "OpenSSL not found in PATH: $_"
        $null 
    }
}

function Select-OpenSSLExecutable {
    <#
    .SYNOPSIS
    Prompts user to select openssl.exe manually via file dialog or folder search.
    #>
    # 1) Let the user select openssl.exe directly
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Title = "Select openssl.exe"
    $ofd.Filter = "openssl.exe|openssl.exe|Executables (*.exe)|*.exe|All files (*.*)|*.*"
    $ofd.Multiselect = $false
    
    try {
        $common = @(
            "$env:ProgramFiles\OpenSSL-Win64\bin",
            "$env:ProgramFiles(x86)\OpenSSL-Win32\bin",
            "$env:ProgramFiles\Git\usr\bin",
            "$env:Chocolatey\bin",
            "$env:ProgramFiles\Git\mingw64\bin"
        ) | Where-Object { $_ -and (Test-Path $_) }
        
        if ($common.Count -gt 0) { 
            $ofd.InitialDirectory = $common[0] 
        }
    } 
    catch {
        Write-Verbose "Error setting initial directory: $_"
    }
    
    if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        if (Test-Path $ofd.FileName) { 
            return $ofd.FileName 
        }
    }

    # 2) Fallback: pick a folder and search typical subpaths (and recurse)
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Select folder that contains openssl.exe (or a subfolder like \bin)"
    $fbd.ShowNewFolderButton = $false
    
    if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $candidates = @(
            (Join-Path $fbd.SelectedPath "openssl.exe"),
            (Join-Path $fbd.SelectedPath "bin\openssl.exe"),
            (Join-Path $fbd.SelectedPath "usr\bin\openssl.exe"),
            (Get-ChildItem -Path $fbd.SelectedPath -Filter openssl.exe -Recurse -ErrorAction SilentlyContinue | 
                Select-Object -First 1 -ExpandProperty FullName)
        ) | Where-Object { $_ -and (Test-Path $_) }
        
        if ($candidates -and $candidates[0]) { 
            return $candidates[0] 
        }
        
        [System.Windows.Forms.MessageBox]::Show(
            "openssl.exe not found under the selected path.",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    
    return $null
}

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

    # UI sink (ListBox)
    if (-not $NoUI) {
        try {
            if ($null -ne $script:LogBox) {
                [void]$script:LogBox.Items.Add($Message)
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

#endregion Helper Functions

#region Themes

$script:LightTheme = @{
    FormBackColor    = [System.Drawing.Color]::White
    ForeColor        = [System.Drawing.Color]::Black
    ControlBackColor = [System.Drawing.Color]::White
    ListBackColor    = [System.Drawing.Color]::White
    ButtonBackColor  = [System.Drawing.Color]::Gainsboro
    PanelBackColor   = [System.Drawing.Color]::FromArgb(245, 245, 245)
    GoodColor        = [System.Drawing.Color]::Green
    BadColor         = [System.Drawing.Color]::Red
    StatusBackColor  = [System.Drawing.Color]::FromArgb(235, 235, 235)
}

$script:DarkTheme = @{
    FormBackColor    = [System.Drawing.Color]::FromArgb(30, 30, 30)
    ForeColor        = [System.Drawing.Color]::White
    ControlBackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
    ListBackColor    = [System.Drawing.Color]::FromArgb(40, 40, 40)
    ButtonBackColor  = [System.Drawing.Color]::FromArgb(70, 70, 70)
    PanelBackColor   = [System.Drawing.Color]::FromArgb(25, 25, 25)
    GoodColor        = [System.Drawing.Color]::LimeGreen
    BadColor         = [System.Drawing.Color]::Tomato
    StatusBackColor  = [System.Drawing.Color]::FromArgb(35, 35, 35)
}

function Set-ControlTheme {
    <#
    .SYNOPSIS
    Applies theme colors to a control and its children recursively.
    #>
    param(
        $Control,
        $Theme
    )
    
    if ($Control -is [System.Windows.Forms.TextBox]) {
        $Control.BackColor = $Theme.ListBackColor
        $Control.ForeColor = $Theme.ForeColor
    }
    elseif ($Control -is [System.Windows.Forms.ListBox]) {
        $Control.BackColor = $Theme.ListBackColor
        $Control.ForeColor = $Theme.ForeColor
    }
    elseif ($Control -is [System.Windows.Forms.Button]) {
        $Control.BackColor = $Theme.ButtonBackColor
        $Control.ForeColor = $Theme.ForeColor
    }
    elseif ($Control -is [System.Windows.Forms.Panel]) {
        $Control.BackColor = $Theme.PanelBackColor
        foreach ($sub in $Control.Controls) { 
            Set-ControlTheme -Control $sub -Theme $Theme 
        }
        return
    }
    elseif ($Control -is [System.Windows.Forms.StatusStrip]) {
        $Control.BackColor = $Theme.StatusBackColor
        foreach ($sub in $Control.Items) { 
            $sub.ForeColor = $Theme.ForeColor 
        }
        return
    }
    else {
        $Control.BackColor = $Theme.ControlBackColor
        $Control.ForeColor = $Theme.ForeColor
    }

    if ($Control.Controls -and $Control.Controls.Count -gt 0) {
        foreach ($sub in $Control.Controls) { 
            Set-ControlTheme -Control $sub -Theme $Theme 
        }
    }
}

function Set-Theme {
    <#
    .SYNOPSIS
    Applies a theme to the entire form.
    #>
    param(
        $Form,
        $Theme
    )
    
    $Form.BackColor = $Theme.FormBackColor
    foreach ($ctrl in $Form.Controls) { 
        Set-ControlTheme -Control $ctrl -Theme $Theme 
    }
}

#endregion Themes

#region Extraction Logic

$script:StopRequested = $false
$script:LastExtractedPath = $null

function Invoke-P12Extraction {
    <#
    .SYNOPSIS
    Extracts PEM, CER, and KEY files from P12/PFX certificates using OpenSSL.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $OpenSSLPath,

        [Parameter(Mandatory = $true)]
        [System.Collections.ArrayList]
        $Files,

        [Parameter(Mandatory = $true)]
        [string]
        $OutputFolder,

        [Parameter(Mandatory = $true)]
        [string]
        $Password,

        [bool]
        $EncryptKey,

        [bool]
        $StripHeaders,

        [bool]
        $ExtractPEM,

        [bool]
        $ExtractCER,

        [bool]
        $ExtractKey,

        [bool]
        $AppendCA,

        [string]
        $CAFilePath,

        [System.Windows.Forms.ProgressBar]
        $ProgressBar,

        [System.Windows.Forms.ListBox]
        $LogBox,

        [System.Windows.Forms.ToolStripStatusLabel]
        $StatusLabel
    )

    $ProgressBar.Maximum = $Files.Count
    $ProgressBar.Value = 0
    $LogBox.Items.Clear()

    $total = $Files.Count
    $processed = 0

    if ($StatusLabel) {
        $StatusLabel.Text = "Processed {0} / {1} files" -f $processed, $total
    }

    # Start transcript if enabled
    $transcriptStarted = $false
    $originalVerbosePreference = $VerbosePreference
    if ($script:TranscriptEnabled -and $script:TranscriptPath) {
        try {
            # Enable verbose output so it gets captured in the transcript
            $VerbosePreference = 'Continue'

            Start-Transcript -Path $script:TranscriptPath -Force -ErrorAction Stop
            $transcriptStarted = $true

            Write-Host "=== TRANSCRIPT STARTED ==="
            Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            Write-Host "OpenSSL Path: $OpenSSLPath"
            Write-Host "Output Folder: $OutputFolder"
            Write-Host "Total Files: $total"
            Write-Host "Options: ExtractPEM=$ExtractPEM, ExtractCER=$ExtractCER, ExtractKey=$ExtractKey, EncryptKey=$EncryptKey, StripHeaders=$StripHeaders, AppendCA=$AppendCA"
            if ($AppendCA -and $CAFilePath) {
                Write-Host "CA File: $CAFilePath"
            }
            Write-Host "======================================"
        }
        catch {
            $VerbosePreference = $originalVerbosePreference
            Add-Log -Message ("⚠️ Failed to start transcript: {0}" -f $_)
        }
    }

    foreach ($file in $Files) {
        # Allow UI to process events (including Stop button clicks)
        [System.Windows.Forms.Application]::DoEvents()

        if ($script:StopRequested) {
            Add-Log -Message "🛑 Extraction stopped by user."
            break
        }

        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file)
        $pemPath = Join-Path $OutputFolder ("{0}.pem" -f $baseName)
        $cerPath = Join-Path $OutputFolder ("{0}.cer" -f $baseName)
        $keyPath = Join-Path $OutputFolder ("{0}.key" -f $baseName)

        # Pre-clean any existing outputs to ensure a clean overwrite
        foreach ($p in @($pemPath, $cerPath, $keyPath)) {
            if ($p -and (Test-Path -LiteralPath $p)) {
                Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
            }
        }

        $successFlags = @()

        try {
            # CERT as PEM (text)
            if ($ExtractPEM) {
                $passIn = 'pass:{0}' -f $Password

                if ($script:TranscriptEnabled) {
                    Write-Host "Extracting PEM from: $($file.Name)"
                    Write-Host "Command: openssl pkcs12 -in `"$($file.FullName)`" -clcerts -nokeys -out `"$pemPath`" -passin [HIDDEN]"
                    $output = & $OpenSSLPath pkcs12 -in $file.FullName -clcerts -nokeys -out $pemPath -passin $passIn 2>&1
                    if ($output) { Write-Host $output }
                } else {
                    & $OpenSSLPath pkcs12 -in $file.FullName -clcerts -nokeys -out $pemPath -passin $passIn 2>$null
                }
                
                if (Test-Path $pemPath) {
                    if ($StripHeaders) {
                        if (-not (Limit-PemEnvelope -Path $pemPath)) {
                            Add-Log -Message ("⚠️ Failed to trim outside-PEM lines for {0} .pem" -f $file.Name)
                        }
                    }
                    
                    if ($AppendCA -and $CAFilePath) {
                        if (Test-Path -LiteralPath $pemPath) {
                            try {
                                $pemRaw = Get-Content -LiteralPath $pemPath -Raw -ErrorAction Stop
                                $caRaw = Get-Content -LiteralPath $CAFilePath -Raw -ErrorAction Stop
                                
                                # Remove ALL trailing blank lines from PEM and ALL leading blank lines from CA
                                $pemRaw = $pemRaw -replace '(\r?\n)*\s*\z', ''
                                $caRaw = $caRaw -replace '^\s*(\r?\n)*', ''
                                
                                # Join with a single line break
                                $combined = $pemRaw + "`r`n" + $caRaw
                                Set-Content -LiteralPath $pemPath -Value $combined -Encoding ascii -NoNewline
                                $successFlags += "PEM+CA"
                            } 
                            catch {
                                Add-Log -Message ("❌ {0} → Failed to append CA to PEM: {1}" -f $file.Name, $_)
                                $successFlags += "PEM"
                            }
                        } 
                        else {
                            Add-Log -Message ("❌ {0} → PEM not created, cannot append CA." -f $file.Name)
                        }
                    } 
                    else { 
                        $successFlags += "PEM" 
                    }
                }
            }

            # CERT as CER (DER/binary)
            if ($ExtractCER) {
                $passIn = 'pass:{0}' -f $Password
                $tempPem = [System.IO.Path]::GetTempFileName() + ".pem"

                try {
                    if ($script:TranscriptEnabled) {
                        Write-Host "Extracting CER from: $($file.Name)"
                        Write-Host "Command: openssl pkcs12 -in `"$($file.FullName)`" -clcerts -nokeys -out `"$tempPem`" -passin [HIDDEN]"
                        $output = & $OpenSSLPath pkcs12 -in $file.FullName -clcerts -nokeys -out $tempPem -passin $passIn 2>&1
                        if ($output) { Write-Host $output }
                    } else {
                        & $OpenSSLPath pkcs12 -in $file.FullName -clcerts -nokeys -out $tempPem -passin $passIn 2>$null
                    }

                    if (Test-Path -LiteralPath $tempPem) {
                        if ($script:TranscriptEnabled) {
                            Write-Host "Command: openssl x509 -in `"$tempPem`" -outform DER -out `"$cerPath`""
                            $output = & $OpenSSLPath x509 -in $tempPem -outform DER -out $cerPath 2>&1
                            if ($output) { Write-Host $output }
                        } else {
                            & $OpenSSLPath x509 -in $tempPem -outform DER -out $cerPath 2>$null
                        }
                    }
                }
                finally {
                    if (Test-Path -LiteralPath $tempPem) {
                        Remove-Item -LiteralPath $tempPem -Force -ErrorAction SilentlyContinue
                    }
                }
                
                if (Test-Path $cerPath) { 
                    $successFlags += "CER" 
                }
            }

            # PRIVATE KEY
            if ($ExtractKey) {
                if (-not $EncryptKey) {
                    $passIn = 'pass:{0}' -f $Password

                    if ($script:TranscriptEnabled) {
                        Write-Host "Extracting KEY (unencrypted) from: $($file.Name)"
                        Write-Host "Command: openssl pkcs12 -in `"$($file.FullName)`" -nocerts -out `"$keyPath`" -nodes -passin [HIDDEN]"
                        $output = & $OpenSSLPath pkcs12 -in $file.FullName -nocerts -out $keyPath -nodes -passin $passIn 2>&1
                        if ($output) { Write-Host $output }
                    } else {
                        & $OpenSSLPath pkcs12 -in $file.FullName -nocerts -out $keyPath -nodes -passin $passIn 2>$null
                    }
                }
                else {
                    $passIn = 'pass:{0}' -f $Password
                    # Use custom key password if provided, otherwise use P12 password
                    $keyPassOut = if ($script:txtKeyPassword -and $script:txtKeyPassword.Text) {
                        $script:txtKeyPassword.Text
                    } else {
                        $Password
                    }
                    $passOut = 'pass:{0}' -f $keyPassOut

                    if ($script:TranscriptEnabled) {
                        Write-Host "Extracting KEY (encrypted) from: $($file.Name)"
                        Write-Host "Command: openssl pkcs12 -in `"$($file.FullName)`" -nocerts -out `"$keyPath`" -passin [HIDDEN] -passout [HIDDEN]"
                        $output = & $OpenSSLPath pkcs12 -in $file.FullName -nocerts -out $keyPath -passin $passIn -passout $passOut 2>&1
                        if ($output) { Write-Host $output }
                    } else {
                        & $OpenSSLPath pkcs12 -in $file.FullName -nocerts -out $keyPath -passin $passIn -passout $passOut 2>$null
                    }
                }
                
                if (Test-Path $keyPath) {
                    if ($StripHeaders) {
                        if (-not (Limit-PemEnvelope -Path $keyPath)) {
                            Add-Log -Message ("⚠️ Failed to trim outside-PEM lines for {0} .key" -f $file.Name)
                        }
                    }
                    
                    $keyStatus = if ($EncryptKey) { "(enc)" } else { "(noenc)" }
                    $successFlags += "KEY{0}" -f $keyStatus
                }
            }

            if ($successFlags.Count -gt 0) {
                if ($successFlags -contains "PEM+CA" -and $CAFilePath) {
                    $caFileName = Split-Path -Path $CAFilePath -Leaf
                    Add-Log -Message ("✅ {0} → {1} (CA: {2})" -f $file.Name, ($successFlags -join ', '), $caFileName)
                } 
                else {
                    Add-Log -Message ("✅ {0} → {1}" -f $file.Name, ($successFlags -join ', '))
                }
            } 
            else {
                Add-Log -Message ("❌ {0} → No outputs produced" -f $file.Name)
            }
        }
        catch {
            $errorMsg = $_.Exception.Message
            if ($script:TranscriptEnabled) {
                Write-Host "ERROR processing $($file.Name): $errorMsg" -ForegroundColor Red
                Write-Host "Error details: $($_ | Out-String)"
            }
            Add-Log -Message ("❌ {0} → Error: {1}" -f $file.Name, $errorMsg)
        }

        $processed++
        $ProgressBar.Value = [Math]::Min($processed, $total)
        $StatusLabel.Text = "Processed {0} / {1} files" -f $processed, $total
        $LogBox.TopIndex = $LogBox.Items.Count - 1

        if ($script:TranscriptEnabled) {
            Write-Host "Progress: $processed / $total files completed"
            Write-Host "---"
        }

        Start-Sleep -Milliseconds $script:ProgressRefreshMs
    }

    # Stop transcript if it was started
    if ($transcriptStarted) {
        try {
            Write-Host "======================================"
            Write-Host "=== TRANSCRIPT ENDED ==="
            Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            Write-Host "Total files processed: $processed / $total"
            Write-Host "Stopped: $(if ($script:StopRequested) { 'Yes (user requested)' } else { 'No (completed)' })"
            Stop-Transcript -ErrorAction Stop
        }
        catch {
            Add-Log -Message ("⚠️ Failed to stop transcript: {0}" -f $_)
        }
        finally {
            # Restore original verbose preference
            $VerbosePreference = $originalVerbosePreference
        }
    }

    $script:LastExtractedPath = $OutputFolder
}

#endregion Extraction Logic

#region UI Effects

function Start-ButtonFlash {
    <#
    .SYNOPSIS
    Creates a visual flash effect on a button to draw attention.
    #>
    param(
        $Button
    )
    
    $orig = $Button.BackColor
    
    for ($i = 0; $i -lt $script:FlashCount; $i++) {
        $Button.BackColor = [System.Drawing.Color]::Gold
        Start-Sleep -Milliseconds $script:FlashDelayMs
        $Button.BackColor = [System.Drawing.Color]::LimeGreen
        Start-Sleep -Milliseconds $script:FlashDelayMs
    }
    
    $Button.BackColor = $orig
}

#endregion UI Effects

#region GUI Setup

$form = New-Object System.Windows.Forms.Form
$form.Text = "P12/PFX Certificate Toolkit (GUI)"
$form.Size = New-Object System.Drawing.Size(800, 860)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = 'Sizable'
$form.AutoScroll = $true
$form.VerticalScroll.Visible = $true
$form.MinimumSize = New-Object System.Drawing.Size(800, 700)

#region Top Controls (Scrollable Content)

# Folder selection
$lblFolder = New-Object System.Windows.Forms.Label
$lblFolder.Location = New-Object System.Drawing.Point(20, 50)
$lblFolder.Size = New-Object System.Drawing.Size(260, 25)
$lblFolder.Text = "Select Folder with .p12 files:"
$form.Controls.Add($lblFolder)

$script:txtFolder = New-Object System.Windows.Forms.TextBox
$script:txtFolder.Location = New-Object System.Drawing.Point(280, 45)
$script:txtFolder.Size = New-Object System.Drawing.Size(380, 25)
$script:txtFolder.ReadOnly = $true
$script:txtFolder.Anchor = "Top, Left, Right"
$form.Controls.Add($script:txtFolder)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Location = New-Object System.Drawing.Point(670, 45)
$btnBrowse.Size = New-Object System.Drawing.Size(90, 25)
$btnBrowse.Text = "Browse..."
$btnBrowse.Anchor = "Top, Right"
$form.Controls.Add($btnBrowse)

# Dark mode toggle
$script:chkDark = New-Object System.Windows.Forms.CheckBox
$script:chkDark.Location = New-Object System.Drawing.Point(670, 10)
$script:chkDark.Anchor = "Top, Right"
$script:chkDark.Size = New-Object System.Drawing.Size(120, 20)
$script:chkDark.Text = "Dark Mode"
$form.Controls.Add($script:chkDark)

# Password field
$lblPwd = New-Object System.Windows.Forms.Label
$lblPwd.Location = New-Object System.Drawing.Point(160, 110)
$lblPwd.Text = "P12 Password:"
$form.Controls.Add($lblPwd)

$script:txtPwd = New-Object System.Windows.Forms.TextBox
$script:txtPwd.Location = New-Object System.Drawing.Point(280, 105)
$script:txtPwd.Size = New-Object System.Drawing.Size(380, 25)
$script:txtPwd.PasswordChar = [char]0
$script:txtPwd.Anchor = "Top, Left, Right"
$form.Controls.Add($script:txtPwd)

# P12 status
$script:lblP12Status = New-Object System.Windows.Forms.Label
$script:lblP12Status.Location = New-Object System.Drawing.Point(20, 80)
$script:lblP12Status.Size = New-Object System.Drawing.Size(740, 25)
$script:lblP12Status.ForeColor = 'Gray'
$script:lblP12Status.Text = "No folder selected."
$script:lblP12Status.Anchor = "Top, Left, Right"
$form.Controls.Add($script:lblP12Status)

# Options row 1 (what to extract)
$script:chkExtractPEM = New-Object System.Windows.Forms.CheckBox
$script:chkExtractPEM.Location = New-Object System.Drawing.Point(20, 130)
$script:chkExtractPEM.Size = New-Object System.Drawing.Size(120, 20)
$script:chkExtractPEM.Text = "Extract PEM"
$script:chkExtractPEM.Checked = $true
$form.Controls.Add($script:chkExtractPEM)

$script:chkExtractCER = New-Object System.Windows.Forms.CheckBox
$script:chkExtractCER.Location = New-Object System.Drawing.Point(160, 130)
$script:chkExtractCER.Size = New-Object System.Drawing.Size(120, 20)
$script:chkExtractCER.Text = "Extract CER"
$script:chkExtractCER.Checked = $false
$form.Controls.Add($script:chkExtractCER)

$script:chkExtractKey = New-Object System.Windows.Forms.CheckBox
$script:chkExtractKey.Location = New-Object System.Drawing.Point(300, 130)
$script:chkExtractKey.Size = New-Object System.Drawing.Size(120, 20)
$script:chkExtractKey.Text = "Extract Key"
$script:chkExtractKey.Checked = $true
$form.Controls.Add($script:chkExtractKey)

$script:chkStripHeaders = New-Object System.Windows.Forms.CheckBox
$script:chkStripHeaders.Location = New-Object System.Drawing.Point(440, 130)
$script:chkStripHeaders.Size = New-Object System.Drawing.Size(320, 20)
$script:chkStripHeaders.Text = "Strip headers from .pem and .key files"
$script:chkStripHeaders.Checked = $true
$script:chkStripHeaders.Anchor = "Top, Left, Right"
$form.Controls.Add($script:chkStripHeaders)

# Options row 2 (key encryption)
$script:chkEncryptKey = New-Object System.Windows.Forms.CheckBox
$script:chkEncryptKey.Location = New-Object System.Drawing.Point(20, 160)
$script:chkEncryptKey.Size = New-Object System.Drawing.Size(180, 20)
$script:chkEncryptKey.Text = "Encrypt the key file"
$script:chkEncryptKey.Checked = $false
$form.Controls.Add($script:chkEncryptKey)

$script:lblKeyPassword = New-Object System.Windows.Forms.Label
$script:lblKeyPassword.Location = New-Object System.Drawing.Point(210, 162)
$script:lblKeyPassword.Size = New-Object System.Drawing.Size(70, 20)
$script:lblKeyPassword.Text = "Password:"
$form.Controls.Add($script:lblKeyPassword)

$script:txtKeyPassword = New-Object System.Windows.Forms.TextBox
$script:txtKeyPassword.Location = New-Object System.Drawing.Point(280, 158)
$script:txtKeyPassword.Size = New-Object System.Drawing.Size(200, 25)
$script:txtKeyPassword.PasswordChar = '*'
$script:txtKeyPassword.Enabled = $false
$script:txtKeyPassword.Anchor = "Top, Left"
$form.Controls.Add($script:txtKeyPassword)

# CA chain append (PEM only)
$script:chkAppendCA = New-Object System.Windows.Forms.CheckBox
$script:chkAppendCA.Location = New-Object System.Drawing.Point(20, 190)
$script:chkAppendCA.Size = New-Object System.Drawing.Size(320, 20)
$script:chkAppendCA.Text = "Append IA/Root CA information to PEM files"
$script:chkAppendCA.Checked = $false
$form.Controls.Add($script:chkAppendCA)

$script:btnSelectCA = New-Object System.Windows.Forms.Button
$script:btnSelectCA.Location = New-Object System.Drawing.Point(350, 188)
$script:btnSelectCA.Size = New-Object System.Drawing.Size(130, 24)
$script:btnSelectCA.Text = "Select CA File..."
$script:btnSelectCA.Enabled = $false
$form.Controls.Add($script:btnSelectCA)

$script:lblCAPath = New-Object System.Windows.Forms.Label
$script:lblCAPath.Location = New-Object System.Drawing.Point(490, 190)
$script:lblCAPath.Size = New-Object System.Drawing.Size(270, 20)
$script:lblCAPath.ForeColor = 'Gray'
$script:lblCAPath.Text = ""
$script:lblCAPath.AutoEllipsis = $true
$script:lblCAPath.Anchor = "Top, Left, Right"
$form.Controls.Add($script:lblCAPath)

# Logging options
$script:chkLogToFile = New-Object System.Windows.Forms.CheckBox
$script:chkLogToFile.Location = New-Object System.Drawing.Point(20, 215)
$script:chkLogToFile.Size = New-Object System.Drawing.Size(140, 20)
$script:chkLogToFile.Text = "Write to log file"
$script:chkLogToFile.Checked = $false
$form.Controls.Add($script:chkLogToFile)

$script:btnBrowseLog = New-Object System.Windows.Forms.Button
$script:btnBrowseLog.Location = New-Object System.Drawing.Point(160, 213)
$script:btnBrowseLog.Size = New-Object System.Drawing.Size(130, 24)
$script:btnBrowseLog.Text = "Select Log File..."
$script:btnBrowseLog.Enabled = $false
$form.Controls.Add($script:btnBrowseLog)

$script:lblLogPath = New-Object System.Windows.Forms.Label
$script:lblLogPath.Location = New-Object System.Drawing.Point(300, 215)
$script:lblLogPath.Size = New-Object System.Drawing.Size(460, 20)
$script:lblLogPath.ForeColor = 'Gray'
$script:lblLogPath.AutoEllipsis = $true
$script:lblLogPath.Anchor = "Top, Left, Right"
$form.Controls.Add($script:lblLogPath)

# Verbose transcript logging option
$script:chkVerboseTranscript = New-Object System.Windows.Forms.CheckBox
$script:chkVerboseTranscript.Location = New-Object System.Drawing.Point(20, 240)
$script:chkVerboseTranscript.Size = New-Object System.Drawing.Size(400, 20)
$script:chkVerboseTranscript.Text = "Enable verbose transcript (captures all commands)"
$script:chkVerboseTranscript.Checked = $false
$script:chkVerboseTranscript.Anchor = "Top, Left"
$form.Controls.Add($script:chkVerboseTranscript)

# Files list
$script:listP12Files = New-Object System.Windows.Forms.ListBox
$script:listP12Files.MultiColumn = $false
$script:listP12Files.HorizontalScrollbar = $true
$script:listP12Files.ScrollAlwaysVisible = $true
$script:listP12Files.IntegralHeight = $false
$script:listP12Files.DrawMode = 'Normal'
$script:listP12Files.Location = New-Object System.Drawing.Point(20, 270)
$script:listP12Files.Size = New-Object System.Drawing.Size(740, 280)
$script:listP12Files.Anchor = "Top, Left, Right, Bottom"
$form.Controls.Add($script:listP12Files)

# Progress bar
$script:ProgressBar = New-Object System.Windows.Forms.ProgressBar
$script:ProgressBar.Location = New-Object System.Drawing.Point(20, 530)
$script:ProgressBar.Size = New-Object System.Drawing.Size(740, 25)
$script:ProgressBar.Style = 'Continuous'
$script:ProgressBar.Anchor = "Bottom, Left, Right"
$form.Controls.Add($script:ProgressBar)

# Log box
$script:LogBox = New-Object System.Windows.Forms.ListBox
$script:LogBox.Location = New-Object System.Drawing.Point(20, 560)
$script:LogBox.Size = New-Object System.Drawing.Size(740, 190)
$script:LogBox.Anchor = "Bottom, Left, Right"
$form.Controls.Add($script:LogBox)

# OpenSSL status label
$script:lblOpenSSL = New-Object System.Windows.Forms.Label
$script:lblOpenSSL.Location = New-Object System.Drawing.Point(20, 755)
$script:lblOpenSSL.Size = New-Object System.Drawing.Size(740, 30)
$script:lblOpenSSL.ForeColor = 'Red'
$script:lblOpenSSL.Anchor = "Bottom, Left, Right"
$form.Controls.Add($script:lblOpenSSL)

#endregion Top Controls

#region Bottom Panel (Always Visible)

$script:panelBottom = New-Object System.Windows.Forms.Panel
$script:panelBottom.Dock = 'Bottom'
$script:panelBottom.Height = 60
$script:panelBottom.BackColor = $script:LightTheme.PanelBackColor
$form.Controls.Add($script:panelBottom)

# Status bar (very bottom, below the panel)
$script:statusStrip = New-Object System.Windows.Forms.StatusStrip
$script:statusStrip.Dock = 'Bottom'
$form.Controls.Add($script:statusStrip)

$script:statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$script:statusLabel.Text = "Processed 0 / 0 files"
[void]$script:statusStrip.Items.Add($script:statusLabel)

$script:lblRunStatus = New-Object System.Windows.Forms.Label
$script:lblRunStatus.Location = New-Object System.Drawing.Point(10, 20)
$script:lblRunStatus.AutoSize = $true
$script:lblRunStatus.Text = ""
$script:panelBottom.Controls.Add($script:lblRunStatus)

$script:btnOpenFolder = New-Object System.Windows.Forms.Button
$script:btnOpenFolder.Size = New-Object System.Drawing.Size(180, 36)
$script:btnOpenFolder.Location = New-Object System.Drawing.Point(130, 15)
$script:btnOpenFolder.Text = "📂 Open Extracted Folder"
$script:btnOpenFolder.Enabled = $false
$script:panelBottom.Controls.Add($script:btnOpenFolder)

$script:btnCheckOpenSSL = New-Object System.Windows.Forms.Button
$script:btnCheckOpenSSL.Size = New-Object System.Drawing.Size(220, 36)
$script:btnCheckOpenSSL.Location = New-Object System.Drawing.Point(320, 15)
$script:btnCheckOpenSSL.Text = "Select OpenSSL Folder..."
$script:panelBottom.Controls.Add($script:btnCheckOpenSSL)

$script:btnTestOpenSSL = New-Object System.Windows.Forms.Button
$script:btnTestOpenSSL.Size = New-Object System.Drawing.Size(120, 36)
$script:btnTestOpenSSL.Location = New-Object System.Drawing.Point(470, 15)
$script:btnTestOpenSSL.Text = "Test OpenSSL"
$script:btnTestOpenSSL.Enabled = $false
$script:panelBottom.Controls.Add($script:btnTestOpenSSL)

$script:btnStart = New-Object System.Windows.Forms.Button
$script:btnStart.Size = New-Object System.Drawing.Size(130, 36)
$script:btnStart.Location = New-Object System.Drawing.Point(600, 15)
$script:btnStart.Text = "Start Extraction"
$script:btnStart.Enabled = $false
$script:panelBottom.Controls.Add($script:btnStart)

$script:btnStop = New-Object System.Windows.Forms.Button
$script:btnStop.Size = New-Object System.Drawing.Size(80, 36)
$script:btnStop.Location = New-Object System.Drawing.Point(735, 15)
$script:btnStop.Text = "Stop"
$script:btnStop.Enabled = $false
$script:panelBottom.Controls.Add($script:btnStop)

$script:btnExit = New-Object System.Windows.Forms.Button
$script:btnExit.Size = New-Object System.Drawing.Size(90, 36)
$script:btnExit.Text = "Exit"
$script:panelBottom.Controls.Add($script:btnExit)

#endregion Bottom Panel

#endregion GUI Setup

#region Responsive Layout Functions

function Update-BottomPanelLayout {
    <#
    .SYNOPSIS
    Centers and scales bottom panel buttons responsively.
    #>
    $padding = 10
    $spacing = 10

    # Collect buttons in display order
    $buttons = @()
    foreach ($ctrl in $script:panelBottom.Controls) {
        if ($ctrl -is [System.Windows.Forms.Button]) { 
            $buttons += $ctrl 
        }
    }
    
    if ($buttons.Count -eq 0) { 
        return 
    }

    # Auto-size bottom panel to fit the tallest button
    $vpad = 12
    $maxBtnH = ($buttons | Measure-Object -Property Height -Maximum).Maximum
    $script:panelBottom.Height = [Math]::Max([int]$maxBtnH + (2 * $vpad), 60)

    # Cache original widths once
    foreach ($b in $buttons) {
        if (-not $b.Tag) { 
            $b.Tag = [int]$b.Width 
        }
    }

    # Compute total width (baseline) and available width
    $baselineTotal = 0
    foreach ($b in $buttons) { 
        $baselineTotal += [int]$b.Tag + $spacing 
    }
    
    if ($buttons.Count -gt 0) { 
        $baselineTotal -= $spacing 
    }

    $available = [Math]::Max(100, $script:panelBottom.ClientSize.Width - (2 * $padding))

    # Scale down if needed (min scale factor)
    $scale = 1.0
    if ($baselineTotal -gt $available) {
        $scale = $available / [double]$baselineTotal
        if ($scale -lt $script:MinButtonScale) { 
            $scale = $script:MinButtonScale 
        }
    }

    # Set widths with scale, clamp at 80 min
    $actualTotal = 0
    foreach ($b in $buttons) {
        $newWidth = [Math]::Max(80, [int][Math]::Floor([double]$b.Tag * $scale))
        $b.Width = $newWidth
        $actualTotal += $newWidth + $spacing
    }
    
    if ($buttons.Count -gt 0) { 
        $actualTotal -= $spacing 
    }

    # Reduce spacing if still overflowing
    if ($actualTotal -gt $available) {
        $spacing = 5
        $actualTotal = 0
        foreach ($b in $buttons) { 
            $actualTotal += $b.Width + $spacing 
        }
        if ($buttons.Count -gt 0) { 
            $actualTotal -= $spacing 
        }
    }

    # Final X start (centered; left-align if still too wide)
    $startX = [Math]::Max($padding, [int][Math]::Floor(($script:panelBottom.ClientSize.Width - $actualTotal) / 2))

    # Vertically center label and buttons
    $script:lblRunStatus.Location = New-Object System.Drawing.Point(
        $padding, 
        [Math]::Max(5, [int][Math]::Floor(($script:panelBottom.ClientSize.Height - $script:lblRunStatus.Height) / 2))
    )

    $x = $startX
    foreach ($b in $buttons) {
        $b.Location = New-Object System.Drawing.Point(
            $x, 
            [int][Math]::Floor(($script:panelBottom.ClientSize.Height - $b.Height) / 2)
        )
        $x += $b.Width + $spacing
    }
}

function Update-ScrollableLayout {
    <#
    .SYNOPSIS
    Adjusts the scrollable content area to prevent overlapping with fixed panels.
    #>
    $padding = 10

    # Compute available height for the log box
    $panelH = $script:panelBottom.Height
    $statusH = $script:statusStrip.Height
    $labelH = $script:lblOpenSSL.Height

    $available = $form.ClientSize.Height - $script:ProgressBar.Bottom - $panelH - $statusH - (2 * $padding) - $labelH
    if ($available -lt 80) { 
        $available = 80 
    }
    
    $script:LogBox.Height = $available

    # Place the OpenSSL label directly beneath the LogBox
    $script:lblOpenSSL.Top = $script:LogBox.Bottom + $padding

    # Ensure label never overlaps the bottom panel
    $maxTop = $script:panelBottom.Top - $labelH - $padding
    if ($script:lblOpenSSL.Top -gt $maxTop) { 
        $script:lblOpenSSL.Top = $maxTop 
    }
}

#endregion Responsive Layout Functions

#region Event Handlers

# Theme toggle
$script:chkDark.Add_CheckedChanged({
    if ($script:chkDark.Checked) { 
        Set-Theme -Form $form -Theme $script:DarkTheme
        $script:lblOpenSSL.ForeColor = $script:DarkTheme.BadColor
    } 
    else { 
        Set-Theme -Form $form -Theme $script:LightTheme
        $script:lblOpenSSL.ForeColor = $script:LightTheme.BadColor
    }
})

# Browse for P12 folder
$btnBrowse.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select folder containing .p12/.pfx files"
    
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $selected = (Resolve-Path -LiteralPath $dialog.SelectedPath -ErrorAction SilentlyContinue).Path
        if (-not $selected) { 
            $selected = $dialog.SelectedPath.Trim() 
        }
        
        $script:txtFolder.Text = $selected
        Add-Log -Message ("📁 Selected folder: {0}" -f $selected)

        $script:listP12Files.Items.Clear()
        $files = @(Get-P12Files -FolderPath $selected)

        if ($files.Count -gt 0) {
            $script:lblP12Status.ForeColor = if ($script:chkDark.Checked) { 
                $script:DarkTheme.GoodColor 
            } else { 
                $script:LightTheme.GoodColor 
            }
            $script:lblP12Status.Text = "✅ Found {0} .p12/.pfx files:" -f $files.Count
            
            [string[]]$paths = $files | ForEach-Object { $_.FullName }
            [void]$script:listP12Files.Items.AddRange($paths)
        } 
        else {
            $script:lblP12Status.ForeColor = if ($script:chkDark.Checked) { 
                $script:DarkTheme.BadColor 
            } else { 
                $script:LightTheme.BadColor 
            }
            $script:lblP12Status.Text = "❌ No .p12 or .pfx files found."
        }

        Add-Log -Message ("🔍 Browse check: detected {0} file(s) in: {1}" -f $files.Count, $selected)
    }
})

# Encrypt key option - enable/disable password field
$script:chkEncryptKey.Add_CheckedChanged({
    $script:txtKeyPassword.Enabled = $script:chkEncryptKey.Checked

    if ($script:chkEncryptKey.Checked) {
        # Auto-populate with P12 password if available and field is empty
        if (-not $script:txtKeyPassword.Text) {
            $script:txtKeyPassword.Text = $script:txtPwd.Text
        }
        # Set focus to password field
        $script:txtKeyPassword.Focus()
    } else {
        # Clear password when unchecked
        $script:txtKeyPassword.Text = ""
    }
})

# CA option & selection
$script:chkAppendCA.Add_CheckedChanged({
    $script:btnSelectCA.Enabled = $script:chkAppendCA.Checked

    if (-not $script:chkAppendCA.Checked) {
        $script:CAFilePath = $null
        $script:lblCAPath.Text = ""
    }
    elseif (-not $script:chkExtractPEM.Checked) {
        Add-Log -Message "ℹ️ Note: 'Append CA' requires 'Extract PEM'. Enable 'Extract PEM' before starting."
    }
})

$script:btnSelectCA.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Title = "Select CA Chain File (PEM)"
    $ofd.Filter = "PEM Files (*.pem)|*.pem|All Files (*.*)|*.*"
    $ofd.Multiselect = $false
    
    if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        if (Test-CAFile -Path $ofd.FileName) {
            $script:CAFilePath = $ofd.FileName
            $script:lblCAPath.Text = $script:CAFilePath
            $script:lblCAPath.ForeColor = if ($script:chkDark.Checked) { 
                $script:DarkTheme.GoodColor 
            } else { 
                $script:LightTheme.GoodColor 
            }
            
            $caFileName = Split-Path -Path $script:CAFilePath -Leaf
            Add-Log -Message ("🔗 CA chain selected: {0}" -f $caFileName)
        } 
        else {
            $script:CAFilePath = $null
            $script:lblCAPath.Text = "Invalid CA file (must be PEM with BEGIN CERTIFICATE)."
            $script:lblCAPath.ForeColor = if ($script:chkDark.Checked) { 
                $script:DarkTheme.BadColor 
            } else { 
                $script:LightTheme.BadColor 
            }
            
            [System.Windows.Forms.MessageBox]::Show(
                "Selected file doesn't look like a PEM CA bundle. It must contain '-----BEGIN CERTIFICATE-----'.",
                "Invalid CA file",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
        }
    }
})

# Logging options
$script:chkLogToFile.Add_CheckedChanged({
    $script:btnBrowseLog.Enabled = $script:chkLogToFile.Checked
    
    if (-not $script:chkLogToFile.Checked) {
        $script:LogToFileEnabled = $false
        $script:LogFilePath = $null
        $script:lblLogPath.Text = ""
        Add-Log -Message "Logging to file disabled."
    } 
    else {
        Add-Log -Message "Logging to file enabled."
    }
})

$script:btnBrowseLog.Add_Click({
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Title = "Select log file"
    $sfd.Filter = "Text files (*.txt)|*.txt|All files (*.*)|*.*"
    $sfd.AddExtension = $true
    $sfd.DefaultExt = "txt"
    $sfd.OverwritePrompt = $false
    
    $initialDir = $script:txtFolder.Text
    if (-not (Test-Path -LiteralPath $initialDir)) { 
        $initialDir = [Environment]::GetFolderPath('Desktop') 
    }
    
    $sfd.InitialDirectory = $initialDir
    $sfd.FileName = "ExtractLog_{0}.txt" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')
    
    if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:LogFilePath = $sfd.FileName
        $script:lblLogPath.Text = $script:LogFilePath
        $script:LogToFileEnabled = $true
        Add-Log -Message ("Log file set: {0}" -f $script:LogFilePath)
    }
})

# OpenSSL checks
$script:btnCheckOpenSSL.Add_Click({
    $found = Test-OpenSSL
    
    if ($found) {
        $script:OpenSSLPath = $found
        $script:lblOpenSSL.ForeColor = if ($script:chkDark.Checked) { 
            $script:DarkTheme.GoodColor 
        } else { 
            $script:LightTheme.GoodColor 
        }
        $script:lblOpenSSL.Text = "✅ OpenSSL found at: {0}" -f $found
        $script:btnTestOpenSSL.Enabled = $true
        $script:btnStart.Enabled = $true
    } 
    else {
        $script:lblOpenSSL.ForeColor = if ($script:chkDark.Checked) { 
            $script:DarkTheme.BadColor 
        } else { 
            $script:LightTheme.BadColor 
        }
        $script:lblOpenSSL.Text = "❌ OpenSSL not found in PATH. Click 'Select OpenSSL Folder...' to browse."

        $manual = Select-OpenSSLExecutable
        if ($manual) {
            $script:OpenSSLPath = $manual
            $script:lblOpenSSL.ForeColor = if ($script:chkDark.Checked) { 
                $script:DarkTheme.GoodColor 
            } else { 
                $script:LightTheme.GoodColor 
            }
            $script:lblOpenSSL.Text = "✅ Using manual OpenSSL path: {0}" -f $manual
            $script:btnTestOpenSSL.Enabled = $true
            $script:btnStart.Enabled = $true
        }
    }
})

$script:btnTestOpenSSL.Add_Click({
    $ver = Invoke-OpenSSLTest -OpenSSLPath $script:OpenSSLPath
    
    if ($ver) { 
        [System.Windows.Forms.MessageBox]::Show(
            ("OpenSSL Test Successful:`n{0}" -f $ver),
            "Success",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
    else { 
        [System.Windows.Forms.MessageBox]::Show(
            "Failed to execute OpenSSL.",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
})

# Start extraction
$script:btnStart.Add_Click({
    if (-not $script:OpenSSLPath) { 
        return 
    }
    
    $folder = $script:txtFolder.Text.Trim()
    $password = $script:txtPwd.Text

    if (-not $password) { 
        [System.Windows.Forms.MessageBox]::Show(
            "Please enter the P12 password first.",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return 
    }
    
    if (-not (Test-Path -LiteralPath $folder)) { 
        [System.Windows.Forms.MessageBox]::Show(
            "Please select a valid folder first.",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return 
    }
    
    if ($script:chkAppendCA.Checked -and -not (Test-Path -LiteralPath $script:CAFilePath)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Please select a valid CA chain file (PEM) or uncheck the option.",
            "CA Chain Required",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }
    
    if ($script:chkAppendCA.Checked -and -not $script:chkExtractPEM.Checked) {
        [System.Windows.Forms.MessageBox]::Show(
            "To append the CA chain, 'Extract PEM' must be selected.",
            "Enable Extract PEM",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }

    $outputFolder = Join-Path $folder "Extracted"
    $OverwriteExisting = $true

    if (Test-Path -LiteralPath $outputFolder) {
        $existing = @(Get-ChildItem -LiteralPath $outputFolder -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in '.pem', '.cer', '.key' })
        
        if ($existing.Count -gt 0) {
            $choice = [System.Windows.Forms.MessageBox]::Show(
                "The 'Extracted' folder already exists and contains files.`r`n" +
                "Yes  = Overwrite in the same folder`r`n" +
                "No   = Create a new timestamped folder`r`n" +
                "Cancel = Abort",
                "Extracted Folder Exists",
                [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            
            switch ($choice) {
                'Yes' { 
                    $OverwriteExisting = $true 
                }
                'No' {
                    $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
                    $outputFolder = Join-Path $folder ("Extracted_{0}" -f $stamp)
                    New-Item -ItemType Directory -Path $outputFolder | Out-Null
                    $OverwriteExisting = $false
                }
                default { 
                    return 
                }
            }
        }
    } 
    else {
        New-Item -ItemType Directory -Path $outputFolder | Out-Null
    }

    $overwriteMsg = if ($OverwriteExisting) { " (overwrite)" } else { " (new)" }
    Add-Log -Message ("📦 Output folder: {0}{1}" -f $outputFolder, $overwriteMsg)

    # Setup verbose transcript logging
    if ($script:chkVerboseTranscript.Checked) {
        $script:TranscriptEnabled = $true
        $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
        $script:TranscriptPath = Join-Path $outputFolder ("Transcript_{0}.log" -f $stamp)

        try {
            New-Item -ItemType File -Path $script:TranscriptPath -Force | Out-Null
            Add-Log -Message ("📝 Verbose transcript enabled: {0}" -f $script:TranscriptPath)
        }
        catch {
            $script:TranscriptEnabled = $false
            $script:TranscriptPath = $null
            Add-Log -Message ("⚠️ Failed to create transcript file: {0}" -f $_)
        }
    }
    else {
        $script:TranscriptEnabled = $false
        $script:TranscriptPath = $null
    }

    # Setup logging
    if ($script:chkLogToFile.Checked) {
        if (-not $script:LogFilePath) {
            $script:LogToFileEnabled = $true
            $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
            $script:LogFilePath = Join-Path $outputFolder ("ExtractLog_{0}.txt" -f $stamp)
            
            try { 
                New-Item -ItemType File -Path $script:LogFilePath -Force | Out-Null 
            } 
            catch {
                Write-Verbose "Error creating log file: $_"
            }
            
            $script:lblLogPath.Text = $script:LogFilePath
        } 
        else {
            $script:LogToFileEnabled = $true
        }
        
        Add-Log -Message ("===== Run started {0} =====" -f (Get-Date))
        
        $ver = Invoke-OpenSSLTest -OpenSSLPath $script:OpenSSLPath
        if ($ver) { 
            Add-Log -Message ("OpenSSL: {0}" -f $ver)
        } 
        else { 
            Add-Log -Message "OpenSSL: (unknown)" 
        }
        
        Add-Log -Message ("Options: ExtractPEM={0}, ExtractCER={1}, ExtractKey={2}, EncryptKey={3}, StripHeaders={4}, AppendCA={5}" -f 
            $script:chkExtractPEM.Checked, 
            $script:chkExtractCER.Checked, 
            $script:chkExtractKey.Checked, 
            $script:chkEncryptKey.Checked, 
            $script:chkStripHeaders.Checked, 
            $script:chkAppendCA.Checked
        )
        
        if ($script:chkAppendCA.Checked -and $script:CAFilePath) { 
            Add-Log -Message ("CA File: {0}" -f $script:CAFilePath)
        }
    } 
    else {
        $script:LogToFileEnabled = $false
        $script:LogFilePath = $null
    }

    $files = @(Get-P12Files -FolderPath $folder)
    Add-Log -Message ("▶️ Start: folder = {0}" -f $folder)
    Add-Log -Message ("🔎 Start check: detected {0} file(s) in: {1}" -f $files.Count, $folder)
    
    if ($script:chkAppendCA.Checked) {
        if (Test-Path -LiteralPath $script:CAFilePath) {
            $caFileName = Split-Path $script:CAFilePath -Leaf
            Add-Log -Message ("🔗 CA chain: {0}" -f $caFileName)
        } 
        else {
            Add-Log -Message "⚠️ CA chain path is invalid or missing."
        }
    }
    
    if ($files.Count -eq 0) { 
        [System.Windows.Forms.MessageBox]::Show(
            "No .p12/.pfx files found.",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return 
    }

    # UI state: running
    $script:StopRequested = $false
    $script:btnStart.Enabled = $false
    $script:btnStop.Enabled = $true
    $script:btnOpenFolder.Enabled = $false
    $script:lblRunStatus.Text = "Running..."
    $script:lblRunStatus.ForeColor = if ($script:chkDark.Checked) { 
        $script:DarkTheme.GoodColor 
    } else { 
        $script:LightTheme.GoodColor 
    }
    
    $oldTitle = $form.Text
    $form.Text = "[Running] P12/PFX Certificate Toolkit (GUI)"
    
    if ($script:statusLabel) { 
        $script:statusLabel.Text = "Processed 0 / {0} files" -f $files.Count 
    }

    Invoke-P12Extraction `
        -OpenSSLPath $script:OpenSSLPath `
        -Files $files `
        -OutputFolder $outputFolder `
        -Password $password `
        -EncryptKey $script:chkEncryptKey.Checked `
        -StripHeaders $script:chkStripHeaders.Checked `
        -ExtractPEM $script:chkExtractPEM.Checked `
        -ExtractCER $script:chkExtractCER.Checked `
        -ExtractKey $script:chkExtractKey.Checked `
        -AppendCA $script:chkAppendCA.Checked `
        -CAFilePath $script:CAFilePath `
        -ProgressBar $script:ProgressBar `
        -LogBox $script:LogBox `
        -StatusLabel $script:statusLabel

    # UI state: finished/cancelled
    $script:btnStop.Enabled = $false
    $script:btnStart.Enabled = $true
    $script:lblRunStatus.Text = ""
    $form.Text = $oldTitle
    
    if ($script:LastExtractedPath -and (Test-Path $script:LastExtractedPath)) {
        $script:btnOpenFolder.Enabled = $true
        $script:btnOpenFolder.BackColor = [System.Drawing.Color]::LimeGreen
        Start-ButtonFlash -Button $script:btnOpenFolder
    }
    
    if ($script:LogToFileEnabled) { 
        Add-Log -Message ("===== Run completed {0} =====" -f (Get-Date))
    }
    
    # Close the app if user chose to exit after the run
    if ($form.Tag -eq 'ExitAfterRun') {
        $form.Close()
        return
    }
})

# Stop extraction
$script:btnStop.Add_Click({
    $script:StopRequested = $true
})

# Open extracted folder
$script:btnOpenFolder.Add_Click({
    if ($script:LastExtractedPath -and (Test-Path $script:LastExtractedPath)) {
        Start-Process $script:LastExtractedPath
    }
})

# Exit button
$script:btnExit.Add_Click({
    # If a run is active (Stop enabled or title shows running), offer choices
    $isRunning = $script:btnStop.Enabled -or ($form.Text -like "[Running]*")
    
    if ($isRunning) {
        $choice = [System.Windows.Forms.MessageBox]::Show(
            "Extraction is currently running.`r`n" +
            "Yes    = Stop now and exit`r`n" +
            "No     = Exit after current run finishes`r`n" +
            "Cancel = Do nothing",
            "Confirm Exit",
            [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        
        switch ($choice) {
            'Yes' {
                $script:StopRequested = $true
                $form.Tag = 'ExitAfterRun'
            }
            'No' { 
                $form.Tag = 'ExitAfterRun' 
            }
            default { 
                return 
            }
        }
    } 
    else {
        $form.Close()
    }
})

# Resize handlers
$form.Add_Resize({ 
    Update-BottomPanelLayout
    Update-ScrollableLayout 
})

$script:panelBottom.Add_Resize({ 
    Update-BottomPanelLayout 
})

#endregion Event Handlers

#region Script Variables

$script:OpenSSLPath = $null
$script:CAFilePath = $null
$script:LogToFileEnabled = $false
$script:LogFilePath = $null
$script:TranscriptPath = $null
$script:TranscriptEnabled = $false

#endregion Script Variables

#region Initialization

# Initial OpenSSL auto-check
$initial = Test-OpenSSL

if ($initial) {
    $script:OpenSSLPath = $initial
    $script:lblOpenSSL.ForeColor = $script:LightTheme.GoodColor
    $script:lblOpenSSL.Text = "✅ OpenSSL found at: {0}" -f $initial
    $script:btnTestOpenSSL.Enabled = $true
    $script:btnStart.Enabled = $true
} 
else {
    $script:lblOpenSSL.Text = "❌ OpenSSL not found. Click 'Select OpenSSL Folder...' to locate it."
}

# Apply initial theme
Set-Theme -Form $form -Theme $script:LightTheme

# Initial layout update
Update-ScrollableLayout
Update-BottomPanelLayout

#endregion Initialization

# Show the form
[void]$form.ShowDialog()
    