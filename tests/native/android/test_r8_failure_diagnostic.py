"""Closed diagnostic; negative and acceptance witnesses only."""
import importlib.util, unittest, json
from pathlib import Path
spec=importlib.util.spec_from_file_location('r8',Path(__file__).resolve().parents[3]/'scripts/native/check_android_r8.py')
r8=importlib.util.module_from_spec(spec);spec.loader.exec_module(r8)
class ClosedDiagnosticTests(unittest.TestCase):
 def test_closed_invariant_alphabet(self):
  for reason in r8.REASONS:
   with self.assertRaises(r8.R8Refused) as cm:r8.require(False, reason)
   value=r8.closed_failure(cm.exception)
   self.assertEqual(value['reason'],reason)
   expected={'schemaVersion','status','reason','exceptionKind','uiValidated','storeBuild'}
   if reason=='MAPPING_FILE':expected.add('mappingFiles')
   self.assertEqual(set(value),expected)
   self.assertFalse(value['uiValidated']);self.assertFalse(value['storeBuild'])
 def test_unknown_messages_never_escape(self):
  for error in [RuntimeError('do-not-export-this-payload'), KeyError('do-not-export-this-payload'), ValueError('do-not-export-this-payload'),r8.R8Refused('do-not-export-this-payload')]:
   self.assertNotIn('do-not-export-this-payload',json.dumps(r8.closed_failure(error)))
   self.assertEqual(r8.closed_failure(error)['reason'],'UNCLASSIFIED')
 def test_compiler_marker_and_disabled_configuration_are_distinct(self):
  for mapping, config, reason in [('', '', 'R8_COMPILER_MARKER'),('# compiler: R8', '-dontoptimize', 'GLOBAL_OPTIMIZATION_DISABLED')]:
   with self.assertRaises(r8.R8Refused) as cm:r8.inspect_r8(mapping,config,[],set())
   self.assertEqual(cm.exception.reason,reason)
 def test_success_predicate_unchanged(self):
  r8.require(True, 'DEX_SIZE')
  result=r8.inspect_r8('# compiler: R8\nexample.Plugin -> example.Plugin:\nexample.Helper -> a.b:\n','', [{'classpath':'example.Plugin'}],{'example.Plugin','app.jolene.android.MainActivity','a.b'})
  self.assertEqual(result['renamedClasses'],1)
if __name__=='__main__':unittest.main()
