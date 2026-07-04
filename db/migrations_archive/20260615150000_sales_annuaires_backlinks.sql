-- Annuaires / backlinks : liste suivie dans l'admin (acquisition SEO).
CREATE TABLE IF NOT EXISTS public.sales_annuaires (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nom text NOT NULL,
  url text NOT NULL,
  categorie text NOT NULL DEFAULT 'GENERAL',
  autorite text NOT NULL DEFAULT 'MOYENNE',
  gratuit boolean NOT NULL DEFAULT true,
  comment_soumettre text,
  texte_a_soumettre text,
  statut text NOT NULL DEFAULT 'A_SOUMETTRE',
  lien_obtenu text,
  notes text,
  favori boolean NOT NULL DEFAULT false,
  cree_le timestamptz NOT NULL DEFAULT now(),
  maj_le timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT sales_annuaires_statut_check CHECK (statut IN ('A_SOUMETTRE','SOUMIS','PUBLIE','REFUSE')),
  CONSTRAINT sales_annuaires_autorite_check CHECK (autorite IN ('ELEVEE','MOYENNE','FAIBLE'))
);

ALTER TABLE public.sales_annuaires ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_sales_annuaires_admin ON public.sales_annuaires;
CREATE POLICY pol_sales_annuaires_admin ON public.sales_annuaires
  FOR ALL TO authenticated USING (public.est_admin()) WITH CHECK (public.est_admin());
GRANT ALL ON public.sales_annuaires TO authenticated, service_role;

-- Seed : annuaires réels où soumettre Jolene Santé (gratuits sauf mention).
INSERT INTO public.sales_annuaires (nom, url, categorie, autorite, gratuit, comment_soumettre)
SELECT * FROM (VALUES
 ('Appvizer','https://www.appvizer.fr','SAAS','ELEVEE',true,$c$En bas de page : « Référencer mon logiciel ». Annuaire SaaS français de référence.$c$),
 ('Capterra France','https://www.capterra.fr','SAAS','ELEVEE',true,$c$Compte vendeur (Gartner Digital Markets) — couvre aussi GetApp et Software Advice.$c$),
 ('GetApp','https://www.getapp.fr','SAAS','ELEVEE',true,$c$Même inscription que Capterra (groupe Gartner). Vérifiez que la fiche apparaît.$c$),
 ('G2','https://www.g2.com','SAAS','ELEVEE',true,$c$« Add your product » (gratuit). Avis logiciels, très forte autorité de domaine.$c$),
 ('Product Hunt','https://www.producthunt.com','STARTUP','ELEVEE',true,$c$« Submit » votre produit. Idéal le jour du lancement (pic de trafic + backlink).$c$),
 ('BetaList','https://betalist.com','STARTUP','MOYENNE',true,$c$« Submit a startup ». Pour les startups en phase de lancement.$c$),
 ('Crunchbase','https://www.crunchbase.com','STARTUP','ELEVEE',true,$c$Créez le profil entreprise (« Add a company », gratuit).$c$),
 ('Welcome to the Jungle','https://www.welcometothejungle.com','EMPLOI','ELEVEE',true,$c$Page entreprise gratuite. Double bénéfice : recrutement + autorité SEO.$c$),
 ('Les Pépites Tech','https://lespepitestech.com','STARTUP','MOYENNE',true,$c$Annuaire des startups françaises. Soumettez votre startup.$c$),
 ('Société.com','https://www.societe.com','B2B','ELEVEE',true,$c$Fiche auto-générée via votre SIREN. Réclamez et complétez la fiche Jolene SAS (ajout du lien site web).$c$),
 ('PagesJaunes','https://www.pagesjaunes.fr','GENERAL','ELEVEE',true,$c$Créez une fiche professionnelle gratuite avec lien vers jolene.app.$c$),
 ('Kompass','https://fr.kompass.com','B2B','MOYENNE',true,$c$Inscription entreprise de base gratuite.$c$),
 ('Europages','https://www.europages.fr','B2B','MOYENNE',true,$c$Référencement entreprise B2B européen, offre gratuite.$c$),
 ('La French Tech','https://lafrenchtech.gouv.fr','STARTUP','ELEVEE',true,$c$Annuaire de l'écosystème. Vérifiez l'éligibilité via votre Communauté French Tech locale.$c$)
) v
WHERE NOT EXISTS (SELECT 1 FROM public.sales_annuaires);

UPDATE public.sales_annuaires SET texte_a_soumettre = $m$Jolene Santé est la plateforme qui met en relation directe les établissements de santé (EHPAD, cliniques, hôpitaux, pharmacies) et les soignants vérifiés — diplôme, RPPS et assurance contrôlés. Publiez ou trouvez des missions et remplacements ponctuels, avec contrats et démarches automatisés. Inscription gratuite pour les soignants, 15 % de commission tout compris pour les établissements, sans engagement.$m$
WHERE texte_a_soumettre IS NULL;

UPDATE public.sales_annuaires SET texte_a_soumettre = $s$Jolene Santé connecte établissements de santé et soignants vérifiés pour des missions et remplacements ponctuels. Inscription gratuite, contrats automatisés.$s$
WHERE nom IN ('BetaList','Société.com','Kompass','Europages');
