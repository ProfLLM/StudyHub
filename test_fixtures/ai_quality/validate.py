#!/usr/bin/env python3
"""Validate corpus assets and expectations; does not assess provider quality."""
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET

from PIL import Image, ImageChops

root = Path(__file__).resolve().parent
manifest = json.loads((root / "manifest.json").read_text())
assert manifest["schema_version"] == 1
assert len(manifest["cases"]) == 6
ids = set()
for case in manifest["cases"]:
    assert case["id"] not in ids
    ids.add(case["id"])
    assert case["equations"] and case["required"] and case["forbidden"]
    nodes = set(case["diagram"]["nodes"])
    assert len(nodes) == len(case["diagram"]["nodes"])
    for source, target, _ in case["diagram"]["directed_edges"]:
        assert source in nodes and target in nodes
    for kind, asset in case["assets"].items():
        path = root / asset["path"]
        assert path.parent == root
        data = path.read_bytes()
        assert hashlib.sha256(data).hexdigest() == asset["sha256"], path
        assert len(data) == asset["bytes"]
        if kind == "svg":
            svg = ET.fromstring(data)
            assert svg.tag.endswith("svg")
            assert not any(e.tag.endswith(("script", "foreignObject", "image")) for e in svg.iter())
        else:
            with Image.open(path) as im:
                assert im.size == (1000, 1400)
                assert im.format == "PNG"
                # Nontrivial image including variation in the interior, not a blank fixture.
                assert ImageChops.difference(im, Image.new("RGB", im.size, im.getpixel((0, 0)))).getbbox()
                assert len(im.crop((100, 160, 900, 1300)).convert("L").getcolors(256) or []) > 10
print("Validated 6 synthetic sheets: checksums, PNG dimensions/content, SVG parsing, diagram references.")
