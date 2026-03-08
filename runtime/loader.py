from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
from typing import Any, Dict, Mapping


@dataclass(frozen=True)
class LoaderContract:
    task_package_ref: str
    runtime_bundle_ref: str
    trigger_type: str
    requested_operator: str


def load_contract(raw: Mapping[str, str]) -> LoaderContract:
    required = (
        "task_package_ref",
        "runtime_bundle_ref",
        "trigger_type",
        "requested_operator",
    )
    missing = [key for key in required if not str(raw.get(key, "")).strip()]
    if missing:
        raise ValueError(f"missing required loader fields: {', '.join(missing)}")

    return LoaderContract(
        task_package_ref=str(raw["task_package_ref"]).strip(),
        runtime_bundle_ref=str(raw["runtime_bundle_ref"]).strip(),
        trigger_type=str(raw["trigger_type"]).strip(),
        requested_operator=str(raw["requested_operator"]).strip(),
    )


REQUIRED_TASK_KEYS = (
    "task_id",
    "task_type",
    "operator",
    "bundle",
    "contract",
    "input",
    "output",
)

REQUIRED_BUNDLE_KEYS = (
    "bundle_id",
    "bundle_version",
    "executor",
    "resources",
    "policy",
)


def _parse_yaml(text: str) -> Dict[str, Any]:
    # Prefer PyYAML when available. Fall back to JSON-only parsing so this
    # runtime still works without extra dependencies for minimal sample tasks.
    try:
        import yaml  # type: ignore

        loaded = yaml.safe_load(text)
    except ModuleNotFoundError:
        loaded = json.loads(text)

    if not isinstance(loaded, dict):
        raise ValueError("yaml root must be a mapping")
    return loaded


def load_yaml_file(path: Path) -> Dict[str, Any]:
    if not path.exists():
        raise FileNotFoundError(f"yaml file not found: {path}")
    if not path.is_file():
        raise ValueError(f"yaml path is not a file: {path}")
    return _parse_yaml(path.read_text(encoding="utf-8"))


def _validate_required_keys(kind: str, data: Mapping[str, Any], required: tuple[str, ...]) -> None:
    missing = [key for key in required if key not in data]
    if missing:
        raise ValueError(f"{kind} is missing required keys: {', '.join(missing)}")


def load_task_yaml(path: Path) -> Dict[str, Any]:
    data = load_yaml_file(path)
    _validate_required_keys("task.yaml", data, REQUIRED_TASK_KEYS)
    return data


def load_bundle_yaml(path: Path) -> Dict[str, Any]:
    data = load_yaml_file(path)
    _validate_required_keys("bundle.yaml", data, REQUIRED_BUNDLE_KEYS)
    return data