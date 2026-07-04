-- Module Sales / Sourcing — annuaire des groupes de recrutement (WhatsApp/Facebook/
-- LinkedIn/Telegram/job boards), contacts sourcés (soignants & établissements),
-- templates de messages, pipeline CRM.
--
-- BONUS : corrige une dette des tables Cockpit (equipe_admin, investisseurs_pipeline,
-- fondateur_documents) dont la RLS était active SANS policy admin → lectures vides
-- côté client. On ajoute les policies admin manquantes.

-- ═══════════════════════════════════════════════════════════
-- 0. Fix RLS cockpit (policies admin manquantes)
-- ═══════════════════════════════════════════════════════════
DROP POLICY IF EXISTS admin_all_equipe_admin ON public.equipe_admin;
CREATE POLICY admin_all_equipe_admin ON public.equipe_admin
  FOR ALL USING (public.est_admin()) WITH CHECK (public.est_admin());

DROP POLICY IF EXISTS admin_all_investisseurs ON public.investisseurs_pipeline;
CREATE POLICY admin_all_investisseurs ON public.investisseurs_pipeline
  FOR ALL USING (public.est_admin()) WITH CHECK (public.est_admin());

DROP POLICY IF EXISTS admin_all_fondateur_documents ON public.fondateur_documents;
CREATE POLICY admin_all_fondateur_documents ON public.fondateur_documents
  FOR ALL USING (public.est_admin()) WITH CHECK (public.est_admin());

-- ═══════════════════════════════════════════════════════════
-- 1. Annuaire des groupes
-- ═══════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.sales_groupes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nom text NOT NULL,
  plateforme text NOT NULL DEFAULT 'WHATSAPP'
    CHECK (plateforme IN ('WHATSAPP','FACEBOOK','LINKEDIN','TELEGRAM','JOBBOARD','AUTRE')),
  profession text NOT NULL DEFAULT 'TOUTES',
  region text,
  url text,
  membres int,
  audience text NOT NULL DEFAULT 'MIXTE'
    CHECK (audience IN ('SOIGNANTS','ETABLISSEMENTS','MIXTE')),
  statut text NOT NULL DEFAULT 'A_VERIFIER'
    CHECK (statut IN ('ACTIF','A_VERIFIER','INACTIF')),
  notes text,
  cree_le timestamptz NOT NULL DEFAULT now(),
  maj_le timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.sales_groupes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS admin_all_sales_groupes ON public.sales_groupes;
CREATE POLICY admin_all_sales_groupes ON public.sales_groupes
  FOR ALL USING (public.est_admin()) WITH CHECK (public.est_admin());

COMMENT ON TABLE public.sales_groupes IS
  'Annuaire des groupes/communautés de recrutement santé par plateforme & profession.';

-- ═══════════════════════════════════════════════════════════
-- 2. Contacts sourcés (soignants & établissements)
-- ═══════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.sales_contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type text NOT NULL DEFAULT 'SOIGNANT'
    CHECK (type IN ('SOIGNANT','ETABLISSEMENT')),
  nom text NOT NULL,
  profession text,
  telephone text,
  email text,
  ville text,
  groupe_id uuid REFERENCES public.sales_groupes(id) ON DELETE SET NULL,
  statut text NOT NULL DEFAULT 'PROSPECT'
    CHECK (statut IN ('PROSPECT','CONTACTE','RELANCE','INSCRIT','PERDU')),
  notes text,
  cree_le timestamptz NOT NULL DEFAULT now(),
  maj_le timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.sales_contacts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS admin_all_sales_contacts ON public.sales_contacts;
CREATE POLICY admin_all_sales_contacts ON public.sales_contacts
  FOR ALL USING (public.est_admin()) WITH CHECK (public.est_admin());

COMMENT ON TABLE public.sales_contacts IS
  'Prospects soignants/établissements sourcés depuis les groupes — pipeline CRM.';

-- ═══════════════════════════════════════════════════════════
-- 3. Templates de messages (publication assistée)
-- ═══════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.sales_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nom text NOT NULL,
  cible text NOT NULL DEFAULT 'GROUPE'
    CHECK (cible IN ('GROUPE','SOIGNANT','ETABLISSEMENT')),
  profession text,
  contenu text NOT NULL,
  cree_le timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.sales_templates ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS admin_all_sales_templates ON public.sales_templates;
CREATE POLICY admin_all_sales_templates ON public.sales_templates
  FOR ALL USING (public.est_admin()) WITH CHECK (public.est_admin());

COMMENT ON TABLE public.sales_templates IS
  'Bibliothèque de templates de posts/messages pour la publication assistée.';

-- ═══════════════════════════════════════════════════════════
-- 4. Seed templates (publication assistée — modifiables)
-- ═══════════════════════════════════════════════════════════
INSERT INTO public.sales_templates (nom, cible, profession, contenu) VALUES
('Post groupe — recrutement soignants', 'GROUPE', NULL,
'Bonjour à tous 👋

Jolene recrute des soignants (IDE, AS, etc.) pour des missions en établissement, partout en France. Inscription 100% gratuite, paiement rapide, missions près de chez vous.

➡️ Inscris-toi : https://jolene.app?utm_source=facebook&utm_medium=groupe&utm_campaign=sourcing
Des questions ? Écrivez-moi en MP 🙂'),
('Post groupe — établissements', 'GROUPE', NULL,
'Bonjour 👋

Vous êtes un établissement de santé et cherchez du personnel soignant rapidement ? Jolene vous met en relation avec des soignants vérifiés, gère contrats & DPAE. Publiez votre besoin en quelques minutes.

➡️ https://jolene.app?utm_source=facebook&utm_medium=groupe&utm_campaign=sourcing_etab'),
('DM soignant — premier contact', 'SOIGNANT', NULL,
'Bonjour {prenom},

Je suis Gabrielle, fondatrice de Jolene. J''ai vu que vous cherchiez des missions. Jolene propose des missions en établissement avec paiement rapide et zéro frais côté soignant. Ça vous intéresse d''en discuter ?'),
('DM établissement — premier contact', 'ETABLISSEMENT', NULL,
'Bonjour,

Je suis Gabrielle, fondatrice de Jolene. Nous aidons les établissements à trouver des soignants vérifiés rapidement (contrats + DPAE gérés). Seriez-vous ouvert à un échange de 10 min cette semaine ?')
ON CONFLICT DO NOTHING;

-- ═══════════════════════════════════════════════════════════
-- 5. Seed groupes candidats (recherche web — À VÉRIFIER par la fondatrice)
--    Job boards publics connus → ACTIF. Groupes Facebook → A_VERIFIER
--    (adhésion/intitulé exact à confirmer). URL absente = à retrouver.
--    Guard : ne s'exécute que si la table est vide (ré-exécution sûre).
-- ═══════════════════════════════════════════════════════════
INSERT INTO public.sales_groupes (nom, plateforme, profession, region, url, audience, statut, notes)
SELECT v.nom, v.plateforme, v.profession, v.region, v.url, v.audience, v.statut, v.notes
FROM (VALUES
  -- Facebook (à vérifier)
  ('IDEL - Rempla France', 'FACEBOOK', 'IDE', 'National', 'https://www.facebook.com/groups/idelremplafrance/', 'MIXTE', 'A_VERIFIER', 'Remplacements IDEL. URL trouvée en recherche.'),
  ('Entraides et Remplacements IDEL - Île-de-France', 'FACEBOOK', 'IDE', 'Île-de-France', 'https://www.facebook.com/groups/1154287448620332/', 'MIXTE', 'A_VERIFIER', 'Régional IDF.'),
  ('Remplaçant ou remplacé IDEL cherche urgent', 'FACEBOOK', 'IDE', 'National', 'https://www.facebook.com/groups/772765116228117', 'MIXTE', 'A_VERIFIER', NULL),
  ('Emploi infirmière', 'FACEBOOK', 'IDE', 'National', 'https://www.facebook.com/emploi.sante.infirmiere/', 'MIXTE', 'A_VERIFIER', 'Page emploi IDE.'),
  ('Remplasoignant', 'FACEBOOK', 'TOUTES', 'National', 'https://www.facebook.com/remplasoignant/', 'MIXTE', 'A_VERIFIER', 'Page remplacement soignant.'),
  ('Vie d''Aides-Soignants', 'FACEBOOK', 'AS', 'National', 'https://www.facebook.com/ViedAideSoignants/', 'SOIGNANTS', 'A_VERIFIER', 'Communauté AS — orientation emploi à confirmer.'),
  ('Remplacement entre Médecin généraliste', 'FACEBOOK', 'MEDECIN', 'National', 'https://www.facebook.com/groups/2016285328550261/', 'MIXTE', 'A_VERIFIER', NULL),
  ('RemplaFrance (remplacement, collaboration, emploi)', 'FACEBOOK', 'TOUTES', 'National', 'https://www.facebook.com/remplafrance.remplacement.collaboration.emploi/', 'MIXTE', 'A_VERIFIER', 'Multi-professions médicales.'),
  ('Médecins Remplaçants de France', 'FACEBOOK', 'MEDECIN', 'National', NULL, 'MIXTE', 'A_VERIFIER', 'Groupe privé cité par plusieurs sources — URL à retrouver.'),
  ('Remplacement sage-femme libérale', 'FACEBOOK', 'SAGE_FEMME', 'National', 'https://www.facebook.com/groups/1579291265781925/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Kiné Annonces – France', 'FACEBOOK', 'KINE', 'National', NULL, 'MIXTE', 'A_VERIFIER', 'Groupe majeur d''annonces cité par rempleo.fr — URL à retrouver.'),
  ('Offre de remplacement/assistanat kiné Haute-Savoie', 'FACEBOOK', 'KINE', 'Auvergne-Rhône-Alpes', 'https://www.facebook.com/groups/253211101808478/', 'MIXTE', 'A_VERIFIER', 'Régional 74.'),
  ('Pharmapro.fr : jobs pharmacien et préparateur', 'FACEBOOK', 'PHARMACIEN', 'National', 'https://www.facebook.com/groups/pharmapro.fr/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Team Officine', 'FACEBOOK', 'PHARMACIEN', 'National', 'https://www.facebook.com/teamofficine/', 'MIXTE', 'A_VERIFIER', 'Emploi officine.'),
  ('Offres emploi médical & dentaire (Evolu''Santé)', 'FACEBOOK', 'DENTISTE', 'National', 'https://www.facebook.com/groups/evolusante.recrutement/', 'ETABLISSEMENTS', 'A_VERIFIER', 'Recrutement médical/dentaire.'),
  ('EMPLOI ERGOTHERAPEUTE', 'FACEBOOK', 'ERGOTHERAPEUTE', 'National', 'https://www.facebook.com/groups/EMPLOIERGOTHERAPEUTE/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Annonces Orthophonistes France', 'FACEBOOK', 'ORTHOPHONISTE', 'National', NULL, 'MIXTE', 'A_VERIFIER', 'Nom confirmé — URL à retrouver.'),
  -- Job boards (réels, publics)
  ('StaffSanté', 'JOBBOARD', 'TOUTES', 'National', 'https://www.staffsante.fr/', 'MIXTE', 'ACTIF', '1er site emploi santé CDI/CDD/intérim.'),
  ('StaffSocial (AES / social)', 'JOBBOARD', 'AES', 'National', 'https://www.staffsocial.fr/', 'MIXTE', 'ACTIF', 'Offres AES / médico-social.'),
  ('Hublo', 'JOBBOARD', 'TOUTES', 'National', 'https://hublo.com/fr', 'MIXTE', 'ACTIF', 'Vacations/remplacements (1M+ pros, 5000+ étabs).'),
  ('Medelse', 'JOBBOARD', 'TOUTES', 'National', 'https://www.medelse.com/', 'MIXTE', 'A_VERIFIER', 'Remplacement/vacation — URL homepage à confirmer.'),
  ('EmploiSoignant', 'JOBBOARD', 'TOUTES', 'National', 'https://www.emploisoignant.com/recherche-offres', 'MIXTE', 'ACTIF', 'Intérim/remplacement.'),
  ('Hellowork (santé)', 'JOBBOARD', 'TOUTES', 'National', 'https://www.hellowork.com/fr-fr/emploi/domaine_sante.html', 'MIXTE', 'ACTIF', '55k+ offres santé.'),
  ('Indeed (santé)', 'JOBBOARD', 'TOUTES', 'National', 'https://fr.indeed.com/q-sant%C3%A9-emplois.html', 'MIXTE', 'ACTIF', '176k+ offres santé.'),
  ('APEC (cadres santé)', 'JOBBOARD', 'TOUTES', 'National', 'https://www.apec.fr/', 'ETABLISSEMENTS', 'ACTIF', 'Encadrement santé.'),
  ('Appel Médical', 'JOBBOARD', 'TOUTES', 'National', 'https://www.appelmedical.com/', 'ETABLISSEMENTS', 'ACTIF', 'Agence intérim médical/paramédical.'),
  ('Adecco Medical', 'JOBBOARD', 'TOUTES', 'National', 'https://www.adecco.com/fr-fr/medical/offres-emploi', 'ETABLISSEMENTS', 'ACTIF', 'Agence intérim médical/paramédical.'),
  ('FHF emploi (hôpital public)', 'JOBBOARD', 'TOUTES', 'National', 'https://emploi.fhf.fr/emploi/search', 'ETABLISSEMENTS', 'ACTIF', 'Fédération Hospitalière de France.'),
  ('France Travail (santé)', 'JOBBOARD', 'TOUTES', 'National', 'https://candidat.francetravail.fr/offres/emploi/sante/s36', 'MIXTE', 'ACTIF', 'Offres publiques santé/social.'),
  ('Samsic Emploi (santé)', 'JOBBOARD', 'AS', 'National', 'https://www.samsic-emploi.fr/nos-offres/aide-soignant-emploi', 'ETABLISSEMENTS', 'ACTIF', 'Agence intérim.'),
  ('Jobvitae', 'JOBBOARD', 'TOUTES', 'National', 'https://www.jobvitae.fr/', 'MIXTE', 'ACTIF', 'Job board santé/médical/social.'),
  ('RemplaJob (RemplaFrance)', 'JOBBOARD', 'MEDECIN', 'National', 'https://remplajob.com/', 'MIXTE', 'ACTIF', 'Remplacement multi-professions médicales.'),
  ('Médecins Remplaçants de France (annonces)', 'JOBBOARD', 'MEDECIN', 'National', 'https://medecinsremplacants.org/annonces', 'MIXTE', 'ACTIF', NULL),
  ('Infirmea', 'JOBBOARD', 'IDE', 'National', 'https://infirmea.fr/', 'MIXTE', 'A_VERIFIER', 'App remplacement IDEL.'),
  ('Rempleo (kiné)', 'JOBBOARD', 'KINE', 'National', 'https://rempleo.fr/annonces/kine/remplacement', 'MIXTE', 'ACTIF', '2000+ annonces remplacement kiné.'),
  ('Physiojob', 'JOBBOARD', 'KINE', 'National', 'https://www.physiojob.com/annonces-remplacement-kine/', 'MIXTE', 'ACTIF', NULL),
  ('Club Officine', 'JOBBOARD', 'PHARMACIEN', 'National', 'https://www.clubofficine.fr/', 'MIXTE', 'ACTIF', 'Emploi pharmacien/préparateur.'),
  ('Dentiste-Remplacant.com', 'JOBBOARD', 'DENTISTE', 'National', 'https://www.dentiste-remplacant.com/', 'MIXTE', 'ACTIF', 'Remplacement/collaboration dentaire.'),
  ('Orthomalin (annonces)', 'JOBBOARD', 'ORTHOPHONISTE', 'National', 'https://www.orthomalin.com/petites-annonces', 'MIXTE', 'ACTIF', NULL),
  ('App''Ines', 'JOBBOARD', 'PSYCHOMOTRICIEN', 'National', 'https://appines.fr/annonces/', 'MIXTE', 'ACTIF', 'Remplacement paramédical (psychomot, ergo…).'),
  ('AFPPE (manip radio)', 'JOBBOARD', 'MANIPULATEUR_RADIO', 'National', 'https://new.afppe.com/job_offers/', 'MIXTE', 'ACTIF', 'Offres MERM.'),
  ('Ordre des sages-femmes (offres)', 'JOBBOARD', 'SAGE_FEMME', 'National', 'https://www.ordre-sages-femmes.fr/demarches/offres-emploi-sages-femmes/', 'MIXTE', 'ACTIF', NULL),
  ('LinkedIn Jobs — Infirmier France', 'LINKEDIN', 'IDE', 'National', 'https://fr.linkedin.com/jobs/infirmier-emplois', 'MIXTE', 'ACTIF', 'Page jobs (pas groupe communautaire).')
) AS v(nom, plateforme, profession, region, url, audience, statut, notes)
WHERE NOT EXISTS (SELECT 1 FROM public.sales_groupes);
