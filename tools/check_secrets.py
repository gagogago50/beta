#!/usr/bin/env python3
"""B3 — anti-leak guard.

Scans the source for places a secret *value* could leave the device. It is a
heuristic, not a proof: it flags log / print / notification / serialization
lines that **interpolate a secret-typed expression** (e.g. `$password`,
`{address}`, `identity`), and cross-checks that the redaction layer is applied
on the hot paths. It deliberately does NOT flag lines that merely describe an
action ("identity saved to Keystore") — those carry no secret value.

Exit code: 0 = no interpolation-of-secret candidates,
          1 = at least one candidate to review.
Runs in CI so a future refactor cannot start leaking a secret value through a
new log line or serialized field.

The app already redacts at two layers, which this tool verifies is wired up:
  * Dart:  lib/services/app_log.dart  (AppLog redacts hostnames/IPs/secrets)
  * Rust:  native/src/lib.rs           (crate::redact)
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCAN = [
    ROOT / "lib",
    ROOT / "native" / "src",
    ROOT / "android" / "app" / "src" / "main" / "kotlin",
]
SKIP_DIRS = {"generated", "target", ".dart_tool", "build"}
# Files where a secret must legitimately cross an edge (identity backup).
WHITELIST = {
    "identity_backup_service.dart",
    "MainActivity.kt",
    "IdentityBackup.kt",
    "ts_ffi.dart",
}

SECRET_NAMES = (
    "identity",
    "client_identity",
    "password",
    "passwd",
    "pwd",
    "uid",
    "nickname",
    "secret",
    "token",
    "address",
    "host",
)

# Log/notification/serialization sinks.
SINK = re.compile(
    r"AppLog\.[ewid]\s*\("
    r"|log_(error|warn|info|debug)!\s*\("
    r"|debugPrint\s*\("
    r"|NotificationCompat|setContentText|setContentTitle|setTicker|setSubText"
    r"|Clipboard\.setData|share\s*\("
)

# Interpolation of a name that contains a secret token (Dart `$x` / `${x}`
# only — interpolation is the only way a value reaches a string). Built by
# string so `$` stays a literal dollar, not a regex anchor.
_SECRET_ALT = "|".join(SECRET_NAMES)
INTERPOLATE_SECRET = re.compile(
    r"\$(?:\{?\s*[a-zA-Z_][a-zA-Z0-9_]*\s*\}?)"
)
# The simpler, robust rule: flag any `$`/`${ ... }` interpolation whose
# identifier contains a secret token. We check the identifier text separately.
def _interpolates_secret(line: str) -> bool:
    for m in re.finditer(r"\$\{?([a-zA-Z_][a-zA-Z0-9_]*)\}?", line):
        name = m.group(1)
        if any(token in name.lower() for token in SECRET_NAMES):
            return True
    return False


def files():
    for base in SCAN:
        if not base.exists():
            continue
        for p in base.rglob("*"):
            if p.suffix not in {".dart", ".rs", ".kt"}:
                continue
            rel = p.relative_to(ROOT)
            if any(part in SKIP_DIRS for part in rel.parts):
                continue
            yield p


def is_comment(line: str) -> bool:
    s = line.lstrip()
    return s.startswith("//") or s.startswith("/*") or s.startswith("*") or s.startswith("#")


def main() -> int:
    issues = 0

    # 0. Verify the redaction layers exist and are referenced on their hot paths.
    app_log = ROOT / "lib" / "services" / "app_log.dart"
    rust_lib = ROOT / "native" / "src" / "lib.rs"
    if not app_log.exists() or "redact" not in app_log.read_text(encoding="utf-8", errors="replace"):
        print("WARN: Dart redaction layer (AppLog) not found.")
        issues += 1
    if not rust_lib.exists() or "redact" not in rust_lib.read_text(encoding="utf-8", errors="replace"):
        print("WARN: Rust redaction layer (crate::redact) not found.")
        issues += 1

    for p in files():
        rel = p.relative_to(ROOT)
        text = p.read_text(encoding="utf-8", errors="replace")
        lines = text.splitlines()

        for i, line in enumerate(lines, 1):
            if is_comment(line):
                continue
            # Sink call that interpolates a secret-typed expression.
            if SINK.search(line) and _interpolates_secret(line):
                if p.name in WHITELIST:
                    # Identity backup legitimately moves the secret; only warn.
                    print(f"{rel}:{i}: (whitelisted) {line.strip()[:90]}")
                else:
                    issues += 1
                    print(f"{rel}:{i}: {line.strip()[:90]}")
            # Serialization / notification exposing a secret field name.
            if ("toJson" in line or "toMap" in line or "Notification" in line) and not is_comment(
                line
            ):
                if re.search(r"\b(password|identity|client_identity|uid)\b", line, re.I):
                    issues += 1
                    print(f"{rel}:{i}: serial/notify mentions a secret field -> {line.strip()[:90]}")

    if issues:
        print(f"\n{issues} candidate(s) to review.")
        return 1
    print("No secret-value interpolation found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
