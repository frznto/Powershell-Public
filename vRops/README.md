# vROps PowerShell Tools

PowerShell 7 tools for managing VMware Aria Operations (vROps) adapter instances, certificates, and credentials via the Suite API.

**Author:** Matthew Blakeslee-Hisel

---

## Contents

| Path | Description |
|------|-------------|
| `VROps-Custom/` | PowerShell module — adapter, certificate, and credential management functions |
| `Invoke-VROpsAdapterHealthCheck.ps1` | Orchestration script — interactively test adapter connections and accept certificates |

---

## Requirements

- PowerShell 7.0+
- [`VMware.VimAutomation.vROps`](https://developer.broadcom.com/tools/vmware-powercli/latest) module (included in VMware PowerCLI)
- An active vROps connection via `Connect-OMServer`

---

## VROps-Custom Module

### Installation

Copy the `VROps-Custom` folder to a directory in your `$env:PSModulePath`, then import it:

```powershell
Import-Module VROps-Custom
```

### Connecting

```powershell
Connect-OMServer -Server 'vrops.domain.local'
```

### Functions

#### Adapter Instances

| Function | Description |
|----------|-------------|
| `Get-VROpsAdapterInstance` | List adapter instances, optionally filtered by kind or ID |
| `Test-VROpsAdapterConnection` | Test an adapter's connection; optionally auto-accept certificates |
| `Confirm-VROpsAdapterCertificate` | Accept untrusted certificates for an adapter via the testconnection endpoint |
| `Update-VROpsAdapterInstance` | Update adapter instance properties |
| `Start-VROpsAdapterMonitoring` | Start collection on a stopped adapter |
| `Stop-VROpsAdapterMonitoring` | Stop collection on a running adapter |

#### Certificates

| Function | Description |
|----------|-------------|
| `Get-VROpsCertificate` | List trusted certificates in vROps |
| `Remove-VROpsCertificate` | Remove a trusted certificate |

#### Credentials

| Function | Description |
|----------|-------------|
| `Get-VROpsCredentialKind` | List available credential kinds for an adapter type |
| `Get-VROpsCredential` | List credential instances |
| `New-VROpsCredential` | Create a new credential instance |
| `Update-VROpsCredential` | Update an existing credential instance |
| `Remove-VROpsCredential` | Delete a credential instance |
| `Get-VROpsCredentialAdapter` | List adapters associated with a credential |
| `Get-VROpsCredentialResource` | List resources associated with a credential |

### Examples

```powershell
# List all adapter instances
Get-VROpsAdapterInstance

# Test a specific adapter connection
Test-VROpsAdapterConnection -AdapterId 'f3a1b2c3-...'

# Test all VCENTER adapters and auto-accept any untrusted certificates
Get-VROpsAdapterInstance -AdapterKindKey 'VCENTER' | Test-VROpsAdapterConnection -AcceptCertificate

# List all credentials
Get-VROpsCredential

# Create a new vCenter credential
New-VROpsCredential -Name 'My vCenter Cred' -AdapterKindKey 'VMWARE' -CredentialKindKey 'PRINCIPALCREDENTIAL' `
    -Fields @{ USER = 'svc-account@domain.local'; PASSWORD = 'YourPasswordHere' }

# Remove a credential with force (no confirmation prompt)
Remove-VROpsCredential -CredentialId 'f3a1b2c3-...' -Force
```

---

## Invoke-VROpsAdapterHealthCheck.ps1

Interactive script that scans adapter instances, tests their connections, and handles untrusted certificate acceptance.

### Features

- Prompts for vROps hostname and credentials if no active session exists (with ping reachability check)
- Numbered menu to select which adapter kinds (integrations) to test
- Interactive per-adapter certificate acceptance with Y / N / Accept All options
- Optional CSV logging of results
- Non-interactive mode via parameters for use in automation

### Usage

```powershell
# Interactive — prompts for connection, adapter selection, and logging
.\Invoke-VROpsAdapterHealthCheck.ps1

# Non-interactive — test specific adapter kinds, auto-accept certs, log results
.\Invoke-VROpsAdapterHealthCheck.ps1 -Adapters 'VMWARE','NSXTAdapter' -AcceptCerts -LogPath C:\Logs\adapter-check.csv

# Include adapters that are stopped or disabled
.\Invoke-VROpsAdapterHealthCheck.ps1 -IncludeStopped
```

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `-Adapters` | `string[]` | Adapter kind keys to test. Omit for interactive menu. |
| `-AcceptCerts` | switch | Auto-accept all untrusted certificates without prompting. |
| `-LogPath` | string | CSV file path for results. Prompts if not supplied. |
| `-IncludeStopped` | switch | Include adapters in a stopped or disabled collection state. |

---

## Notes

- All functions require an active `Connect-OMServer` session.
- `Set-StrictMode -Version Latest` is enforced throughout — all code is strict-mode safe.
- Certificate acceptance uses `POST` then `PATCH` to `/suite-api/api/adapters/testconnection` per the documented vROps API pattern.
