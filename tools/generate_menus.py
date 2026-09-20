#!/usr/bin/env python3
"""Pin menu payloads to a reviewed installer revision, not a moving branch."""
from pathlib import Path
import argparse, hashlib, subprocess
p=Path(__file__).resolve().parents[1]
a=argparse.ArgumentParser();a.add_argument('--check',action='store_true');args=a.parse_args()
revision='bb38629f825339f64c4b5b0018c3dde47787d9a2'
for ext in ('sh','ps1'):
    lines=[]
    for stem in ('pi','dsh','lmm','lmm-use'):
        name=f'{stem}.{ext}'
        payload=subprocess.check_output(['git','show',f'{revision}:{name}'],cwd=p)
        sha=hashlib.sha256(payload).hexdigest()
        lines.append(f"{name}) printf '%s' '{sha}';;" if ext=='sh' else f"  '{name}' = '{sha}'")
    text=(p/f'templates/menu.{ext}.in').read_text().replace('@@REVISION@@',revision).replace('@@HASHES@@','\n'.join(lines))
    data=text.encode('utf-8-sig' if ext=='ps1' else 'utf-8')
    path=p/f'menu.{ext}'
    if args.check:
        assert path.read_bytes()==data, f'{path} is stale'
    else:
        path.write_bytes(data);path.chmod(0o755 if ext=='sh' else 0o644)
