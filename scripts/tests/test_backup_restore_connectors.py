"""Unit tests for scripts/backup_restore_connectors.py (stdlib unittest, no network).

Run from the repository root:
    python3 -m unittest discover -s scripts/tests -v
"""

import importlib.util
import json
import pathlib
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "backup_restore_connectors.py"
_spec = importlib.util.spec_from_file_location("backup_restore_connectors", SCRIPT)
brc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(brc)


def entry(collection_id, data_connector, display_name=None):
    return {"collectionId": collection_id, "displayName": display_name or collection_id, "dataConnector": data_connector}


def jira_connector(**overrides):
    connector = {
        "dataSource": "jira",
        "dataSourceVersion": 3,
        "connectorModes": ["FEDERATED", "ACTIONS"],
        "refreshInterval": "86400s",
        "params": {"instance_id": "cloud-123", "instance_uri": "https://acme.atlassian.net", "static_ip_enabled": False},
        "entities": [
            {"entityName": "project", "params": {"exclusion_filters": {}, "inclusion_filters": {}}, "dataStore": "ds1"},
            {"entityName": "issue", "params": {}, "dataStore": "ds2"},
        ],
        "actionConfig": {"createBapConnection": True, "isActionConfigured": True,
                         "actionParams": {"auth_type": "OAUTH", "instance_uri": "https://acme.atlassian.net"}},
        "bapConfig": {"supportedConnectorModes": ["ACTIONS"], "enabledActions": ["create_issue"]},
        "destinationConfigs": [{"key": "url", "destinations": [{"host": "https://acme.atlassian.net", "port": 443}]}],
    }
    connector.update(overrides)
    return connector


class ConvertEntriesTest(unittest.TestCase):
    def test_workspace_connector_goes_to_core_1p_map_with_matching_import_address(self):
        connector = {
            "dataSource": "google_drive", "dataSourceVersion": 2, "connectorModes": ["FEDERATED", "ACTIONS"],
            "entities": [{"entityName": "google_drive"}],
            "actionConfig": {"createBapConnection": True, "actionParams": {"auth_key": "OAuth", "auth_type": "OAUTH"}},
            "bapConfig": {"supportedConnectorModes": ["ACTIONS"], "enabledActions": ["search_files"]},
        }
        out = brc.convert_entries("acme-prod", "global", [entry("ge-1p-google-drive", connector)])

        self.assertEqual(out["connectors_3p"], {})
        drive = out["connectors_1p"]["ge_1p_google_drive"]
        self.assertEqual(drive["entity_name"], "google_drive")
        self.assertEqual(drive["data_source_version"], 2)
        self.assertEqual(drive["action_params"], {"auth_key": "OAuth", "auth_type": "OAUTH"})
        self.assertEqual(
            out["import_commands"],
            ["terraform import 'google_discovery_engine_data_connector.core_1p_connectors[\"ge_1p_google_drive\"]' "
             "projects/acme-prod/locations/global/collections/ge-1p-google-drive/dataConnector"],
        )

    def test_third_party_connector_exports_entities_entity_params_and_destinations(self):
        out = brc.convert_entries("acme-prod", "eu", [entry("eu-jira_177", jira_connector())])

        jira = out["connectors_3p"]["eu_jira_177"]
        self.assertEqual(jira["entities"], ["project", "issue"])
        # Only non-empty entity params are exported, as JSON object strings.
        self.assertEqual(jira["entity_params"], {"project": json.dumps({"exclusion_filters": {}, "inclusion_filters": {}}, sort_keys=True)})
        self.assertEqual(jira["destination_configs"], [{"key": "url", "destinations": [{"host": "https://acme.atlassian.net", "port": 443}]}])
        self.assertEqual(jira["params"]["static_ip_enabled"], "false")
        self.assertIsNone(jira["json_params"])
        self.assertIn('third_party_connectors["eu_jira_177"]', out["import_commands"][0])

    def test_nested_params_are_exported_via_json_params_with_warning(self):
        connector = jira_connector(params={"tenant_id": "t1", "admin_filter": {"Site": ["a"]}, "eeeu_enabled": True})
        out = brc.convert_entries("p", "global", [entry("sp-1", connector)])

        conn = out["connectors_3p"]["sp_1"]
        self.assertEqual(conn["params"], {})
        self.assertEqual(json.loads(conn["json_params"]), {"tenant_id": "t1", "admin_filter": {"Site": ["a"]}, "eeeu_enabled": True})
        self.assertTrue(any("json_params" in w for w in out["warnings"]))

    def test_nested_action_params_are_reported_not_silently_dropped(self):
        connector = jira_connector(actionConfig={"createBapConnection": True,
                                                 "actionParams": {"auth_type": "OAUTH", "scopes_map": {"a": "b"}}})
        out = brc.convert_entries("p", "global", [entry("jira-1", connector)])

        self.assertEqual(out["connectors_3p"]["jira_1"]["action_params"], {"auth_type": "OAUTH"})
        self.assertTrue(any("actionParams.scopes_map" in w and "NOT exported" in w for w in out["warnings"]))

    def test_unsupported_data_source_is_skipped_with_warning_and_no_import(self):
        connector = jira_connector(dataSource="salesforce")
        out = brc.convert_entries("p", "global", [entry("sfdc-1", connector)])

        self.assertEqual(out["connectors_3p"], {})
        self.assertEqual(out["import_commands"], [])
        self.assertTrue(any("salesforce" in w and "skipped" in w for w in out["warnings"]))

    def test_connector_without_entities_is_skipped_instead_of_fabricating_one(self):
        out = brc.convert_entries("p", "global", [entry("jira-empty", jira_connector(entities=[]))])

        self.assertEqual(out["connectors_3p"], {})
        self.assertTrue(any("no entities" in w for w in out["warnings"]))

    def test_workspace_connector_with_unsupported_version_is_skipped(self):
        connector = {"dataSource": "google_mail", "dataSourceVersion": 1, "connectorModes": ["DATA_INGESTION"],
                     "entities": [{"entityName": "google_mail"}]}
        out = brc.convert_entries("p", "global", [entry("gmail-v1", connector)])

        self.assertEqual(out["connectors_1p"], {})
        self.assertTrue(any("dataSourceVersion 1" in w for w in out["warnings"]))

    def test_colliding_and_numeric_keys_become_unique_valid_identifiers(self):
        out = brc.convert_entries("p", "global", [
            entry("jira-a", jira_connector()),
            entry("jira_a", jira_connector()),
            entry("123-jira", jira_connector()),
        ])

        self.assertEqual(set(out["connectors_3p"]), {"jira_a", "jira_a_2", "c_123_jira"})
        self.assertTrue(any("already used" in w for w in out["warnings"]))


class LoadBackupTest(unittest.TestCase):
    def _write(self, content):
        handle = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
        handle.write(content)
        handle.close()
        self.addCleanup(pathlib.Path(handle.name).unlink)
        return handle.name

    def test_loads_a_valid_backup(self):
        path = self._write(json.dumps([entry("jira-1", jira_connector())]))
        self.assertEqual(brc.load_backup(path)[0]["collectionId"], "jira-1")

    def test_rejects_non_list_document(self):
        path = self._write(json.dumps({"collections": []}))
        with self.assertRaisesRegex(brc.BackupFormatError, "expected a JSON list"):
            brc.load_backup(path)

    def test_rejects_entry_without_collection_id(self):
        path = self._write(json.dumps([{"dataConnector": jira_connector()}]))
        with self.assertRaisesRegex(brc.BackupFormatError, "no collectionId"):
            brc.load_backup(path)

    def test_rejects_entry_without_data_connector_object(self):
        path = self._write(json.dumps([{"collectionId": "jira-1", "dataConnector": "oops"}]))
        with self.assertRaisesRegex(brc.BackupFormatError, "no dataConnector object"):
            brc.load_backup(path)

    def test_truncated_json_raises_decode_error(self):
        path = self._write('[{"collectionId": "jira-1", "dataConnector": {')
        with self.assertRaises(json.JSONDecodeError):
            brc.load_backup(path)


class HclRenderingTest(unittest.TestCase):
    def test_terraform_template_sequences_are_escaped(self):
        # A value copied from the API must never be evaluated as a Terraform template.
        self.assertEqual(brc.hcl_string('${file("/etc/passwd")}'), '"$${file(\\"/etc/passwd\\")}"')
        self.assertEqual(brc.hcl_string("%{ if true }x%{ endif }"), '"%%{ if true }x%%{ endif }"')

    def test_rendered_tfvars_defaults_to_prevent_and_deterministic_ids(self):
        converted = brc.convert_entries("acme-prod", "eu", [entry("jira-1", jira_connector())])
        text = brc.render_hcl_tfvars("acme-prod", "eu", converted)

        self.assertIn('deletion_policy      = "PREVENT"', text)
        self.assertIn("append_random_suffix = false", text)
        self.assertIn('"jira_1" = {', text)
        self.assertIn("BEFORE THE FIRST APPLY", text)

    def test_unrenderable_value_raises_type_error(self):
        with self.assertRaises(TypeError):
            brc.hcl_value(object(), 0)


if __name__ == "__main__":
    unittest.main()
