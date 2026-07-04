-- Nettoyage des guillemets parasites (sur-échappement CSV) dans les bases de
-- prospection + contacts sourcés. Un " littéral n'est jamais légitime dans un
-- nom/adresse/ville d'établissement ou de soignant FR → on les retire et on
-- normalise les espaces. Les imports sont hardenisés en parallèle (nettoie()).
UPDATE public.prospects_etablissements
SET nom     = btrim(regexp_replace(replace(nom, '"', ''),     '\s+', ' ', 'g')),
    ville   = btrim(regexp_replace(replace(ville, '"', ''),   '\s+', ' ', 'g')),
    adresse = btrim(regexp_replace(replace(adresse, '"', ''), '\s+', ' ', 'g'))
WHERE nom LIKE '%"%' OR ville LIKE '%"%' OR adresse LIKE '%"%';

UPDATE public.prospects_soignants
SET nom      = btrim(regexp_replace(replace(nom, '"', ''),      '\s+', ' ', 'g')),
    ville    = btrim(regexp_replace(replace(ville, '"', ''),    '\s+', ' ', 'g')),
    enseigne = btrim(regexp_replace(replace(enseigne, '"', ''), '\s+', ' ', 'g'))
WHERE nom LIKE '%"%' OR ville LIKE '%"%' OR enseigne LIKE '%"%';

UPDATE public.sales_contacts
SET nom   = btrim(regexp_replace(replace(nom, '"', ''),   '\s+', ' ', 'g')),
    ville = btrim(regexp_replace(replace(ville, '"', ''), '\s+', ' ', 'g'))
WHERE nom LIKE '%"%' OR ville LIKE '%"%';

-- La garantie de remplacement EST construite et opérationnelle (toggle + détection
-- no-show + mission de remplacement auto). Seul le SURCOÛT n'est pas facturé
-- (gratuit, offre de lancement). On clarifie la description du paramètre.
UPDATE public.parametres_systeme
SET description = 'Surcoût en % de l''option garantie de remplacement. La garantie est active et GRATUITE (offre de lancement) ; ce surcoût n''est pas encore facturé.',
    avertissement = 'La facturation du surcoût n''est pas branchée : changer cette valeur n''a aucun effet tant que la monétisation n''est pas construite.'
WHERE cle = 'garantie_remplacement_prix_pct';
