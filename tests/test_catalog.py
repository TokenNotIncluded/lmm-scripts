"""Catalog entries, compact published launchers and Termux menu filtering."""
import os
from pathlib import Path
import subprocess
import sys
import unittest
P=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(P/'tools'))
from catalog import TOOLS, EXTERNAL

class CatalogTests(unittest.TestCase):
    def test_all_entries_and_menu_payloads_exist(self):
        self.assertEqual(len(TOOLS),7)
        for ext in ('sh','ps1'):
            menu=(P/f'menu.{ext}').read_text(encoding='utf-8-sig')
            for name,label,_ in TOOLS:
                self.assertTrue((P/f'{name}.{ext}').exists())
                self.assertIn(label,menu); self.assertIn(f'{name}.{ext}',menu)
            for name in EXTERNAL:
                self.assertLess((P/f'{name}.{ext}').stat().st_size,4000)

    @unittest.skipIf(sys.platform=='win32','Shell execution is tested on Unix')
    def test_termux_menu_hides_only_desktop_tools(self):
        normal=dict(os.environ,TERMUX_VERSION='',TERMUX_APP__PACKAGE_NAME='',PREFIX='')
        desktop=subprocess.check_output(['bash',str(P/'menu.sh'),'--list'],env=normal,text=True)
        mobile=subprocess.check_output(['bash',str(P/'menu.sh'),'--list'],env=normal|{'TERMUX_VERSION':'test'},text=True)
        for _,label,kind in TOOLS:
            self.assertIn(label,desktop)
            if kind=='desktop': self.assertNotIn(label,mobile)
            else: self.assertIn(label,mobile)

    @unittest.skipIf(sys.platform=='win32','Shell execution is tested on Unix')
    def test_new_help_is_offline(self):
        for name in EXTERNAL:
            result=subprocess.run(['bash',str(P/f'{name}.sh'),'--help'],env=dict(os.environ,LMM_LIB_DIR='/missing/local/libraries'),capture_output=True,text=True,timeout=10)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertIn('--dry-run',result.stdout)

if __name__=='__main__': unittest.main(verbosity=2)
