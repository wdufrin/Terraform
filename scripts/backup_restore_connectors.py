#!/usr/bin/env python3
"""
Gemini Enterprise / Discovery Engine Connector Backup & Restore Tool

Exports live data connectors to:
  * a raw JSON backup (--export-json),
  * a tfvars file for this module (--export-tfvars),
  * a `terraform import` shell script (--export-import-script), and/or
  * Terraform 1.5+ import blocks (--export-import-blocks).

It can read from the live API (default) or regenerate everything offline from a previous
JSON backup (--input-json), which is the disaster-recovery path.

Each connector is read with GET .../collections/<id>/dataConnector - the same endpoint the
Terraform provider uses on refresh - so the exported entities match what `terraform plan`
compares against.

Known limits (reported as warnings, never silently "fixed"):
  * The API does not return credentials (client secrets, refresh tokens). Add them through
    connector_secret_refs / connector_secrets before the first `terraform apply`.
  * Connectors this module cannot represent are skipped: unsupported data sources, Workspace
    connectors that are not dataSourceVersion 2, and connectors with no entities.
"""

import argparse
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Dict, List, Optional, Tuple

WORKSPACE_SOURCES = {"google_drive", "google_calendar", "google_mail", "google_chat"}

# Must stay in sync with the data_source validation of var.third_party_connectors in variables.tf.
THIRD_PARTY_SOURCES = {
    "jira", "confluence", "github", "slack", "servicenow", "sharepoint",
    "outlook", "onedrive", "teams", "azure_active_directory", "custom_mcp",
}


class BackupFormatError(ValueError):
    """Raised when a --input-json backup file does not have the expected structure."""


# ---------------------------------------------------------------------------
# API access
# ---------------------------------------------------------------------------

def get_access_token() -> str:
    """Return GOOGLE_OAUTH_ACCESS_TOKEN, or a token from `gcloud auth print-access-token`."""
    token = os.environ.get("GOOGLE_OAUTH_ACCESS_TOKEN")
    if token:
        return token.strip()
    try:
        proc = subprocess.run(
            ["gcloud", "auth", "print-access-token"],
            check=True,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        sys.exit("Error: gcloud is not installed and GOOGLE_OAUTH_ACCESS_TOKEN is not set.")
    except subprocess.CalledProcessError as err:
        sys.exit(f"Error obtaining gcloud access token: {err.stderr.strip() or err}")
    return proc.stdout.strip()


def get_api_endpoint(location: str) -> str:
    if location == "global":
        return "https://discoveryengine.googleapis.com"
    return f"https://{location}-discoveryengine.googleapis.com"


def _get_json(url: str, project_id: str, token: str) -> Tuple[int, Dict[str, Any]]:
    """GET a URL and return (status, decoded JSON). Non-404 HTTP errors terminate the program."""
    req = urllib.request.Request(
        url,
        headers={"Authorization": f"Bearer {token}", "X-Goog-User-Project": project_id},
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as err:
        if err.code == 404:
            return 404, {}
        body = err.read().decode("utf-8", errors="replace")
        sys.exit(f"HTTP {err.code} from {url}: {body}")
    except urllib.error.URLError as err:
        sys.exit(f"Network error calling {url}: {err.reason}")


def fetch_connectors(project_id: str, location: str, token: str) -> List[Dict[str, Any]]:
    """Return [{collectionId, displayName, dataConnector}] for every collection with a connector."""
    base = f"{get_api_endpoint(location)}/v1alpha/projects/{project_id}/locations/{location}"
    collections: List[Dict[str, Any]] = []
    page_token: Optional[str] = None
    while True:
        query = {"pageSize": "100"}
        if page_token:
            query["pageToken"] = page_token
        _, data = _get_json(f"{base}/collections?{urllib.parse.urlencode(query)}", project_id, token)
        collections.extend(data.get("collections", []))
        page_token = data.get("nextPageToken")
        if not page_token:
            break

    entries: List[Dict[str, Any]] = []
    for col in collections:
        collection_id = col.get("name", "").split("/")[-1]
        if not collection_id:
            continue
        status, connector = _get_json(f"{base}/collections/{collection_id}/dataConnector", project_id, token)
        if status == 404 or not connector:
            continue  # Collection without a data connector (e.g. a plain data store collection).
        entries.append({
            "collectionId": collection_id,
            "displayName": col.get("displayName") or collection_id,
            "dataConnector": connector,
        })
    return entries


def load_backup(path: str) -> List[Dict[str, Any]]:
    """Load a JSON backup written by --export-json and validate its structure."""
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, list):
        raise BackupFormatError(f"{path}: expected a JSON list of connector entries, got {type(data).__name__}")
    for index, entry in enumerate(data):
        if not isinstance(entry, dict):
            raise BackupFormatError(f"{path}: entry {index} is not an object")
        if not isinstance(entry.get("collectionId"), str) or not entry["collectionId"]:
            raise BackupFormatError(f"{path}: entry {index} has no collectionId")
        if not isinstance(entry.get("dataConnector"), dict):
            raise BackupFormatError(f"{path}: entry {index} ({entry['collectionId']}) has no dataConnector object")
    return data


# ---------------------------------------------------------------------------
# Conversion to module inputs
# ---------------------------------------------------------------------------

def _stringify_scalar(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def _scalar_map(values: Dict[str, Any], collection_id: str, field: str, warnings: List[str]) -> Dict[str, str]:
    """Convert a flat dict to map(string). Nested values cannot be represented, so they are
    reported instead of being dropped silently."""
    out: Dict[str, str] = {}
    for key, value in values.items():
        if value is None:
            continue
        if isinstance(value, (dict, list)):
            warnings.append(
                f"{collection_id}: {field}.{key} is a nested object that this module's map(string) input cannot hold; "
                "it was NOT exported - add it manually if the connector needs it."
            )
            continue
        out[key] = _stringify_scalar(value)
    return out


def _params_to_inputs(params: Dict[str, Any]) -> Tuple[Dict[str, str], Optional[str]]:
    """Return (params map, json_params). Nested values cannot live in map(string), so the whole
    object is passed through json_params instead, preserving the original JSON types."""
    if any(isinstance(v, (dict, list)) for v in params.values()):
        return {}, json.dumps(params, sort_keys=True)
    return {k: _stringify_scalar(v) for k, v in params.items() if v is not None}, None


def _tf_key(collection_id: str, used: set, warnings: List[str]) -> str:
    key = collection_id.replace("-", "_").replace(".", "_")
    if key[0].isdigit():
        key = f"c_{key}"
    candidate, n = key, 2
    while candidate in used:
        candidate = f"{key}_{n}"
        n += 1
    if candidate != key:
        warnings.append(f"{collection_id}: Terraform key '{key}' already used; using '{candidate}'.")
    used.add(candidate)
    return candidate


def convert_entries(project_id: str, location: str, entries: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Convert connector entries into module inputs plus import commands/blocks."""
    connectors_1p: Dict[str, Any] = {}
    connectors_3p: Dict[str, Any] = {}
    import_commands: List[str] = []
    import_blocks: List[str] = []
    warnings: List[str] = []
    used_keys: set = set()

    for entry in entries:
        collection_id = entry["collectionId"]
        display_name = entry.get("displayName") or collection_id
        dc = entry["dataConnector"]
        data_source = dc.get("dataSource", "")
        version = dc.get("dataSourceVersion")
        modes = list(dc.get("connectorModes") or [])
        action_config = dc.get("actionConfig") or {}
        bap_config = dc.get("bapConfig") or {}
        entities = [e for e in (dc.get("entities") or []) if e.get("entityName")]

        if data_source in WORKSPACE_SOURCES:
            if version is not None and int(version) != 2:
                warnings.append(f"{collection_id}: skipped - Workspace connector with dataSourceVersion {version}; this module only manages version 2.")
                continue
            if len(entities) > 1:
                warnings.append(f"{collection_id}: has {len(entities)} entities; this module manages one Workspace entity, so only '{entities[0]['entityName']}' is exported.")
            key = _tf_key(collection_id, used_keys, warnings)
            connectors_1p[key] = {
                "collection_id": collection_id,
                "collection_display_name": display_name,
                "data_source": data_source,
                "data_source_version": 2,
                "entity_name": entities[0]["entityName"] if entities else data_source,
                "refresh_interval": dc.get("refreshInterval", "0s"),
                "auto_run_disabled": bool(dc.get("autoRunDisabled", False)),
                "json_params": json.dumps(dc.get("params") or {}, sort_keys=True),
                "connector_modes": modes,
                "create_bap_connection": bool(action_config.get("createBapConnection", False)),
                "action_params": _scalar_map(action_config.get("actionParams") or {}, collection_id, "actionParams", warnings),
                "supported_bap_modes": list(bap_config.get("supportedConnectorModes") or []),
                "enabled_actions": list(bap_config.get("enabledActions") or []),
            }
            address = f'google_discovery_engine_data_connector.core_1p_connectors["{key}"]'
        else:
            if data_source not in THIRD_PARTY_SOURCES:
                warnings.append(f"{collection_id}: skipped - data source '{data_source}' is not supported by this module.")
                continue
            if not entities:
                warnings.append(f"{collection_id}: skipped - the connector has no entities, which this module requires.")
                continue
            params, json_params = _params_to_inputs(dc.get("params") or {})
            if json_params is not None:
                warnings.append(f"{collection_id}: params contain nested objects; exported through json_params to preserve their JSON types.")
            action_params = _scalar_map(action_config.get("actionParams") or {}, collection_id, "actionParams", warnings)
            entity_params = {e["entityName"]: json.dumps(e["params"], sort_keys=True)
                             for e in entities if isinstance(e.get("params"), dict) and e["params"]}
            destination_configs = []
            for item in dc.get("destinationConfigs") or []:
                cfg: Dict[str, Any] = {
                    "key": item.get("key", "url"),
                    "destinations": [{"host": d.get("host", ""), "port": d.get("port")} for d in item.get("destinations") or []],
                }
                if item.get("params"):
                    cfg["params"] = json.dumps(item["params"], sort_keys=True)
                destination_configs.append(cfg)
            key = _tf_key(collection_id, used_keys, warnings)
            connectors_3p[key] = {
                "enabled": True,
                "collection_id": collection_id,
                "collection_display_name": display_name,
                "data_source": data_source,
                "data_source_version": version if version is not None else 1,
                "entities": [e["entityName"] for e in entities],
                "entity_params": entity_params,
                "refresh_interval": dc.get("refreshInterval", "86400s"),
                "auto_run_disabled": bool(dc.get("autoRunDisabled", True)),
                "connector_modes": modes,
                "create_bap_connection": bool(action_config.get("createBapConnection", False)),
                "supported_bap_modes": list(bap_config.get("supportedConnectorModes") or []),
                "enabled_actions": list(bap_config.get("enabledActions") or []),
                "params": params,
                "json_params": json_params,
                "action_params": action_params,
                "destination_configs": destination_configs,
            }
            address = f'google_discovery_engine_data_connector.third_party_connectors["{key}"]'

        resource_id = f"projects/{project_id}/locations/{location}/collections/{collection_id}/dataConnector"
        import_commands.append(f"terraform import '{address}' {resource_id}")
        import_blocks.append(f'import {{\n  to = {address}\n  id = "{resource_id}"\n}}')

    return {
        "connectors_1p": connectors_1p,
        "connectors_3p": connectors_3p,
        "import_commands": import_commands,
        "import_blocks": import_blocks,
        "warnings": warnings,
    }


# ---------------------------------------------------------------------------
# HCL rendering
# ---------------------------------------------------------------------------

def hcl_string(value: str) -> str:
    """Quote a string as an HCL literal. JSON escaping is valid HCL, but HCL also treats
    '${' and '%{' as template sequences, so those are escaped too."""
    return json.dumps(value).replace("${", "$${").replace("%{", "%%{")


def hcl_value(value: Any, indent: int) -> str:
    pad = "  " * indent
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return hcl_string(value)
    if isinstance(value, list):
        if not value:
            return "[]"
        if all(not isinstance(v, (dict, list)) for v in value):
            return "[" + ", ".join(hcl_value(v, indent) for v in value) + "]"
        inner = ",\n".join(f"{pad}  {hcl_value(v, indent + 1)}" for v in value)
        return f"[\n{inner}\n{pad}]"
    if isinstance(value, dict):
        if not value:
            return "{}"
        lines = [f"{pad}  {hcl_string(k)} = {hcl_value(v, indent + 1)}" for k, v in value.items()]
        return "{\n" + "\n".join(lines) + f"\n{pad}}}"
    raise TypeError(f"Cannot render {type(value).__name__} as HCL")


def render_hcl_tfvars(project_id: str, location: str, converted: Dict[str, Any]) -> str:
    lines = [
        "# Auto-generated by scripts/backup_restore_connectors.py",
        "#",
        "# BEFORE THE FIRST APPLY:",
        "#   1. The API never returns credentials. Add client secrets / tokens through",
        "#      connector_secret_refs (preferred) or connector_secrets, or Terraform will send",
        "#      these params without them.",
        "#   2. Run `terraform plan` and confirm it shows `0 to destroy`.",
        f"project_id           = {hcl_string(project_id)}",
        f"location             = {hcl_string(location)}",
        "append_random_suffix = false # deterministic collection IDs, required for import",
        'deletion_policy      = "PREVENT"',
        "",
        f"connectors = {hcl_value(converted['connectors_1p'], 0)}",
        "",
        f"third_party_connectors = {hcl_value(converted['connectors_3p'], 0)}",
        "",
    ]
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Back up, export, and restore Discovery Engine / Gemini Enterprise connectors."
    )
    parser.add_argument("--project", required=True, help="GCP project ID")
    parser.add_argument("--location", default="global", choices=["global", "us", "eu"], help="Discovery Engine location")
    parser.add_argument("--input-json", help="Regenerate outputs from an existing JSON backup instead of calling the API")
    parser.add_argument("--export-tfvars", help="File to write the generated tfvars to")
    parser.add_argument("--export-json", help="File to write the raw JSON backup to")
    parser.add_argument("--export-import-script", help="File to write a `terraform import` shell script to")
    parser.add_argument("--export-import-blocks", help="File to write Terraform 1.5+ import blocks to")
    args = parser.parse_args()

    if args.input_json:
        try:
            entries = load_backup(args.input_json)
        except BackupFormatError as err:
            sys.exit(f"Invalid backup file: {err}")
        print(f"Loaded {len(entries)} connectors from {args.input_json}.")
    else:
        token = get_access_token()
        print(f"Discovering data connectors for {args.project} in '{args.location}'...")
        entries = fetch_connectors(args.project, args.location, token)
        print(f"Found {len(entries)} data connectors.")

    converted = convert_entries(args.project, args.location, entries)
    print(f"Exported {len(converted['connectors_1p'])} Workspace and {len(converted['connectors_3p'])} third-party connectors.")
    for warning in converted["warnings"]:
        print(f"WARNING: {warning}", file=sys.stderr)

    if args.export_json:
        with open(args.export_json, "w", encoding="utf-8") as handle:
            json.dump(entries, handle, indent=2)
        print(f"Wrote raw backup JSON to {args.export_json}")

    if args.export_tfvars:
        with open(args.export_tfvars, "w", encoding="utf-8") as handle:
            handle.write(render_hcl_tfvars(args.project, args.location, converted))
        print(f"Wrote Terraform tfvars to {args.export_tfvars}")

    if args.export_import_script:
        with open(args.export_import_script, "w", encoding="utf-8") as handle:
            handle.write("#!/bin/bash\nset -euo pipefail\n\n")
            for cmd in converted["import_commands"]:
                handle.write(f"{cmd}\n")
        os.chmod(args.export_import_script, 0o755)
        print(f"Wrote import shell script to {args.export_import_script}")

    if args.export_import_blocks:
        with open(args.export_import_blocks, "w", encoding="utf-8") as handle:
            handle.write("\n\n".join(converted["import_blocks"]) + "\n")
        print(f"Wrote Terraform 1.5+ import blocks to {args.export_import_blocks}")


if __name__ == "__main__":
    main()
