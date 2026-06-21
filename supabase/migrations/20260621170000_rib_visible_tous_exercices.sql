-- Le RIB était sur-restreint à LIBERAL_ONLY (matrice documents du 27/05/2026,
-- migration 20260527155700_documents_requis_matrice_exercice), ce qui le masquait
-- aux soignants SALARIÉS dans la page Documents (le filtre cache les LIBERAL_ONLY
-- aux non-libéraux). Or le paiement d'une mission salariée (VIREMENT_PAIE) côté
-- établissement consulte ce RIB via fn_consulter_rib_soignant → contradiction :
-- l'établissement a besoin du RIB pour payer, mais le salarié ne pouvait pas le
-- déposer. On rétablit la visibilité : RIB requis pour TOUS les types d'exercice.
update public.documents_requis_par_profession
set type_exercice_requis = 'TOUS'
where type_document = 'RIB'
  and type_exercice_requis = 'LIBERAL_ONLY';
