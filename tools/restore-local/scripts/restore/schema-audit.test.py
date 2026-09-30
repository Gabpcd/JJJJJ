import unittest,importlib.util,pathlib
spec=importlib.util.spec_from_file_location('schema_audit',pathlib.Path(__file__).with_name('schema-audit.py'))
a=importlib.util.module_from_spec(spec);spec.loader.exec_module(a)
class SchemaAudit(unittest.TestCase):
 def test_body_calls_are_inventory_not_runtime_proof(self):
  r=a.audit("CREATE SCHEMA public; CREATE FUNCTION public.f() RETURNS void LANGUAGE plpgsql AS $$ BEGIN PERFORM private.g(); END $$;")
  self.assertEqual(r['lexical_references_not_dependency_closure']['private'],['g'])
  self.assertIn('PRIVATE_SCHEMA_MISSING',r['blockers']);self.assertFalse(r['import_ready'])
 def test_even_private_presence_does_not_fake_full_bundle(self):
  r=a.audit('CREATE SCHEMA public; CREATE SCHEMA private;')
  self.assertNotIn('PRIVATE_SCHEMA_MISSING',r['blockers']);self.assertFalse(r['import_ready'])
  self.assertIn('MANAGED_CUSTOMIZATIONS_BUNDLE_REQUIRED',r['blockers'])
 def test_top_level_effects_refused(self):
  for sql in ["SELECT net.http_post('https://example.com');","COPY public.x FROM PROGRAM 'curl example.com';","DO $$ BEGIN PERFORM 1; END $$;","INSERT INTO public.x VALUES(1);","DROP SCHEMA public CASCADE;"]:
   with self.subTest(sql=sql): self.assertIn('TOP_LEVEL_STATEMENT_REQUIRES_REVIEW',a.audit(sql)['blockers'])
 def test_dump_config_is_recognized_structurally(self):
  r=a.audit("SELECT pg_catalog.set_config('search_path', '', false); CREATE SCHEMA public;")
  self.assertNotIn('NON_DUMP_SELECT',r['unapproved_statement_types'])
 def test_invalid_sql_raises_before_inventory(self):
  with self.assertRaises(Exception):a.audit('not valid sql')
if __name__=='__main__':unittest.main()
