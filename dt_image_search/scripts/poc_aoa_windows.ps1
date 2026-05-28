$thisScript = $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path (Split-Path -Parent $thisScript) "..\..")
Set-Location $repoRoot

if ([string]::IsNullOrWhiteSpace($env:PYTHONPATH)) {
  $env:PYTHONPATH = "."
} else {
  $env:PYTHONPATH = "$($env:PYTHONPATH);."
}

python -m dt_image_search.mobile.transport.poc.android_aoa_poc --host-os windows --simulate --output-root dt_image_search/mobile/transport/poc/runs

