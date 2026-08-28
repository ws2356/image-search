$Mode = "host"
$RunsRoot = "dt_image_search/mobile/transport/poc/runs"
$RequiredHosts = "windows"

if ($args.Count -gt 0) { $Mode = "$($args[0])".ToLowerInvariant() }
if ($args.Count -gt 1) { $RunsRoot = "$($args[1])" }
if ($args.Count -gt 2) { $RequiredHosts = "$($args[2])" }

if ($Mode -ne "host" -and $Mode -ne "simulate") {
  throw "Usage: poc_aoa_pipeline_windows.ps1 [host|simulate] [runs_root] [required_hosts]"
}

$thisScript = $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path (Split-Path -Parent $thisScript) "..\..")
Set-Location $repoRoot

if ([string]::IsNullOrWhiteSpace($env:PYTHONPATH)) {
  $env:PYTHONPATH = "."
} else {
  $env:PYTHONPATH = "$($env:PYTHONPATH);."
}

python -m dt_image_search.mobile.transport.poc.android_aoa_poc --host-os windows --mode $Mode --output-root $RunsRoot
python -m dt_image_search.mobile.transport.poc.summarize_aoa_runs --runs-root $RunsRoot
python -m dt_image_search.mobile.transport.poc.poc_aoa_gate --runs-root $RunsRoot --required-hosts $RequiredHosts

