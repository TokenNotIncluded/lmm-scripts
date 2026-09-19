#!/usr/bin/env python3
from pathlib import Path
root=Path(__file__).resolve().parent
for app,package,version in [('pi','@earendil-works/pi-coding-agent','0.85.1'),('dsh','@deepseek-ai/dsh','0.1.5-rc.1')]:
 for extension in ['sh','ps1']:
  source=root/'templates'/('installer.'+extension)
  if not source.exists():continue
  text=source.read_text().replace('@APP@',app).replace('@PACKAGE@',package).replace('@VERSION@',version)
  (root/(app+'.'+extension)).write_text(text)
