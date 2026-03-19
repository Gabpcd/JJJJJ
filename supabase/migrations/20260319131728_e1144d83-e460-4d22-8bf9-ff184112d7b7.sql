
-- FIX tokens push
DROP POLICY IF EXISTS pol_token_insert ON tokens_push;
CREATE POLICY pol_token_insert ON tokens_push FOR INSERT TO authenticated 
WITH CHECK (utilisateur_id = auth.uid());

-- FIX tokens calendrier
DROP POLICY IF EXISTS pol_tcal_insert ON tokens_calendrier;
CREATE POLICY pol_tcal_insert ON tokens_calendrier FOR INSERT TO authenticated 
WITH CHECK (soignant_id = auth.uid());

-- FIX evaluations
DROP POLICY IF EXISTS pol_eval_insert ON evaluations;
CREATE POLICY pol_eval_insert ON evaluations FOR INSERT TO authenticated 
WITH CHECK (
    evaluateur_id = auth.uid()
    AND (
        mission_id IN (SELECT id FROM missions WHERE soignant_assigne_id = auth.uid())
        OR mission_id IN (SELECT id FROM missions WHERE etablissement_id = mon_etablissement_id())
        OR est_admin()
    )
);

-- FIX litiges
DROP POLICY IF EXISTS pol_litige_insert ON litiges;
CREATE POLICY pol_litige_insert ON litiges FOR INSERT TO authenticated 
WITH CHECK (
    est_admin()
    OR (soignant_id = auth.uid() AND mission_id IN (SELECT id FROM missions WHERE soignant_assigne_id = auth.uid()))
    OR (etablissement_id = mon_etablissement_id() AND mission_id IN (SELECT id FROM missions WHERE etablissement_id = mon_etablissement_id()))
);

-- FIX candidatures INSERT
DROP POLICY IF EXISTS pol_cand_insert ON candidatures;
CREATE POLICY pol_cand_insert ON candidatures FOR INSERT TO authenticated 
WITH CHECK (
    soignant_id = auth.uid()
    OR est_admin()
    OR mission_id IN (SELECT id FROM missions WHERE etablissement_id = mon_etablissement_id())
);

-- FIX presences INSERT
DROP POLICY IF EXISTS pol_pres_insert ON presences;
CREATE POLICY pol_pres_insert ON presences FOR INSERT TO authenticated 
WITH CHECK (
    soignant_id = auth.uid()
    OR est_admin()
    OR mission_id IN (SELECT id FROM missions WHERE etablissement_id = mon_etablissement_id())
);

-- FIX messages_chat INSERT
DROP POLICY IF EXISTS pol_msg_chat_insert ON messages_chat;
CREATE POLICY pol_msg_chat_insert ON messages_chat FOR INSERT TO authenticated 
WITH CHECK (
    auteur_id = auth.uid()
);

-- FIX parrainages INSERT
DROP POLICY IF EXISTS pol_parr_insert ON parrainages;
CREATE POLICY pol_parr_insert ON parrainages FOR INSERT TO authenticated 
WITH CHECK (parrain_id = auth.uid() OR est_admin());

-- FIX conversations INSERT
DROP POLICY IF EXISTS pol_conv_insert ON conversations;
CREATE POLICY pol_conv_insert ON conversations FOR INSERT TO authenticated 
WITH CHECK (
    participant_1_id = auth.uid() OR participant_2_id = auth.uid() OR est_admin()
);

-- FIX journaux_audit INSERT
DROP POLICY IF EXISTS pol_audit_insert ON journaux_audit;
CREATE POLICY pol_audit_insert ON journaux_audit FOR INSERT TO authenticated 
WITH CHECK (true);

-- FIX contrats INSERT
DROP POLICY IF EXISTS pol_contrat_insert ON contrats_mission;
CREATE POLICY pol_contrat_insert ON contrats_mission FOR INSERT TO authenticated 
WITH CHECK (est_admin());
