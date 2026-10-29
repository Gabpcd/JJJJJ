-- Contrat historique des dix triggers de la recette dashboard du 30 septembre.
-- Extrait du snapshot 442a0d1c73ed1c15b0b0e47cc52fa159fb162753 ; aucune activation de recette.
-- Les triggers ajoutés ensuite doivent continuer à faire refuser ce contrat historique.

CREATE OR REPLACE TRIGGER "dec_age_minimum" BEFORE INSERT OR UPDATE ON "public"."soignants" FOR EACH ROW EXECUTE FUNCTION "public"."dec_verifier_age_minimum"();
CREATE OR REPLACE TRIGGER "dec_bloquer_desinscrip" BEFORE UPDATE ON "public"."soignants" FOR EACH ROW EXECUTE FUNCTION "public"."dec_bloquer_desinscription_missions"();
CREATE OR REPLACE TRIGGER "trg_00_verrouiller_transition_liberale" BEFORE UPDATE ON "public"."soignants" FOR EACH ROW EXECUTE FUNCTION "public"."fn_verrouiller_transition_liberale"();
CREATE OR REPLACE TRIGGER "trg_mirror_teleportation_alerte_systeme" AFTER INSERT ON "public"."journaux_audit" FOR EACH ROW EXECUTE FUNCTION "public"."fn_mirror_teleportation_alerte_systeme"();
CREATE OR REPLACE TRIGGER "trg_protect_adeli_verification" BEFORE UPDATE ON "public"."soignants" FOR EACH ROW EXECUTE FUNCTION "public"."fn_protect_adeli_verification"();
CREATE OR REPLACE TRIGGER "trg_protect_soignant_verification" BEFORE UPDATE ON "public"."soignants" FOR EACH ROW EXECUTE FUNCTION "public"."fn_protect_soignant_verification"();
CREATE OR REPLACE TRIGGER "trg_protect_specialite_medicale_verifiee" BEFORE UPDATE ON "public"."soignants" FOR EACH ROW EXECUTE FUNCTION "public"."fn_protect_specialite_medicale_verifiee"();
CREATE OR REPLACE TRIGGER "trg_proteger_verification_siret_liberal" BEFORE UPDATE ON "public"."soignants" FOR EACH ROW EXECUTE FUNCTION "public"."fn_proteger_verification_siret_liberal"();
CREATE OR REPLACE TRIGGER "trg_sync_types_contrat" BEFORE UPDATE ON "public"."soignants" FOR EACH ROW EXECUTE FUNCTION "public"."dec_sync_types_contrat_exercice"();
CREATE OR REPLACE TRIGGER "trg_verifier_type_exercice" BEFORE INSERT OR UPDATE ON "public"."soignants" FOR EACH ROW EXECUTE FUNCTION "public"."dec_verifier_type_exercice_profession"();
