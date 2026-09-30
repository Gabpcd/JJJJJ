import importlib.util,pathlib,unittest
spec=importlib.util.spec_from_file_location('audit',pathlib.Path(__file__).with_name('audit-ddl.py'));m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class AuditTests(unittest.TestCase):
 def test_schema_only_is_scanned_not_released(self):
  sql="SET client_encoding='UTF8'; SELECT pg_catalog.set_config('search_path', '', false); CREATE SCHEMA private; CREATE TABLE private.t(id uuid); CREATE FUNCTION private.f() RETURNS text LANGUAGE sql AS $$SELECT 'example'::text$$;"
  r=m.audit(sql);self.assertEqual(r['statements'],5);self.assertFalse(r['import_ready']);self.assertTrue(r['manual_review_required'])
 def test_comment_is_metadata_and_still_secret_scanned(self):
  self.assertEqual(m.audit("COMMENT ON TABLE public.t IS 'documentation'")['statements'],1)
  with self.assertRaisesRegex(m.Refused,'SECRET_PATTERN_REFUSED'):m.audit("COMMENT ON TABLE public.t IS 'sk_live_CANARY123456789'")
 def test_top_level_effects_rejected(self):
  for sql in ["INSERT INTO public.t VALUES(1)","COPY public.t FROM STDIN","DELETE FROM public.t","UPDATE public.t SET id=1","DO $$BEGIN NULL; END$$","SELECT public.unknown()","CALL public.unknown()","CREATE SUBSCRIPTION s CONNECTION 'host=x' PUBLICATION p","CREATE SERVER s FOREIGN DATA WRAPPER postgres_fdw OPTIONS(host 'x')"]:
   with self.subTest(sql=sql),self.assertRaises(m.Refused):m.audit(sql)
 def test_secret_canaries_never_reflected(self):
  for secret in ['sk_live_CANARY0123456789','sb_secret_CANARY0123456789','eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJDQU5BUlkifQ.c2lnbmF0dXJlQ0FOQVJZ','postgres://user:CANARY_SECRET@example.invalid/db','-----BEGIN PRIVATE KEY-----']:
   with self.subTest(secret=secret),self.assertRaisesRegex(m.Refused,'^SECRET_PATTERN_REFUSED$'):m.audit("CREATE FUNCTION public.x() RETURNS text LANGUAGE sql AS $$ SELECT '"+secret+"' $$;")
 def test_meta_commands_not_executable(self):
  token='A'*32;r=m.audit('\\restrict '+token+'\nCREATE TABLE public.t(id int);\n\\unrestrict '+token+'\n');self.assertEqual(r['statements'],1)
  for sql in ['\\! echo CANARY','\\connect postgres','\\restrict '+token+'\nCREATE TABLE t(id int);','\\restrict '+token+'\n\\unrestrict '+('B'*32)]:
   with self.subTest(sql=sql),self.assertRaises(m.Refused):m.audit(sql)
 def test_guc_not_arbitrary_code(self):
  with self.assertRaisesRegex(m.Refused,'GUC_REFUSED'):m.audit("SET session_preload_libraries='unsafe'")
if __name__=='__main__':unittest.main()
