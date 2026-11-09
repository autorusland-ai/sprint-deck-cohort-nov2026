"""Static packaging/guardrail tests. These do NOT grade either bot's prose."""
from pathlib import Path
import hashlib
import json
import re
import unittest

ROOT=Path(__file__).resolve().parents[1]
PACKAGE=ROOT/'hermes-ivanych/skill-packages/tekstov'

class TekstovSkillTests(unittest.TestCase):
    def setUp(self):
        self.text=(ROOT/'skills/tekstov/SKILL.md').read_text(encoding='utf-8')

    def test_native_frontmatter_and_trigger(self):
        self.assertTrue(self.text.startswith('---\nname: tekstov\n'))
        self.assertIn('description:',self.text.split('---',2)[1])
        for trigger in ['напиши пост','отредактируй','перепиши']:
            self.assertIn(trigger,self.text)

    def test_progressive_disclosure(self):
        refs=re.findall(r'<(references/[^>]+)>',self.text)
        self.assertEqual(len(refs),4)
        for ref in refs:
            self.assertTrue((PACKAGE/ref).is_file(),ref)
        self.assertIn('не загружай всё сразу',self.text)
        self.assertLess(len(self.text),14000)

    def test_private_package_is_same_adapter(self):
        actual=(PACKAGE/'SKILL.md').read_text(encoding='utf-8')
        self.assertEqual(actual,self.text)

    def test_source_provenance_hashes(self):
        manifest=json.loads((PACKAGE/'SOURCES.json').read_text(encoding='utf-8'))
        self.assertEqual(len(manifest['references']),4)
        for record in manifest['references']:
            data=(PACKAGE/record['package_path']).read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(),record['package_sha256'])

    def test_no_ide_rules_or_macos_payload(self):
        files=[p for p in PACKAGE.rglob('*') if p.is_file()]
        self.assertEqual(len(files),7)
        for path in files:
            self.assertNotIn('__MACOSX',str(path))
            self.assertNotIn('.DS_Store',str(path))
            self.assertNotEqual(path.suffix,'.mdc')

    def test_explicit_guardrails(self):
        for required in ['черновик','отдельного явного поручения','не сочиняй',
                         'Не отправляй приватный черновик','не переобучение',
                         'не имитируй чтение','не называй точной цитатой']:
            self.assertIn(required.lower(),self.text.lower())

    def test_behavioral_acceptance_cases_are_not_claimed_run(self):
        text=(ROOT/'skills/tekstov/EVAL.md').read_text(encoding='utf-8')
        self.assertIn('не выполненные тесты модели',text)
        for number in range(1,10):self.assertRegex(text,rf'(?m)^{number}\. ')
        self.assertIn('провал независимо',text)

if __name__=='__main__':unittest.main()
