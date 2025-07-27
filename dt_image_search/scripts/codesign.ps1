#Requires -Version 5.1

param()

# Set strict mode and error action
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Get script directory and change to repo root (equivalent to bash path resolution)
$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path -Parent $scriptPath
Set-Location (Join-Path $scriptDir "../..")

Write-Host "Changed to repository root: $(Get-Location)"

. "$scriptDir\utils.ps1"

$codeSignTool = Search-Codesign

# SignTool sign /fd SHA256 /a /f mycert.pfx /p mypassword MyApp.msix

try {
    $process = Start-Process -FilePath $codeSignTool -ArgumentList @(
        "sign",
        "/fd", "SHA256",
        "/a",
        "/f", "MyDevCert.pfx",
        "/p", "123456",
        "DTImageSearch.msix"
    ) -Wait -PassThru -NoNewWindow
    
    if ($process.ExitCode -ne 0) {
        Write-Error "Failed to create MSIX package."
        exit 1
    }
    
    Write-Host "Successfully created MSIX package: DTImageSearch.msix"
} catch {
    Write-Error "Failed to create MSIX package: $($_.Exception.Message)"
    exit 1
}