#!/usr/bin/env python3
"""Generate small installers that load common functions from a pinned revision."""
import argparse
import json
import re
import shlex
from render import ROOT, emit, libraries, standalone, template

# JSON field -> shell / PowerShell variable. Keep a single naming map.
NAMES = {
    'script_version': ('SCRIPT_VERSION', 'ScriptVersion'),
    'library_revision': ('LIB_REVISION', 'LibRevision'),
    'node_version': ('NODE_VERSION', 'NodeVersion'),
    'pi_version': ('PI_VERSION', 'PiVersion'),
    'pi_provider_version': ('PI_PROVIDER_VERSION', 'PiProviderVersion'),
    'pnpm_version': ('PNPM_VERSION', 'PnpmVersion'),
    'dsh_version': ('DSH_VERSION', 'DshVersion'),
    'dsh_provider_url': ('DSH_PROVIDER_URL', 'DshProviderUrl'),
    'dsh_provider_sha256': ('DSH_PROVIDER_SHA256', 'DshProviderSha256'),
    'lmm_version': ('LMM_VERSION', 'LmmVersion'),
    'lmm_release_base': ('LMM_RELEASE_BASE', 'LmmReleaseBase'),
}


def constants(versions: dict, target: str, ext: str, body: str) -> str:
    shell = ext == 'sh'
    quote = shlex.quote if shell else lambda value: "'" + value.replace("'", "''") + "'"
    result = f'TARGET={quote(target)}\n' if shell else f'$Target = {quote(target)}\n'
    for key, names in NAMES.items():
        name = names[0 if shell else 1]
        if not re.search(r'\$(?:\{)?' + name + r'\b', body, re.I if not shell else 0):
            continue
        value = versions[key]
        if not isinstance(value, str) or '\n' in value or '\r' in value:
            raise ValueError(f'Invalid version field: {key}')
        result += f'{name}={quote(value)}\n' if shell else f'${name} = {quote(value)}\n'
    for key, shname, psname in [('node_sha256', 'node_hash', 'NodeHashes'), ('lmm_sha256', 'lmm_hash', 'LmmHashes')]:
        if (shname if shell else '$' + psname) not in body:
            continue
        hashes = versions[key]
        for platform, digest in hashes.items():
            if not re.fullmatch(r'[a-z0-9-]+', platform) or not re.fullmatch(r'[0-9a-f]{64}', digest):
                raise ValueError(f'Invalid {key} entry: {platform}')
        if shell:
            result += shname + '() { case "$1" in\n'
            result += ''.join(f"  {platform}) printf '%s\\n' {quote(digest)};;\n" for platform, digest in hashes.items())
            result += "  *) printf '\\n';;\nesac; }\n"
        else:
            result += f'${psname} = @{{\n'
            result += ''.join(f'  {quote(platform)} = {quote(digest)}\n' for platform, digest in hashes.items()) + '}\n'
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    versions = json.loads((ROOT / 'versions.json').read_text(encoding='utf-8'))
    if not re.fullmatch(r'[0-9a-f]{40}', versions['library_revision']):
        raise ValueError('library_revision must be a full Git commit ID')
    for target in ('pi', 'dsh', 'lmm'):
        for ext in ('sh', 'ps1'):
            parts = ['lib/hash.sh', 'lib/termux.sh', 'lib/quote.sh'] if ext == 'sh' else ['lib/common.ps1']
            parts.append(f'lib/download.{ext}')
            if target != 'lmm':
                parts.append(f'lib/node.{ext}')
            parts.append(f'tools/{target}.{ext}')
            shared = libraries(*parts[:-1])
            names = [part.rsplit('/', 1)[1] for part in parts[:-1]]
            loader = template(f'load.{ext}.in') + '\n' + libraries(parts[-1])
            if ext == 'sh':
                imports = 'for library in ' + ' '.join(names) + '; do\n  lmm_source_lib "$library" || exit $?\ndone'
            else:
                imports = "foreach ($library in @(" + ','.join("'" + name + "'" for name in names) + ")) {\n    . (Get-LmmLibrary $library)\n  }"
            body = template(f'install.{ext}.in').replace('@@LIBRARIES@@', loader)
            body = body.replace('@@LOAD_LIBRARIES@@', imports)
            body = body.replace('@@NODE_CHECK@@', template('lib/node-check.sh') if target != 'lmm' and ext == 'sh' else '')
            client = target != 'lmm'
            body = body.replace('@@CLIENT_STATE@@', 'INSTALL_NODE=1 BOOTSTRAP=1 NPM_SELECTED=0' if client else '')
            body = body.replace('@@NO_BOOTSTRAP@@', 'INSTALL_NODE=0; BOOTSTRAP=0' if client else ':')
            body = body.replace('@@NO_INSTALL_NODE@@', 'INSTALL_NODE=0' if client else ':')
            body = body.replace('@@CONSTANTS@@', constants(versions, target, ext, body + '\n' + shared))
            if ext == 'sh':
                body = standalone(body, 'lmm_install_main')
            else:
                body.encode('ascii')
            emit(f'{target}.{ext}', body, args.check)
    use = template('use.sh.in').replace('@@LIBRARIES@@', libraries('lib/root.sh'))
    emit('lmm-use.sh', standalone(use, 'lmm_use_main'), args.check)


if __name__ == '__main__':
    main()
