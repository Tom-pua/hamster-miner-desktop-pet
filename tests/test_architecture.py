import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class ArchitectureBoundaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content = json.loads((ROOT / "config" / "content.json").read_text(encoding="utf-8-sig"))
        cls.balance = json.loads((ROOT / "config" / "balance.json").read_text(encoding="utf-8-sig"))

    def test_content_ids_and_weights_are_valid(self):
        pets = [pet["name"] for pet in self.content["pets"]]
        skills = [skill["id"] for skill in self.content["skills"]]
        self.assertEqual(len(pets), len(set(pets)))
        self.assertEqual(len(skills), len(set(skills)))
        self.assertEqual(len(pets), 18)
        self.assertEqual(len(skills), 15)
        for key in ("oreWeight", "chestWeight", "eggWeight"):
            self.assertAlmostEqual(sum(item[key] for item in self.content["rarities"]), 1.0)
        colors = {item["key"]: item["color"].upper() for item in self.content["rarities"]}
        self.assertEqual(colors, {"white": "#DCE5E4", "blue": "#56A8FF", "purple": "#B77AFF", "gold": "#FF9F43", "red": "#FF5E6A"})

    def test_balance_has_migratable_version_and_positive_curves(self):
        self.assertGreaterEqual(self.balance["saveVersion"], 4)
        self.assertGreater(self.balance["hpGrowth"], 1)
        self.assertGreater(self.balance["eggPriceGrowth"], 1)
        self.assertGreater(self.balance["pickaxeCoefficient"], 1)

    def test_domain_has_no_ui_storage_or_global_state_dependency(self):
        text = (ROOT / "domain" / "Rules.ps1").read_text(encoding="utf-8-sig")
        for forbidden in ("PresentationFramework", "System.Windows", "Get-Content", "WriteAllText", "$script:State"):
            self.assertNotIn(forbidden, text)

    def test_application_has_no_ui_or_file_io_dependency(self):
        text = (ROOT / "app" / "GameApplication.ps1").read_text(encoding="utf-8-sig")
        for forbidden in ("System.Windows", "Get-Content", "WriteAllText", "MessageBox"):
            self.assertNotIn(forbidden, text)

    def test_storage_has_no_gameplay_or_ui_dependency(self):
        text = (ROOT / "infra" / "Storage.ps1").read_text(encoding="utf-8-sig")
        for forbidden in ("System.Windows", "Get-BaseDamage", "Get-PetBonus"):
            self.assertNotIn(forbidden, text)

    def test_xaml_views_expose_required_contracts(self):
        panel = (ROOT / "ui" / "panel.xaml").read_text(encoding="utf-8-sig")
        overlay = (ROOT / "ui" / "overlay.xaml").read_text(encoding="utf-8-sig")
        dialog = (ROOT / "ui" / "dialog.xaml").read_text(encoding="utf-8-sig")
        for name in ("AdventureTabs", "MineWarehouseValue", "MineWarehouse", "AttackDamageText", "EquipmentFilter", "InventoryListBox", "KeyboardTreePanel", "UpgradePetButton", "StartupCheckBox"):
            self.assertIn(f'x:Name="{name}"', panel)
        for name in ("Hamster", "TargetImage", "ImpactLayer", "RunReportButton", "WarehouseText", "ToastBorder"):
            self.assertIn(f'x:Name="{name}"', overlay)
        self.assertIn("<Viewbox", overlay)
        self.assertNotIn('x:Name="Toolbar"', overlay)
        self.assertNotIn('x:Name="PauseButton"', overlay)
        for name in ("DialogTitle", "DialogMessage", "DialogConfirmButton", "DialogCancelButton"):
            self.assertIn(f'x:Name="{name}"', dialog)
        self.assertNotIn("EquipSelectedButton", panel)
        self.assertNotIn("SellSelectedButton", panel)

    def test_composition_root_loads_modules_and_external_views(self):
        text = (ROOT / "DeepDesk.ps1").read_text(encoding="utf-8-sig")
        for path in ("config\\Config.ps1", "domain\\Rules.ps1", "app\\GameApplication.ps1", "infra\\Storage.ps1"):
            self.assertIn(path, text)
        for path in ("ui\\overlay.xaml", "ui\\panel.xaml", "ui\\dialog.xaml"):
            self.assertIn(path, text)

    def test_overlay_is_resolution_and_dpi_adaptive(self):
        text = (ROOT / "DeepDesk.ps1").read_text(encoding="utf-8-sig")
        for contract in (
            "Get-ResponsiveOverlayScale",
            "Update-OverlayResponsiveLayout",
            "Set-OverlayPhysicalPosition",
            "PointFromScreen",
            "GetWorkAreaForPoint",
        ):
            self.assertIn(contract, text)
        self.assertNotIn("PrimaryScreen.WorkingArea", text)

    def test_startup_registration_and_direct_hamster_drag_contracts(self):
        text = (ROOT / "DeepDesk.ps1").read_text(encoding="utf-8-sig")
        portable = (ROOT / "launcher" / "PortableLauncher.cs").read_text(encoding="utf-8-sig")
        single = (ROOT / "launcher" / "SingleFileLauncher.cs").read_text(encoding="utf-8-sig")
        self.assertIn("CurrentVersion\\Run", text)
        self.assertIn("Set-StartupRegistration", text)
        self.assertIn("if ($SmokeTest) { return }", text)
        self.assertIn("foreach($surface in @($Hamster))", text)
        self.assertNotIn("ToolbarShown", text)
        self.assertNotIn('FloorText.Text="B$', text)
        self.assertIn("DEEPDESK_LAUNCHER_PATH", portable)
        self.assertIn("DEEPDESK_LAUNCHER_PATH", single)


if __name__ == "__main__":
    unittest.main()
