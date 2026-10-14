"""Build calibration witnesses from the bundled public database, not RAW claims."""
from pathlib import Path
import hashlib
import json
import math
import xml.etree.ElementTree as ET
import argparse
import subprocess

ROOT = Path(__file__).resolve().parents[1]
HERE = ROOT / "Build/Audit"
HERE.mkdir(parents=True, exist_ok=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", help="Compile and run the native witness audit")
    args = parser.parse_args()
    cameras, lenses, sources, compatible_mounts = [], [], [], {}
    for path in sorted((ROOT / "Resources/LensBridge/db").glob("*.xml")):
        data = path.read_bytes()
        root = ET.fromstring(data)
        sources.append({"file": path.name, "sha256": hashlib.sha256(data).hexdigest()})
        for mount in root.findall("mount"):
            compatible_mounts.setdefault(mount.findtext("name"), set()).update(c.text for c in mount.findall("compat"))
        cameras.extend(root.findall("camera"))
        lenses.extend((path.name, index, lens) for index, lens in enumerate(root.findall("lens")))
    requests, skipped = [], []
    for filename, index, lens in lenses:
        key = f"{filename}:{index}"
        model, maker = lens.findtext("model"), lens.findtext("maker")
        mounts = {mount.text for mount in lens.findall("mount")}
        crop = float(lens.findtext("cropfactor", "1"))
        candidates = [camera for camera in cameras if (camera.findtext("mount") in mounts or mounts.intersection(compatible_mounts.get(camera.findtext("mount"), set()))) and float(camera.findtext("cropfactor", "1")) >= crop * .96]
        calibration = lens.find("calibration")
        points = [] if calibration is None else [p for p in calibration if p.get("focal")]
        if not candidates or not points:
            skipped.append({"id": key, "lens": model, "reason": "no-compatible-calibration-crop-camera" if not candidates else "no-optical-calibration-point"})
            continue
        camera = min(candidates, key=lambda c: abs(math.log(float(c.findtext("cropfactor", "1")) / crop)))
        # Prefer a vignetting witness with explicit focal, aperture and distance.
        point = next((p for p in points if p.tag == "vignetting"), points[0])
        metadata = {"Make": camera.findtext("maker"), "Model": camera.findtext("model"), "LensModel": model, "FocalLength": float(point.get("focal")), "FNumber": float(point.get("aperture", "8")), "FocusDistance": float(point.get("distance", "1000"))}
        aspect = lens.findtext("aspect-ratio", "3:2").split(":")
        ratio = float(aspect[0]) / float(aspect[1]) if len(aspect) == 2 else float(aspect[0])
        projections = {"rectilinear": 1, "fisheye": 2, "panoramic": 3, "equirectangular": 4, "orthographic": 5, "stereographic": 6, "equisolid": 7, "thoby": 8}
        requests.append({"id": key, "expectedLens": model, "expectedMaker": maker, "expectedCrop": crop, "expectedProjection": projections[lens.findtext("type", "rectilinear")], "expectedAspectRatio": ratio, "metadata": metadata, "width": round(32 * ratio), "height": 32, "expectedModels": [m.text for m in lens.findall("model")], "expectedCameraCrop": float(camera.findtext("cropfactor", "1")), "expectedCameraMount": camera.findtext("mount")})
    manifest = {"sourceRepository": "https://github.com/lensfun/lensfun", "sourceCommit": "43f9e001ab66c4fcdd4f400463f13b72f94b2288", "cameraEntries": len(cameras), "lensEntries": len(lenses), "uniqueMakerModels": len({(lens.findtext("maker"), lens.findtext("model")) for _, _, lens in lenses}), "testedScope": "Database-derived identity aliases and interpolation witnesses in small native coordinates at each recorded aspect ratio; not real RAW or optical accuracy coverage", "requests": requests, "skipped": skipped, "sources": sources}
    destination = HERE / "catalog-audit-input.json"
    destination.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(f"{len(cameras)} cameras, {len(lenses)} lens entries, {len(requests)} interpolation witnesses, {len(skipped)} explicit skips")
    if args.run:
        executable = HERE / "audit-catalog"
        subprocess.run(["xcrun", "clang", "-O2", "-fobjc-arc", "-arch", "arm64", "-mmacosx-version-min=26.0", "-I", str(ROOT / "Sources/Native"), "-framework", "Cocoa", "-framework", "ImageIO", "-framework", "CoreImage", str(ROOT / "Tests/audit_catalog.m"), str(ROOT / "Sources/Native/LensNativeProfileEngine.m"), "-o", str(executable)], check=True, cwd=ROOT)
        subprocess.run([str(executable)], check=True, cwd=ROOT)

if __name__ == "__main__":
    main()
