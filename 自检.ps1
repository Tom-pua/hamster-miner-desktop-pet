param()
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$smokeDir = Join-Path $env:TEMP ('DeepDeskSmoke-' + [guid]::NewGuid().ToString('N'))
$env:DEEPDESK_SAVE_DIR = $smokeDir
try {
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectDir 'tests\test_migrations.ps1')
    if ($LASTEXITCODE -ne 0) { throw "旧存档迁移自检失败，退出码：$LASTEXITCODE" }
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $projectDir 'DeepDesk.ps1') -SmokeTest
    if ($LASTEXITCODE -ne 0) { throw "桌宠进程自检失败，退出码：$LASTEXITCODE" }
    if (-not (Test-Path -LiteralPath (Join-Path $smokeDir 'save-wpf.json'))) { throw '存档写入检查失败' }
    Write-Host '桌宠矿工界面、游戏逻辑与存档自检通过。' -ForegroundColor Green
} finally {
    $resolvedSmoke = [System.IO.Path]::GetFullPath($smokeDir)
    $resolvedTemp = [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
    if ($resolvedSmoke.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolvedSmoke -Leaf).StartsWith('DeepDeskSmoke-') -and (Test-Path -LiteralPath $resolvedSmoke)) {
        Remove-Item -LiteralPath $resolvedSmoke -Recurse -Force
    }
}
