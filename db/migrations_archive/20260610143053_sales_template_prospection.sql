-- Prospection email 1-clic : colonne sujet sur les templates + template officiel
-- de prospection établissement (placeholders {{nom}} / {{ville}}), éditable depuis
-- l'onglet Templates — utilisé par le mailto pré-rempli ET l'envoi direct Resend.
-- NOTE : déjà appliquée en prod via MCP (version 20260610143053).
ALTER TABLE public.sales_templates ADD COLUMN IF NOT EXISTS sujet text;

INSERT INTO public.sales_templates (nom, cible, contenu, sujet)
SELECT 'Email prospection établissement', 'ETABLISSEMENT',
E'Bonjour,\n\nJe suis Gabrielle, fondatrice de Jolene (jolene.app), la plateforme qui met en relation les établissements de santé avec des soignants vérifiés — diplômes, RPPS et assurances contrôlés.\n\nConcrètement pour {{nom}} :\n• Publiez un besoin en 2 minutes, recevez des candidatures de soignants notés et vérifiés\n• Contrats et déclarations générés automatiquement\n• 15 % de commission tout compris — et pour nos premiers partenaires : 0 % sur vos 5 premières missions\n\nAuriez-vous 10 minutes cette semaine pour en parler ? Vous pouvez répondre directement à cet email.\n\nBien cordialement,\nGabrielle — Fondatrice de Jolene\njolene.app',
'Renfort soignant sous 48h pour {{nom}} — sans engagement'
WHERE NOT EXISTS (SELECT 1 FROM public.sales_templates WHERE nom = 'Email prospection établissement');
