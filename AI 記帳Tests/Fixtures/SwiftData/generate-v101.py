#!/usr/bin/env python3
"""Generate synthetic on-disk stores from unchanged v1.0.1 model source; no network or SQL."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile

SOURCE_COMMIT = "9063807944d1b46e2125711338c73acfa20f32e9"
HERE = Path(__file__).resolve().parent


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", required=True, help="Booted iOS Simulator UDID")
    parser.add_argument("--output", required=True, type=Path, help="New directory; existing paths are refused")
    args = parser.parse_args()
    destination = args.output.resolve()
    if destination.exists():
        parser.error("Output must not already exist; existing fixtures are never overwritten.")
    model = HERE / "V101Models.swift.source"
    generator = HERE / "V101Generator.swift.source"
    # The frozen model blob is the exact file at SOURCE_COMMIT; verify against Git's blob identity.
    blob = hashlib.sha1(f"blob {model.stat().st_size}\0".encode() + model.read_bytes()).hexdigest()
    expected_blob = "3989c729c8e175071437ab14d2cdc7e5e708914a"
    if blob != expected_blob:
        raise SystemExit("Frozen model source differs from the v1.0.1 Git blob.")
    sdk = output("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path")
    version = output("xcrun", "--sdk", "iphonesimulator", "--show-sdk-version")
    arch = "arm64" if platform.machine() == "arm64" else "x86_64"
    target = f"{arch}-apple-ios26.2-simulator"
    manifest = {
        "sourceCommit": SOURCE_COMMIT, "sourceTag": "v1.0.1", "modelGitBlob": blob,
        "sourcePath": "AI 記帳/Models/DataModels.swift", "module": "AI_記帳",
        "modelSHA256": digest(model), "generatorSHA256": digest(generator),
        "xcode": output("xcodebuild", "-version"), "sdkVersion": version, "target": target,
        "limitation": "Release model source regenerated on the recorded current runtime; not an artifact from the release OS. Intermediate deployments and newer model types are not covered.",
        "fixtures": {},
    }
    with tempfile.TemporaryDirectory(prefix="v101-generator-") as temporary:
        work = Path(temporary)
        shutil.copyfile(model, work / "DataModels.swift")
        shutil.copyfile(generator, work / "Generator.swift")
        executable = work / "generator"
        env = dict(os.environ, SDKROOT=sdk)
        subprocess.run(["xcrun", "--sdk", "iphonesimulator", "swiftc", "-sdk", sdk, "-target", target,
                        "-module-name", "AI_記帳", "-parse-as-library", str(work / "DataModels.swift"),
                        str(work / "Generator.swift"), "-o", str(executable)], env=env, check=True)
        destination.mkdir(parents=True)
        for mode in ("empty", "populated"):
            store_dir = work / mode
            subprocess.run(["xcrun", "simctl", "spawn", args.simulator, str(executable), str(store_dir), mode], check=True)
            entry = json.loads((store_dir / "generation.json").read_text())
            entry["files"] = {}
            # The generator has exited, so copy a quiescent family. Never open the original with SQLite.
            for suffix in ("", "-wal", "-shm"):
                source = store_dir / ("AI_Accounting_v3.store" + suffix)
                if source.exists():
                    name = f"v1.0.1-{mode}.store{suffix}"
                    shutil.copyfile(source, destination / name)
                    entry["files"][name] = digest(destination / name)
            manifest["fixtures"][mode] = entry
        (destination / "v101-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(destination / "v101-manifest.json")


if __name__ == "__main__":
    main()
