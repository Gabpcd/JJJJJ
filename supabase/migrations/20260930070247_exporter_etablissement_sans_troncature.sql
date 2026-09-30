-- Définition LIVE relue le 30/09/2026 (prosrc md5 bb36c4ee8e9ed20c1a3a65752ce4840e).
-- Même projection JSON et même périmètre établissement ; suppression des deux
-- LIMIT 200 silencieux. Aucun fichier binaire ni nouveau jeu de données exporté.
CREATE OR REPLACE FUNCTION public.fn_exporter_rgpd_etablissement()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $export$
DECLARE
    v_etab_id uuid := public.mon_etablissement_id();
    v_result jsonb;
BEGIN
    IF auth.uid() IS NULL OR NOT public.fn_compte_auth_actif() OR v_etab_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    SELECT jsonb_build_object(
        'etablissement', (SELECT row_to_json(e) FROM (
            SELECT nom, type::text, siret, finess, email_contact, telephone_contact,
                adresse_rue, adresse_code_postal, adresse_ville, convention_collective,
                cree_le, modifie_le
            FROM public.etablissements WHERE id = v_etab_id
        ) e),
        'missions', (SELECT COALESCE(jsonb_agg(row_to_json(m)), '[]') FROM (
            SELECT id, intitule, statut::text, debut_le, fin_le, taux_horaire_base, total_brut, cree_le
            FROM public.missions WHERE etablissement_id = v_etab_id ORDER BY cree_le DESC, id DESC
        ) m),
        'factures', (SELECT COALESCE(jsonb_agg(row_to_json(f)), '[]') FROM (
            SELECT numero_facture, montant_ht, montant_ttc, statut, date_emission, date_paiement
            FROM public.factures WHERE etablissement_id = v_etab_id ORDER BY date_emission DESC, id DESC
        ) f),
        'contrats', (SELECT COALESCE(jsonb_agg(row_to_json(c)), '[]') FROM (
            SELECT type_contrat, statut, cree_le, modifie_le
            FROM public.contrats_mission WHERE etablissement_id = v_etab_id ORDER BY cree_le DESC, id DESC
        ) c),
        'export_date', now()
    ) INTO v_result;

    RETURN v_result;
END;
$export$;
REVOKE ALL ON FUNCTION public.fn_exporter_rgpd_etablissement() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_exporter_rgpd_etablissement() TO authenticated, service_role;

INSERT INTO private.security_definer_inventory(signature, categorie, definition_md5, justification, recense_le)
SELECT p.oid::regprocedure::text, 'RPC_UTILISATEUR_AUTH_INTERNE', md5(p.prosrc),
    'Export des projections existantes sans limite silencieuse : compte actif et établissement canonique uniquement.', now()
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'fn_exporter_rgpd_etablissement'
ON CONFLICT(signature) DO UPDATE SET definition_md5 = EXCLUDED.definition_md5,
    justification = EXCLUDED.justification, recense_le = EXCLUDED.recense_le;
