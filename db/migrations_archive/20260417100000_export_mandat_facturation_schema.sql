-- ============================================================
-- Export schéma prod : mandat de facturation art. 289 I-2 CGI
-- ============================================================
-- Cette migration reproduit le schéma existant en prod (créé via
-- dashboard/MCP). Marquée "applied" pour ne pas être rejouée.
-- ============================================================

-- 1. Table mandats_facturation_signatures
CREATE TABLE IF NOT EXISTS public.mandats_facturation_signatures (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    soignant_id     UUID NOT NULL REFERENCES public.soignants(id) ON DELETE CASCADE,
    version         TEXT NOT NULL,
    signed_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    ip_address      TEXT,
    user_agent      TEXT,
    contenu_hash    TEXT,
    cree_le         TIMESTAMPTZ NOT NULL DEFAULT now(),
    pdf_url         TEXT,
    revoked_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_mandats_soignant
    ON public.mandats_facturation_signatures (soignant_id, signed_at DESC);

-- 2. Colonnes soignants
ALTER TABLE public.soignants
    ADD COLUMN IF NOT EXISTS mandat_facturation_signe BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS mandat_facturation_signe_le TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS mandat_facturation_version TEXT;

-- 3. RLS
ALTER TABLE public.mandats_facturation_signatures ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'mandats_facturation_signatures' AND policyname = 'Admin lit tout') THEN
        CREATE POLICY "Admin lit tout" ON public.mandats_facturation_signatures FOR SELECT USING (est_admin());
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'mandats_facturation_signatures' AND policyname = 'Soignant lit ses signatures') THEN
        CREATE POLICY "Soignant lit ses signatures" ON public.mandats_facturation_signatures FOR SELECT USING (auth.uid() = soignant_id);
    END IF;
END $$;

-- 4. RPC fn_signer_mandat_facturation
CREATE OR REPLACE FUNCTION public.fn_signer_mandat_facturation(
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
    v_signature_id UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN '{"error":"Non authentifié"}'::JSONB;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM soignants WHERE id = v_user_id AND supprime_le IS NULL) THEN
        RETURN '{"error":"Seuls les soignants peuvent signer ce mandat"}'::JSONB;
    END IF;

    INSERT INTO mandats_facturation_signatures (soignant_id, version, ip_address, user_agent, contenu_hash)
    VALUES (v_user_id, p_version, p_ip, p_user_agent, p_contenu_hash)
    RETURNING id INTO v_signature_id;

    UPDATE soignants SET
        mandat_facturation_signe = TRUE,
        mandat_facturation_signe_le = now(),
        mandat_facturation_version = p_version
    WHERE id = v_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'signature_id', v_signature_id,
        'version', p_version,
        'signed_at', now()
    );
END;
$function$;

-- 5. GRANTs
GRANT EXECUTE ON FUNCTION public.fn_signer_mandat_facturation(TEXT, TEXT, TEXT, TEXT)
    TO authenticated;
