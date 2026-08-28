$Mode = "host"
if ($args.Count -gt 0) {
  $Mode = "$($args[0])".ToLowerInvariant()
}
if ($Mode -ne "host" -and $Mode -ne "simulate") {
  throw "Usage: poc_aoa_windows.ps1 [host|simulate]"
}

$thisScript = $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path (Split-Path -Parent $thisScript) "..\..")
Set-Location $repoRoot

if ([string]::IsNullOrWhiteSpace($env:PYTHONPATH)) {
  $env:PYTHONPATH = "."
} else {
  $env:PYTHONPATH = "$($env:PYTHONPATH);."
}

python -m dt_image_search.mobile.transport.poc.android_aoa_poc --host-os windows --mode $Mode --output-root dt_image_search/mobile/transport/poc/runs
