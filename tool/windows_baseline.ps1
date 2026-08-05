[CmdletBinding()]
param(
    [string]$ReleaseDirectory = "build/windows/x64/runner/Release",
    [string]$ExecutablePath = "",
    [ValidateRange(1, 120)]
    [int]$WarmupSeconds = 10,
    [switch]$SkipLaunch,
    [string]$OutputPath = "build/windows-baseline.json"
)

$ErrorActionPreference = "Stop"

$releasePath = Resolve-Path $ReleaseDirectory -ErrorAction Stop
$files = Get-ChildItem $releasePath -Recurse -File
$totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
if ($null -eq $totalBytes) {
    $totalBytes = 0
}

$baseline = [ordered]@{
    capturedAtUtc = [DateTime]::UtcNow.ToString("o")
    releaseDirectory = $releasePath.Path
    releaseBytes = [int64]$totalBytes
    releaseMiB = [Math]::Round($totalBytes / 1MB, 2)
    fileCount = $files.Count
    launchMeasured = $false
    windowReadyMilliseconds = $null
    workingSetMiB = $null
    privateMemoryMiB = $null
    cpuSeconds = $null
}

if (-not $SkipLaunch) {
    if ([string]::IsNullOrWhiteSpace($ExecutablePath)) {
        $candidate = Get-ChildItem $releasePath -Filter "pure_live.exe" -File | Select-Object -First 1
        if ($null -eq $candidate) {
            throw "pure_live.exe was not found in $($releasePath.Path)"
        }
        $ExecutablePath = $candidate.FullName
    }

    $resolvedExecutable = Resolve-Path $ExecutablePath -ErrorAction Stop
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process -FilePath $resolvedExecutable.Path -PassThru

    try {
        $deadline = [DateTime]::UtcNow.AddSeconds(30)
        while (-not $process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 200
            $process.Refresh()

            if ($process.MainWindowHandle -ne 0 -and $process.Responding) {
                break
            }
        }

        $stopwatch.Stop()
        Start-Sleep -Seconds $WarmupSeconds
        $process.Refresh()

        if ($process.HasExited) {
            throw "PureLive exited before baseline metrics were captured."
        }

        $baseline.launchMeasured = $true
        $baseline.windowReadyMilliseconds = $stopwatch.ElapsedMilliseconds
        $baseline.workingSetMiB = [Math]::Round($process.WorkingSet64 / 1MB, 2)
        $baseline.privateMemoryMiB = [Math]::Round($process.PrivateMemorySize64 / 1MB, 2)
        $baseline.cpuSeconds = [Math]::Round($process.TotalProcessorTime.TotalSeconds, 2)
    }
    finally {
        if ($null -ne $process -and -not $process.HasExited) {
            Stop-Process -Id $process.Id -Force
        }
    }
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$json = $baseline | ConvertTo-Json -Depth 4
Set-Content -Path $OutputPath -Value $json -Encoding utf8
Write-Output $json
