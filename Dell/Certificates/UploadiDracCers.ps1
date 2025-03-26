<#
.SYNOPSIS
  Upload Certificates for iDracs from a csv list
.DESCRIPTION
  Upload Certificates for iDracs from a csv list which is saved in the same directory that the csv list is located in.
  Tested on iDrac version 9, but should work on version 8 as well.
.PARAMETER <Parameter_Name>
    <Brief description of parameter input required. Repeat this attribute if required>
.INPUTS
  <Inputs if any, otherwise state None>
.OUTPUTS
  <Outputs if any, otherwise state None - example: Log file stored in C:\Windows\Temp\<name>.log>
.NOTES
  Version:        1.0
  Author:         Matthew Blakeslee-Hisel
  Creation Date:  3/25/2025
  Purpose/Change: 
  


  CSV Header Structure: fqdn,ip


.EXAMPLE
  
#>

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

<#
# Check PowerShell version
if ($PSVersionTable.PSEdition -ne 'Core' -and $PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "This script requires PowerShell Core 7 or later to run."
    return
}

#>

#Required modules: List modules that are required for the script
# Ensure the module is available before running the script
If (-not (Get-Module -ListAvailable -Name IdracRedfishSupport)) {
    Write-Host "Required module 'IdracRedfishSupport' is not installed. Install it before running the script." -ForegroundColor Red
    Exit 1
}

# Check PowerShell version and load System.Windows.Forms accordingly
if ($PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.PSVersion.Major -ge 7) {
    Add-Type -AssemblyName System.Windows.Forms
} else {
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
}


#----------------------------------------------------------[Declarations]----------------------------------------------------------

#Script Version
$sScriptVersion = "1.0"

#Log File Info
$sLogPath = "C:\Windows\Temp"
$sLogName = "<script_name>.log"
$sLogFile = Join-Path -Path $sLogPath -ChildPath $sLogName

#-----------------------------------------------------------[Functions]------------------------------------------------------------

<#
Function <FunctionName>{
  Param()
  
  Begin{
    Log-Write -LogPath $sLogFile -LineValue "<description of what is going on>..."
  }
  
  Process{
    Try{
      <code goes here>
    }
    
    Catch{
      Log-Error -LogPath $sLogFile -ErrorDesc $_.Exception -ExitGracefully $True
      Break
    }
  }
  
  End{
    If($?){
      Log-Write -LogPath $sLogFile -LineValue "Completed Successfully."
      Log-Write -LogPath $sLogFile -LineValue " "
    }
  }
}
#>


#-----------------------------------------------------------[Execution]------------------------------------------------------------

#Log-Start -LogPath $sLogPath -LogName $sLogName -ScriptVersion $sScriptVersion
#Script Execution goes here

Write-Host 
Write-Host "Verify the certificates are in the same directory as the target csv list."
Write-Host "Certificates should be in the .pem format WITHOUT IA or CA information"
Write-Host

# Securely cache credentials
$SessionCache = [PSCustomObject]@{
  Credential = Get-Credential -Message "Enter the iDRAC credentials. If using domain credentials must be in the form of username@domain"
}

# Extract username and password separately
$IdracUsername = $SessionCache.Credential.UserName
$SecurePassword = $SessionCache.Credential.Password

# Set folder location for the CSV 
$Directory = "$ENV:USERPROFILE\Downloads"

# Explorer Window to prompt for CSV file selection
Write-Host "Select CSV list" -ForegroundColor Green -BackgroundColor Black
Start-Sleep -Seconds 2

$File = New-Object System.Windows.Forms.OpenFileDialog -Property @{
  InitialDirectory = "$Directory"
  Filter = "CSV Files (*.csv)|*.csv|All files (*.*)|*.*"
}
$null = $File.ShowDialog()
$FilePath = $File.FileName
$FolderPath = [System.IO.Path]::GetDirectoryName($FilePath)

# Validate file selection
if (-not $FilePath -or -not (Test-Path $FilePath)) {
  Write-Host "No valid file selected. Exiting script." -ForegroundColor Red
  Exit 1
}

$iDracTargets = Import-CSV -Path $FilePath -Delimiter ',' -Encoding UTF8 | Select-Object fqdn,ip

# Initialize summary results array
$SummaryResults = @()

# Start loop to process each entry in the CSV
ForEach ($Target in $iDracTargets) { 

  # Remove variables to prevent previous loops data
  Remove-Variable -Force -ErrorAction Ignore -Name "CommonName", "IPAddress", "PemFilePath"

  $CommonName = $Target.fqdn
  $IPAddress = $Target.ip
  $PemFilePath = Join-Path $FolderPath "$CommonName.pem"

  # Check if PEM file exists
  if (-not (Test-Path -Path $PemFilePath -PathType Leaf)) {
      Write-Host "ERROR: PEM file '$PemFilePath' not found. Skipping $CommonName." -ForegroundColor Red
      $SummaryResults += [PSCustomObject]@{ FQDN = $CommonName; Status = "Failed - PEM file missing" }
      continue
  }  

  # Check if the host is reachable
  if (-not (Test-Connection -ComputerName $CommonName -Count 2 -Quiet)) {
      Write-Host "ERROR: $CommonName could not be reached. No Certificate was uploaded." -ForegroundColor Red
      $SummaryResults += [PSCustomObject]@{ FQDN = $CommonName; Status = "Failed - Host unreachable" }
      continue
  }

  # Verify if the resolved IP matches the expected IP
  try {
      $ResolvedIP = [System.Net.Dns]::GetHostAddresses($CommonName) | Select-Object -ExpandProperty IPAddressToString
      if ($ResolvedIP -notcontains $IPAddress) {
          Write-Host "ERROR: DNS mismatch for $CommonName (Expected: $IPAddress, Resolved: $ResolvedIP). No Certificate was uploaded." -ForegroundColor Red
          $SummaryResults += [PSCustomObject]@{ FQDN = $CommonName; Status = "Failed - DNS mismatch" }
          continue
      }
  } catch {
      Write-Host "ERROR: Unable to resolve $CommonName. No Certificate was uploaded." -ForegroundColor Red
      $SummaryResults += [PSCustomObject]@{ FQDN = $CommonName; Status = "Failed - DNS resolution error" }
      continue
  }

  # Upload PEM File to iDRAC
  $UploadedCert = Invoke-ExportImportSslCertificateREDFISH -idrac_ip $IPAddress -idrac_username $IdracUsername -idrac_password ([System.Net.NetworkCredential]::new("", $SecurePassword).Password) -import_ssl_cert Server -cert_filename $PemFilePath

  # Check for errors
  if ($UploadedCert.ErrorRecord -match "error") {
      Write-Host "ERROR: Upload failed for $CommonName. Check logs for details." -ForegroundColor Red
      $SummaryResults += [PSCustomObject]@{ FQDN = $CommonName; Status = "Failed - Upload error" }
      continue
  }

  # Restart the iDRAC
  Invoke-ResetIdracREDFISH -idrac_ip $IPAddress -idrac_username $IdracUsername -idrac_password ([System.Net.NetworkCredential]::new("", $SecurePassword).Password)

  # If everything succeeded, mark as success
  $SummaryResults += [PSCustomObject]@{ FQDN = $CommonName; Status = "Success - Certificate uploaded" }
}

# Output Summary with color-coded results
Write-Host "`n===== Certificate Upload Summary =====" -ForegroundColor Cyan
foreach ($entry in $SummaryResults) {
  if ($entry.Status -like "Success*") {
      Write-Host ("{0,-30} {1}" -f $entry.FQDN, $entry.Status) -ForegroundColor Black -BackgroundColor Green
  } else {
      Write-Host ("{0,-30} {1}" -f $entry.FQDN, $entry.Status) -ForegroundColor White -BackgroundColor Red
  }
}
Write-Host "========================================" -ForegroundColor Cyan

#Log-Finish -LogPath $sLogFile


