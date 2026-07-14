-- Les contrôles applicatifs de quota doivent rester exacts sous concurrence.
-- Ces triggers sérialisent les INSERT par auteur avant de recompter, y compris
-- si plusieurs requêtes arrivent dans la même milliseconde.

CREATE OR REPLACE FUNCTION private.dec_borner_flood_message_contact()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  -- Les formulaires anonymes passent par contact-form (Turnstile + rate limit
  -- Edge) et n'ont pas d'expediteur_id ; ce verrou couvre le RPC authentifié.
  IF NEW.expediteur_id IS NULL THEN
    RETURN NEW;
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'MESSAGE_CONTACT_RATE:' || NEW.expediteur_id::text,
      0
    )
  );
  IF (
    SELECT pg_catalog.count(*)
    FROM public.messages_contact mc
    WHERE mc.expediteur_id = NEW.expediteur_id
      AND mc.cree_le > pg_catalog.now() - interval '1 hour'
  ) >= 10 THEN
    RAISE EXCEPTION 'Trop de demandes. Réessayez dans une heure.'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.dec_borner_flood_message_contact()
  FROM PUBLIC, anon, authenticated, service_role;
DROP TRIGGER IF EXISTS dec_borner_flood_message_contact
  ON public.messages_contact;
CREATE TRIGGER dec_borner_flood_message_contact
BEFORE INSERT ON public.messages_contact
FOR EACH ROW
EXECUTE FUNCTION private.dec_borner_flood_message_contact();

CREATE OR REPLACE FUNCTION private.dec_borner_flood_message_litige()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'MESSAGE_LITIGE_RATE:' || NEW.litige_id::text || ':' ||
      NEW.auteur_id::text,
      0
    )
  );
  IF (
    SELECT pg_catalog.count(*)
    FROM public.messages_litige ml
    WHERE ml.litige_id = NEW.litige_id
      AND ml.auteur_id = NEW.auteur_id
      AND ml.cree_le > pg_catalog.now() - interval '5 minutes'
  ) >= 20 THEN
    RAISE EXCEPTION
      'Trop de messages envoyés. Patientez quelques minutes.'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.dec_borner_flood_message_litige()
  FROM PUBLIC, anon, authenticated, service_role;
DROP TRIGGER IF EXISTS dec_borner_flood_message_litige
  ON public.messages_litige;
CREATE TRIGGER dec_borner_flood_message_litige
BEFORE INSERT ON public.messages_litige
FOR EACH ROW
EXECUTE FUNCTION private.dec_borner_flood_message_litige();

CREATE OR REPLACE FUNCTION private.dec_borner_flood_message_chat()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  -- Les messages système d'attribution utilisent l'UUID nul et ne doivent pas
  -- consommer le quota humain.
  IF NEW.auteur_id = '00000000-0000-0000-0000-000000000000'::uuid THEN
    RETURN NEW;
  END IF;

  -- Sérialisation globale par acteur : une rotation de conversations, d'IP ou
  -- d'instance Edge ne permet pas de dépasser le plafond.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'MESSAGE_CHAT_RATE:' || NEW.auteur_id::text,
      0
    )
  );
  IF (
    SELECT pg_catalog.count(*)
    FROM public.messages_chat mc
    WHERE mc.auteur_id = NEW.auteur_id
      AND mc.cree_le > pg_catalog.now() - interval '5 minutes'
  ) >= 60 THEN
    RAISE EXCEPTION
      'Trop de messages envoyés. Patientez quelques minutes.'
      USING ERRCODE = 'P0001';
  END IF;

  -- La conversation est déjà verrouillée par le RPC canonique ; cette seconde
  -- borne protège aussi toute insertion interne future.
  IF (
    SELECT pg_catalog.count(*)
    FROM public.messages_chat mc
    WHERE mc.conversation_id = NEW.conversation_id
      AND mc.auteur_id = NEW.auteur_id
      AND mc.cree_le > pg_catalog.now() - interval '1 minute'
  ) >= 30 THEN
    RAISE EXCEPTION
      'Trop de messages envoyés. Patientez une minute.'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.dec_borner_flood_message_chat()
  FROM PUBLIC, anon, authenticated, service_role;
DROP TRIGGER IF EXISTS dec_borner_flood_message_chat
  ON public.messages_chat;
CREATE TRIGGER dec_borner_flood_message_chat
BEFORE INSERT ON public.messages_chat
FOR EACH ROW
EXECUTE FUNCTION private.dec_borner_flood_message_chat();

NOTIFY pgrst, 'reload schema';
