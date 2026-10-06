#!/usr/bin/env python3
"""Copy completed App Store capture cases and record unedited-file evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct

ROOT = Path(__file__).resolve().parents[1]
ORDER = ["01-iptv.png", "02-channels.png", "03-player.png",
         "04-sharing.png", "05-xtream.png", "06-carplay.png"]


def collect(log, result_bundle):
    case, pending, completed = None, [], []
    text = Path(log).read_text()
    for line in text.splitlines():
        match = re.search(r"Test Case '-\[MirivoUITests\.ProductUITests (\w+)\]' started", line)
        if match:
            case, pending = match[1], []
        if line.startswith("MIRIVO_UI_CAPTURE: "):
            pending.append(Path(line.removeprefix("MIRIVO_UI_CAPTURE: ")))
        if case and f"{case}]' passed" in line:
            completed.extend((case, p) for p in pending)
            pending = []

    out = ROOT / "Release/AppStore/screenshots/store-20261005"
    evidence_path = out / "iphone-provenance.json"
    evidence = json.loads(evidence_path.read_text())
    files = {item["file"]: item for item in evidence["files"]}
    locales = set()
    for case, source in completed:
        match = re.fullmatch(r"mirivo-store-(.+?)-(0\d-.+)\.png", source.name)
        if not match:
            continue
        locale, name = match[1], match[2] + ".png"
        if name not in ORDER:
            continue
        destination = out / "iphone" / locale / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        if source.resolve() != destination.resolve():
            shutil.copy2(source, destination)
        data = destination.read_bytes()
        dimensions = list(struct.unpack(">II", data[16:24]))
        if dimensions != [1320, 2868] or data[25] != 2:
            raise ValueError(f"Unexpected PNG format: {destination}")
        relative = str(destination.relative_to(ROOT))
        files[relative] = {
            "file": relative, "source": str(source), "dimensions": dimensions,
            "sha256": hashlib.sha256(data).hexdigest(),
            "resultBundle": result_bundle, "testCase": case,
            "testCasePassed": True,
            "resultSuitePassed": True if "** TEST SUCCEEDED **" in text else
                False if "** TEST FAILED **" in text else None,
        }
        locales.add(locale)
    evidence["files"] = sorted(files.values(), key=lambda item: item["file"])
    evidence["additionalCaptureEvidence"] = "Per-file resultBundle/testCase records; failed cases are excluded."
    evidence_path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
    for locale in locales:
        names = sorted(p.name for p in (out / "iphone" / locale).glob("*.png"))
        if names != ORDER:
            raise ValueError(f"Incomplete screenshot set: {locale}")
    print(json.dumps({"completeLocalesFromLog": sorted(locales), "totalPNGFiles": len(files)}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", required=True)
    parser.add_argument("--result-bundle", required=True)
    args = parser.parse_args()
    collect(args.log, args.result_bundle)
