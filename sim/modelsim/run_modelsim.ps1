<#
    sim/modelsim/run_modelsim.ps1 -- ModelSim ASE batch regression driver
    Implements VERIF_PLAN.md section 5.

    Runs run_all.do under vsim -c, then scans the transcript for verdicts and
    prints a result table. Exits non-zero if any run failed OR if the number of
    verdicts does not match the number of runs launched -- a run that died
    without printing a verdict must never be read as a pass.

    Usage:  .\run_modelsim.ps1 [-VsimPath <path to vsim.exe>]
#>

param(
    [string]$VsimPath = "C:\intelFPGA\18.1\modelsim_ase\win32aloem\vsim.exe"
)

$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

if (-not (Test-Path $VsimPath)) {
    Write-Host "vsim not found at $VsimPath"
    Write-Host "Pass the correct location with -VsimPath."
    exit 1
}

$transcriptFile = Join-Path $PSScriptRoot 'transcript'
if (Test-Path $transcriptFile) { Remove-Item $transcriptFile -Force }

Write-Host "Running ModelSim regression (this takes a few minutes)..."
& $VsimPath -c -do run_all.do | Out-File -FilePath 'run_all.out' -Encoding utf8

# Read exactly ONE source. vsim mirrors everything into both `transcript` and
# stdout, so concatenating them double-counts every verdict.
$log = @()
if (Test-Path $transcriptFile)    { $log = Get-Content $transcriptFile }
elseif (Test-Path 'run_all.out')  { $log = Get-Content 'run_all.out' }

# ModelSim's `echo` prefixes output with "# ", so anchors must tolerate it.
$launched = ($log | Select-String -Pattern '^#?\s*=== RUN ').Count
$passed   = ($log | Select-String -Pattern '=== TEST PASSED').Count
$failed   = ($log | Select-String -Pattern '=== TEST FAILED').Count

Write-Host ''
Write-Host ('{0,-34} {1,-11} {2}' -f 'TESTBENCH', 'TEST', 'RESULT')
Write-Host ('-' * 62)

$current = $null
foreach ($line in $log) {
    if ($line -match '=== RUN (\S+) (\S+) seed=(\S+)') {
        $current = @{ tb = $Matches[1]; test = $Matches[2]; seed = $Matches[3] }
    }
    elseif ($line -match '=== TEST (PASSED|FAILED)' -and $current) {
        Write-Host ('{0,-34} {1,-11} {2}' -f $current.tb, $current.test, $Matches[1])
        $current = $null
    }
}

Write-Host ''
if ($failed -eq 0 -and $launched -gt 0 -and $passed -eq $launched) {
    Write-Host "MODELSIM REGRESSION: $passed/$launched PASSED"
    exit 0
}
else {
    Write-Host "MODELSIM REGRESSION: $passed/$launched PASSED ($failed FAILED)"
    if ($passed + $failed -ne $launched) {
        $missing = $launched - $passed - $failed
        Write-Host "$missing run(s) produced no verdict at all -- treated as failures."
    }
    exit 1
}
