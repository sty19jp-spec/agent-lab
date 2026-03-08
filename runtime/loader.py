from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping


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
