from __future__ import annotations

import argparse
import json
from typing import Any, Dict

from runtime.engine import run_runtime
from runtime.loader import load_contract


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Phase23 minimal AI Task Package Execution entrypoint")
    parser.add_argument("--task-package-ref", required=True)
    parser.add_argument("--runtime-bundle-ref", required=True)
    parser.add_argument("--trigger-type", required=True)
    parser.add_argument("--requested-operator", required=True)
    parser.add_argument("--retry-counter", type=int, default=0)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    raw: Dict[str, Any] = {
        "task_package_ref": args.task_package_ref,
        "runtime_bundle_ref": args.runtime_bundle_ref,
        "trigger_type": args.trigger_type,
        "requested_operator": args.requested_operator,
    }
    contract = load_contract(raw)
    result = run_runtime(contract=contract, retry_counter=args.retry_counter)
    print(json.dumps(result.evidence, ensure_ascii=True, indent=2))
    return 0 if result.ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
