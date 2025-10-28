# P12/PFX Certificate Toolkit (GUI)
This GUI was designed and generated from ChatGPT.

Some places do not allow for automation against Certificate Authorities and as such will allow for bulk generation of certificates from a csv.
The goal of this GUI script is to allow for easier extraction of the pem/cer and/or key files with some extra possibly needed features.
This script also allows running from a computer with non admin rights via the use of a portable version of OpenSSL. 
OpenSSL portable Link: https://kb.firedaemon.com/support/solutions/articles/4000121705
Latest version "OpenSSL 3.6.0 ZIP x86+x64+ARM64"

A Windows PowerShell **WinForms** utility to extract **PEM**, **CER (DER)**, and **KEY** files from `.p12/.pfx` bundles using **OpenSSL**.  
Includes optional **key encryption**, **header stripping** (keeps BEGIN/END, removes outside noise), **append IA/Root CA to PEM**, **progress + status bar**, **Stop/Exit**, **DPI-aware layout**, **Dark Mode**, and **optional file logging**.

> ✅ Designed for ops teams automating certificate handling across VMware/ESXi and similar environments.

---

## Features

- **Folder-based extraction**: Select a folder containing `.p12/.pfx` files; processes each one.
- **Outputs**  
  - **PEM** (leaf certificate, text) — can **append** your IA/Root CA bundle (PEM) without blank lines.  
  - **CER** (DER/binary) — leaf certificate only.  
  - **KEY** (private key) — encrypted (PKCS#8) or unencrypted (`-nodes`) per option.
- **Strip Headers from .pem and .key files**  
  Preserves the `-----BEGIN …-----` / `-----END …-----` envelope; removes all lines **before** the first `BEGIN` and **after** the last `END`.  
  (Does **not** remove `Proc-Type:` / `DEK-Info:` encryption metadata inside a legacy PEM envelope.)
- **OpenSSL discovery**  
  Auto-detects from `PATH`; otherwise “**Select OpenSSL Folder…**” (handles common `bin\` layouts). “**Test OpenSSL**” prints version.
- **Progress & status**  
  List of found files, per-file results, and a status bar: **Processed X / Y files**.
- **Safe overwrite behavior**  
  If `Extracted` exists, choose: **Overwrite** or create **Extracted_YYYY-MM-DD_HH-mm-ss**.
- **Optional file logging**  
  “Write to log file” + “Select Log File…”. All in-UI logs tee to file when enabled.
- **Stop / Exit**  
  Stop mid-run; Exit immediately or after run completion.
- **Dark Mode & DPI-aware layout**  
  Looks clean on 100–200% scaling and 1080p–4K displays.

---

## Requirements

- **Windows** (PowerShell 5.1 or PowerShell 7+)
- **OpenSSL** (not bundled)  
  - Any standard Windows build (e.g., `C:\Program Files\OpenSSL-Win64\bin\openssl.exe`)
- Execution policy that allows running local scripts:
  ```powershell
  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
  ```
- Unblock files if downloaded:
  ```powershell
  Unblock-File .\P12PFX_Certificate_Toolkit_GUI.ps1
  ```

---

## Getting Started

1. **OpenSSL**  
   - If `openssl.exe` is on `PATH`, the app shows **OpenSSL found**.  
   - Otherwise click **Select OpenSSL Folder…** and point to the folder that contains `openssl.exe` (tool also checks common `bin\` subfolders).  
   - Click **Test OpenSSL** to verify.

2. **Select input folder**  
   - Click **Browse…** and choose a folder with `.p12/.pfx` files.  
   - You can **edit the path inline** (textbox supports filesystem autocomplete). Press **Enter** to refresh.

3. **Enter the P12 password**  
   - The box shows plaintext for operational clarity (your call).

4. **Options**  
   - **Extract PEM / CER / Key** (choose any or all).  
   - **Encrypt the key file** (unchecked by default → unencrypted key, i.e., OpenSSL `-nodes`).  
   - **Strip Headers from .pem and .key files** (recommended): keeps only the BEGIN/END envelope.  
   - **Append IA/Root CA to PEM files** → choose your **PEM** bundle (applies to PEM only).

5. **Run**  
   - Click **Start Extraction**.  
   - If `Extracted` exists, choose **Overwrite** or **create timestamped folder**.  
   - Use **Stop** to cancel early. **Exit** can stop now or close after finishing.  
   - **Open Extracted Folder** highlights when outputs are ready.

---

## Output Details

- **PEM**: leaf certificate (`-----BEGIN CERTIFICATE----- …`)  
  - If **Append IA/Root CA** is enabled, the CA bundle is appended with **no blank lines**.
- **CER (DER)**: binary leaf certificate (no headers, not concatenated).  
- **KEY**:  
  - **Encrypted PKCS#8** if “Encrypt the key file” is checked (OpenSSL will prompt/derive from your provided password).  
  - **Unencrypted** if unchecked (uses `-nodes`).  
  - The **strip headers** option never removes the envelope or required metadata inside the BEGIN/END block.

> **Note:** Appending CA affects **PEM** only. CER is DER and cannot contain a chain.

---

## Logging

- Toggle **Write to log file** to tee UI messages to a timestamped log in the output folder (or pick a path via **Select Log File…**).
- Typical events: OpenSSL status, counts, per-file results, CA bundle selection, start/stop markers.

---

## Building a Standalone EXE (optional)

Use **PS2EXE** (free):

```powershell
Install-Module ps2exe -Scope CurrentUser -Force

$In  = ".\P12PFX_Certificate_Toolkit_GUI.ps1"
$Out = ".\P12PFX-Cert-Toolkit.exe"
$Ico = ".\cert.ico"   # optional

Invoke-ps2exe `
  -InputFile   $In `
  -OutputFile  $Out `
  -NoConsole `
  -STA `
  -Title       "P12/PFX Certificate Toolkit (GUI)" `
  -ProductName "P12/PFX Certificate Toolkit" `
  -CompanyName "CompanyName" `
  -FileVersion "1.6.0.0" `
  -ProductVersion "1.6.0.0" `
  -IconPath    $Ico
```

**Code signing** (recommended to reduce AV/SmartScreen prompts):
```powershell
& "C:\Program Files (x86)\Windows Kits\10\bin\x64\signtool.exe" sign `
   /fd SHA256 /a /tr http://timestamp.digicert.com /td SHA256 `
   /n "GCI" ".\P12PFX-Cert-Toolkit.exe"
```

---

## Troubleshooting

- **“OpenSSL not found”**  
  Use **Select OpenSSL Folder…** and point at the directory containing `openssl.exe`; click **Test OpenSSL**.

- **“A positional parameter cannot be found that accepts argument ‘+’.”**  
  This happens when a log line is written like:  
  `Add-Log -Message "text" + $var`  
  Use subexpressions instead:  
  `Add-Log -Message "text $($var)"`

- **Encrypted vs unencrypted key**  
  - `-----BEGIN ENCRYPTED PRIVATE KEY-----` → encrypted PKCS#8  
  - `-----BEGIN PRIVATE KEY-----` → unencrypted PKCS#8  
  - `Proc-Type: 4,ENCRYPTED` inside legacy PEM → encrypted  
  You can also validate with `openssl pkey -in key -noout -passin pass:dummy` (non-zero exit means encrypted).

- **No blank lines between PEM leaf and CA**  
  The app trims trailing/leading newlines before concatenation; if you still see gaps, verify your CA bundle doesn’t start with blank lines.

- **DPI / resizing**  
  The bottom button row self-centers and auto-sizes; the OpenSSL status sits above it to avoid overlap.

---

## Security Notes

- The P12 password is displayed in plaintext (operator-friendly). If this is a concern, switch to masked input.
- Unencrypted private keys are created when **Encrypt the key file** is **unchecked** (default). Ensure destination folders are access-controlled.
- Logs may include filenames and options; they never include the P12 password.

---

## Contributing

PRs welcome. Please:
- Keep UI strings and behavior in sync with feature flags.
- Use `Add-Log` for any new messages (so they tee to file when enabled).
- Test both **OpenSSL on PATH** and **manual selection** cases.
- Validate behavior at 100%, 150%, and 200% scaling.

---

## License

MIT (or your org’s standard license). Add your preferred text in `LICENSE`.

---

## Changelog

- **1.6**  
  - Overwrite-or-timestamp prompt for output folder  
  - No-blank-line CA append to PEM  
  - Tee logging to file (optional)  
  - Stop/Exit handling and status bar  
  - Dark Mode + DPI improvements  
  - Inline-editable folder path with autocomplete
