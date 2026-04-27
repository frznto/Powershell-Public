# PowerShell Public

Scripts and modules I've built to solve problems I kept running into. Mostly infrastructure stuff — certificates, Dell hardware, and VMware Aria Operations. Sharing them here in case they're useful to someone else.

**Author:** Matthew Blakeslee-Hisel

---

## Projects

### [vRops](./vRops/)
A PowerShell module and script for working with VMware Aria Operations via the Suite API. The module handles adapter instances, certificates, and credentials. The health check script lets you run through your adapters interactively, test connections, and deal with untrusted certs without having to dig through the UI.

- `VROps-Custom` — module with 15 functions
- `Invoke-VROpsAdapterHealthCheck.ps1` — interactive adapter connection tester

---

### [P12/PFX Certificate Toolkit](./P12_PFX%20Certficate%20Toolkit_GUI/)
A GUI wrapper around OpenSSL for pulling apart P12/PFX certificate files. I built this because not everyone on the team is comfortable with OpenSSL commands and I got tired of walking through it manually.

- Extracts PEM, CER, and KEY files
- Handles CA chains, key encryption, batch processing, and has a dark mode

---

### [Dell — iDRAC Certificates](./Dell/Certificates/)
A pair of scripts for bulk CSR generation and certificate upload to Dell iDRAC interfaces. Handy when you have a lot of servers and don't want to click through each iDRAC one by one.

- `GenerateiDracCSRS.ps1` — bulk CSR generation
- `UploadiDracCers.ps1` — bulk certificate upload

---

## Requirements

PowerShell 7.0+ for most things. Check the individual project READMEs for anything else needed.
