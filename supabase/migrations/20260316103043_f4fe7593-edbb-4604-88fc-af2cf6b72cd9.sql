
DROP FUNCTION IF EXISTS public.fn_export_fec(integer);

CREATE OR REPLACE FUNCTION public.fn_export_fec(p_annee integer)
RETURNS TABLE(
  journal_code TEXT, journal_libelle TEXT, ecriture_num TEXT, ecriture_date TEXT,
  compte_num TEXT, compte_libelle TEXT, comp_aux_num TEXT, comp_aux_libelle TEXT,
  piece_ref TEXT, piece_date TEXT, ecriture_libelle TEXT,
  debit NUMERIC, credit NUMERIC, montant NUMERIC, devise TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT est_admin() THEN RETURN; END IF;

    RETURN QUERY
    SELECT
        'VE'::TEXT, 'Ventes'::TEXT,
        f.numero_facture,
        TO_CHAR(f.date_emission, 'YYYYMMDD'),
        '706000'::TEXT, 'Prestations de services'::TEXT,
        e.siret::TEXT, e.nom,
        f.numero_facture, TO_CHAR(f.date_emission, 'YYYYMMDD'),
        'Commission Soin Direct'::TEXT,
        0::NUMERIC, f.montant_ht,
        f.montant_ttc, 'EUR'::TEXT
    FROM factures f
    JOIN etablissements e ON e.id = f.etablissement_id
    WHERE EXTRACT(YEAR FROM f.date_emission) = p_annee
    ORDER BY f.date_emission;
END;
$$;
