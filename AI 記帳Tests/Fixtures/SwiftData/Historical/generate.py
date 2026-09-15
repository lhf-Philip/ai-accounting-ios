#!/usr/bin/env python3
"""Rebuild synthetic historical stores with exact Git model sources (never current models)."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import subprocess

ROOT = Path(__file__).resolve().parents[4]
FIXTURES = Path(__file__).resolve().parent


def run(command, **kwargs):
    return subprocess.check_output(command, text=True, **kwargs).strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", required=True, help="Booted iOS simulator UUID")
    parser.add_argument("--output", required=True, type=Path, help="New directory; existing paths are refused")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    sdk = run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"])
    xcode = run(["xcodebuild", "-version"])
    generator = (FIXTURES / "Generator.swift.source").read_text()
    for era in json.loads((FIXTURES / "eras.json").read_text()):
        directory = output / era["label"]
        directory.mkdir()
        model = directory / "DataModels.swift"
        model.write_bytes(subprocess.check_output([
            "git", "show", era["commit"] + ":AI 記帳/Models/DataModels.swift"
        ], cwd=ROOT))
        seed = directory / "Generator.swift"
        seed.write_text(generator.replace("ERA_MODELS", "[" + ", ".join(m + ".self" for m in era["models"]) + "]"))
        executable = directory / "generator"
        command = ["xcrun", "--sdk", "iphonesimulator", "swiftc", "-sdk", sdk,
                   "-target", platform.machine() + "-apple-ios26.2-simulator",
                   "-swift-version", "5", "-default-isolation", "MainActor",
                   "-module-name", "AI_記帳", "-parse-as-library", str(model), str(seed), "-o", str(executable)]
        command += [item for flag in era["flags"] for item in ["-D", "ERA_" + flag]]
        with (directory / "compile.log").open("w") as log:
            subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
        golden = directory / "golden"
        with (directory / "generate.log").open("w") as log:
            # Wait for process exit before taking the store/WAL/SHM family hashes.
            subprocess.run(["xcrun", "simctl", "spawn", args.simulator, str(executable), str(golden), "populated"],
                           stdout=log, stderr=subprocess.STDOUT, check=True)
        manifest = dict(era, modelSHA256=digest(model), generatorSHA256=digest(seed), xcode=xcode,
                        runtime=json.loads((golden / "generation.json").read_text()),
                        files={p.name: digest(p) for p in sorted(golden.glob("AI_Accounting_v3.store*"))})
        (golden / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        print(era["label"] + ": " + str(golden), flush=True)


if __name__ == "__main__":
    main()
