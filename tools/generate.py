#!/usr/bin/env python3
"""Emit standalone hosted installers; the server imports only root scripts."""
from pathlib import Path
import argparse,json,shlex
P=Path(__file__).resolve().parents[1]
v=json.loads((P/'versions.json').read_text())
parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
keys={'script_version':'SCRIPT_VERSION','node_version':'NODE_VERSION','pi_version':'PI_VERSION','pi_provider_version':'PI_PROVIDER_VERSION','dsh_version':'DSH_VERSION','dsh_provider_url':'DSH_PROVIDER_URL','dsh_provider_sha256':'DSH_PROVIDER_SHA256','lmm_version':'LMM_VERSION','lmm_release_base':'LMM_RELEASE_BASE'}
pkeys={'script_version':'ScriptVersion','node_version':'NodeVersion','pi_version':'PiVersion','pi_provider_version':'PiProviderVersion','dsh_version':'DshVersion','dsh_provider_url':'DshProviderUrl','dsh_provider_sha256':'DshProviderSha256','lmm_version':'LmmVersion','lmm_release_base':'LmmReleaseBase'}
for target in ['pi','dsh','lmm']:
 sh=f'TARGET={shlex.quote(target)}\n'+''.join(f'{name}={shlex.quote(v[key])}\n' for key,name in keys.items())
 for name,key in [('node_hash','node_sha256'),('lmm_hash','lmm_sha256')]:
  sh+=name+'() { case "$1" in\n'+''.join(f'  {platform}) printf \'%s\\n\' {shlex.quote(sha)};;\n' for platform,sha in v[key].items())+'  *) printf \'\\n\';;\nesac; }\n'
 ps=f"$Target = '{target}'\n"+''.join(f"${name} = '{v[key]}'\n" for key,name in pkeys.items())
 for name,key in [('NodeHashes','node_sha256'),('LmmHashes','lmm_sha256')]:
  ps+=f'${name} = @{{\n'+''.join(f"  '{platform}' = '{sha}'\n" for platform,sha in v[key].items())+'}\n'
 for ext,constants in [('sh',sh),('ps1',ps)]:
  body=(P/'templates'/f'install.{ext}.in').read_text().replace('@@CONSTANTS@@',constants)
  if ext=='sh':
   lines=body.splitlines(keepends=True);body=lines[0]+'lmm_install_main() {\n'+''.join(lines[1:])+'\n}\nif true; then\n  lmm_install_main "$@"\nfi\n'
  if ext=='ps1':body.encode('ascii')
  path=P/f'{target}.{ext}'
  if args.check:
   if not path.exists() or path.read_text()!=body:raise SystemExit(f'Generated file out of date: {path}')
  else:path.write_text(body);path.chmod(0o755 if ext=='sh' else 0o644)
