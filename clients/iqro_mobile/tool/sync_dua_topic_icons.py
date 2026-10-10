"""Sync the Flutter vector definitions from the web's canonical geometry."""
import argparse
import json
import subprocess
from pathlib import Path
mobile = Path(__file__).resolve().parents[1]
source = mobile.parents[1] / 'services/web/lib/dua-topic-icons.json'
target = mobile / 'lib/features/dua/dua_topic_icons.g.dart'
content = "// Generated from services/web/lib/dua-topic-icons.json.\npart of 'dua_thematic_icon.dart';\n\nfinal _duaVectorShapes = jsonDecode(r'''" + json.dumps(json.loads(source.read_text()), separators=(',', ':')) + "''') as Map<String, dynamic>;\n"
content = subprocess.run(
    ['dart', 'format', '--output=show', '--show=none', '--summary=none',
     '--stdin-name=' + str(target)],
    input=content, text=True, capture_output=True, check=True, cwd=mobile,
).stdout
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
if args.check:
    if target.read_text() != content:
        raise SystemExit('Run tool/sync_dua_topic_icons.py to sync icon geometry')
    print('Web and Flutter icon geometry match')
else:
    target.write_text(content)
