#Requires -Version 7.0
#Requires -Module VMware.VimAutomation.vROps

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Get-ChildItem -Path "$PSScriptRoot\Functions\Private\*.ps1" -ErrorAction Stop |
    ForEach-Object { . $_.FullName }

Get-ChildItem -Path "$PSScriptRoot\Functions\Public\*.ps1" -ErrorAction Stop |
    ForEach-Object { . $_.FullName }
