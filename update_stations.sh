#!/bin/bash
# Updates BiciMAD station coordinates from the public GBFS feed.
# Run when EMT adds or removes stations (~once per year).
# Usage: ./update_stations.sh
#
# Regenerates:
#   resources/data/stations_coords.json  (raw data, reference)
#   source/StationsData.mc               (Monkey C constant used by the app)

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Downloading stations from GBFS BiciMAD..."
python3 << 'PYEOF'
import urllib.request, json, sys, os

script_dir = os.environ.get("SCRIPT_DIR", ".")
url = "https://madrid.publicbikesystem.net/customer/gbfs/v3.0/station_information"

try:
    with urllib.request.urlopen(url, timeout=15) as r:
        data = json.load(r)
except Exception as e:
    print(f"Download error: {e}", file=sys.stderr)
    sys.exit(1)

stations = data["data"]["stations"]
compact = []
for s in stations:
    sid   = s["station_id"]
    lat   = s["lat"]
    lon   = s["lon"]
    names = s.get("name", [])
    name  = next((n["text"] for n in names if n.get("language") == "es"),
                  names[0]["text"] if names else sid)
    compact.append([sid, name, round(lat, 5), round(lon, 5)])

# Save reference JSON
json_path = os.path.join(script_dir, "resources/data/stations_coords.json")
os.makedirs(os.path.dirname(json_path), exist_ok=True)
with open(json_path, "w", encoding="utf-8") as f:
    json.dump(compact, f, separators=(",",":"), ensure_ascii=False)

# Generate Monkey C file
mc_lines = [
    "// Static coordinates for all BiciMAD stations.",
    "// Source: GBFS https://madrid.publicbikesystem.net/customer/gbfs/v3.0/station_information",
    "// To update: ./update_stations.sh",
    "import Toybox.Lang;",
    "",
    "class StationsData {",
    "    static function getCoords() as Array {",
    "        return ["
]

entries = []
for s in compact:
    sid, name, lat, lon = s
    name_esc = name.replace('"', '\\"')
    entries.append(f'            ["{sid}","{name_esc}",{lat}d,{lon}d]')

mc_lines.append(",\n".join(entries))
mc_lines += ["        ];", "    }", "}"]
mc_out = "\n".join(mc_lines)

mc_path = os.path.join(script_dir, "source/StationsData.mc")
with open(mc_path, "w", encoding="utf-8") as f:
    f.write(mc_out)

print(f"OK: {len(compact)} stations")
print(f"  -> {json_path} ({os.path.getsize(json_path)} bytes)")
print(f"  -> {mc_path} ({os.path.getsize(mc_path)} bytes)")
print("")
print("Now rebuild the app and deploy to the watch.")
PYEOF
