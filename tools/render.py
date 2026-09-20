"""Shared rendering and byte-for-byte checks for installer and menu entry points."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def template(name: str) -> str:
    return (ROOT / 'templates' / name).read_text(encoding='utf-8')


def libraries(*names: str) -> str:
    return '\n'.join(template(name).rstrip() for name in names) + '\n'


def standalone(text: str, name: str) -> str:
    """Do not execute a partial pipe before the complete function is received."""
    first, body = text.split('\n', 1)
    return f'{first}\n{name}() {{\n{body}\n}}\nif true; then\n  {name} "$@"\nfi\n'


def emit(name: str, text: str, check: bool, encoding: str = 'utf-8') -> None:
    if re.search(r'@@[A-Z_]+@@', text):
        raise ValueError(f'Unexpanded template marker in {name}')
    data = text.encode(encoding)
    path = ROOT / name
    if check:
        if not path.exists() or path.read_bytes() != data:
            raise SystemExit(f'Generated file out of date: {name}')
    else:
        path.write_bytes(data)
        path.chmod(0o755 if name.endswith('.sh') else 0o644)
