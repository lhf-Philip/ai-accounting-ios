#!/usr/bin/env python3
"""Print the UDID of an available iPhone Simulator for local test commands."""

from __future__ import annotations

import json
import subprocess
import sys


PREFERRED_NAMES = ("iPhone 13", "iPhone 17", "iPhone 17 Pro")


def main() -> int:
    result = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "-j"],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(result.stderr.strip() or "Unable to list iOS Simulators.", file=sys.stderr)
        return result.returncode

    payload = json.loads(result.stdout)
    iphones = [
        device
        for runtime_devices in payload.get("devices", {}).values()
        for device in runtime_devices
        if device.get("isAvailable", True)
        and str(device.get("name", "")).startswith("iPhone")
        and device.get("udid")
    ]

    for preferred_name in PREFERRED_NAMES:
        match = next(
            (device for device in iphones if device["name"] == preferred_name),
            None,
        )
        if match:
            print(match["udid"])
            return 0

    if iphones:
        print(iphones[0]["udid"])
        return 0

    print(
        "No available iPhone Simulator found. Install an iOS runtime in Xcode.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
