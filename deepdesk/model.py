from __future__ import annotations

import copy
import json
import math
import os
import random
import shutil
import time
import uuid
from dataclasses import dataclass, asdict
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Callable


RARITIES = ("white", "blue", "purple", "gold", "red")
RARITY_LABEL = {
    "white": "普通",
    "blue": "稀有",
    "purple": "史诗",
    "gold": "传说",
    "red": "神话",
}
RARITY_COLOR = {
    "white": "#DCE5E4",
    "blue": "#56A8FF",
    "purple": "#B77AFF",
    "gold": "#F8C95C",
    "red": "#FF5E6A",
}
RARITY_COEFFICIENT = {
    "white": 1.0,
    "blue": 1.35,
    "purple": 1.9,
    "gold": 2.8,
    "red": 4.2,
}
INACTIVE_PET_PASSIVE_RATIO = 0.10
SKILL_POINT_INTERVAL = 70
MINERALS = {
    "white": ("铁矿", 1),
    "blue": ("蓝晶", 4),
    "purple": ("星银", 15),
    "gold": ("太阳金", 80),
    "red": ("虚空钻", 500),
}
ORE_HP_MULTIPLIER = {
    "white": 1.0,
    "blue": 2.0,
    "purple": 4.0,
    "gold": 8.0,
    "red": 20.0,
}
ORE_AMOUNT_MULTIPLIER = {
    "white": 1.0,
    "blue": 1.25,
    "purple": 1.6,
    "gold": 2.0,
    "red": 2.5,
}
CHEST_HP_MULTIPLIER = {
    "white": 0.8,
    "blue": 1.5,
    "purple": 4.0,
    "gold": 10.0,
    "red": 25.0,
}
CHEST_LABEL = {
    "white": "木箱",
    "blue": "铁箱",
    "purple": "水晶箱",
    "gold": "黄金箱",
    "red": "星核箱",
}
SLOTS = ("head", "pickaxe", "clothing", "shoes")
SLOT_LABEL = {"head": "头部", "pickaxe": "镐子", "clothing": "衣服", "shoes": "鞋子"}
STARTER_NAMES = {
    "head": "软布帽",
    "pickaxe": "木柄镐",
    "clothing": "帆布工装",
    "shoes": "防滑布靴",
}
SET_NAMES = {
    "white": ("新手矿工", "岩层学徒", "井下搬运工", "煤灯巡检员", "旧镇掘进队", "浅层拾荒者"),
    "blue": ("蓝晶技师", "蒸汽钻探者", "洞穴测绘员", "萤火勘探队", "潮汐矿工", "冰层破岩者"),
    "purple": ("星银咏唱者", "地底自动师", "裂隙猎手", "暗夜宝藏家", "蘑菇炼金师", "雷纹速记员"),
    "gold": ("永昼钟匠", "星轨鹰眼", "黄金勘探家", "森灵寻脉师", "王室宝藏猎手", "深海回声王"),
    "red": ("虚空键圣", "永恒机神", "绯红鹰眼", "天穹钻冕", "三相创世", "地心守望者"),
}
SLOT_ITEM_NAMES = {
    "head": ("矿帽", "目镜", "冠冕", "兜帽"),
    "pickaxe": ("掘进镐", "裂岩镐", "钻星镐", "共鸣镐"),
    "clothing": ("工装", "披风", "长衣", "护甲"),
    "shoes": ("矿靴", "足具", "履带靴", "踏岩靴"),
}


PETS: tuple[dict[str, Any], ...] = (
    {"id": "rock_mouse", "rarity": "white", "name": "石团鼠", "effect": "全伤害 +5%", "kind": "all_damage", "base": 0.05},
    {"id": "backpack_turtle", "rarity": "white", "name": "背包龟", "effect": "矿物数量 +4%", "kind": "yield", "base": 0.04},
    {"id": "bulb_bug", "rarity": "white", "name": "灯泡虫", "effect": "返回资金 +4%", "kind": "funds", "base": 0.04},
    {"id": "typing_bird", "rarity": "blue", "name": "打字雀", "effect": "键盘伤害 +8%", "kind": "keyboard_damage", "base": 0.08},
    {"id": "gear_mole", "rarity": "blue", "name": "齿轮鼹", "effect": "挂机伤害 +10%", "kind": "auto_damage", "base": 0.10},
    {"id": "treasure_dog", "rarity": "blue", "name": "寻宝犬", "effect": "宝箱率 ×1.10", "kind": "chest", "base": 0.10},
    {"id": "ink_octopus", "rarity": "purple", "name": "墨水章鱼", "effect": "每50次键盘命中追加墨迹打击", "kind": "ink", "base": 1.00},
    {"id": "moon_rabbit", "rarity": "purple", "name": "月眠兔", "effect": "挂机间隔缩短 8%", "kind": "auto_speed", "base": 0.08},
    {"id": "crosshair_falcon", "rarity": "purple", "name": "准星隼", "effect": "弱点引爆 +12%", "kind": "weakness", "base": 0.12},
    {"id": "gold_slime", "rarity": "gold", "name": "黄金史莱姆", "effect": "全部矿物回收价 +5%", "kind": "funds", "base": 0.05},
    {"id": "crystal_dragon", "rarity": "gold", "name": "水晶龙仔", "effect": "蓝色以上矿量 +15%", "kind": "rare_yield", "base": 0.15},
    {"id": "clock_cat", "rarity": "gold", "name": "时钟猫", "effect": "回挖全伤害 +18%", "kind": "rewind_damage", "base": 0.18},
    {"id": "keyboard_phoenix", "rarity": "red", "name": "万键凤凰", "effect": "每100次键盘命中发动凤凰打击", "kind": "phoenix", "base": 10.0},
    {"id": "perpetual_whale", "rarity": "red", "name": "永动鲸", "effect": "每60秒挂机发动鲸落", "kind": "whale", "base": 20.0},
    {"id": "fate_fox", "rarity": "red", "name": "命运九尾", "effect": "装备有概率提升品质", "kind": "gear_luck", "base": 0.03},
    {"id": "magnet_hedgehog", "rarity": "blue", "name": "磁石刺猬", "effect": "宝箱装备属性 +8%", "kind": "gear_power", "base": 0.08},
    {"id": "lava_salamander", "rarity": "purple", "name": "熔岩蝾螈", "effect": "对宝箱伤害 +25%", "kind": "chest_damage", "base": 0.25},
    {"id": "star_raccoon", "rarity": "gold", "name": "星轨浣熊", "effect": "矿物数量 +10%", "kind": "yield", "base": 0.10},
)
PET_BY_ID = {pet["id"]: pet for pet in PETS}
PET_RARITY_WEIGHT = {"white": 0.45, "blue": 0.27, "purple": 0.20, "gold": 0.06, "red": 0.02}
PET_UPGRADE_BASE = {"white": 80, "blue": 144, "purple": 280, "gold": 560, "red": 1200}


SKILLS: tuple[dict[str, Any], ...] = (
    {"id": "trained_tap", "tree": "keyboard", "tier": 1, "name": "熟练敲击", "max": 10, "desc": "键盘伤害每级 +12%"},
    {"id": "hot_hands", "tree": "keyboard", "tier": 1, "name": "热手", "max": 10, "desc": "每层连击每级 +0.15% 伤害"},
    {"id": "space_hammer", "tree": "keyboard", "tier": 2, "name": "空格重锤", "max": 8, "desc": "每25次键盘命中追加重击"},
    {"id": "fast_typing", "tree": "keyboard", "tier": 3, "name": "高速录入", "max": 6, "desc": "50连击以上每级 +2% 暴击率"},
    {"id": "keyboard_symphony", "tree": "keyboard", "tier": 5, "name": "键盘交响", "max": 3, "desc": "键盘连击总倍率每级 ×1.5"},
    {"id": "auto_pick", "tree": "idle", "tier": 1, "name": "自动镐", "max": 10, "desc": "自动攻击间隔每级 -4%"},
    {"id": "silent_charge", "tree": "idle", "tier": 1, "name": "静默蓄能", "max": 10, "desc": "每静默10秒自动伤害每级 +3%"},
    {"id": "steady_drill", "tree": "idle", "tier": 2, "name": "稳定钻头", "max": 8, "desc": "自动攻击伤害每级 +15%"},
    {"id": "return_blast", "tree": "idle", "tier": 3, "name": "复工爆破", "max": 6, "desc": "恢复输入时释放蓄积伤害"},
    {"id": "perpetual_core", "tree": "idle", "tier": 5, "name": "永动机芯", "max": 3, "desc": "自动伤害总倍率每级 ×1.6"},
    {"id": "precision", "tree": "mouse", "tier": 1, "name": "精准镐击", "max": 10, "desc": "鼠标伤害每级 +12%"},
    {"id": "crack_tracking", "tree": "mouse", "tier": 1, "name": "裂纹追踪", "max": 10, "desc": "弱点引爆每层每级 +2%"},
    {"id": "quick_mark", "tree": "mouse", "tier": 2, "name": "快速标记", "max": 8, "desc": "降低弱点引爆所需点击数"},
    {"id": "treasure_instinct", "tree": "mouse", "tier": 3, "name": "寻宝直觉", "max": 6, "desc": "装备品质提升判定每级 +2%"},
    {"id": "heart_blast", "tree": "mouse", "tier": 5, "name": "红心爆破", "max": 3, "desc": "弱点引爆总倍率每级 ×1.7"},
)
SKILL_BY_ID = {skill["id"]: skill for skill in SKILLS}
TIER_COST = {1: 1, 2: 2, 3: 4, 4: 7, 5: 12}
TIER_REQUIREMENT = {1: 0, 2: 5, 3: 15, 4: 30, 5: 50}


@dataclass
class Equipment:
    id: str
    slot: str
    rarity: str
    set_name: str
    name: str
    level: int
    roll: float
    source_depth: int

    @classmethod
    def from_dict(cls, value: dict[str, Any]) -> "Equipment":
        return cls(**value)

    def affix_value(self) -> float:
        coeff = RARITY_COEFFICIENT[self.rarity]
        if self.slot == "head":
            return 0.005 * coeff * math.log2(self.level + 1) * self.roll
        if self.slot == "pickaxe":
            return normal_hp(self.level) * 0.08 * coeff * self.roll
        if self.slot == "clothing":
            return 0.0075 * coeff * math.log2(self.level + 1) * self.roll
        return min(0.20, 0.0036 * coeff * math.log2(self.level + 1) * self.roll)

    def affix_text(self) -> str:
        value = self.affix_value()
        if self.slot == "head":
            return f"宠物效果 +{value * 100:.1f}%"
        if self.slot == "pickaxe":
            return f"基础攻击 +{format_number(value)}"
        if self.slot == "clothing":
            return f"返回资金 +{value * 100:.1f}%"
        return f"回挖比例 +{value * 100:.1f}%"


def normal_hp(depth: int) -> float:
    depth = max(1, int(depth))
    return 10.0 * (1.032 ** (depth - 1)) * (1.35 ** ((depth - 1) // 100))


def format_number(value: float | int) -> str:
    value = float(value)
    if value < 1000:
        return f"{value:,.0f}"
    if value < 1_000_000:
        return f"{value / 1000:.2f}K"
    if value < 1_000_000_000:
        return f"{value / 1_000_000:.2f}M"
    if value < 1_000_000_000_000:
        return f"{value / 1_000_000_000:.2f}B"
    return f"{value:.3e}".replace("e+", "e")


def choose_weighted(rng: random.Random, weights: list[tuple[str, float]]) -> str:
    total = sum(weight for _, weight in weights)
    roll = rng.random() * total
    cursor = 0.0
    for value, weight in weights:
        cursor += weight
        if roll <= cursor:
            return value
    return weights[-1][0]


class GameModel:
    """纯本地游戏状态。不会接收或保存键码、字符、坐标或应用名称。"""

    SAVE_VERSION = 4

    def __init__(self, save_dir: str | Path | None = None, seed: int | None = None) -> None:
        default_dir = Path(os.environ.get("APPDATA", Path.home())) / "DeepDeskMiner"
        self.save_dir = Path(save_dir) if save_dir else default_dir
        self.save_path = self.save_dir / "save.json"
        self.rng = random.Random(seed)
        self._event_listeners: list[Callable[[dict[str, Any]], None]] = []
        self._dirty = False
        self._last_save_monotonic = time.monotonic()
        self._last_tick = time.monotonic()
        self._last_input = time.monotonic()
        self._last_auto = time.monotonic()
        self._auto_stored_damage = 0.0
        self._keyboard_times: list[float] = []
        self._mouse_times: list[float] = []
        self.data = self._default_data()
        if self.save_path.exists():
            self.load()
        if not self.data.get("target"):
            self.data["target"] = self.generate_target(self.data["depth"])
        self._ensure_daily()

    def _default_data(self) -> dict[str, Any]:
        equipment: list[dict[str, Any]] = []
        equipped: dict[str, str] = {}
        for slot in SLOTS:
            item = Equipment(
                id=f"starter_{slot}",
                slot=slot,
                rarity="white",
                set_name="新手矿工",
                name=STARTER_NAMES[slot],
                level=1,
                roll=1.0,
                source_depth=1,
            )
            equipment.append(asdict(item))
            equipped[slot] = item.id
        return {
            "version": self.SAVE_VERSION,
            "created_at": datetime.now().isoformat(timespec="seconds"),
            "depth": 1,
            "run_start_depth": 1,
            "max_depth": 1,
            "target": None,
            "warehouse": {rarity: 0 for rarity in RARITIES},
            "funds": 0,
            "skill_points": 0,
            "cleared_counter": 0,
            "highest_skill_milestone": 0,
            "run_equipment_count": 0,
            "skills": {},
            "equipment": equipment,
            "equipped": equipped,
            "catalog_sets": {"新手矿工": list(SLOTS)},
            "pets": {"rock_mouse": 1},
            "active_pet": "rock_mouse",
            "support_pets": [],
            "eggs_bought": 0,
            "combo": 0,
            "weakness": 0,
            "round_keyboard_hits": 0,
            "round_mouse_hits": 0,
            "paused": False,
            "completed": False,
            "notification": "标准",
            "stats": {
                "keyboard_hits": 0,
                "mouse_hits": 0,
                "auto_hits": 0,
                "returns": 0,
                "layers_cleared": 0,
                "chests_opened": 0,
                "opened_seconds": 0,
                "highest_rarity": "white",
            },
            "daily": {},
            "settings": {"overlay_x": None, "overlay_y": None, "overlay_hidden": False, "sound": False},
        }

    def add_listener(self, callback: Callable[[dict[str, Any]], None]) -> None:
        self._event_listeners.append(callback)

    def emit(self, event_type: str, **payload: Any) -> None:
        event = {"type": event_type, **payload}
        for callback in tuple(self._event_listeners):
            callback(event)

    def mark_dirty(self) -> None:
        self._dirty = True

    def save(self, force: bool = False) -> None:
        if not force and not self._dirty:
            return
        self.save_dir.mkdir(parents=True, exist_ok=True)
        payload = copy.deepcopy(self.data)
        payload["version"] = self.SAVE_VERSION
        temp_path = self.save_dir / "save.tmp"
        temp_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        if self.save_path.exists():
            stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
            backup = self.save_dir / f"save-{stamp}.bak.json"
            shutil.copy2(self.save_path, backup)
            backups = sorted(self.save_dir.glob("save-*.bak.json"), reverse=True)
            for old in backups[3:]:
                old.unlink(missing_ok=True)
        os.replace(temp_path, self.save_path)
        self._dirty = False
        self._last_save_monotonic = time.monotonic()

    def load(self) -> None:
        try:
            loaded = json.loads(self.save_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            backups = sorted(self.save_dir.glob("save-*.bak.json"), reverse=True)
            if not backups:
                return
            loaded = json.loads(backups[0].read_text(encoding="utf-8"))
        if int(loaded.get("version", 1)) < 3:
            highest_depth = max(1, int(loaded.get("max_depth", 1)))
            loaded["highest_skill_milestone"] = (highest_depth // SKILL_POINT_INTERVAL) * SKILL_POINT_INTERVAL
        default = self._default_data()
        default.update(loaded)
        default["stats"] = {**self._default_data()["stats"], **loaded.get("stats", {})}
        default["settings"] = {**self._default_data()["settings"], **loaded.get("settings", {})}
        self.data = default

    def _daily_key(self, now: datetime | None = None) -> str:
        adjusted = (now or datetime.now()) - timedelta(hours=4)
        return adjusted.date().isoformat()

    def _ensure_daily(self) -> None:
        key = self._daily_key()
        if self.data.get("daily", {}).get("date") != key:
            self.data["daily"] = {
                "date": key,
                "opened_seconds": 0.0,
                "layers": 0,
                "keyboard": 0,
                "mouse": 0,
                "auto": 0,
                "rewarded": False,
            }
            self.mark_dirty()

    def daily_status(self) -> dict[str, Any]:
        self._ensure_daily()
        daily = self.data["daily"]
        return {
            "陪伴20分钟": min(1.0, daily["opened_seconds"] / 1200),
            "清除20层": min(1.0, daily["layers"] / 20),
            "工作方式": min(1.0, max(daily["keyboard"] / 200, daily["mouse"] / 100, daily["auto"] / 60)),
            "rewarded": daily["rewarded"],
        }

    def _check_daily_reward(self) -> None:
        daily = self.data["daily"]
        if daily["rewarded"]:
            return
        if daily["opened_seconds"] >= 1200 and daily["layers"] >= 20 and (
            daily["keyboard"] >= 200 or daily["mouse"] >= 100 or daily["auto"] >= 60
        ):
            daily["rewarded"] = True
            self.data["skill_points"] += 1
            self.emit("daily_reward", amount=1)
            self.mark_dirty()

    def get_equipment(self, item_id: str | None) -> Equipment | None:
        if not item_id:
            return None
        for raw in self.data["equipment"]:
            if raw["id"] == item_id:
                return Equipment.from_dict(raw)
        return None

    def equipped_item(self, slot: str) -> Equipment:
        item = self.get_equipment(self.data["equipped"].get(slot))
        if item is None:
            raise RuntimeError(f"missing equipped item: {slot}")
        return item

    def head_pet_bonus(self) -> float:
        return self.equipped_item("head").affix_value()

    def pickaxe_attack(self) -> float:
        return self.equipped_item("pickaxe").affix_value()

    def clothing_funds_bonus(self) -> float:
        return self.equipped_item("clothing").affix_value()

    def return_ratio(self) -> float:
        return min(0.90, 0.70 + self.equipped_item("shoes").affix_value())

    def pet_effect(self, kind: str) -> float:
        result = 0.0
        active_pet = self.data.get("active_pet")
        for pet_id in self.data.get("pets", {}):
            position = 1.0 if pet_id == active_pet else INACTIVE_PET_PASSIVE_RATIO
            pet = PET_BY_ID.get(pet_id or "")
            if not pet or pet["kind"] != kind:
                continue
            level = self.data["pets"].get(pet_id, 1)
            growth = (1.08 ** (level - 1)) * (1 + self.head_pet_bonus()) * position
            result += float(pet["base"]) * growth
        return result

    def chest_chance(self) -> float:
        multiplier = 1 + self.pet_effect("chest")
        return min(0.60, 0.15 * multiplier)

    def generate_target(self, depth: int, seed: int | None = None) -> dict[str, Any]:
        depth = max(1, min(10000, int(depth)))
        seed = int(seed if seed is not None else self.rng.getrandbits(63))
        rng = random.Random(seed)
        if depth <= 10:
            kind, rarity, name, multiplier = "tutorial", "white", "教学岩壁", 1.0
        elif depth == 10000:
            kind, rarity, name, multiplier = "diamond", "red", "地心永恒钻石", 300.0
            base = normal_hp(9999)
            maximum = base * multiplier
            return {"seed": seed, "kind": kind, "rarity": rarity, "name": name, "max_hp": maximum, "hp": maximum}
        elif rng.random() < self.chest_chance():
            rarity = choose_weighted(rng, [("red", 0.02), ("gold", 0.04), ("purple", 0.10), ("blue", 0.20), ("white", 0.64)])
            kind, name, multiplier = "chest", CHEST_LABEL[rarity], CHEST_HP_MULTIPLIER[rarity]
        else:
            rarity = choose_weighted(rng, [("red", 0.01), ("gold", 0.025), ("purple", 0.10), ("blue", 0.20), ("white", 0.665)])
            kind, name, multiplier = "ore", MINERALS[rarity][0], ORE_HP_MULTIPLIER[rarity]
        maximum = normal_hp(depth) * multiplier
        return {"seed": seed, "kind": kind, "rarity": rarity, "name": name, "max_hp": maximum, "hp": maximum}

    def skill_level(self, skill_id: str) -> int:
        return int(self.data["skills"].get(skill_id, 0))

    def skill_cost(self, skill_id: str) -> int:
        skill = SKILL_BY_ID[skill_id]
        next_level = self.skill_level(skill_id) + 1
        return math.ceil(TIER_COST[skill["tier"]] * (1.55 ** (next_level - 1)))

    def tree_investment(self, tree: str) -> int:
        return sum(self.skill_level(skill["id"]) for skill in SKILLS if skill["tree"] == tree)

    def can_buy_skill(self, skill_id: str) -> tuple[bool, str]:
        skill = SKILL_BY_ID[skill_id]
        if self.skill_level(skill_id) >= skill["max"]:
            return False, "已满级"
        requirement = TIER_REQUIREMENT[skill["tier"]]
        if self.tree_investment(skill["tree"]) < requirement:
            return False, f"本系需投入 {requirement} 点"
        cost = self.skill_cost(skill_id)
        if self.data["skill_points"] < cost:
            return False, f"需要 {cost} 技能点"
        return True, ""

    def buy_skill(self, skill_id: str) -> tuple[bool, str]:
        ok, reason = self.can_buy_skill(skill_id)
        if not ok:
            return False, reason
        cost = self.skill_cost(skill_id)
        self.data["skill_points"] -= cost
        self.data["skills"][skill_id] = self.skill_level(skill_id) + 1
        self.mark_dirty()
        self.emit("skill_bought", skill=SKILL_BY_ID[skill_id]["name"])
        self.save(force=True)
        return True, "升级成功"

    def reset_skills(self) -> int:
        refunded = 0
        for skill in SKILLS:
            for level in range(1, self.skill_level(skill["id"]) + 1):
                refunded += math.ceil(TIER_COST[skill["tier"]] * (1.55 ** (level - 1)))
        self.data["skills"] = {}
        self.data["skill_points"] += refunded
        self.mark_dirty()
        self.save(force=True)
        return refunded

    def _rate_allowed(self, kind: str, now: float) -> bool:
        history = self._keyboard_times if kind == "keyboard" else self._mouse_times
        limit = 30 if kind == "keyboard" else 20
        history[:] = [stamp for stamp in history if now - stamp < 1.0]
        if len(history) >= limit:
            return False
        history.append(now)
        return True

    def _base_damage(self) -> float:
        return 1.0 + self.pickaxe_attack()

    def _all_damage_multiplier(self) -> float:
        multiplier = 1 + self.pet_effect("all_damage")
        if self.data["depth"] <= self.data.get("max_depth", 1):
            multiplier *= 1 + self.pet_effect("rewind_damage")
        return multiplier

    def _keyboard_damage(self) -> tuple[float, bool]:
        base = self._base_damage()
        multiplier = 1 + 0.12 * self.skill_level("trained_tap")
        multiplier *= 1 + self.pet_effect("keyboard_damage")
        multiplier *= self._all_damage_multiplier()
        heat = 0.0015 * self.skill_level("hot_hands") * self.data["combo"]
        multiplier *= 1 + heat
        if self.data["combo"] >= 100:
            multiplier *= 1.5 ** self.skill_level("keyboard_symphony")
        crit_chance = 0.05
        if self.data["combo"] > 50:
            crit_chance += 0.02 * self.skill_level("fast_typing")
        critical = self.rng.random() < min(0.75, crit_chance)
        if critical:
            multiplier *= 2.0
        return base * multiplier, critical

    def _mouse_damage(self) -> tuple[float, bool]:
        base = self._base_damage()
        multiplier = (1 + 0.12 * self.skill_level("precision")) * self._all_damage_multiplier()
        critical = self.rng.random() < 0.05
        if critical:
            multiplier *= 2.0
        return base * multiplier, critical

    def _auto_damage(self, idle_seconds: float) -> float:
        multiplier = 1 + 0.15 * self.skill_level("steady_drill")
        multiplier *= 1 + min(30, int(idle_seconds // 10)) * 0.03 * self.skill_level("silent_charge")
        multiplier *= 1.6 ** self.skill_level("perpetual_core")
        multiplier *= 1 + self.pet_effect("auto_damage")
        multiplier *= self._all_damage_multiplier()
        return self._base_damage() * multiplier

    def auto_interval(self) -> float:
        interval = 3.0 * (0.96 ** self.skill_level("auto_pick"))
        interval /= 1 + self.pet_effect("auto_speed")
        return max(0.35, interval)

    def process_input(self, kind: str, now: float | None = None) -> float:
        if self.data["paused"] or self.data["completed"] or kind not in ("keyboard", "mouse"):
            return 0.0
        now = now if now is not None else time.monotonic()
        if not self._rate_allowed(kind, now):
            self.emit("rate_limited", kind=kind)
            return 0.0
        was_idle = now - self._last_input >= 10.0
        self._last_input = now
        if kind == "keyboard":
            self.data["combo"] = min(100, self.data["combo"] + 1)
            self.data["round_keyboard_hits"] += 1
            self.data["stats"]["keyboard_hits"] += 1
            self.data["daily"]["keyboard"] += 1
            damage, critical = self._keyboard_damage()
            if self.data["round_keyboard_hits"] % 25 == 0 and self.skill_level("space_hammer"):
                damage *= 1 + 1.5 * self.skill_level("space_hammer")
            ink = self.pet_effect("ink")
            if ink and self.data["stats"]["keyboard_hits"] % 50 == 0:
                damage += self._base_damage() * ink
            phoenix = self.pet_effect("phoenix")
            if phoenix and self.data["stats"]["keyboard_hits"] % 100 == 0:
                damage += self._base_damage() * phoenix
                self.emit("special", message="万键凤凰发动了凤凰打击！")
        else:
            self.data["weakness"] = min(30, self.data["weakness"] + 1)
            self.data["round_mouse_hits"] += 1
            self.data["stats"]["mouse_hits"] += 1
            self.data["daily"]["mouse"] += 1
            damage, critical = self._mouse_damage()
            threshold = max(6, round(10 - 0.5 * self.skill_level("quick_mark")))
            if self.data["round_mouse_hits"] % threshold == 0:
                explosion = self._base_damage() * (1 + self.data["weakness"] * 0.02 * self.skill_level("crack_tracking"))
                explosion *= 1.7 ** self.skill_level("heart_blast")
                explosion *= 1 + self.pet_effect("weakness")
                damage += explosion
                self.emit("special", message=f"弱点引爆 ×{self.data['weakness']}！")
                self.data["weakness"] = 0
        if was_idle and self.skill_level("return_blast") and self._auto_stored_damage > 0:
            blast = self._auto_stored_damage * 0.08 * self.skill_level("return_blast")
            damage += blast
            self._auto_stored_damage = 0.0
            self.emit("special", message=f"复工爆破 {format_number(blast)}")
        self.apply_damage(damage, kind=kind, critical=critical)
        self._check_daily_reward()
        self.mark_dirty()
        return damage

    def process_auto_hit(self, idle_seconds: float) -> float:
        if self.data["paused"] or self.data["completed"]:
            return 0.0
        damage = self._auto_damage(idle_seconds)
        self.data["stats"]["auto_hits"] += 1
        self.data["daily"]["auto"] += 1
        self._auto_stored_damage += damage
        whale = self.pet_effect("whale")
        if whale and int(idle_seconds) > 0 and int(idle_seconds) % 60 < self.auto_interval():
            damage += self._base_damage() * whale
            self.emit("special", message="永动鲸发动了鲸落打击！")
        self.apply_damage(damage, kind="auto", critical=False)
        self._check_daily_reward()
        self.mark_dirty()
        return damage

    def apply_damage(self, damage: float, kind: str, critical: bool = False) -> None:
        if damage <= 0 or not self.data.get("target"):
            return
        remaining = float(damage)
        chain = 0
        while remaining > 0 and chain < 5 and not self.data["completed"]:
            target = self.data["target"]
            dealt = min(remaining, target["hp"])
            target["hp"] = max(0.0, target["hp"] - remaining)
            self.emit("hit", damage=dealt, source=kind, critical=critical, chain=chain)
            if target["hp"] > 0:
                break
            overflow = max(0.0, remaining - dealt)
            self._clear_target()
            chain += 1
            if overflow <= 0:
                break
            next_target = self.data["target"]
            if overflow < next_target["max_hp"] * 5:
                break
            remaining = overflow

    def _clear_target(self) -> None:
        target = self.data["target"]
        depth = self.data["depth"]
        drop_text = ""
        if target["kind"] == "ore":
            base_amount = 1 + depth // 50
            amount = base_amount * ORE_AMOUNT_MULTIPLIER[target["rarity"]]
            amount *= 1 + self.pet_effect("yield")
            if target["rarity"] != "white":
                amount *= 1 + self.pet_effect("rare_yield")
            amount = max(1, math.floor(amount))
            self.data["warehouse"][target["rarity"]] += amount
            drop_text = f"+{amount} {MINERALS[target['rarity']][0]}"
            self.data["stats"]["highest_rarity"] = self._higher_rarity(
                self.data["stats"].get("highest_rarity", "white"), target["rarity"]
            )
        elif target["kind"] == "chest":
            item = self._generate_equipment(depth, target["rarity"], target["seed"])
            self.data["equipment"].append(asdict(item))
            self.data["stats"]["chests_opened"] += 1
            self.data["run_equipment_count"] += 1
            self._record_catalog(item)
            drop_text = f"{item.set_name}·{item.name}"
            self.emit("equipment_drop", item=asdict(item), equipped=False)
        elif target["kind"] == "diamond":
            self.data["completed"] = True
            self.emit("game_complete")
            self.mark_dirty()
            self.save(force=True)
            return
        self.data["stats"]["layers_cleared"] += 1
        self.data["daily"]["layers"] += 1
        next_depth = min(10000, depth + 1)
        if next_depth > self.data["highest_skill_milestone"] and next_depth % SKILL_POINT_INTERVAL == 0:
            self.data["highest_skill_milestone"] = next_depth
            self.data["skill_points"] += 1
            self.emit("skill_point", amount=1, milestone=next_depth)
        old_depth = depth
        self.data["depth"] = next_depth
        self.data["max_depth"] = max(self.data["max_depth"], self.data["depth"])
        self.data["target"] = self.generate_target(self.data["depth"])
        self.emit("layer_clear", depth=old_depth, drop=drop_text, target=target)
        self._check_daily_reward()
        self.mark_dirty()

    def _higher_rarity(self, left: str, right: str) -> str:
        return right if RARITIES.index(right) > RARITIES.index(left) else left

    def _gear_upgrade_chance(self) -> float:
        return min(0.95, 0.02 * self.skill_level("treasure_instinct") + (1 - math.exp(-self.pet_effect("gear_luck"))))

    def _generate_equipment(self, depth: int, rarity: str, seed: int) -> Equipment:
        rng = random.Random(seed ^ 0x5A17C0DE)
        if rarity != "red" and rng.random() < self._gear_upgrade_chance():
            rarity = RARITIES[RARITIES.index(rarity) + 1]
        slot = rng.choice(SLOTS)
        set_name = rng.choice(SET_NAMES[rarity])
        level = max(1, round(depth * rng.uniform(0.9, 1.1)))
        roll = rng.uniform(0.85, 1.15)
        if set_name == "新手矿工":
            name = STARTER_NAMES[slot]
        else:
            name = rng.choice(SLOT_ITEM_NAMES[slot])
        return Equipment(str(uuid.uuid4()), slot, rarity, set_name, name, level, roll, depth)

    def _record_catalog(self, item: Equipment) -> None:
        owned = set(self.data["catalog_sets"].get(item.set_name, []))
        before = len(owned)
        owned.add(item.slot)
        self.data["catalog_sets"][item.set_name] = sorted(owned)
        if before < 4 == len(owned) and item.rarity in ("purple", "gold", "red"):
            self.emit("set_complete", set_name=item.set_name, rarity=item.rarity)

    def _auto_equip(self, item: Equipment) -> bool:
        current = self.equipped_item(item.slot)
        if item.affix_value() > current.affix_value():
            self.data["equipped"][item.slot] = item.id
            return True
        return False

    def equip(self, item_id: str) -> bool:
        item = self.get_equipment(item_id)
        if not item:
            return False
        self.data["equipped"][item.slot] = item.id
        self.mark_dirty()
        self.save(force=True)
        return True

    def warehouse_value(self) -> float:
        return sum(self.data["warehouse"][rarity] * MINERALS[rarity][1] for rarity in RARITIES)

    def return_preview(self) -> dict[str, Any]:
        depth_bonus = 1 + 0.02 * (self.data["depth"] // 100)
        pet_bonus = 1 + self.pet_effect("funds")
        clothes_bonus = 1 + self.clothing_funds_bonus()
        funds = math.floor(self.warehouse_value() * depth_bonus * pet_bonus * clothes_bonus)
        ratio = self.return_ratio()
        next_depth = max(1, math.floor(self.data["depth"] * ratio))
        per_hit = max(1.0, self._base_damage() * self._all_damage_multiplier())
        estimated_hits = 0.0
        sample_step = max(1, (self.data["depth"] - next_depth) // 100)
        for level in range(next_depth, self.data["depth"], sample_step):
            estimated_hits += normal_hp(level) / per_hit
        estimated_hits *= sample_step
        return {
            "funds": funds,
            "return_depth": self.data["depth"],
            "ratio": ratio,
            "next_depth": next_depth,
            "estimated_hits": math.ceil(estimated_hits),
        }

    def return_to_surface(self) -> dict[str, Any]:
        preview = self.return_preview()
        self.data["funds"] += preview["funds"]
        self.data["warehouse"] = {rarity: 0 for rarity in RARITIES}
        self.data["depth"] = preview["next_depth"]
        self.data["run_start_depth"] = preview["next_depth"]
        self.data["target"] = self.generate_target(preview["next_depth"])
        self.data["combo"] = 0
        self.data["weakness"] = 0
        self.data["round_keyboard_hits"] = 0
        self.data["round_mouse_hits"] = 0
        self.data["run_equipment_count"] = 0
        self.data["stats"]["returns"] += 1
        auto_equipped = 0
        for raw in self.data["equipment"]:
            item = self.get_equipment(raw.get("id"))
            if item and self._auto_equip(item):
                auto_equipped += 1
        preview["auto_equipped"] = auto_equipped
        self.mark_dirty()
        self.save(force=True)
        self.emit("returned", **preview)
        return preview

    def egg_price(self) -> int:
        return math.ceil(500 * (1.28 ** self.data["eggs_bought"]))

    def egg_probabilities(self) -> dict[str, float]:
        remaining_rarities = {
            pet["rarity"] for pet in PETS if pet["id"] not in self.data["pets"]
        }
        total = sum(PET_RARITY_WEIGHT[rarity] for rarity in remaining_rarities)
        if total <= 0:
            return {}
        return {rarity: PET_RARITY_WEIGHT[rarity] / total for rarity in RARITIES if rarity in remaining_rarities}

    def hatch_pet(self) -> tuple[bool, str, dict[str, Any] | None]:
        if len(self.data["pets"]) >= len(PETS):
            return False, "宠物图鉴已完成", None
        price = self.egg_price()
        if self.data["funds"] < price:
            return False, f"还需要 {format_number(price - self.data['funds'])} 资金", None
        probabilities = self.egg_probabilities()
        rarity = choose_weighted(self.rng, list(probabilities.items()))
        candidates = [pet for pet in PETS if pet["rarity"] == rarity and pet["id"] not in self.data["pets"]]
        pet = self.rng.choice(candidates)
        self.data["funds"] -= price
        self.data["eggs_bought"] += 1
        self.data["pets"][pet["id"]] = 1
        self.mark_dirty()
        self.save(force=True)
        self.emit("pet_hatched", pet=pet)
        return True, f"孵出了 {pet['name']}！", pet

    def pet_upgrade_cost(self, pet_id: str) -> int:
        pet = PET_BY_ID[pet_id]
        next_level = self.data["pets"].get(pet_id, 0) + 1
        return math.ceil(PET_UPGRADE_BASE[pet["rarity"]] * (1.22 ** (next_level - 1)))

    def upgrade_pet(self, pet_id: str) -> tuple[bool, str]:
        if pet_id not in self.data["pets"]:
            return False, "尚未获得这只宠物"
        cost = self.pet_upgrade_cost(pet_id)
        if self.data["funds"] < cost:
            return False, f"需要 {format_number(cost)} 资金"
        self.data["funds"] -= cost
        self.data["pets"][pet_id] += 1
        self.mark_dirty()
        self.save(force=True)
        return True, "升级成功"

    def set_active_pet(self, pet_id: str) -> bool:
        if pet_id not in self.data["pets"]:
            return False
        self.data["active_pet"] = pet_id
        self.data["support_pets"] = [value for value in self.data.get("support_pets", []) if value != pet_id]
        self.mark_dirty()
        self.save(force=True)
        return True

    def toggle_support_pet(self, pet_id: str) -> bool:
        if pet_id not in self.data["pets"] or pet_id == self.data.get("active_pet"):
            return False
        support = self.data.setdefault("support_pets", [])
        if pet_id in support:
            support.remove(pet_id)
        elif len(support) < 2:
            support.append(pet_id)
        else:
            support.pop(0)
            support.append(pet_id)
        self.mark_dirty()
        self.save(force=True)
        return True

    def set_paused(self, paused: bool | None = None) -> bool:
        self.data["paused"] = (not self.data["paused"]) if paused is None else bool(paused)
        self.mark_dirty()
        self.save(force=True)
        self.emit("pause_changed", paused=self.data["paused"])
        return self.data["paused"]

    def tick(self, now: float | None = None) -> None:
        now = now if now is not None else time.monotonic()
        elapsed = max(0.0, min(2.0, now - self._last_tick))
        self._last_tick = now
        self._ensure_daily()
        if not self.data["paused"]:
            self.data["stats"]["opened_seconds"] += elapsed
            self.data["daily"]["opened_seconds"] += elapsed
            if now - self._last_input > 2.5:
                decay = max(1, int(elapsed * 12))
                self.data["combo"] = max(0, self.data["combo"] - decay)
            idle_seconds = now - self._last_input
            if idle_seconds >= 10:
                interval = self.auto_interval()
                attacks = min(5, int((now - self._last_auto) / interval))
                if attacks:
                    for _ in range(attacks):
                        self.process_auto_hit(idle_seconds)
                    self._last_auto = now
            else:
                self._last_auto = now
            self._check_daily_reward()
            self.mark_dirty()
        if now - self._last_save_monotonic >= 5:
            self.save()

    def target_progress(self) -> float:
        target = self.data["target"]
        if not target or target["max_hp"] <= 0:
            return 0.0
        return max(0.0, min(1.0, target["hp"] / target["max_hp"]))

    def shutdown(self) -> None:
        self.save(force=True)
