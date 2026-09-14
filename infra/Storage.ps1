function ConvertTo-GameHashtable($Value) {
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $result = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) { $result[$property.Name] = ConvertTo-GameHashtable $property.Value }
        return $result
    }
    if ($Value -is [System.Collections.IList] -and $Value -isnot [string]) { return @($Value | ForEach-Object { ConvertTo-GameHashtable $_ }) }
    return $Value
}

function Merge-GameDefaults($Loaded,$Defaults) {
    if ($Loaded -isnot [System.Collections.IDictionary]) { return $Defaults }
    foreach ($key in $Defaults.Keys) {
        if (-not $Loaded.Contains($key)) {
            $Loaded[$key] = $Defaults[$key]
        } elseif ($Loaded[$key] -is [System.Collections.IDictionary] -and $Defaults[$key] -is [System.Collections.IDictionary]) {
            [void](Merge-GameDefaults $Loaded[$key] $Defaults[$key])
        }
    }
    return $Loaded
}

function Read-GameStateFile([string]$Path,$Defaults) {
    if (-not (Test-Path -LiteralPath $Path)) { return $Defaults }
    try {
        $loaded = ConvertTo-GameHashtable (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
        return Merge-GameDefaults $loaded $Defaults
    } catch {
        return $Defaults
    }
}

function Invoke-GameStateMigrations($State,[object[]]$SkillNodes,[int]$SaveVersion,[int]$SkillMilestoneInterval=70) {
    $originalVersion = if ($State.Contains('Version')) { [int]$State.Version } else { 1 }
    if ($null -eq $State.Inventory -or ($State.Inventory -is [System.Collections.IDictionary] -and $State.Inventory.Count -eq 0)) {
        $State.Inventory = @()
    } elseif ($State.Inventory -isnot [System.Collections.IList]) {
        $State.Inventory = @($State.Inventory)
    }
    if ($null -eq $State.UnlockedSets -or ($State.UnlockedSets -is [System.Collections.IDictionary] -and $State.UnlockedSets.Count -eq 0)) {
        $State.UnlockedSets = @()
    } elseif ($State.UnlockedSets -isnot [System.Collections.IList]) {
        $State.UnlockedSets = @($State.UnlockedSets)
    }
    $old = $State.Skills
    $migrated = [ordered]@{}
    foreach ($node in $SkillNodes) { $migrated[$node.Id] = 0 }
    if ($old -is [System.Collections.IDictionary]) {
        foreach ($node in $SkillNodes) {
            if ($old.Contains($node.Id)) { $migrated[$node.Id] = [int]$old[$node.Id] }
        }
        if ($old.Contains('keyboard')) { $migrated.trained_tap = [int]$old.keyboard }
        if ($old.Contains('idle')) { $migrated.steady_drill = [int]$old.idle }
        if ($old.Contains('mouse')) { $migrated.precision = [int]$old.mouse }
    }
    $State.Skills = $migrated
    if ($originalVersion -lt 6) {
        $highestDepth = if ($State.Contains('MaxDepth')) { [int]$State.MaxDepth } else { 1 }
        $State.HighestSkillMilestone = [int]([math]::Floor($highestDepth / [double]$SkillMilestoneInterval) * $SkillMilestoneInterval)
    } elseif (-not $State.Contains('HighestSkillMilestone')) {
        $State.HighestSkillMilestone = 0
    }
    if (-not $State.Contains('RunEquipmentCount')) { $State.RunEquipmentCount = 0 }
    if (-not $State.Contains('StartupEnabled')) { $State.StartupEnabled = $true }
    $State.Version = $SaveVersion
    $State.DataRevision = 1
    return $State
}

function Write-GameStateFile($State,[string]$Path) {
    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $temp = "$Path.$PID.tmp"
    $backup = Join-Path $directory 'save-wpf.backup.json'
    $json = $State | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($temp,$json,[System.Text.UTF8Encoding]::new($false))
    $attempt = 0
    while ($true) {
      try {
        if (Test-Path -LiteralPath $Path) {
          try {
            [System.IO.File]::Replace($temp,$Path,$backup)
          } catch [System.PlatformNotSupportedException] {
            [System.IO.File]::Copy($Path,$backup,$true)
            [System.IO.File]::Copy($temp,$Path,$true)
            [System.IO.File]::Delete($temp)
          }
        } else {
          [System.IO.File]::Move($temp,$Path)
        }
        break
      } catch [System.IO.IOException], [System.UnauthorizedAccessException] {
        $attempt++
        if ($attempt -ge 3) { throw }
        Start-Sleep -Milliseconds (40*$attempt)
      }
    }
}
