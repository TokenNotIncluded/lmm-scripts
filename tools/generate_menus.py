#!/usr/bin/env python3
"""Generate both menus from the installer catalog and one published revision."""
import argparse
import hashlib
import shlex
import subprocess
from catalog import TOOLS
from render import ROOT, emit, libraries, template

revision='a5e8b423bfa3ac8176bc6735da00339ffff811e9'


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args=parser.parse_args()
    for ext in ('sh', 'ps1'):
        hashes=[]
        for stem in [name for name, _, _ in TOOLS] + ['lmm-use']:
            name=f'{stem}.{ext}'
            payload=subprocess.check_output(['git','show',f'{revision}:{name}'],cwd=ROOT)
            digest=hashlib.sha256(payload).hexdigest()
            hashes.append(f"{name}) printf '%s' '{digest}';;" if ext=='sh' else f"  '{name}' = '{digest}'")
        if ext=='sh':
            catalog='\n'.join(key+'=('+' '.join(shlex.quote(row[index]) for row in TOOLS)+')' for index,key in enumerate(('tools','labels','kinds')))
        else:
            catalog='$tools=@(\n'+',\n'.join("  @{Name='%s';Label='%s';Kind='%s'}" % row for row in TOOLS)+'\n)'
        text=template(f'menu.{ext}.in').replace('@@CATALOG@@',catalog)
        text=text.replace('@@REVISION@@',revision).replace('@@HASHES@@','\n'.join(hashes))
        if ext=='sh':
            text=text.replace('@@LIBRARIES@@',libraries('lib/root.sh','lib/hash.sh','lib/termux.sh'))
        emit(f'menu.{ext}',text,args.check,'utf-8-sig' if ext=='ps1' else 'utf-8')


if __name__=='__main__':
    main()
