import json
import tempfile
import unittest
from pathlib import Path

from deepdesk.model import GameModel, INACTIVE_PET_PASSIVE_RATIO, PETS, RARITIES


class GameModelTests(unittest.TestCase):
    def model(self, seed=7):
        self.temp = tempfile.TemporaryDirectory()
        return GameModel(Path(self.temp.name), seed=seed)

    def tearDown(self):
        if hasattr(self, "temp"):
            self.temp.cleanup()

    def test_tutorial_layers_never_drop_loot(self):
        model = self.model()
        for _ in range(10):
            self.assertEqual(model.data["target"]["kind"], "tutorial")
            model.apply_damage(model.data["target"]["hp"], "keyboard")
        self.assertEqual(model.data["depth"], 11)
        self.assertEqual(sum(model.data["warehouse"].values()), 0)

    def test_first_arrival_at_each_seventy_layer_milestone_gives_one_skill_point(self):
        model = self.model()
        for _ in range(69):
            model.apply_damage(model.data["target"]["hp"], "keyboard")
        self.assertEqual(model.data["skill_points"], 1)
        self.assertEqual(model.data["highest_skill_milestone"], 70)
        model.data["depth"] = 69
        model.data["target"] = model.generate_target(69)
        model.apply_damage(model.data["target"]["hp"], "keyboard")
        self.assertEqual(model.data["skill_points"], 1)
        model.data["depth"] = 139
        model.data["target"] = model.generate_target(139)
        model.apply_damage(model.data["target"]["hp"], "keyboard")
        self.assertEqual(model.data["skill_points"], 2)

    def test_run_equipment_counter_tracks_chests_and_resets_on_return(self):
        model = self.model()
        model.data["depth"] = 11
        model.data["target"] = {"seed": 12345, "kind": "chest", "rarity": "blue", "name": "铁箱", "max_hp": 1.0, "hp": 1.0}
        model.apply_damage(1.0, "keyboard")
        self.assertEqual(model.data["run_equipment_count"], 1)
        model.return_to_surface()
        self.assertEqual(model.data["run_equipment_count"], 0)

    def test_return_clears_warehouse_and_rewinds(self):
        model = self.model()
        model.data["depth"] = 100
        model.data["target"] = model.generate_target(100)
        model.data["warehouse"]["blue"] = 10
        preview = model.return_preview()
        result = model.return_to_surface()
        self.assertEqual(result["funds"], preview["funds"])
        self.assertEqual(sum(model.data["warehouse"].values()), 0)
        self.assertGreaterEqual(model.data["depth"], 70)
        self.assertLessEqual(model.data["depth"], 90)

    def test_pet_pool_never_duplicates_and_closes_at_eighteen(self):
        model = self.model()
        model.data["funds"] = 10**12
        while len(model.data["pets"]) < len(PETS):
            ok, _, pet = model.hatch_pet()
            self.assertTrue(ok)
            self.assertIsNotNone(pet)
        ok, reason, _ = model.hatch_pet()
        self.assertFalse(ok)
        self.assertIn("完成", reason)
        self.assertEqual(len(model.data["pets"]), 18)

    def test_egg_price_uses_steeper_growth(self):
        model = self.model()
        self.assertEqual(model.egg_price(), 500)
        model.data["eggs_bought"] = 1
        self.assertEqual(model.egg_price(), 640)

    def test_all_inactive_owned_pets_contribute_ten_percent(self):
        model = self.model()
        model.data["pets"]["bulb_bug"] = 1
        model.data["pets"]["gold_slime"] = 1
        model.data["active_pet"] = "rock_mouse"
        expected = (0.04 + 0.05) * (1 + model.head_pet_bonus()) * INACTIVE_PET_PASSIVE_RATIO
        self.assertAlmostEqual(model.pet_effect("funds"), expected)
        model.data["active_pet"] = "bulb_bug"
        expected = (0.04 + 0.05 * INACTIVE_PET_PASSIVE_RATIO) * (1 + model.head_pet_bonus())
        self.assertAlmostEqual(model.pet_effect("funds"), expected)

    def test_target_is_preserved_across_save(self):
        model = self.model()
        model.data["target"]["hp"] *= 0.37
        original = dict(model.data["target"])
        model.save(force=True)
        loaded = GameModel(model.save_dir, seed=99)
        self.assertEqual(loaded.data["target"], original)

    def test_save_contains_no_input_content_fields(self):
        model = self.model()
        model.process_input("keyboard", now=100.0)
        model.process_input("mouse", now=101.0)
        model.save(force=True)
        payload = json.loads(model.save_path.read_text(encoding="utf-8"))
        serialized = json.dumps(payload).lower()
        for forbidden in ("vkcode", "scancode", "cursor", "foreground", "clipboard", "keystroke"):
            self.assertNotIn(forbidden, serialized)

    def test_final_floor_is_always_the_diamond(self):
        model = self.model()
        for seed in range(20):
            target = model.generate_target(10000, seed)
            self.assertEqual(target["kind"], "diamond")
            self.assertEqual(target["name"], "地心永恒钻石")


if __name__ == "__main__":
    unittest.main()
