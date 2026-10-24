#!/usr/bin/env python3
"""Validate device profiles in devices/*.json.

Usage:
    python3 tools/validate_devices.py [devices_dir] [--strict]

Exit code 0 means all profiles are structurally valid. Verified profiles must
also carry BIOS/distro/kernel and measured 35/45 W numbers.

This validator is intentionally dependency-free so it can run in CI.
"""

import argparse
import json
import os
import re
import sys

ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
STATUSES = {"verified", "experimental", "unknown"}


def hex_int(value, default=None):
    try:
        return int(str(value), 0)
    except (TypeError, ValueError):
        return default


def is_hex_byte(value):
    number = hex_int(value)
    return number is not None and 0 <= number <= 255


def validate(path, data, errors, warnings):
    stem = os.path.splitext(os.path.basename(path))[0]

    if not isinstance(data, dict):
        errors.append(f"{path}: top-level JSON must be an object")
        return None

    for key in ("id", "name", "status", "match", "ec", "acpi"):
        if key not in data:
            errors.append(f"{path}: missing required key '{key}'")

    profile_id = data.get("id")
    if not isinstance(profile_id, str) or not ID_RE.match(profile_id):
        errors.append(f"{path}: id must match {ID_RE.pattern}")
    elif profile_id != stem:
        errors.append(f"{path}: id '{profile_id}' must match filename '{stem}'")

    name = data.get("name")
    if not isinstance(name, str) or not name.strip():
        errors.append(f"{path}: name must be a non-empty string")

    status = data.get("status")
    if status not in STATUSES:
        errors.append(f"{path}: status must be one of {sorted(STATUSES)}")

    match = data.get("match")
    if not isinstance(match, dict):
        errors.append(f"{path}: match must be an object")
    else:
        for key in ("dmi_vendor", "dmi_product"):
            value = match.get(key)
            if not isinstance(value, str) or not value.strip():
                errors.append(f"{path}: match.{key} must be a non-empty string")
        board = match.get("dmi_board")
        if board is not None and not isinstance(board, str):
            errors.append(f"{path}: match.dmi_board must be a string")
        bios = match.get("dmi_bios")
        if bios is not None:
            values = bios if isinstance(bios, list) else [bios]
            if not all(isinstance(item, str) and item for item in values):
                errors.append(f"{path}: match.dmi_bios must be a string or list of strings")

    ec = data.get("ec")
    if not isinstance(ec, dict):
        errors.append(f"{path}: ec must be an object")
    else:
        device = ec.get("device")
        if not isinstance(device, str) or not device.startswith("/"):
            errors.append(f"{path}: ec.device must be an absolute path")
        if not is_hex_byte(ec.get("offset")):
            errors.append(f"{path}: ec.offset must be a byte (0x00-0xFF)")

    acpi = data.get("acpi")
    if not isinstance(acpi, dict):
        errors.append(f"{path}: acpi must be an object")
    else:
        wmaa = acpi.get("wmaa_path")
        if not isinstance(wmaa, str) or not (wmaa.startswith("\\") or wmaa.startswith("_SB")):
            errors.append(f"{path}: acpi.wmaa_path must be an ACPI path")
        for key in ("group", "get_command", "set_command"):
            if not is_hex_byte(acpi.get(key)):
                errors.append(f"{path}: acpi.{key} must be a byte (0x00-0xFF)")

    defaults = data.get("defaults")
    if defaults is not None:
        if not isinstance(defaults, dict):
            errors.append(f"{path}: defaults must be an object")
        else:
            if "poll_interval" in defaults:
                interval = defaults["poll_interval"]
                if not isinstance(interval, (int, float)) or not 0.1 <= float(interval) <= 10:
                    errors.append(f"{path}: defaults.poll_interval must be 0.1-10")
            if "notify_app" in defaults and not isinstance(defaults["notify_app"], str):
                errors.append(f"{path}: defaults.notify_app must be a string")

    tested = data.get("tested")
    if tested is not None and not isinstance(tested, dict):
        errors.append(f"{path}: tested must be an object")
        tested = {}
    if status == "verified":
        for key in ("bios", "distro", "kernel", "balanced_w", "performance_w"):
            if key not in (tested or {}):
                errors.append(f"{path}: verified profiles need tested.{key}")
        for key in ("balanced_w", "performance_w"):
            value = (tested or {}).get(key)
            if not isinstance(value, (int, float)) or value <= 0:
                errors.append(f"{path}: tested.{key} must be a positive number")

    notes = data.get("notes")
    if notes is not None and not isinstance(notes, str):
        errors.append(f"{path}: notes must be a string")

    if status == "experimental":
        warnings.append(f"{path}: experimental profile; mark verified after hardware testing")
    return profile_id


def main():
    parser = argparse.ArgumentParser(description="Validate honorfnpp device profiles")
    parser.add_argument("directory", nargs="?", default="devices")
    parser.add_argument("--strict", action="store_true", help="treat warnings as errors")
    args = parser.parse_args()

    if not os.path.isdir(args.directory):
        print(f"error: {args.directory} is not a directory", file=sys.stderr)
        return 2

    errors = []
    warnings = []
    ids = {}
    matches = {}
    count = 0
    by_status = {status: 0 for status in STATUSES}

    for name in sorted(os.listdir(args.directory)):
        if not name.endswith(".json") or name.startswith("_"):
            continue
        path = os.path.join(args.directory, name)
        try:
            with open(path, encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, ValueError) as exc:
            errors.append(f"{path}: cannot read JSON: {exc}")
            continue
        count += 1
        profile_id = validate(path, data, errors, warnings)
        if profile_id:
            if profile_id in ids:
                errors.append(f"{path}: duplicate id '{profile_id}' (also {ids[profile_id]})")
            else:
                ids[profile_id] = path
        if isinstance(data, dict):
            status = data.get("status")
            if status in by_status:
                by_status[status] += 1
            match = data.get("match")
            if isinstance(match, dict):
                key = (
                    str(match.get("dmi_vendor", "")).lower(),
                    str(match.get("dmi_product", "")).lower(),
                    str(match.get("dmi_board", "")).lower(),
                )
                if key in matches:
                    warnings.append(
                        f"{path}: same DMI match as {matches[key]}; add dmi_bios to disambiguate"
                    )
                else:
                    matches[key] = path

    for warning in warnings:
        print(f"WARNING: {warning}")
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)

    if count == 0:
        print(f"error: no profiles found in {args.directory}", file=sys.stderr)
        return 1
    if errors or (args.strict and warnings):
        print(f"FAILED: {len(errors)} error(s), {len(warnings)} warning(s)", file=sys.stderr)
        return 1

    print(
        f"OK: {count} profile(s) — "
        f"{by_status['verified']} verified, "
        f"{by_status['experimental']} experimental, "
        f"{by_status['unknown']} unknown, "
        f"{len(warnings)} warning(s)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
