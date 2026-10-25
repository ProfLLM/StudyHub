"""Encode only public PNGs/titles/hashes; never semantic expected answers."""
import base64
import hashlib
import json
import pathlib
import argparse

args = argparse.ArgumentParser(description=__doc__)
args.add_argument("output", type=pathlib.Path)
args.add_argument("--replay-from", type=pathlib.Path,
                  help="Local public synthetic raw HTML run; never account data.")
options = args.parse_args()

root = pathlib.Path(__file__).resolve().parents[1]
corpus = root / "test_fixtures" / "ai_quality"
manifest = json.loads((corpus / "manifest.json").read_text())
sheets = []
for case in manifest["cases"]:
    asset = case["assets"]["png"]
    image = (corpus / asset["path"]).read_bytes()
    assert hashlib.sha256(image).hexdigest() == asset["sha256"]
    sheets.append({"id": case["id"], "title": case["title"],
                   "sha256": asset["sha256"],
                   "png_base64": base64.b64encode(image).decode("ascii")})
assert len(sheets) == 6
if options.replay_from:
    for sheet in sheets:
        sheet["recorded_html"] = (options.replay_from / f"{sheet['id']}.raw.html").read_text()
    sheets[0]["ordered_pair_html"] = (options.replay_from / "07_ordered_pair.raw.html").read_text()
payload = json.dumps(sheets, separators=(",", ":")).encode()
assert len(payload) <= 2 * 1024 * 1024
options.output.write_bytes(payload)
