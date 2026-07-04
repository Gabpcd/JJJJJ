-- Le frontend (src/lib/constantes.ts) propose déjà 'DENTISTE' (Chirurgien-Dentiste)
-- et 'AUXILIAIRE_PUERICULTURE' à l'inscription, mais l'enum type_profession ne les
-- contenait pas → l'enregistrement échouait (enum invalide) pour ces 2 professions.
-- On synchronise l'enum. (ADD VALUE seul, sans usage dans la même transaction ;
-- la config liberal/documents est posée dans la migration suivante, après commit.)
ALTER TYPE public.type_profession ADD VALUE IF NOT EXISTS 'DENTISTE';
ALTER TYPE public.type_profession ADD VALUE IF NOT EXISTS 'AUXILIAIRE_PUERICULTURE';
