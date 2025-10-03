# Set strict mode and error action
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$cn = "Wansong Dev Cert"
# Modify dt_image_search/resources/AppxManifest.xml file 'Package/Identity/Publisher' attribute to be "CN=$cn"
$currentScriptPath = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$appxManifestPath = Join-Path -Path $currentScriptPath -ChildPath "..\resources\AppxManifest.xml"
[xml]$appxManifest = Get-Content -Path "$appxManifestPath"
$appxManifest.Package.Identity.Publisher = "CN=$cn"

# Set up formatting options
$settings = New-Object System.Xml.XmlWriterSettings
$settings.Indent = $true
$settings.IndentChars = "    "  # Four spaces
$settings.NewLineChars = "`r`n"
$settings.NewLineHandling = "Replace"
# Create writer and save
$writer = [System.Xml.XmlWriter]::Create("$appxManifestPath", $settings)
$appxManifest.Save($writer)
$writer.Close()

Remove-Item -Path "mydevcert.cer" -ErrorAction SilentlyContinue
Remove-Item -Path "MyDevCert.pfx" -ErrorAction SilentlyContinue
$cert = Get-ChildItem -Path Cert:\CurrentUser\My | Where-Object { $_.Issuer -eq $_.Subject } | Where-Object { $_.Subject -like "*CN=$cn*" } 
if ($cert) {
    Write-Host "Certificate already exists: $($cert.Subject)"
} else {
    Write-Host "Creating new self-signed certificate..."
    $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=Wansong Dev Cert" -CertStoreLocation "Cert:\CurrentUser\My"
}

Export-Certificate -Cert $cert -FilePath "mydevcert.cer"
$pwd = ConvertTo-SecureString -String "123456" -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath MyDevCert.pfx -Password $pwd
# Export-PfxCertificate -Cert $cert -FilePath MyDevCert.pfx -Password $pwd

Import-Certificate -FilePath "mydevcert.cer" -CertStoreLocation "Cert:\LocalMachine\Root"
