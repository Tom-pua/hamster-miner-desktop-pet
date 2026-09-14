param([switch]$SmokeTest)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:InstanceMutex=$null
$script:InstanceMutexOwned=$false
if(-not$SmokeTest){
    $createdNew=$false
    $script:InstanceMutex=[System.Threading.Mutex]::new($true,'Local\DeepDeskMiner.SingleInstance',[ref]$createdNew)
    if(-not$createdNew){
        [void][System.Windows.MessageBox]::Show('桌宠矿工已经在运行。请从系统托盘打开现有窗口；如需更新版本，请先彻底退出旧版。','桌宠矿工 · 已在运行','OK','Information')
        $script:InstanceMutex.Dispose();exit 2
    }
    $script:InstanceMutexOwned=$true
}

$nativeCode = @'
using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace DeepDesk {
    public static class InputHooks {
        private const int WH_KEYBOARD_LL = 13;
        private const int WH_MOUSE_LL = 14;
        private const int WM_KEYDOWN = 0x0100;
        private const int WM_KEYUP = 0x0101;
        private const int WM_SYSKEYDOWN = 0x0104;
        private const int WM_SYSKEYUP = 0x0105;
        private const int WM_LBUTTONDOWN = 0x0201;
        private const int WM_RBUTTONDOWN = 0x0204;
        private const int WM_MBUTTONDOWN = 0x0207;
        private const int LLKHF_INJECTED = 0x10;
        private const int LLMHF_INJECTED = 0x01;
        private delegate IntPtr HookProc(int code, IntPtr wParam, IntPtr lParam);
        private static readonly HookProc KeyboardProc = KeyboardCallback;
        private static readonly HookProc MouseProc = MouseCallback;
        private static IntPtr keyboardHook = IntPtr.Zero;
        private static IntPtr mouseHook = IntPtr.Zero;
        private static readonly HashSet<uint> pressed = new HashSet<uint>();
        public static readonly ConcurrentQueue<string> Hits = new ConcurrentQueue<string>();
        public static bool Enabled { get; set; }
        static InputHooks() { Enabled = true; }

        [StructLayout(LayoutKind.Sequential)]
        private struct KeyboardData { public uint vkCode, scanCode, flags, time; public UIntPtr extra; }
        [StructLayout(LayoutKind.Sequential)]
        private struct Point { public int x, y; }
        [StructLayout(LayoutKind.Sequential)]
        private struct MouseData { public Point pt; public uint mouseData, flags, time; public UIntPtr extra; }

        [DllImport("user32.dll", SetLastError=true)] private static extern IntPtr SetWindowsHookEx(int id, HookProc callback, IntPtr module, uint threadId);
        [DllImport("user32.dll")] private static extern bool UnhookWindowsHookEx(IntPtr hook);
        [DllImport("user32.dll")] private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr wParam, IntPtr lParam);
        [DllImport("kernel32.dll", CharSet=CharSet.Auto)] private static extern IntPtr GetModuleHandle(string name);

        public static void Start() {
            if (keyboardHook != IntPtr.Zero) return;
            IntPtr module = GetModuleHandle(null);
            keyboardHook = SetWindowsHookEx(WH_KEYBOARD_LL, KeyboardProc, module, 0);
            mouseHook = SetWindowsHookEx(WH_MOUSE_LL, MouseProc, module, 0);
        }
        public static void Stop() {
            if (keyboardHook != IntPtr.Zero) UnhookWindowsHookEx(keyboardHook);
            if (mouseHook != IntPtr.Zero) UnhookWindowsHookEx(mouseHook);
            keyboardHook = mouseHook = IntPtr.Zero;
            pressed.Clear();
            string ignored; while (Hits.TryDequeue(out ignored)) { }
        }
        private static IntPtr KeyboardCallback(int code, IntPtr wParam, IntPtr lParam) {
            if (code >= 0) {
                KeyboardData data = Marshal.PtrToStructure<KeyboardData>(lParam);
                int message = wParam.ToInt32();
                if (message == WM_KEYUP || message == WM_SYSKEYUP) pressed.Remove(data.vkCode);
                else if (message == WM_KEYDOWN || message == WM_SYSKEYDOWN) {
                    if (Enabled && !pressed.Contains(data.vkCode) && (data.flags & LLKHF_INJECTED) == 0) {
                        pressed.Add(data.vkCode); Hits.Enqueue("keyboard");
                    }
                }
            }
            return CallNextHookEx(IntPtr.Zero, code, wParam, lParam);
        }
        private static IntPtr MouseCallback(int code, IntPtr wParam, IntPtr lParam) {
            if (code >= 0 && Enabled) {
                int message = wParam.ToInt32();
                if (message == WM_LBUTTONDOWN || message == WM_RBUTTONDOWN || message == WM_MBUTTONDOWN) {
                    MouseData data = Marshal.PtrToStructure<MouseData>(lParam);
                    if ((data.flags & LLMHF_INJECTED) == 0) Hits.Enqueue("mouse");
                }
            }
            return CallNextHookEx(IntPtr.Zero, code, wParam, lParam);
        }
    }

    public static class WindowStyles {
        private const int GWL_EXSTYLE = -20;
        private const long WS_EX_TRANSPARENT = 0x20L;
        private const long WS_EX_TOOLWINDOW = 0x80L;
        private const long WS_EX_NOACTIVATE = 0x08000000L;
        private const uint MONITOR_DEFAULTTONEAREST = 2;
        [StructLayout(LayoutKind.Sequential)]
        public struct NativeRect { public int Left, Top, Right, Bottom; }
        [StructLayout(LayoutKind.Sequential)]
        public struct NativePoint { public int X, Y; }
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Auto)]
        private struct MonitorInfo {
            public int Size;
            public NativeRect Monitor;
            public NativeRect Work;
            public uint Flags;
        }
        [DllImport("user32.dll", EntryPoint="GetWindowLongPtr")] private static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int index);
        [DllImport("user32.dll", EntryPoint="SetWindowLongPtr")] private static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int index, IntPtr value);
        [DllImport("user32.dll", EntryPoint="GetWindowLong")] private static extern IntPtr GetWindowLongPtr32(IntPtr hWnd, int index);
        [DllImport("user32.dll", EntryPoint="SetWindowLong")] private static extern IntPtr SetWindowLongPtr32(IntPtr hWnd, int index, IntPtr value);
        [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hWnd, out NativeRect rect);
        [DllImport("user32.dll")] private static extern IntPtr MonitorFromWindow(IntPtr hWnd, uint flags);
        [DllImport("user32.dll")] private static extern IntPtr MonitorFromPoint(NativePoint point, uint flags);
        [DllImport("user32.dll", CharSet=CharSet.Auto)] private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
        public static void SetClickThrough(IntPtr hwnd, bool enabled) {
            long style = (IntPtr.Size == 8 ? GetWindowLongPtr64(hwnd, GWL_EXSTYLE) : GetWindowLongPtr32(hwnd, GWL_EXSTYLE)).ToInt64();
            style |= WS_EX_TOOLWINDOW;
            if (enabled) style |= WS_EX_TRANSPARENT | WS_EX_NOACTIVATE;
            else style &= ~(WS_EX_TRANSPARENT | WS_EX_NOACTIVATE);
            if (IntPtr.Size == 8) SetWindowLongPtr64(hwnd, GWL_EXSTYLE, new IntPtr(style));
            else SetWindowLongPtr32(hwnd, GWL_EXSTYLE, new IntPtr(style));
        }
        public static NativeRect GetBounds(IntPtr hwnd) {
            NativeRect rect;
            if (!GetWindowRect(hwnd, out rect)) throw new InvalidOperationException("Unable to read the desktop pet window bounds.");
            return rect;
        }
        public static NativeRect GetWorkArea(IntPtr hwnd) {
            return ReadWorkArea(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST));
        }
        public static NativeRect GetWorkAreaForPoint(int x, int y) {
            NativePoint point = new NativePoint { X = x, Y = y };
            return ReadWorkArea(MonitorFromPoint(point, MONITOR_DEFAULTTONEAREST));
        }
        private static NativeRect ReadWorkArea(IntPtr monitor) {
            MonitorInfo info = new MonitorInfo();
            info.Size = Marshal.SizeOf(typeof(MonitorInfo));
            if (monitor == IntPtr.Zero || !GetMonitorInfo(monitor, ref info)) throw new InvalidOperationException("Unable to read the monitor work area.");
            return info.Work;
        }
    }
}
'@
Add-Type -TypeDefinition $nativeCode -Language CSharp

$script:ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configModule = Join-Path $script:ProjectDir 'config\Config.ps1'
$domainModule = Join-Path $script:ProjectDir 'domain\Rules.ps1'
$applicationModule = Join-Path $script:ProjectDir 'app\GameApplication.ps1'
$storageModule = Join-Path $script:ProjectDir 'infra\Storage.ps1'
. $configModule
. $domainModule
. $applicationModule
. $storageModule
$script:Config = Import-DeepDeskConfig $script:ProjectDir
$script:Content = $script:Config.Content
$script:Balance = $script:Config.Balance
$script:AssetPath = Join-Path $script:ProjectDir 'assets\miner_hamster.png'
$script:SaveDir = if ($env:DEEPDESK_SAVE_DIR) { $env:DEEPDESK_SAVE_DIR } else { Join-Path $env:APPDATA 'DeepDeskMiner' }
$script:SavePath = Join-Path $script:SaveDir 'save-wpf.json'
$script:StartupRegistryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$script:StartupRegistryName = 'DeepDeskMiner'
$script:Rng = [System.Random]::new()
$script:Rarities=@($script:Content.rarities|ForEach-Object{$_.key})
$script:RarityNames=@{};$script:RarityColors=@{};$script:Minerals=@{};$script:MineralValues=@{};$script:OreHp=@{};$script:ChestHp=@{};$script:ChestNames=@{};$script:TargetAssetFiles=[ordered]@{}
foreach($rarity in $script:Content.rarities){$key=[string]$rarity.key;$script:RarityNames[$key]=[string]$rarity.label;$script:RarityColors[$key]=[string]$rarity.color;$script:Minerals[$key]=[string]$rarity.oreName;$script:MineralValues[$key]=[double]$rarity.oreValue;$script:OreHp[$key]=[double]$rarity.oreHp;$script:ChestHp[$key]=[double]$rarity.chestHp;$script:ChestNames[$key]=[string]$rarity.chestName;$script:TargetAssetFiles["ore:$key"]=[string]$rarity.oreAsset;$script:TargetAssetFiles["chest:$key"]=[string]$rarity.chestAsset}
$script:SlotLabels=@{};$script:SlotDefinitions=@{};foreach($slot in $script:Content.slots){$script:SlotLabels[[string]$slot.key]=[string]$slot.label;$script:SlotDefinitions[[string]$slot.key]=$slot}
$script:Pets=@($script:Content.pets|ForEach-Object{[ordered]@{Name=[string]$_.name;Rarity=[string]$_.rarity;Effect=[string]$_.label;Kind=[string]$_.kind;Base=[double]$_.base;Trigger=[int]$_.trigger}})
$script:EquipmentSetsByRarity=[ordered]@{};foreach($rarity in $script:Rarities){$script:EquipmentSetsByRarity[$rarity]=@($script:Content.equipmentSets.$rarity)}
$script:SetEffects=[ordered]@{};foreach($effect in $script:Content.setEffects){$script:SetEffects[[string]$effect.name]=[ordered]@{Kind=[string]$effect.kind;Value=[double]$effect.value;Text=[string]$effect.text}}
$script:SkillNodes=@($script:Content.skills|ForEach-Object{[ordered]@{Id=[string]$_.id;Tree=[string]$_.tree;Tier=[int]$_.tier;Max=[int]$_.max;Name=[string]$_.name;Desc=[string]$_.description;Value=[double]$_.value;Trigger=[int]$_.trigger;Minimum=[int]$_.minimum}})
$script:HitUntil = [datetime]::MinValue
$script:HitStarted = [datetime]::MinValue
$script:ToastUntil = [datetime]::MinValue
$script:DamageFloats = [System.Collections.ArrayList]::new()
$script:LastInput = [datetime]::UtcNow
$script:LastAuto = [datetime]::UtcNow
$script:LastWhale = [datetime]::UtcNow
$script:LastSave = [datetime]::UtcNow
$script:KeyboardTimes = [System.Collections.Generic.Queue[datetime]]::new()
$script:MouseTimes = [System.Collections.Generic.Queue[datetime]]::new()
$script:Exiting = $false
$script:LastLiveRefresh = [datetime]::MinValue
$script:OverlayGestureStart = $null
$script:OverlayGestureWindowStart = $null
$script:OverlayGestureWindowRect = $null
$script:OverlayGestureDragging = $false
$script:OverlayBaseWidth = 370.0
$script:OverlayBaseHeight = 300.0
$script:OverlayScale = 1.0
$script:OverlayHwnd = [IntPtr]::Zero
$script:OverlayNeedsDefaultPosition = $false
$script:OverlayPlacementReady = $false
$script:LastOverlayLayoutCheck = [datetime]::MinValue
$script:RuntimeStage = 'startup'
$script:RuntimeFaultStreak = 0
$script:LastRuntimeFaultStage = ''
$script:LastRuntimeFaultToast = [datetime]::MinValue

function New-SkillState {
    $skills = [ordered]@{}
    foreach ($node in $script:SkillNodes) { $skills[$node.Id] = 0 }
    return $skills
}

function New-State {
    $warehouse=[ordered]@{};foreach($rarity in $script:Rarities){$warehouse[$rarity]=0}
    $equipment=[ordered]@{};foreach($slot in $script:Content.slots){$key=[string]$slot.key;$equipment[$key]=[ordered]@{Slot=$key;Name=[string]$slot.starterName;Set=[string]$script:Content.starterSetName;Rarity='white';Level=1;Value=[double]$slot.starterValue}}
    $starterSlots=@($script:Content.slots|ForEach-Object{[string]$_.key});$catalog=[ordered]@{};$catalog[[string]$script:Content.starterSetName]=$starterSlots
    $starterPet=[string]$script:Pets[0].Name;$pets=[ordered]@{};$pets[$starterPet]=1
    return [ordered]@{
        Version=[int]$script:Balance.saveVersion; DataRevision=1; CreatedAt=(Get-Date).ToString('s'); Depth=1; RunStartDepth=1; MaxDepth=1; Target=$null
        Warehouse=$warehouse; Funds=0.0; SkillPoints=0; ClearedCounter=0; HighestSkillMilestone=0; RunEquipmentCount=0
        Skills=(New-SkillState); Combo=0; Weakness=0; KeyboardRound=0; MouseRound=0
        Pets=$pets; ActivePet=$starterPet; EggsBought=0; Equipment=$equipment
        Inventory=@(); CatalogSets=$catalog; UnlockedSets=@()
        AtSurface=$false; Paused=$false; Completed=$false; OnboardingSeen=$false; StartupEnabled=$true
        Stats=[ordered]@{Keyboard=0;Mouse=0;Auto=0;Layers=0;Returns=0;Chests=0;Highest='white'}
        Position=[ordered]@{Left=$null;Top=$null}
    }
}

$script:State=Read-GameStateFile $script:SavePath (New-State)
$script:State=Invoke-GameStateMigrations $script:State $script:SkillNodes ([int]$script:Balance.saveVersion) ([int]$script:Balance.skillPointEveryLayers)
foreach($slot in @($script:Content.slots|ForEach-Object{[string]$_.key})) {
    if (-not $script:State.Equipment[$slot].Contains('Slot')) { $script:State.Equipment[$slot]['Slot'] = $slot }
}
foreach($item in @($script:State.Inventory)) {
    if (-not $item.Slot -or -not $item.Set) { continue }
    $knownSlots = @()
    if ($script:State.CatalogSets.Contains($item.Set)) { $knownSlots = @($script:State.CatalogSets[$item.Set]) }
    if ($knownSlots -notcontains $item.Slot) { $knownSlots += $item.Slot; $script:State.CatalogSets[$item.Set] = @($knownSlots) }
}
foreach($setName in @($script:SetEffects.Keys)) {
    if ($script:State.CatalogSets.Contains($setName) -and @($script:State.CatalogSets[$setName]).Count -ge $script:Content.slots.Count -and @($script:State.UnlockedSets) -notcontains $setName) {
        $script:State.UnlockedSets = @($script:State.UnlockedSets) + @($setName)
    }
}

function Save-State {
    Write-GameStateFile $script:State $script:SavePath
    $script:LastSave = [datetime]::UtcNow
}

function Get-StartupLaunchCommand {
    $launcherPath = [string]$env:DEEPDESK_LAUNCHER_PATH
    if (-not [string]::IsNullOrWhiteSpace($launcherPath) -and (Test-Path -LiteralPath $launcherPath)) {
        return ('"{0}"' -f $launcherPath)
    }
    $windowsDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
    $powershellPath = Join-Path $windowsDirectory 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $scriptPath = Join-Path $script:ProjectDir 'DeepDesk.ps1'
    return ('"{0}" -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{1}"' -f $powershellPath,$scriptPath)
}

function Set-StartupRegistration([bool]$Enabled) {
    if ($SmokeTest) { return }
    if ($Enabled) {
        if (-not (Test-Path -LiteralPath $script:StartupRegistryPath)) { New-Item -Path $script:StartupRegistryPath -Force | Out-Null }
        New-ItemProperty -LiteralPath $script:StartupRegistryPath -Name $script:StartupRegistryName -Value (Get-StartupLaunchCommand) -PropertyType String -Force | Out-Null
    } elseif (Test-Path -LiteralPath $script:StartupRegistryPath) {
        Remove-ItemProperty -LiteralPath $script:StartupRegistryPath -Name $script:StartupRegistryName -ErrorAction SilentlyContinue
    }
}

function Get-NormalHp([int]$Depth) {
    return Get-NormalHpValue $Depth $script:Balance
}

function Format-Number([double]$Value) {
    if ([double]::IsNaN($Value)) { return '--' }
    if ([double]::IsPositiveInfinity($Value)) { return '∞' }
    if ([double]::IsNegativeInfinity($Value)) { return '-∞' }
    if ($Value -lt 1000) { return '{0:N0}' -f $Value }
    if ($Value -lt 1e6) { return '{0:N2}K' -f ($Value/1e3) }
    if ($Value -lt 1e9) { return '{0:N2}M' -f ($Value/1e6) }
    if ($Value -lt 1e12) { return '{0:N2}B' -f ($Value/1e9) }
    return '{0:0.000e+0}' -f $Value
}

function Get-HpProgress($Target) {
    if(-not$Target){return 0.0}
    $hp=[double]$Target.Hp;$maximum=[double]$Target.MaxHp
    if($maximum-le0-or[double]::IsNaN($hp)-or[double]::IsInfinity($hp)-or[double]::IsNaN($maximum)-or[double]::IsInfinity($maximum)){return 0.0}
    return [math]::Min(100.0,[math]::Max(0.0,100.0*$hp/$maximum))
}

function Get-WeightedRarity([double[]]$Weights) {
    $roll = $script:Rng.NextDouble()
    $cursor = 0.0
    for ($i=0; $i -lt $Weights.Count; $i++) {
        $cursor += $Weights[$i]
        if ($roll -le $cursor) { return $script:Rarities[$i] }
    }
    return 'white'
}

function Get-RarityRecord([string]$Rarity) {
    return $script:Content.rarities | Where-Object key -eq $Rarity | Select-Object -First 1
}

function Select-ConfiguredRarity([string]$WeightProperty) {
    $roll=$script:Rng.NextDouble();$cursor=0.0;$fallback=[string]$script:Rarities[-1]
    foreach($rarity in $script:Content.rarities){$cursor += [double]$rarity.$WeightProperty;if($roll-le$cursor){return [string]$rarity.key}}
    return $fallback
}

function New-Target([int]$Depth) {
    $hp = Get-NormalHp $Depth
    if ($Depth -le [int]$script:Balance.tutorialDepth) { return [ordered]@{Kind='tutorial';Rarity='white';Name='教学岩壁';MaxHp=$hp;Hp=$hp} }
    if ($Depth -ge [int]$script:Balance.maxDepth) {
        $hp = (Get-NormalHp ([int]$script:Balance.maxDepth-1)) * [double]$script:Balance.finalTargetHpMultiplier
        return [ordered]@{Kind='diamond';Rarity='red';Name='地心永恒钻石';MaxHp=$hp;Hp=$hp}
    }
    $treasureSkill=Get-SkillDefinition 'treasure_instinct'
    $chestChance = [math]::Min([double]$script:Balance.chestChanceCap, [double]$script:Balance.chestBaseChance * (1 + (Get-PetBonus 'chest')) + [double]$treasureSkill.Value * (Get-SkillLevel 'treasure_instinct') + (Get-SetBonus 'chest'))
    if ($script:Rng.NextDouble() -lt $chestChance) {
        $rarity = Select-ConfiguredRarity 'chestWeight'
        $max = $hp * [double]$script:ChestHp[$rarity]
        return [ordered]@{Kind='chest';Rarity=$rarity;Name=$script:ChestNames[$rarity];MaxHp=$max;Hp=$max}
    }
    $rarity = Select-ConfiguredRarity 'oreWeight'
    $max = $hp * [double]$script:OreHp[$rarity]
    return [ordered]@{Kind='ore';Rarity=$rarity;Name=$script:Minerals[$rarity];MaxHp=$max;Hp=$max}
}

function Get-PetBonus([string]$Kind) {
    $total = 0.0
    foreach ($pet in $script:Pets) {
        if ($pet.Kind -ne $Kind -or -not $script:State.Pets.Contains($pet.Name)) { continue }
        $ratio = if ($pet.Name -eq $script:State.ActivePet) { 1.0 } else { [double]$script:Balance.inactivePetPassiveRatio }
        $total += (Get-PetScaledBonus $pet ([int]$script:State.Pets[$pet.Name])) * $ratio
    }
    return $total
}
function Get-PetTrigger([string]$Kind) {
    $pet=$script:Pets|Where-Object Kind -eq $Kind|Select-Object -First 1
    if($pet){return [int]$pet.Trigger}
    return 0
}
function Get-PetScaledBonus($Pet,[int]$Level=0) {
    if (-not $Pet) { return 0.0 }
    if ($Level -le 0) { $Level=if($script:State.Pets.Contains($Pet.Name)){[int]$script:State.Pets[$Pet.Name]}else{1} }
    return Get-ScaledEffectValue ([double]$Pet.Base) $Level ([double]$script:State.Equipment.head.Value) (Get-SetBonus 'pet') $script:Balance
}
function Get-PetEffectText($Pet,[int]$Level=0,[double]$Contribution=1.0) {
    $bonus=(Get-PetScaledBonus $Pet $Level)*$Contribution
    switch($Pet.Kind){
        'damage'{return '所有挖矿伤害 +{0:P1}'-f$bonus}
        'yield'{return '矿物数量 +{0:P1}'-f$bonus}
        'funds'{return '返回资金 +{0:P1}'-f$bonus}
        'keyboard'{return '键盘伤害 +{0:P1}'-f$bonus}
        'auto'{return '挂机伤害 +{0:P1}'-f$bonus}
        'chest'{return '宝箱出现率 ×{0:N3}'-f(1+$bonus)}
        'ink'{return "每$($Pet.Trigger)次键盘命中追加 $('{0:P0}'-f$bonus) 基础伤害"}
        'auto_speed'{return '挂机攻击间隔加速 +{0:P1}'-f$bonus}
        'weakness'{return '弱点引爆伤害 +{0:P1}'-f$bonus}
        'rare_yield'{return '蓝色以上矿量 +{0:P1}'-f$bonus}
        'rewind_damage'{return '回挖层全伤害 +{0:P1}'-f$bonus}
        'phoenix'{return "每$($Pet.Trigger)次键盘命中追加 $('{0:P0}'-f$bonus) 基础伤害"}
        'whale'{return "每$($Pet.Trigger)秒挂机追加 $('{0:P0}'-f$bonus) 基础伤害"}
        'gear_luck'{return '装备升品概率 {0:P1}'-f([math]::Min([double]$script:Balance.gearLuckCap,$bonus))}
        'gear_power'{return '宝箱装备属性 +{0:P1}'-f$bonus}
        'chest_damage'{return '对宝箱伤害 +{0:P1}'-f$bonus}
    }
    return $Pet.Effect
}

function Get-EggPrice { return Get-EggPriceValue ([int]$script:State.EggsBought) $script:Balance }

function Get-PetUpgradePrice([int]$Level) { return [math]::Ceiling([double]$script:Balance.petUpgradeBasePrice*[math]::Pow([double]$script:Balance.petUpgradeGrowth,$Level)) }

function Get-SkillDefinition([string]$Id) { return $script:SkillNodes | Where-Object Id -eq $Id | Select-Object -First 1 }

function Get-SkillLevel([string]$Id) {
    if ($script:State.Skills -is [System.Collections.IDictionary] -and $script:State.Skills.Contains($Id)) { return [int]$script:State.Skills[$Id] }
    return 0
}
function Test-SkillUnlocked([string]$Id) {
    return Test-ApplicationSkillUnlocked $script:State $script:SkillNodes $script:Balance $Id
}
function Buy-Skill([string]$Id) {
    if (-not (Invoke-SkillPurchase $script:State $script:SkillNodes $script:Balance $Id)) { return $false }
    Save-State
    return $true
}
function Reset-Skills {
    $refund = Invoke-SkillReset $script:State $script:SkillNodes
    Save-State
    return $refund
}

function Get-BaseDamage { return Get-BaseDamageValue ([double]$script:State.Equipment.pickaxe.Value) $script:Balance }
function Get-SetBonus([string]$Kind) {
    $bonus = 0.0
    foreach ($setName in @($script:State.UnlockedSets)) {
        if ($script:SetEffects.Contains($setName) -and $script:SetEffects[$setName].Kind -eq $Kind) { $bonus += [double]$script:SetEffects[$setName].Value }
    }
    return $bonus
}
function Get-CurrentHitDamage([string]$Kind) {
    $base = Get-BaseDamage
    $rewindMultiplier = if ([int]$script:State.Depth -lt [int]$script:State.MaxDepth) { 1 + (Get-PetBonus 'rewind_damage') } else { 1.0 }
    $targetMultiplier = if ($script:State.Target.Kind -eq 'chest') { 1 + (Get-PetBonus 'chest_damage') } else { 1.0 }
    $allMultiplier = (1 + (Get-PetBonus 'damage')) * (1 + (Get-SetBonus 'damage')) * $rewindMultiplier * $targetMultiplier
    if ($Kind -eq 'keyboard') {
        $tap=Get-SkillDefinition 'trained_tap';$heat=Get-SkillDefinition 'hot_hands';$fast=Get-SkillDefinition 'fast_typing';$symphony=Get-SkillDefinition 'keyboard_symphony'
        return Get-KeyboardDamageValue $base $allMultiplier (Get-SkillLevel 'trained_tap') ([double]$tap.Value) (Get-SkillLevel 'hot_hands') ([double]$heat.Value) ([int]$script:State.Combo) (Get-SkillLevel 'fast_typing') ([double]$fast.Value) ([int]$fast.Trigger) (Get-SkillLevel 'keyboard_symphony') ([double]$symphony.Value) ([int]$symphony.Trigger) (Get-PetBonus 'keyboard') (Get-SetBonus 'keyboard')
    }
    if ($Kind -eq 'mouse') {$precision=Get-SkillDefinition 'precision';return Get-MouseDamageValue $base $allMultiplier (Get-SkillLevel 'precision') ([double]$precision.Value) (Get-SetBonus 'mouse')}
    $idle = [math]::Max(0.0, [double]([datetime]::UtcNow - $script:LastInput).TotalSeconds)
    $drill=Get-SkillDefinition 'steady_drill';$charge=Get-SkillDefinition 'silent_charge';$core=Get-SkillDefinition 'perpetual_core';$chargeStacks=[math]::Min([int]$script:Balance.weaknessMaximum,[math]::Floor($idle/[double]$charge.Trigger))
    return Get-AutoDamageValue $base $allMultiplier (Get-SkillLevel 'steady_drill') ([double]$drill.Value) (Get-SkillLevel 'silent_charge') ([double]$charge.Value) $chargeStacks (Get-SkillLevel 'perpetual_core') ([double]$core.Value) (Get-PetBonus 'auto') (Get-SetBonus 'auto')
}
function Get-AutoInterval {$node=Get-SkillDefinition 'auto_pick';return Get-AutoIntervalValue (Get-SkillLevel 'auto_pick') ([double]$node.Value) (Get-PetBonus 'auto_speed') $script:Balance}
function Get-AffixText($Item) {
    if (-not $Item) { return '' }
    switch ($Item.Slot) {
        'head' { return '宠物效果 +{0:P1}' -f [double]$Item.Value }
        'pickaxe' { return "基础攻击 +$(Format-Number ([double]$script:Balance.pickaxeCoefficient * [double]$Item.Value))（已含镐子强化 20%）" }
        'clothing' { return '返回资金 +{0:P1}' -f [double]$Item.Value }
        'shoes' { return '回挖比例 +{0:P1}' -f [double]$Item.Value }
    }
}
function Get-NextSkillMilestone {
    return [int]$script:State.HighestSkillMilestone + [int]$script:Balance.skillPointEveryLayers
}
function Get-WarehouseValue {
    $sum = 0.0
    foreach ($rarity in $script:Rarities) { $sum += [double]$script:State.Warehouse[$rarity] * [double]$script:MineralValues[$rarity] }
    return $sum
}
function Get-ReturnRatio { return Get-ReturnRatioValue ([double]$script:State.Equipment.shoes.Value) $script:Balance }
function Get-ReturnFunds {
    return [math]::Floor((Get-WarehouseValue) * (1 + [double]$script:Balance.depthFundsPer100 * [math]::Floor([double]$script:State.Depth/100)) * (1 + [double]$script:State.Equipment.clothing.Value) * (1 + (Get-PetBonus 'funds')) * (1 + (Get-SetBonus 'funds')))
}

if (-not $script:State.Target) { $script:State.Target = New-Target ([int]$script:State.Depth) }

function Show-Toast([string]$Text, [string]$Color='#52C7B5') {
    $Toast.Text = $Text; $Toast.Foreground = $Color; $ToastBorder.BorderBrush = $Color; $ToastBorder.Visibility = 'Visible'
    $script:ToastUntil = [datetime]::UtcNow.AddSeconds(3)
}

function Add-DamageFloat([double]$Damage,[string]$Rarity) {
    if(-not$DamageFloatLayer){return}
    if($script:DamageFloats.Count-ge[int]$script:Balance.damageFloatMaximum){$oldest=$script:DamageFloats[0];[void]$DamageFloatLayer.Children.Remove($oldest.Control);$script:DamageFloats.RemoveAt(0)}
    $label=[System.Windows.Controls.TextBlock]::new()
    $label.Text="-$(Format-Number $Damage) HP"
    $label.Width=110;$label.TextAlignment='Center';$label.FontFamily='Microsoft YaHei UI';$label.FontSize=14;$label.FontWeight='ExtraBold'
    $color=if($script:RarityColors.Contains($Rarity)){$script:RarityColors[$Rarity]}else{'#F4F7F4'}
    $label.Foreground=New-UiBrush $color
    $shadow=[System.Windows.Media.Effects.DropShadowEffect]::new();$shadow.Color=[System.Windows.Media.Colors]::Black;$shadow.BlurRadius=5;$shadow.ShadowDepth=2;$shadow.Opacity=.92;$label.Effect=$shadow
    $scale=[System.Windows.Media.ScaleTransform]::new(.94,.94);$label.RenderTransform=$scale;$label.RenderTransformOrigin=[System.Windows.Point]::new(.5,.5)
    $baseX=20+$script:Rng.NextDouble()*20;$baseY=70+$script:Rng.NextDouble()*8;$drift=-7+$script:Rng.NextDouble()*14
    [System.Windows.Controls.Canvas]::SetLeft($label,$baseX);[System.Windows.Controls.Canvas]::SetTop($label,$baseY)
    [void]$DamageFloatLayer.Children.Add($label)
    [void]$script:DamageFloats.Add([pscustomobject]@{Control=$label;Scale=$scale;Started=[datetime]::UtcNow;BaseX=$baseX;BaseY=$baseY;Drift=$drift})
}

function Add-Equipment([string]$Rarity, [int]$Depth) {
    $luck = [math]::Min([double]$script:Balance.gearLuckCap,(Get-PetBonus 'gear_luck'))
    if ($Rarity -ne 'red' -and $luck -gt 0 -and $script:Rng.NextDouble() -lt $luck) {
        $oldRarity=$Rarity;$Rarity=$script:Rarities[$script:Rarities.IndexOf($Rarity)+1]
        Show-Toast "命运九尾：装备从 $($script:RarityNames[$oldRarity]) 提升为 $($script:RarityNames[$Rarity])！" '#FF5E6A'
    }
    $slots = @($script:Content.slots|ForEach-Object{[string]$_.key}); $slot = $slots[$script:Rng.Next(0,$slots.Count)]
    $setPool=@($script:EquipmentSetsByRarity[$Rarity]);$setName=$setPool[$script:Rng.Next(0,$setPool.Count)]
    $coefficient = [double](Get-RarityRecord $Rarity).equipmentCoefficient
    $level = [math]::Max(1,[math]::Round($Depth * (1-[double]$script:Balance.equipmentLevelVariance + $script:Rng.NextDouble()*([double]$script:Balance.equipmentLevelVariance*2))))
    $roll = [double]$script:Balance.equipmentRollMinimum + $script:Rng.NextDouble()*[double]$script:Balance.equipmentRollRange
    $value = switch ($slot) {
        head { [double]$script:Balance.equipmentHeadFactor*$coefficient*[math]::Log($level+1,2)*$roll }
        pickaxe { (Get-NormalHp ([int]$level))*[double]$script:Balance.equipmentPickaxeHpFactor*$coefficient*$roll }
        clothing { [double]$script:Balance.equipmentClothingFactor*$coefficient*[math]::Log($level+1,2)*$roll }
        shoes { [math]::Min([double]$script:Balance.equipmentShoesCap,[double]$script:Balance.equipmentShoesFactor*$coefficient*[math]::Log($level+1,2)*$roll) }
    }
    $value = [double]$value * (1 + (Get-PetBonus 'gear_power'))
    $item = [ordered]@{Slot=$slot;Name=[string]$script:SlotDefinitions[$slot].dropName;Set=$setName;Rarity=$Rarity;Level=$level;Value=$value;Depth=$Depth}
    $script:State.Inventory = @($script:State.Inventory) + @($item)
    $knownSlots = @()
    if ($script:State.CatalogSets.Contains($item.Set)) { $knownSlots = @($script:State.CatalogSets[$item.Set]) }
    if ($knownSlots -notcontains $slot) { $knownSlots += $slot; $script:State.CatalogSets[$item.Set] = @($knownSlots) }
    if ($knownSlots.Count -ge $script:Content.slots.Count -and $script:SetEffects.Contains($item.Set) -and @($script:State.UnlockedSets) -notcontains $item.Set) {
        $script:State.UnlockedSets = @($script:State.UnlockedSets) + @($item.Set)
        Show-Toast "套装完成：$($item.Set) · $($script:SetEffects[$item.Set].Text)" $script:RarityColors[$Rarity]
    }
    $script:State.Stats.Chests = [int]$script:State.Stats.Chests + 1
    $script:State.RunEquipmentCount = [int]$script:State.RunEquipmentCount + 1
    return "$($item.Set)·$($item.Name)"
}

function Clear-Target {
    $target = $script:State.Target; $depth = [int]$script:State.Depth; $drop = ''; $skillAwarded = $false; $equipmentAwarded = $false
    if ($target.Kind -eq 'ore') {
        $yieldBonus=(Get-PetBonus 'yield')+(Get-SetBonus 'yield');if($script:Rarities.IndexOf($target.Rarity)-ge1){$yieldBonus+=Get-PetBonus 'rare_yield'}
        $amount = [math]::Max(1,[math]::Floor((1+[math]::Floor($depth/[int]$script:Balance.oreAmountEveryLayers))*(1+$yieldBonus)))
        $script:State.Warehouse[$target.Rarity] = [int]$script:State.Warehouse[$target.Rarity] + $amount
        $drop = "+$amount $($script:Minerals[$target.Rarity])"
        if ($script:Rarities.IndexOf($target.Rarity) -gt $script:Rarities.IndexOf($script:State.Stats.Highest)) { $script:State.Stats.Highest = $target.Rarity }
    } elseif ($target.Kind -eq 'chest') { $drop = Add-Equipment $target.Rarity $depth; $equipmentAwarded = $true }
    elseif ($target.Kind -eq 'diamond') {
        $script:State.Completed = $true; Save-State
        [void](Show-GameDialog '抵达世界最深处' '你敲下的每一个字、点下的每一次鼠标，都把我们带到了这里。谢谢你陪它挖到世界最深处。' 'Info' '收下永恒钻石')
        return
    }
    $script:State.Stats.Layers = [int]$script:State.Stats.Layers + 1
    $nextDepth = [math]::Min([int]$script:Balance.maxDepth,$depth+1)
    $milestoneInterval = [int]$script:Balance.skillPointEveryLayers
    if ($nextDepth -gt [int]$script:State.HighestSkillMilestone -and $nextDepth % $milestoneInterval -eq 0) {
        $script:State.HighestSkillMilestone = $nextDepth
        $script:State.SkillPoints = [int]$script:State.SkillPoints + 1
        $skillAwarded = $true
        Show-Toast "首次抵达第 $nextDepth 层 · 获得 1 技能点" '#52C7B5'
    } elseif ($target.Kind -eq 'chest' -or $target.Rarity -in @('purple','gold','red')) { Show-Toast "第 $depth 层 · $drop" $script:RarityColors[$target.Rarity] }
    $script:State.Depth = $nextDepth; $script:State.MaxDepth = [math]::Max([int]$script:State.MaxDepth,[int]$script:State.Depth)
    $script:State.Target = New-Target ([int]$script:State.Depth)
    if ($skillAwarded -or $equipmentAwarded) { Save-State }
}

function Invoke-Damage([double]$Damage, [string]$Source) {
    if ($script:State.Paused -or $script:State.Completed -or $script:State.AtSurface) { return }
    $hitRarity=[string]$script:State.Target.Rarity
    $remainingHp=[double]$script:State.Target.Hp-[double]$Damage
    if($remainingHp-lt0.0){$remainingHp=0.0}
    $script:State.Target.Hp=[double]$remainingHp
    $now=[datetime]::UtcNow;$script:HitStarted=$now;$script:HitUntil=$now.AddMilliseconds([double]$script:Balance.hitAnimationMilliseconds)
    $script:LastHitSource = $Source
    Add-DamageFloat $Damage $hitRarity
    if ([double]$script:State.Target.Hp -le 0) { Clear-Target }
}

function Test-Rate([string]$Kind) {
    $queue = $script:MouseTimes
    if ($Kind -eq 'keyboard') { $queue = $script:KeyboardTimes }
    $limit = if ($Kind -eq 'keyboard') {[int]$script:Balance.keyboardRateLimit} else {[int]$script:Balance.mouseRateLimit}; $now=[datetime]::UtcNow
    while ($queue.Count -gt 0 -and ($now-$queue.Peek()).TotalSeconds -ge 1) { [void]$queue.Dequeue() }
    if ($queue.Count -ge $limit) { return $false }; $queue.Enqueue($now); return $true
}

function Invoke-Hit([string]$Kind) {
    if (-not (Test-Rate $Kind) -or $script:State.Paused -or $script:State.AtSurface) { return }
    $wasIdle = ([datetime]::UtcNow-$script:LastInput).TotalSeconds -ge [double]$script:Balance.idleTriggerSeconds; $script:LastInput=[datetime]::UtcNow
    if ($Kind -eq 'keyboard') {
        $script:State.Stats.Keyboard=[int]$script:State.Stats.Keyboard+1; $script:State.KeyboardRound=[int]$script:State.KeyboardRound+1; $script:State.Combo=[math]::Min([int]$script:Balance.comboMaximum,[int]$script:State.Combo+1)
        $damage=Get-CurrentHitDamage 'keyboard'
        $space=Get-SkillDefinition 'space_hammer';if ((Get-SkillLevel 'space_hammer') -gt 0 -and [int]$script:State.KeyboardRound % [int]$space.Trigger -eq 0) { $damage += (Get-BaseDamage) * [double]$space.Value * (Get-SkillLevel 'space_hammer'); Show-Toast '空格重锤！' '#52C7B5' }
        if ([int]$script:State.Stats.Keyboard % (Get-PetTrigger 'ink') -eq 0 -and (Get-PetBonus 'ink') -gt 0) { $damage += (Get-BaseDamage) * (Get-PetBonus 'ink'); Show-Toast '墨水章鱼发动了墨迹打击！' '#B77AFF' }
        if ([int]$script:State.Stats.Keyboard % (Get-PetTrigger 'phoenix') -eq 0 -and (Get-PetBonus 'phoenix') -gt 0) { $damage += (Get-BaseDamage) * (Get-PetBonus 'phoenix'); Show-Toast '万键凤凰发动了炽焰打击！' '#FF5E6A' }
    } else {
        $script:State.Stats.Mouse=[int]$script:State.Stats.Mouse+1; $script:State.MouseRound=[int]$script:State.MouseRound+1; $script:State.Weakness=[math]::Min([int]$script:Balance.weaknessMaximum,[int]$script:State.Weakness+1)
        $damage=Get-CurrentHitDamage 'mouse'
        $quick=Get-SkillDefinition 'quick_mark';$track=Get-SkillDefinition 'crack_tracking';$heart=Get-SkillDefinition 'heart_blast';$markThreshold = [math]::Max([int]$quick.Minimum, [int]$quick.Trigger-[math]::Floor((Get-SkillLevel 'quick_mark')/[double]$quick.Value))
        if ([int]$script:State.MouseRound % $markThreshold -eq 0) { $damage += (Get-BaseDamage)*(1+[double]$track.Value*(Get-SkillLevel 'crack_tracking')*[int]$script:State.Weakness)*(1+(Get-PetBonus 'weakness'))*(1+[double]$heart.Value*(Get-SkillLevel 'heart_blast')); Show-Toast "红心弱点引爆 ×$($script:State.Weakness)" '#FF7994'; $script:State.Weakness=0 }
    }
    $returnBlast=Get-SkillDefinition 'return_blast';if ($wasIdle -and (Get-SkillLevel 'return_blast') -gt 0) { $damage += (Get-BaseDamage) * [double]$returnBlast.Value * (Get-SkillLevel 'return_blast'); Show-Toast '复工爆破！' '#F3B84B' }
    Invoke-Damage $damage $Kind
}

function Invoke-AutoHit {
    if ($script:State.AtSurface) { return }
    $damage=Get-CurrentHitDamage 'auto'
    if ((Get-PetBonus 'whale') -gt 0 -and ([datetime]::UtcNow-$script:LastWhale).TotalSeconds -ge (Get-PetTrigger 'whale')) { $damage += (Get-BaseDamage)*(Get-PetBonus 'whale');$script:LastWhale=[datetime]::UtcNow;Show-Toast '永动鲸发动了鲸落！' '#56A8FF' }
    $script:State.Stats.Auto=[int]$script:State.Stats.Auto+1; Invoke-Damage $damage 'auto'
}

function Equip-BestItems {
    return @(Invoke-BestEquipmentSelection $script:State @($script:Content.slots))
}

function Return-ToSurface {
    $funds=Get-ReturnFunds; $next=[math]::Max(1,[math]::Floor([int]$script:State.Depth*(Get-ReturnRatio)))
    $script:State.Funds=[double]$script:State.Funds+$funds; foreach($r in $script:Rarities){$script:State.Warehouse[$r]=0}
    $script:State.Depth=$next; $script:State.RunStartDepth=$next; $script:State.Target=New-Target $next; $script:State.Combo=0; $script:State.Weakness=0; $script:State.RunEquipmentCount=0; $script:State.AtSurface=$true; $script:State.Stats.Returns=[int]$script:State.Stats.Returns+1
    $autoEquipped=@(Equip-BestItems)
    [DeepDesk.InputHooks]::Enabled=$false
    $equipNotice=if($autoEquipped.Count){" · 自动换装 $($autoEquipped.Count) 件"}else{''};Save-State; Show-Toast "返回地面 · 获得 $(Format-Number $funds) 资金$equipNotice" '#F3B84B'; Update-Details
}

function Start-Mining {
    $script:State.AtSurface = $false
    $script:LastInput = [datetime]::UtcNow
    $script:LastAuto = [datetime]::UtcNow
    [DeepDesk.InputHooks]::Enabled = -not $script:State.Paused
    Save-State; Show-Toast "从第 $($script:State.Depth) 层重新下矿" '#52C7B5'; Update-Details
}

function Require-Surface {
    if ($script:State.AtSurface) { return $true }
    [void](Show-GameDialog '需要返回地面' '宠物孵化、升级与换阵只在返回地面后开放。装备和技能点会在矿井中即时结算。' 'Info' '明白了')
    return $false
}

function Select-EggPet($Remaining) {
    $weights = @{};foreach($rarity in $script:Content.rarities){$weights[[string]$rarity.key]=[double]$rarity.eggWeight}
    $availableRarities = @($Remaining | ForEach-Object {$_.Rarity} | Select-Object -Unique)
    $total = 0.0; foreach($rarity in $availableRarities){$total += [double]$weights[$rarity]}
    $roll = $script:Rng.NextDouble() * $total; $cursor = 0.0; $selectedRarity = $availableRarities[-1]
    foreach($rarity in $availableRarities){$cursor += [double]$weights[$rarity];if($roll -le $cursor){$selectedRarity=$rarity;break}}
    $candidates = @($Remaining | Where-Object Rarity -eq $selectedRarity)
    return $candidates[$script:Rng.Next(0,$candidates.Count)]
}

$overlayXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Width="370" Height="300" WindowStyle="None" AllowsTransparency="True" Background="Transparent" Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize">
 <Canvas Width="370" Height="300">
  <Border Canvas.Left="220" Canvas.Top="54" Width="134" Height="34" CornerRadius="17" Background="#E9142124" BorderBrush="#66365055" BorderThickness="1"><Grid><TextBlock x:Name="FloorText" Foreground="#F3F2E8" FontWeight="Bold" FontSize="12" Margin="14,0,0,0" VerticalAlignment="Center"/><TextBlock x:Name="TargetMini" Foreground="#52C7B5" FontWeight="Bold" FontSize="10" HorizontalAlignment="Right" Margin="0,0,12,0" VerticalAlignment="Center"/></Grid></Border>
  <Grid x:Name="TargetVisual" Canvas.Left="215" Canvas.Top="118" Width="138" Height="120"><Image x:Name="TargetImage" Width="138" Height="120" Stretch="Uniform"/></Grid>
  <Image x:Name="Hamster" Canvas.Left="15" Canvas.Top="73" Width="205" Height="205" Stretch="Uniform" RenderTransformOrigin="0.63,0.72"><Image.RenderTransform><TransformGroup><RotateTransform x:Name="HamsterRotate" Angle="0"/><ScaleTransform x:Name="HamsterScale" ScaleX="1" ScaleY="1"/><TranslateTransform x:Name="HamsterTranslate" X="0" Y="0"/></TransformGroup></Image.RenderTransform></Image>
  <Canvas x:Name="ImpactLayer" Canvas.Left="205" Canvas.Top="103" Width="164" Height="145" IsHitTestVisible="False" Visibility="Collapsed">
   <Ellipse x:Name="ImpactFlash" Canvas.Left="63" Canvas.Top="55" Width="38" Height="38" Stroke="#FFF4B0" StrokeThickness="5" Fill="#44FFFFFF"/>
   <Ellipse x:Name="Impact1" Canvas.Left="76" Canvas.Top="68" Width="10" Height="7" Fill="#F3B84B"/>
   <Ellipse x:Name="Impact2" Canvas.Left="76" Canvas.Top="68" Width="7" Height="10" Fill="#F3B84B"/>
   <Ellipse x:Name="Impact3" Canvas.Left="76" Canvas.Top="68" Width="9" Height="6" Fill="#F3B84B"/>
   <Ellipse x:Name="Impact4" Canvas.Left="76" Canvas.Top="68" Width="6" Height="9" Fill="#F3B84B"/>
   <Ellipse x:Name="Impact5" Canvas.Left="76" Canvas.Top="68" Width="11" Height="7" Fill="#F3B84B"/>
   <Ellipse x:Name="Impact6" Canvas.Left="76" Canvas.Top="68" Width="7" Height="11" Fill="#F3B84B"/>
  </Canvas>
  <Border Canvas.Left="215" Canvas.Top="239" Width="136" Height="20" Background="#E9172225" CornerRadius="10"><Grid Margin="4"><ProgressBar x:Name="HpBar" Minimum="0" Maximum="100" Height="12" Foreground="#52C7B5" Background="#263A3E" BorderThickness="0"/><TextBlock x:Name="HpText" Foreground="White" FontSize="8" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/></Grid></Border>
  <Border Canvas.Left="18" Canvas.Top="242" Width="194" Height="50" Background="#E9142124" BorderBrush="#66365055" BorderThickness="1" CornerRadius="14"><Grid><TextBlock x:Name="WarehouseText" Foreground="#F3B84B" FontSize="10" FontWeight="Bold" Margin="13,5" VerticalAlignment="Center"/></Grid></Border>
  <Border x:Name="ToastBorder" Canvas.Left="20" Canvas.Top="207" Width="330" Height="32" CornerRadius="15" Background="#F0152428" BorderBrush="#52C7B5" BorderThickness="1" Visibility="Collapsed"><TextBlock x:Name="Toast" Foreground="#52C7B5" FontSize="10" FontWeight="Bold" TextAlignment="Center" VerticalAlignment="Center"/></Border>
  <TextBlock x:Name="FloatText" Canvas.Left="245" Canvas.Top="105" Width="100" Foreground="White" FontWeight="Bold" FontSize="13" TextAlignment="Center" Opacity="0"/>
 </Canvas>
</Window>
'@

$detailsXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="桌宠矿工 · Project Deep Desk" Width="960" Height="680" MinWidth="880" MinHeight="620" Background="#111A1D" Foreground="#F3F2E8" WindowStartupLocation="CenterScreen">
 <Window.Resources>
  <Style TargetType="Button"><Setter Property="Background" Value="#263A3E"/><Setter Property="Foreground" Value="#F3F2E8"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Padding" Value="14,8"/><Setter Property="Margin" Value="4"/><Setter Property="Cursor" Value="Hand"/></Style>
  <Style TargetType="TextBlock"><Setter Property="FontFamily" Value="Microsoft YaHei UI"/></Style>
  <Style TargetType="TabItem"><Setter Property="Foreground" Value="#F3F2E8"/><Setter Property="Background" Value="#203034"/><Setter Property="Padding" Value="18,10"/></Style>
  <Style x:Key="Card" TargetType="Border"><Setter Property="Background" Value="#203034"/><Setter Property="CornerRadius" Value="12"/><Setter Property="Padding" Value="18"/><Setter Property="Margin" Value="6"/></Style>
 </Window.Resources>
 <Grid Margin="18"><Grid.RowDefinitions><RowDefinition Height="68"/><RowDefinition Height="*"/></Grid.RowDefinitions>
  <Grid><StackPanel><TextBlock Text="桌宠矿工" FontSize="25" FontWeight="Bold"/><TextBlock Text="PROJECT DEEP DESK" FontSize="10" Foreground="#52C7B5" FontWeight="Bold"/></StackPanel><StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center"><TextBlock x:Name="HeaderFunds" Foreground="#F3B84B" FontWeight="Bold" Margin="15"/><TextBlock x:Name="HeaderSkill" Foreground="#52C7B5" FontWeight="Bold" Margin="15"/><TextBlock x:Name="HeaderDepth" Foreground="#9EB0AD" Margin="15"/></StackPanel></Grid>
  <TabControl Grid.Row="1" Background="#111A1D" BorderThickness="0">
   <TabItem Header="矿井"><Grid Margin="8"><Grid.ColumnDefinitions><ColumnDefinition Width="3*"/><ColumnDefinition Width="2*"/></Grid.ColumnDefinitions>
    <StackPanel><Border Style="{StaticResource Card}"><StackPanel><TextBlock x:Name="MineDepth" FontSize="16" FontWeight="Bold"/><TextBlock x:Name="MineTarget" FontSize="28" FontWeight="Bold" Margin="0,12,0,4"/><TextBlock x:Name="MineHp" Foreground="#9EB0AD"/><ProgressBar x:Name="MineHpBar" Height="14" Margin="0,10,0,8" Minimum="0" Maximum="100" Foreground="#52C7B5"/><TextBlock x:Name="MineMechanics" Foreground="#9EB0AD"/><TextBlock x:Name="AttackDamageText" Foreground="#52C7B5" FontSize="14" FontWeight="Bold" Margin="0,12,0,0"/></StackPanel></Border><Border Style="{StaticResource Card}"><StackPanel><TextBlock Text="本轮收获" FontSize="16" FontWeight="Bold"/><TextBlock x:Name="MineWarehouseValue" Foreground="#F3B84B" FontSize="20" FontWeight="Bold" Margin="0,8"/><TextBlock x:Name="MineWarehouse" Foreground="#52C7B5" LineHeight="26"/></StackPanel></Border></StackPanel>
    <StackPanel Grid.Column="1"><Border Style="{StaticResource Card}"><StackPanel><TextBlock Text="返回地面预览" FontSize="16" FontWeight="Bold"/><TextBlock x:Name="ReturnPreview" Foreground="#9EB0AD" LineHeight="29" Margin="0,12"/><Button x:Name="ConfirmReturnButton" Content="返回地面" Background="#52C7B5" Foreground="#0B1B1A" FontWeight="Bold"/><Button x:Name="DescendButton" Content="整备完成 · 继续下矿" Background="#F3B84B" Foreground="#0B1B1A" FontWeight="Bold" Visibility="Collapsed"/></StackPanel></Border><Border Style="{StaticResource Card}"><StackPanel><TextBlock Text="运行状态" FontSize="16" FontWeight="Bold"/><TextBlock x:Name="BuildInfo" Foreground="#9EB0AD" LineHeight="27" Margin="0,10"/><Button x:Name="PanelPauseButton" Content="暂停挖矿"/></StackPanel></Border></StackPanel>
   </Grid></TabItem>
   <TabItem Header="技能"><ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Margin="14"><Grid Margin="5,0,5,12"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel><TextBlock Text="技能树" FontSize="20" FontWeight="Bold"/><TextBlock Text="首次抵达 70、140、210…层时各获得 1 点；回挖不重复。" Foreground="#9EB0AD" Margin="0,5,0,0"/><TextBlock x:Name="SkillSummary" Foreground="#52C7B5" FontWeight="Bold" Margin="0,7,0,0"/></StackPanel><Button x:Name="ResetSkillsButton" Grid.Column="1" Content="免费重置全部技能" Background="#B77AFF" Foreground="#111A1D" FontWeight="Bold" VerticalAlignment="Center"/></Grid><Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions><StackPanel x:Name="KeyboardTreePanel" Grid.Column="0"/><StackPanel x:Name="IdleTreePanel" Grid.Column="1"/><StackPanel x:Name="MouseTreePanel" Grid.Column="2"/></Grid></StackPanel></ScrollViewer></TabItem>
   <TabItem Header="宠物"><Grid Margin="14"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions><Border Style="{StaticResource Card}"><Grid><StackPanel><TextBlock Text="矿工宠物蛋" FontSize="18" FontWeight="Bold"/><TextBlock x:Name="EggInfo" Foreground="#9EB0AD" Margin="0,7"/></StackPanel><Button x:Name="HatchButton" Content="孵化伙伴" Background="#52C7B5" Foreground="#0B1B1A" FontWeight="Bold" HorizontalAlignment="Right" VerticalAlignment="Center"/></Grid></Border><Border Grid.Row="1" Style="{StaticResource Card}"><Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><TextBlock Text="同行伙伴" FontSize="18" FontWeight="Bold"/><ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="0,8,0,8"><TextBlock x:Name="PetsList" Foreground="#9EB0AD" LineHeight="30" TextWrapping="Wrap"/></ScrollViewer><StackPanel Grid.Row="2"><TextBlock x:Name="PetUpgradeInfo" Foreground="#F3B84B" Margin="4,0,4,4"/><StackPanel Orientation="Horizontal"><Button x:Name="NextPetButton" Content="切换出战"/><Button x:Name="UpgradePetButton" Content="升级当前伙伴" Background="#52C7B5" Foreground="#0B1B1A" FontWeight="Bold"/></StackPanel></StackPanel></Grid></Border></Grid></TabItem>
   <TabItem Header="装备"><Grid Margin="14"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions><Border Style="{StaticResource Card}"><StackPanel><TextBlock Text="当前穿戴" FontSize="18" FontWeight="Bold"/><TextBlock Text="返回地面后会自动穿上各部位属性最高的装备" Foreground="#52C7B5" FontWeight="Bold" Margin="0,6,0,0"/><TextBlock x:Name="EquippedList" Foreground="#9EB0AD" LineHeight="28" Margin="0,8"/></StackPanel></Border><Grid Grid.Row="1"><Grid.ColumnDefinitions><ColumnDefinition Width="3*"/><ColumnDefinition Width="2*"/></Grid.ColumnDefinitions><Border Style="{StaticResource Card}"><Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions><TextBlock Text="永久背包 · 查看全部装备" FontSize="18" FontWeight="Bold"/><StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,10,0,0"><TextBlock Text="分类" Foreground="#9EB0AD" VerticalAlignment="Center" Margin="0,0,10,0"/><ComboBox x:Name="EquipmentFilter" Width="160" Height="30" Background="#F3F2E8" Foreground="#111A1D" BorderBrush="#426064"/></StackPanel><ListBox x:Name="InventoryListBox" Grid.Row="2" Margin="0,10,0,0" Background="#182427" Foreground="#F3F2E8" BorderThickness="0" FontFamily="Microsoft YaHei UI"/></Grid></Border><Border Grid.Column="1" Style="{StaticResource Card}"><StackPanel><TextBlock Text="装备属性" FontSize="18" FontWeight="Bold"/><TextBlock x:Name="SelectedItemDetails" Foreground="#9EB0AD" LineHeight="28" Margin="0,14" TextWrapping="Wrap"/></StackPanel></Border></Grid></Grid></TabItem>
   <TabItem Header="图鉴"><ScrollViewer><StackPanel Margin="14"><Border Style="{StaticResource Card}"><StackPanel><TextBlock Text="矿物图鉴" FontSize="18" FontWeight="Bold"/><TextBlock x:Name="MineralCatalog" FontSize="16" Foreground="#9EB0AD" Margin="0,14"/></StackPanel></Border><Border Style="{StaticResource Card}"><StackPanel><TextBlock Text="伙伴图鉴" FontSize="18" FontWeight="Bold"/><TextBlock x:Name="PetCatalog" Foreground="#9EB0AD" LineHeight="28" Margin="0,10" TextWrapping="Wrap"/></StackPanel></Border><Border Style="{StaticResource Card}"><StackPanel><TextBlock Text="套装图鉴与永久效果" FontSize="18" FontWeight="Bold"/><TextBlock x:Name="SetCatalog" Foreground="#9EB0AD" LineHeight="28" Margin="0,10" TextWrapping="Wrap"/></StackPanel></Border></StackPanel></ScrollViewer></TabItem>
   <TabItem Header="档案"><Grid Margin="14"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions><Border Style="{StaticResource Card}"><StackPanel><TextBlock Text="旅程统计" FontSize="18" FontWeight="Bold"/><TextBlock x:Name="StatsText" Foreground="#9EB0AD" LineHeight="29" Margin="0,10"/></StackPanel></Border><StackPanel Grid.Column="1"><Border Style="{StaticResource Card}"><StackPanel><TextBlock Text="隐私边界" FontSize="18" FontWeight="Bold"/><TextBlock Text="只累计匿名的键盘、鼠标和挂机次数。程序不保存字符、键码、输入文字、鼠标坐标、前台应用、剪贴板或屏幕内容。所有存档仅在本机。" Foreground="#9EB0AD" TextWrapping="Wrap" LineHeight="24" Margin="0,10"/></StackPanel></Border><Border Style="{StaticResource Card}"><StackPanel><Button x:Name="OpenSaveButton" Content="打开本地存档位置"/><Button x:Name="ExitButton" Content="退出桌宠矿工" Background="#FF6B6B"/></StackPanel></Border></StackPanel></Grid></TabItem>
  </TabControl>
 </Grid>
</Window>
'@

# UI markup is kept outside the runtime so visual iteration does not touch game rules.
$overlayXaml = Get-Content -LiteralPath (Join-Path $script:ProjectDir 'ui\overlay.xaml') -Raw -Encoding UTF8
$detailsXaml = Get-Content -LiteralPath (Join-Path $script:ProjectDir 'ui\panel.xaml') -Raw -Encoding UTF8
$script:DialogXaml = Get-Content -LiteralPath (Join-Path $script:ProjectDir 'ui\dialog.xaml') -Raw -Encoding UTF8

function Load-Xaml([string]$Text) {
    $reader = [System.Xml.XmlNodeReader]::new([xml]$Text)
    return [Windows.Markup.XamlReader]::Load($reader)
}
$Overlay = Load-Xaml $overlayXaml
$Details = Load-Xaml $detailsXaml
foreach($name in @('FloorText','TargetMini','TargetVisual','TargetImage','TargetScale','TargetRotate','TargetTranslate','Hamster','HamsterRotate','HamsterScale','HamsterTranslate','ImpactLayer','ImpactFlash','Impact1','Impact2','Impact3','Impact4','Impact5','Impact6','DamageFloatLayer','HpBar','HpText','RunReportButton','WarehouseText','ToastBorder','Toast','FloatText')) { Set-Variable -Scope Script -Name $name -Value $Overlay.FindName($name) }
foreach($name in @('AdventureTabs','HeaderFunds','HeaderSkill','HeaderDepth','MineDepth','MineTarget','MineHp','MineHpBar','MineMechanics','AttackDamageText','MineWarehouseValue','MineWarehouse','ReturnPreview','ConfirmReturnButton','DescendButton','BuildInfo','PanelPauseButton','SkillSummary','ResetSkillsButton','KeyboardTreePanel','IdleTreePanel','MouseTreePanel','EggInfo','HatchButton','PetsList','PetUpgradeInfo','NextPetButton','UpgradePetButton','EquippedList','EquipmentFilter','InventoryListBox','SelectedItemDetails','MineralCatalog','PetCatalog','SetCatalog','StatsText','StartupCheckBox','OpenSaveButton','ExitButton')) { Set-Variable -Scope Script -Name $name -Value $Details.FindName($name) }

function Load-Bitmap([string]$Path) {
    $bitmap = [System.Windows.Media.Imaging.BitmapImage]::new(); $bitmap.BeginInit(); $bitmap.CacheOption='OnLoad'; $bitmap.UriSource=[uri]$Path; $bitmap.EndInit(); $bitmap.Freeze()
    return $bitmap
}
$Hamster.Source = Load-Bitmap $script:AssetPath
$script:TargetImages = @{}
foreach ($key in $script:TargetAssetFiles.Keys) { $script:TargetImages[$key] = Load-Bitmap (Join-Path $script:ProjectDir "assets\$($script:TargetAssetFiles[$key])") }
foreach ($filterName in @('全部装备','头部','镐子','衣服','鞋子','普通','稀有','史诗','传说','神话')) { [void]$EquipmentFilter.Items.Add($filterName) }
$EquipmentFilter.SelectedIndex = 0
$StartupCheckBox.IsChecked = [bool]$script:State.StartupEnabled

function Get-OverlayDpiScale {
    try {
        $dpi=[System.Windows.Media.VisualTreeHelper]::GetDpi($Overlay)
        $x=if([double]$dpi.DpiScaleX-gt0){[double]$dpi.DpiScaleX}else{1.0}
        $y=if([double]$dpi.DpiScaleY-gt0){[double]$dpi.DpiScaleY}else{1.0}
        return [pscustomobject]@{X=$x;Y=$y}
    } catch { return [pscustomobject]@{X=1.0;Y=1.0} }
}

function Get-ResponsiveOverlayScaleForSize([double]$WorkWidthDip,[double]$WorkHeightDip) {
    $scale=[math]::Min(1.0,[math]::Min([double]($workWidthDip/2200.0),[double]($workHeightDip/1250.0)))
    if($scale-lt.62){$scale=.62}
    return [math]::Round([double]$scale,3)
}

function Get-ResponsiveOverlayScale($WorkArea) {
    $dpi=Get-OverlayDpiScale
    $workWidthDip=([double]$WorkArea.Right-[double]$WorkArea.Left)/[double]$dpi.X
    $workHeightDip=([double]$WorkArea.Bottom-[double]$WorkArea.Top)/[double]$dpi.Y
    return Get-ResponsiveOverlayScaleForSize $workWidthDip $workHeightDip
}

function Update-OverlayResponsiveLayout([switch]$DockBottomRight,[switch]$Persist) {
    if($script:OverlayHwnd-eq[IntPtr]::Zero){return}
    $work=[DeepDesk.WindowStyles]::GetWorkArea($script:OverlayHwnd)
    $targetScale=Get-ResponsiveOverlayScale $work
    if([math]::Abs([double]$script:OverlayScale-[double]$targetScale)-gt.001){
        $script:OverlayScale=[double]$targetScale
        $Overlay.Width=$script:OverlayBaseWidth*$script:OverlayScale
        $Overlay.Height=$script:OverlayBaseHeight*$script:OverlayScale
        $Overlay.UpdateLayout()
    }
    $dpi=Get-OverlayDpiScale
    $bounds=[DeepDesk.WindowStyles]::GetBounds($script:OverlayHwnd)
    $width=[double]$bounds.Right-[double]$bounds.Left
    $height=[double]$bounds.Bottom-[double]$bounds.Top
    $marginX=18.0*[double]$dpi.X;$marginY=18.0*[double]$dpi.Y
    if($DockBottomRight){
        $targetLeft=[double]$work.Right-$width-$marginX
        $targetTop=[double]$work.Bottom-$height-$marginY
    }else{
        $targetLeft=[double]$bounds.Left;$targetTop=[double]$bounds.Top
        $maxLeft=[double]$work.Right-$width;$maxTop=[double]$work.Bottom-$height
        if($targetLeft-lt[double]$work.Left){$targetLeft=[double]$work.Left}elseif($targetLeft-gt$maxLeft){$targetLeft=$maxLeft}
        if($targetTop-lt[double]$work.Top){$targetTop=[double]$work.Top}elseif($targetTop-gt$maxTop){$targetTop=$maxTop}
    }
    $dx=$targetLeft-[double]$bounds.Left;$dy=$targetTop-[double]$bounds.Top
    if([math]::Abs($dx)-gt.25){$Overlay.Left=[double]$Overlay.Left+$dx/[double]$dpi.X}
    if([math]::Abs($dy)-gt.25){$Overlay.Top=[double]$Overlay.Top+$dy/[double]$dpi.Y}
    if($Persist){$script:State.Position.Left=[double]$Overlay.Left;$script:State.Position.Top=[double]$Overlay.Top}
}

function Set-OverlayPhysicalPosition([double]$DesiredLeft,[double]$DesiredTop,$CursorPosition) {
    if($script:OverlayHwnd-eq[IntPtr]::Zero){return}
    $work=[DeepDesk.WindowStyles]::GetWorkAreaForPoint([int]$CursorPosition.X,[int]$CursorPosition.Y)
    $bounds=[DeepDesk.WindowStyles]::GetBounds($script:OverlayHwnd)
    $width=[double]$bounds.Right-[double]$bounds.Left;$height=[double]$bounds.Bottom-[double]$bounds.Top
    $maxLeft=[double]$work.Right-$width;$maxTop=[double]$work.Bottom-$height
    $targetLeft=[double]$DesiredLeft;$targetTop=[double]$DesiredTop
    if($targetLeft-lt[double]$work.Left){$targetLeft=[double]$work.Left}elseif($targetLeft-gt$maxLeft){$targetLeft=$maxLeft}
    if($targetTop-lt[double]$work.Top){$targetTop=[double]$work.Top}elseif($targetTop-gt$maxTop){$targetTop=$maxTop}
    $dpi=Get-OverlayDpiScale
    $Overlay.Left=[double]$Overlay.Left+($targetLeft-[double]$bounds.Left)/[double]$dpi.X
    $Overlay.Top=[double]$Overlay.Top+($targetTop-[double]$bounds.Top)/[double]$dpi.Y
}

$script:OverlayNeedsDefaultPosition=$null-eq$script:State.Position.Left-or$null-eq$script:State.Position.Top
if($script:OverlayNeedsDefaultPosition){$Overlay.Left=0;$Overlay.Top=0}else{$Overlay.Left=[double]$script:State.Position.Left;$Overlay.Top=[double]$script:State.Position.Top}
$Overlay.Add_SourceInitialized({
    $script:OverlayHwnd=[System.Windows.Interop.WindowInteropHelper]::new($Overlay).Handle
    [DeepDesk.WindowStyles]::SetClickThrough($script:OverlayHwnd,$true)
})
$Overlay.Add_Loaded({
    Update-OverlayResponsiveLayout -DockBottomRight:$script:OverlayNeedsDefaultPosition -Persist
    $script:OverlayNeedsDefaultPosition=$false;$script:OverlayPlacementReady=$true
})
$Details.Add_Closing({ param($sender,$event) if(-not $script:Exiting){$event.Cancel=$true;$sender.Hide()} })

function Start-OverlayGesture($Sender,$Event) {
    $script:OverlayGestureStart=[System.Windows.Forms.Cursor]::Position
    $script:OverlayGestureWindowStart=[System.Windows.Point]::new($Overlay.Left,$Overlay.Top)
    $script:OverlayGestureWindowRect=if($script:OverlayHwnd-ne[IntPtr]::Zero){[DeepDesk.WindowStyles]::GetBounds($script:OverlayHwnd)}else{$null}
    $script:OverlayGestureDragging=$false
    [void]$Sender.CaptureMouse();$Event.Handled=$true
}
function Move-OverlayGesture($Sender,$Event) {
    if($null-eq$script:OverlayGestureStart-or$Event.LeftButton-ne[System.Windows.Input.MouseButtonState]::Pressed){return}
    $point=[System.Windows.Forms.Cursor]::Position;$dx=$point.X-$script:OverlayGestureStart.X;$dy=$point.Y-$script:OverlayGestureStart.Y
    if(-not$script:OverlayGestureDragging-and([math]::Abs($dx)-gt5-or[math]::Abs($dy)-gt5)){$script:OverlayGestureDragging=$true}
    if($script:OverlayGestureDragging){
        if($null-ne$script:OverlayGestureWindowRect){Set-OverlayPhysicalPosition ([double]$script:OverlayGestureWindowRect.Left+$dx) ([double]$script:OverlayGestureWindowRect.Top+$dy) $point}
        else{$dpi=Get-OverlayDpiScale;$Overlay.Left=$script:OverlayGestureWindowStart.X+$dx/[double]$dpi.X;$Overlay.Top=$script:OverlayGestureWindowStart.Y+$dy/[double]$dpi.Y}
    }
    $Event.Handled=$true
}
function Stop-OverlayGesture($Sender,$Event) {
    if($Sender.IsMouseCaptured){$Sender.ReleaseMouseCapture()}
    if($script:OverlayGestureDragging){Update-OverlayResponsiveLayout -Persist;Save-State}
    $script:OverlayGestureStart=$null;$script:OverlayGestureWindowStart=$null;$script:OverlayGestureWindowRect=$null;$script:OverlayGestureDragging=$false;$Event.Handled=$true
}
foreach($surface in @($Hamster)){$surface.Add_PreviewMouseLeftButtonDown({param($sender,$event)Start-OverlayGesture $sender $event});$surface.Add_PreviewMouseMove({param($sender,$event)Move-OverlayGesture $sender $event});$surface.Add_PreviewMouseLeftButtonUp({param($sender,$event)Stop-OverlayGesture $sender $event})}

function Show-GameDialog([string]$Title,[string]$Message,[ValidateSet('Info','Confirm')][string]$Mode='Info',[string]$ConfirmText='确认') {
    $dialog=Load-Xaml $script:DialogXaml
    if($Details.IsVisible){$dialog.Owner=$Details}
    $dialog.FindName('DialogTitle').Text=$Title
    $dialog.FindName('DialogMessage').Text=$Message
    $confirm=$dialog.FindName('DialogConfirmButton');$cancel=$dialog.FindName('DialogCancelButton')
    $confirm.Content=$ConfirmText
    if($Mode-eq'Info'){$cancel.Visibility='Collapsed';$confirm.Content=if($ConfirmText-eq'确认'){'知道了'}else{$ConfirmText}}
    $confirm.Add_Click({$dialog.DialogResult=$true})
    $cancel.Add_Click({$dialog.DialogResult=$false})
    return [bool]$dialog.ShowDialog()
}

function Update-RunReportDisplays {
    $valueText=Format-Number (Get-WarehouseValue)
    $equipmentCount=[int]$script:State.RunEquipmentCount
    $WarehouseText.Text="已获得矿物价值：$valueText 金币`n已获得装备：$equipmentCount 件"
    $MineWarehouseValue.Text="已获得矿物价值：$valueText 金币"
    $MineWarehouse.Text="已获得装备：$equipmentCount 件"
}

function Update-Overlay {
    $target=$script:State.Target; $FloorText.Text="第 $($script:State.Depth) 层"; $TargetMini.Text=if($script:State.AtSurface){'地面整备'}elseif($script:State.Paused){'暂停'}else{$target.Name}; $TargetMini.Foreground=if($script:State.AtSurface){'#F3B84B'}else{$script:RarityColors[$target.Rarity]}
    $rarityBrush=New-UiBrush $script:RarityColors[$target.Rarity];$HpBar.Foreground=$rarityBrush
    $progress=if($script:State.AtSurface){0}else{Get-HpProgress $target}; $HpBar.Value=$progress; $HpText.Text=if($script:State.AtSurface){'地面营地'}else{"$(Format-Number ([double]$target.Hp)) HP"}; Update-RunReportDisplays
    $TargetVisual.Visibility=if($script:State.AtSurface){'Collapsed'}else{'Visible'}
    if (-not $script:State.AtSurface) {
        $assetKey = if ($target.Kind -eq 'tutorial') {'ore:white'} elseif ($target.Kind -eq 'diamond') {'ore:red'} else {"$($target.Kind):$($target.Rarity)"}
        if ($script:TargetImages.ContainsKey($assetKey)) { $TargetImage.Source = $script:TargetImages[$assetKey] }
    }
    $now = [datetime]::UtcNow
    if ($now -lt $script:HitUntil) {
        $elapsed=($now-$script:HitStarted).TotalMilliseconds;$duration=[double]$script:Balance.hitAnimationMilliseconds;$p=[math]::Min(1.0,[math]::Max(0.0,[double]($elapsed/$duration)));$strength=1-$p
        $HamsterRotate.Angle=if($elapsed-lt120){-19}elseif($elapsed-lt240){9}else{-5*$strength};$HamsterScale.ScaleX=1+.09*$strength;$HamsterScale.ScaleY=1-.05*$strength;$HamsterTranslate.X=8*$strength;$HamsterTranslate.Y=0
        $TargetScale.ScaleX=1;$TargetScale.ScaleY=1;$TargetRotate.Angle=0;$TargetTranslate.X=[math]::Sin($elapsed/19.0)*6*$strength
        $ImpactLayer.Visibility='Visible';$ImpactLayer.Opacity=[math]::Min(1.0,[double](1.5*$strength));$flashSize=38+78*$p;$ImpactFlash.Width=$flashSize;$ImpactFlash.Height=$flashSize;[System.Windows.Controls.Canvas]::SetLeft($ImpactFlash,82-$flashSize/2);[System.Windows.Controls.Canvas]::SetTop($ImpactFlash,73-$flashSize/2);$particleBrush=New-UiBrush $script:RarityColors[$target.Rarity];$dx=@(-1.0,-.65,0,.65,1.0,.45);$dy=@(-.15,-.82,-1.0,-.78,-.12,.78);$distance=58*$p;for($i=0;$i-lt6;$i++){$particle=Get-Variable -Scope Script -Name "Impact$($i+1)" -ValueOnly;$particle.Fill=$particleBrush;[System.Windows.Controls.Canvas]::SetLeft($particle,78+$dx[$i]*$distance);[System.Windows.Controls.Canvas]::SetTop($particle,70+$dy[$i]*$distance)}
    } else {
        $HamsterRotate.Angle=0;$HamsterScale.ScaleX=1;$HamsterScale.ScaleY=1;$HamsterTranslate.X=0;$HamsterTranslate.Y=0;$TargetScale.ScaleX=1;$TargetScale.ScaleY=1;$TargetRotate.Angle=0;$TargetTranslate.X=0;$ImpactLayer.Visibility='Collapsed'
    }
    for($i=$script:DamageFloats.Count-1;$i-ge0;$i--){$entry=$script:DamageFloats[$i];$floatP=($now-$entry.Started).TotalMilliseconds/[double]$script:Balance.damageFloatMilliseconds;if($floatP-ge1){[void]$DamageFloatLayer.Children.Remove($entry.Control);$script:DamageFloats.RemoveAt($i);continue};$rise=[double]$script:Balance.damageFloatRisePixels*$floatP;[System.Windows.Controls.Canvas]::SetLeft($entry.Control,$entry.BaseX+$entry.Drift*$floatP);[System.Windows.Controls.Canvas]::SetTop($entry.Control,$entry.BaseY-$rise);$entry.Control.Opacity=[math]::Pow(1-$floatP,.72);$floatScale=.94+.06*[math]::Min(1.0,[double]($floatP/.18));$entry.Scale.ScaleX=$floatScale;$entry.Scale.ScaleY=$floatScale}
    if($now -ge $script:ToastUntil){$ToastBorder.Visibility='Collapsed'}
}

function New-UiBrush([string]$Color) { return [System.Windows.Media.BrushConverter]::new().ConvertFromString($Color) }
function Render-SkillTrees {
    $trees = @(
        [ordered]@{Id='keyboard';Title='⌨  敲击系';Color='#52C7B5';Panel=$KeyboardTreePanel},
        [ordered]@{Id='idle';Title='⚙  挂机系';Color='#F3B84B';Panel=$IdleTreePanel},
        [ordered]@{Id='mouse';Title='◆  鼠标系';Color='#FF7994';Panel=$MouseTreePanel}
    )
    $spent = 0; foreach($node in $script:SkillNodes){$spent += Get-SkillLevel $node.Id}
    $SkillSummary.Text="可用 $($script:State.SkillPoints) 点  ·  已投入 $spent 点  ·  重置费用 0"
    $ResetSkillsButton.IsEnabled = $spent -gt 0
    foreach($tree in $trees){
        $panel=$tree.Panel; $panel.Children.Clear()
        $header=[System.Windows.Controls.TextBlock]::new();$header.Text=$tree.Title;$header.FontSize=17;$header.FontWeight='Bold';$header.Foreground=New-UiBrush $tree.Color;$header.Margin=[System.Windows.Thickness]::new(6,0,6,8);[void]$panel.Children.Add($header)
        $nodes=@();foreach($tier in 1..5){$nodes+=@($script:SkillNodes|Where-Object{$_.Tree-eq$tree.Id-and[int]$_.Tier-eq$tier}|Select-Object -First 1)}
        foreach($node in $nodes){
            if([int]$node.Tier-gt1){$link=[System.Windows.Controls.TextBlock]::new();$link.Text='↓';$link.TextAlignment='Center';$link.Foreground=New-UiBrush '#60777A';$link.FontSize=16;$link.Height=22;[void]$panel.Children.Add($link)}
            $level=Get-SkillLevel $node.Id;$unlocked=Test-SkillUnlocked $node.Id
            $card=[System.Windows.Controls.Border]::new();$card.Background=New-UiBrush $(if($unlocked){'#203034'}else{'#182326'});$card.BorderBrush=New-UiBrush $(if($unlocked){$tree.Color}else{'#314044'});$card.BorderThickness=[System.Windows.Thickness]::new(1);$card.CornerRadius=[System.Windows.CornerRadius]::new(10);$card.Padding=[System.Windows.Thickness]::new(12);$card.Margin=[System.Windows.Thickness]::new(5,0,5,0)
            $stack=[System.Windows.Controls.StackPanel]::new();$title=[System.Windows.Controls.TextBlock]::new();$title.Text="第 $($node.Tier) 层 · $($node.Name)";$title.FontWeight='Bold';$title.FontSize=14;$title.Foreground=New-UiBrush $(if($unlocked){'#F3F2E8'}else{'#718083'});[void]$stack.Children.Add($title)
            $desc=[System.Windows.Controls.TextBlock]::new();$desc.Text=$node.Desc;$desc.TextWrapping='Wrap';$desc.Foreground=New-UiBrush '#9EB0AD';$desc.FontSize=11;$desc.Margin=[System.Windows.Thickness]::new(0,5,0,7);[void]$stack.Children.Add($desc)
            $footer=[System.Windows.Controls.Grid]::new();[void]$footer.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new());$autoColumn=[System.Windows.Controls.ColumnDefinition]::new();$autoColumn.Width=[System.Windows.GridLength]::Auto;[void]$footer.ColumnDefinitions.Add($autoColumn)
            $levelText=[System.Windows.Controls.TextBlock]::new();$levelText.Text="Lv.$level / $($node.Max)";$levelText.Foreground=New-UiBrush $tree.Color;$levelText.VerticalAlignment='Center';[void]$footer.Children.Add($levelText)
            $button=[System.Windows.Controls.Button]::new();$button.Tag=$node.Id;$button.Content=if(-not$unlocked){"需上层 Lv.$($script:Balance.skillUnlockPreviousLevel)"}elseif($level-ge[int]$node.Max){'已满级'}else{'投入 1 点'};$button.IsEnabled=$unlocked-and$level-lt[int]$node.Max-and[int]$script:State.SkillPoints-gt0;$button.Padding=[System.Windows.Thickness]::new(9,5,9,5);[System.Windows.Controls.Grid]::SetColumn($button,1);$button.Add_Click({param($sender,$event)if(Buy-Skill ([string]$sender.Tag)){Update-Details}});[void]$footer.Children.Add($button)
            [void]$stack.Children.Add($footer);$card.Child=$stack;[void]$panel.Children.Add($card)
        }
    }
}

function Refresh-InventoryList {
    $filter=if($EquipmentFilter.SelectedItem){[string]$EquipmentFilter.SelectedItem}else{'全部装备'}
    $items=@($script:State.Inventory)
    $slotFilter=@{'头部'='head';'镐子'='pickaxe';'衣服'='clothing';'鞋子'='shoes'}
    $rarityFilter=@{'普通'='white';'稀有'='blue';'史诗'='purple';'传说'='gold';'神话'='red'}
    if($slotFilter.ContainsKey($filter)){$wanted=$slotFilter[$filter];$items=@($items|Where-Object Slot -eq $wanted)}
    elseif($rarityFilter.ContainsKey($filter)){$wanted=$rarityFilter[$filter];$items=@($items|Where-Object Rarity -eq $wanted)}
    $script:VisibleInventory=@($items);[array]::Reverse($script:VisibleInventory)
    $InventoryListBox.Items.Clear()
    foreach($item in $script:VisibleInventory){
        $row=[System.Windows.Controls.ListBoxItem]::new()
        $row.Content="$($script:RarityNames[$item.Rarity])  $($script:SlotLabels[$item.Slot])  $($item.Set)·$($item.Name)  Lv.$($item.Level)  ·  $(Get-AffixText $item)"
        $row.Foreground=New-UiBrush $script:RarityColors[$item.Rarity]
        $row.Padding=[System.Windows.Thickness]::new(7,5,7,5)
        $row.Tag=$item.Rarity
        [void]$InventoryListBox.Items.Add($row)
    }
    if(-not$script:VisibleInventory.Count){$emptyRow=[System.Windows.Controls.ListBoxItem]::new();$emptyRow.Content=if(@($script:State.Inventory).Count-eq0){'尚未从宝箱获得装备'}else{"$filter 分类暂无装备"};$emptyRow.Foreground=New-UiBrush '#718083';$emptyRow.IsEnabled=$false;[void]$InventoryListBox.Items.Add($emptyRow)}
    $SelectedItemDetails.Foreground=New-UiBrush '#9EB0AD'
    $SelectedItemDetails.Text='从左侧背包选择装备可查看完整属性；返回地面时系统会自动择优换装。'
}

function Update-Details {
    $target=$script:State.Target; $HeaderFunds.Text="资金  $(Format-Number ([double]$script:State.Funds))"; $HeaderSkill.Text="技能点  $($script:State.SkillPoints)"; $HeaderDepth.Text="最深  $($script:State.MaxDepth) 层"
    $MineDepth.Text=if($script:State.AtSurface){"地面营地 · 下次从第 $($script:State.Depth) 层出发"}else{"第 $($script:State.Depth) 层 · $($script:RarityNames[$target.Rarity])"}; $MineTarget.Text=if($script:State.AtSurface){'整备与结算'}else{$target.Name}; $MineTarget.Foreground=if($script:State.AtSurface){'#F3B84B'}else{$script:RarityColors[$target.Rarity]}; $MineHp.Text="$(Format-Number ([double]$target.Hp)) / $(Format-Number ([double]$target.MaxHp)) HP"; $MineHpBar.Value=Get-HpProgress $target
    $quick=Get-SkillDefinition 'quick_mark';$markThreshold=[math]::Max([int]$quick.Minimum,[int]$quick.Trigger-[math]::Floor((Get-SkillLevel 'quick_mark')/[double]$quick.Value)); $MineMechanics.Text="连击 $($script:State.Combo)/$($script:Balance.comboMaximum)  ·  弱点引爆 $($script:State.Weakness)/$markThreshold  ·  下个首次技能点 第 $(Get-NextSkillMilestone) 层"; Update-RunReportDisplays
    $AttackDamageText.Text=if($script:State.AtSurface){'地面整备中 · 挖矿已暂停'}else{"当前一击：键盘 $(Format-Number (Get-CurrentHitDamage 'keyboard'))  ·  鼠标 $(Format-Number (Get-CurrentHitDamage 'mouse'))  ·  自动 $(Format-Number (Get-CurrentHitDamage 'auto'))"}
    $funds=Get-ReturnFunds; $ratio=Get-ReturnRatio; $next=[math]::Max(1,[math]::Floor([int]$script:State.Depth*$ratio)); $ReturnPreview.Text=if($script:State.AtSurface){"资金和宠物已进入地面结算`n可孵化、升级或切换伙伴`n整备完成后继续下矿"}else{"本次可获得资金   $(Format-Number $funds)`n本次返回层数   $($script:State.Depth)`n当前回挖比例   $('{0:P1}' -f $ratio)`n下次起始层数   $next"}
    $ConfirmReturnButton.Visibility=if($script:State.AtSurface){'Collapsed'}else{'Visible'}; $DescendButton.Visibility=if($script:State.AtSurface){'Visible'}else{'Collapsed'}
    $treasure=Get-SkillDefinition 'treasure_instinct';$chestChance=[math]::Min([double]$script:Balance.chestChanceCap,[double]$script:Balance.chestBaseChance*(1+(Get-PetBonus 'chest'))+[double]$treasure.Value*(Get-SkillLevel 'treasure_instinct')+(Get-SetBonus 'chest')); $BuildInfo.Text="出战伙伴   $($script:State.ActivePet)`n镐子攻击加成   +$(Format-Number ([double]$script:Balance.pickaxeCoefficient*[double]$script:State.Equipment.pickaxe.Value))`n实际宝箱概率   $('{0:P1}' -f $chestChance)`n已激活套装   $(@($script:State.UnlockedSets).Count) 个"; $PanelPauseButton.Content=if($script:State.Paused){'继续挖矿'}else{'暂停挖矿'}
    Render-SkillTrees
    $price=Get-EggPrice; $EggInfo.Text="已收集 $($script:State.Pets.Count)/$($script:Pets.Count) · 当前价格 $(Format-Number $price) · 每次 ×$($script:Balance.eggPriceGrowth) · 非出战伙伴持续提供 $('{0:P0}'-f[double]$script:Balance.inactivePetPassiveRatio) 属性 · $(if($script:State.AtSurface){'可整备'}else{'返回地面后可整备'})"
    $HatchButton.IsEnabled=[bool]$script:State.AtSurface; $NextPetButton.IsEnabled=[bool]$script:State.AtSurface; $UpgradePetButton.IsEnabled=[bool]$script:State.AtSurface
    $activeLevel=[int]$script:State.Pets[$script:State.ActivePet];$upgradeCost=Get-PetUpgradePrice $activeLevel;$activePetDefinition=$script:Pets|Where-Object Name -eq $script:State.ActivePet|Select-Object -First 1;$PetUpgradeInfo.Text="当前：$(Get-PetEffectText $activePetDefinition $activeLevel)  →  下一级：$(Get-PetEffectText $activePetDefinition ($activeLevel+1))`n升级费用 $(Format-Number $upgradeCost)$(if(-not$script:State.AtSurface){'（返回地面后可升级）'})"
    $PetsList.Text=($script:Pets | ForEach-Object { if($script:State.Pets.Contains($_.Name)){$active=$_.Name-eq$script:State.ActivePet;$ratio=if($active){1.0}else{[double]$script:Balance.inactivePetPassiveRatio};$status=if($active){'[出战 · 100%]'}else{"[后台被动 · $('{0:P0}'-f$ratio)]"};"● $($_.Name)  Lv.$($script:State.Pets[$_.Name])  ·  $(Get-PetEffectText $_ ([int]$script:State.Pets[$_.Name]) $ratio)  $status"}else{"○ 未发现伙伴  ·  $($script:RarityNames[$_.Rarity])"} }) -join "`n"
    $EquippedList.Text=(@($script:Content.slots|ForEach-Object{$key=[string]$_.key;$i=$script:State.Equipment[$key];"$($_.label)  $($i.Set)·$($i.Name)  Lv.$($i.Level)  ·  $(Get-AffixText $i)"})-join"`n")
    Refresh-InventoryList
    $highest=$script:Rarities.IndexOf($script:State.Stats.Highest); $MineralCatalog.Text=($script:Rarities|ForEach-Object{if($script:Rarities.IndexOf($_)-le$highest){"◆ $($script:Minerals[$_])"}else{'◇ ???'}})-join'     '; $PetCatalog.Text=($script:Pets|ForEach-Object{if($script:State.Pets.Contains($_.Name)){$_.Name}else{'剪影'}})-join'  ·  '
    $allSets=@([string]$script:Content.starterSetName);foreach($rarity in $script:Rarities){$allSets+=@($script:EquipmentSetsByRarity[$rarity])}; $SetCatalog.Text=($allSets|ForEach-Object{$setName=$_;$slots=if($script:State.CatalogSets.Contains($setName)){@($script:State.CatalogSets[$setName])}else{@()};$effect=if($script:SetEffects.Contains($setName)){$script:SetEffects[$setName].Text}else{'该套装没有永久效果'};$state=if(@($script:State.UnlockedSets)-contains$setName){'已激活'}elseif($slots.Count-ge$script:Content.slots.Count-and-not$script:SetEffects.Contains($setName)){'已收集'}else{"$($slots.Count)/$($script:Content.slots.Count)"};"$setName  [$state]  ·  $effect"})-join"`n"
    $StatsText.Text="首次下矿   $($script:State.CreatedAt.Replace('T',' '))`n键盘匿名命中   $($script:State.Stats.Keyboard)`n鼠标匿名命中   $($script:State.Stats.Mouse)`n挂机自动攻击   $($script:State.Stats.Auto)`n累计清层   $($script:State.Stats.Layers)`n返回地面   $($script:State.Stats.Returns) 次`n开启宝箱   $($script:State.Stats.Chests)"
}

function Toggle-Pause { $script:State.Paused=-not [bool]$script:State.Paused; [DeepDesk.InputHooks]::Enabled=(-not $script:State.Paused -and -not $script:State.AtSurface); Save-State; Update-Overlay; Update-Details }
function Show-Details { Update-Details; $Details.Show(); [void]$Details.Activate() }
function Show-MineReport { Update-Details; $AdventureTabs.SelectedIndex=0; $Details.Show(); [void]$Details.Activate() }
$PanelPauseButton.Add_Click({Toggle-Pause})
$RunReportButton.Add_MouseLeftButtonUp({param($sender,$event)Show-MineReport;$event.Handled=$true})
$ConfirmReturnButton.Add_Click({$funds=Get-ReturnFunds;$ratio=Get-ReturnRatio;$next=[math]::Max(1,[math]::Floor([int]$script:State.Depth*$ratio));if(Show-GameDialog '呼叫地面升降梯' "本轮矿物将结算为 $(Format-Number $funds) 资金。`n下次从第 $next 层重新出发，并自动换上各部位属性最高的装备。" 'Confirm' '返回地面'){Return-ToSurface}})
$DescendButton.Add_Click({Start-Mining})
$ResetSkillsButton.Add_Click({$spent=0;foreach($node in $script:SkillNodes){$spent+=Get-SkillLevel $node.Id};if($spent-le0){return};if(Show-GameDialog '重绘技能星图' "将返还全部 $spent 点技能点，不消耗任何资金。你可以立即重新分配。" 'Confirm' '免费重置'){$refunded=Reset-Skills;Show-Toast "技能已重置 · 返还 $refunded 点" '#B77AFF';Update-Details}})
$HatchButton.Add_Click({if(-not(Require-Surface)){return};$price=Get-EggPrice;$remaining=@($script:Pets|Where-Object{-not$script:State.Pets.Contains($_.Name)});if(-not$remaining.Count){[void](Show-GameDialog '伙伴图鉴完成' '所有矿工伙伴都已经加入营地。' 'Info' '太棒了')}elseif([double]$script:State.Funds-lt$price){[void](Show-GameDialog '资金不足' "唤醒这枚宠物蛋需要 $(Format-Number $price) 资金。" 'Info' '继续挖矿')}else{$pet=Select-EggPet $remaining;$script:State.Funds=[double]$script:State.Funds-$price;$script:State.EggsBought=[int]$script:State.EggsBought+1;$script:State.Pets[$pet.Name]=1;Save-State;$passive=[double]$script:Balance.inactivePetPassiveRatio;[void](Show-GameDialog '新伙伴加入' "孵出了 $($pet.Name)！`n`n已进入后台并持续生效：`n$(Get-PetEffectText $pet 1 $passive)" 'Info' '欢迎加入');Update-Details}})
$NextPetButton.Add_Click({if(-not(Require-Surface)){return};$owned=@($script:Pets|Where-Object{$script:State.Pets.Contains($_.Name)});if($owned.Count-gt1){$index=($owned.Name).IndexOf($script:State.ActivePet);$script:State.ActivePet=$owned[($index+1)%$owned.Count].Name;Save-State;Update-Details}})
$UpgradePetButton.Add_Click({if(-not(Require-Surface)){return};$pet=$script:Pets|Where-Object Name -eq $script:State.ActivePet|Select-Object -First 1;$level=[int]$script:State.Pets[$pet.Name];$cost=Get-PetUpgradePrice $level;if([double]$script:State.Funds-ge$cost){$script:State.Funds=[double]$script:State.Funds-$cost;$script:State.Pets[$pet.Name]=$level+1;Save-State;Show-Toast "$($pet.Name) 升至 Lv.$($level+1) · $(Get-PetEffectText $pet ($level+1))" '#52C7B5';Update-Details}else{[void](Show-GameDialog '训练资金不足' "伙伴训练需要 $(Format-Number $cost) 资金。" 'Info' '继续挖矿')}})
$EquipmentFilter.Add_SelectionChanged({Refresh-InventoryList})
$InventoryListBox.Add_SelectionChanged({
    $index=$InventoryListBox.SelectedIndex
    if($index-lt0-or$index-ge@($script:VisibleInventory).Count){
        $SelectedItemDetails.Foreground=New-UiBrush '#9EB0AD';$SelectedItemDetails.Text='从左侧背包选择装备可查看完整属性；返回地面时系统会自动择优换装。'
        return
    }
    $item=$script:VisibleInventory[$index];$current=$script:State.Equipment[$item.Slot]
    $scale=if($item.Slot-eq'pickaxe'){[double]$script:Balance.pickaxeCoefficient}else{1.0};$delta=$scale*([double]$item.Value-[double]$current.Value)
    $comparison=if($delta-gt0){"比当前高 $(Format-Number $delta)"}elseif($delta-lt0){"比当前低 $(Format-Number ([math]::Abs($delta)))"}else{'与当前相同'}
    $setEffect=if($script:SetEffects.Contains($item.Set)){$script:SetEffects[$item.Set].Text}else{'该套装没有永久效果'}
    $setProgress=if($script:State.CatalogSets.Contains($item.Set)){@($script:State.CatalogSets[$item.Set]).Count}else{0};$setState=if(@($script:State.UnlockedSets)-contains$item.Set){'永久效果已激活'}else{"收集进度 $setProgress/$($script:Content.slots.Count)"}
    $SelectedItemDetails.Foreground=New-UiBrush $script:RarityColors[$item.Rarity]
    $SelectedItemDetails.Text="$($script:RarityNames[$item.Rarity]) · $($script:SlotLabels[$item.Slot])`n$($item.Set)·$($item.Name)`n装备等级：Lv.$($item.Level)`n属性：$(Get-AffixText $item)`n对比：$comparison`n套装：$setEffect`n状态：$setState`n换装：返回地面后自动选择最高属性"
})
$OpenSaveButton.Add_Click({Save-State;Start-Process explorer.exe -ArgumentList $script:SaveDir})
$StartupCheckBox.Add_Click({
    $requested = [bool]$StartupCheckBox.IsChecked
    try {
        Set-StartupRegistration $requested
        $script:State.StartupEnabled = $requested
        Save-State
        Show-Toast $(if($requested){'已开启开机自动启动'}else{'已关闭开机自动启动'}) '#59DCC8'
    } catch {
        $StartupCheckBox.IsChecked = [bool]$script:State.StartupEnabled
        [void](Show-GameDialog '启动项设置失败' "无法修改当前 Windows 用户的开机启动项。`n`n$($_.Exception.Message)" 'Info' '知道了')
    }
})
function Release-InstanceMutex {if($script:InstanceMutexOwned-and$script:InstanceMutex){try{$script:InstanceMutex.ReleaseMutex()}catch{};$script:InstanceMutexOwned=$false;$script:InstanceMutex.Dispose();$script:InstanceMutex=$null}}
function Exit-App {$script:Exiting=$true;[DeepDesk.InputHooks]::Stop();Save-State;$NotifyIcon.Visible=$false;$NotifyIcon.Dispose();$Details.Close();$Overlay.Close();Release-InstanceMutex;[System.Windows.Application]::Current.Shutdown()}
$ExitButton.Add_Click({Exit-App})

if(-not$SmokeTest){
    try { Set-StartupRegistration ([bool]$script:State.StartupEnabled) }
    catch {
        $script:State.StartupEnabled=$false;$StartupCheckBox.IsChecked=$false;Save-State
        [void](Show-GameDialog '开机启动未能开启' "Windows 拒绝写入当前用户的启动项，本次已保持关闭。`n`n$($_.Exception.Message)" 'Info' '知道了')
    }
}

$NotifyIcon=[System.Windows.Forms.NotifyIcon]::new();$NotifyIcon.Icon=[System.Drawing.SystemIcons]::Application;$NotifyIcon.Text='桌宠矿工 · Project Deep Desk';$NotifyIcon.Visible=$true
$menu=[System.Windows.Forms.ContextMenuStrip]::new();$showItem=$menu.Items.Add('显示桌宠');$detailItem=$menu.Items.Add('打开详情');$pauseItem=$menu.Items.Add('暂停/继续');[void]$menu.Items.Add('-');$exitItem=$menu.Items.Add('退出')
$showItem.Add_Click({$Overlay.Show();Update-OverlayResponsiveLayout -Persist;$Overlay.Activate();[DeepDesk.WindowStyles]::SetClickThrough($script:OverlayHwnd,$true)});$detailItem.Add_Click({Show-Details});$pauseItem.Add_Click({Toggle-Pause});$exitItem.Add_Click({Exit-App});$NotifyIcon.ContextMenuStrip=$menu;$NotifyIcon.Add_DoubleClick({Show-Details})

function Update-OverlayInteraction([datetime]$Now,$CursorPosition) {
    if(-not$Overlay.IsVisible-or-not$script:OverlayPlacementReady){return}
    if($null-eq$CursorPosition){$CursorPosition=[System.Windows.Forms.Cursor]::Position}
    try{
        $windowPoint=$Overlay.PointFromScreen([System.Windows.Point]::new([double]$CursorPosition.X,[double]$CursorPosition.Y))
        $localX=[double]$windowPoint.X/[double]$script:OverlayScale
        $localY=[double]$windowPoint.Y/[double]$script:OverlayScale
    }catch{
        $dpi=Get-OverlayDpiScale
        $localX=(([double]$CursorPosition.X/[double]$dpi.X)-[double]$Overlay.Left)/[double]$script:OverlayScale
        $localY=(([double]$CursorPosition.Y/[double]$dpi.Y)-[double]$Overlay.Top)/[double]$script:OverlayScale
    }
    $overHamster=$localX-ge15-and$localX-le220-and$localY-ge73-and$localY-le278
    $overReport=$localX-ge18-and$localX-le212-and$localY-ge242-and$localY-le292
    if($overHamster-or$overReport-or$null-ne$script:OverlayGestureStart){[DeepDesk.WindowStyles]::SetClickThrough($script:OverlayHwnd,$false)}else{[DeepDesk.WindowStyles]::SetClickThrough($script:OverlayHwnd,$true)}
}

function Update-LiveDetails([datetime]$Now) {
    if(-not$Details.IsVisible-or($Now-$script:LastLiveRefresh).TotalMilliseconds-lt500){return}
    $target=$script:State.Target
    $HeaderFunds.Text="资金  $(Format-Number ([double]$script:State.Funds))";$HeaderSkill.Text="技能点  $($script:State.SkillPoints)";$HeaderDepth.Text="最深  $($script:State.MaxDepth) 层"
    $MineDepth.Text=if($script:State.AtSurface){"地面营地 · 下次从第 $($script:State.Depth) 层出发"}else{"第 $($script:State.Depth) 层 · $($script:RarityNames[$target.Rarity])"};$MineTarget.Text=if($script:State.AtSurface){'整备与结算'}else{$target.Name};$MineTarget.Foreground=if($script:State.AtSurface){'#F3B84B'}else{$script:RarityColors[$target.Rarity]}
    $MineHp.Text="$(Format-Number ([double]$target.Hp)) / $(Format-Number ([double]$target.MaxHp)) HP"
    $MineHpBar.Value=Get-HpProgress $target
    $quick=Get-SkillDefinition 'quick_mark'
    $markThreshold=[math]::Max([int]$quick.Minimum,[int]$quick.Trigger-[math]::Floor((Get-SkillLevel 'quick_mark')/[double]$quick.Value))
    $MineMechanics.Text="连击 $($script:State.Combo)/$($script:Balance.comboMaximum)  ·  弱点引爆 $($script:State.Weakness)/$markThreshold  ·  下个首次技能点 第 $(Get-NextSkillMilestone) 层"
    $AttackDamageText.Text=if($script:State.AtSurface){'地面整备中 · 挖矿已暂停'}else{"当前一击：键盘 $(Format-Number (Get-CurrentHitDamage 'keyboard'))  ·  鼠标 $(Format-Number (Get-CurrentHitDamage 'mouse'))  ·  自动 $(Format-Number (Get-CurrentHitDamage 'auto'))"}
    Update-RunReportDisplays
    $funds=Get-ReturnFunds;$ratio=Get-ReturnRatio;$next=[math]::Max(1,[math]::Floor([int]$script:State.Depth*$ratio));$ReturnPreview.Text=if($script:State.AtSurface){"资金和宠物已进入地面结算`n可孵化、升级或切换伙伴`n整备完成后继续下矿"}else{"本次可获得资金   $(Format-Number $funds)`n本次返回层数   $($script:State.Depth)`n当前回挖比例   $('{0:P1}' -f $ratio)`n下次起始层数   $next"}
    $script:LastLiveRefresh=$Now
}

function Invoke-RuntimeTick([datetime]$Now,$CursorPosition=$null) {
    $script:RuntimeStage='INPUT'
    $kind='';$processed=0
    while($processed-lt300-and[DeepDesk.InputHooks]::Hits.TryDequeue([ref]$kind)){Invoke-Hit $kind;$processed++}
    $script:RuntimeStage='AUTO'
    $idle=($Now-$script:LastInput).TotalSeconds
    if(-not$script:State.Paused-and-not$script:State.AtSurface-and$idle-ge[double]$script:Balance.idleTriggerSeconds){$interval=Get-AutoInterval;if(($Now-$script:LastAuto).TotalSeconds-ge$interval){Invoke-AutoHit;$script:LastAuto=$Now}}else{$script:LastAuto=$Now}
    if($idle-gt2.5-and[int]$script:State.Combo-gt0){$script:State.Combo=[math]::Max(0,[int]$script:State.Combo-1)}
    $script:RuntimeStage='LAYOUT'
    if($script:OverlayPlacementReady-and($Now-$script:LastOverlayLayoutCheck).TotalSeconds-ge1){
        try{Update-OverlayResponsiveLayout -Persist}catch{}finally{$script:LastOverlayLayoutCheck=$Now}
    }
    $script:RuntimeStage='POINTER'
    Update-OverlayInteraction $Now $CursorPosition
    $script:RuntimeStage='DETAILS'
    Update-LiveDetails $Now
    $script:RuntimeStage='SAVE'
    if(($Now-$script:LastSave).TotalSeconds-ge[double]$script:Balance.autosaveSeconds){try{Save-State}catch{$script:LastSave=$Now;throw}}
    $script:RuntimeStage='OVERLAY'
    Update-Overlay
    $script:RuntimeStage='READY'
    $script:RuntimeFaultStreak=0
    $script:LastRuntimeFaultStage=''
}

function Write-RuntimeFault($ErrorRecord,[string]$Stage) {
    try {
        New-Item -ItemType Directory -Force -Path $script:SaveDir | Out-Null
        $message="[$([datetime]::Now.ToString('s'))][$Stage] $($ErrorRecord|Out-String)`r`n$($ErrorRecord.ScriptStackTrace)`r`n"
        [System.IO.File]::AppendAllText((Join-Path $script:SaveDir 'error.log'),$message,[System.Text.UTF8Encoding]::new($false))
    } catch { }
}

function Handle-RuntimeFault($ErrorRecord) {
    $stage=[string]$script:RuntimeStage
    Write-RuntimeFault $ErrorRecord $stage
    $now=[datetime]::UtcNow
    if($stage-eq'SAVE'){
        if(($now-$script:LastRuntimeFaultToast).TotalSeconds-ge5){Show-Toast '存档暂时写入失败，挖矿仍在继续 [SAVE]' '#FF9F43';$script:LastRuntimeFaultToast=$now}
        return
    }
    if($script:LastRuntimeFaultStage-eq$stage){$script:RuntimeFaultStreak++}else{$script:RuntimeFaultStreak=1;$script:LastRuntimeFaultStage=$stage}
    if($script:RuntimeFaultStreak-ge3){
        $script:State.Paused=$true
        [DeepDesk.InputHooks]::Enabled=$false
        Show-Toast "运行阶段连续异常，已暂停 [$stage]" '#FF5E6A'
    }elseif(($now-$script:LastRuntimeFaultToast).TotalSeconds-ge5){
        Show-Toast "短暂异常已自动恢复 [$stage]" '#FF9F43'
        $script:LastRuntimeFaultToast=$now
    }
}

$timer=[System.Windows.Threading.DispatcherTimer]::new();$timer.Interval=[timespan]::FromMilliseconds(50)
$timer.Add_Tick({try{Invoke-RuntimeTick ([datetime]::UtcNow)}catch{Handle-RuntimeFault $_}})

Update-Overlay;Update-Details
if($SmokeTest){
  $Overlay.Show();$Details.Show();$script:State.Paused=$false;$script:State.AtSurface=$false
  Update-OverlayResponsiveLayout -Persist;$layoutBounds=[DeepDesk.WindowStyles]::GetBounds($script:OverlayHwnd);$layoutWork=[DeepDesk.WindowStyles]::GetWorkArea($script:OverlayHwnd)
  if($script:OverlayScale-lt.62-or$script:OverlayScale-gt1.0){throw '桌宠分辨率自适应比例失败'}
  if((Get-ResponsiveOverlayScaleForSize 2880 1800)-ne1.0-or(Get-ResponsiveOverlayScaleForSize 1920 1080)-ne.864-or(Get-ResponsiveOverlayScaleForSize 1440 900)-ne.655-or(Get-ResponsiveOverlayScaleForSize 1280 720)-ne.62){throw '常见分辨率桌宠缩放回归失败'}
  if($layoutBounds.Left-lt$layoutWork.Left-or$layoutBounds.Top-lt$layoutWork.Top-or$layoutBounds.Right-gt$layoutWork.Right-or$layoutBounds.Bottom-gt$layoutWork.Bottom){throw '桌宠初始位置超出屏幕工作区'}
  $Overlay.Left=[double]$Overlay.Left+100000;$Overlay.Top=[double]$Overlay.Top+100000;Update-OverlayResponsiveLayout -Persist;$layoutBounds=[DeepDesk.WindowStyles]::GetBounds($script:OverlayHwnd);$layoutWork=[DeepDesk.WindowStyles]::GetWorkArea($script:OverlayHwnd)
  if($layoutBounds.Left-lt$layoutWork.Left-or$layoutBounds.Top-lt$layoutWork.Top-or$layoutBounds.Right-gt$layoutWork.Right-or$layoutBounds.Bottom-gt$layoutWork.Bottom){throw '桌宠越界位置自动纠正失败'}
  $savedLargeTarget=$script:State.Target;$largeHp=[double][int]::MaxValue+100000000.25;$script:State.Target=[ordered]@{Kind='ore';Rarity='purple';Name='Int32 边界回归矿';MaxHp=$largeHp;Hp=$largeHp};Invoke-Damage 1.25 'keyboard';$expectedLargeHp=$largeHp-1.25;if([math]::Abs([double]$script:State.Target.Hp-$expectedLargeHp)-gt.001){throw '超过 Int32 上限后的扣血失败'};$script:State.Target=$savedLargeTarget
  $runtimeProbe=[datetime]::UtcNow;$insideScreen=$Overlay.PointToScreen([System.Windows.Point]::new(40*$script:OverlayScale,100*$script:OverlayScale));$insidePoint=[System.Drawing.Point]::new([int]$insideScreen.X,[int]$insideScreen.Y);Invoke-RuntimeTick $runtimeProbe $insidePoint
  $outsideScreen=$Overlay.PointToScreen([System.Windows.Point]::new(365*$script:OverlayScale,290*$script:OverlayScale));$outsidePoint=[System.Drawing.Point]::new([int]$outsideScreen.X,[int]$outsideScreen.Y);Invoke-RuntimeTick $runtimeProbe.AddMilliseconds(1) $outsidePoint;if($Overlay.FindName('Toolbar')){throw '桌宠悬浮工具条未移除'};if($TargetVisual.Cursor-ne[System.Windows.Input.Cursors]::Arrow-or$Hamster.Cursor-ne[System.Windows.Input.Cursors]::Hand){throw '仓鼠独占直接拖动区域失败'}
  if(-not[bool]$script:State.StartupEnabled-or-not[bool]$StartupCheckBox.IsChecked){throw '开机自启动默认状态失败'}
  $savedDepthLabel=[int]$script:State.Depth;$script:State.Depth=123;Update-Overlay;if($FloorText.Text-ne'第 123 层'){throw '桌宠楼层中文显示失败'};$script:State.Depth=$savedDepthLabel;Update-Overlay
  $script:LastSave=$runtimeProbe.AddSeconds((-1*[double]$script:Balance.autosaveSeconds)-1);Invoke-RuntimeTick $runtimeProbe.AddMilliseconds(2) $outsidePoint;if($script:RuntimeStage-ne'READY'-or$script:State.Paused){throw '计时循环与自动存档恢复失败'}
  $queuedKeyboard=[int]$script:State.Stats.Keyboard;$queuedMouse=[int]$script:State.Stats.Mouse;[DeepDesk.InputHooks]::Hits.Enqueue('keyboard');[DeepDesk.InputHooks]::Hits.Enqueue('mouse');Invoke-RuntimeTick $runtimeProbe.AddMilliseconds(60) $outsidePoint;if([int]$script:State.Stats.Keyboard-ne$queuedKeyboard+1-or[int]$script:State.Stats.Mouse-ne$queuedMouse+1){throw '系统输入队列恢复路径失败'}
  $script:State.Paused=$true;$script:LastInput=$runtimeProbe.AddSeconds(-20);$script:LastAuto=$runtimeProbe.AddSeconds(-20);Toggle-Pause;$autoBefore=[int]$script:State.Stats.Auto;Invoke-RuntimeTick $runtimeProbe.AddMilliseconds(620) $outsidePoint;if([int]$script:State.Stats.Auto-le$autoBefore-or$script:RuntimeStage-ne'READY'){throw '暂停恢复后 0.5 秒挂机路径失败'}
  if($script:Pets.Count-ne18){throw '宠物数量回归失败'}
  $dropSets=@();foreach($rarity in $script:Rarities){$dropSets+=@($script:EquipmentSetsByRarity[$rarity])};if($dropSets.Count-ne11-or@($dropSets|Select-Object -Unique).Count-ne11){throw '新增装备套装池失败'}
  foreach($newSet in @('粉尘行者','潮汐钻探队','秘银时术师','森灵工程团','日冕收藏家','深渊破界者')){if(-not$script:SetEffects.Contains($newSet)){throw "套装效果未接入：$newSet"}}
  if($script:SkillNodes.Count-ne15){throw '技能树节点数量失败'}
  if($script:TargetImages.Count-ne10){throw '矿物与宝箱贴图加载失败'}
  if($EquipmentFilter.Items.Count-ne10){throw '装备分类加载失败'}
  if([System.Windows.Controls.Canvas]::GetLeft($Hamster)-ge[System.Windows.Controls.Canvas]::GetLeft($TargetVisual)){throw '桌宠与矿物顺序回归失败'}
  if([math]::Abs((Get-BaseDamage)-(1+[double]$script:Balance.pickaxeCoefficient*[double]$script:State.Equipment.pickaxe.Value))-gt.0001){throw '镐子 20% 系数失败'}
  if((Get-PetTrigger 'ink')-ne50-or(Get-PetTrigger 'phoenix')-ne100-or(Get-PetTrigger 'whale')-ne60){throw '宠物触发周期配置失败'}
  $beforeKeyboardHit=[int]$script:State.Stats.Keyboard;$beforeMouseHit=[int]$script:State.Stats.Mouse;$beforeFloatCount=$script:DamageFloats.Count;Invoke-Hit 'keyboard';Invoke-Hit 'mouse';if([int]$script:State.Stats.Keyboard-ne$beforeKeyboardHit+1-or[int]$script:State.Stats.Mouse-ne$beforeMouseHit+1){throw '真实键盘鼠标命中路径失败'};if($script:DamageFloats.Count-lt$beforeFloatCount+2){throw '每次命中独立漂浮字失败'}
  foreach($rarity in $script:Rarities){Add-DamageFloat 1 $rarity;$actual=$script:DamageFloats[$script:DamageFloats.Count-1].Control.Foreground.ToString();$expected=(New-UiBrush $script:RarityColors[$rarity]).ToString();if($actual-ne$expected){throw "扣血字品质颜色失败：$rarity"}}
  $savedPoints=[int]$script:State.SkillPoints;$savedLevels=@{};foreach($node in $script:SkillNodes){$savedLevels[$node.Id]=Get-SkillLevel $node.Id;$script:State.Skills[$node.Id]=0};$script:State.SkillPoints=5
  for($i=0;$i-lt3;$i++){if(-not(Buy-Skill 'trained_tap')){throw '技能树投入失败'}}
  if(-not(Test-SkillUnlocked 'hot_hands')-or-not(Buy-Skill 'hot_hands')){throw '技能树层级解锁失败'}
  if((Reset-Skills)-ne4-or[int]$script:State.SkillPoints-ne5){throw '免费重置技能点失败'}
  foreach($node in $script:SkillNodes){$script:State.Skills[$node.Id]=$savedLevels[$node.Id]};$script:State.SkillPoints=$savedPoints
  $originalPet=$script:State.ActivePet
  foreach($pet in $script:Pets){$script:State.Pets[$pet.Name]=1;$script:State.ActivePet=$pet.Name;if((Get-PetBonus $pet.Kind)-le0){throw "宠物被动未接入：$($pet.Name)"}}
  if([math]::Abs([double]$script:Balance.inactivePetPassiveRatio-.10)-gt.0001){throw '非出战宠物被动系数配置失败'}
  $fundPets=@($script:Pets|Where-Object Kind -eq 'funds');$script:State.ActivePet='石团鼠';$inactiveExpected=0.0;foreach($pet in $fundPets){$inactiveExpected+=(Get-PetScaledBonus $pet 1)*[double]$script:Balance.inactivePetPassiveRatio};if([math]::Abs((Get-PetBonus 'funds')-$inactiveExpected)-gt.0001){throw '所有非出战宠物 10% 被动叠加失败'}
  $script:State.ActivePet='灯泡虫';$activeExpected=(Get-PetScaledBonus $fundPets[0] 1)+(Get-PetScaledBonus $fundPets[1] 1)*[double]$script:Balance.inactivePetPassiveRatio;if([math]::Abs((Get-PetBonus 'funds')-$activeExpected)-gt.0001){throw '出战 100% 与后台 10% 组合失败'}
  $effectPet=$script:Pets[0];$script:State.Pets[$effectPet.Name]=1;$effectLevel1=Get-PetScaledBonus $effectPet 1;$effectText1=Get-PetEffectText $effectPet 1;$script:State.Pets[$effectPet.Name]=2;$effectLevel2=Get-PetScaledBonus $effectPet 2;$effectText2=Get-PetEffectText $effectPet 2;if($effectLevel2-le$effectLevel1-or$effectText2-eq$effectText1){throw '宠物升级效果未动态增长'};$script:State.Pets[$effectPet.Name]=1
  $script:State.ActivePet=$originalPet
  $savedEggs=[int]$script:State.EggsBought;$script:State.EggsBought=0;$egg0=Get-EggPrice;$script:State.EggsBought=1;$egg1=Get-EggPrice;$script:State.EggsBought=$savedEggs;if($egg0-ne[double]$script:Balance.eggBasePrice-or$egg1-ne[math]::Ceiling([double]$script:Balance.eggBasePrice*[double]$script:Balance.eggPriceGrowth)){throw '孵化价格曲线失败'}
  for($i=0;$i-lt180;$i++){Invoke-Damage ((Get-BaseDamage)*1.05) 'keyboard'}
  Update-Overlay;if($ImpactLayer.Visibility-ne'Visible'-or$HamsterRotate.Angle-eq0){throw '挖矿打击动画失败'}
  $beforeSkill=[int]$script:State.SkillPoints;$script:State.HighestSkillMilestone=0;$script:State.Depth=69;$script:State.MaxDepth=69;$script:State.Target=New-Target 69;$script:State.Target.Hp=.1;Invoke-Damage 1 'keyboard'
  if([int]$script:State.SkillPoints-ne$beforeSkill+1-or[int]$script:State.HighestSkillMilestone-ne70){throw '首次抵达 70 层技能点即时结算失败'}
  $script:State.Depth=69;$script:State.Target=New-Target 69;$script:State.Target.Hp=.1;Invoke-Damage 1 'keyboard'
  if([int]$script:State.SkillPoints-ne$beforeSkill+1){throw '回挖 70 层重复发放技能点'}
  $script:State.Depth=139;$script:State.MaxDepth=139;$script:State.Target=New-Target 139;$script:State.Target.Hp=.1;Invoke-Damage 1 'keyboard'
  if([int]$script:State.SkillPoints-ne$beforeSkill+2-or[int]$script:State.HighestSkillMilestone-ne140){throw '首次抵达 140 层技能点结算失败'}
  $expectedSkillAfterMilestones=$beforeSkill+2
  $tries=0;while(@($script:State.UnlockedSets)-notcontains'星银咏唱者'-and$tries-lt80){[void](Add-Equipment 'purple' ([int]$script:State.Depth));$tries++}
  if(@($script:State.UnlockedSets)-notcontains'星银咏唱者'){throw '套装永久效果解锁失败'}
  if((Get-SetBonus 'damage')-lt.119){throw '套装效果未参与数值结算'}
  Update-Details
  if(-not$RunReportButton-or-not$AdventureTabs){throw '桌宠战报入口或冒险手册分页未加载'}
  $script:State.Warehouse.white=[int]$script:State.Warehouse.white+7;$script:State.RunEquipmentCount=3;Update-Overlay;$expectedRunValue=Format-Number (Get-WarehouseValue)
  if($WarehouseText.Text-ne"已获得矿物价值：$expectedRunValue 金币`n已获得装备：3 件"-or$MineWarehouseValue.Text-ne"已获得矿物价值：$expectedRunValue 金币"-or$MineWarehouse.Text-ne'已获得装备：3 件'){throw '桌宠与矿井战报实时同步失败'}
  $AdventureTabs.SelectedIndex=3;Show-MineReport;if($AdventureTabs.SelectedIndex-ne0-or-not$Details.IsVisible){throw '桌宠战报跳转矿井战报页失败'}
  if($KeyboardTreePanel.Children.Count-lt10-or$IdleTreePanel.Children.Count-lt10-or$MouseTreePanel.Children.Count-lt10){throw '技能树界面渲染失败'}
  if($KeyboardTreePanel.Children[1].Child.Children[0].Text-notlike'第 1 层*'-or$KeyboardTreePanel.Children[9].Child.Children[0].Text-notlike'第 5 层*'){throw '技能树正序展示失败'}
  if($UpgradePetButton.Visibility-ne'Visible'-or[string]::IsNullOrWhiteSpace($PetUpgradeInfo.Text)){throw '宠物升级入口显示失败'}
  if($Details.FindName('EquipSelectedButton')){throw '手动装备按钮未移除'}
  if($EquipmentFilter.Foreground.ToString()-ne'#FF111A1D'){throw '装备筛选字体颜色失败'}
  if($InventoryListBox.Items.Count-lt1){throw '装备背包显示失败'}
  $EquipmentFilter.SelectedIndex=7;Refresh-InventoryList;if(@($script:VisibleInventory|Where-Object Rarity -ne 'purple').Count-gt0){throw '装备品质分类失败'};$EquipmentFilter.SelectedIndex=0;Refresh-InventoryList
  for($i=0;$i-lt$script:VisibleInventory.Count;$i++){$row=$InventoryListBox.Items[$i];$item=$script:VisibleInventory[$i];if($row -isnot [System.Windows.Controls.ListBoxItem]){throw '装备品质彩色行类型失败'};$actual=$row.Foreground.ToString();$expected=(New-UiBrush $script:RarityColors[$item.Rarity]).ToString();if($actual-ne$expected){throw "装备字体品质颜色失败：$($item.Rarity)"}}
  $InventoryListBox.SelectedIndex=0
  if($SelectedItemDetails.Text-notlike'*属性：*'-or$SelectedItemDetails.Text-notlike'*返回地面后自动*'){throw '装备属性与自动换装提示失败'};if($SelectedItemDetails.Foreground.ToString() -ne (New-UiBrush $script:RarityColors[$script:VisibleInventory[0].Rarity]).ToString()){throw '装备详情品质颜色失败'}
  if($Details.FindName('SellSelectedButton')){throw '装备卖出入口未移除'}
  $candidate=@($script:State.Inventory)[0];$script:State.Equipment[$candidate.Slot]=$candidate
  if((Get-AffixText $candidate).Length-lt3){throw '装备属性显示失败'}
  if((Get-CurrentHitDamage 'keyboard')-le0){throw '当前攻击力计算失败'}
  $autoCandidate=[ordered]@{Slot='pickaxe';Name='回归测试镐';Set='自动换装测试';Rarity='red';Level=999;Value=([double]$script:State.Equipment.pickaxe.Value+999);Depth=999};$script:State.Inventory=@($script:State.Inventory)+@($autoCandidate);if($script:State.Equipment.pickaxe.Set-eq'自动换装测试'){throw '装备在上岸前被提前穿戴'}
  $script:State.Warehouse.white=[int]$script:State.Warehouse.white+10;$beforeFunds=[double]$script:State.Funds;Return-ToSurface
  if(-not$script:State.AtSurface-or[double]$script:State.Funds-le$beforeFunds){throw '地面资金结算失败'}
  if([int]$script:State.RunEquipmentCount-ne0-or$MineWarehouse.Text-ne'已获得装备：0 件'){throw '返回地面后本轮装备计数未归零'}
  if($script:State.Equipment.pickaxe.Set-ne'自动换装测试'){throw '返回地面自动择优换装失败'}
  if(-not$HatchButton.IsEnabled){throw '地面宠物结算入口失败'}
  $beforePetLevel=[int]$script:State.Pets[$script:State.ActivePet];$beforeUpgradeInfo=$PetUpgradeInfo.Text;$upgradeCost=Get-PetUpgradePrice $beforePetLevel;$script:State.Funds=[double]$script:State.Funds+$upgradeCost;$UpgradePetButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent));if([int]$script:State.Pets[$script:State.ActivePet]-ne$beforePetLevel+1-or$PetUpgradeInfo.Text-eq$beforeUpgradeInfo){throw '宠物升级按钮与效果刷新失败'}
  $beforeHp=[double]$script:State.Target.Hp;Invoke-Damage 999 'keyboard';if([double]$script:State.Target.Hp-ne$beforeHp){throw '地面停挖边界失败'}
  Start-Mining;if($HatchButton.IsEnabled){throw '矿井中宠物入口未关闭'};Update-Overlay;Update-Details;Save-State;Save-State
  $script:State.Depth=490;$script:State.MaxDepth=490;$script:State.RunStartDepth=490;$script:State.Target=New-Target 490;$script:State.AtSurface=$false;$script:State.Paused=$false
  $depthProbeNow=[datetime]::UtcNow;for($expectedDepth=490;$expectedDepth-lt621;$expectedDepth++){$hp=[double]$script:State.Target.Hp;if([double]::IsNaN($hp)-or[double]::IsInfinity($hp)){throw "深层生命值无效：$expectedDepth"};Invoke-Damage ($hp+1) 'keyboard';Invoke-RuntimeTick ($depthProbeNow.AddMilliseconds(55*($expectedDepth-489))) $outsidePoint;if([int]$script:State.Depth-ne$expectedDepth+1){throw "深层跨层失败：$expectedDepth"}}
  if([int]$script:State.Depth-ne621-or$script:RuntimeStage-ne'READY'){throw '490 至 620 层持续运行失败'}
  $bulkInventory=@($script:State.Inventory);for($i=1;$i-le750;$i++){$rarity=$script:Rarities[$i%$script:Rarities.Count];$bulkInventory+=@([ordered]@{Slot='pickaxe';Name="压力测试镐$i";Set='背包压力测试';Rarity=$rarity;Level=500+$i;Value=1000000.0+$i;Depth=500})};$script:State.Inventory=$bulkInventory
  Update-Details;if($script:VisibleInventory.Count-lt750-or$InventoryListBox.Items.Count-lt750){throw '大容量装备背包刷新失败'};Save-State
  $saved=Get-Content -LiteralPath $script:SavePath -Raw -Encoding UTF8|ConvertFrom-Json;if([int]$saved.SkillPoints-lt$expectedSkillAfterMilestones-or[int]$saved.HighestSkillMilestone-lt140){throw '首次里程碑技能点即时保存失败'}
  $script:Exiting=$true;$Details.Close();$Overlay.Close();$NotifyIcon.Dispose();Release-InstanceMutex;Write-Output 'SMOKE_OK';exit 0
}
[DeepDesk.InputHooks]::Enabled=(-not$script:State.Paused -and -not$script:State.AtSurface);[DeepDesk.InputHooks]::Start();$timer.Start();$Overlay.Show()
if(-not$script:State.OnboardingSeen){$script:State.OnboardingSeen=$true;Save-State;Show-Details;[void](Show-GameDialog '欢迎来到桌宠矿工' "矿工仓鼠只统计匿名的键盘和鼠标按下次数。`n`n不会读取或保存字符、键码、文字、鼠标坐标、前台应用、剪贴板或屏幕内容。暂停后会立刻停止计数。`n`n按住仓鼠即可直接拖动位置；冒险手册可从桌宠战报或系统通知区域打开。" 'Info' '开始挖矿')}
$app=[System.Windows.Application]::new();$app.ShutdownMode='OnExplicitShutdown';try{[void]$app.Run()}finally{[DeepDesk.InputHooks]::Stop();if($NotifyIcon){$NotifyIcon.Visible=$false;$NotifyIcon.Dispose()};Release-InstanceMutex}
