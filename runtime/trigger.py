from __future__ import annotations

from dataclasses import dataclass

CANONICAL_TRIGGER_TYPES = {"manual", "schedule", "event_stub"}


@dataclass(frozen=True)
class TriggerContext:
    trigger_type: str


def normalize_trigger(trigger_type: str) -> TriggerContext:
    normalized = trigger_type.strip().lower()
    if normalized not in CANONICAL_TRIGGER_TYPES:
        raise ValueError(f"unsupported trigger_type: {trigger_type}")
    return TriggerContext(trigger_type=normalized)
