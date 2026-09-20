"""One tool list for installer generation and both menus."""
TOOLS = (
    ('pi', 'Pi + LMM', 'managed'),
    ('dsh', 'DSH + LMM', 'managed'),
    ('lmm', 'LMM CLI (preview)', 'managed'),
    ('codex', 'Codex CLI', 'external'),
    ('claude-code', 'Claude Code', 'external'),
    ('cc-switch', 'CC Switch', 'desktop'),
    ('clash-verge-rev', 'Clash Verge Rev', 'desktop'),
)
EXTERNAL = tuple(name for name, _, kind in TOOLS if kind != 'managed')
