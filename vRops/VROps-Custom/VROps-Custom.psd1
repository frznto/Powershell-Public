@{
    ModuleVersion     = '1.1.0'
    GUID              = 'b7e4f1a2-3c8d-4e9f-a051-6d7b8c9e0f12'
    Author            = 'Matthew Blakeslee-Hisel'
    Description       = 'Custom PowerShell module for vROps adapter instance and credential management via the Suite API. Requires an active Connect-OMServer session
from VMware.VimAutomation.vROps.'
    PowerShellVersion = '7.0'

    RequiredModules   = @(
        @{ ModuleName = 'VMware.VimAutomation.vROps'; ModuleVersion = '1.0.0' }
    )

    RootModule        = 'VROps-Custom.psm1'

    FunctionsToExport = @(
        # Adapter functions
        'Get-VROpsAdapterInstance'
        'Test-VROpsAdapterConnection'
        'Confirm-VROpsAdapterCertificate'
        'Update-VROpsAdapterInstance'
        'Start-VROpsAdapterMonitoring'
        'Stop-VROpsAdapterMonitoring'
        # Certificate functions
        'Get-VROpsCertificate'
        'Remove-VROpsCertificate'
        # Credential functions
        'Get-VROpsCredentialKind'
        'Get-VROpsCredential'
        'New-VROpsCredential'
        'Update-VROpsCredential'
        'Remove-VROpsCredential'
        'Get-VROpsCredentialAdapter'
        'Get-VROpsCredentialResource'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags = @('VMware', 'vROps', 'vRealize', 'Aria', 'Adapters', 'Credentials', 'REST')
        }
    }
}