#!/usr/bin/env python3
"""Check the signed distribution IPA, including required HealthKit rights."""

import argparse
import plistlib
import subprocess
import tempfile
from pathlib import Path


def run(*args):
    return subprocess.run(args, check=True, capture_output=True).stdout


def check(ipa):
    required = plistlib.loads(
        (Path(__file__).resolve().parents[1] / "Linea/Linea.entitlements").read_bytes()
    )
    with tempfile.TemporaryDirectory(prefix="linea-release-check-") as directory:
        run("ditto", "-x", "-k", str(ipa.resolve()), directory)
        apps = list((Path(directory) / "Payload").glob("*.app"))
        if len(apps) != 1:
            raise ValueError("Expected exactly one application in Payload")
        app = apps[0]
        run("codesign", "--verify", "--deep", "--strict", str(app))
        entitlements = plistlib.loads(run("codesign", "-d", "--entitlements", ":-", str(app)))
        profile = plistlib.loads(run("security", "cms", "-D", "-i", str(app / "embedded.mobileprovision")))
        for key, value in required.items():
            if entitlements.get(key) != value:
                raise ValueError(f"Required signing entitlement missing or changed: {key}")
            if profile["Entitlements"].get(key) != value:
                raise ValueError(f"Provisioning profile does not allow: {key}")
        if entitlements.get("get-task-allow") is not False:
            raise ValueError("Distribution app must have get-task-allow=false")
        info = plistlib.loads((app / "Info.plist").read_bytes())
        if info.get("ITSAppUsesNonExemptEncryption") is not False:
            raise ValueError("Expected explicit non-exempt encryption=false")
        for key in ("NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription"):
            if not str(info.get(key, "")).strip():
                raise ValueError(f"Missing HealthKit purpose string: {key}")
        widgets = list((app / "PlugIns").glob("*.appex"))
        if not widgets:
            raise ValueError("Expected the Focus widget extension")
        for widget in widgets:
            widget_info = plistlib.loads((widget / "Info.plist").read_bytes())
            for key in ("CFBundleVersion", "CFBundleShortVersionString"):
                if widget_info.get(key) != info.get(key):
                    raise ValueError(f"App/widget version mismatch: {key}")
        print(f"PASS: {info['CFBundleShortVersionString']} ({info['CFBundleVersion']}): "
              "signature, HealthKit, provisioning, purpose strings, encryption and widget version")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    arguments = parser.parse_args()
    try:
        check(arguments.ipa)
    except (ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"FAIL: {error}\n")
