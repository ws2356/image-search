# Set strict mode and error action
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$cn = "Wansong Dev Cert"

$cert = Get-ChildItem -Path Cert:\CurrentUser\My | Where-Object { $_.Issuer -eq $_.Subject } | Where-Object { $_.Subject -like "*CN=$cn*" } 
if ($cert) {
    Write-Host "Certificate already exists: $($cert.Subject)"
} else {
    Write-Host "Creating new self-signed certificate..."
    $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=Wansong Dev Cert" -CertStoreLocation "Cert:\CurrentUser\My"
}

Export-Certificate -Cert $cert -FilePath "mydevcert.cer"

Import-Certificate -FilePath "mydevcert.cer" -CertStoreLocation "Cert:\LocalMachine\Root"

Import-Certificate -FilePath "mydevcert.cer" -CertStoreLocation "Cert:\LocalMachine\TrustedPublisher"
