-- Sources historiques LIVE du 01/10/2026 ; seulement dans le PostgreSQL éphémère du témoin.

CREATE OR REPLACE FUNCTION "public"."next_invoice_number"("p_soignant_id" "uuid") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ DECLARE v_siret TEXT; v_year TEXT; v_last_seq INTEGER; v_next_seq INTEGER; v_lock_key BIGINT; v_result TEXT; BEGIN v_lock_key := ('x' || left(md5(p_soignant_id::text), 15))::bit(64)::bigint; PERFORM pg_advisory_xact_lock(v_lock_key); SELECT COALESCE(LEFT(siret_liberal, 8), LEFT(p_soignant_id::text, 8)) INTO v_siret FROM soignants WHERE id = p_soignant_id; IF v_siret IS NULL THEN v_siret := LEFT(p_soignant_id::text, 8); END IF; v_year := TO_CHAR(CURRENT_DATE, 'YYYY'); SELECT MAX(NULLIF(SPLIT_PART(numero_facture, '-', 4), '')::INTEGER) INTO v_last_seq FROM factures_honoraires WHERE soignant_id = p_soignant_id AND numero_facture LIKE 'JOL-%'; v_next_seq := COALESCE(v_last_seq, 0) + 1; v_result := 'JOL-' || v_siret || '-' || v_year || '-' || LPAD(v_next_seq::TEXT, 5, '0'); RETURN v_result; END; $$;


ALTER FUNCTION "public"."next_invoice_number"("p_soignant_id" "uuid") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."next_avoir_number"("p_soignant_id" "uuid") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_siret TEXT;
  v_year TEXT;
  v_last_seq INTEGER;
  v_next_seq INTEGER;
  v_lock_key BIGINT;
  v_result TEXT;
BEGIN
  v_lock_key := ('x' || left(md5('AV:' || p_soignant_id::text), 15))::bit(64)::bigint;
  PERFORM pg_advisory_xact_lock(v_lock_key);

  SELECT COALESCE(LEFT(siret_liberal, 8), LEFT(p_soignant_id::text, 8))
    INTO v_siret
    FROM public.soignants WHERE id = p_soignant_id;
  IF v_siret IS NULL THEN
    v_siret := LEFT(p_soignant_id::text, 8);
  END IF;

  v_year := TO_CHAR(CURRENT_DATE, 'YYYY');

  SELECT MAX(
    NULLIF(SPLIT_PART(numero_facture, '-', 4), '')::INTEGER
  ) INTO v_last_seq
    FROM public.factures_honoraires
   WHERE soignant_id = p_soignant_id
     AND type_document = 'AVOIR'
     AND numero_facture LIKE 'AV-%';

  v_next_seq := COALESCE(v_last_seq, 0) + 1;
  v_result := 'AV-' || v_siret || '-' || v_year || '-' || LPAD(v_next_seq::TEXT, 5, '0');
  RETURN v_result;
END;
$$;


ALTER FUNCTION "public"."next_avoir_number"("p_soignant_id" "uuid") OWNER TO "postgres";
