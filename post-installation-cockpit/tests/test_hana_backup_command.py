import json
import unittest
from pathlib import Path

import app


def load_backup_script() -> app.ScriptDefinition:
    catalog_path = Path(__file__).parents[1] / "scripts_catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    scripts = app.load_scripts(
        {
            "default_timeout_seconds": catalog["default_timeout_seconds"],
            "scripts": catalog["scripts"],
        }
    )
    return next(script for script in scripts if script.script_id == "hana_backup_setup")


class HanaBackupCommandTests(unittest.TestCase):
    def test_uses_existing_remote_script(self) -> None:
        script = load_backup_script()

        self.assertEqual(
            script.path,
            "/global/sapcd/scripts/HANA/hanaSetupBackup_v5.sh",
        )

    def test_uses_default_password(self) -> None:
        script = load_backup_script()
        parameter_values = {
            "sid": "S31",
            "ip": "192.0.2.10",
            "node": "UCCS31BACKUP_HANA",
            "restart_section": "3",
        }

        arguments = app.build_script_arguments(script, parameter_values)

        self.assertEqual(
            arguments,
            [
                "--sid",
                "S31",
                "--ip",
                "192.0.2.10",
                "--node",
                "UCCS31BACKUP_HANA",
                "-j",
                "3",
            ],
        )
        self.assertNotIn("--pass", arguments)


if __name__ == "__main__":
    unittest.main()
