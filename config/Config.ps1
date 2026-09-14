function Import-DeepDeskConfig([string]$ProjectDir) {
    $contentPath = Join-Path $ProjectDir 'config\content.json'
    $balancePath = Join-Path $ProjectDir 'config\balance.json'
    if (-not (Test-Path -LiteralPath $contentPath)) { throw "Missing content config: $contentPath" }
    if (-not (Test-Path -LiteralPath $balancePath)) { throw "Missing balance config: $balancePath" }
    $content = Get-Content -LiteralPath $contentPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $balance = Get-Content -LiteralPath $balancePath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-UniqueConfigKeys @($content.rarities) 'key' 'rarity'
    Assert-UniqueConfigKeys @($content.slots) 'key' 'slot'
    Assert-UniqueConfigKeys @($content.pets) 'name' 'pet'
    Assert-UniqueConfigKeys @($content.skills) 'id' 'skill'
    Assert-UniqueConfigKeys @($content.setEffects) 'name' 'set effect'
    if ([int]$balance.saveVersion -lt 1) { throw 'saveVersion must be positive' }
    if ([int]$balance.skillPointEveryLayers -lt 1) { throw 'skillPointEveryLayers must be positive' }
    if ([int]$balance.oreAmountEveryLayers -lt 1) { throw 'oreAmountEveryLayers must be positive' }
    foreach ($weightProperty in @('oreWeight','chestWeight','eggWeight')) {
        $sum = 0.0
        foreach ($rarity in $content.rarities) { $sum += [double]$rarity.$weightProperty }
        if ([math]::Abs($sum-1.0) -gt 0.000001) { throw "$weightProperty must add up to 1.0 (actual: $sum)" }
    }
    $rarityKeys = @($content.rarities | ForEach-Object { [string]$_.key })
    foreach ($pet in $content.pets) {
        if ($rarityKeys -notcontains [string]$pet.rarity) { throw "Pet '$($pet.name)' uses unknown rarity '$($pet.rarity)'" }
    }
    foreach ($treeName in @('keyboard','idle','mouse')) {
        $tiers = @($content.skills | Where-Object tree -eq $treeName | ForEach-Object { [int]$_.tier } | Sort-Object)
        if (($tiers -join ',') -ne '1,2,3,4,5') { throw "Skill tree '$treeName' must contain tiers 1 through 5" }
    }
    return [ordered]@{ Content=$content; Balance=$balance }
}

function Assert-UniqueConfigKeys([object[]]$Items,[string]$Property,[string]$Label) {
    $seen = @{}
    foreach ($item in $Items) {
        $key = [string]$item.$Property
        if ([string]::IsNullOrWhiteSpace($key)) { throw "$Label has an empty $Property" }
        if ($seen.ContainsKey($key)) { throw "Duplicate $Label key: $key" }
        $seen[$key] = $true
    }
}

function Get-ConfigRecord([object[]]$Items,[string]$Property,[string]$Value) {
    return $Items | Where-Object { [string]$_.$Property -eq $Value } | Select-Object -First 1
}
