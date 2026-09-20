#!/usr/bin/env python3
"""Pin menu payloads to a reviewed installer revision, not a moving branch."""
from pathlib import Path
import argparse, hashlib, subprocess
p=Path(__file__).resolve().parents[1]
a=argparse.ArgumentParser();a.add_argument('--check',action='store_true');args=a.parse_args()
revision='95c162c2031ecba34942b2a91631c1ec1f6f3d05'
for ext in ('sh','ps1'):
    lines=[]
    for stem in ('pi','dsh','lmm','lmm-use'):
        name=f'{stem}.{ext}'
        payload=subprocess.check_output(['git','show',f'{revision}:{name}'],cwd=p)
        sha=hashlib.sha256(payload).hexdigest()
        lines.append(f"{name}) printf '%s' '{sha}';;" if ext=='sh' else f"  '{name}' = '{sha}'")
    text=(p/f'templates/menu.{ext}.in').read_text(encoding='utf-8').replace('@@REVISION@@',revision).replace('@@HASHES@@','\n'.join(lines))
    data=text.encode('utf-8-sig' if ext=='ps1' else 'utf-8')
    path=p/f'menu.{ext}'
    if args.check:
        assert path.read_bytes()==data, f'{path} is stale'
    else:
        path.write_bytes(data);path.chmod(0o755 if ext=='sh' else 0o644)
