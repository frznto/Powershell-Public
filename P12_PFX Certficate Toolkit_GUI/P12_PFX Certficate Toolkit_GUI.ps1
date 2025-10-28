<#
.SYNOPSIS
  P12/PFX Certificate Toolkit (GUI): extract PEM, CER, and KEY from .p12/.pfx using OpenSSL
  with optional key encryption, header stripping, CA chain append (PEM only),
  dark mode, progress, logs, start/stop, fixed bottom button panel,
  "Open Extracted Folder" button, and a status bar showing processed counts.

.NOTES
  - Requires OpenSSL.
  - CER is DER (binary). Header stripping & CA append apply to PEM/KEY only.
  - OpenSSL portable Link: https://kb.firedaemon.com/support/solutions/articles/4000121705
  - Latest version as of 10/27/2025 "OpenSSL 3.6.0 ZIP x86+x64+ARM64"
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --------------------------
# Helper Functions
# --------------------------
function Test-OpenSSL {
  try { (Get-Command openssl.exe -ErrorAction Stop).Source } catch { $null }
}

function Select-OpenSSLExecutable {
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
    if ($common.Count -gt 0) { $ofd.InitialDirectory = $common[0] }
  } catch {}
  if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    if (Test-Path $ofd.FileName) { return $ofd.FileName }
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
      (Get-ChildItem -Path $fbd.SelectedPath -Filter openssl.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName)
    ) | Where-Object { $_ -and (Test-Path $_) }
    if ($candidates -and $candidates[0]) { return $candidates[0] }
    [System.Windows.Forms.MessageBox]::Show("openssl.exe not found under the selected path.","Error",
      [System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
  }
  return $null
}

function Get-P12Files {
  param(
    [Parameter(Mandatory=$true)][string]$FolderPath,
    [switch]$Recurse
  )

  if (-not (Test-Path -LiteralPath $FolderPath)) { return @() }

  # Primary: fast filters per extension (handles case-insensitivity)
  $common = @{
    LiteralPath = $FolderPath
    File        = $true
    Force       = $true
    ErrorAction = 'SilentlyContinue'
  }
  if ($Recurse) { $common.Recurse = $true }

  $files = @()
  $files += @(Get-ChildItem @common -Filter '*.p12')
  $files += @(Get-ChildItem @common -Filter '*.pfx')

  # Fallback: filter by Extension (covers weird providers / UNC quirks)
  if ($files.Count -eq 0) {
    $files = Get-ChildItem @common | Where-Object { $_.Extension -match '^\.(p12|pfx)$' }
  }

  return @($files)
}


function Run-OpenSSLTest {
  param([string]$OpenSSLPath)
  if (-not $OpenSSLPath -or -not (Test-Path $OpenSSLPath)) { return $null }
  try { & $OpenSSLPath version 2>$null } catch { $null }

}

function Validate-CAFile {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return $false }
  try {
    $firstKB = (Get-Content -Path $Path -TotalCount 50 -ErrorAction Stop)
    return ($firstKB -match '-----BEGIN CERTIFICATE-----')
  } catch { return $false }
}

function Add-Log {
  param(
    [Parameter(Mandatory = $true)][string]$Message,
    [switch]$NoUI
  )

  $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

  # UI sink (ListBox) — write directly, do NOT call Add-Log here
  if (-not $NoUI) {
    try {
      if ($null -ne $LogBox) {
        [void]$LogBox.Items.Add($Message)
        $LogBox.TopIndex = [Math]::Max(0, $LogBox.Items.Count - 1)
      }
    } catch { }
  }

  # File sink
  if ($script:LogToFileEnabled -and $script:LogFilePath) {
    try {
      Add-Content -LiteralPath $script:LogFilePath -Value "[$ts] $Message" -Encoding UTF8 -ErrorAction Stop
    } catch { }
  }
}


function Keep-OnlyPemEnvelope {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $false }
  try {
    $lines = Get-Content -LiteralPath $Path -ErrorAction Stop
    if (-not $lines) { return $false }

    $beginIdx = $null
    for ($i = 0; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -match '^\s*-----BEGIN\s.+-----\s*$') { $beginIdx = $i; break }
    }

    $endIdx = $null
    for ($j = $lines.Count - 1; $j -ge 0; $j--) {
      if ($lines[$j] -match '^\s*-----END\s.+-----\s*$') { $endIdx = $j; break }
    }

    if ($beginIdx -eq $null -or $endIdx -eq $null -or $endIdx -lt $beginIdx) { return $false }

    # Keep only from first BEGIN through last END (inclusive).
    $slice = $lines[$beginIdx..$endIdx]

    # Collapse multiple blank lines at the edges.
    while ($slice.Count -gt 0 -and [string]::IsNullOrWhiteSpace($slice[0])) { $slice = $slice[1..($slice.Count-1)] }
    while ($slice.Count -gt 0 -and [string]::IsNullOrWhiteSpace($slice[-1])) { $slice = $slice[0..($slice.Count-2)] }

    $slice | Set-Content -LiteralPath $Path -Encoding ascii
    return $true
  } catch { return $false }
}

# --------------------------
# Themes
# --------------------------
$LightTheme = @{
  FormBackColor    = [System.Drawing.Color]::White
  ForeColor        = [System.Drawing.Color]::Black
  ControlBackColor = [System.Drawing.Color]::White
  ListBackColor    = [System.Drawing.Color]::White
  ButtonBackColor  = [System.Drawing.Color]::Gainsboro
  PanelBackColor   = [System.Drawing.Color]::FromArgb(245,245,245)
  GoodColor        = [System.Drawing.Color]::Green
  BadColor         = [System.Drawing.Color]::Red
  StatusBackColor  = [System.Drawing.Color]::FromArgb(235,235,235)
}

$DarkTheme = @{
  FormBackColor    = [System.Drawing.Color]::FromArgb(30,30,30)
  ForeColor        = [System.Drawing.Color]::White
  ControlBackColor = [System.Drawing.Color]::FromArgb(45,45,45)
  ListBackColor    = [System.Drawing.Color]::FromArgb(40,40,40)
  ButtonBackColor  = [System.Drawing.Color]::FromArgb(70,70,70)
  PanelBackColor   = [System.Drawing.Color]::FromArgb(25,25,25)
  GoodColor        = [System.Drawing.Color]::LimeGreen
  BadColor         = [System.Drawing.Color]::Tomato
  StatusBackColor  = [System.Drawing.Color]::FromArgb(35,35,35)
}

function Apply-ThemeToControl {
  param($ctrl, $theme)
  if ($ctrl -is [System.Windows.Forms.TextBox]) {
    $ctrl.BackColor = $theme.ListBackColor
    $ctrl.ForeColor = $theme.ForeColor
  }
  elseif ($ctrl -is [System.Windows.Forms.ListBox]) {
    $ctrl.BackColor = $theme.ListBackColor
    $ctrl.ForeColor = $theme.ForeColor
  }
  elseif ($ctrl -is [System.Windows.Forms.Button]) {
    $ctrl.BackColor = $theme.ButtonBackColor
    $ctrl.ForeColor = $theme.ForeColor
  }
  elseif ($ctrl -is [System.Windows.Forms.Panel]) {
    $ctrl.BackColor = $theme.PanelBackColor
    foreach ($sub in $ctrl.Controls) { Apply-ThemeToControl $sub $theme }
    return
  }
  elseif ($ctrl -is [System.Windows.Forms.StatusStrip]) {
    $ctrl.BackColor = $theme.StatusBackColor
    foreach ($sub in $ctrl.Items) { $sub.ForeColor = $theme.ForeColor }
    return
  }
  else {
    $ctrl.BackColor = $theme.ControlBackColor
    $ctrl.ForeColor = $theme.ForeColor
  }

  if ($ctrl.Controls -and $ctrl.Controls.Count -gt 0) {
    foreach ($sub in $ctrl.Controls) { Apply-ThemeToControl $sub $theme }
  }
}

function Set-Theme {
  param($form, $theme)
  $form.BackColor = $theme.FormBackColor
  foreach ($ctrl in $form.Controls) { Apply-ThemeToControl $ctrl $theme }
}

# --------------------------
# Extraction logic
# --------------------------
$global:StopRequested     = $false
$global:LastExtractedPath = $null

function Extract-P12Files {
  param(
    [string]$OpenSSLPath,
    [System.Collections.ArrayList]$Files,
    [string]$OutputFolder,
    [string]$Password,
    [bool]$EncryptKey,
    [bool]$StripHeaders,
    [bool]$ExtractPEM,
    [bool]$ExtractCER,
    [bool]$ExtractKey,
    [bool]$AppendCA,
    [string]$CAFilePath,
    [System.Windows.Forms.ProgressBar]$ProgressBar,
    [System.Windows.Forms.ListBox]$LogBox,
    [System.Windows.Forms.ToolStripStatusLabel]$StatusLabel
  )

  $ProgressBar.Maximum = $Files.Count
  $ProgressBar.Value   = 0
  $LogBox.Items.Clear()

  $total    = $Files.Count
  $processed = 0
  if ($StatusLabel) { $StatusLabel.Text = "Processed $processed / $total files" }

  foreach ($file in $Files) {
    if ($global:StopRequested) { 
      Add-Log -Message "🛑 Extraction stopped by user."
      break 
    }

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file)
    $pemPath  = Join-Path $OutputFolder "$baseName.pem"
    $cerPath  = Join-Path $OutputFolder "$baseName.cer"
    $keyPath  = Join-Path $OutputFolder "$baseName.key"

    # Pre-clean any existing outputs to ensure a clean overwrite
    foreach ($p in @($pemPath,$cerPath,$keyPath)) {
      if ($p -and (Test-Path -LiteralPath $p)) {
        Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
      }
    }

        # Pre-clean any existing outputs to ensure a clean overwrite
    foreach ($p in @($pemPath,$cerPath,$keyPath)) {
      if ($p -and (Test-Path -LiteralPath $p)) {
        Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
      }
    }

    $successFlags = @()

    try {
      # CERT as PEM (text)
      if ($ExtractPEM) {
        $passIn = ('pass:{0}' -f $Password)
        & $OpenSSLPath pkcs12 -in $file.FullName -clcerts -nokeys -out $pemPath -passin $passIn 2>$null
        if (Test-Path $pemPath) {
          if ($StripHeaders) {
            if (-not (Keep-OnlyPemEnvelope -Path $pemPath)) {
                Add-Log -Message "⚠️ Failed to trim outside-PEM lines for $($file.Name) .pem"
            }
          }
          if ($AppendCA -and $CAFilePath) {
            if (Test-Path -LiteralPath $pemPath) {
                try {
                $pemRaw = Get-Content -LiteralPath $pemPath -Raw -ErrorAction Stop
                $caRaw  = Get-Content -LiteralPath $CAFilePath -Raw -ErrorAction Stop
                # Remove ALL trailing blank lines from PEM and ALL leading blank lines from CA.
                $pemRaw = $pemRaw -replace '(\r?\n)*\s*\z',''
                $caRaw  = $caRaw  -replace '^\s*(\r?\n)*',''
                # Join with a single line break so END and BEGIN are adjacent lines (no blank line).
                $combined = $pemRaw + "`r`n" + $caRaw
                Set-Content -LiteralPath $pemPath -Value $combined -Encoding ascii -NoNewline
                $successFlags += "PEM+CA"
                } catch {
                Add-Log -Message "❌ $($file.Name) → Failed to append CA to PEM: $_"
                $successFlags += "PEM"
                }
            } else {
                Add-Log -Message "❌ $($file.Name) → PEM not created, cannot append CA."
            }
            } else { $successFlags += "PEM" }
        }
      }

      # CERT as CER (DER/binary)
      if ($ExtractCER) {
        $passIn  = ('pass:{0}' -f $Password)
        $tempPem = [System.IO.Path]::GetTempFileName() + ".pem"
        try {
          & $OpenSSLPath pkcs12 -in $file.FullName -clcerts -nokeys -out $tempPem -passin $passIn 2>$null

         if (Test-Path -LiteralPath $tempPem) {
          & $OpenSSLPath x509 -in $tempPem -outform DER -out $cerPath 2>$null
         }
        }
        finally {
          if (Test-Path -LiteralPath $tempPem) {
            Remove-Item -LiteralPath $tempPem -Force -ErrorAction SilentlyContinue
          }
        }
        if (Test-Path $cerPath) { $successFlags += "CER" }
      }

      # PRIVATE KEY
      if ($ExtractKey) {
        if (-not $EncryptKey) {
          $passIn = ('pass:{0}' -f $Password)
          & $OpenSSLPath pkcs12 -in $file.FullName -nocerts -out $keyPath -nodes -passin $passIn 2>$null
        } else {
          $passIn  = ('pass:{0}' -f $Password)
          $passOut = ('pass:{0}' -f $Password)
          & $OpenSSLPath pkcs12 -in $file.FullName -nocerts -out $keyPath -passin  $passIn -passout $passOut 2>$null
        }
        & cmd /c $cmdKey 2>$null
        if (Test-Path $keyPath) {
          if ($StripHeaders) {
            if (-not (Keep-OnlyPemEnvelope -Path $keyPath)) {
                Add-Log -Message "⚠️ Failed to trim outside-PEM lines for $($file.Name) .key"
            }
          }
          $successFlags += ("KEY" + ($(if($EncryptKey){"(enc)"}else{"(noenc)"})))
        }
      }

      if ($successFlags.Count -gt 0) {
        if ($successFlags -contains "PEM+CA" -and $CAFilePath) {
          Add-Log -Message "✅ $($file.Name) → $($successFlags -join ', ') (CA: $(Split-Path -Path $CAFilePath -Leaf))"
        } else {
          Add-Log -Message "✅ $($file.Name) → $($successFlags -join ', ')"
        }
      } else {
        Add-Log -Message "❌ $($file.Name) → No outputs produced"
      }
    }
    catch {
      Add-Log -Message "❌ $($file.Name) → Error: $_"
    }

    $processed++
    $ProgressBar.Value = [Math]::Min($processed, $total)
    $StatusLabel.Text = "Processed $processed / $total files"
    $LogBox.TopIndex = $LogBox.Items.Count - 1
    Start-Sleep -Milliseconds 40
  }

  $global:LastExtractedPath = $OutputFolder
}

# --------------------------
# Flash Effect for "Open Folder" Button
# --------------------------
function Flash-Button {
  param($button)
  $orig = $button.BackColor
  for ($i=0; $i -lt 4; $i++) {
    $button.BackColor = [System.Drawing.Color]::Gold
    Start-Sleep -Milliseconds 150
    $button.BackColor = [System.Drawing.Color]::LimeGreen
    Start-Sleep -Milliseconds 150
  }
  $button.BackColor = $orig
}

# --------------------------
# GUI Setup
# --------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "P12/PFX Certificate Toolkit (GUI)"
$form.Size = New-Object System.Drawing.Size(800, 860)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = 'Sizable'
$form.AutoScroll = $true
$form.VerticalScroll.Visible = $true
$form.MinimumSize = New-Object System.Drawing.Size(800, 700)

# --- Top controls (scrollable content) ---

# Folder selection
$lblFolder = New-Object System.Windows.Forms.Label
$lblFolder.Location = New-Object System.Drawing.Point(20,50)
$lblFolder.Size = New-Object System.Drawing.Size(260,25)
$lblFolder.Text = "Select Folder with .p12 files:"
$form.Controls.Add($lblFolder)

$txtFolder = New-Object System.Windows.Forms.TextBox
$txtFolder.Location = New-Object System.Drawing.Point(280,45)
$txtFolder.Size = New-Object System.Drawing.Size(380,25)
$txtFolder.ReadOnly = $true
$txtFolder.Anchor="Top, Left, Right"
$form.Controls.Add($txtFolder)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Location = New-Object System.Drawing.Point(670,45)
$btnBrowse.Size = New-Object System.Drawing.Size(90,25)
$btnBrowse.Text = "Browse..."
$btnBrowse.Anchor="Top, Right"
$form.Controls.Add($btnBrowse)

# Dark mode toggle + Password
$chkDark = New-Object System.Windows.Forms.CheckBox
$chkDark.Location = New-Object System.Drawing.Point(670,10)
$chkDark.Anchor = "Top, Right"
$chkDark.Size = New-Object System.Drawing.Size(120,20)
$chkDark.Text = "Dark Mode"
$form.Controls.Add($chkDark)

$lblPwd = New-Object System.Windows.Forms.Label
$lblPwd.Location = New-Object System.Drawing.Point(160,110)
$lblPwd.Text = "P12 Password:"
$form.Controls.Add($lblPwd)

$txtPwd = New-Object System.Windows.Forms.TextBox
$txtPwd.Location = New-Object System.Drawing.Point(280,105)
$txtPwd.Size = New-Object System.Drawing.Size(380,25)
$txtPwd.PasswordChar = [char]0   # always show plaintext
$txtPwd.Anchor="Top, Left, Right"
$form.Controls.Add($txtPwd)

# P12 status
$lblP12Status = New-Object System.Windows.Forms.Label
$lblP12Status.Location = New-Object System.Drawing.Point(20,80)
$lblP12Status.Size = New-Object System.Drawing.Size(740,25)
$lblP12Status.ForeColor = 'Gray'
$lblP12Status.Text = "No folder selected."
$lblP12Status.Anchor="Top, Left, Right"
$form.Controls.Add($lblP12Status)

# Options row 1
$chkEncryptKey = New-Object System.Windows.Forms.CheckBox
$chkEncryptKey.Location = New-Object System.Drawing.Point(20,130)
$chkEncryptKey.Size = New-Object System.Drawing.Size(200,20)
$chkEncryptKey.Text = "Encrypt the key file"
$chkEncryptKey.Checked = $false   # default: unencrypted (-nodes)
$form.Controls.Add($chkEncryptKey)

$chkStripHeaders = New-Object System.Windows.Forms.CheckBox
$chkStripHeaders.Location = New-Object System.Drawing.Point(240,130)
$chkStripHeaders.Size = New-Object System.Drawing.Size(320,20)
$chkStripHeaders.Text = "Strip headers from .pem and .key files"
$chkStripHeaders.Checked = $true
$form.Controls.Add($chkStripHeaders)

# Options row 2 (what to extract)
$chkExtractPEM = New-Object System.Windows.Forms.CheckBox
$chkExtractPEM.Location = New-Object System.Drawing.Point(20,160)
$chkExtractPEM.Size = New-Object System.Drawing.Size(120,20)
$chkExtractPEM.Text = "Extract PEM"
$chkExtractPEM.Checked = $true
$form.Controls.Add($chkExtractPEM)

$chkExtractCER = New-Object System.Windows.Forms.CheckBox
$chkExtractCER.Location = New-Object System.Drawing.Point(160,160)
$chkExtractCER.Size = New-Object System.Drawing.Size(120,20)
$chkExtractCER.Text = "Extract CER"
$chkExtractCER.Checked = $false
$form.Controls.Add($chkExtractCER)

$chkExtractKey = New-Object System.Windows.Forms.CheckBox
$chkExtractKey.Location = New-Object System.Drawing.Point(300,160)
$chkExtractKey.Size = New-Object System.Drawing.Size(120,20)
$chkExtractKey.Text = "Extract Key"
$chkExtractKey.Checked = $true
$form.Controls.Add($chkExtractKey)

# CA chain append (PEM only)
$chkAppendCA = New-Object System.Windows.Forms.CheckBox
$chkAppendCA.Location = New-Object System.Drawing.Point(20,190)
$chkAppendCA.Size = New-Object System.Drawing.Size(320,20)
$chkAppendCA.Text = "Append IA/Root CA information to PEM files"
$chkAppendCA.Checked = $false
$form.Controls.Add($chkAppendCA)

$btnSelectCA = New-Object System.Windows.Forms.Button
$btnSelectCA.Location = New-Object System.Drawing.Point(350,188)
$btnSelectCA.Size = New-Object System.Drawing.Size(130,24)
$btnSelectCA.Text = "Select CA File..."
$btnSelectCA.Enabled = $false
$form.Controls.Add($btnSelectCA)

$lblCAPath = New-Object System.Windows.Forms.Label
$lblCAPath.Location = New-Object System.Drawing.Point(490,190)
$lblCAPath.Size = New-Object System.Drawing.Size(270,20)
$lblCAPath.ForeColor = 'Gray'
$lblCAPath.Text = ""
$lblCAPath.AutoEllipsis = $true
$lblCAPath.Anchor = "Top, Left, Right"
$form.Controls.Add($lblCAPath)

# Logging options
$chkLogToFile = New-Object System.Windows.Forms.CheckBox
$chkLogToFile.Location = New-Object System.Drawing.Point(20,215)
$chkLogToFile.Size = New-Object System.Drawing.Size(140,20)
$chkLogToFile.Text = "Write to log file"
$chkLogToFile.Checked = $false
$form.Controls.Add($chkLogToFile)

$btnBrowseLog = New-Object System.Windows.Forms.Button
$btnBrowseLog.Location = New-Object System.Drawing.Point(160,213)
$btnBrowseLog.Size = New-Object System.Drawing.Size(130,24)
$btnBrowseLog.Text = "Select Log File..."
$btnBrowseLog.Enabled = $false
$form.Controls.Add($btnBrowseLog)

$lblLogPath = New-Object System.Windows.Forms.Label
$lblLogPath.Location = New-Object System.Drawing.Point(300,215)
$lblLogPath.Size = New-Object System.Drawing.Size(460,20)
$lblLogPath.ForeColor = 'Gray'
$lblLogPath.AutoEllipsis = $true
$lblLogPath.Anchor = "Top, Left, Right"
$form.Controls.Add($lblLogPath)

# Files list
$listP12Files = New-Object System.Windows.Forms.ListBox
$listP12Files.MultiColumn = $false
$listP12Files.HorizontalScrollbar = $true
$listP12Files.ScrollAlwaysVisible = $true
$listP12Files.IntegralHeight = $false
$listP12Files.DrawMode = 'Normal'
$listP12Files.Location = New-Object System.Drawing.Point(20,250)
$listP12Files.Size = New-Object System.Drawing.Size(740,300)
$listP12Files.Anchor = "Top, Left, Right, Bottom"
$form.Controls.Add($listP12Files)

# Progress + Log
$ProgressBar = New-Object System.Windows.Forms.ProgressBar
$ProgressBar.Location = New-Object System.Drawing.Point(20,530)
$ProgressBar.Size = New-Object System.Drawing.Size(740,25)
$ProgressBar.Style = 'Continuous'
$ProgressBar.Anchor="Bottom, Left, Right"
$form.Controls.Add($ProgressBar)

$LogBox = New-Object System.Windows.Forms.ListBox
$LogBox.Location = New-Object System.Drawing.Point(20,560)
$LogBox.Size = New-Object System.Drawing.Size(740,190)
$LogBox.Anchor="Bottom, Left, Right"
$form.Controls.Add($LogBox)

# OpenSSL status label (in scroll area)
$lblOpenSSL = New-Object System.Windows.Forms.Label
$lblOpenSSL.Location = New-Object System.Drawing.Point(20,755)
$lblOpenSSL.Size = New-Object System.Drawing.Size(740,30)
$lblOpenSSL.ForeColor = 'Red'
$lblOpenSSL.Anchor = "Bottom, Left, Right"
$form.Controls.Add($lblOpenSSL)

# --- Bottom panel (always visible) ---
$panelBottom = New-Object System.Windows.Forms.Panel
$panelBottom.Dock = 'Bottom'
$panelBottom.Height = 60
$panelBottom.BackColor = $LightTheme.PanelBackColor
$form.Controls.Add($panelBottom)

# --- Status bar (very bottom, below the panel) ---
$script:statusStrip = New-Object System.Windows.Forms.StatusStrip
$script:statusStrip.Dock = 'Bottom'              # add AFTER panelBottom so it sits at the very bottom
$form.Controls.Add($script:statusStrip)

$script:statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$script:statusLabel.Text = "Processed 0 / 0 files"
[void]$script:statusStrip.Items.Add($script:statusLabel)

$lblRunStatus = New-Object System.Windows.Forms.Label
$lblRunStatus.Location = New-Object System.Drawing.Point(10,20)
$lblRunStatus.AutoSize = $true
$lblRunStatus.Text = ""  # set to "Running..." during extraction
$panelBottom.Controls.Add($lblRunStatus)

$btnOpenFolder = New-Object System.Windows.Forms.Button
$btnOpenFolder.Size = New-Object System.Drawing.Size(180,36)
$btnOpenFolder.Location = New-Object System.Drawing.Point(130,15)
$btnOpenFolder.Text = "📂 Open Extracted Folder"
$btnOpenFolder.Enabled = $false
$panelBottom.Controls.Add($btnOpenFolder)

$btnCheckOpenSSL = New-Object System.Windows.Forms.Button
$btnCheckOpenSSL.Size = New-Object System.Drawing.Size(220,36)
$btnCheckOpenSSL.Location = New-Object System.Drawing.Point(320,15)
$btnCheckOpenSSL.Text = "Select OpenSSL Folder..."
$panelBottom.Controls.Add($btnCheckOpenSSL)

$btnTestOpenSSL = New-Object System.Windows.Forms.Button
$btnTestOpenSSL.Size = New-Object System.Drawing.Size(120,36)
$btnTestOpenSSL.Location = New-Object System.Drawing.Point(470,15)
$btnTestOpenSSL.Text = "Test OpenSSL"
$btnTestOpenSSL.Enabled = $false
$panelBottom.Controls.Add($btnTestOpenSSL)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Size = New-Object System.Drawing.Size(130,36)
$btnStart.Location = New-Object System.Drawing.Point(600,15)
$btnStart.Text = "Start Extraction"
$btnStart.Enabled = $false
$panelBottom.Controls.Add($btnStart)

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Size = New-Object System.Drawing.Size(80,36)
$btnStop.Location = New-Object System.Drawing.Point(735,15)
$btnStop.Text = "Stop"
$btnStop.Enabled = $false
$panelBottom.Controls.Add($btnStop)

# Exit button
$btnExit = New-Object System.Windows.Forms.Button
$btnExit.Size = New-Object System.Drawing.Size(90,36)
$btnExit.Text = "Exit"
$panelBottom.Controls.Add($btnExit)

# ---- BEGIN: Responsive bottom buttons/layout helpers ----
function Center-BottomPanelButtons {
  $padding = 10
  $spacing = 10

  # Collect buttons in display order
  $buttons = @()
  foreach ($ctrl in $panelBottom.Controls) {
    if ($ctrl -is [System.Windows.Forms.Button]) { $buttons += $ctrl }
  }
  if ($buttons.Count -eq 0) { return }

    # Auto-size bottom panel to fit the tallest button (prevents clipping)
  $vpad = 12
  $maxBtnH = ($buttons | Measure-Object -Property Height -Maximum).Maximum
  $panelBottom.Height = [Math]::Max([int]$maxBtnH + (2 * $vpad), 60)

  # Cache original widths once (so we can scale predictably)
  foreach ($b in $buttons) {
    if (-not $b.Tag) { $b.Tag = [int]$b.Width }  # store baseline width in Tag
  }

  # Compute total width (baseline) and available width
  $baselineTotal = 0
  foreach ($b in $buttons) { $baselineTotal += [int]$b.Tag + $spacing }
  if ($buttons.Count -gt 0) { $baselineTotal -= $spacing }

  $available = [Math]::Max(100, $panelBottom.ClientSize.Width - (2 * $padding))

  # Scale down if needed (min 80px per button)
  $scale = 1.0
  if ($baselineTotal -gt $available) {
    $scale = $available / [double]$baselineTotal
    if ($scale -lt 0.7) { $scale = 0.7 }  # don’t shrink beyond ~70% unless absolutely necessary
  }

  # First pass: set widths with scale, clamp at 80 min
  $actualTotal = 0
  foreach ($b in $buttons) {
    $newWidth = [Math]::Max(80, [int][Math]::Floor([double]$b.Tag * $scale))
    $b.Width = $newWidth
    $actualTotal += $newWidth + $spacing
  }
  if ($buttons.Count -gt 0) { $actualTotal -= $spacing }

  # Reduce spacing if still overflowing
  if ($actualTotal -gt $available) {
    $spacing = 5
    $actualTotal = 0
    foreach ($b in $buttons) { $actualTotal += $b.Width + $spacing }
    if ($buttons.Count -gt 0) { $actualTotal -= $spacing }
  }

  # Final X start (centered; left-align if still too wide)
  $startX = [Math]::Max($padding, [int][Math]::Floor(($panelBottom.ClientSize.Width - $actualTotal) / 2))

  # Vertically center label; place buttons on a single row
  $lblRunStatus.Location = New-Object System.Drawing.Point($padding, [Math]::Max(5, [int][Math]::Floor(($panelBottom.ClientSize.Height - $lblRunStatus.Height) / 2)))

  $x = $startX
  foreach ($b in $buttons) {
    $b.Location = New-Object System.Drawing.Point($x, [int][Math]::Floor(($panelBottom.ClientSize.Height - $b.Height) / 2))
    $x += $b.Width + $spacing
  }
}

function Adjust-ScrollableLayout {
  # Keep the OpenSSL label just above the bottom panel and resize the log box to fit.
  $padding = 10

  # Compute available height for the log box so it doesn’t collide with the bottom panel or the OpenSSL label
  $panelH  = $panelBottom.Height
  $statusH = $statusStrip.Height
  $labelH  = $lblOpenSSL.Height

  # Target: LogBox bottom + label + padding should sit above the bottom panel
  $available = $form.ClientSize.Height - $ProgressBar.Bottom - $panelH - $statusH - (2 * $padding) - $labelH
  if ($available -lt 80) { $available = 80 }   # don’t collapse too far
  $LogBox.Height = $available

  # Place the OpenSSL label directly beneath the LogBox with padding
  $lblOpenSSL.Top = $LogBox.Bottom + $padding

  # Safety: ensure label never overlaps the bottom panel
  $maxTop = $panelBottom.Top - $labelH - $padding
  if ($lblOpenSSL.Top -gt $maxTop) { $lblOpenSSL.Top = $maxTop }
}

# Recenter/reflow on resize and once at startup
$form.Add_Resize({ Center-BottomPanelButtons; Adjust-ScrollableLayout })
$panelBottom.Add_Resize({ Center-BottomPanelButtons })
Adjust-ScrollableLayout
Center-BottomPanelButtons
# ---- END: Responsive bottom buttons/layout helpers ----


# --------------------------
# Logic / Event wiring
# --------------------------
$script:OpenSSLPath = $null
$script:CAFilePath = $null
$script:LogToFileEnabled = $false
$script:LogFilePath      = $null

# Theme
$chkDark.Add_CheckedChanged({
  if ($chkDark.Checked) { 
    Set-Theme -form $form -theme $DarkTheme
    $lblOpenSSL.ForeColor = $DarkTheme.BadColor
  } else { 
    Set-Theme -form $form -theme $LightTheme
    $lblOpenSSL.ForeColor = $LightTheme.BadColor
  }
})
Set-Theme -form $form -theme $LightTheme

# Browse for P12 folder
$btnBrowse.Add_Click({
  $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
  $dialog.Description = "Select folder containing .p12/.pfx files"
  if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    $selected = (Resolve-Path -LiteralPath $dialog.SelectedPath -ErrorAction SilentlyContinue).Path
    if (-not $selected) { $selected = $dialog.SelectedPath.Trim() }
    $txtFolder.Text = $selected
    Add-Log -Message "📁 Selected folder: $selected"

    $listP12Files.Items.Clear()
    $files = @(Get-P12Files -FolderPath $selected)

    if ($files.Count -gt 0) {
      $lblP12Status.ForeColor = $(if ($chkDark.Checked) { $DarkTheme.GoodColor } else { $LightTheme.GoodColor })
      $lblP12Status.Text = "✅ Found $($files.Count) .p12/.pfx files:"
      [string[]]$__paths = $files | ForEach-Object { $_.FullName }
      [void]$listP12Files.Items.AddRange($__paths)
    } else {
      $lblP12Status.ForeColor = $(if ($chkDark.Checked) { $DarkTheme.BadColor } else { $LightTheme.BadColor })
      $lblP12Status.Text = "❌ No .p12 or .pfx files found."
    }

    Add-Log -Message "🔍 Browse check: detected $($files.Count) file(s) in: $selected"
  }
})


# CA option & selection
$chkAppendCA.Add_CheckedChanged({
  $btnSelectCA.Enabled = $chkAppendCA.Checked
  if (-not $chkAppendCA.Checked) {
    # Clear the script-scoped CA path and label when unchecked
    $script:CAFilePath = $null
    $lblCAPath.Text = ""
  }
  elseif (-not $chkExtractPEM.Checked) {
    # Inform user that Append CA requires Extract PEM
    Add-Log -Message "ℹ️ Note: 'Append CA' requires 'Extract PEM'. Enable 'Extract PEM' before starting."
  }
})

$btnSelectCA.Add_Click({
  $ofd = New-Object System.Windows.Forms.OpenFileDialog
  $ofd.Title = "Select CA Chain File (PEM)"
  $ofd.Filter = "PEM Files (*.pem)|*.pem|All Files (*.*)|*.*"
  $ofd.Multiselect = $false
  if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    if (Validate-CAFile -Path $ofd.FileName) {
      $script:CAFilePath = $ofd.FileName
      $lblCAPath.Text = $script:CAFilePath
      $lblCAPath.ForeColor = $(if($chkDark.Checked){$DarkTheme.GoodColor}else{$LightTheme.GoodColor})
      Add-Log -Message "🔗 CA chain selected: $(Split-Path -Path $script:CAFilePath -Leaf)"
    } else {
      $script:CAFilePath = $null
      $lblCAPath.Text = "Invalid CA file (must be PEM with BEGIN CERTIFICATE)."
      $lblCAPath.ForeColor = $(if($chkDark.Checked){$DarkTheme.BadColor}else{$LightTheme.BadColor})
      [System.Windows.Forms.MessageBox]::Show(
        "Selected file doesn't look like a PEM CA bundle. It must contain '-----BEGIN CERTIFICATE-----'.",
        "Invalid CA file",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
      ) | Out-Null
    }
  }
})


$chkLogToFile.Add_CheckedChanged({
  $btnBrowseLog.Enabled = $chkLogToFile.Checked
  if (-not $chkLogToFile.Checked) {
    $script:LogToFileEnabled = $false
    $script:LogFilePath = $null
    $lblLogPath.Text = ""
    Add-Log -Message "Logging to file disabled."
  } else {
    Add-Log -Message "Logging to file enabled."
  }
})

$btnBrowseLog.Add_Click({
  $sfd = New-Object System.Windows.Forms.SaveFileDialog
  $sfd.Title = "Select log file"
  $sfd.Filter = "Text files (*.txt)|*.txt|All files (*.*)|*.*"
  $sfd.AddExtension = $true
  $sfd.DefaultExt = "txt"
  $sfd.OverwritePrompt = $false
  $initialDir = $txtFolder.Text
  if (-not (Test-Path -LiteralPath $initialDir)) { $initialDir = [Environment]::GetFolderPath('Desktop') }
  $sfd.InitialDirectory = $initialDir
  $sfd.FileName = "ExtractLog_{0}.txt" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')
  if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    $script:LogFilePath = $sfd.FileName
    $lblLogPath.Text = $script:LogFilePath
    $script:LogToFileEnabled = $true
    Add-Log -Message ("Log file set: " + $script:LogFilePath)
  }
})

# OpenSSL checks
$btnCheckOpenSSL.Add_Click({
  $found = Test-OpenSSL
  if ($found) {
    $script:OpenSSLPath = $found
    $lblOpenSSL.ForeColor = $(if($chkDark.Checked){$DarkTheme.GoodColor}else{$LightTheme.GoodColor})
    $lblOpenSSL.Text="✅ OpenSSL found at: $found"
    $btnTestOpenSSL.Enabled=$true
    $btnStart.Enabled=$true
  } else {
    $lblOpenSSL.ForeColor = $(if($chkDark.Checked){$DarkTheme.BadColor}else{$LightTheme.BadColor})
    $lblOpenSSL.Text="❌ OpenSSL not found in PATH. Click 'Select OpenSSL Folder...' to browse."

    $manual = Select-OpenSSLExecutable
    if ($manual) {
      $script:OpenSSLPath = $manual
      $lblOpenSSL.ForeColor = $(if($chkDark.Checked){$DarkTheme.GoodColor}else{$LightTheme.GoodColor})
      $lblOpenSSL.Text="✅ Using manual OpenSSL path: $manual"
      $btnTestOpenSSL.Enabled=$true
      $btnStart.Enabled=$true
    }
  }
})
$btnTestOpenSSL.Add_Click({
  $ver = Run-OpenSSLTest -OpenSSLPath $script:OpenSSLPath
  if ($ver) { [System.Windows.Forms.MessageBox]::Show("OpenSSL Test Successful:`n$ver","Success") }
  else { [System.Windows.Forms.MessageBox]::Show("Failed to execute OpenSSL.","Error") }
})

# Start / Stop / Open Folder
$btnStart.Add_Click({
  if (-not $script:OpenSSLPath) { return }
  $folder   = $txtFolder.Text.Trim()
  $password = $txtPwd.Text

  if (-not $password) { [System.Windows.Forms.MessageBox]::Show("Please enter the P12 password first.","Error"); return }
  if (-not (Test-Path -LiteralPath $folder)) { [System.Windows.Forms.MessageBox]::Show("Please select a valid folder first.","Error"); return }
  if ($chkAppendCA.Checked -and -not (Test-Path -LiteralPath $script:CAFilePath)) {
    [System.Windows.Forms.MessageBox]::Show("Please select a valid CA chain file (PEM) or uncheck the option.","CA Chain Required",
      [System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    return
  }
  if ($chkAppendCA.Checked -and -not $chkExtractPEM.Checked) {
    [System.Windows.Forms.MessageBox]::Show("To append the CA chain, 'Extract PEM' must be selected.","Enable Extract PEM",
      [System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    return
  }

  $outputFolder = Join-Path $folder "Extracted"
  $OverwriteExisting = $true

  if (Test-Path -LiteralPath $outputFolder) {
    $existing = @(Get-ChildItem -LiteralPath $outputFolder -File -Force -ErrorAction SilentlyContinue |
                  Where-Object { $_.Extension -in '.pem','.cer','.key' })
    if ($existing.Count -gt 0) {
      $choice = [System.Windows.Forms.MessageBox]::Show(
        "The 'Extracted' folder already exists and contains files." + [Environment]::NewLine +
        "Yes  = Overwrite in the same folder" + [Environment]::NewLine +
        "No   = Create a new timestamped folder" + [Environment]::NewLine +
        "Cancel = Abort",
        "Extracted Folder Exists",
        [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
        [System.Windows.Forms.MessageBoxIcon]::Question
      )
      switch ($choice) {
        'Yes'    { $OverwriteExisting = $true }
        'No'     {
          $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
          $outputFolder = Join-Path $folder ("Extracted_" + $stamp)
          New-Item -ItemType Directory -Path $outputFolder | Out-Null
          $OverwriteExisting = $false
        }
        default  { return }
      }
    }
  } else {
    New-Item -ItemType Directory -Path $outputFolder | Out-Null
  }

  Add-Log -Message "📦 Output folder: $outputFolder$(if ($OverwriteExisting) { ' (overwrite)' } else { ' (new)' })"

  # If logging is enabled but no path chosen yet, default to output folder
  if ($chkLogToFile.Checked) {
    if (-not $script:LogFilePath) {
      $script:LogToFileEnabled = $true
      $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
      $script:LogFilePath = Join-Path $outputFolder ("ExtractLog_{0}.txt" -f $stamp)
      try { New-Item -ItemType File -Path $script:LogFilePath -Force | Out-Null } catch {}
      $lblLogPath.Text = $script:LogFilePath
    } else {
      $script:LogToFileEnabled = $true
    }
    Add-Log -Message ("===== Run started {0} =====" -f (Get-Date))
    $ver = Run-OpenSSLTest -OpenSSLPath $script:OpenSSLPath
    if ($ver) { Add-Log -Message ("OpenSSL: " + $ver) } else { Add-Log -Message "OpenSSL: (unknown)" }
    Add-Log -Message ("Options: ExtractPEM={0}, ExtractCER={1}, ExtractKey={2}, EncryptKey={3}, StripHeaders={4}, AppendCA={5}" -f `
        $chkExtractPEM.Checked, $chkExtractCER.Checked, $chkExtractKey.Checked, $chkEncryptKey.Checked, $chkStripHeaders.Checked, $chkAppendCA.Checked)
    if ($chkAppendCA.Checked -and $script:CAFilePath) { Add-Log -Message ("CA File: " + $script:CAFilePath) }
  } else {
    $script:LogToFileEnabled = $false
    $script:LogFilePath = $null
  }

  $files = @(Get-P12Files -FolderPath $folder)
  Add-Log -Message "▶️ Start: folder = $folder"
  Add-Log -Message "🔎 Start check: detected $($files.Count) file(s) in: $folder"
  if ($chkAppendCA.Checked) {
    if (Test-Path -LiteralPath $script:CAFilePath) {
      Add-Log -Message ("🔗 CA chain: " + (Split-Path $script:CAFilePath -Leaf))
    } else {
      Add-Log -Message "⚠️ CA chain path is invalid or missing."
    }
  }
  if ($files.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show("No .p12/.pfx files found.","Error"); return }

  # UI state: running
  $global:StopRequested = $false
  $btnStart.Enabled = $false
  $btnStop.Enabled  = $true
  $btnOpenFolder.Enabled = $false
  $lblRunStatus.Text = "Running..."
  $lblRunStatus.ForeColor = $(if($chkDark.Checked){$DarkTheme.GoodColor}else{$LightTheme.GoodColor})
  $oldTitle = $form.Text
  $form.Text = "[Running] P12/PFX Certificate Toolkit (GUI)"
  if ($script:statusLabel) { $script:statusLabel.Text = "Processed 0 / $($files.Count) files" }

  Extract-P12Files -OpenSSLPath $script:OpenSSLPath -Files $files -OutputFolder $outputFolder `
    -Password $password -EncryptKey:$chkEncryptKey.Checked -StripHeaders:$chkStripHeaders.Checked `
    -ExtractPEM:$chkExtractPEM.Checked -ExtractCER:$chkExtractCER.Checked -ExtractKey:$chkExtractKey.Checked `
    -AppendCA:$chkAppendCA.Checked -CAFilePath $script:CAFilePath -ProgressBar $ProgressBar -LogBox $LogBox -StatusLabel $script:statusLabel

  # UI state: finished/cancelled
  $btnStop.Enabled  = $false
  $btnStart.Enabled = $true
  $lblRunStatus.Text = ""
  $form.Text = $oldTitle
  if ($global:LastExtractedPath -and (Test-Path $global:LastExtractedPath)) {
    $btnOpenFolder.Enabled = $true
    $btnOpenFolder.BackColor = [System.Drawing.Color]::LimeGreen
    Flash-Button $btnOpenFolder
  }
  if ($script:LogToFileEnabled) { Add-Log -Message ("===== Run completed {0} =====" -f (Get-Date)) }
  if ($form.Tag -eq 'ExitAfterRun') { $form.Close(); return }
})

    # Close the app if user chose to exit after the run
    if ($form.Tag -eq 'ExitAfterRun') {
    $form.Close()
    return
    }

$btnStop.Add_Click({
  $global:StopRequested = $true
})

$btnOpenFolder.Add_Click({
  if ($global:LastExtractedPath -and (Test-Path $global:LastExtractedPath)) {
    Start-Process $global:LastExtractedPath
  }
})

$btnExit.Add_Click({
  # If a run is active (Stop enabled or title shows running), offer choices
  $isRunning = $btnStop.Enabled -or ($form.Text -like "[Running]*")
  if ($isRunning) {
    $choice = [System.Windows.Forms.MessageBox]::Show(
      "Extraction is currently running." + [Environment]::NewLine +
      "Yes    = Stop now and exit" + [Environment]::NewLine +
      "No     = Exit after current run finishes" + [Environment]::NewLine +
      "Cancel = Do nothing",
      "Confirm Exit",
      [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
      [System.Windows.Forms.MessageBoxIcon]::Question
    )
    switch ($choice) {
      'Yes' {
        $global:StopRequested = $true
        $form.Tag = 'ExitAfterRun'
      }
      'No'  { $form.Tag = 'ExitAfterRun' }
      default { return }
    }
  } else {
    $form.Close()
  }
})

# Initial OpenSSL auto-check (label only)
$initial = Test-OpenSSL
if ($initial) {
  $script:OpenSSLPath = $initial
  $lblOpenSSL.ForeColor = $LightTheme.GoodColor
  $lblOpenSSL.Text="✅ OpenSSL found at: $initial"
  $btnTestOpenSSL.Enabled=$true
  $btnStart.Enabled=$true
} else {
  $lblOpenSSL.Text="❌ OpenSSL not found. Click 'Select OpenSSL Folder...' to locate it."
}

# Initial theme
Set-Theme -form $form -theme $LightTheme

[void]$form.ShowDialog()
