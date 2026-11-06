"""Sync the Flutter vector definitions from the web's canonical geometry."""
import argparse
import json
import subprocess
from pathlib import Path
mobile = Path(__file__).resolve().parents[1]
web = mobile.parents[1] / 'services/web/lib'
PAIRS = [
    (web / 'dua-topic-icons.json', mobile / 'lib/features/dua/dua_topic_icons.g.dart',
     'dua_thematic_icon.dart', '_duaVectorShapes'),
    (web / 'home-section-icons.json', mobile / 'lib/features/home/home_section_icons.g.dart',
     'home_section_icon.dart', '_homeSectionShapes'),
]


def render(source, target, part_of, name):
    content = (f"// Generated from services/web/lib/{source.name}.\npart of '{part_of}';\n\n"
               f"final {name} = jsonDecode(r'''" + json.dumps(json.loads(source.read_text()), separators=(',', ':'))
               + "''') as Map<String, dynamic>;\n")
    return subprocess.run(
        ['dart', 'format', '--output=show', '--show=none', '--summary=none',
         '--stdin-name=' + str(target)],
        input=content, text=True, capture_output=True, check=True, cwd=mobile,
    ).stdout


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
for source, target, part_of, name in PAIRS:
    content = render(source, target, part_of, name)
    if args.check:
        if not target.exists() or target.read_text() != content:
            raise SystemExit(f'Run tool/sync_dua_topic_icons.py to sync {source.name}')
    else:
        target.write_text(content)
if args.check:
    print('Web and Flutter icon geometry match')
