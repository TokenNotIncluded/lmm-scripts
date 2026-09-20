#!/usr/bin/env python3
"""Pin menu payloads to a reviewed installer revision, not a moving branch."""
from pathlib import Path
import argparse, hashlib, subprocess
from render import emit, libraries
p=Path(__file__).resolve().parents[1]
a=argparse.ArgumentParser();a.add_argument('--check',action='store_true');args=a.parse_args()
revision='9c8f76329ec7846e5b899b2e9fef2320172cdbb7'
for ext in ('sh','ps1'):
    lines=[]
    for stem in ('pi','dsh','lmm','lmm-use'):
        name=f'{stem}.{ext}'
        payload=subprocess.check_output(['git','show',f'{revision}:{name}'],cwd=p)
        sha=hashlib.sha256(payload).hexdigest()
        lines.append(f"{name}) printf '%s' '{sha}';;" if ext=='sh' else f"  '{name}' = '{sha}'")
    text=(p/f'templates/menu.{ext}.in').read_text(encoding='utf-8').replace('@@REVISION@@',revision).replace('@@HASHES@@','\n'.join(lines))
    if ext=='sh': text=text.replace('@@LIBRARIES@@',libraries('lib/root.sh','lib/hash.sh','lib/termux.sh'))
    emit(f'menu.{ext}',text,args.check,'utf-8-sig' if ext=='ps1' else 'utf-8')
