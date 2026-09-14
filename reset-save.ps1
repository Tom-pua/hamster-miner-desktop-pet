param()
$ErrorActionPreference = 'Stop'

$created = $false
$mutex = [System.Threading.Mutex]::new($true,'Local\DeepDeskMiner.SingleInstance',[ref]$created)
$acquired = $created
try {
    if (-not $created) {
        try { $acquired = $mutex.WaitOne(0) }
        catch [System.Threading.AbandonedMutexException] { $acquired = $true }
    }
    if (-not $acquired) {
        Write-Host 'Deep Desk Miner is still running. Exit it from the system tray, then run this tool again.' -ForegroundColor Yellow
        exit 2
    }

    Write-Host 'This permanently deletes the current Deep Desk Miner save, backup, and error log.' -ForegroundColor Yellow
    $answer = Read-Host 'Type CLEAR to confirm'
    if ($answer -cne 'CLEAR') {
        Write-Host 'Cancelled. No files were changed.'
        exit 1
    }

    $targetDir = [System.IO.Path]::GetFullPath((Join-Path $env:APPDATA 'DeepDeskMiner'))
    $expectedParent = [System.IO.Path]::GetFullPath($env:APPDATA)
    if ((Split-Path -Parent $targetDir) -ne $expectedParent -or (Split-Path -Leaf $targetDir) -ne 'DeepDeskMiner') { throw "Unexpected save directory: $targetDir" }
    foreach ($name in @('save-wpf.json','save-wpf.backup.json','error.log')) {
        $target = [System.IO.Path]::GetFullPath((Join-Path $targetDir $name))
        if (-not $target.StartsWith($targetDir + '\',[System.StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe file path: $target" }
        if (Test-Path -LiteralPath $target) { [System.IO.File]::Delete($target) }
    }

    $remaining = @('save-wpf.json','save-wpf.backup.json','error.log') | Where-Object { Test-Path -LiteralPath (Join-Path $targetDir $_) }
    if ($remaining.Count -gt 0) { throw "Files still present: $($remaining -join ', ')" }
    Write-Host 'Save cleared. The next launch will create a new game at floor 1.' -ForegroundColor Green
} finally {
    if ($acquired) { try { $mutex.ReleaseMutex() } catch {} }
    $mutex.Dispose()
}
