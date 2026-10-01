-- Fragment staging uniquement. Installation vide ; aucun consommateur ni activation.
-- Le projet est prouvé par l'exécuteur Management avant cet appel, pas par ce CHECK.
DO $capacity_preflight$
BEGIN
 IF current_user<>'postgres' OR current_setting('server_version_num')::integer/10000<>17
   OR to_regclass('private.stripe_connect_test_capacities') IS NOT NULL
   OR to_regtype('private.stripe_connect_test_capacities') IS NOT NULL
   OR (SELECT count(*) FROM private.stripe_connect_release_gate)<>1
   OR NOT EXISTS(SELECT 1 FROM private.stripe_connect_release_gate WHERE protocol='CONNECT_PRETRANSFER_V1' AND enabled IS FALSE)
   OR EXISTS(SELECT 1 FROM private.stripe_connect_avant_transfert) THEN
   RAISE EXCEPTION 'CONNECT_TEST_CAPACITY_INSTALLATION_REFUSED';
 END IF;
END $capacity_preflight$;
CREATE TABLE private.stripe_connect_test_capacities (
 id uuid PRIMARY KEY,
 protocol text NOT NULL CHECK(protocol='CONNECT_STAGING_TEST_V1'),
 project_ref text NOT NULL CHECK(project_ref='mejpriaetwgtcstbgfid'),
 run_id text NOT NULL UNIQUE CHECK(run_id ~ '^f1-[A-Za-z0-9-]{1,80}$'),
 server_sha text NOT NULL CHECK(server_sha ~ '^[a-f0-9]{40}$'),
 ui_sha text NOT NULL CHECK(ui_sha ~ '^[a-f0-9]{40}$'),
 source_manifest_sha256 text NOT NULL CHECK(source_manifest_sha256 ~ '^[a-f0-9]{64}$'),
 enabled boolean NOT NULL DEFAULT false,
 installed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 expires_at timestamptz NOT NULL,
 etablissement_id uuid NOT NULL REFERENCES public.etablissements(id),
 soignant_id uuid NOT NULL REFERENCES public.soignants(id),
 mission_id uuid NOT NULL REFERENCES public.missions(id),
 facture_honoraire_id uuid NOT NULL UNIQUE REFERENCES public.factures_honoraires(id),
 facture_commission_id uuid NOT NULL UNIQUE REFERENCES public.factures(id),
 platform_account_id text NOT NULL CHECK(platform_account_id ~ '^acct_[A-Za-z0-9]+$'),
 customer_id text NOT NULL CHECK(customer_id ~ '^cus_[A-Za-z0-9]+$'),
 destination_id text NOT NULL CHECK(destination_id ~ '^acct_[A-Za-z0-9]+$'),
 livemode boolean NOT NULL DEFAULT false CHECK(livemode IS FALSE),
 soignant_cents bigint NOT NULL CHECK(soignant_cents>0 AND soignant_cents<=9007199254740991),
 commission_cents bigint NOT NULL CHECK(commission_cents>0 AND commission_cents<=9007199254740991),
 total_cents bigint NOT NULL CHECK(total_cents>0 AND total_cents<=9007199254740991),
 max_checkouts smallint NOT NULL DEFAULT 1 CHECK(max_checkouts=1),
 max_refunds smallint NOT NULL DEFAULT 1 CHECK(max_refunds=1),
 transfers_allowed boolean NOT NULL DEFAULT false CHECK(transfers_allowed IS FALSE),
 operation_id uuid UNIQUE REFERENCES private.stripe_connect_avant_transfert(id),
 checkout_reserved_at timestamptz,
 refund_reserved_at timestamptz,
 revoked_at timestamptz,
 CHECK(expires_at>installed_at),
 CHECK(etablissement_id<>soignant_id),
 CHECK(facture_honoraire_id<>facture_commission_id),
 CHECK(soignant_cents+commission_cents=total_cents),
 CHECK((checkout_reserved_at IS NULL)=(operation_id IS NULL)),
 CHECK(refund_reserved_at IS NULL OR checkout_reserved_at IS NOT NULL),
 CHECK(revoked_at IS NULL OR enabled IS FALSE)
);
ALTER TABLE private.stripe_connect_test_capacities OWNER TO postgres;
ALTER TABLE private.stripe_connect_test_capacities ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.stripe_connect_test_capacities FROM PUBLIC,anon,authenticated,service_role;
DO $capacity_postflight$
DECLARE v_role text;
BEGIN
 IF EXISTS(SELECT 1 FROM private.stripe_connect_test_capacities)
   OR EXISTS(SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl,acldefault('r',c.relowner))) a
     WHERE c.oid='private.stripe_connect_test_capacities'::regclass AND (a.grantee<>c.relowner OR a.grantor<>c.relowner))
   OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='private.stripe_connect_test_capacities'::regclass)
   OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='private.stripe_connect_test_capacities'::regclass AND NOT tgisinternal)
   OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='private.stripe_connect_test_capacities'::regclass
      AND relowner='postgres'::regrole AND relrowsecurity) THEN
   RAISE EXCEPTION 'CONNECT_TEST_CAPACITY_POSTFLIGHT';
 END IF;
 FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   IF has_table_privilege(v_role,'private.stripe_connect_test_capacities','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') THEN
     RAISE EXCEPTION 'CONNECT_TEST_CAPACITY_ACL'; END IF;
 END LOOP;
END $capacity_postflight$;
