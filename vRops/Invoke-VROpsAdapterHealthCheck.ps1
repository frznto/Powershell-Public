#Requires -Version 7.0
#Requires -Module VROps-Custom

<#
.SYNOPSIS
    Tests all adapter connections in vROps and reports results.
.DESCRIPTION
    Retrieves adapter instances, optionally filtered by adapter kind, tests each
    connection, and handles untrusted certificates either interactively or automatically.
.PARAMETER Adapters
    One or more adapter kind keys to test (e.g. -Adapters VMWARE,NSXTAdapter,HCX).
    Omit to test all adapters.
.PARAMETER AcceptCerts
    Auto-accept all untrusted certificates without prompting. When set, untrusted
    certs are accepted and the connection is re-tested in a single call.
.PARAMETER LogPath
    Optional CSV file path to write results.
.PARAMETER IncludeStopped
    Include adapters in a stopped/not-collecting state. Default: skip them.
.EXAMPLE
    .\Invoke-VROpsAdapterHealthCheck.ps1
.EXAMPLE
    .\Invoke-VROpsAdapterHealthCheck.ps1 -Adapters 'VMWARE,NSXTAdapter' -AcceptCerts -LogPath C:\Logs\adapter-check.csv
.EXAMPLE
    .\Invoke-VROpsAdapterHealthCheck.ps1 -Adapters 'VMWARE' -IncludeStopped -WhatIf
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$Adapters = @(),

    [Parameter(Mandatory = $false)]
    [switch]$AcceptCerts,

    [Parameter(Mandatory = $false)]
    [string]$LogPath,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeStopped
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Verify / establish connection ─────────────────────────────────────────────
$omServers = (Get-Variable -Name 'DefaultOMServers' -Scope Global -ErrorAction SilentlyContinue)?.Value
if (-not $omServers -or @($omServers).Count -eq 0) {
    do {
        $serverHost = (Read-Host 'No vROps connection found. Enter vROps hostname').Trim()
        if (-not $serverHost) { continue }

        Write-Host "  Checking connectivity to '$serverHost'..." -NoNewline
        $pingOk = Test-Connection -ComputerName $serverHost -Count 1 -Quiet -ErrorAction SilentlyContinue
        if (-not $pingOk) {
            Write-Host ' Unreachable' -ForegroundColor Red
            Write-Host "  Cannot reach '$serverHost'. Please try a different hostname."
            $serverHost = $null
        } else {
            Write-Host ' OK' -ForegroundColor Green
        }
    } while (-not $serverHost)

    $connected = $false
    do {
        $cred = Get-Credential -Message "Enter credentials for '$serverHost'"
        if (-not $cred) {
            Write-Host '  No credentials provided. Exiting.' -ForegroundColor Red
            exit 1
        }

        try {
            Connect-OMServer -Server $serverHost -Credential $cred
            $connected = $true
        } catch {
            Write-Host '  Authentication failed. Please check your username and password.' -ForegroundColor Red
        }
    } while (-not $connected)
}
Write-Verbose "Connected to: $($global:DefaultOMServers[0].Name)"

# ── Banner ─────────────────────────────────────────────────────────────────────
$bannerLine = '═' * 54
Write-Host ''
Write-Host "  ╔$bannerLine╗" -ForegroundColor Cyan
Write-Host "  ║   vROps Integration Certificate Connection Testing   ║" -ForegroundColor Cyan
Write-Host "  ╚$bannerLine╝" -ForegroundColor Cyan
Write-Host ''

# ── Log path prompt (if not supplied via parameter) ───────────────────────────
if (-not $LogPath) {
    $logChoice = (Read-Host 'Log results to CSV? [Y] Yes  [N] No  (default: Y)').Trim()
    if ($logChoice -ine 'N') {
        $defaultLog = Join-Path $PSScriptRoot ("VROps-AdapterHealthCheck-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $customPath = (Read-Host "Log path (Enter for default: $defaultLog)").Trim()
        $LogPath    = $customPath ? $customPath : $defaultLog
        Write-Host "Logging to: $LogPath"
        Write-Host ''
    }
}

# ── Retrieve adapters ──────────────────────────────────────────────────────────
Write-Host 'Retrieving adapter instances...'
$allAdapters = Get-VROpsAdapterInstance

# collectionState: 'COLLECTING', 'NOT_COLLECTING', 'UNKNOWN', 'DISABLED'
$testableAdapters = $IncludeStopped ? $allAdapters : @($allAdapters | Where-Object {
    $_.PSObject.Properties['collectionState']?.Value -notin 'NOT_COLLECTING', 'DISABLED'
})

# ── Select adapter kinds ───────────────────────────────────────────────────────
if ($Adapters.Count -gt 0) {
    # Non-interactive: filter by provided kinds
    $adapterList = @($testableAdapters | Where-Object { $_.resourceKey.adapterKindKey -in $Adapters })
    Write-Verbose "Adapter kind filter: $($Adapters -join ', ')"
} else {
    # Interactive: show numbered menu grouped by kind
    $kindGroups = @($testableAdapters |
        Group-Object { $_.resourceKey.adapterKindKey } |
        Sort-Object Name)

    Write-Host ''
    Write-Host 'Available adapter kinds (Integrations):'
    for ($i = 0; $i -lt $kindGroups.Count; $i++) {
        Write-Host ('  [{0,2}]  {1}  ({2} adapter(s))' -f ($i + 1), $kindGroups[$i].Name, $kindGroups[$i].Count)
    }
    Write-Host ''
    Write-Host '   [A]  All'
    Write-Host '   [Q]  Quit'
    Write-Host ''

    do {
        $selection = (Read-Host 'Enter numbers (e.g. 1,2,4), A for all, or Q to quit').Trim()
    } while (-not $selection)

    if ($selection -ieq 'Q') {
        Write-Host 'Exiting.'
        exit 0
    }

    if ($selection -ieq 'A') {
        $adapterList = $testableAdapters
    } else {
        $selectedIndices = $selection -split ',' | ForEach-Object { [int]$_.Trim() - 1 }
        $selectedKinds   = @($selectedIndices | ForEach-Object { $kindGroups[$_].Name })
        $adapterList     = @($testableAdapters | Where-Object { $_.resourceKey.adapterKindKey -in $selectedKinds })
    }
}

$total = @($adapterList).Count
Write-Host ''
Write-Host "$total adapter(s) to test."
Write-Host ''

# ── Test loop ──────────────────────────────────────────────────────────────────
$results  = [System.Collections.Generic.List[PSCustomObject]]::new()
$acceptAll = $AcceptCerts.IsPresent

foreach ($adapter in $adapterList) {
    $adapterName = $adapter.resourceKey.name
    $adapterKind = $adapter.resourceKey.adapterKindKey
    $adapterId   = $adapter.id
    $certAction  = 'N/A'
    $errorMsg    = $null
    $status      = 'Unknown'

    Write-Host ''
    Write-Host '  ─────────────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-Host "  Now testing: $adapterName" -ForegroundColor White
    Write-Host '  ─────────────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-Host "  [$adapterKind] $adapterName" -NoNewline

    try {
        # If auto-accepting, pass -AcceptCertificate so the function handles
        # cert acceptance and re-test in a single call.
        $testParams = @{ AdapterId = $adapterId }
        if ($acceptAll) { $testParams['AcceptCertificate'] = $true }

        $testResult = Test-VROpsAdapterConnection @testParams

        if ($testResult.Success) {
            $status = 'Pass'
            Write-Host ' — Pass' -ForegroundColor Green
        } else {
            $status   = 'Fail'
            $errorMsg = $testResult.PSObject.Properties['errorMessage']?.Value ?? 'No detail returned'
            Write-Host ' — Fail' -ForegroundColor Red
            Write-Host "      $errorMsg"
        }

        # ── Cert handling (interactive path only) ──────────────────────────────
        $certs = $testResult.PSObject.Properties['adapter-certificates']?.Value
        if ($certs -and -not $acceptAll) {
            $certCount = @($certs).Count
            Write-Host "      $certCount untrusted certificate(s) detected." -ForegroundColor Yellow

            $choice = $Host.UI.PromptForChoice(
                'Untrusted Certificate',
                "  Adapter : $adapterName`n  $certCount certificate(s) require acceptance. Accept all?",
                [System.Management.Automation.Host.ChoiceDescription[]](
                    [System.Management.Automation.Host.ChoiceDescription]::new('&Yes',        'Accept all certificates for this adapter'),
                    [System.Management.Automation.Host.ChoiceDescription]::new('&No',         'Skip — do not accept'),
                    [System.Management.Automation.Host.ChoiceDescription]::new('Accept &All', 'Accept all certificates for this and all remaining adapters')
                ),
                1  # default: No
            )

            if ($choice -in 0, 2) {
                if ($choice -eq 2) { $acceptAll = $true }

                # Accept certs via testConnection — passing all thumbprints in one POST
                Write-Host "      Accepting $certCount certificate(s) and re-testing..." -NoNewline
                $retest = Test-VROpsAdapterConnection -AdapterId $adapterId -AcceptCertificate -WarningAction SilentlyContinue
                if ($retest.Success) {
                    $status     = 'Pass'
                    $certAction = "Accepted ($certCount)"
                    Write-Host ' Pass' -ForegroundColor Green
                } else {
                    $status     = 'Fail'
                    $certAction = 'Accept failed'
                    $errorMsg   = $retest.PSObject.Properties['errorMessage']?.Value ?? 'No detail returned'
                    Write-Host ' Fail' -ForegroundColor Red
                    Write-Host "      $errorMsg"
                }
            } else {
                $certAction = 'Skipped'
                Write-Host "      Certificate(s) skipped." -ForegroundColor Gray
            }
        } elseif ($certs -and $acceptAll) {
            # -AcceptCertificate was passed to Test-VROpsAdapterConnection above,
            # so cert was already accepted and re-tested in that call.
            $certAction = 'Accepted'
        }

    } catch {
        $status   = 'Error'
        $errorMsg = $_.Exception.Message
        Write-Host ' — Error' -ForegroundColor Red
        Write-Host "      $errorMsg"
    }

    $results.Add([PSCustomObject]@{
        AdapterName = $adapterName
        AdapterKind = $adapterKind
        AdapterId   = $adapterId
        TestResult  = $status
        CertAction  = $certAction
        Error       = $errorMsg
    })
}

# ── Summary ────────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '─── Summary ────────────────────────────────────────────────────────'
$results | Format-Table AdapterName, AdapterKind, TestResult, CertAction -AutoSize

$failCount = @($results | Where-Object { $_.TestResult -in 'Fail', 'Error' }).Count

if ($failCount -gt 0) {
    Write-Host "$failCount adapter(s) failed." -ForegroundColor Red
} else {
    Write-Host "All adapters passed." -ForegroundColor Green
}

# ── Log output ─────────────────────────────────────────────────────────────────
if ($LogPath) {
    $results | Export-Csv -Path $LogPath -NoTypeInformation -Force
    Write-Host "Results written to: $LogPath"
}

# ── Exit code for automation ───────────────────────────────────────────────────
if ($failCount -gt 0) { exit 1 }
