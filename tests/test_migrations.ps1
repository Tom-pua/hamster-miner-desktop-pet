param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $root 'infra\Storage.ps1')

$nodes = (Get-Content -LiteralPath (Join-Path $root 'config\content.json') -Raw -Encoding UTF8 | ConvertFrom-Json).skills
$legacy = [ordered]@{
    Version = 1
    MaxDepth = 541
    Skills = [ordered]@{keyboard=2;idle=3;mouse=4}
    Inventory = [ordered]@{}
    UnlockedSets = [ordered]@{}
}
$migrated = Invoke-GameStateMigrations $legacy $nodes 7 70
if ($migrated.Skills.Count -ne 15) { throw 'Legacy skill table was not expanded to 15 nodes.' }
if ([int]$migrated.Skills.trained_tap -ne 2 -or [int]$migrated.Skills.steady_drill -ne 3 -or [int]$migrated.Skills.precision -ne 4) { throw 'Legacy skill migration failed.' }
if ($migrated.Inventory -isnot [System.Collections.IList] -or $migrated.UnlockedSets -isnot [System.Collections.IList]) { throw 'Legacy collection migration failed.' }
if ([int]$migrated.HighestSkillMilestone -ne 490) { throw 'Skill milestone history migration failed.' }
if ([int]$migrated.RunEquipmentCount -ne 0) { throw 'Run equipment counter migration failed.' }
if (-not [bool]$migrated.StartupEnabled) { throw 'Startup preference migration failed.' }
if ([int]$migrated.Version -ne 7) { throw 'Save version migration failed.' }
Write-Output 'MIGRATION_OK'
