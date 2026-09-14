function Get-NormalHpValue([int]$Depth,$Balance) {
    return [double]$Balance.hpBase * [math]::Pow([double]$Balance.hpGrowth,[math]::Max(0,$Depth-1)) * [math]::Pow([double]$Balance.hpMilestone,[math]::Floor(($Depth-1)/100))
}

function Get-ScaledEffectValue([double]$Base,[int]$Level,[double]$EquipmentBonus,[double]$SetBonus,$Balance) {
    return $Base * [math]::Pow([double]$Balance.petLevelGrowth,[math]::Max(0,$Level-1)) * (1+$EquipmentBonus+$SetBonus)
}

function Get-BaseDamageValue([double]$PickaxeValue,$Balance) {
    return 1 + [double]$Balance.pickaxeCoefficient * $PickaxeValue
}

function Get-EggPriceValue([int]$EggsBought,$Balance) {
    return [math]::Ceiling([double]$Balance.eggBasePrice * [math]::Pow([double]$Balance.eggPriceGrowth,$EggsBought))
}

function Get-ReturnRatioValue([double]$ShoesValue,$Balance) {
    return [math]::Min([double]$Balance.returnRatioCap,[double]$Balance.returnBaseRatio+$ShoesValue)
}

function Get-AutoIntervalValue([int]$Level,[double]$PerLevel,[double]$PetSpeed,$Balance) {
    return [math]::Max([double]$Balance.autoIntervalMinimum,([double]$Balance.autoBaseInterval*[math]::Pow(1-$PerLevel,$Level))/(1+$PetSpeed))
}

function Get-KeyboardDamageValue([double]$Base,[double]$AllMultiplier,[int]$TapLevel,[double]$TapValue,[int]$HeatLevel,[double]$HeatValue,[int]$Combo,[int]$FastLevel,[double]$FastValue,[int]$FastTrigger,[int]$SymphonyLevel,[double]$SymphonyValue,[int]$SymphonyTrigger,[double]$PetBonus,[double]$SetBonus) {
    $fast = if($Combo-ge$FastTrigger){1+$FastValue*$FastLevel}else{1.0}
    $symphony = if($Combo-ge$SymphonyTrigger){1+$SymphonyValue*$SymphonyLevel}else{1.0}
    return $Base*$AllMultiplier*(1+$TapValue*$TapLevel)*(1+$HeatValue*$HeatLevel*$Combo)*$fast*$symphony*(1+$PetBonus)*(1+$SetBonus)
}

function Get-MouseDamageValue([double]$Base,[double]$AllMultiplier,[int]$Level,[double]$PerLevel,[double]$SetBonus) {
    return $Base*$AllMultiplier*(1+$PerLevel*$Level)*(1+$SetBonus)
}

function Get-AutoDamageValue([double]$Base,[double]$AllMultiplier,[int]$DrillLevel,[double]$DrillValue,[int]$ChargeLevel,[double]$ChargeValue,[int]$ChargeStacks,[int]$CoreLevel,[double]$CoreValue,[double]$PetBonus,[double]$SetBonus) {
    return $Base*$AllMultiplier*(1+$DrillValue*$DrillLevel)*(1+$ChargeValue*$ChargeStacks*$ChargeLevel)*(1+$CoreValue*$CoreLevel)*(1+$PetBonus)*(1+$SetBonus)
}

function Select-BestItemForSlot($Current,[object[]]$Inventory,[string]$Slot) {
    $best=$Current
    foreach($candidate in @($Inventory|Where-Object Slot -eq $Slot)){if([double]$candidate.Value-gt[double]$best.Value){$best=$candidate}}
    return $best
}
