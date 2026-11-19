#!/usr/bin/env python3
"""Audit locally emitted Claude/Codex/Grok/OpenCode model IDs against JP's bundled pricing table.

OpenCode is read from its SQLite store (`opencode.db`) with a read-only connection, projecting ONLY
the assistant-message `modelID` / `providerID` fields and the session `model` column — never message
content, prompts, tokens, paths, or auth data.

Claude ids are checked as the app prices them: a turn whose `usage.speed` is "fast" is reported under
its `-fast-mode` accounting id (`ModelIdentity.fastModeID`), because that row, not the standard one,
bills it. A US-only inference turn (`usage.inference_geo` "us") needs no row of its own: the app prices
it as the row above times the `rate_multipliers` factor, so the script checks that row.

OpenCode ids are checked as emitted. The `-opencode`/`-zen`/`-go`/`-peak` accounting ids the app derives
from them at parse time are guarded in Swift by `OpenCodeGoProviderTests`, which enumerates every
routed id `OpenCodeGateway.normalizedModelID` can return; this script does not re-implement that routing.
"""

from __future__ import annotations

import argparse
import base64
import glob
import json
import os
import re
import sqlite3
from pathlib import Path


SCANNED_FILES: dict[str, int] = {}
OPENCODE_TABLES_READ: list[str] = []


ALIASES: dict[str, str] = {}

# Mirrors `OpenCodeBrand.needle` and `MuseSparkProvider.isSparkModelObject`: an OpenCode assistant row
# reaches a JP row only through a gateway row (by providerID) or a model-brand row (by model id).
OPENCODE_GATEWAYS_JP_INGESTS = {"opencode", "opencode-go"}
OPENCODE_BRAND_NEEDLES = ("mimo", "nemotron", "deepseek", "big-pickle", "muse-spark", "muse-wonder")


def undecorated(model: str) -> str:
    """Mirrors `ModelIdentity.undecorated`: vendor prefix, `[1m]`, and snapshot date removed.

    The prefix is the text through the LAST `/`, unless the id ends in `/` (`withoutVendorPrefix`).
    """
    slash = model.rfind("/")
    value = model[slash + 1 :] if 0 <= slash < len(model) - 1 else model
    value = value[:-4] if value.endswith("[1m]") else value
    return re.sub(r"-(?:[0-9]{8}|[0-9]{4}-[0-9]{2}-[0-9]{2})$", "", value)


def fast_mode_id(model: str) -> str:
    """Mirrors `ModelIdentity.fastModeID`: the undecorated id plus `-fast-mode`."""
    return undecorated(model) + "-fast-mode"


def is_free_tier(model: str) -> bool:
    """Mirrors `ModelIdentity.isFreeTier`: a free-tier id is deliberately unpriced, never a gap."""
    return model.endswith("-free") or undecorated(model).endswith("-free")


def normalized(model: str) -> str:
    """Mirrors `ModelIdentity.pricingID` (undecorated, lowercased, then aliased), reading the SAME
    `aliases` map as the app and website."""
    value = undecorated(model).lower()
    return ALIASES.get(value, value)


def opencode_row_ingests(gateway: str, model: str) -> bool:
    lower = model.lower()
    if gateway in OPENCODE_GATEWAYS_JP_INGESTS:
        return True
    if any(needle in lower for needle in OPENCODE_BRAND_NEEDLES):
        return True
    return gateway == "meta" and "spark" in lower


def json_lines(pattern: str):
    SCANNED_FILES[pattern] = 0
    for path in glob.iglob(os.path.expanduser(pattern), recursive=True):
        SCANNED_FILES[pattern] += 1
        try:
            with open(path, encoding="utf-8", errors="ignore") as handle:
                for line in handle:
                    try:
                        yield path, json.loads(line)
                    except (json.JSONDecodeError, UnicodeDecodeError):
                        continue
        except OSError as error:
            raise RuntimeError("A local model source could not be read") from error


def codex_models(root: str) -> tuple[set[str], int, int]:
    models: set[str] = set()
    pattern = str(Path(os.path.expanduser(root)) / "**" / "rollout-*.jsonl")
    by_file: dict[str, dict[str, object]] = {}
    for path, obj in json_lines(pattern):
        state = by_file.setdefault(path, {"models": set(), "early": 0})
        payload = obj.get("payload") or {}
        if obj.get("type") in {"session_meta", "turn_context"}:
            model = payload.get("model")
            if not model:
                model = ((payload.get("collaboration_mode") or {}).get("settings") or {}).get("model")
            if isinstance(model, str) and model:
                models.add(model)
                state_models = state["models"]
                assert isinstance(state_models, set)
                state_models.add(model)
        elif obj.get("type") == "event_msg" and payload.get("type") == "token_count":
            if not state["models"]:
                state["early"] = int(state["early"]) + 1
    early_resolved = sum(int(state["early"]) for state in by_file.values() if state["models"])
    permanently_unknown = sum(int(state["early"]) for state in by_file.values() if not state["models"])
    return models, early_resolved, permanently_unknown


def claude_models(root: str) -> set[str]:
    models: set[str] = set()
    pattern = str(Path(os.path.expanduser(root)) / "**" / "*.jsonl")
    for _, obj in json_lines(pattern):
        message = obj.get("message") or {}
        model = message.get("model")
        if isinstance(model, str) and model and model != "<synthetic>":
            fast = (message.get("usage") or {}).get("speed") == "fast"
            models.add(fast_mode_id(model) if fast else model)
    return models


def cursor_models(path: str) -> set[str]:
    """Model ids from JP's opt-in Cursor capture. Decodes `model` or `model_b64` only."""
    models: set[str] = set()
    file = Path(os.path.expanduser(path))
    if not file.is_file():
        return models
    SCANNED_FILES[str(file)] = 1
    try:
        handle = open(file, encoding="utf-8", errors="ignore")
    except OSError as error:
        raise RuntimeError("A local model source could not be read") from error
    with handle:
        for line in handle:
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            model = obj.get("model")
            if not isinstance(model, str) or not model:
                encoded = obj.get("model_b64")
                if isinstance(encoded, str):
                    try:
                        model = base64.b64decode(encoded).decode("utf-8")
                    except (ValueError, UnicodeDecodeError):
                        model = None
            if isinstance(model, str) and model:
                models.add(model)
    return models


def grok_models(root: str) -> set[str]:
    models: set[str] = set()
    pattern = str(Path(os.path.expanduser(root)) / "**" / "updates.jsonl")
    for _, obj in json_lines(pattern):
        update = ((obj.get("params") or {}).get("update") or {})
        model_usage = ((update.get("usage") or {}).get("modelUsage") or {})
        if isinstance(model_usage, dict):
            models.update(model for model in model_usage if isinstance(model, str) and model)
    return models


def opencode_models(root: str) -> tuple[dict[str, set[str]], set[str]]:
    """(gateway providerID -> model ids) from assistant messages, plus every model id seen on a
    session row. Identifiers only; the connection is read-only and never writes or checkpoints."""
    by_gateway: dict[str, set[str]] = {}
    session_models: set[str] = set()
    db = Path(os.path.expanduser(root)) / "opencode.db"
    if not db.is_file():
        return by_gateway, session_models
    try:
        conn = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    except sqlite3.Error as error:
        raise RuntimeError("OpenCode model source could not be read completely") from error
    try:
        tables = {name for (name,) in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        # OpenCode's session-v2 store writes turns to `session_message` (model under `$.model`) and
        # stops appending to `message`, so both are read, mirroring `OpenCodeStore.assistantProjection`.
        selects = []
        if "message" in tables:
            selects.append(
                """
                SELECT lower(coalesce(json_extract(data, '$.providerID'), '')), json_extract(data, '$.modelID')
                FROM message WHERE json_extract(data, '$.role') = 'assistant'
                """
            )
        if "session_message" in tables:
            selects.append(
                """
                SELECT lower(coalesce(json_extract(data, '$.model.providerID'), '')),
                       json_extract(data, '$.model.id')
                FROM session_message WHERE type = 'assistant'
                """
            )
        rows = (
            conn.execute("SELECT DISTINCT * FROM (" + " UNION ALL ".join(selects) + ")").fetchall()
            if selects
            else []
        )
        OPENCODE_TABLES_READ.extend(sorted(tables & {"message", "session_message"}))
        for gateway, model in rows:
            if isinstance(model, str) and model:
                by_gateway.setdefault(gateway or "(none)", set()).add(model)
        for (raw,) in conn.execute("SELECT DISTINCT model FROM session").fetchall():
            if not isinstance(raw, str) or not raw:
                continue
            try:
                parsed = json.loads(raw)
                model = parsed.get("id") if isinstance(parsed, dict) else None
            except json.JSONDecodeError:
                model = raw
            if isinstance(model, str) and model:
                session_models.add(model)
    except sqlite3.Error as error:
        raise RuntimeError("OpenCode model source could not be read completely") from error
    finally:
        conn.close()
    return by_gateway, session_models


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default=".")
    parser.add_argument("--claude-root", default="~/.claude/projects")
    parser.add_argument("--codex-root", default="~/.codex/sessions")
    parser.add_argument("--grok-root", default="~/.grok/sessions")
    parser.add_argument("--opencode-root", default="~/.local/share/opencode")
    parser.add_argument(
        "--cursor-capture",
        default="~/Library/Application Support/JPtheCat/cursor-usage.jsonl",
    )
    args = parser.parse_args()

    price_path = Path(args.repo).resolve() / "mac/Sources/JPtheCatCore/Resources/pricing-default.json"
    table = json.loads(price_path.read_text(encoding="utf-8"))
    prices = set(table["models"])
    ALIASES.update(table.get("aliases") or {})
    if not ALIASES:
        raise RuntimeError("pricing-default.json has no aliases map; the audit would under-resolve ids")
    codex, early_resolved, permanently_unknown = codex_models(args.codex_root)
    claude = claude_models(args.claude_root)
    grok = grok_models(args.grok_root)
    cursor = cursor_models(args.cursor_capture)
    opencode_by_gateway, opencode_sessions = opencode_models(args.opencode_root)
    opencode = set().union(*opencode_by_gateway.values(), opencode_sessions)
    opencode_ingested = {
        model
        for gateway, models in opencode_by_gateway.items()
        for model in models
        if opencode_row_ingests(gateway, model)
    } | {model for model in opencode_sessions if opencode_row_ingests("", model)}

    def missing(models: set[str]) -> list[str]:
        return sorted(
            model
            for model in models
            if not is_free_tier(model) and model not in prices and normalized(model) not in prices
        )

    result = {
        "claude": {"emitted_models": sorted(claude), "missing_prices": missing(claude)},
        "codex": {
            "emitted_models": sorted(codex),
            "missing_prices": missing(codex),
            "early_token_events_later_attributable": early_resolved,
            "token_events_without_any_same_file_model": permanently_unknown,
        },
        "grok": {"emitted_models": sorted(grok), "missing_prices": missing(grok)},
        "cursor": {"emitted_models": sorted(cursor), "missing_prices": missing(cursor)},
        "opencode": {
            "emitted_models": sorted(opencode),
            "emitted_models_by_gateway": {
                gateway: sorted(models) for gateway, models in sorted(opencode_by_gateway.items())
            },
            "free_tier_models_deliberately_unpriced": sorted(m for m in opencode if is_free_tier(m)),
            # Ids from gateways no JP row reads (for example a local oMLX server) never reach a
            # dashboard row, so they are listed for review but are not pricing gaps.
            "models_no_jp_row_ingests": sorted(opencode - opencode_ingested),
            "missing_prices": missing(opencode_ingested),
        },
        "pricing_models": len(prices),
        "pricing_aliases": len(ALIASES),
        "scan_evidence": {
            "jsonl_files_read": sum(SCANNED_FILES.values()),
            "opencode_database_read": (Path(os.path.expanduser(args.opencode_root)) / "opencode.db").is_file(),
            "opencode_message_tables_read": OPENCODE_TABLES_READ,
            "emitted_model_counts": {
                "claude": len(claude),
                "codex": len(codex),
                "grok": len(grok),
                "opencode": len(opencode),
                "cursor": len(cursor),
            },
        },
    }
    print(json.dumps(result, indent=2))
    has_missing = any(
        result[provider]["missing_prices"]
        for provider in ("claude", "codex", "grok", "opencode", "cursor")
    )
    if not any((claude, codex, grok, opencode, cursor)):
        return 2  # An empty audit is not a coverage pass.
    return 1 if has_missing else 0


if __name__ == "__main__":
    raise SystemExit(main())
