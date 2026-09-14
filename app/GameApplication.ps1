function Get-ApplicationSkillNode([object[]]$SkillNodes,[string]$Id) {
    return $SkillNodes | Where-Object Id -eq $Id | Select-Object -First 1
}

function Test-ApplicationSkillUnlocked($State,[object[]]$SkillNodes,$Balance,[string]$Id) {
    $node = Get-ApplicationSkillNode $SkillNodes $Id
    if (-not $node) { return $false }
    if ([int]$node.Tier -le 1) { return $true }
    $previous = $SkillNodes | Where-Object { $_.Tree -eq $node.Tree -and [int]$_.Tier -eq ([int]$node.Tier-1) } | Select-Object -First 1
    return ($previous -and [int]$State.Skills[$previous.Id] -ge [int]$Balance.skillUnlockPreviousLevel)
}

function Invoke-SkillPurchase($State,[object[]]$SkillNodes,$Balance,[string]$Id) {
    $node = Get-ApplicationSkillNode $SkillNodes $Id
    if (-not $node -or -not (Test-ApplicationSkillUnlocked $State $SkillNodes $Balance $Id)) { return $false }
    if ([int]$State.SkillPoints -le 0 -or [int]$State.Skills[$Id] -ge [int]$node.Max) { return $false }
    $State.SkillPoints = [int]$State.SkillPoints - 1
    $State.Skills[$Id] = [int]$State.Skills[$Id] + 1
    return $true
}

function Invoke-SkillReset($State,[object[]]$SkillNodes) {
    $refund = 0
    foreach ($node in $SkillNodes) {
        $refund += [int]$State.Skills[$node.Id]
        $State.Skills[$node.Id] = 0
    }
    $State.SkillPoints = [int]$State.SkillPoints + $refund
    return $refund
}

function Invoke-BestEquipmentSelection($State,[object[]]$Slots) {
    $changed = @()
    foreach ($slotDefinition in $Slots) {
        $slot = [string]$slotDefinition.key
        $current = $State.Equipment[$slot]
        $best = Select-BestItemForSlot $current @($State.Inventory) $slot
        if ([double]$best.Value -gt [double]$current.Value) {
            $State.Equipment[$slot] = $best
            $changed += "$($best.Set)-$($best.Name)"
        }
    }
    return @($changed)
}
