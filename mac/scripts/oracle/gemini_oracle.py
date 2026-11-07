#!/usr/bin/env python3
"""Independent oracle for GeminiProvider — a second implementation of the exact token mapping in
Sources/JPtheCatCore/Providers/GeminiProvider.swift, used to prove the Swift parser on real data
(golden-corpus equivalence, the same posture as the Codex telescope-vs-oracle check).

Walks ~/.gemini/tmp/<hash>/chats/session-*.json and, for each assistant (`type == "gemini"`) message
with a tokens object, computes the SAME mapping the Swift parser does:
    bill_input  = max(0, input - cached) + tool     # cached ⊆ input; tool at input rate
    cache_read  = cached
    bill_output = output + thoughts                  # thinking billed as output
    ev_total    = bill_input + bill_output + cache_read
Skips zero-total turns; dedupes within a file by message id (keep first) and globally by
(msg_id, sessionId) (keep first — equals the index's keep-max for collision-free real data).

Prints deterministic JSON: per-raw-model {input, output, cacheRead, count} plus grand totals.
Usage: gemini_oracle.py [root]   (default root: ~/.gemini/tmp)
"""
import collections
import glob
import json
import os
import sys


def _int(value):
    return int(value) if isinstance(value, (int, float)) and not isinstance(value, bool) else 0


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.gemini/tmp")
    files = glob.glob(os.path.join(root, "*", "chats", "session-*.json"))

    seen = set()  # (msg_id, session_id) global keep-first
    by_model = collections.defaultdict(lambda: {"input": 0, "output": 0, "cacheRead": 0, "count": 0})
    totals = {"input": 0, "output": 0, "cacheRead": 0, "count": 0}

    for path in sorted(files):
        try:
            with open(path, encoding="utf-8") as handle:
                doc = json.load(handle)
        except (json.JSONDecodeError, OSError, UnicodeDecodeError):
            continue  # transient mid-write / unreadable -> fail closed, like the Swift parser
        if not isinstance(doc, dict):
            continue
        session_id = doc.get("sessionId")
        messages = doc.get("messages")
        if not session_id or not isinstance(messages, list):
            continue

        file_seen = set()
        for message in messages:
            if not isinstance(message, dict) or message.get("type") != "gemini":
                continue
            tokens = message.get("tokens")
            msg_id = message.get("id")
            if not isinstance(tokens, dict) or not msg_id or msg_id in file_seen:
                continue
            file_seen.add(msg_id)
            key = (msg_id, session_id)
            if key in seen:
                continue

            bill_input = max(0, _int(tokens.get("input")) - _int(tokens.get("cached"))) + _int(tokens.get("tool"))
            cache_read = _int(tokens.get("cached"))
            bill_output = _int(tokens.get("output")) + _int(tokens.get("thoughts"))
            if bill_input + bill_output + cache_read == 0:
                continue

            seen.add(key)
            model = message.get("model") or "gemini"
            for bucket in (by_model[model], totals):
                bucket["input"] += bill_input
                bucket["output"] += bill_output
                bucket["cacheRead"] += cache_read
                bucket["count"] += 1

    print(json.dumps({"by_model": dict(by_model), "totals": totals}, sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
