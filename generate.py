#!/usr/bin/env python3
"""Compatibility entry point; maintained generators live in tools/."""
import runpy
from pathlib import Path
runpy.run_path(str(Path(__file__).parent/'tools'/'generate.py'),run_name='__main__')
