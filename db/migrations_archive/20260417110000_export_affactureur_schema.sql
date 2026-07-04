-- ============================================================
-- Export schéma prod : intégration affactureur (Defacto)
-- ============================================================
-- Cette migration reproduit le schéma existant en prod (créé via
-- dashboard/MCP). Marquée "applied" pour ne pas être rejouée.
-- ============================================================

-- 1. Table factor_advances
CREATE TABLE IF NOT EXISTS public.factor_advances (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    facture_honoraire_id    UUID NOT NULL REFERENCES public.factures_honoraires(id) ON DELETE CASCADE,
    soignant_id             UUID NOT NULL REFERENCES public.soignants(id),
    etablissement_id        UUID NOT NULL REFERENCES public.etablissements(id),
    mission_id              UUID REFERENCES public.missions(id),
    provider                TEXT NOT NULL DEFAULT 'defacto',
    provider_advance_id     TEXT,
    provider_invoice_id     TEXT,
    montant_facture_ttc     NUMERIC NOT NULL,
    frais_factor            NUMERIC,
    frais_jolene            NUMERIC DEFAULT 0,
    montant_net_soignant    NUMERIC,
    statut                  TEXT NOT NULL DEFAULT 'DEMANDEE'
                            CHECK (statut IN ('DEMANDEE','EN_ANALYSE','APPROUVEE','REJETEE','FINANCEE','RECOUVREE','IMPAYEE','ANNULEE')),
    motif_rejet             TEXT,
    cree_le                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    approuvee_le            TIMESTAMPTZ,
    financee_le             TIMESTAMPTZ,
    recouvree_le            TIMESTAMPTZ,
    modifie_le              TIMESTAMPTZ NOT NULL DEFAULT now(),
    raw_response            JSONB
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_factor_advances_facture
    ON public.factor_advances (facture_honoraire_id);
CREATE INDEX IF NOT EXISTS idx_factor_advances_soignant
    ON public.factor_advances (soignant_id);
CREATE INDEX IF NOT EXISTS idx_factor_advances_provider_id
    ON public.factor_advances (provider, provider_advance_id);
CREATE INDEX IF NOT EXISTS idx_factor_advances_statut
    ON public.factor_advances (statut);

-- 2. Table cessions_creance
CREATE TABLE IF NOT EXISTS public.cessions_creance (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    soignant_id             UUID NOT NULL REFERENCES public.soignants(id),
    facture_honoraire_id    UUID NOT NULL REFERENCES public.factures_honoraires(id) ON DELETE CASCADE,
    montant                 NUMERIC NOT NULL,
    version_texte           TEXT NOT NULL,
    contenu_hash            TEXT,
    signed_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    ip_address              TEXT,
    user_agent              TEXT,
    cree_le                 TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_cessions_creance_facture
    ON public.cessions_creance (facture_honoraire_id);
CREATE INDEX IF NOT EXISTS idx_cessions_creance_soignant
    ON public.cessions_creance (soignant_id);

-- 3. Trigger modifie_le sur factor_advances
CREATE OR REPLACE FUNCTION public.fn_factor_advances_modifie_le()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
BEGIN NEW.modifie_le = now(); RETURN NEW; END;
$function$;

DROP TRIGGER IF EXISTS trg_factor_advances_modifie_le ON public.factor_advances;
CREATE TRIGGER trg_factor_advances_modifie_le
    BEFORE UPDATE ON public.factor_advances
    FOR EACH ROW EXECUTE FUNCTION fn_factor_advances_modifie_le();

-- 4. RLS
ALTER TABLE public.factor_advances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cessions_creance ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'factor_advances' AND policyname = 'Admin gère factor_advances') THEN
        CREATE POLICY "Admin gère factor_advances" ON public.factor_advances FOR ALL USING (est_admin()) WITH CHECK (est_admin());
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'factor_advances' AND policyname = 'Soignant lit ses avances') THEN
        CREATE POLICY "Soignant lit ses avances" ON public.factor_advances FOR SELECT USING (auth.uid() = soignant_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'cessions_creance' AND policyname = 'Admin lit cessions') THEN
        CREATE POLICY "Admin lit cessions" ON public.cessions_creance FOR SELECT USING (est_admin());
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'cessions_creance' AND policyname = 'Soignant lit ses cessions') THEN
        CREATE POLICY "Soignant lit ses cessions" ON public.cessions_creance FOR SELECT USING (auth.uid() = soignant_id);
    END IF;
END $$;

-- 5. RPC fn_signer_cession_creance
CREATE OR REPLACE FUNCTION public.fn_signer_cession_creance(
    p_facture_honoraire_id UUID,
    p_version TEXT,
    p_ip TEXT DEFAULT NULL,
    p_user_agent TEXT DEFAULT NULL,
    p_contenu_hash TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_user_id UUID := auth.uid();
    v_facture RECORD;
    v_existing_id UUID;
    v_cession_id UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN '{"error":"Non authentifié"}'::JSONB;
    END IF;

    SELECT * INTO v_facture
    FROM factures_honoraires
    WHERE id = p_facture_honoraire_id AND soignant_id = v_user_id;

    IF v_facture IS NULL THEN
        RETURN '{"error":"Facture introuvable ou non autorisée"}'::JSONB;
    END IF;

    SELECT id INTO v_existing_id FROM cessions_creance WHERE facture_honoraire_id = p_facture_honoraire_id;
    IF v_existing_id IS NOT NULL THEN
        RETURN jsonb_build_object('success', true, 'cession_id', v_existing_id, 'message', 'Cession déjà existante');
    END IF;

    INSERT INTO cessions_creance (
        soignant_id, facture_honoraire_id, montant,
        version_texte, contenu_hash, ip_address, user_agent
    ) VALUES (
        v_user_id, p_facture_honoraire_id, v_facture.montant_ttc,
        p_version, p_contenu_hash, p_ip, p_user_agent
    ) RETURNING id INTO v_cession_id;

    RETURN jsonb_build_object('success', true, 'cession_id', v_cession_id);
END;
$function$;

-- 6. RPC fn_mes_avances_factor
CREATE OR REPLACE FUNCTION public.fn_mes_avances_factor()
RETURNS TABLE(
    id UUID, numero_facture TEXT, etablissement_nom TEXT, mission_intitule TEXT,
    montant_facture_ttc NUMERIC, frais_factor NUMERIC, frais_jolene NUMERIC,
    montant_net_soignant NUMERIC, statut TEXT, cree_le TIMESTAMPTZ, financee_le TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
    SELECT a.id, fh.numero_facture, e.nom, m.intitule,
           a.montant_facture_ttc, a.frais_factor, a.frais_jolene, a.montant_net_soignant,
           a.statut, a.cree_le, a.financee_le
    FROM factor_advances a
    JOIN factures_honoraires fh ON fh.id = a.facture_honoraire_id
    JOIN etablissements e ON e.id = a.etablissement_id
    LEFT JOIN missions m ON m.id = a.mission_id
    WHERE a.soignant_id = auth.uid()
    ORDER BY a.cree_le DESC;
$function$;

-- 7. RPC fn_admin_factor_stats
CREATE OR REPLACE FUNCTION public.fn_admin_factor_stats()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT est_admin() THEN RETURN '{"error":"Accès refusé"}'::JSONB; END IF;
    RETURN jsonb_build_object(
        'total_demandes', (SELECT COUNT(*) FROM factor_advances),
        'demandes_en_cours', (SELECT COUNT(*) FROM factor_advances WHERE statut IN ('DEMANDEE','EN_ANALYSE','APPROUVEE')),
        'demandes_financees', (SELECT COUNT(*) FROM factor_advances WHERE statut IN ('FINANCEE','RECOUVREE')),
        'demandes_rejetees', (SELECT COUNT(*) FROM factor_advances WHERE statut = 'REJETEE'),
        'volume_finance_total', (SELECT COALESCE(SUM(montant_net_soignant), 0) FROM factor_advances WHERE statut IN ('FINANCEE','RECOUVREE')),
        'commission_jolene_total', (SELECT COALESCE(SUM(frais_jolene), 0) FROM factor_advances WHERE statut IN ('FINANCEE','RECOUVREE'))
    );
END;
$function$;

-- 8. GRANTs
GRANT EXECUTE ON FUNCTION public.fn_signer_cession_creance(UUID, TEXT, TEXT, TEXT, TEXT)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_mes_avances_factor()
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_admin_factor_stats()
    TO authenticated;
