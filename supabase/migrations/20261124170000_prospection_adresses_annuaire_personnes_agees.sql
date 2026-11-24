-- Prospection : adresses de contact publiques des établissements pour personnes âgées (24/11/2026).
--
-- Constat (lecture seule, 24/11) : sur les 2 318 établissements ciblés des
-- départements pilotes (75, 92, 56), 656 ont une adresse et toutes sont en
-- messagerie de santé fermée (MSSanté, Apicrypt). L'agent de prospection par
-- email n'a donc aucune cible (20261124123500 le rend visible).
--
-- Source ajoutée : l'annuaire officiel des établissements pour personnes âgées
-- (pour-les-personnes-agees.gouv.fr, portail de la CNSA), tel que republié en
-- données ouvertes sur data.gouv.fr (jeu « issu du site », sans organisation ;
-- le compte qui l'a publié a été supprimé depuis) :
--   jeu     « Etablissements EHPAD, ESLD, résidences autonomie, accueils de jour »,
--           identifiant 5ca48257634f414eb3f14803, Licence Ouverte 2.0 ;
--   fichier base-etablissements.csv publié le 11/11/2020 (dernière publication),
--           sha256 6d57e557a44365ea2b41ea52f794e9a33df26cf1d21c0747dc3e67a3609b5670,
--           relevé le 24/11/2026 ;
--   site d'origine, « Mentions légales », lu le 24/11/2026 : les contenus sont
--           « librement et gratuitement réutilisables », à l'exception notamment de
--           ceux « contenant des données personnelles » ; le site demande aussi
--           d'être contacté par qui réutilise ses contenus.
-- Le fichier porte 10 901 lignes. Le script reproductible
-- scripts/acquisition/extraire-annuaire-personnes-agees.mjs en importe 5138 :
-- un FINESS à neuf chiffres et une adresse qui porte un mot de fonction ou de
-- type d'établissement (contact, direction, accueil, ehpad…), et dont tout le
-- reste de l'identifiant s'explique par le nom de l'établissement ou de sa
-- commune (le champ « gestionnaire » n'est pas lu, ce peut être une personne
-- physique). Ne sont PAS importées : 1 610 adresses au seul nom de la
-- structure (classe S : un établissement peut porter le nom d'une personne,
-- et rien dans le fichier ne le distingue), 3 509 adresses qui peuvent
-- nommer une personne (« prenom.nom@ », initiale isolée, mot inexpliqué, prénom
-- sans mot de fonction, « mr.nom@ »), 22 dont le domaine est à une faute de
-- frappe d'un domaine courant, 568 lignes sans adresse, 16 adresses mal
-- formées, 38 établissements de Corse dont ce script ne lit pas le FINESS
-- (2A, 2B). Aucune adresse n'est devinée, aucune n'est en messagerie de santé
-- fermée. Le tri reste une heuristique ; chaque brouillon est relu avant envoi.
--
-- Ce que fait la migration :
--   1. Colonne prospects_etablissements.email_provenance (jsonb) : l'adresse
--      décrite, sa source, l'adresse de la page du jeu, la date de publication,
--      la date de mise à jour de la fiche, la date du relevé, la classe, et
--      l'ancienne adresse fermée qu'elle remplace. La provenance ne vaut que si
--      son adresse est encore celle du prospect : une adresse modifiée ensuite
--      (à la main, par un autre import) n'hérite pas d'une source qui n'est plus
--      la sienne.
--   2. Import : l'adresse du jeu est écrite sur le prospect de même FINESS quand
--      il n'a pas d'adresse ou une adresse en messagerie fermée (ou mal formée).
--      Une adresse ouverte existante est conservée. Un prospect en opposition
--      n'est pas touché. Les compteurs du sourcing suivent par leur trigger.
--      Trois invariants sont contrôlés après l'écriture, sinon tout est annulé :
--      aucune adresse ouverte du bloc n'a changé, aucun prospect en opposition
--      ne porte de provenance, et les comptes se recoupent.
--   3. private.fn_growth_email_source : provenance valide d'une adresse.
--      private.fn_growth_mention_opposition : source UNIQUE de la mention
--      d'opposition d'un email de prospection. La mention existante
--      (growth_config.prospection_mention_opposition) cite « répertoire FINESS et
--      Annuaire Santé » : elle serait fausse pour une adresse venue de cet
--      annuaire. La mention de l'annuaire reprend mot pour mot la phrase
--      d'opposition existante, et ne change que l'origine déclarée
--      (tests/node/prospection-adresses-publiques.node.mjs compare les deux).
--      Défaut porté par le code, clé facultative
--      prospection_mention_opposition_annuaire_pa ; aucune écriture dans
--      growth_config. Une origine que ce code ne connaît pas n'a pas de mention :
--      aucun brouillon n'est préparé, et l'agent le compte (verrou explicite).
--      C'est le cas d'une provenance SAISIE_MANUELLE (code prévu pour les
--      adresses saisies à la main ; aucun écran ne le pose encore) et de toute adresse d'un établissement dont le
--      prospect porte une provenance qui décrit une AUTRE adresse (adresse du
--      prospect changée depuis l'import, fiche CRM corrigée à la main). La
--      mention historique reste celle des établissements sans provenance.
--   4. Agent email : corps LIVE (20261124123500) repris à l'identique, à six
--      endroits près — mention selon l'origine de l'adresse pour les premiers
--      contacts ET les relances, source et provenance dans le contexte du
--      brouillon (premier contact et relance), compteur exclus_sans_mention
--      dans le résultat.
--   5. Décompte : clé adresses_annuaire_public (adresses utilisables dont la
--      provenance est valide et n'est pas une saisie manuelle).
--   6. Agent d'appels : corps LIVE (20261124123500) repris à l'identique, à un
--      critère de tri près. Jusqu'ici aucune cible n'avait d'adresse utilisable ;
--      désormais un EHPAD peut être joint par email. Les fiches d'appel vont
--      d'abord aux établissements qu'aucun email ne peut joindre, pour que les
--      deux agents ne se disputent pas les mêmes cibles (une cible n'a qu'un
--      canal à la fois).
-- Rien n'est envoyé : l'agent écrit des brouillons, la fondatrice valide et
-- envoie elle-même. Décision et sources : docs/AGENTS_CROISSANCE.md §4 ter et §5.
--
-- Aucun BEGIN/COMMIT : la CLI ou le banc appelant possède la transaction.
SET LOCAL lock_timeout = '5s';

-- ---------------------------------------------------------------------------
-- 0. Préflight fail-closed : corps LIVE attendus (ceux de 20261124123500),
--    colonne et fonctions neuves absentes
-- ---------------------------------------------------------------------------
DO $adresses_publiques_avant$
DECLARE
  p record;
BEGIN
  FOR p IN
    SELECT v.signature, v.empreinte, v.volatilite,
           f.prosrc, f.prosecdef, f.provolatile, f.proconfig
    FROM (VALUES
      ('private.fn_growth_agent_prospection()', 'fe559b7040a3e6647317a050acd44094', 'v'),
      ('private.fn_growth_agent_appels()', 'edfda5a16fe5c3ec59eb73e6f2bf021c', 'v'),
      ('private.fn_growth_cibles_prospection()', 'c70e65a8dfdd12743c89a5d2b78770ed', 's'),
      ('private.fn_growth_prospects_cibles()', 'c740121ca64462667302f7172c62ff2d', 's'),
      ('private.fn_growth_email_mssante(text)', '6b76fa42d9128f71408afcc04a66e96c', 'i')
    ) AS v(signature, empreinte, volatilite)
    LEFT JOIN pg_catalog.pg_proc f ON f.oid = pg_catalog.to_regprocedure(v.signature)
  LOOP
    IF p.prosrc IS NULL
      OR pg_catalog.md5(p.prosrc) <> p.empreinte
      OR p.prosecdef IS NOT FALSE
      OR p.provolatile::text <> p.volatilite
      OR p.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
    THEN
      RAISE EXCEPTION 'ADRESSES_PUBLIQUES_SOURCE_AVANT_DIVERGENTE : % en base (md5 %, prosecdef %, volatilité %, search_path %) ne correspond plus au corps du dépôt (md5 %, volatilité %, search_path vide). Redéfinition refusée : repartir de la définition LIVE (CLAUDE.md, garde-fous 9.0 n°2).',
        p.signature, COALESCE(pg_catalog.md5(p.prosrc), 'fonction absente'), p.prosecdef, p.provolatile, p.proconfig,
        p.empreinte, p.volatilite;
    END IF;
  END LOOP;

  IF pg_catalog.to_regprocedure('private.fn_growth_config(text,text)') IS NULL THEN
    RAISE EXCEPTION 'ADRESSES_PUBLIQUES_CONFIG_ABSENTE : private.fn_growth_config(text,text) absente.';
  END IF;
  IF pg_catalog.to_regprocedure('private.fn_growth_email_source(text,text)') IS NOT NULL
    OR pg_catalog.to_regprocedure('private.fn_growth_mention_opposition(text,text)') IS NOT NULL
  THEN
    RAISE EXCEPTION 'ADRESSES_PUBLIQUES_HELPER_DEJA_PRESENT : une fonction private.fn_growth_* de ce lot existe déjà en base sans migration du dépôt. Repartir de la définition LIVE (CLAUDE.md, garde-fous 9.0 n°2).';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
             WHERE a.attrelid = 'public.prospects_etablissements'::pg_catalog.regclass
               AND a.attname = 'email_provenance' AND NOT a.attisdropped) THEN
    RAISE EXCEPTION 'ADRESSES_PUBLIQUES_COLONNE_DEJA_PRESENTE : prospects_etablissements.email_provenance existe déjà sans migration du dépôt.';
  END IF;
END;
$adresses_publiques_avant$;

-- ---------------------------------------------------------------------------
-- 1. Provenance d'une adresse de contact
-- ---------------------------------------------------------------------------
ALTER TABLE public.prospects_etablissements
  ADD COLUMN email_provenance jsonb,
  ADD CONSTRAINT prospects_etab_email_provenance_forme CHECK (
    email_provenance IS NULL
    OR (jsonb_typeof(email_provenance) = 'object'
        AND COALESCE(email_provenance->>'email', '') ~ '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$'
        AND COALESCE(email_provenance->>'email', '') !~ '[@.](mssante\.fr|apicrypt\.org)$'
        AND COALESCE(email_provenance->>'source_code', '') ~ '^[A-Z0-9_]{3,60}$'
        -- Une saisie manuelle n'a pas de page source ; toute autre origine en a une.
        AND (email_provenance->>'source_code' = 'SAISIE_MANUELLE'
             OR COALESCE(email_provenance->>'source_url', '') ~ '^https://')
        AND COALESCE(email_provenance->>'releve_le', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$')
  );

COMMENT ON COLUMN public.prospects_etablissements.email_provenance IS
  'Origine de l''adresse de contact quand elle vient d''un annuaire public ouvert : email (l''adresse décrite), source_code, source_url, source_publie_le, source_maj_le, releve_le, classe (FONCTION), remplace (ancienne adresse en messagerie fermée). Ne vaut que si email est encore l''adresse du prospect (private.fn_growth_email_source). source_code SAISIE_MANUELLE : code prévu pour une adresse saisie à la main, sans page source ; aucun écran ne le pose encore. NULL : adresse historique (FINESS, Annuaire Santé) ou saisie à la main.';

-- ---------------------------------------------------------------------------
-- 2. Import des adresses retenues par le script reproductible
-- ---------------------------------------------------------------------------
-- Une ligne par établissement : FINESS ; adresse ; classe (F : mot de fonction,
-- seule classe importée) ; date de mise à jour de la fiche dans le jeu.
-- Bloc produit par :
--   node scripts/acquisition/extraire-annuaire-personnes-agees.mjs base-etablissements.csv --sql bloc
-- 5138 lignes, md5 6dc0d75a074214ed5ac3e390b0ae1d50 (contrôlé ci-dessous et par la garde Node).
DO $adresses_publiques_import$
DECLARE
  v_donnees text := $adresses_publiques_donnees$
010001246;direction@ajmarpa.fr;F;2020-10-04
010001360;marpa.montracol@orange.fr;F;2020-10-04
010002228;direction.amberieu@orpea.net;F;2020-10-04
010004059;accueil@orsac-lecloschevalier.fr;F;2020-10-04
010007078;direction@ajmarpa.fr;F;2020-10-04
010007268;accueil@ville-beynost.fr;F;2020-10-04
010008332;marpa.plain-champ@wanadoo.fr;F;2020-10-04
010008399;direction@ajmarpa.fr;F;2020-10-04
010008589;marpaleverger@orange.fr;F;2020-10-04
010008670;lacitedesseniors@orange.fr;F;2020-10-04
010008696;marpa.lescarlines@gmail.com;F;2020-10-04
010008738;marpa-verchere@orange.fr;F;2020-10-04
010008753;marpalerenon01@orange.fr;F;2020-10-04
010008795;mairie@mairievlm.fr;F;2020-10-04
010008829;marpabrenod@orange.fr;F;2020-10-04
010009066;accueil@fede01.admr.org;F;2020-10-04
010010270;marpagrieges@orange.fr;F;2020-10-04
010010494;accueil.angeville@croix-rouge.fr;F;2020-10-04
010010684;marpalareyssouze@orange.fr;F;2020-10-04
010780013;divonne.accueil@ch-paysdegex.fr;F;2020-10-04
010780849;grex-accueil@itinova.org;F;2020-10-09
010780906;ehpadamberieu@fontelune.fr;F;2020-10-04
010780914;contact@ehpadbage.fr;F;2020-10-04
010780922;mr.cerdon@ehpad-cerdon.fr;F;2020-10-04
010780930;mdrcostaz@orange.fr;F;2020-10-04
010780955;accueil.coligny@orange.fr;F;2020-10-04
010780963;direction@ehpad-lagnieu.fr;F;2020-10-09
010780971;contact@ehpadmontluel.fr;F;2020-10-04
010780989;ehpadmontmerle@orange.fr;F;2020-10-04
010781003;ehpadtriviercourtes@ehpad01560.fr;F;2020-10-04
010781011;direction@ehpadsaulaies.fr;F;2020-10-04
010781029;ehpadtenay@maisonsoie.fr;F;2020-10-04
010781037;contact@ehpadvillars.fr;F;2020-10-04
010781078;contact@ehpad-pontdain.fr;F;2020-10-04
010784106;rosalie-secretariat@itinova.org;F;2020-10-04
010784114;secretariat@arygeoffray.fr;F;2020-10-04
010784130;mr.bellegarde@croix-rouge.fr;F;2020-10-04
010784429;info@ch-avs.fr;F;2020-10-09
010784437;info@ch-avs.fr;F;2020-10-04
010784510;gex.accueil@ch-paysdegex.fr;F;2020-10-04
010784551;mairie@stdc.fr;F;2020-10-04
010784569;foyerdesmousserons@val-revermont.fr;F;2020-10-04
010784577;mairie@vonnas.com;F;2020-10-04
010784585;ccas@ville-gex.fr;F;2020-10-04
010784593;contact@josephineguillon.fr;F;2020-10-04
010784601;secretariat@assolaroseraie.fr;F;2020-10-04
010784619;ccas@hauteville-lompnes.com;F;2020-10-04
010784635;residence-des-frachets@orange.fr;F;2020-10-04
010784692;contact@josephineguillon.fr;F;2020-10-04
010785673;mdrbonreposbelley@wanadoo.fr;F;2020-10-04
010785681;contact@josephineguillon.fr;F;2020-10-04
010786002;lechapuis.secretariat@gmail.com;F;2020-10-04
010786010;direction@ch-belley.fr;F;2020-10-04
010786085;hopital@chpv.fr;F;2020-10-09
010786119;mr.chalamont@orange.fr;F;2020-10-04
010786135;contact@mrbouchacourt.fr;F;2020-10-04
010786176;direction@st-joseph-jasseron.fr;F;2020-10-04
010788008;info@ch-avs.fr;F;2020-10-04
010788032;direction@ehpad-montrevel.fr;F;2020-10-09
010788040;accueil-ameyzieu@groupecolisee.com;F;2020-10-04
010788230;contact@chateau-de-vernange.com;F;2020-10-04
010788438;ehpad.pleinsoleil@ehpad-lhuis.fr;F;2020-10-04
010788644;direction@chateaudevalence.fr;F;2020-10-04
010788669;mapastvulbas@clairesfontaines.fr;F;2020-10-04
010789030;residence.utrillo@wanadoo.fr;F;2020-10-04
010789220;ehpad.ceyzeriat@wanadoo.fr;F;2020-10-04
010789535;mairie@izernore.fr;F;2020-10-04
010789915;bourg.direction@sofinam.fr;F;2020-10-04
010790384;direction@ajmarpa.fr;F;2020-10-04
020000030;residencebrisset@ch-hirson.fr;F;2020-10-04
020002028;ehpadlefevre@mr-flavy.fr;F;2020-10-04
020002101;contact@ehpad-lacapelle.fr;F;2020-10-09
020002135;mr.coucy@wanadoo.fr;F;2020-10-04
020002168;contact@residencedelourcq.fr;F;2020-10-04
020002176;direction@ehpad-laon.fr;F;2020-10-04
020002184;ehpad-liesse@orange.fr;F;2020-10-04
020002192;direction.mdrmarle@wanadoo.fr;F;2020-10-04
020002200;administration@mroulchy.fr;F;2020-10-04
020003943;accueil.pommery@fondationdiaconesses.org;F;2020-10-04
020003976;ehpad.corbeny@coallia.org;F;2020-10-04
020004677;secretariat.eclaircie@ch-soissons.fr;F;2020-10-04
020004693;direction.bellevue@ch-chateau-thierry.fr;F;2020-10-14
020004719;ch-guise@wanadoo.fr;F;2020-10-04
020004727;direction@ch-chauny.fr;F;2020-10-04
020004750;direction@ch-vervins.com;F;2020-10-04
020004776;direction@ch-chauny.fr;F;2020-10-04
020004974;hebergement@ch-lenouvion.fr;F;2020-10-04
020009007;ch-guise@wanadoo.fr;F;2020-10-04
020009114;accueil@residence-bellevue.net;F;2020-10-04
020009197;direction@residence-saint-leger.fr;F;2020-10-04
020009411;residence.amitie@amsam.net;F;2020-10-04
020012639;ehpad.stquentin@tempsdevie.fr;F;2020-10-04
020012761;contact@carct.fr;F;2020-10-04
030001234;direction@chsi-ainay.fr;F;2020-10-04
030004428;secretariat-jardindessources@sud-generations.fr;F;2020-10-04
030005508;marpa@noyantdallier.fr;F;2020-10-04
030007116;marpast-yorre@orange.fr;F;2020-10-04
030780134;ehpad@mrcusset.fr;F;2020-10-04
030780142;mr.gannat@wanadoo.fr;F;2020-10-04
030780597;accueil@ehpad-chantelle.fr;F;2020-10-04
030780605;reception@ehpad-gayette.fr;F;2020-10-04
030780720;contact@epms-valdesioule.fr;F;2020-10-04
030780761;accueil@ehpad-lapalisse.fr;F;2020-10-04
030780928;ehpad-pierre.masseboeuf@orange.fr;F;2020-10-04
030780936;contact@ehpad-cerilly.fr;F;2020-10-04
030780944;contact.ehpad@laumance.fr;F;2020-10-04
030780951;ehpad@ehpadld.fr;F;2020-10-09
030780969;direction@ehpad-echassieres.fr;F;2020-10-04
030780977;ehpad-herisson@wanadoo.fr;F;2020-10-09
030780985;ehpad.lurcy-levis@orange.fr;F;2020-10-04
030780993;emeraude.direction@orange.fr;F;2020-10-04
030781405;ehpad.saint-joseph@ccass-sbe.org;F;2020-10-04
030782569;contact@ehpadlescedres03.fr;F;2020-10-04
030782593;ehpad.jeannecoulon@orange.fr;F;2020-10-04
030782619;villars.accueil@wanadoo.fr;F;2020-10-04
030782643;accueil.ehpad@ermitage-moulins.fr;F;2020-10-04
030782767;residence.saintetherese@moulinshabitat.fr;F;2020-10-04
030782775;foyerlogement.bellenaves@orange.fr;F;2020-10-04
030783013;residence.parc@wanadoo.fr;F;2020-10-04
030783179;residencelescoupances@orange.fr;F;2020-10-04
030783583;secretariatusld@ch-vichy.fr;F;2020-10-04
030783880;direction@ch-moulins-yzeure.fr;F;2020-10-04
030784169;direction@hopcobour.net;F;2020-10-04
030785190;direction@ch-moulins-yzeure.fr;F;2020-10-04
030785216;hopital@ch-neris.fr;F;2020-10-04
030785539;administration@lvg03.fr;F;2020-10-04
030785620;marpa.chevagnes@orange.fr;F;2020-10-04
030785653;marpa-marcillat@wanadoo.fr;F;2020-10-04
030785737;accueil.lesvignes@fr.oleane.com;F;2020-10-04
030785778;residence@ehpadlhermitage.fr;F;2020-10-04
040002289;direction@centredescarmes.com;F;2020-10-04
040004152;marpa.lamotteducaire@orange.fr;F;2020-10-04
040004301;contact@lesjardinsducigaloun.fr;F;2020-10-04
040780702;mrthoard@orange.fr;F;2020-10-04
040780892;ehpadduluberon@orange.fr;F;2020-10-04
040781023;administration@lepibleu.fr;F;2020-10-04
040785065;contact@residence-paul-cezanne.com;F;2020-10-04
040785388;direction.beatrix@ages-asso.fr;F;2020-10-04
040785412;secretariat@ehpad-paulhonnorat.fr;F;2020-10-04
040785529;direction@ch-banon.fr;F;2020-10-04
040785677;direction@ch-entrevaux.fr;F;2020-10-04
040785727;direction@ch-forcalquier.fr;F;2020-10-04
040785776;direction-jausiers@hopitaux-ubayens.fr;F;2020-10-04
040785826;etablissementlesmees@lou-cigalou04.fr;F;2020-10-04
040785925;accueil@ch-riez.fr;F;2020-10-04
040785974;accueil@hopital-seyne.fr;F;2020-10-04
040786022;accueilmr@valensoleille.fr;F;2020-10-04
040787129;accueil-barcelonnette@hopitaux-ubayens.fr;F;2020-10-04
040789075;secretariat@louseren-ehpad.fr;F;2020-10-04
040789240;ehpad@saintvincent04.fr;F;2020-10-04
050001494;direction-lameije@sud-generations.fr;F;2020-10-04
050001585;foyersoleil-laragne@wanadoo.fr;F;2020-10-04
050001833;accueil.chanterelles@ch-embrun.fr;F;2020-10-04
050001858;direction@ch-laragne.fr;F;2020-10-04
050002047;accueil.guillestre@guilecrins.fr;F;2020-10-04
050002054;direction.pavie@mrsavines-lelac.fr;F;2020-10-04
050002062;secretariat@ledrac.fr;F;2020-10-04
050002609;direction@fondationseltzer.fr;F;2020-10-04
050003029;info@ehpadjmartin.fr;F;2020-10-04
050003318;ehpadbonnedonne@coallia.org;F;2020-10-04
050003599;direction@ledrac.fr;F;2020-10-04
050005438;accueil.louvilage@ch-embrun.fr;F;2020-10-04
050005511;contact@le-val-de-serres.com;F;2020-10-04
050005701;direction@ch-laragne.fr;F;2020-10-04
050005768;accueil.ehpad.st-mens@ville-gap.fr;F;2020-10-04
050005818;direction@ch-laragne.fr;F;2020-10-04
050005859;gerontologie@chicas-gap.fr;F;2020-10-04
050006071;gerontologie@chicas-gap.fr;F;2020-10-04
050006626;direction.ouleta@free.fr;F;2020-10-04
050007079;direction@ladurance.fr;F;2020-10-04
050008507;ssiad.argentiere@vvcs.fr;F;2020-10-04
060000551;direction@cls-vallauris.fr;F;2020-10-04
060003266;secretariat.cantazur@cantavencoise.com;F;2020-10-04
060003316;direction@ancilla.fr;F;2020-10-04
060003878;contact@masdesmimosas.com;F;2020-10-04
060004090;reception.parcdemougins@korian.fr;F;2020-10-04
060004918;direction-tende@chu-nice.fr;F;2020-10-04
060005139;association@fa06.fr;F;2020-10-04
060007168;secretariat@tourelles-vallauris.com;F;2020-10-04
060012168;direction@residencedespaillons.fr;F;2020-10-04
060012879;accueil.sorgentino@korian.fr;F;2020-10-04
060012978;accueil.mougins@groupecolisee.com;F;2020-10-04
060013059;direction@closdecimiez.com;F;2020-10-04
060016458;contact@accueil-alzheimer.fr;F;2020-10-04
060018918;secretariat-lyna@medifar.org;F;2020-10-04
060020294;direction.villafoch@orpea.net;F;2020-10-04
060020369;ehpad@lauriers-roses-levens.fr;F;2020-10-04
060020518;direction@ehpad-eauvive.fr;F;2020-10-04
060020559;direction-lesrestanques@sud-generations.fr;F;2020-10-04
060020807;ehpad.saintjean@ordredemaltefrance.org;F;2020-10-04
060021128;retraite@ccas-beausoleil.fr;F;2020-10-04
060021185;accueil-ehpad@mairie-mandelieu.fr;F;2020-10-04
060023702;secretariat.direction@ch-antibes.fr;F;2020-10-04
060023843;secretariat.direction@ch-antibes.fr;F;2020-10-04
060024106;direction.collettes@lna-sante.com;F;2020-10-04
060024262;direction.falicon@lna-sante.com;F;2020-10-04
060780871;mr.barsurloup@wanadoo.fr;F;2020-10-09
060780939;ehpadlabrigue@hopital-breil-roya.com;F;2020-10-04
060781259;residence-mirasol@medifar.org;F;2020-10-04
060781275;contact@maisonrusse.fr;F;2020-10-04
060781317;accueil@crr.asso.fr;F;2020-10-04
060781408;residence.olivier@orange.fr;F;2020-10-04
060781416;accueil@ehpadfamlantosque.fr;F;2020-10-04
060781499;direction@residencelaroseraie.com;F;2020-10-04
060782125;direction@fondation-pauliani.org;F;2020-10-04
060782141;contact@bougainvillees.org;F;2020-10-04
060782166;ehpadsaorge@hopital-breil-roya.com;F;2020-10-04
060782174;ehpadgastaldy@orange.fr;F;2020-10-04
060782190;reception.fontdivina@korian.fr;F;2020-10-04
060782406;direction@lucioles-nice.com;F;2020-10-04
060782505;contact@heuresclaires.com;F;2020-10-04
060782919;mdrgenets@wanadoo.fr;F;2020-10-04
060784196;direction.gabres@aoapar.fr;F;2020-10-04
060784212;secretariat@orsac-monfleuri.fr;F;2020-10-04
060786456;accueil@lafontouna.fr;F;2020-10-04
060790185;direction@ch-cannes.fr;F;2020-10-04
060790284;direction@ch-puget-theniers.fr;F;2020-10-04
060790334;accueil@hopital-breil-roya.com;F;2020-10-04
060790433;direction@hopitalsospel.fr;F;2020-10-04
060790565;secretariat@tourelles-vallauris.com;F;2020-10-04
060790698;direction@stemarguerite.com;F;2020-10-04
060790714;direction@ch-cannes.fr;F;2020-10-04
060790789;direction-tende@chu-nice.fr;F;2020-10-04
060791381;direction@polesante-vallauris.fr;F;2020-10-04
060791639;administration@lucioles-nice.com;F;2020-10-04
060792082;direction@ehpad-escapade.fr;F;2020-10-04
060792231;info-residencehelena@wanadoo.fr;F;2020-10-04
060792322;contact@chateaudelabrague.com;F;2020-10-04
060792694;contact@ehpad-feuillantines.fr;F;2020-10-04
060792728;hopital.saintmaur@gmail.com;F;2020-10-04
060792868;residence.pasteur@ccas-antibes.fr;F;2020-10-04
060798972;direction@residencelesfloralies.fr;F;2020-10-04
060799210;direction@residencelespensees.com;F;2020-10-04
060799434;direction.grasse71@orpea.net;F;2020-10-04
060799459;fleurie.residence@wanadoo.fr;F;2020-10-04
060799467;contact.aquarelles@gmail.com;F;2020-10-04
060799897;secretariat@azureva.fr;F;2020-10-04
060799970;ccas@mairie-mandelieu.fr;F;2020-10-04
060800208;mdralbarea@wanadoo.fr;F;2020-10-04
060800422;arcenciel.administration@orange.fr;F;2020-10-04
060800588;residence-messidor@medifar.org;F;2020-10-04
060800893;accueil-begum-aga-khan@groupe-sos.org;F;2020-10-04
060801354;contact@noisetiers.com;F;2020-10-04
070001250;ehpad.chalendas@bethanie.fr;F;2020-10-04
070002639;accueil@leschataigniers07.com;F;2020-10-04
070004890;mdrstemarie@orange.fr;F;2020-10-04
070005012;foyerjeanhelene@mfrs.fr;F;2020-10-04
070005657;direction@ch-privas.fr;F;2020-10-04
070006358;mapa.boulieu@annonay-agglo.fr;F;2020-10-04
070780333;direction@ch-ardeche-meridionale.fr;F;2020-10-04
070780606;secretariat@ehpad-burzet.fr;F;2020-10-04
070780614;ehpad.mimosas@wanadoo.fr;F;2020-10-04
070780622;contact@mdrchomerac.fr;F;2020-10-04
070780630;administration@ehpad-valgorge.fr;F;2020-10-04
070783477;contact@ehpadsatillieu.fr;F;2020-10-09
070783493;contact@residence-monfoyer.com;F;2020-10-04
070783527;mdr.montalivet@wanadoo.fr;F;2020-10-04
070783543;residencelac@hotmail.fr;F;2020-10-04
070783576;contact@champ-long.fr;F;2020-10-04
070783584;info@le-sandron.fr;F;2020-10-04
070783600;ehpad.coulet@orange.fr;F;2020-10-04
070783626;ehpad@les-myrtilles.com;F;2020-10-09
070783634;accueil@lesterrassesdelibie.fr;F;2020-10-04
070783683;residence.teil@mutualite-ardeche.fr;F;2020-10-04
070783691;accueil.vans@mutualite-ardeche.fr;F;2020-10-04
070783709;residence.thueyts@mutualite-ardeche.fr;F;2020-10-04
070783774;ehpad.lepins@orange.fr;F;2020-10-04
070783816;accueil@hopitalstfelicien.fr;F;2020-10-04
070783832;residence.lamitie@orange-business.fr;F;2020-10-04
070784046;direction-tournon@lesopalines.fr;F;2020-10-04
070784277;charnivet.secretariat@orange.fr;F;2020-10-04
070784400;residencelegrandpre@orange.fr;F;2020-10-09
070784426;ehpad.laclairiere@annonay-agglo.fr;F;2020-10-04
070784467;direction@ch-tournon.fr;F;2020-10-04
070784483;direction@ch-annonay.fr;F;2020-10-04
070784517;direction@ch-privas.fr;F;2020-10-04
070784525;direction@hi-bsav.fr;F;2020-10-04
070784533;accueil@ch-joyeuse.fr;F;2020-10-04
070784541;direction@ch-privas.fr;F;2020-10-04
070784558;direction@hopital-lamastre.fr;F;2020-10-04
070784566;direction@ch-rl.fr;F;2020-10-04
070784582;accueil-chambonas@ch-ca.fr;F;2020-10-04
070784616;contact@ch-vallon.fr;F;2020-10-04
070784624;accueil@beauregard-residence.fr;F;2020-10-04
070784632;secretariatdedirection@ch-vdb.fr;F;2020-10-04
070784640;direction@hi-bsav.fr;F;2020-10-04
070784939;secretariatdedirection@ch-vdb.fr;F;2020-10-04
070785365;residence.aubenas@mutualite-ardeche.fr;F;2020-10-04
070786033;mdr-saintjoseph@orange.fr;F;2020-10-04
070786074;residence.jaujac@mutualite-ardeche.fr;F;2020-10-09
070786082;residence.alba@mutualite-ardeche.fr;F;2020-10-04
070786462;ccas.resid-val-ardeche@wanadoo.fr;F;2020-10-04
070786553;secretariatlavandes@mfrs.fr;F;2020-10-04
070786561;residence.ollieres@mutualite-ardeche.fr;F;2020-10-04
070786579;marpa7@wanadoo.fr;F;2020-10-04
080002025;accueil.lesvignes@ehpad-ardennes.fr;F;2020-10-04
080002058;mdrrocroi@wanadoo.fr;F;2020-10-04
080002918;marpa.gabreau@orange.fr;F;2020-10-04
080003221;residence.lawarenne@resideis.fr;F;2020-10-04
080003395;direction@ch-ghsa.fr;F;2020-10-04
080003684;direction@ch-sedan.fr;F;2020-10-04
080003692;direction@ch-sedan.fr;F;2020-10-04
080003718;secretariatbraconnier@orange.fr;F;2020-10-04
080005374;ccasmouzon@orange.fr;F;2020-10-04
080005705;mr.carignan@croix-rouge.fr;F;2020-10-04
080005903;residence.lessorbiers@resideis.fr;F;2020-10-04
080006018;ehpadpredusart@utrca.fr;F;2020-10-04
080006067;direction@ch-ghsa.fr;F;2020-10-04
080006174;direction.fumay@ch-nord-ardennes.fr;F;2020-10-09
080006182;direction@ch-nouzonville.fr;F;2020-10-04
080007024;contact@adapah08.asso.fr;F;2020-10-04
080007370;residencevaldemeuse@orange.fr;F;2020-10-04
080008196;contact@adapah08.asso.fr;F;2020-10-04
080008204;ehpadmarcadet@utrca.fr;F;2020-10-04
080009178;direction@ch-sedan.fr;F;2020-10-04
080009970;ehpad.signy08@gmail.com;F;2020-10-04
080009988;contact@residence-liart.com;F;2020-10-04
080010564;direction@th-ghsa.fr;F;2020-10-04
090000399;direction@ch-lavelanet.fr;F;2020-10-04
090000605;accueil.ostal@goyheneche.asso.fr;F;2020-10-04
090000613;direction@goyheneche.asso.fr;F;2020-10-04
090000662;residence.autonomie@agglo-pfv.fr;F;2020-10-04
090001439;sauzeil.ehpad@cc-hauteariege.fr;F;2020-10-04
090002916;info.villalesroses@orange.fr;F;2020-10-04
090003005;ehpaddessources@orange.fr;F;2020-10-04
090780131;mr.mirepoix@wanadoo.fr;F;2020-10-04
090780149;ehpad.erce@sante-couserans.fr;F;2020-10-04
090780362;administration.vertcoteau@wanadoo.fr;F;2020-10-04
090780461;contact@residencelacroixdusud.com;F;2020-10-04
090781477;direction@chi-val-ariege.fr;F;2020-10-04
090781535;direction@ch-ariege-couserans.fr;F;2020-10-14
090781543;direction@ch-lavelanet.fr;F;2020-10-04
090781642;ehpad.lechateau@orange.fr;F;2020-10-04
090781998;ehpad.massat@wanadoo.fr;F;2020-10-04
090782293;direction@lausada.com;F;2020-10-04
090782343;chtarascon@hopital-tarascon09.fr;F;2020-10-04
090782624;residence.paulane@orange.fr;F;2020-10-04
090782707;direction@ch-axlesthermes.fr;F;2020-10-04
090782970;hectordossun.secretariat@ch-ariege-couserans.fr;F;2020-10-04
090783283;accueil.castillon@ariege-assistance.asso.fr;F;2020-10-04
090783341;residence.estelas@wanadoo.fr;F;2020-10-04
090783846;volpresidence@orange.fr;F;2020-10-04
090783945;direction@ch-ariege-couserans.fr;F;2020-10-04
100000231;foyerlogement.barsuraube@orange.fr;F;2020-10-04
100001239;direction@residencedupays.com;F;2020-10-04
100002138;mdrarcis@gmail.com;F;2020-10-04
100002146;contact@ehpad-brienne.fr;F;2020-10-04
100002153;ehpad.chaource@orange.fr;F;2020-10-04
100002161;ehpadervy@orange.fr;F;2020-10-04
100002179;ehpad@ehpadmery.com;F;2020-10-04
100002187;accueil@parcfleuri.fr;F;2020-10-04
100002195;ehpad.riceys@wanadoo.fr;F;2020-10-04
100002203;mdr-trainel@wanadoo.fr;F;2020-10-04
100002211;ehpad.villenauxelagrande@orange.fr;F;2020-10-04
100003425;residencedelamoline@wanadoo.fr;F;2020-10-04
100003581;direction.mesanges@orange.fr;F;2020-10-04
100004159;accueil.vendeuvresurbarse@groupecolisee.com;F;2020-10-04
100004357;contact@residence-la-sapiniere.com;F;2020-10-04
100005362;direction@ch-troyes.fr;F;2020-10-04
100005909;contact@ch-bsa.fr;F;2020-10-04
100005925;accueil@hopital10110.fr;F;2020-10-04
100006444;direction@ch-troyes.fr;F;2020-10-04
100006568;contact@villadutertre.fr;F;2020-10-04
100006873;contact@residence-louis-pasteur.com;F;2020-10-04
100006907;accueil.saintemarthe@cias10-marcilly-fontaine.fr;F;2020-10-04
100006915;accueil.lestilleuls@cias10-marcilly-fontaine.fr;F;2020-10-04
100006972;residencedelisle@orpea.net;F;2020-10-04
100007137;estissac.marpa@troyes-cm.fr;F;2020-10-04
100009018;direction@ch-troyes.fr;F;2020-10-04
110002607;accueil.antinea@maisonsdefamille.com;F;2020-10-04
110002706;ehpad.rieux@wanadoo.fr;F;2020-10-04
110002813;residence.laetitia@gmail.com;F;2020-10-04
110003498;secretariat-figueres@groupe-sos.org;F;2020-10-04
110004488;reception.lespinsverts@korian.fr;F;2020-10-04
110004967;direction@romarinsccas.fr;F;2020-10-04
110005006;direction@ch-narbonne.fr;F;2020-10-04
110005287;secretariat.direction@ch-portlanouvelle.fr;F;2020-10-04
110005386;reception.closdelorchidee@korian.fr;F;2020-10-04
110005451;ehpad.villa.domitia@orange.fr;F;2020-10-04
110005576;direction@asm11.fr;F;2020-10-04
110005584;direction@asm11.fr;F;2020-10-04
110005782;accueil.chenier@ch-limoux.fr;F;2020-10-04
110005980;direction@asm11.fr;F;2020-10-04
110780103;admission@lacaponada.fr;F;2020-10-04
110780715;residence.mr@wanadoo.fr;F;2020-10-04
110780723;bon.accueil@ehpad-chalabre.fr;F;2020-10-04
110780731;mresperaza@wanadoo.fr;F;2020-10-04
110781283;direction@ch-narbonne.fr;F;2020-10-04
110782844;bethanie-accueil@wanadoo.fr;F;2020-10-04
110782851;accueil.stvincent11@ccass-sbe.org;F;2020-10-04
110782869;direction@asm11.fr;F;2020-10-04
110782885;contact@residence-marronnier.com;F;2020-10-04
110782927;accueil.mimosas@lna-sante.com;F;2020-10-04
110783289;direction@asm11.fr;F;2020-10-04
110785789;direction@asm11.fr;F;2020-10-04
110786530;ehpadcastelou@orange.fr;F;2020-10-04
110787314;admissions.ehpad@ch-castelnaudary.fr;F;2020-10-04
110787322;admissions.ehpad@ch-castelnaudary.fr;F;2020-10-04
110787348;contact@ch-limoux.fr;F;2020-10-04
110787363;direction@ch-lezignan.fr;F;2020-10-04
110787538;secretariat.lasfountetos@orange.fr;F;2020-10-04
110787579;accueil.lesestamounets@orange.fr;F;2020-10-04
110789450;laroque.residence@sud-minervois.com;F;2020-10-04
110791332;ehpad.roquefeuil@ch-limoux.fr;F;2020-10-04
110791597;secretariat.lechateau@capsante.fr;F;2020-10-04
120005509;ehpadlescheveuxdange@orange.fr;F;2020-10-04
120007083;foyerbellevue@wanadoo.fr;F;2020-10-04
120007356;accueil@saintdo.fr;F;2020-10-04
120780432;accueil@gailogis.fr;F;2020-10-04
120780457;secretariat@hl-vallon.fr;F;2020-10-04
120780465;direction.mdr@wanadoo.fr;F;2020-10-04
120780499;ehpad.laroussilhe@wanadoo.fr;F;2020-10-04
120780515;ehpad.ste-therese@anras.fr;F;2020-10-04
120781075;contact@residence-2vallees.com;F;2020-10-04
120782263;secretariat.direction@ch-villefranche-rouergue.fr;F;2020-10-04
120782313;direction@ch-decazeville.fr;F;2020-10-04
120782347;direction@ehpadstcyrice.fr;F;2020-10-04
120782354;residencepontdesalars@wanadoo.fr;F;2020-10-04
120782362;contact@ehpadbonaccueil.fr;F;2020-10-04
120782420;info@ehpad-saintemarie.com;F;2020-10-04
120782461;residencebeausoleil@wanadoo.fr;F;2020-10-04
120782479;mdr.marie-vernieres@wanadoo.fr;F;2020-10-04
120782487;ehpad.lacroixbleue@anras.fr;F;2020-10-04
120782529;residence.mdr@wanadoo.fr;F;2020-10-04
120782545;accueil@gailogis.fr;F;2020-10-04
120782560;ehpad.andrecalvignac@wanadoo.fr;F;2020-10-04
120782586;ehpad-adrienne-lugans@orange.fr;F;2020-10-04
120782594;foyer.soleil.millau@wanadoo.fr;F;2020-10-04
120783287;ehpad.saintemarthe@orange.fr;F;2020-10-04
120783303;secretariat.direction@ch-villefranche-rouergue.fr;F;2020-10-14
120783543;logementsfoyer@gmail.com;F;2020-10-04
120784087;ccas-accueil@baraqueville.fr;F;2020-10-04
120784095;direction@hl-saintgeniezdolt.fr;F;2020-10-04
120784178;direction@ch-saintaffrique.fr;F;2020-10-04
120784566;ehpad.lunac@orange.fr;F;2020-10-04
120785191;secretariat.direction@ch-villefranche-rouergue.fr;F;2020-10-04
120785217;direction@ch-saintaffrique.fr;F;2020-10-04
120785233;secretariat@ch-espalion.fr;F;2020-10-04
120785258;secretariat@hl-vallon.fr;F;2020-10-04
120785522;ehpaddirection@charmettesmillau.com;F;2020-10-04
120785530;ehpadsteclaire@orange.fr;F;2020-10-04
120786074;direction@hl-saintgeniezdolt.fr;F;2020-10-04
120786546;direction@repos-sante.fr;F;2020-10-04
120786843;ehpadfirmi@wanadoo.fr;F;2020-10-04
120786868;ehpadgloriande@wanadoo.fr;F;2020-10-04
120786900;contact@residenceladourbie.fr;F;2020-10-04
120786959;direction@ch-rodez.fr;F;2020-10-04
120786967;direction@ch-rodez.fr;F;2020-10-04
120787056;marpalescolombes@orange.fr;F;2020-10-04
120787262;direction@ch-decazeville.fr;F;2020-10-04
120787395;residencelugan@ehpadlamontanie.fr;F;2020-10-04
120787676;direction.valfleuri@gcsms-palaios.fr;F;2020-10-04
120788005;contact@steannelaprimaube.fr;F;2020-10-04
120788179;accueil@saintdo.fr;F;2020-10-04
130008733;ehpad.lecigalou@ch-laciotat.fr;F;2020-10-04
130008949;secretariat-domainedelolivier@sud-generations.fr;F;2020-10-04
130009608;reception.masdesaines@korian.fr;F;2020-10-04
130009988;accueil@residencemarseillane.fr;F;2020-10-04
130010218;reception.lesparents@korian.fr;F;2020-10-04
130011018;contact@lesamandiers.fr;F;2020-10-04
130014178;accueil@residence-mazargues.fr;F;2020-10-04
130017908;accueil.ehpad@atlastrets.com;F;2020-10-04
130023369;contact@horizonbleu.fr;F;2020-10-04
130023559;administratif@residencenotredame.org;F;2020-10-04
130026198;secretariat@rivoli-ehpad.com;F;2020-10-04
130027089;direction-tournesols@sud-generations.fr;F;2020-10-04
130027378;accueil.stvictoret@groupecolisee.com;F;2020-10-04
130028608;direction.lemaillon@orange.fr;F;2020-10-04
130030208;accueil@peupliers-ehpad.com;F;2020-10-04
130032659;direction-cascade@sud-generations.fr;F;2020-10-13
130032709;residencefontclair@orange.fr;F;2020-10-04
130033129;direction@ch-allauch.fr;F;2020-10-04
130033178;direction@ch-aubagne.fr;F;2020-10-04
130033269;secretariat-direction@ch-aix.fr;F;2020-10-04
130033459;accueil-jardinsdemirabeau@sud-generations.fr;F;2020-10-13
130037112;mapad@ccas-aixenprovence.org;F;2020-10-04
130038078;accueil.lagora@korian.fr;F;2020-10-04
130038409;secretariat-lesiris@sud-generations.fr;F;2020-10-04
130038839;contact-lesmelodies@mutuellesdusoleil.fr;F;2020-10-04
130042146;accueil@lestempsbleus.com;F;2020-10-04
130042484;accueil.olympe@groupecolisee.com;F;2020-10-04
130045396;accueil.marseillejoliette@groupecolisee.com;F;2020-10-04
130045537;direction@residencepasteur.fr;F;2020-10-04
130046329;accueil-lesterrasses@sud-generations.fr;F;2020-10-04
130046923;direction-jardinsdemirabeau@sud-generations.fr;F;2020-10-04
130047749;direction-lechatelier@sud-generations.fr;F;2020-10-04
130047905;direction-villamarie@sud-generations.fr;F;2020-10-04
130048283;contact@labastidedescalanques.fr;F;2020-10-04
130780141;info@les-camoins.com;F;2020-10-04
130780307;accueil@stjd.fr;F;2020-10-04
130780646;direction@saintgeorgesehpad.com;F;2020-10-04
130780778;mdr.lafruitiere@orange.fr;F;2020-10-04
130780794;bocage-accueil@domusvi.com;F;2020-10-04
130780810;accueil.ste.emilie@fedes.fr;F;2020-10-13
130780828;direction@residencemaguen.com;F;2020-10-04
130781230;directionfoyer@catho-aixarles.fr;F;2020-10-04
130781487;direction@castelroseraie.fr;F;2020-10-04
130781636;accueilbarbentane@mrpi-chateaurenard-barbentane.fr;F;2020-10-04
130781693;accueilcabannes@mrpi-noves-cabannes.fr;F;2020-10-04
130781743;direction@ehpad-cassis.fr;F;2020-10-04
130781800;info@maisons-paisibles.com;F;2020-10-04
130781958;contact@mrplafare.org;F;2020-10-04
130782030;flore-darc.accueil@orange.fr;F;2020-10-04
130782113;direction@ehpad-lambesc.fr;F;2020-10-04
130782139;ehpadmarignane@orange.fr;F;2020-10-04
130782329;mdr.elysee@yahoo.fr;F;2020-10-04
130782519;direction@ehpad-stcannat.fr;F;2020-10-04
130782527;accueil@ehpad-st-chamas.fr;F;2020-10-04
130782808;direction@leopoldcartoux.fr;F;2020-10-04
130783749;ehpad.notre-maison@croix-rouge.fr;F;2020-10-04
130784002;administration@bon-pasteur.fr;F;2020-10-04
130784242;accueil@salette-montval.com;F;2020-10-04
130784473;direction.poetes@lenobleage.fr;F;2020-10-04
130784754;contact@bastide-saint-jean.com;F;2020-10-04
130784762;contact@la-constance.fr;F;2020-10-04
130786791;mdr.jeanne.arc@wanadoo.fr;F;2020-10-04
130786858;accueil@la-forezienne.com;F;2020-10-04
130787237;info@maisons-paisibles.com;F;2020-10-04
130787260;residenceduparc@agafpa.com;F;2020-10-04
130790058;marignane.ccas@orange.fr;F;2020-10-04
130790108;foyerdaudet@fontvieille.fr;F;2020-10-04
130790322;regain.direction@armapad.fr;F;2020-10-04
130793334;accueil.residence@atlastrets.com;F;2020-10-04
130797954;administratif@ssd-lasouvenance.com;F;2020-10-04
130798333;direction@ch-allauch.fr;F;2020-10-04
130798358;secretariat-direction@ch-aix.fr;F;2020-10-04
130798457;direction@ch-aubagne.fr;F;2020-10-04
130798754;accueil.lambesc@stv-s.org;F;2020-10-04
130798762;residencechevillon@orange.fr;F;2020-10-04
130798804;reception.perier@korian.fr;F;2020-10-04
130800048;reception.valdessources@korian.fr;F;2020-10-04
130800816;standard.les.anemones@gmail.com;F;2020-10-04
130802044;direction.stluc@orpea.net;F;2020-10-04
130802119;direction@ch-allauch.fr;F;2020-10-04
130802374;accueil@retraite-sainte-victoire.com;F;2020-10-04
130802655;reception.laloubiere@korian.fr;F;2020-10-04
130806466;secretariat@ehpad-mgasquet.fr;F;2020-10-04
130807282;ehpad.lerayondesoleil@ch-laciotat.fr;F;2020-10-04
130808017;direction.verteprairie@lna-sante.com;F;2020-10-04
130808686;mdr.stebernadette@gmail.com;F;2020-10-04
130809114;direction-marseille@orange.fr;F;2020-10-04
130809866;contact@residencemarguerite.com;F;2020-10-04
130809940;contact@terres-rouges.fr;F;2020-10-04
130810401;direction-chateau.de.fontainieu@orange.fr;F;2020-10-04
130811102;accueil@lamaisondegardanne.fr;F;2020-10-04
130811722;contact-residencelespins@orange.fr;F;2020-10-04
140001280;accueil@ehpadlaurencedelapierre.fr;F;2020-10-04
140002098;ehpadstjacquesstchristophe@wanadoo.fr;F;2020-10-04
140002114;direction@ch-falaise.fr;F;2020-10-04
140002122;contact@ehpad-troarn.fr;F;2020-10-04
140004086;direction@ch-cotefleurie.fr;F;2020-10-04
140004433;direction@ch-cotefleurie.fr;F;2020-10-04
140004441;direction@ch-falaise.fr;F;2020-10-04
140004573;rh@ehpadsj.fr;F;2020-10-04
140004755;ehpa.cheminvert@caen.fr;F;2020-10-04
140004763;ehpa.gueriniere@caen.fr;F;2020-10-04
140004771;ehpa.gracededieu@caen.fr;F;2020-10-04
140004789;ehpa.pierreheuze@caen.fr;F;2020-10-04
140004813;ehpad.mathilde@caen.fr;F;2020-10-04
140007352;ehpadsaintjoseph@orange.fr;F;2020-10-04
140007386;residenceduval@herouville.net;F;2020-10-04
140007394;ccas@mondeville.fr;F;2020-10-04
140007956;ccas@colombelles.fr;F;2020-10-04
140007972;contact@ehpad-argences.fr;F;2020-10-04
140008012;contact@stjosephlivarot.fr;F;2020-10-04
140008095;ccas@houlgate.fr;F;2020-10-04
140008236;ladelivrande.mdr@wanadoo.fr;F;2020-10-04
140011610;direction@ehpad-saintemarie.fr;F;2020-10-04
140011628;direction@residencelesopalines.com;F;2020-10-04
140011727;ccas@mairie-bayeux.fr;F;2020-10-04
140011750;residencelesdouets@wanadoo.fr;F;2020-10-04
140011792;mairie@ville-courseulles.fr;F;2020-10-04
140011818;ccas@dives-sur-mer.fr;F;2020-10-04
140011826;mairie.dozule@wanadoo.fr;F;2020-10-04
140011891;ccas@ville-lisieux.fr;F;2020-10-04
140011909;ccas@ville-lisieux.fr;F;2020-10-04
140011925;mairie@portenbessin-huppain.fr;F;2020-10-04
140011982;mairie.vassy@wanadoo.fr;F;2020-10-04
140013798;direction@ch-lisieux.fr;F;2020-10-04
140013806;direction@ch-lisieux.fr;F;2020-10-04
140013830;direction@ch-falaise.fr;F;2020-10-04
140013848;direction@ch-falaise.fr;F;2020-10-04
140013905;administration@epms-orbec.fr;F;2020-10-04
140013947;direction@ch-cotefleurie.fr;F;2020-10-04
140015108;accueil@ehpad-beausoleil.fr;F;2020-10-04
140015199;ehpa.haievigne@caen.fr;F;2020-10-04
140015488;direction@ch-ple.fr;F;2020-10-04
140015827;residence.chanterelles@resalia-ms.com;F;2020-10-04
140015835;mdr.les-cedres@wanadoo.fr;F;2020-10-04
140015991;accueil@symphonia-ehpad.fr;F;2020-10-04
140016015;contact@residence-rene-castel.com;F;2020-10-04
140016049;reception.thalatta@korian.fr;F;2020-10-04
140016098;residence.orchidees@resalia-ms.com;F;2020-10-04
140016395;contact@hom-age.fr;F;2020-10-04
140016429;residenceduparc@hom-age.fr;F;2020-10-04
140016494;contact@gaston-de-renty.com;F;2020-10-04
140016601;ehpad.lebelvedere@gmail.com;F;2020-10-04
140016734;ccas@ville-lisieux.fr;F;2020-10-04
140016825;accueil.demi.lune@les-matines.fr;F;2020-10-04
140016890;mdr.lestilleuls.courseulles@wanadoo.fr;F;2020-10-04
140016908;residenceduval@herouville.net;F;2020-10-04
140017096;mezidon.ehpad.direction@anais.asso.fr;F;2020-10-04
140017211;contact@residence-gustave-courbet.com;F;2020-10-04
140017476;direction.touques@lna-sante.com;F;2020-10-04
140019530;korian.reinemathilde-reception@groupe-korian.com;F;2020-10-04
140024613;residencemathilde@fondation-misericorde.fr;F;2020-10-04
140025560;ehpad.jardindelsa@mfn-ssam.fr;F;2020-10-04
140026261;residence.lesdeuxfontaines@hom-age.fr;F;2020-10-04
140027012;accueil@normandia.fr;F;2020-10-04
140027053;residence.emeraude@hom-age.fr;F;2020-10-04
140027079;residence.topaze@hom-age.fr;F;2020-10-04
140027418;ehpad.epron@mfn-ssam.fr;F;2020-10-04
140027459;direction@ch-falaise.fr;F;2020-10-04
140028010;contact@le-florilege.fr;F;2020-10-04
140028473;ccas@mva14.fr;F;2020-10-04
140030198;ehpad.port-en-bessin@croix-rouge.fr;F;2020-10-04
140030313;ccas@mairie-bayeux.fr;F;2020-10-04
150002418;secretariat.usld@ch-mauriac.fr;F;2020-10-04
150002426;ehpaddelacere@gmail.com;F;2020-10-04
150002699;directioncapblanc@emera.fr;F;2020-10-04
150780161;ehpad-allanche15@orange.fr;F;2020-10-04
150780385;secretariat@ehpad-stelisabeth.fr;F;2020-10-04
150780484;contact@mr-maurs.fr;F;2020-10-04
150780518;ehpad.neussargues@wanadoo.fr;F;2020-10-04
150780534;ehpad@maisonretraitepleaux.fr;F;2020-10-04
150780575;direction@ehpad-riom15.fr;F;2020-10-04
150780682;administration@maisonretraitesalers.fr;F;2020-10-04
150782316;direction@ch-aurillac.fr;F;2020-10-04
150782548;accueil@hl-condat.fr;F;2020-10-04
150782563;direction@ch-aurillac.fr;F;2020-10-04
150782704;residence.auzelaire@wanadoo.fr;F;2020-10-04
150782712;residence.artense@orange.fr;F;2020-10-04
150783025;secretariat@lefloret.fr;F;2020-10-04
150783181;direction@ch-mauriac.fr;F;2020-10-04
150783801;marpa0527@orange.fr;F;2020-10-04
160000527;administration@ehpad-montbron.fr;F;2020-10-04
160002093;administration@ehpad-aubeterre.fr;F;2020-10-04
160002580;ehpad.lesjardinsdantan@orange.fr;F;2020-10-04
160003695;residence.felixgaillard@wanadoo.fr;F;2020-10-04
160003711;foyerrogercardinaud@wanadoo.fr;F;2020-10-04
160003745;secretariat.gamby@wanadoo.fr;F;2020-10-04
160004222;secretariat@ehpadlesorchidees.fr;F;2020-10-04
160004230;ehpadcompain@wanadoo.fr;F;2020-10-04
160004248;ccas@mairie-soyaux.fr;F;2020-10-04
160004271;foyer.rouillac@croix-rouge.fr;F;2020-10-04
160004412;contactecureuils@ardevie.org;F;2020-10-04
160004420;mdrberneuil@aol.com;F;2020-10-04
160004503;direction.secretariat@ch-cognac.fr;F;2020-10-04
160004669;direction@ch-confolens.fr;F;2020-10-14
160005435;residence-leshyades@orange.fr;F;2020-10-04
160006383;direction@hopital-larochefoucauld.fr;F;2020-10-04
160006391;direction@ch-confolens.fr;F;2020-10-04
160007050;direction-ehpad@mouthiers-sur-boeme.fr;F;2020-10-04
160007118;contact.jardinsdelouise@philogeris.com;F;2020-10-04
160007472;mairie.chantillac@wanadoo.fr;F;2020-10-04
160007563;accueil.jarnac@ch-cognac.fr;F;2020-10-04
160007571;ehpad@ch-ruffec.fr;F;2020-10-04
160007803;direction@ch-sud-charente.fr;F;2020-10-04
160008280;mdr.lenoblet@orange.fr;F;2020-10-04
160008322;contact@residence-charles-dorleans.com;F;2020-10-04
160009007;direction@chateaudecresse.fr;F;2020-10-04
160009510;secretariat.ehpad@ch-sud-charente.fr;F;2020-10-04
160009551;mdrbandiat@orange.fr;F;2020-10-04
160009643;direction@ehpad-lacouronne.fr;F;2020-10-04
160009866;ccas.brillac@orange.fr;F;2020-10-04
160009874;secretariat@les-jonquilles.com;F;2020-10-04
160009940;foyer.fleac@orange.fr;F;2020-10-04
160011656;direction.champagne@orange.fr;F;2020-10-04
160011672;direction@ehpad-baignes.fr;F;2020-10-04
160011953;mdrchasseneuil@orange.fr;F;2020-10-04
160013231;direction@chateaudecresse.fr;F;2020-10-04
160014304;direction@ehpad-baignes.fr;F;2020-10-04
170009674;accueil@ehpad-beaulieu.com;F;2020-10-04
170009831;mdr.montigny@orange.fr;F;2020-10-04
170009880;ccas.sainthilaire@orange.fr;F;2020-10-04
170014989;accueil.chateaudemons@orpea.net;F;2020-10-13
170019632;accueil@ljdh-thenac.fr;F;2020-10-04
170019749;residence.lesjardinsdelucile@groupe-mieuxvivre.fr;F;2020-10-04
170020804;ehpad.recouvrance@ville-saintes.fr;F;2020-10-04
170021059;residence.valpastour@trema-asso.fr;F;2020-10-04
170021075;accueil@ehpad-nieul.fr;F;2020-10-04
170021364;accueil.jonzac@groupecolisee.com;F;2020-10-04
170021943;residence.leschampsdunoyer@trema-asso.fr;F;2020-10-04
170022602;accueil.floirac@agepartenaires.com;F;2020-10-04
170022966;secretariat.ehpad@ch-angely.fr;F;2020-10-13
170023006;contact.amelie@lna-sante.com;F;2020-10-04
170023014;residence.rieuxcoudreau@trema-asso.fr;F;2020-10-04
170023196;residence.lesjardinsdelucile@groupe-mieuxvivre.fr;F;2020-10-04
170024038;direction@ch-boscamnant.fr;F;2020-10-04
170780217;secretariat@ehpad-marans.fr;F;2020-10-04
170781140;secretariat.matha@ch-angely.fr;F;2020-10-04
170781157;ehpad-valdegeres@ght-atlantique17.fr;F;2020-10-13
170782387;ehpad@chateaudecharron.com;F;2020-10-04
170782478;secretariat.coralline@ch-royan.fr;F;2020-10-04
170782676;secretariat.mars@ccas-larochelle.fr;F;2020-10-04
170782700;foyer.etang@mairie-royan.fr;F;2020-10-04
170782874;residence.lescedres@ccas-aytre.fr;F;2020-10-04
170782932;residence.decande@groupe-mieuxvivre.fr;F;2020-10-04
170783526;ehpadstsavinien@ch-angely.fr;F;2020-10-13
170783559;secretariat.ehpad@ch-angely.fr;F;2020-10-13
170783575;direction.hopital@ch-jonzac.fr;F;2020-10-13
170783625;direction@ght-atlantique17.fr;F;2020-10-04
170784326;ehpad-usld@ch-saintonge.fr;F;2020-10-04
170784334;contact@residence-ombriere.com;F;2020-10-04
170784433;direction@fl-ccas.fr;F;2020-10-04
170784441;residencelachanceliere@gmail.com;F;2020-10-04
170785133;accueil.le.logis@mairie-royan.fr;F;2020-10-04
170786412;ehpad-usld@ch-saintonge.fr;F;2020-10-04
170788848;direction.hopital@ch-jonzac.fr;F;2020-10-04
170791198;direction@hopitalmarennes.net;F;2020-10-04
170791263;direction@ch-boscamnant.fr;F;2020-10-04
170791289;secretariat.ehpad@ch-angely.fr;F;2020-10-14
170791321;direction@ght-atlantique17.fr;F;2020-10-04
170799837;ehpa.roseraie@amapa.fr;F;2020-10-04
170800437;accueil.ouchedescarmes@orange.fr;F;2020-10-04
170800809;directionaube@gmail.com;F;2020-10-04
170801625;marpacherac17@wanadoo.fr;F;2020-10-04
170802789;direction@ch-royan.fr;F;2020-10-04
170802839;foyerlasavinoise@ch-angely.fr;F;2020-10-04
170802961;ehpad-bernaysaintmartin@orange.fr;F;2020-10-04
170803647;contact.oleron@viteal.com;F;2020-10-14
170803688;contact@chatellenie.com;F;2020-10-14
170803779;la-tonnelle-mdr@wanadoo.fr;F;2020-10-04
170803951;direction.residenceharmonie@orpea.net;F;2020-10-14
170805477;ehpad-providence@providencesaintes.com;F;2020-10-04
170805576;reception.cotesauvage@korian.fr;F;2020-10-04
170805758;direction@rdp17.fr;F;2020-10-04
180000085;ehpad.gracay@wanadoo.fr;F;2020-10-04
180000101;ehpad.lesrosesdargent@wanadoo.fr;F;2020-10-04
180000119;secretariat@hopital-sancerre.fr;F;2020-10-04
180000127;mr.la.guerche@wanadoo.fr;F;2020-10-04
180000135;ehpad.lescedres@outlook.fr;F;2020-10-04
180000143;direction@ehpadligneres.fr;F;2020-10-04
180000168;accueil@ehpad-chatelet.com;F;2020-10-04
180000192;ehpad.mehun@orange.fr;F;2020-10-04
180000218;ehpad-nohant@orange.fr;F;2020-10-04
180000234;administration.ehpadstflorent@orange.fr;F;2020-10-04
180000275;ehpad.maginot@gmail.com;F;2020-10-04
180000291;larocherie.direction@wanadoo.fr;F;2020-10-04
180000556;residence.raynal@ville-bourges.fr;F;2020-10-04
180001166;marpa.saulzais@orange.fr;F;2020-10-04
180001174;marpa.chapelle@wanadoo.fr;F;2020-10-04
180003048;marpaduvaldarnon@orange.fr;F;2020-10-04
180003378;direction@ch-stamand.fr;F;2020-10-04
180003410;direction.residence-vesdun@cdc-berry-grand-sud.fr;F;2020-10-04
180003436;residencelouisjouannin@orange.fr;F;2020-10-04
180003444;residence.guilbeau@ville-bourges.fr;F;2020-10-04
180003469;ehpad.ambroise-croizat@ville-vierzon.fr;F;2020-10-04
180004087;accueil.gite-amitie@ladapt.net;F;2020-10-04
180004426;ehpad.les-marronniers@orange.fr;F;2020-10-04
180004434;secretariat-les-vallieres@orange.fr;F;2020-10-04
180004442;residence.bailly@ville-bourges.fr;F;2020-10-04
180004608;contact@ehpad-chateaumeillant.fr;F;2020-10-04
180004616;secretariat@hopital-sancerre.fr;F;2020-10-04
180004673;direction@ch-stamand.fr;F;2020-10-04
180004848;direction@ch-stamand.fr;F;2020-10-04
180004889;secretariat@hopital-sancerre.fr;F;2020-10-04
180005696;secretariat.usld.bourges@ch-george-sand.fr;F;2020-10-04
180005803;direction@ch-bourges.fr;F;2020-10-04
180005860;contact@massay18.fr;F;2020-10-04
180005944;marpacharentonducher@orange.fr;F;2020-10-04
180006017;reception.portesdesologne@korian.fr;F;2020-10-04
180006637;secretariat@hopital-sancerre.fr;F;2020-10-04
180007429;direction.ehpad.antoinemoreau@orange.fr;F;2020-10-04
180007825;secretariat.usld.dun@ch-george-sand.fr;F;2020-10-04
180008658;secretariat.usld.bourges@ch-george-sand.fr;F;2020-10-04
180008666;administration1.lavalleebleue@korian.fr;F;2020-10-04
180008674;secretariat.ehpad.chezal@ch-george-sand.fr;F;2020-10-04
180008682;secretariat.usld.dun@ch-george-sand.fr;F;2020-10-04
190000083;ehpadneuvic19@orange.fr;F;2020-10-04
190000299;accueil@ehpad-argentat.fr;F;2020-10-04
190001438;contact@ehpad-beynat.fr;F;2020-10-04
190001834;direction@ch-tulle.fr;F;2020-10-04
190002097;administration@augreduvent19.fr;F;2020-10-04
190002113;direction@chg-cornil.fr;F;2020-10-04
190002139;mrtreignac@wanadoo.fr;F;2020-10-04
190002188;ehpadpeyrelevade@mutualitelimousine.fr;F;2020-10-04
190002717;direction@ch-ussel.fr;F;2020-10-04
190002725;secretariat.direction@ch-bort.fr;F;2020-10-04
190002733;secretariat.direction@ch-bort.fr;F;2020-10-04
190002741;direction@ch-tulle.fr;F;2020-10-04
190003673;secretariat.ehpad@avehc.fr;F;2020-10-04
190003681;accueil@ehpadbugeat.fr;F;2020-10-04
190003699;direction@ehpad-pompadour.fr;F;2020-10-04
190003723;secretariat.direction@chg-uzerche.fr;F;2020-10-04
190003731;direction.ehpadstprivat@orange.fr;F;2020-10-04
190003749;ehpad.seilhac@wanadoo.fr;F;2020-10-04
190003764;ehpad.marcillac@wanadoo.fr;F;2020-10-04
190003772;direction@ehpadmeyssac.fr;F;2020-10-04
190003780;direction@croiseedesans.fr;F;2020-10-04
190003806;ehpad3@wanadoo.fr;F;2020-10-04
190003814;accueil@ehpad-donzenac.fr;F;2020-10-04
190003822;ccas.chamboulive@wanadoo.fr;F;2020-10-04
190003848;residence.nacre@ville-tulle.fr;F;2020-10-04
190003863;foyer@ussel19.fr;F;2020-10-04
190003905;ehpad.charlesgobert@wanadoo.fr;F;2020-10-04
190004028;sornacehpad@orange.fr;F;2020-10-04
190004044;lauriers.contact@gmail.com;F;2020-10-04
190004093;ccas@brive.fr;F;2020-10-04
190004119;direction@ch-ussel.fr;F;2020-10-04
190004234;ccas@brive.fr;F;2020-10-04
190005140;secretariat.direction@shg-uzerche.fr;F;2020-10-04
190005165;direction@chg-cornil.fr;F;2020-10-04
190005231;secretariat-direction@ehpad-vigeois.fr;F;2020-10-04
190005330;ccas@brive.fr;F;2020-10-04
190005520;ehpad.eygurande@orange.fr;F;2020-10-04
190005611;marpa.liginiac@orange.fr;F;2020-10-04
190005652;accueil.brive@orpea.net;F;2020-10-04
190005926;contact@ehpadchabrignac.fr;F;2020-10-04
190006254;mairie.laguenne@wanadoo.fr;F;2020-10-04
190010538;ccas@brive.fr;F;2020-10-04
190010884;direction.cosnac@groupecolisee.com;F;2020-10-04
190011395;direction@ch-tulle.fr;F;2020-10-14
190011783;direction@chg-cornil.fr;F;2020-10-14
210006409;direction@chs-chartreuse.fr;F;2020-10-04
210007159;residence-visitation@wanadoo.fr;F;2020-10-04
210010435;direction-meursault@lesopalines.fr;F;2020-10-04
210010799;marpa.talmay@pepcbfc.fr;F;2020-10-04
210011250;secretariat.moutiers@orange.fr;F;2020-10-04
210780565;secretariat@laprovidence21.fr;F;2020-10-04
210780813;accueil@foyer-st-francois.com;F;2020-10-04
210780912;mrlaignes@wanadoo.fr;F;2020-10-04
210780920;secretariat.moutiers@orange.fr;F;2020-10-04
210780938;mr.nolay@wanadoo.fr;F;2020-10-04
210780946;ehpad.lesarcades@ehpadlesarcades.fr;F;2020-10-04
210780953;ehpad.lasaone@orange.fr;F;2020-10-04
210780961;administrationmrbligny@wanadoo.fr;F;2020-10-04
210781043;ehpad.moussier@ccass-sbe.org;F;2020-10-04
210781118;direction@epcapa-dijon.fr;F;2020-10-04
210781464;residence-du-parc@mfbssam.fr;F;2020-10-04
210781522;direction@ch-beaune.fr;F;2020-10-04
210781530;direction@ch-beaune.fr;F;2020-10-04
210781589;accueil.ehpad@ch-semur.fr;F;2020-10-04
210950010;accueil@residence-jeanne.fr;F;2020-10-04
210950028;esperance.direction@arpavie.fr;F;2020-10-14
210950051;direction-verdaines@groupe-sos.org;F;2020-10-04
210950069;accueil@mdr-st-joseph.com;F;2020-10-04
210950119;direction@epcapa-dijon.fr;F;2020-10-04
210950226;direction@ch-hco.fr;F;2020-10-04
210983375;contact@lacroixviolette.fr;F;2020-10-04
210983474;accueil-arnayleduc@ch-beaune.fr;F;2020-10-04
210983557;direction@ch-hco.fr;F;2020-10-04
210983565;direction@ch-hco.fr;F;2020-10-04
210983615;direction@ch-beaune.fr;F;2020-10-04
210983987;direction@epcapa-dijon.fr;F;2020-10-04
210984399;hopitalseurre@wanadoo.fr;F;2020-10-04
210984407;direction@ch-hco.fr;F;2020-10-04
210984415;hopital.nuits@wanadoo.fr;F;2020-10-04
210984423;secretariat@hopitalissurtille.com;F;2020-10-04
210984431;direction.auxonne@ch-auxonne.fr;F;2020-10-04
210984449;accueil-arnayleduc@ch-beaune.fr;F;2020-10-04
210985305;reception.closdesvignes@korian.fr;F;2020-10-04
210985339;direction-hauteville@lesopalines.fr;F;2020-10-04
210985362;ehpaddirection.longvic@orange.fr;F;2020-10-04
210985750;ehpadrecey@coallia.org;F;2020-10-04
210986170;direction-santenay@lesopalines.fr;F;2020-10-04
210986188;contact@eteindien21.fr;F;2020-10-04
210986386;hopitalseurre@wanadoo.fr;F;2020-10-04
210986600;secretariat@ehpad-maisondetherese.fr;F;2020-10-04
210986642;tonnelles.direction@arpavie.fr;F;2020-10-04
210986808;direction@ch-hco.fr;F;2020-10-04
210986865;marpa.montigny@pep21.org;F;2020-10-04
210986907;marpa.baigneux@orange.fr;F;2020-10-04
210987939;direction@chs-chartreuse.fr;F;2020-10-04
220000533;contact@moncontour.hstv.fr;F;2020-10-04
220002398;direction@ch2p.bzh;F;2020-10-04
220002406;administration@ehpadkerdudi.fr;F;2020-10-04
220002422;direction@ehpadcorlay.fr;F;2020-10-04
220002448;ehpad.pleudihen@wanadoo.fr;F;2020-10-04
220003875;ccas.maelcarhaix@wanadoo.fr;F;2020-10-04
220003891;direction@ch2p.bzh;F;2020-10-04
220003909;contact@residence-des-genets-merdrignac.com;F;2020-10-04
220003925;ehpad.chatelaudren@wanadoo.fr;F;2020-10-04
220003933;administration@ehpad-callac.fr;F;2020-10-04
220003974;ehpadploumilliau@wanadoo.fr;F;2020-10-04
220004006;ehpad@ville-plerin.fr;F;2020-10-04
220004014;ehpad@plestinlesgreves.com;F;2020-10-04
220004030;residence.ledan@wanadoo.fr;F;2020-10-04
220004055;directionevran@orange.fr;F;2020-10-04
220004071;foyerdugavel@wanadoo.fr;F;2020-10-04
220004097;foyer.logement.lanvallay@wanadoo.fr;F;2020-10-04
220004113;ehpadploeuc@orange.fr;F;2020-10-04
220004139;direction@montbareil.fr;F;2020-10-04
220004154;mdr-le-cosquer@orange.fr;F;2020-10-04
220004352;accueil@ccasplancoet.fr;F;2020-10-04
220004378;direction@presuzun.fr;F;2020-10-04
220004394;accueil@lgoplouha.fr;F;2020-10-04
220004527;secretariat-kersalic@orange.fr;F;2020-10-04
220004535;foyerlesmouettes@wanadoo.fr;F;2020-10-04
220004550;mairie-lanvellec@orange.fr;F;2020-10-04
220004592;ccasbroons@wanadoo.fr;F;2020-10-04
220004600;ehpadkermaria@plouguenast-langast.fr;F;2020-10-04
220004659;foyerlogement.treguier@wanadoo.fr;F;2020-10-04
220004667;residence.lacroixgreau@orange.fr;F;2020-10-04
220004964;accueil@etad.fr;F;2020-10-04
220004980;residence.duparc@wanadoo.fr;F;2020-10-04
220005037;accueil.mr@ch-dinan.fr;F;2020-10-04
220005417;direction-cedre@montbareil.fr;F;2020-10-04
220005433;foyer.hernot@ville-lannion.fr;F;2020-10-04
220005524;ehpad.pax@coallia.org;F;2020-10-04
220005581;association.joachim.fleury@gmail.com;F;2020-10-04
220006407;direction@ch-treguier.fr;F;2020-10-04
220006456;direction@ch2p.bzh;F;2020-10-04
220006464;direction@ch2p.bzh;F;2020-10-04
220006498;direction@ch2p.bzh;F;2020-10-04
220006506;secretariat.direction@ch-centre-bretagne.fr;F;2020-10-04
220006597;hopital@ch-stbrieuc.fr;F;2020-10-04
220006753;ehpad@henon.fr;F;2020-10-04
220006779;foyerlogement@ehpad-hillion.fr;F;2020-10-04
220006795;ehpad.jugonleslacs@wanadoo.fr;F;2020-10-04
220006811;foyerlequinic@wanadoo.fr;F;2020-10-04
220006852;ccas-pleneejugon@orange.fr;F;2020-10-04
220006860;accueil@bourgneufehpad.org;F;2020-10-04
220006878;ccas-pleneejugon@orange.fr;F;2020-10-04
220006910;ccas@ville-penvenan.fr;F;2020-10-04
220006936;ehpad.ereac@mutualite22.fr;F;2020-10-04
220007603;foyer.pleslin@wanadoo.fr;F;2020-10-04
220007645;direction@ch-treguier.fr;F;2020-10-04
220007769;mairie@rostrenen.com;F;2020-10-04
220013890;ehpadplelan@dinan-agglomeration.fr;F;2020-10-04
220013957;accueil.ehpad@ville-pledran.fr;F;2020-10-04
220014138;secretariat.keramour@ahbretagne.com;F;2020-10-04
220014690;ehpad@fondationbonsauveur.fr;F;2020-10-04
220014997;residence-prevallon@saint-brieuc.fr;F;2020-10-04
220016125;ehpad.clairsoleil@coallia.org;F;2020-10-04
220016166;direction@ch2p.bzh;F;2020-10-04
220016174;direction@ch2p.bzh;F;2020-10-04
220016182;direction@ch2p.bzh;F;2020-10-04
220016216;ehpad.saint-emilion@coallia.org;F;2020-10-04
220016240;direction@ch2p.bzh;F;2020-10-04
220017149;ehpad.horizon-bleu@orange.fr;F;2020-10-04
220018741;foyer.logement-trevou@orange.fr;F;2020-10-04
220019178;direction-ermitage@montbareil.fr;F;2020-10-04
220020143;direction@ch-dinan.fr;F;2020-10-04
220020150;ccas@ville-penvenan.fr;F;2020-10-04
220020168;direction@ehpad-hillion.fr;F;2020-10-04
220020176;ccasplemet@wanadoo.fr;F;2020-10-04
220020184;secretariat.keramour@ahbretagne.com;F;2020-10-04
220020408;contact@admr22.org;F;2020-10-04
220020432;ccas@ehpadfrehel.fr;F;2020-10-04
220020556;foyerlogementplelanlepetit@orange.fr;F;2020-10-04
220021083;direction@ch-treguier.fr;F;2020-10-04
220021091;contact@admr22.org;F;2020-10-04
220022032;residence-kersalic@orange.fr;F;2020-10-04
220022321;accueil@bourgneufehpad.org;F;2020-10-04
220022404;direction@montbareil.fr;F;2020-10-04
220022412;direction@ch2p.bzh;F;2020-10-04
220022420;ehpad@ch-guingamp.fr;F;2020-10-04
220023428;contact@hstv.fr;F;2020-10-04
230000234;secretariat.direction@ch-bourganeuf.fr;F;2020-10-04
230000242;secretariat.direction@ch-bourganeuf.fr;F;2020-10-04
230000259;ch.gueret@ch-gueret.fr;F;2020-10-04
230000283;ehpadlesbouquets@sil.fr;F;2020-10-04
230000333;foyer-residenceeau-bonne@wanadoo.fr;F;2020-10-04
230000523;accueil@ehpad-lachapelaude.fr;F;2020-10-04
230000531;contact@ehpadmarsac.fr;F;2020-10-04
230003618;ehpad-chatelus@ehpad-boussac.fr;F;2020-10-04
230003659;ehpadlechabanou@ch-aubusson.fr;F;2020-10-04
230004079;direction@ch-lasouterraine.fr;F;2020-10-04
230004178;ch.evauxlesbains@ch-evauxlesbains.fr;F;2020-10-04
230004681;direction@ch-lasouterraine.fr;F;2020-10-04
230780256;administration@ehpad-auzances.fr;F;2020-10-04
230780264;accueil@ehpadbenevent.fr;F;2020-10-04
230780272;ehpad@ehpad-chambon.fr;F;2020-10-04
230780280;direction@ehpad-dun.fr;F;2020-10-04
230780306;administration@ehpad-mainsat.fr;F;2020-10-04
230780314;direction@ch-lasouterraine.fr;F;2020-10-04
230780322;secretariat@ehpad-royere.fr;F;2020-10-04
230781627;ehpadboussac@ehpad-boussac.fr;F;2020-10-04
230781668;ch.gueret@sil.fr;F;2020-10-14
230781676;accueil@ehpad-bussiere.fr;F;2020-10-04
230781684;secretariat@ehpadlesmyosotis.fr;F;2020-10-04
230781692;ehpad.fursac0@orange.fr;F;2020-10-04
230781767;secretariat.direction@ch-bourganeuf.fr;F;2020-10-04
230781916;administration@ehpadajain.fr;F;2020-10-04
230782724;ch.evauxlesbains@ch-evauxlesbains.fr;F;2020-10-04
230782732;direction@ch-lasouterraine.fr;F;2020-10-04
230782898;direction@ch-st-vaury.fr;F;2020-10-04
240000224;administration.villadescebrades@korian.fr;F;2020-10-04
240000570;accueil@ehpadfonfrede.fr;F;2020-10-04
240002071;accueil@ehpad-lacoquille.fr;F;2020-10-04
240002121;ehpad24440@orange.fr;F;2020-10-04
240002139;accueil@bourdeilles2sequoias.fr;F;2020-10-04
240002147;ehpad.brantome@sil.fr;F;2020-10-04
240002154;ehpadcadouin@orange.fr;F;2020-10-14
240002162;secretariat@ehpad-carsac.fr;F;2020-10-04
240002170;direction@ehpadmareuil.fr;F;2020-10-04
240002188;direction@ehpadmontignac.fr;F;2020-10-04
240002204;ehpad@ehpad-mussidan.fr;F;2020-10-04
240002212;ehpad-porte.aquitaine@orange.fr;F;2020-10-04
240002238;ehpadthiviers@sil.fr;F;2020-10-04
240002246;secretariat@ehpadhautefort.fr;F;2020-10-04
240002253;ehpad.lalinde@orange.fr;F;2020-10-04
240002261;accueil@ehpad-monpazier.fr;F;2020-10-04
240002279;direction2017@ehpad-salignac.fr;F;2020-10-04
240002741;direction@lajuvenie.fr;F;2020-10-04
240004390;secretariat.ehpad@ch-perigueux.fr;F;2020-10-04
240004408;secretariat.ehpad@ch-perigueux.fr;F;2020-10-04
240005074;mairie@mussidan.fr;F;2020-10-04
240005082;mairie@stcyprien24.fr;F;2020-10-04
240005124;retraitedumanoire@orange.fr;F;2020-10-04
240005280;mr.neuvic@wanadoo.fr;F;2020-10-04
240006304;secretariat.ehpad@ch-perigueux.fr;F;2020-10-04
240006379;accueil.prigonrieux@groupecolisee.com;F;2020-10-14
240006502;ehpad.brantome@sil.fr;F;2020-10-04
240006544;cias.eymet@wanadoo.fr;F;2020-10-04
240006577;ccas-riberac@wanadoo.fr;F;2020-10-04
240006585;ccas@saint-astier.fr;F;2020-10-04
240006601;admissions@hl-belves.fr;F;2020-10-04
240006916;contact@leboisdore.net;F;2020-10-04
240006973;accueil@ljdh-alvere.fr;F;2020-10-04
240007609;direction@hl-belves.fr;F;2020-10-04
240007617;secretariat.direction@ch-bergerac.fr;F;2020-10-04
240007625;secretariat.direction@ch-bergerac.fr;F;2020-10-04
240007658;admission@hldomme.com;F;2020-10-14
240007666;accueil@hopital-excideuil.fr;F;2020-10-04
240007674;secretariat.direction@ch-nontron.fr;F;2020-10-04
240007690;hopital@hlsa.fr;F;2020-10-04
240007716;direction-secretariat@ch-sarlat.fr;F;2020-10-04
240008136;accueil@ehpadsaintleon.fr;F;2020-10-04
240008391;ehpad@ladryade.fr;F;2020-10-04
240008557;direction-secretariat@ch-sarlat.fr;F;2020-10-04
240008565;accueil@residence-leschenesverts.com;F;2020-10-04
240008631;contact@petitgardonne.fr;F;2020-10-04
240008656;secretariat.direction@ch-nontron.fr;F;2020-10-04
240008763;direction@ehpad-tremolades.fr;F;2020-10-04
240009282;mairie@mairie-neuvic.fr;F;2020-10-04
240009407;contact@lacompassion.fr;F;2020-10-04
240009761;ehpad-jean-gallet@orange.fr;F;2020-10-04
240009779;direction.lamothe@sgmr-ouest.com;F;2020-10-04
240009894;direction-secretariat@ch-sarlat.fr;F;2020-10-04
240009902;cias@sarlat.fr;F;2020-10-04
240009928;marpa@ciasbdp.fr;F;2020-10-04
240013029;ehpad.cantonsaintcyprien@orange.fr;F;2020-10-04
240013300;contact@lavalleeduroy.fr;F;2020-10-04
240013318;secretariat.direction@ch-nontron.fr;F;2020-10-04
240013961;administration.yvanroque@korian.fr;F;2020-10-04
240014902;ehpad@lesjardinsdeplaisance.com;F;2020-10-04
240015925;contact@ehpad-thiviers.fr;F;2020-10-04
240016311;secretariat.lesvignes@orpea.net;F;2020-10-04
250000429;direction@cls-bellevaux.com;F;2020-10-04
250001237;direction@cls-bellevaux.com;F;2020-10-04
250001252;direction@cjw-avanne.com;F;2020-10-04
250002102;ehpadchateauvorget.rougemont@orange.fr;F;2020-10-04
250002128;mraudincourt@gmail.com;F;2020-10-04
250002862;mrlevier@chi-hautecomte.fr;F;2020-10-04
250002888;direction@cjw-avanne.com;F;2020-10-04
250004041;contact@chi-hautecomte.fr;F;2020-10-04
250004165;secretariat-direction@ehpad-mamirolle.fr;F;2020-10-04
250004215;hopital-baume-direction@orange.fr;F;2020-10-04
250004223;accueil@hopitalmorteau.fr;F;2020-10-04
250004264;contact@chquingey.fr;F;2020-10-04
250004363;residenceautonomie.cedres@besancon.fr;F;2020-10-04
250004389;residenceautonomie.hortensias@besancon.fr;F;2020-10-04
250004397;residenceautonomie.lilas@besancon.fr;F;2020-10-04
250004405;residenceautonomie.huot@besancon.fr;F;2020-10-04
250004413;residenceautonomie.marulaz@besancon.fr;F;2020-10-04
250004421;foyer.bossiere@montbeliard.com;F;2020-10-04
250004439;foyer.logement@valdahon.com;F;2020-10-04
250004447;residenceautonomie@salinsdebregille.com;F;2020-10-04
250004496;secretariat@ehpadsaintferjeux.fr;F;2020-10-04
250007119;contact@ch-ornans.fr;F;2020-10-04
250007226;accueil@hopitalmorteau.fr;F;2020-10-04
250007234;contact@chi-hautecomte.fr;F;2020-10-04
250007762;contact@chi-hautecomte.fr;F;2020-10-04
250008349;residence.surleau@fondation-arcenciel.fr;F;2020-10-04
250010675;marpa.amancey@orange.fr;F;2020-10-04
250011608;hopital-baume-direction@wanadoo.fr;F;2020-10-04
250015161;marpamaiche@gmail.com;F;2020-10-04
250015245;secretariat-direction@ehpad-mamirolle.fr;F;2020-10-04
250015278;accueil@eliad-fc.fr;F;2020-10-04
250015328;accueil@eliad-fc.fr;F;2020-10-04
250017498;accueil@eliad-fc.fr;F;2020-10-04
250017795;marpalesvalentines@orange.fr;F;2020-10-04
250018843;direction.bonnetage@groupecolisee.com;F;2020-10-04
250019205;marpaduvaldeloue@orange.fr;F;2020-10-04
250019387;accueil@eliad-fc.fr;F;2020-10-04
260000898;accueil.fleuriades@voila.fr;F;2020-10-04
260000906;accueil@ehpad-lamatiniere.fr;F;2020-10-04
260002068;mr-grignan@wanadoo.fr;F;2020-10-04
260003868;accueil@ehpadmarsanne.fr;F;2020-10-04
260005418;ehpad.eden@eovi.fr;F;2020-10-04
260005426;ehpad.dauphine@eovi.fr;F;2020-10-04
260005434;ehpad.beausoleil@eovi.fr;F;2020-10-04
260005442;ehpad.delessert@eovi.fr;F;2020-10-04
260005467;secretariat@orsac-la-pousterle.fr;F;2020-10-04
260005475;ehpad.loubet@eovi.fr;F;2020-10-04
260005483;accueil@residencelapastourelle.fr;F;2020-10-04
260005509;ehpa.louise-michel@eovi.fr;F;2020-10-04
260005517;mr.tulette@wanadoo.fr;F;2020-10-04
260005525;direction-sainte-germaine@groupe-sos.org;F;2020-10-04
260005541;residence.moun-oustaou@orange.fr;F;2020-10-04
260005566;direction@orsac-la-pousterle.fr;F;2020-10-04
260005582;accueil@ehpadlesminimes.fr;F;2020-10-04
260006168;secretariat-beauvoir@groupe-sos.org;F;2020-10-04
260006176;ehpad.arnaud@habitat-humanisme.org;F;2020-10-04
260006218;ehpad.lescedres@wanadoo.fr;F;2020-10-04
260009139;direction@ch-montelimar.fr;F;2020-10-04
260009162;direction@hl-dieulefit.fr;F;2020-10-04
260009170;direction@ch-crest.fr;F;2020-10-04
260009188;direction@ch-die.fr;F;2020-10-04
260009196;direction@hl-buis.fr;F;2020-10-04
260009204;direction@hl-nyons.fr;F;2020-10-04
260009303;mapa.oustalet@wanadoo.fr;F;2020-10-04
260009311;residencemariefrancepreault@mairie-valence.fr;F;2020-10-04
260010012;direction@chs-levalmont.fr;F;2020-10-04
260010467;mdr.voieromaine@wanadoo.fr;F;2020-10-04
260011051;secretariat.direction@ch-hdn.fr;F;2020-10-04
260011457;accueil.blanchelaine@orange.fr;F;2020-10-04
260011754;direction.ehpad@mareverdy.fr;F;2020-10-04
260012208;ehpad.peysson@eovi.fr;F;2020-10-04
260012257;ehpad.collines@eovi.fr;F;2020-10-04
260012489;contact@lesgenets.fr;F;2020-10-04
260013016;ehpa.louise.michel@eovi.fr;F;2020-10-04
260013073;direction.ehpad@mareverdy.fr;F;2020-10-04
260013123;direction@hl-nyons.fr;F;2020-10-04
260013222;accueil.montelier@groupecolisee.com;F;2020-10-04
260013974;secretariat.ehpad.saintegermaine@orange.fr;F;2020-10-04
260014188;vallis-aurea.direction@arpavie.fr;F;2020-10-04
260017462;direction-galaure@lesopalines.fr;F;2020-10-04
260017611;marpa@marpa-anneyron.com;F;2020-10-04
260018122;ehpad.biancheri@eovi.fr;F;2020-10-04
260018148;contact@marpa-baronnies-provencales.fr;F;2020-10-04
260018171;ehpad.biancheri@eovi.fr;F;2020-10-04
260018213;ehpad.loubet@eovi.fr;F;2020-10-04
260018403;accueil-administratif-rochecolombe@ch-montelimar.fr;F;2020-10-04
270002074;mrecouis@wanadoo.fr;F;2020-10-04
270002306;reception.lermitage@korian.fr;F;2020-10-04
270002322;ccas.mairie@evreux.fr;F;2020-10-04
270003965;mairie-breteuil@orange.fr;F;2020-10-14
270003973;ccas@evreux.fr;F;2020-10-04
270003981;ccas@evreux.fr;F;2020-10-04
270003999;ccas@ville-gaillon.fr;F;2020-10-04
270004237;residence@pontdelarche.fr;F;2020-10-04
270004294;ccas@romilly-sur-andelle.fr;F;2020-10-04
270004328;ccas@marcel27.fr;F;2020-10-04
270004336;contact@vernon27.fr;F;2020-10-04
270007727;residencejuillet@verneuilsuravre.fr;F;2020-10-04
270008667;direction@ch-gisors.fr;F;2020-10-04
270008675;direction@ch-gisors.fr;F;2020-10-04
270008683;direction@vbr-sudeure.fr;F;2020-10-04
270008691;direction@vbr-sudeure.fr;F;2020-10-04
270008725;ehpad@chi-elbeuf-louviers.fr;F;2020-10-04
270008758;ccas@evreux.fr;F;2020-10-04
270009053;direction@ch-lesandelys.fr;F;2020-10-04
270009087;secretariatdirection@ch-leneubourg.fr;F;2020-10-04
270009095;secretariatdirection@ch-leneubourg.fr;F;2020-10-04
270009103;accueil@hopital-pacy.fr;F;2020-10-04
270009111;direction@vbr-sudeure.fr;F;2020-10-04
270009129;direction@vbr-sudeure.fr;F;2020-10-04
270009210;direction@ch-pontaudemer.fr;F;2020-10-04
270009228;direction@ch-pontaudemer.fr;F;2020-10-04
270009467;ccasgisors@mairie-gisors.fr;F;2020-10-04
270009566;mairie.st-ouen-du-tilleul@wanadoo.fr;F;2020-10-04
270009590;contact@fleury-sur-andelle.fr;F;2020-10-04
270009939;secretariat.residence@ch-bernay.fr;F;2020-10-04
270010697;accueil.boislarose@philogeris.com;F;2020-10-04
270012099;ccasgisors@mairie-gisors.fr;F;2020-10-04
270012230;contact@villa-saint-michel.fr;F;2020-10-04
270012370;residence.parc@ville-louviers.fr;F;2020-10-04
270012750;contact@lasterina.com;F;2020-10-04
270012990;secretariat@lebremiennd.com;F;2020-10-04
270013097;residencelesjardins@wanadoo.fr;F;2020-10-04
270013527;accueil.saintgermain@agepartenaires.com;F;2020-10-04
270013964;ccas.mairie@evreux.fr;F;2020-10-04
270016728;hopital.pacy@hopital-pacy.fr;F;2020-10-04
270018278;direction@villalaprovidence.fr;F;2020-10-04
270023534;mairie.lieurey@wanadoo.fr;F;2020-10-04
270024524;direction@laresidencedulac.fr;F;2020-10-04
280000167;secretariat@ehpadnogentleroi.fr;F;2020-10-04
280000639;accueil@mdr-brezolles.fr;F;2020-10-04
280000647;mrabondant.direction@gmail.com;F;2020-10-04
280000704;accueil@ehpadsenonches.fr;F;2020-10-04
280002171;mdrtoury@gmail.com;F;2020-10-04
280005968;marpa-margon@orange.fr;F;2020-10-04
280006321;direction@ch-chateaudun.fr;F;2020-10-04
280500083;direction@ch-chateaudun.fr;F;2020-10-04
280500273;residenceautonomie@ville-dreux.fr;F;2020-10-04
280500331;residence.gaujard@agglo-ville.chartres.fr;F;2020-10-04
280500802;residence-autonomie@mairie-chateaudun.fr;F;2020-10-04
280503368;mdrjeannedarc.janville@orange.fr;F;2020-10-04
280503384;secretariat@mr-lesgenets-illiers28.fr;F;2020-10-04
280503392;direction@ehpad-courtalain.fr;F;2020-10-04
280503426;direction@hopital-laloupe.fr;F;2020-10-04
280503434;direction@ch-laloupe.fr;F;2020-10-04
280503558;direction@ch-chateaudun.fr;F;2020-10-04
280503574;direction@ch-dreux.fr;F;2020-10-04
280503582;direction@ch-nogentlerotrou.fr;F;2020-10-04
280504275;foyer@ville-luisant.fr;F;2020-10-04
280504903;direction@ehpad-maintenon.fr;F;2020-10-14
280504911;residence.monfort@agglo-ville.chartres.fr;F;2020-10-04
280505645;direction-gloriettes@groupe-sos.org;F;2020-10-04
280506064;contact.aquarelle@philogeris.com;F;2020-10-04
280506106;direction.charles@lna-sante.com;F;2020-10-04
290000595;ehpad.adoration@maison-saintjoseph.fr;F;2020-10-04
290000884;ehpadsaintfrancois@orange.fr;F;2020-10-04
290000892;contact@plougastel.hstv.fr;F;2020-10-04
290002047;mraudierne@laposte.net;F;2020-10-04
290002054;collinesbleues.accueil@orange.fr;F;2020-10-04
290002070;contact@ehpadabers.fr;F;2020-10-04
290002088;accueil@residence-saint-michel.fr;F;2020-10-04
290002096;contact@ehpadabers.fr;F;2020-10-04
290002104;accueil@mrplabennec.fr;F;2020-10-04
290002112;direction@mdr-alexis-julien.com;F;2020-10-04
290002120;mr.pontcroix@wanadoo.fr;F;2020-10-04
290002179;mr-taule@wanadoo.fr;F;2020-10-04
290002724;ehpad.saintjoseph@maison-saintjoseph.fr;F;2020-10-04
290002740;accueil@asso-sainte-bernadette.fr;F;2020-10-04
290002880;la.retraite@wanadoo.fr;F;2020-10-04
290002930;direction.kerampir@ugecam.assurance-maladie.fr;F;2020-10-04
290003979;direction@ch-quimperle.fr;F;2020-10-04
290004019;accueil.ehpad@hopital-landerneau.fr;F;2020-10-04
290004118;accueil@ch-saint-renan.fr;F;2020-10-04
290004209;direction@ch-douarnenez.fr;F;2020-10-04
290004571;contact@ehpadabers.fr;F;2020-10-04
290004605;residence.kerlevenez@ccas-brest.fr;F;2020-10-04
290004639;ehpad-direction-chateauneuf@orange.fr;F;2020-10-04
290004647;residence.golven@kanarmor.fr;F;2020-10-04
290004654;cias.resid@cc-paysfouesnantais.fr;F;2020-10-04
290004662;residence.guic@wanadoo.fr;F;2020-10-04
290004670;direction@sivu-elorn.fr;F;2020-10-04
290004712;ehpad@villedemorlaix.org;F;2020-10-04
290004720;resid.du.brug@orange.fr;F;2020-10-04
290004738;ehpad.plouigneau@orange.fr;F;2020-10-04
290004753;ehpadfontaine.pontcroix@capsizun.fr;F;2020-10-04
290004779;accueil.valelorn@wanadoo.fr;F;2020-10-04
290004795;residence.kerval@wanadoo.fr;F;2020-10-04
290004944;ehpad.coray@wanadoo.fr;F;2020-10-04
290005909;mestioual-direction@orange.fr;F;2020-10-04
290005917;ehpadcamelias@ccas-pontlabbe.fr;F;2020-10-04
290006378;residence.autonomie@concarneau.fr;F;2020-10-04
290006444;direction@ehpadcamaret.fr;F;2020-10-04
290007590;accueil@hopital-lesneven.fr;F;2020-10-04
290007657;accueil@hopital-crozon.fr;F;2020-10-04
290008853;direction@ch-douarnenez.fr;F;2020-10-04
290009919;foyer.logement.carhaix@orange.fr;F;2020-10-04
290009927;accueillatrinite@cchpb.com;F;2020-10-04
290009935;ehpad.menezkergoff@orange.fr;F;2020-10-04
290010461;ehpad.kerampere@lesgenetsdor.org;F;2020-10-04
290014687;direction@ch-quimperle.fr;F;2020-10-04
290017201;ehpad-louise-le-roux@ccas-brest.fr;F;2020-10-04
290017961;contact@maison-retraite-huelgoat.fr;F;2020-10-04
290018571;mapa.clohars-carnoet@orange.fr;F;2020-10-04
290018597;mapaplouarzel@mutualite29-56.fr;F;2020-10-04
290019793;ehpad.kerallan@lesgenetsdor.org;F;2020-10-04
290019819;accueil-therese.rondeau@wanadoo.fr;F;2020-10-04
290019876;mapa.elliant@wanadoo.fr;F;2020-10-14
290020163;mr.plouvorn@wanadoo.fr;F;2020-10-04
290020312;ehpad.pleyben@wanadoo.fr;F;2020-10-04
290020510;residence.dardoup@orange.fr;F;2020-10-14
290020551;residence.manon@philogeris.com;F;2020-10-04
290020585;marpa.29@orange.fr;F;2020-10-04
290020601;accueil1@ehpadkerlenn.fr;F;2020-10-04
290020957;ehpad.arzano@orange.fr;F;2020-10-04
290021013;mapad@sivu-elorn.fr;F;2020-10-04
290021187;cias.resid@cc-paysfouesnantais.fr;F;2020-10-04
290021294;ehpad.cleden@capsizun.fr;F;2020-10-04
290021427;ehpad.plouhinec@capsizun.fr;F;2020-10-04
290023449;residence.lasource@ildys.org;F;2020-10-04
290023456;ehpad.4moulins@lesgenetsdor.org;F;2020-10-04
290023571;mapa.ouessant@wanadoo.fr;F;2020-10-04
290023605;secretariat-direction@ch-morlaix.fr;F;2020-10-04
290023753;accueil@ehpad-briec.fr;F;2020-10-04
290024462;direction@epsm-quimper.fr;F;2020-10-04
290025139;contact@asdomicile.com;F;2020-10-04
290025402;direction.meriroise@lna-sante.com;F;2020-10-04
290025444;ehpad-antoine-salaun@ccas-brest.fr;F;2020-10-04
290027358;accueildejour@ty-bemdez.fr;F;2020-10-04
290030154;ccas@mairie-quimper.fr;F;2020-10-04
290030634;ehpad.plogonnec@quimper-bretagne-occidentale.bzh;F;2020-10-04
290031822;direction@sivu-elorn.fr;F;2020-10-04
290032036;adminlatrinite@cchpb.com;F;2020-10-04
290032903;contact@adsstpol.una29.fr;F;2020-10-04
290033240;ccas@mairie-quimper.fr;F;2020-10-04
290035047;accueil@saint-vincent-lannouchen.fr;F;2020-10-04
290035872;direction@ch-douarnenez.fr;F;2020-10-04
290035880;hebergement@ch-douarnenez.fr;F;2020-10-04
290036847;secretariat.direction@ch-lanmeur.fr;F;2020-10-04
300002201;ehpad.barjac@coallia.org;F;2020-10-04
300002888;accueil@jsh.fr;F;2020-10-04
300003118;contact@ehpadbonnefond.fr;F;2020-10-04
300003159;secretariatdirection@hopitalpse.fr;F;2020-10-04
300004199;direction@chuzes.fr;F;2020-10-04
300010089;contact@samdo.fr;F;2020-10-04
300011004;ccas.plantiers@orange.fr;F;2020-10-04
300011764;ehpad.maison.bleue@orange.fr;F;2020-10-04
300012390;direction@chuzes.fr;F;2020-10-04
300012408;direction@chuzes.fr;F;2020-10-04
300012671;secretariat@msprotestante.fr;F;2020-10-14
300012697;direction@chuzes.fr;F;2020-10-04
300012887;secretariat@msprotestante.fr;F;2020-10-04
300012895;contact@samdopomarede.fr;F;2020-10-04
300012986;residencepetitecamargue@ymail.com;F;2020-10-04
300013018;secretariat@ehpad-meynes.fr;F;2020-10-14
300013364;contact@ch-ponteils.fr;F;2020-10-04
300013588;direction@chuzes.fr;F;2020-10-14
300014305;contact.aimargues@presence30.fr;F;2020-10-04
300014313;contact.st_quentin@presence30.fr;F;2020-10-04
300780806;accueilclairsoleil@yahoo.fr;F;2020-10-04
300780830;secretariat@maisonstroch.fr;F;2020-10-04
300781135;direction@chuzes.fr;F;2020-10-04
300781150;ehpad.lebrestalou@wanadoo.fr;F;2020-10-04
300781168;ehpad.devillas@wanadoo.fr;F;2020-10-04
300781176;mdr-leslavandines@wanadoo.fr;F;2020-10-04
300781184;info@mrsa.fr;F;2020-10-14
300781200;administratif@piedemar.fr;F;2020-10-04
300781259;accueil@fildargent.fr;F;2020-10-04
300781267;administratif@levidourle.fr;F;2020-10-04
300781457;contact@fondationrollin.fr;F;2020-10-04
300783438;direction@ch-bagnolssurceze.fr;F;2020-10-04
300783479;accueil@notredamedesmines.fr;F;2020-10-04
300783487;accueil@mrmamaison.fr;F;2020-10-04
300783495;ehpad.stvincent@ville-legrauduroi.fr;F;2020-10-04
300783503;direction-le-foyer@orange.fr;F;2020-10-04
300783511;accueil@residence-lapinede-vergeze.fr;F;2020-10-04
300783529;direction@chuzes.fr;F;2020-10-04
300783545;direction@chuzes.fr;F;2020-10-04
300783693;accueil@ndp.fr;F;2020-10-04
300783701;accueil.lescistes@fondationdiaconesses.org;F;2020-10-04
300783727;foyer.oliviers@ville-ales.fr;F;2020-10-04
300783743;ehpad.bosquet@bagnolssurceze.fr;F;2020-10-04
300783818;ccas.uzes@orange.fr;F;2020-10-04
300785037;direction-gerontologie@chu-nimes.fr;F;2020-10-04
300785045;direction.gerontologie@chu-nimes.fr;F;2020-10-04
300785094;direction@ch-bagnolssurceze.fr;F;2020-10-04
300785136;secretariatdirection@hopitalpse.fr;F;2020-10-04
300785144;direction@chuzes.fr;F;2020-10-04
300785169;hebergement@hlv.fr;F;2020-10-04
300785193;secretariat@msprotestante.fr;F;2020-10-04
300785318;residence.lesmagnans@wanadoo.fr;F;2020-10-04
300785367;secretariatdirection@hopitalpse.fr;F;2020-10-04
300785524;ccas.plantiers@orange.fr;F;2020-10-04
300785540;residence.auzonnet@wanadoo.fr;F;2020-10-04
300786118;accueil@ehpad-glycines.fr;F;2020-10-04
300786159;residence.champorus@wanadoo.fr;F;2020-10-04
300787066;contact.lezan@presence30.fr;F;2020-10-04
300787090;residence.languedoc@harmonie-santeservices.fr;F;2020-10-04
300788460;direction-oliviers@lesopalines.fr;F;2020-10-04
310001383;direction@hl-muret.fr;F;2020-10-04
310003116;residence@retraitesaintsimon.fr;F;2020-10-04
310004338;accueilchartreuse@orange.fr;F;2020-10-04
310006523;contact@leboisvert.fr;F;2020-10-04
310008859;ehpad.laprade@orange.fr;F;2020-10-04
310010798;marpa.auriac@orange.fr;F;2020-10-04
310012158;contact@ehpad-lesbuissonnets.fr;F;2020-10-04
310013438;ehpad@ehpadlesfontenelles.com;F;2020-10-04
310013529;accueil.arcenciel@groupecolisee.com;F;2020-10-04
310014618;ehpad-cadours@orange.fr;F;2020-10-14
310016159;direction@ch-muret.fr;F;2020-10-04
310016738;contact@lacompassion.fr;F;2020-10-04
310017066;mapad@plenitudestmichel.com;F;2020-10-04
310018635;residence.legue@mairie-frouzins.fr;F;2020-10-04
310018734;hopital@hopital-revel.com;F;2020-10-04
310018783;accueil@ehpad-marielehmann.fr;F;2020-10-04
310019120;contact@paul-et-lisa.com;F;2020-10-04
310019591;ehpadminimes@ccas-toulouse.fr;F;2020-10-04
310020268;residencevaldarize@res-o.fr;F;2020-10-04
310020284;direction@maison-retraite-toulouse.fr;F;2020-10-04
310020300;contact@residence-vitalite-serenite.fr;F;2020-10-04
310020797;ehpad.labastide@res-o.fr;F;2020-10-04
310021449;accueil@retraiteisatis.fr;F;2020-10-04
310022215;accueil@afc31.fr;F;2020-10-04
310022314;hopital@hopital-revel.com;F;2020-10-04
310024351;accueil@clinique-minimes.fr;F;2020-10-04
310025093;accueil@clinique-minimes.fr;F;2020-10-04
310782115;contact@ehpad-bessieres.fr;F;2020-10-04
310782123;mrboulogne@orange.fr;F;2020-10-04
310782149;ehpad.cazeres@orange.fr;F;2020-10-04
310782156;accueil.grenade@ehpad-grenade-cadours.com;F;2020-10-04
310782164;direction@ch-muret.fr;F;2020-10-04
310782172;direction.labouilhe@orange.fr;F;2020-10-04
310782198;ehpadlerepos@ccas-toulouse.fr;F;2020-10-04
310784194;ehpadfronton@mrsaintjoseph.fr;F;2020-10-04
310784202;mr.secretariat@ccasfousseret.fr;F;2020-10-04
310784244;direction.villeneuve@agepartenaires.com;F;2020-10-04
310784327;occitanie.residence@gmail.com;F;2020-10-04
310784350;secretariat@ehpad-pauloddo.fr;F;2020-10-04
310784400;secretariat.ehpadsaintvincentdepaul@res-o.fr;F;2020-10-04
310784434;contact@castel-girou.fr;F;2020-10-04
310784772;ehpadfronton@mrsaintjoseph.fr;F;2020-10-04
310784798;ehpadfrancoisedeveyrinas@ccas-toulouse.fr;F;2020-10-04
310784806;ehpadbonnefoy@ccas-toulouse.fr;F;2020-10-04
310784814;ehpaseptdeniers@ccas-toulouse.fr;F;2020-10-04
310784822;ehpadgaubert@ccas-toulouse.fr;F;2020-10-04
310785332;accueil-eracaso@wanadoo.fr;F;2020-10-04
310786298;accueil.pastourel@ehpad-bessieres.fr;F;2020-10-04
310786314;residence.loubayssens@mairie-cugnaux.fr;F;2020-10-04
310786595;contact@residence-closdeugenie.com;F;2020-10-04
310786603;residence.autonomie@mairie-ramonville.fr;F;2020-10-04
310787320;pradine.direction@arpavie.fr;F;2020-10-04
310788021;direction@hopitauxdeluchon.fr;F;2020-10-04
310788658;accueil.ehpadmontroyal@orange.fr;F;2020-10-04
310790431;hopital@hopital-revel.com;F;2020-10-06
310791405;contact@retraitemaisonneuve.com;F;2020-10-04
310792056;direction@ch-saintgaudens.fr;F;2020-10-04
310792080;hopital@hopital-revel.com;F;2020-10-04
310792148;ehpad-lepastel@orange.fr;F;2020-10-04
310792353;direction@ch-saintgaudens.fr;F;2020-10-04
310792494;ehpad.lalbergue@res-o.fr;F;2020-10-04
310793047;accueil@lesjardinsderambam.fr;F;2020-10-04
310793328;secretariat.flourens@orpea.net;F;2020-10-04
310794631;ehpad.sainte-monique@anras.fr;F;2020-10-04
310794854;marpa.aurignac@orange.fr;F;2020-10-04
310797790;stplancardmarpa@gmail.com;F;2020-10-29
320000698;residence.lezian@orange.fr;F;2020-10-04
320001092;hopital@hopital-nogaro.fr;F;2020-10-04
320001399;contact@lesjardinsdagape.com;F;2020-10-04
320002199;direction@ehpad-valdegers.fr;F;2020-10-04
320002298;administration.villacastera@korian.fr;F;2020-10-04
320003254;contact@residence-alliance.com;F;2020-10-04
320780463;accueil@ehpad-elusa.fr;F;2020-10-04
320780489;secretariat@hopital-lombez.fr;F;2020-10-04
320780505;contact.ehpad@cantoloup-lavallee.fr;F;2020-10-04
320782097;secretariat@hopital-gimont.fr;F;2020-10-04
320782170;ehpad.laroseraie32@ccass-sbe.org;F;2020-10-04
320782238;residence-beladour@orange.fr;F;2020-10-04
320782782;direction@epslomagne.fr;F;2020-10-04
320782915;direction@ch-condom.com;F;2020-10-04
320782972;direction@epslomagne.fr;F;2020-10-04
320783137;direction@epslomagne.fr;F;2020-10-04
320783145;secretariat@hopital-gimont.fr;F;2020-10-04
320783152;secretariat@hopital-lombez.fr;F;2020-10-04
320783160;accueil@hopital-mauvezin.fr;F;2020-10-04
320783178;contact@ch-mirande.fr;F;2020-10-04
320783186;hopital@hopital-nogaro.fr;F;2020-10-04
320783194;contact@hopital-vicfezensac.fr;F;2020-10-04
320783301;residencelagrange@coeur-dastarac.fr;F;2020-10-04
320784036;secretariat@hopital-lombez.fr;F;2020-10-04
320784606;ehpad.st-dominique@anras.fr;F;2020-10-04
320784952;secretariat@hopital-gimont.fr;F;2020-10-04
320785025;ehpadlehouga@orange.fr;F;2020-10-04
320785363;mapa32310@orange.fr;F;2020-10-04
330005182;direction@csmr-podensac.fr;F;2020-10-04
330007543;ehpad.marysebastie@mairie-bordeaux.fr;F;2020-10-14
330007972;ehpa-loreeduparc@foyersdesaines.fr;F;2020-10-04
330014648;marpacantelanne@orange.fr;F;2020-10-04
330015728;ehpad@stseurinsurlisle.com;F;2020-10-04
330018169;ehpad.stsymphorien@orange.fr;F;2020-10-04
330020678;ehpad-leboisduloret@foyersdesaines.fr;F;2020-10-04
330020819;contact@lemoulindejeanne.fr;F;2020-10-04
330020918;accueil.carbonblanc@orpea.net;F;2020-10-04
330021049;ehpadmemoiredesailes@aeis.fr;F;2020-10-04
330023938;sauveterre.mairie@wanadoo.fr;F;2020-10-04
330025008;ehpad-lesbaccharis@foyersdesaines.fr;F;2020-10-04
330026279;administration.platane-grand-parc@lesdoyennes.fr;F;2020-10-04
330026568;contact@lavalleeduroy.fr;F;2020-10-04
330027798;lamairie@saintsulpicedefaleyrens.com;F;2020-10-04
330027988;ccas@mairie-vayres.fr;F;2020-10-04
330029018;accueil.andernos@orpea.net;F;2020-10-04
330035619;contact@residence-du-tertre.com;F;2020-10-04
330051988;accueil.talanssa@lna-sante.com;F;2020-10-04
330054412;residenceautonomie@mairie-bordeaux.fr;F;2020-10-04
330054503;secretariat@residence-gallevent.fr;F;2020-10-04
330055799;accueil.ehpad@ch-libourne.fr;F;2020-10-04
330056748;contact.leysotte@lna-sante.com;F;2020-10-04
330058108;accueil.ehpad@ch-libourne.fr;F;2020-10-04
330060401;residencepleinciel@philogeris.com;F;2020-10-04
330781428;ehpad@terre-negre.fr;F;2020-10-04
330781766;direction@csmr-podensac.fr;F;2020-10-04
330781857;direction@ehpadlatourdupin.com;F;2020-10-04
330782525;accueil@meduli.com;F;2020-10-04
330782533;accueil@residence-johntalbot.fr;F;2020-10-04
330782566;direction@lesbalconsdetivoli.com;F;2020-10-04
330782574;jardin.provinces.administration@orange.fr;F;2020-10-04
330782632;secretariat@fondation-roux.com;F;2020-10-04
330782640;contact@ehpad-compostelle.org;F;2020-10-04
330782699;ccas@ville-gradignan.fr;F;2020-10-04
330782723;direction@bon-secours.fr;F;2020-10-04
330782749;contact@maisonprotestante.fr;F;2020-10-04
330782806;direction.fondation-dubois@wanadoo.fr;F;2020-10-04
330782814;direction-saintegermaine@foyersdesaines.fr;F;2020-10-04
330782830;ehpad-levigean@foyersdesaines.fr;F;2020-10-04
330782848;secretariat@bellecroix.fr;F;2020-10-04
330782863;ehpad.lesfontainesdemonjous@probtp.com;F;2020-10-04
330783333;accueil@residence-seguin.fr;F;2020-10-04
330783481;foyercombattant@foyerblaye.fr;F;2020-10-04
330783580;accueil.lebourgailh@lna-sante.com;F;2020-10-04
330785114;accueil.ehpad@ch-libourne.fr;F;2020-10-04
330785130;ehpad-lareole@ch-sudgironde.fr;F;2020-10-04
330785429;contact@logevie.fr;F;2020-10-04
330785452;residenceautonomie@mairie-bordeaux.fr;F;2020-10-14
330785478;residenceautonomie@mairie-bordeaux.fr;F;2020-10-14
330785486;residenceautonomie@mairie-bordeaux.fr;F;2020-10-06
330785494;residenceautonomie@mairie-bordeaux.fr;F;2020-10-04
330785536;residenceautonomie@mairie-bordeaux.fr;F;2020-10-14
330785551;residenceautonomie@mairie-bordeaux.fr;F;2020-10-06
330785569;residenceautonomie@mairie-bordeaux.fr;F;2020-10-14
330785577;contact@logevie.fr;F;2020-10-04
330785585;contact@logevie.fr;F;2020-10-04
330785643;contact@logevie.fr;F;2020-10-04
330785684;contact@logevie.fr;F;2020-10-04
330785692;residenceautonomie@mairie-bordeaux.fr;F;2020-10-14
330785700;contact@logevie.fr;F;2020-10-04
330785718;contact@logevie.fr;F;2020-10-04
330785726;contact@logevie.fr;F;2020-10-04
330785734;contact@logevie.fr;F;2020-10-04
330785742;contact@logevie.fr;F;2020-10-04
330785775;contact@logevie.fr;F;2020-10-04
330785783;contact@logevie.fr;F;2020-10-04
330785791;ehpa@pineuilh.fr;F;2020-10-04
330785809;contact@logevie.fr;F;2020-10-04
330786005;direction-saintgeorges@foyersdesaines.fr;F;2020-10-04
330786112;contact@logevie.fr;F;2020-10-04
330786161;ehpadares@mgen.fr;F;2020-10-04
330786211;accueil@mrprechac.fr;F;2020-10-04
330786229;ehpad.lesmuriers@orange.fr;F;2020-10-04
330786278;administration.villagabriel@korian.fr;F;2020-10-04
330789942;contact@eneal.fr;F;2020-10-04
330789959;residenceautonomie@mairie-bordeaux.fr;F;2020-10-06
330789967;residenceautonomie@mairie-bordeaux.fr;F;2020-10-14
330789975;residenceautonomie@mairie-bordeaux.fr;F;2020-10-14
330789983;residenceautonomie@mairie-bordeaux.fr;F;2020-10-14
330790007;contact@eneal.fr;F;2020-10-04
330790031;secretariat.direction@cmcwallerstein-ares.com;F;2020-10-04
330790916;contact@logevie.fr;F;2020-10-04
330790940;ehpa@mairie-libourne.fr;F;2020-10-04
330790957;info@mairie-ludon-medoc.fr;F;2020-10-04
330790965;contact@logevie.fr;F;2020-10-04
330790981;residenceautonomie@mairie-bordeaux.fr;F;2020-10-14
330791013;contact@logevie.fr;F;2020-10-04
330791021;ehpad.labergedulac@probtp.com;F;2020-10-04
330791054;contact@leclosdesacacias.fr;F;2020-10-04
330791153;contact@villa-presentine.fr;F;2020-10-04
330792615;direction@ppms-monsegur.fr;F;2020-10-04
330792631;direction@ch-bazas.fr;F;2020-10-04
330792649;secretariat.direction@ch-stefoy.fr;F;2020-10-04
330792656;direction@ch-sudgironde.fr;F;2020-10-04
330793357;contact@mairie-soulac.fr;F;2020-10-04
330793373;mairie@lareole.fr;F;2020-10-04
330793399;mairie@mairie-latresne.fr;F;2020-10-04
330795337;residenceautonomie@mairie-bordeaux.fr;F;2020-10-14
330796293;secretariat.ehpadlarrieu@ch-arcachon.fr;F;2020-10-04
330796376;residenceaquitaine@fbocke.fr;F;2020-10-04
330796772;secretariat@mairiedecadillac.fr;F;2020-10-04
330796822;contact@logevie.fr;F;2020-10-04
330796848;ccas@mairie-pessac.fr;F;2020-10-04
330796855;ccas@ville-ares.fr;F;2020-10-04
330796889;directionccas@ville-creon.fr;F;2020-10-04
330796905;ccas@mairie-cestas.fr;F;2020-10-04
330797168;residence.autonomie@cc-estuaire.fr;F;2020-10-04
330797259;contact@castetsendorthe.fr;F;2020-10-04
330797267;ccas@mairie-cestas.fr;F;2020-10-04
330797283;ccas@eysines.fr;F;2020-10-04
330797341;ccas@villemios.fr;F;2020-10-04
330797390;ccas@st-pierre-daurillac.fr;F;2020-10-04
330797457;mairie@sauternes.com;F;2020-10-04
330797929;residenceaudenge@free.fr;F;2020-10-04
330797952;administration.le-chalet@korian.fr;F;2020-10-04
330798232;mdrleserables@wanadoo.fr;F;2020-10-04
330798240;contact.larenaissance@lna-sante.com;F;2020-10-04
330798273;info@clairierebelair.fr;F;2020-10-04
330798281;accueil.staubindemedoc@groupecolisee.com;F;2020-10-04
330798471;contact@terrassesdebeausejour.com;F;2020-10-04
330798554;direction@ehpad-grignols.fr;F;2020-10-04
330798646;contact@residence-la-savane.com;F;2020-10-04
330798679;direction.lesrosesdubassin@groupe-omega.fr;F;2020-10-04
330798711;direction@ehpad-illats.fr;F;2020-10-04
330798794;direction.soulac@groupecolisee.com;F;2020-10-04
330798935;secretariat.direction@ch-stefoy.fr;F;2020-10-04
330799040;contact@residencedubourg.fr;F;2020-10-04
330799057;contact@ehpadpaulclaudel.com;F;2020-10-04
330799297;mapad.bordeaux@croix-rouge.fr;F;2020-10-04
330799404;accueilbordeaux@logea.asso.fr;F;2020-10-04
330799461;residence.abelia@groupe-mieuxvivre.fr;F;2020-10-04
330799792;residence.lachartreuse@groupe-mieuxvivre.fr;F;2020-10-04
330799925;accueil.lalandedefronsac@groupecolisee.com;F;2020-10-04
330800087;direction@residence-lescharmilles.fr;F;2020-10-04
330802737;ccas@vendaysmontalivet.com;F;2020-10-04
330803669;direction@fontaudin.fr;F;2020-10-04
330804394;direction@ch-bazas.fr;F;2020-10-04
340006816;ehpad.orthus@orange.fr;F;2020-10-04
340006949;poesie.direction@arpavie.fr;F;2020-10-04
340008192;ehpad@villeneuve-les-beziers.fr;F;2020-10-04
340011345;administration.lacolombe@korian.fr;F;2020-10-04
340011352;accueilmuscates@mr-frontignan.fr;F;2020-10-04
340011477;secretariat.ehpad@bessan.fr;F;2020-10-04
340014190;ehpad-mathildelaurent@orange.fr;F;2020-10-04
340014240;asteries.direction@arpavie.fr;F;2020-10-04
340016690;ehpad@jardindadoyra.fr;F;2020-10-04
340017151;ehpad.laroseliere@mfgs.fr;F;2020-10-04
340017359;ehpad.nissan34@croix-rouge.fr;F;2020-10-04
340017508;ehpad.gerardsoulatges@mfgs.fr;F;2020-10-04
340017516;secretariat.lesjardins@capsante.fr;F;2020-10-04
340017672;accueil.ehpad@adages.net;F;2020-10-04
340017763;ehpad@ccas-beziers.fr;F;2020-10-04
340017797;secretariat.lamadelon@capsante.fr;F;2020-10-04
340018019;contact@residence-lesjardinsdebrescou.com;F;2020-10-04
340018159;contact@lesjardindaniane.fr;F;2020-10-04
340019512;direction.impressa@mutuelle-mbv.fr;F;2020-10-04
340021419;ehpad2@ccas-beziers.fr;F;2020-10-04
340023415;accueil@les-jardins-deulalie.fr;F;2020-10-04
340023423;contact@lamesange.fr;F;2020-10-04
340781426;mr.cazouls@wanadoo.fr;F;2020-10-04
340781434;accueilstjacques@mr-frontignan.fr;F;2020-10-04
340781483;info@foyerduromarin.com;F;2020-10-04
340782697;direction@hopital-lunel.fr;F;2020-10-04
340783760;ehpad-les-muriers@castelnau-le-lez.fr;F;2020-10-04
340783828;direction.treilles@mutuelle-mbv.fr;F;2020-10-04
340783877;foyer.ste.amelie@orange.fr;F;2020-10-04
340783901;contact.acacias@philogeris.com;F;2020-10-04
340783935;contact@mrp34.org;F;2020-10-04
340784032;ehpadvillamarie@gmail.com;F;2020-10-04
340784040;ehpad.jeannedelanoue@orange.fr;F;2020-10-04
340784503;contact@ehpad-oustal.fr;F;2020-10-04
340784610;mdr.moulines@wanadoo.fr;F;2020-10-04
340784628;garrigues.direction@gmail.com;F;2020-10-04
340784636;ehpad.farigoule@orange.fr;F;2020-10-04
340784768;contact@les-aiguerelles.fr;F;2020-10-04
340785120;contact@chateaularoche.fr;F;2020-10-04
340785195;ehpad@ville-gignac.com;F;2020-10-04
340786524;reception.lapompignane@korian.fr;F;2020-10-04
340786581;ehpad@ccas-servian.fr;F;2020-10-04
340786680;contact@lamesange.fr;F;2020-10-04
340786797;contact@mdryvescouzy.com;F;2020-10-04
340787472;accueilmireille@gmail.com;F;2020-10-04
340787530;direction.lestilleuls@orange.fr;F;2020-10-04
340787688;direction@mr-frontignan.fr;F;2020-10-04
340787894;secretariat@glycines.fr;F;2020-10-04
340787902;tremont.direction@arpavie.fr;F;2020-10-04
340787910;ehpad@ville-nezignan.fr;F;2020-10-04
340788587;contact@hopital-bedarieux.fr;F;2020-10-04
340788595;hopital@hl-bedarieux.com;F;2020-10-04
340788645;direction@hopital-clermont-lherault.fr;F;2020-10-04
340788702;direction@hopital-lunel.fr;F;2020-10-04
340788710;hopital@hopital-stpons.com;F;2020-10-04
340789205;contact@ehpad-capestang.fr;F;2020-10-04
340789213;residenceretraiterenaissance@wanadoo.fr;F;2020-10-04
340789221;residenceleminervois@gmail.com;F;2020-10-04
340789239;info@jardinsdeflore.fr;F;2020-10-04
340789379;secretariat@jardindesophia.com;F;2020-10-04
340789718;contact@feuillantines.fr;F;2020-10-04
340789742;secretariat@laresidentielle.fr;F;2020-10-04
340790187;direction.raoulboubal@gecoh.fr;F;2020-10-04
340790211;direction.lesfloreales@capsante.fr;F;2020-10-15
340791961;ehpad.athena@languedoc-mutualite.fr;F;2020-10-04
340796333;contact@acppa.fr;F;2020-10-04
350000253;admissions@mr-fv-tronchet.fr;F;2020-10-04
350002341;direction@hopital-laguerchedebretagne.fr;F;2020-10-14
350002358;accueil@ehpad-bazouges.fr;F;2020-10-04
350002366;mr.labouexiere@wanadoo.fr;F;2020-10-04
350002374;ehpad.chateaugiron@lesjardinsducastel.com;F;2020-10-04
350002382;residencedelyze@wanadoo.fr;F;2020-10-04
350002390;contact@residence-abbaye.fr;F;2020-10-04
350002408;accueil@residencedeletang.fr;F;2020-10-04
350002424;mr.minihic@wanadoo.fr;F;2020-10-04
350002440;contact@residencelesacacias-stgeorges.fr;F;2020-10-04
350002473;direction.kerjoseph@orange.fr;F;2020-10-04
350002481;mdr.retiers@libertysurf.fr;F;2020-10-04
350002499;contact@ehpad-becherel-romille.fr;F;2020-10-04
350002507;residence@residencelesvergers.com;F;2020-10-04
350002937;secretariat.direction@clhsaintjoseph.com;F;2020-10-04
350005054;accueil.mr.livre@wanadoo.fr;F;2020-10-04
350005229;accueil@nd-chenes.fr;F;2020-10-04
350005252;accueil@maisonsaintcyr.fr;F;2020-10-04
350005294;accueil@ehpadleclosdorriere.fr;F;2020-10-04
350005344;accueil@maisonsaintmichel.fr;F;2020-10-04
350005369;accueil@mrlp.org;F;2020-10-04
350005377;contact@ehpad-tinteniac.fr;F;2020-10-04
350005385;accueil@lasaintefamille.org;F;2020-10-04
350005419;contact@residencesaintemarie.fr;F;2020-10-04
350005427;residence@ndldomalain.fr;F;2020-10-04
350005476;direction.residence-perebrottier@fces.fr;F;2020-10-04
350005542;ehpad.saint-joseph@laposte.net;F;2020-10-04
350006383;residence.bel.air@wanadoo.fr;F;2020-10-04
350006391;contact@residence-albert-aubry.com;F;2020-10-04
350006433;direction@ch-vitre.fr;F;2020-10-04
350006615;foyer-logement@combourg.com;F;2020-10-04
350006623;secretariat.paimpont@orange.fr;F;2020-10-04
350006631;hopital@ch-cancale.fr;F;2020-10-04
350006714;foyer.logement@ville-dinard.fr;F;2020-10-04
350006813;direction@ch-stmeen.fr;F;2020-10-04
350006821;direction@ch-montfort.fr;F;2020-10-04
350006896;foyer.montfort@wanadoo.fr;F;2020-10-04
350006979;accueil.ehpad.goven@orange.fr;F;2020-10-04
350007019;foyerlogement.stbriac@wanadoo.fr;F;2020-10-04
350007266;accueil@residence-laparentele-dol.bzh;F;2020-10-04
350007894;accueil-ehpad-maxent@orange.fr;F;2020-10-04
350009163;accueil@residenceduparmenier.fr;F;2020-10-04
350012100;ccas.chateauneuf@wanadoo.fr;F;2020-10-04
350013181;residence.lesbruyeres@stmeen.fr;F;2020-10-04
350013249;direction@ch-montfort.fr;F;2020-10-04
350013447;accueil@leschenes-saintmalo.fr;F;2020-10-04
350013629;direction.hopital@ch-stmalo.fr;F;2020-10-04
350013637;direction.hopital@ch-stmalo.fr;F;2020-10-04
350013645;contact@chmarchesdebretagne.fr;F;2020-10-04
350013652;direction@ch-fougeres.fr;F;2020-10-04
350013694;direction@hopital-laguerchedebretagne.fr;F;2020-10-04
350013710;direction@chmb.fr;F;2020-10-04
350013728;direction@ch-vitre.fr;F;2020-10-04
350023677;residence@betton.fr;F;2020-10-04
350024337;direction.chenes@ugecam-brpl.cnamts.fr;F;2020-10-04
350028668;direction@ch-fougeres.fr;F;2020-10-04
350028783;ehpad@ems-cesson-sevigne.fr;F;2020-10-04
350028791;residencelatremoille@ccasvitre.fr;F;2020-10-04
350028817;marpa.parce.direction@orange.fr;F;2020-10-04
350028833;residence.la.crepiniere@wanadoo.fr;F;2020-10-04
350028841;residence.st.conwoion@orange.fr;F;2020-10-04
350028858;direction.nympheas@lenobleage.fr;F;2020-10-04
350030292;accueil@baguer-morvan.hstv.fr;F;2020-10-04
350030367;residence-bellevue3@wanadoo.fr;F;2020-10-04
350030540;accueil@larablais.fr;F;2020-10-04
350030565;contact@residence-chateau.fr;F;2020-10-04
350030573;contact@les-roseraies.fr;F;2020-10-04
350030987;mapa.iffendic@wanadoo.fr;F;2020-10-04
350031043;letrehelu.ccas.guichen@wanadoo.fr;F;2020-10-04
350031084;direction@ehpadchartres35.fr;F;2020-10-04
350031613;secretariat.direction@ch-redon.fr;F;2020-10-04
350031639;secretariat.ehpad@acigne.fr;F;2020-10-04
350031654;marpa@guipry-messac.bzh;F;2020-10-04
350031795;direction@bain.hstv.fr;F;2020-10-04
350032116;mapastbroladre@orange.fr;F;2020-10-04
350032231;infos@hopgf.com;F;2020-10-04
350032447;contact@ais35.fr;F;2020-10-04
350032611;direction.ehpad@parigne.org;F;2020-10-04
350032678;ehpad.gael@coallia.org;F;2020-10-04
350032694;accueil.residence@pole-sthelier.com;F;2020-10-04
350033890;residencelecheminvert@wanadoo.fr;F;2020-10-04
350039475;mapa.saintpierreplesguen@wanadoo.fr;F;2020-10-04
350039889;gestion.rennes@rennes-psdp.com;F;2020-10-04
350040051;accueil-secretariat.ehpad@assadredon.fr;F;2020-10-04
350040069;ehpad.montreuil@orange.fr;F;2020-10-04
350041315;direction@residencedubignon.fr;F;2020-10-04
350042479;accueil@lesrondines.fr;F;2020-10-15
350043188;contact@mvv35.fr;F;2020-10-04
350044434;accueil.lanoe@mfiv.fr;F;2020-10-04
350045290;accueil@stlouis.hstv.fr;F;2020-10-04
350045308;accueil.janze@admr35.org;F;2020-10-04
350046025;accueiljourkerelys@argo-asso.com;F;2020-10-04
350046108;direction@edilys.fr;F;2020-10-04
350046215;contact@assaredon.fr;F;2020-10-04
350046777;secretariat.direction@clhsaintjoseph.com;F;2020-10-04
350047791;foyerlogement.stbriac@wanadoo.fr;F;2020-10-04
350049524;direction.hopital@ch-stmalo.fr;F;2020-10-04
350049664;ehpad-fleurdesel@bain.hstv.fr;F;2020-10-04
350049797;admission@residence-abbaye.fr;F;2020-10-04
350049805;accueildejour.bain@admr35.org;F;2020-10-04
350050555;residence@residencelesvergers.com;F;2020-10-04
350051207;contact@hstv.fr;F;2020-10-04
350052155;accueil@leschenes-saintmalo.fr;F;2020-10-04
350052171;accueil@immaculee35.fr;F;2020-10-04
360002026;mr.mezieres@orange.fr;F;2020-10-04
360002034;mdrstgaultier@wanadoo.fr;F;2020-10-04
360002141;association.castel@wanadoo.fr;F;2020-10-04
360002174;mdr.chabris@wanadoo.fr;F;2020-10-04
360003313;direction.ehpad.clion@wanadoo.fr;F;2020-10-04
360003461;residenceisabelle@chateauroux-metropole.fr;F;2020-10-04
360004626;hopital@ch-chatillon.fr;F;2020-10-04
360004634;hopital@ch-chatillon.fr;F;2020-10-04
360004675;accueil@ch-buzancais.fr;F;2020-10-04
360005110;hopital@hl-levroux.fr;F;2020-10-04
360005169;residencelesrives@chateauroux-metropole.fr;F;2020-10-04
360005888;marpasaintaout36@orange.fr;F;2020-10-04
360006126;administration.hameau-eguzon@korian.fr;F;2020-10-04
360006175;ehpadlavaquine@blanchedefontarce.fr;F;2020-10-04
360007009;ehpad.saint-jean@ville-chateauroux.fr;F;2020-10-04
360007074;residence3roues@gmail.com;F;2020-10-04
360007371;marpaardentes.36@orange.fr;F;2020-10-04
360007447;marpa.martizay@gmail.com;F;2020-10-04
360008122;hopital@hl-levroux.fr;F;2020-10-04
360008155;marparoussines@gmail.com;F;2020-10-04
370000507;direction@eslm.fr;F;2020-10-04
370000556;direction@ch-chinon.fr;F;2020-10-04
370000598;contact@ehpad-abilly.fr;F;2020-10-04
370000622;accueilcourtille@ehpad-blere.fr;F;2020-10-04
370000648;ehpad.chateaulavalliere@wanadoo.fr;F;2020-10-04
370000663;contact@ehpad-ligueil.fr;F;2020-10-04
370000671;direction@chluynes.fr;F;2020-10-04
370000689;accueil@ehpad-labourdaisiere.fr;F;2020-10-04
370000697;contact@ehpadpreuillysurclaise.fr;F;2020-10-04
370002388;accueil.ehpadlangeais@gmail.com;F;2020-10-04
370002461;residence.maisonblanche@korian.fr;F;2020-10-04
370002511;direction@ch-chinon.fr;F;2020-10-04
370004228;contact@chicacr.fr;F;2020-10-04
370005159;admission@prieure-stlouans.fr;F;2020-10-04
370005209;residence.tours@fondationbellan.org;F;2020-10-04
370005217;direction@manoirduverger.fr;F;2020-10-04
370005241;foyer-logement.chambray@wanadoo.fr;F;2020-10-04
370005357;contact@ccas-tours.fr;F;2020-10-04
370005365;contact@ccas-tours.fr;F;2020-10-04
370005373;contact@ccas-tours.fr;F;2020-10-04
370005399;contact@ccas-tours.fr;F;2020-10-04
370005407;contact@ccas-tours.fr;F;2020-10-04
370008419;contact@ccas-tours.fr;F;2020-10-15
370008468;accueil.residenceduparc@orpea.net;F;2020-10-04
370010498;accueil.eleonore@lna-sante.com;F;2020-10-04
370011348;accueil-ehpad.tours@croix-rouge.fr;F;2020-10-04
370011553;contact@les-jardins-du-lys.fr;F;2020-10-04
370013302;ehpa.tours@croix-rouge.fr;F;2020-10-04
370013559;accueillescapucines@gmail.com;F;2020-10-04
370013575;accueil-marpa-2aires@orange.fr;F;2020-10-04
370013583;contact@ccas-tours.fr;F;2020-10-04
370100513;mdrvilleloin@wanadoo.fr;F;2020-10-04
370101347;ehpad.celle-guenand@wanadoo.fr;F;2020-10-04
370101362;admissions@ehpad-ilebouchard.fr;F;2020-10-04
370103012;reception.lamenardiere@korian.fr;F;2020-10-04
370103160;residence.choisille@wanadoo.fr;F;2020-10-04
370103368;contact@ccas-tours.fr;F;2020-10-15
370103400;direction@eslm.fr;F;2020-10-04
370103889;contact@lumieresdautomne.fr;F;2020-10-04
370103954;lemaine.direction@bbox.fr;F;2020-10-04
370104085;contact@residence-du-lys.com;F;2020-10-04
370104093;residencedescoutures@wanadoo.fr;F;2020-10-04
370104234;residencelescharmes@wanadoo.fr;F;2020-10-04
370104549;marpa.leboisdesplantes@orange.fr;F;2020-10-04
370104606;contact@ccas-tours.fr;F;2020-10-15
370104648;marpa0268@orange.fr;F;2020-10-04
370104762;marpa-truyes@hotmail.fr;F;2020-10-04
370104770;administration.leplessis@korian.fr;F;2020-10-04
370104796;foyer.avoine@wanadoo.fr;F;2020-10-04
370104887;contact@ccas-tours.fr;F;2020-10-15
380002998;admin.ehpadmens@orange.fr;F;2020-10-04
380010058;contact@lacheneraie38.fr;F;2020-10-04
380012948;accueilstgeorges@mutualiteisere.org;F;2020-10-04
380013409;accueil.cascades@assomarcsimian.fr;F;2020-10-04
380013532;ehpad.closbesson@ville-vif.fr;F;2020-10-04
380016311;accueil-eybens@mutualiteisere.org;F;2020-10-04
380019323;residence@mairie-domene.fr;F;2020-10-04
380019786;direction@ch-vienne.fr;F;2020-10-04
380021063;foyer-cantedor@orange.fr;F;2020-10-04
380781518;admissions@ehpad-voreppe.fr;F;2020-10-04
380781575;administration@mr-bellefontaine.fr;F;2020-10-04
380781583;accueil@ehpad-gdlemps.fr;F;2020-10-04
380781609;mrvillette@hotmail.fr;F;2020-10-04
380781617;contact@ehpadbayard.fr;F;2020-10-04
380781625;administration@oisans-retraite.com;F;2020-10-04
380781641;secretariat@ehpadlestournelles.fr;F;2020-10-15
380781658;ehpadsaintjean38@gmail.com;F;2020-10-04
380781674;ehpad.moirans@wanadoo.fr;F;2020-10-04
380781682;contact@residencejeannedechantal.fr;F;2020-10-04
380782664;accueil@ehpad-vizille.fr;F;2020-10-04
380784470;direction@ch-lamure.fr;F;2020-10-04
380784777;direction@chstmarcellin.eu;F;2020-10-14
380784991;mdr.corps@orange.fr;F;2020-10-04
380785030;ch-rives@ch-rives.fr;F;2020-10-04
380785048;secretariat.abbaye@arbresdevie.org;F;2020-10-04
380785055;contact@lacheneraie38.fr;F;2020-10-04
380785071;accueil@orsac-sevigne.fr;F;2020-10-04
380785097;accueilsolambres@mutualiteisere.org;F;2020-10-04
380785113;secretariat@maisondubonpasteur.fr;F;2020-10-15
380785121;direction@nddr.fr;F;2020-10-04
380785139;contact@lacheneraie38.fr;F;2020-10-04
380785147;accueil@residencevictorhugo.fr;F;2020-10-04
380785238;accueil.providence@assomarcsimian.fr;F;2020-10-04
380785253;accueil.stgermain@habitat-humanisme.org;F;2020-10-04
380785535;residence@gieres.fr;F;2020-10-04
380785592;direction.foyerpervenches@collines.org;F;2020-10-04
380785618;contact@les-coralies.fr;F;2020-10-04
380785808;accueil.stjean@assomarcsimian.fr;F;2020-10-04
380786533;ehpad.lucie-pellat@ccas-grenoble.fr;F;2020-10-04
380786590;ehpad.saint-bruno@ccas-grenoble.fr;F;2020-10-04
380786640;residence.du.parc38@orange.fr;F;2020-10-04
380786707;residence.charminelle@ville-voreppe.fr;F;2020-10-04
380786988;bon-accueil@wanadoo.fr;F;2020-10-04
380789958;accueil.valmarie@habitat-humanisme.org;F;2020-10-04
380790030;levercorsdirection@vinay.fr;F;2020-10-04
380794172;ehpad.narvik@ccas-grenoble.fr;F;2020-10-04
380794503;direction@ch-lamure.fr;F;2020-10-04
380794545;direction@chstmarcellin.eu;F;2020-10-14
380794586;direction@ehpad-vinay.fr;F;2020-10-04
380794685;direction@hlsgv.fr;F;2020-10-04
380794727;direction@hl-beaurepaire.fr;F;2020-10-04
380794743;direction@chpb.fr;F;2020-10-04
380794925;gerontologie@ch-vienne.fr;F;2020-10-04
380795468;ehpadadmin@ville-pontdeclaix.fr;F;2020-10-04
380795864;secretariat.reynies@arbresdevie.org;F;2020-10-04
380795872;secretariat.beviere@arbresdevie.org;F;2020-10-04
380799817;ccas@mairie-seyssins.fr;F;2020-10-04
380800722;foyerlogement@lesavenieres.fr;F;2020-10-04
380801159;ccas@ville-claix.fr;F;2020-10-04
380802595;ehpad@le-gresivaudan.fr;F;2020-10-04
380802611;marpalarevola@orange.fr;F;2020-10-04
380802728;direction@ch-voiron.fr;F;2020-10-04
380803148;direction@residencelespivoles.fr;F;2020-10-04
380803890;arche.secretariat@mutualiteisere.org;F;2020-10-15
380803916;direction@emsleperron.eu;F;2020-10-04
380804740;direction.residence-larcenciel@fces.fr;F;2020-10-04
390004745;residence-moulin@jurasud.net;F;2020-10-04
390005148;ehpad.secretariat@chsjura.fr;F;2020-10-04
390005189;ehpad.secretariat@chsjura.fr;F;2020-10-04
390006138;residencedeslacs@mutualite39.fr;F;2020-10-04
390006195;accueil.ehpadfrancoisdassise@gmail.com;F;2020-10-04
390006336;secretariat@ch-dole.fr;F;2020-10-04
390780096;ehpad.lachatelaine@lonslesaunier.fr;F;2020-10-04
390782225;direction@ch-salinslesbains.fr;F;2020-10-04
390782241;ch-morez@ch-morez.fr;F;2020-10-04
390782381;foyer@lagrandvalliere.fr;F;2020-10-04
390782407;residence.valdamour@dole.org;F;2020-10-04
390782449;contact@ehpad-sainte-marthe.fr;F;2020-10-04
390782480;direction@hopital-poligny.fr;F;2020-10-04
390783942;ehpad.secretariat@chsjura.fr;F;2020-10-04
390783959;direction@ch-champagnole.fr;F;2020-10-04
390784080;direction.orgelet@chi.orja.fr;F;2020-10-04
390784114;direction@hopital-poligny.fr;F;2020-10-04
390784163;residence.paters@dole.org;F;2020-10-04
390784791;foyer.logement@ccorgelet.com;F;2020-10-04
390785186;ehpad.edilys@lonslesaunier.fr;F;2020-10-04
390785434;residencedeslacs@mutualite-39.fr;F;2020-10-04
400006607;accueil@pgps.fr;F;2020-10-04
400009098;direction.ehpadrion@pays-tarusate.fr;F;2020-10-04
400009908;direction@ch-st-sever.fr;F;2020-10-04
400010278;direction@ch-mdm.fr;F;2020-10-04
400010518;secretariat@ehpad.hossegor.fr;F;2020-10-04
400010708;ehpadlesbalcons@orange.fr;F;2020-10-04
400010799;ehpad.paticat@orange.fr;F;2020-10-04
400010898;direction5rivieres@pays-tarusate.fr;F;2020-10-04
400011102;secretariat@ehpad-ccas-seignosse.fr;F;2020-10-04
400011334;mairie.compta@sanguinet.fr;F;2020-10-04
400013983;ehpadgastonlarrieu@dax.fr;F;2020-10-04
400780706;contact@ehpadtartas.fr;F;2020-10-04
400780714;administration@ehpadbiscarrosse.fr;F;2020-10-04
400780722;contact@ehpad-gabarret.fr;F;2020-10-04
400780755;contact@ehpad-landes.fr;F;2020-10-04
400780763;secretariat@ehpadluxey.fr;F;2020-10-04
400780771;accueil@pgps.fr;F;2020-10-04
400780789;accueil@ehpadmugron.fr;F;2020-10-04
400780805;contact@ehpad-landes.fr;F;2020-10-04
400780839;direction@ehpadvilleneuve.fr;F;2020-10-04
400780847;ehpad.lesgourgues@orange.fr;F;2020-10-04
400780854;mdrlabeyrie.pontonx@wanadoo.fr;F;2020-10-04
400780938;direction@ch-mdm.fr;F;2020-10-04
400780995;ehpad.sabres@ciascoeurhautelande.fr;F;2020-10-15
400781050;mimizan.retraite@wanadoo.fr;F;2020-10-04
400781217;accueil.lamartiniere@hospitalieres.org;F;2020-10-04
400781225;accueil.loustaou@orange.fr;F;2020-10-04
400781233;ehpad.saintsever@chalossetursan.fr;F;2020-10-04
400781258;accueil.ehpadsoustons@gmail.com;F;2020-10-04
400781282;ehpadsaintpierre@cias-montdemarsan-agglo.fr;F;2020-10-04
400782827;ccashagetmau@ccashagetmau.fr;F;2020-10-04
400782967;ehpad@castets.fr;F;2020-10-04
400783346;contact@ciasairesuradour.fr;F;2020-10-04
400784088;ehpad@orthe-arrigans.fr;F;2020-10-04
400785689;ehpad40gamarde@orange.fr;F;2020-10-04
400785820;mr.samadet@wanadoo.fr;F;2020-10-04
400787362;direction@ch-st-sever.fr;F;2020-10-04
400787396;ehpadmarsan@cias-montdemarsan-agglo.fr;F;2020-10-04
400787735;ehpad40montfort@orange.fr;F;2020-10-04
400789780;accueil.ehpad@capbreton.fr;F;2020-10-04
400789798;logement.foyer.pissos@wanadoo.fr;F;2020-10-15
400790911;direction@ch-mdm.fr;F;2020-10-04
400791257;ehpadmauleon@cias-montdemarsan-agglo.fr;F;2020-10-04
400791752;ehpad@ccas-tarnos.fr;F;2020-10-04
410000533;directioncampagnarde@orange.fr;F;2020-10-04
410002026;secretariat@ehpadlestourtraits.fr;F;2020-10-04
410002109;contact@ehpad-mer.fr;F;2020-10-04
410002117;secretariat@les-marronniers.fr;F;2020-10-04
410002125;directionlasagesse@gmail.com;F;2020-10-04
410002141;administration@ehpad-salbris.fr;F;2020-10-04
410002158;accueil@ehpad-leguereviau.fr;F;2020-10-04
410002174;accueil@ehpadfresne.fr;F;2020-10-04
410002190;accueil@labonneeure.fr;F;2020-10-04
410002216;residence.lumiere@ciasblaisois.fr;F;2020-10-04
410002224;accueil@residence-lafavorite.fr;F;2020-10-04
410002232;administration@lescedres-ehpad.fr;F;2020-10-04
410003750;direction@ch-vendome.fr;F;2020-10-04
410003784;hopital@ch-selles.fr;F;2020-10-04
410003891;foyer.direction@saintouen41.fr;F;2020-10-04
410003925;hopital@hl-saintaignan.fr;F;2020-10-04
410003958;accueil@residencelecureuil.com;F;2020-10-04
410004170;lavilleauxclercs.ehpad.secretariat@anais.asso.fr;F;2020-10-15
410004295;direction@ch-vendome.fr;F;2020-10-04
410004303;hopital@hlmontrichard.fr;F;2020-10-04
410004337;hopital@ch-selles.fr;F;2020-10-04
410004345;hopital@hl-saintaignan.fr;F;2020-10-04
410004378;direction@ch-vendome.fr;F;2020-10-04
410004386;direction@ch-romorantin.fr;F;2020-10-04
410004402;accueil@hop-marchenoir.fr;F;2020-10-04
410004881;contact@residence-closdemise.fr;F;2020-10-04
410005045;contact@residencedestourelles.com;F;2020-10-04
410005128;ehpad@41lescedres.com;F;2020-10-04
410005193;contact@residence-claude-de-france.com;F;2020-10-04
410005227;secretariat@les-mesanges.fr;F;2020-10-04
410005326;contact@le-val-fleuri.fr;F;2020-10-04
410005334;marpanouan41@gmail.com;F;2020-10-04
410005441;ehpad@41lespommeris.com;F;2020-10-04
410005490;mairie.soings@wanadoo.fr;F;2020-10-04
410005565;direction@ch-romorantin.fr;F;2020-10-04
410005615;contact@marpa-monteaux.fr;F;2020-10-04
410005896;direction.ehpad.chatres@orange.fr;F;2020-10-04
410006134;mapadhuizon@orange.fr;F;2020-10-04
410006878;contact@oree-des-pins.fr;F;2020-10-04
410007413;marpa.theillay@orange.fr;F;2020-10-04
410007637;foyer-logement4@wanadoo.fr;F;2020-10-04
410007694;marpadeoucques@gmail.com;F;2020-10-04
410007868;accueildejour@ciasdublaisois.fr;F;2020-10-04
420003469;accueildejour@aimv.org;F;2020-10-04
420003808;aloess.association@wanadoo.fr;F;2020-10-04
420004509;maison-de-retraite-lavalla@orange.fr;F;2020-10-04
420008898;accueildejour@madforez.com;F;2020-10-04
420008948;direction@laroseraie42.fr;F;2020-10-04
420009938;accueil@maison-d-annie.fr;F;2020-10-04
420010688;secretariat.direction@ch-firminy.fr;F;2020-10-04
420010738;secretariat.direction@ch-roanne.fr;F;2020-10-04
420012403;residence-mutualiste-bellevue@mutualite-loire.com;F;2020-10-04
420012981;gerontologie.secretariat@chu-st-etienne.fr;F;2020-10-04
420013997;ehpad.saintetienne@coallia.org;F;2020-10-04
420016073;residence-mutualiste-acces@mutualite-loire.com;F;2020-10-15
420780728;mrbourgargental@wanadoo.fr;F;2020-10-04
420781783;contact@ehpadblg.fr;F;2020-10-04
420781809;mr.champdieu@wanadoo.fr;F;2020-10-04
420781817;contact@ehpad-leparc.fr;F;2020-10-04
420781825;accueil@ehpadcoutouvre.fr;F;2020-10-04
420781833;ehpad.lapraniere@orange.fr;F;2020-10-04
420781841;contact@ehpadblg.fr;F;2020-10-04
420781866;accueil@ehpadmontagny.fr;F;2020-10-04
420781874;secretariat@ehpad-neulise.fr;F;2020-10-04
420781882;direction@ephad-noiretable.com;F;2020-10-04
420781908;contact@ehpad-panissieres.fr;F;2020-10-04
420781916;contact@ehpad-laforet.fr;F;2020-10-04
420781932;mdr-stgenestmalifaux@wanadoo.fr;F;2020-10-04
420781940;mdrstgermainlaval@wanadoo.fr;F;2020-10-04
420781957;accueil@ehpadsaintheand.fr;F;2020-10-04
420781965;administratif@ehpadlevalduternay.fr;F;2020-10-04
420781973;direction@ehpad-stjustchevalet.com;F;2020-10-04
420781999;ehpad@mdr-stnizier.fr;F;2020-10-15
420782005;accueil@ehpad-accueil.fr;F;2020-10-04
420782039;contact@ehpadusson.fr;F;2020-10-04
420782617;secretariat@ehpad-marie-romier.org;F;2020-10-04
420782633;secretariat@st-vincent-paul.org;F;2020-10-04
420783979;contact@ehpad-bussieres.fr;F;2020-10-04
420783987;contact@apa-rdg.com;F;2020-10-04
420783995;accueil@residencelechasseur.fr;F;2020-10-04
420784001;comptabilite@ehpad-notredame.fr;F;2020-10-04
420784043;foyer.verrerie@ville-firminy.fr;F;2020-10-04
420784092;contact@residence-lamartine.fr;F;2020-10-04
420784381;contact.laprovidence@mwsp.net;F;2020-10-04
420784423;direction.petiteprovence@ville-charlieu.fr;F;2020-10-04
420784464;residencedulac4@wanadoo.fr;F;2020-10-04
420784530;residence.jacoline@orange.fr;F;2020-10-04
420784597;residence.recamiere@ville-la-ricamarie.fr;F;2020-10-04
420784605;residence-mutualiste-lesmyosotis@mutualite-loire.com;F;2020-10-04
420784647;accueil@ehpadjoiedevivre.fr;F;2020-10-04
420784712;direction@laroseraie42.fr;F;2020-10-04
420785289;direction@ch-feurs.fr;F;2020-10-04
420786204;contact@maison-de-jeanne.fr;F;2020-10-04
420786212;mapafelines@fede42.admr.org;F;2020-10-04
420786485;residence@boen.fr;F;2020-10-04
420786873;direction@hopital-saint-galmier.fr;F;2020-10-04
420787194;gerontologie.secretariat@chu-stetienne.fr;F;2020-10-04
420787319;secretariat.direction@ch-roanne.fr;F;2020-10-04
420787681;mdr.violay@wanadoo.fr;F;2020-10-04
420787780;secretariat@ch-stjustlp.fr;F;2020-10-04
420787806;direction@h-charlieu.fr;F;2020-10-04
420787962;contact@chsaintbonnet.fr;F;2020-10-04
420787970;direction@ch-pelussin.fr;F;2020-10-04
420788176;foyer.mail@ville-firminy.fr;F;2020-10-04
420788515;info@renaudiere.org;F;2020-10-04
420789067;direction@hopital-saint-galmier.fr;F;2020-10-04
420789091;direction.labuissonniere@probtp.com;F;2020-10-04
420789281;accueil@ch-spdb.fr;F;2020-10-04
420789299;secretariat.direction@ch-roanne.fr;F;2020-10-04
420789307;contact@chsaintbonnet.fr;F;2020-10-04
420789547;residence.clairmont@orange.fr;F;2020-10-04
420790917;contact@residence-le-grillon.com;F;2020-10-04
420792442;residence-mutualiste-automne@mutualite-loire.com;F;2020-10-04
420792475;foyer.bruneaux@ville-firminy.fr;F;2020-10-04
420793275;ehpad@closchampirol.com;F;2020-10-04
420794505;ehpad.quietude@wanadoo.fr;F;2020-10-04
430000042;mr.allegre@wanadoo.fr;F;2020-10-04
430000075;direction@ehpad-monistrol.fr;F;2020-10-04
430000083;secretariat@ehpad-saugues.fr;F;2020-10-04
430000133;accueil-craponne@association-sd.fr;F;2020-10-04
430000364;accueil.cedres43@orange.fr;F;2020-10-04
430002055;mrbasenbasset2@wanadoo.fr;F;2020-10-04
430002063;ehpad-lachaisedieu@orange.fr;F;2020-10-04
430002139;contact@ehpadvellavi.com;F;2020-10-04
430002188;mrtence@orange.fr;F;2020-10-04
430002568;accueil@lpanazareth.fr;F;2020-10-04
430002758;marpasaintodilon@orange.fr;F;2020-10-04
430003608;accueil@association-sd.fr;F;2020-10-04
430004143;direction@ch-brioude.fr;F;2020-10-04
430005363;mdr.retournac@orange.fr;F;2020-10-04
430005371;residence.sigolene@wanadoo.fr;F;2020-10-04
430005397;mr@ehpad-vertbocage.fr;F;2020-10-04
430005439;secretariat@foyersaintjean.fr;F;2020-10-04
430005488;foyer-bon-accueil@wanadoo.fr;F;2020-10-04
430005595;mapad.coubon@libertysurf.fr;F;2020-10-04
430005629;ehpad.chalmettes@lepuyenvelay.fr;F;2020-10-04
430005983;direction@ch-lepuy.fr;F;2020-10-04
430006353;direction@ch-yssingeaux.fr;F;2020-10-04
430006809;direction@ch-brioude.fr;F;2020-10-04
430006866;contact@ehpadparadis.fr;F;2020-10-04
430007021;mapa.grand.pre@wanadoo.fr;F;2020-10-04
430007252;direction@hlyx.fr;F;2020-10-04
430007310;info.pontsalomon@fede43.admr.org;F;2020-10-04
430007443;info.bergesfleuries@fede43.admr.org;F;2020-10-04
430007567;cias.marpaloudes@wanadoo.fr;F;2020-10-04
430007609;residencelespireilles@orange.fr;F;2020-10-04
430007716;contact@hdm43.fr;F;2020-10-04
430007856;direction@ch-lepuy.fr;F;2020-10-04
430007872;secretariat.de.direction@lepuy-groupe-sainte-marie.com;F;2020-10-04
440000354;accueil.mr.guemene-penfao@wanadoo.fr;F;2020-10-04
440002046;ehpad3rivieres@orange.fr;F;2020-10-04
440002053;residencelagrange@orange.fr;F;2020-10-04
440002079;info.beaulieu@mutualiteretraite.fr;F;2020-10-04
440002095;direction@residence-st-joseph.fr;F;2020-10-04
440002103;direction@ehpad-monrepos.fr;F;2020-10-04
440002327;contact@aimr.fr;F;2020-10-04
440002640;secretariat.varades@ch-erdreloire.fr;F;2020-10-04
440002657;logispetiteforetdirection@orange.fr;F;2020-10-04
440002665;contact@aimr.fr;F;2020-10-04
440002673;info.pampresdores@mutualiteretraite.fr;F;2020-10-04
440002681;residencedusoleil@wanadoo.fr;F;2020-10-04
440002715;info.belairvertou@mutualiteretraite.fr;F;2020-10-04
440002723;administratif@suzaie44.fr;F;2020-10-04
440002731;mdr.teille@wanadoo.fr;F;2020-10-04
440002749;contact@bonaccueil.fr;F;2020-10-04
440002756;residence@v-ecomard.fr;F;2020-10-04
440002764;contact@aimr.fr;F;2020-10-04
440002772;direction@erdrelandes44.fr;F;2020-10-04
440002780;contact@aimr.fr;F;2020-10-04
440002798;accueil@residence-ileverte.fr;F;2020-10-04
440002806;residence@lesjardinsdelerdre.fr;F;2020-10-04
440002822;residencebriere@wanadoo.fr;F;2020-10-04
440002855;accueil@labourgonniere.fr;F;2020-10-04
440002863;direction@resandre.fr;F;2020-10-04
440002871;residence3moulins@wanadoo.fr;F;2020-10-04
440002921;residence.lachataigneraie@wanadoo.fr;F;2020-10-04
440002947;secretariat@mdr-saintjoseph-nantes.com;F;2020-10-04
440002954;accueil@lesrivesdelerdre.fr;F;2020-10-15
440002988;accueilmrsaintpierre@orange.fr;F;2020-10-04
440002996;secretariat@gie-charmilles.fr;F;2020-10-04
440003044;contact@residence-montclair.fr;F;2020-10-04
440003051;residencefleursdeschamps@wanadoo.fr;F;2020-10-04
440003069;accueil@maison-bonrepos.fr;F;2020-10-04
440003077;contact.kermaria@association-beausejour.fr;F;2020-10-04
440003101;direction@residencelaperriere.fr;F;2020-10-04
440003119;residence@cormiere.com;F;2020-10-04
440003135;info.stlouis@mutualiteretraite.fr;F;2020-10-04
440003184;accueil@isacderohan.fr;F;2020-10-04
440003200;direction@mr-derval.com;F;2020-10-04
440003218;accueil@nortseniors.fr;F;2020-10-04
440003234;resid.letraict@asso-automne.fr;F;2020-10-04
440003440;secretariat@laprovidence44.fr;F;2020-10-04
440003457;residence.lesajoncs@orange.fr;F;2020-10-04
440003465;resid.lestilleuls@asso-automne.fr;F;2020-10-04
440003549;info.stjoseph@mutualiteretraite.fr;F;2020-10-04
440003564;administration.oudon@ch-erdreloire.fr;F;2020-10-04
440003572;residencelesillon@wanadoo.fr;F;2020-10-04
440003598;contact@immaculee.fr;F;2020-10-04
440003622;secretariatploreau@orange.fr;F;2020-10-04
440003887;contact@aimr.fr;F;2020-10-04
440007318;contact@les3clochers.fr;F;2020-10-04
440007441;contact@aimr.fr;F;2020-10-04
440007458;contact@aimr.fr;F;2020-10-04
440007466;residenceleverger@wanadoo.fr;F;2020-10-04
440009371;residence.elsa@wanadoo.fr;F;2020-10-04
440009389;info.lachapelle@mutualiteretraite.fr;F;2020-10-04
440009405;info.belairbouaye@mutualiteretraite.fr;F;2020-10-04
440009447;info.reposdeproce@mutualiteretraite.fr;F;2020-10-04
440009462;direction@asso-bon-pasteur.com;F;2020-10-04
440009512;accueil@residence-esperance.fr;F;2020-10-04
440012086;accueil@leprieure-cordemais.fr;F;2020-10-04
440013290;resid.lachalandiere@asso-automne.fr;F;2020-10-04
440013308;residencesautonomie@mairie-nantes.fr;F;2020-10-04
440013324;residencesautonomie@mairie-nantes.fr;F;2020-10-04
440013340;residencesautonomie@mairie-nantes.fr;F;2020-10-04
440013365;residencesautonomie@mairie-nantes.fr;F;2020-10-04
440013373;residencesautonomie@mairie-nantes.fr;F;2020-10-04
440013449;info.lamarriere@mutualiteretraite.fr;F;2020-10-04
440017713;info.louisemichel@mutualiteretraite.fr;F;2020-10-04
440017721;info.lessableaux@mutualiteretraite.fr;F;2020-10-04
440018133;direction@ch-chateaubriant.fr;F;2020-10-14
440018893;info.lesnoelles@mutualiteretraite.fr;F;2020-10-04
440018901;info.lessaulniers@mutualiteretraite.fr;F;2020-10-04
440021095;hopital@ch-savenay.fr;F;2020-10-15
440021111;direction@ch-savenay.fr;F;2020-10-04
440021129;direction@hipr44.fr;F;2020-10-04
440021160;residence.galathea@fondationpartageetvie.org;F;2020-10-04
440021186;hopital@hli-presquile.fr;F;2020-10-14
440021194;hopital@hli-presquile.fr;F;2020-10-15
440021202;direction@ch-lvo.fr;F;2020-10-15
440021210;direction@ch-lvo.fr;F;2020-10-04
440021228;secretariat.direction@hopital-sevre-loire.fr;F;2020-10-04
440021236;hopital@hopital-sevre-loire.fr;F;2020-10-15
440021244;secretariat.direction@hopital-sevre-loire.fr;F;2020-10-04
440021251;hopital@hopital-sevre-loire.fr;F;2020-10-15
440021277;direction@ch-erdreloire.fr;F;2020-10-04
440021285;direction@ch-ancenis.fr;F;2020-10-15
440021293;accueil.ehpadplesse@rochefoucauld.fr;F;2020-10-04
440021301;direction@hipr44.fr;F;2020-10-04
440021327;direction@ch-cnp.fr;F;2020-10-04
440021350;hopital@hli-presquile.fr;F;2020-10-04
440021368;direction@ch-chateaubriant.fr;F;2020-10-04
440021400;ehpad-pirmil@mairie-nantes.fr;F;2020-10-04
440022671;contact@aimr.fr;F;2020-10-04
440023190;ehpad-madeleine@mairie-nantes.fr;F;2020-10-04
440023810;accueil@ehpad-mer-et-pins.com;F;2020-10-04
440024594;resid.automne@asso-automne.fr;F;2020-10-04
440024602;contact.stjoseph@association-beausejour.fr;F;2020-10-04
440024610;accueil@residencestmartin.fr;F;2020-10-04
440024628;maisonderetraitegorges@wanadoo.fr;F;2020-10-04
440024636;ehpad@champfleuri44.fr;F;2020-10-04
440024644;secretariat.rochemaillard@gmail.com;F;2020-10-04
440024701;accueil@residencelouiscubaynes.fr;F;2020-10-04
440024719;residence.davrays@orange.fr;F;2020-10-04
440024727;residenceleseglantines@abse44.fr;F;2020-10-04
440025443;ste.famille.accueil@orange.fr;F;2020-10-04
440026839;accueil@residence-la-roseliere.fr;F;2020-10-04
440027092;accueil@boisherce.fr;F;2020-10-04
440027118;direction.chezaliere@lna-sante.com;F;2020-10-04
440028553;info.richebourg@mutualiteretraite.fr;F;2020-10-04
440028595;accueilstmartin@orange.fr;F;2020-10-04
440028694;resid.lacotedamour@asso-automne.fr;F;2020-10-04
440028827;contact@le-closfleuri.fr;F;2020-10-04
440028843;direction@hl-clisson.fr;F;2020-10-15
440028868;contact@maison-saint-charles.fr;F;2020-10-04
440028884;direction@hl-corcoue.fr;F;2020-10-15
440028934;accueil@residencevaldebrutz.fr;F;2020-10-04
440029544;info.lemuguet@mutualiteretraite.fr;F;2020-10-04
440029825;direction@ch-blain.fr;F;2020-10-15
440029866;accueil.quietus@gmail.com;F;2020-10-04
440032399;direction@hipr44.fr;F;2020-10-15
440032407;direction@hipr44.fr;F;2020-10-04
440032639;info.jeanmace@mutualiteretraite.fr;F;2020-10-04
440033413;residencedudon@residencedudon.fr;F;2020-10-04
440033645;direction@ch-chateaubriant.fr;F;2020-10-15
440034338;direction.diane@lna-sante.com;F;2020-10-04
440037877;contact@foyer-hortensias.fr;F;2020-10-04
440041333;direction@hipr44.fr;F;2020-10-04
440041739;direction.creisker@lenobleage.fr;F;2020-10-04
440042174;resid.leport@asso-automne.fr;F;2020-10-04
440042570;contact@alfarepit.fr;F;2020-10-04
440044337;info.laforet@mutualiteretraite.fr;F;2020-10-04
440044618;contact@accueilretz.org;F;2020-10-04
440044717;info.lenchanterie@mutualiteretraite.fr;F;2020-10-04
440045607;accueil@sfgrillaud.fr;F;2020-10-04
440046555;secretariat@mdr-saintjoseph-nantes.com;F;2020-10-04
440046563;accueildejour@saint-herblain.fr;F;2020-10-04
440046860;recollets-accueil-jour@mairie-nantes.fr;F;2020-10-04
440046936;accueil.pornic@groupecolisee.com;F;2020-10-04
440047470;info.parcdelamande@mutualiteretraite.fr;F;2020-10-04
440047561;direction@hl-corcoue.fr;F;2020-10-04
440047629;direction@ch-cnp.fr;F;2020-10-04
440047678;haute-mitrie-accueil-jour@mairie-nantes.fr;F;2020-10-04
440047744;accueil.guerande@orpea.net;F;2020-10-04
440049302;info.leontine@mutualiteretraite.fr;F;2020-10-04
440051589;info.suzanneflon@mutualiteretraite.fr;F;2020-10-04
440052694;info.louisemichel@mutualiteretraite.fr;F;2020-10-04
440052793;info.lachapelle@mutualiteretraite.fr;F;2020-10-04
440053833;info.beaulieu@mutualiteretraite.fr;F;2020-10-04
440053841;residencelebeguinage@orange.fr;F;2020-10-04
450000781;accueil@fhp-fontpertuis.fr;F;2020-10-04
450000815;contact@notrefoyer.fr;F;2020-10-04
450000823;mrauxy@wanadoo.fr;F;2020-10-04
450001755;residence-st-martin@wanadoo.fr;F;2020-10-04
450002118;administration@ehpaddespres.fr;F;2020-10-04
450002217;ehpad@ehpadlesjardinsdesido.fr;F;2020-10-04
450002225;administration@ehpadlachanterelle.fr;F;2020-10-04
450002241;accueilehpadpetitpierre@orange.fr;F;2020-10-04
450002258;accueilehpadpetitpierre@orange.fr;F;2020-10-04
450002266;accueil@ehpad-lorris.fr;F;2020-10-04
450002282;residencetrianon@orange.fr;F;2020-10-04
450002290;mrpuiseaux@wanadoo.fr;F;2020-10-04
450002308;accueil@ehpad-st-benoit.fr;F;2020-10-04
450002332;mr.meung@orange.fr;F;2020-10-04
450003934;administration1.lebaron@korian.fr;F;2020-10-04
450004007;contact@les-rives-du-puiseaux.com;F;2020-10-04
450005368;accueildejour.clery@orange.fr;F;2020-10-04
450006028;direction@marpa-ste-rose.fr;F;2020-10-04
450006978;marpadenesploy@orange.fr;F;2020-10-04
450007174;foyer.henri.deschamps@orange.fr;F;2020-10-04
450007182;residence.quietude@wanadoo.fr;F;2020-10-04
450007208;contact.chevilly@svfa.fr;F;2020-10-04
450007216;mairiechalette.foyerduclos@wanadoo.fr;F;2020-10-04
450007224;foyerlogement@orange.fr;F;2020-10-04
450007307;accueil@ehpad-raymondpoulin.com;F;2020-10-04
450007679;gestion.orleans@rennes-psdp.com;F;2020-10-04
450007687;accueil@ehpad-nazareth.com;F;2020-10-04
450009139;foyer.georges-brassens@ville-saran.fr;F;2020-10-04
450009485;hopital.beaugency@wanadoo.fr;F;2020-10-04
450009642;foyerdesbelettes@ville-beaugency.fr;F;2020-10-04
450010103;direction@hopitalneuville.fr;F;2020-10-04
450010129;direction@hblr.fr;F;2020-10-04
450010137;contact@hopital-sully.fr;F;2020-10-04
450010764;direction@ch-pithiviers.fr;F;2020-10-04
450012059;direction@hopital-saint-jean.fr;F;2020-10-04
450012067;direction@hopital-saint-jean.fr;F;2020-10-04
450012497;cigogne.direction@arpavie.fr;F;2020-10-04
450012505;administration.santel@korian.fr;F;2020-10-04
450012810;residence-ste-cecile@orange.fr;F;2020-10-04
450013578;marpa.lesalouettes@orange.fr;F;2020-10-04
450013594;contact.lasource@svfa.fr;F;2020-10-04
450014188;retraitepinelles@wanadoo.fr;F;2020-10-04
450014410;direction@ch-pithiviers.fr;F;2020-10-04
450014535;contact.lachapelle@svfa.fr;F;2020-10-04
450015276;retraite.dordives.direction@orange.fr;F;2020-10-04
450016308;accueil.courtenay@groupecolisee.com;F;2020-10-04
450019799;direction@ch-montargis.fr;F;2020-10-04
450020524;marpalescharmilles45@outlook.com;F;2020-10-04
460004674;marpa.de.lauzes@wanadoo.fr;F;2020-10-04
460004989;residencebataille@orange.fr;F;2020-10-04
460005374;residenceolt@mairie-cahors.fr;F;2020-10-04
460005671;contact@ehpad-labarte.org;F;2020-10-04
460006604;ssiad@agirpourmieuxvivre.org;F;2020-10-04
460780299;direction.consuls@wanadoo.fr;F;2020-10-04
460781578;residencebataille@orange.fr;F;2020-10-04
460781586;residence.barthelemy@wanadoo.fr;F;2020-10-04
460781602;residence-autonomie@ccas-luzech.fr;F;2020-10-04
460781610;residence.cesarines@hotmail.com;F;2020-10-04
460781669;ehpad.sousceyrac@orange.fr;F;2020-10-04
460781768;ehpadbagnac@orange.fr;F;2020-10-04
460781990;direction@ch-figeac.fr;F;2020-10-04
460782584;foyer-logements.legalau@wanadoo.fr;F;2020-10-04
460784374;maison.accueil.glanes@orange.fr;F;2020-10-04
460784424;direction@ch-gourdon.fr;F;2020-10-04
460785595;accueil@ch-cahors.fr;F;2020-10-04
460785744;ehpad.st.germain@orange.fr;F;2020-10-04
460785751;foyer-lacascade@orange.fr;F;2020-10-04
460785850;accueil@ch-gramat.fr;F;2020-10-04
460786379;marpalalbenque@orange.fr;F;2020-10-04
460786429;mapad.limogne@orange.fr;F;2020-10-04
460786569;accueil@ch-gramat.fr;F;2020-10-04
460786692;ehpad@ccas-luzech.fr;F;2020-10-04
460786957;direction@ehpad-catus.com;F;2020-10-04
460787039;mapad2@wanadoo.fr;F;2020-10-04
460787203;ehpad.pradels.direction@gmail.com;F;2020-10-04
460787229;direction@ch-figeac.fr;F;2020-10-04
470000506;ehpad@mrcasseneuil.fr;F;2020-10-15
470000514;ehpadaiguillon@fr.oleane.com;F;2020-10-04
470002031;accueil@residence-comarque-beaumanoir.fr;F;2020-10-04
470002056;accueil@residencelescapucins.fr;F;2020-10-04
470002064;mrdamazan@wanadoo.fr;F;2020-10-04
470002080;accueil@mr-masagenais.fr;F;2020-10-04
470002106;administratif@ehpad-mezin.fr;F;2020-10-04
470002114;accueil@fondation-soussial.fr;F;2020-10-04
470002130;administration@ehpad-monflanquin.fr;F;2020-10-04
470002148;ehpadportstemarie@fr.oleane.com;F;2020-10-04
470002155;accueil@mrstelivrade.fr;F;2020-10-04
470002189;accueil@ehpadeulalie.fr;F;2020-10-04
470002239;secretariat@ehpadcancon.fr;F;2020-10-04
470002932;marpa847@orange.fr;F;2020-10-04
470004094;residencederaymond@fondationpartageetvie.org;F;2020-10-04
470005398;secretariat.direction@ch-agen-nerac.fr;F;2020-10-04
470005422;ccas@miramontdeguyenne.fr;F;2020-10-04
470005430;residencebellevue.monclar47@orange.fr;F;2020-10-04
470005455;ccas.tonneins@orange.fr;F;2020-10-04
470005463;tournon.mairie@wanadoo.fr;F;2020-10-04
470008699;secretariat.direction@ch-agen-nerac.fr;F;2020-10-04
470008749;direction@ch-casteljaloux.fr;F;2020-10-04
470008756;hopital.fumel@hopital-fumel.fr;F;2020-10-04
470008764;hopital.fumel@psv47.fr;F;2020-10-04
470008780;secretariat.direction@ch-agen-nerac.fr;F;2020-10-04
470009259;ehpad.sos@orange.fr;F;2020-10-04
470009648;secretariat-chenes-verts@orange.fr;F;2020-10-04
470009739;direction@ehpad-47.com;F;2020-10-15
470009754;residence.lechateau@groupe-mieuxvivre.fr;F;2020-10-04
470013087;contact@ccas-saintebazeille.fr;F;2020-10-04
470013160;marpa.serignac47@wanadoo.fr;F;2020-10-04
470013863;marpa.pont-du-casse@wanadoo.fr;F;2020-10-04
470013897;marpadelavardac@orange.fr;F;2020-10-04
470014200;ehpadlelotusbleu@orange.fr;F;2020-10-04
470014226;asso.jardinalois@fede47.admr.org;F;2020-10-04
470014275;administration.fontaine-bazeille@medica.fr;F;2020-10-04
470015249;administratif@ehpad-mezin.fr;F;2020-10-04
470015876;administration@ehpad-villereal.fr;F;2020-10-04
480000694;hopital@ch-florac.fr;F;2020-10-04
480000751;residenceleonpicy@orange.fr;F;2020-10-04
480001015;ehpad.st-alban@orange.fr;F;2020-10-04
480001254;ehpad.fournels@orange.fr;F;2020-10-04
480003821;direction@ch-langogne.fr;F;2020-10-04
480780089;residence.piencourt@orange.fr;F;2020-10-04
480780329;residence.ray@wanadoo.fr;F;2020-10-04
480780444;ehpad.auroux@wanadoo.fr;F;2020-10-04
480780451;secretariatmaisondesaires@gmail.com;F;2020-10-04
480780477;ehpad.villefort@wanadoo.fr;F;2020-10-04
480780527;rejal-secretariat@fondationcos.org;F;2020-10-04
480780659;residencemargeride@wanadoo.fr;F;2020-10-04
480780766;accueil@residenceles3sources.fr;F;2020-10-04
480780832;secretariatehpad@ch-mende.fr;F;2020-10-04
480783125;accueil.lasoleillade@orange.fr;F;2020-10-04
480783158;direction@chsc.fr;F;2020-10-04
480783182;contact@ehpadmalzieu.fr;F;2020-10-04
480783190;direction@ch-langogne.fr;F;2020-10-04
480783208;accueil@ch-langogne.fr;F;2020-10-04
480783216;hopital@ch-florac.fr;F;2020-10-04
490000650;direction@lyshyrome.fr;F;2020-10-04
490000858;direction@ehpadmaulevrier.fr;F;2020-10-04
490002086;contact.becon@ehpadrba.fr;F;2020-10-04
490002110;contact@leshautsduchateau.fr;F;2020-10-15
490002128;direction.mr.coron@orange.fr;F;2020-10-04
490002136;accueil@leschenesdubellay.fr;F;2020-10-04
490002144;direction@aufilduloir.fr;F;2020-10-04
490002151;ehpad.ecouflant@hauts-de-maine.fr;F;2020-10-04
490002169;ehpad.feneu@hauts-de-maine.fr;F;2020-10-04
490002185;residence.notre-dame@residences-de-levre.fr;F;2020-10-04
490002193;contact.lelion@ehpadrba.fr;F;2020-10-04
490002201;accueil@leschenesdubellay.fr;F;2020-10-04
490002227;direction@esbv.fr;F;2020-10-15
490002235;direction@hopital-baugeois-vallee.fr;F;2020-10-04
490002250;accueil@ehpad-montreuilbellay.fr;F;2020-10-04
490002268;direction@hlmr-stnicolas-angers.fr;F;2020-10-04
490002284;admission@chdouelafontaine.fr;F;2020-10-04
490002292;accueil@ehpadlespontdece.fr;F;2020-10-04
490002326;accueil@residencebonchamps.fr;F;2019-05-28
490002367;accueil@mrstmathurin.fr;F;2020-10-04
490002391;direction@ch-layon-aubance.fr;F;2020-10-04
490002417;contact.vern@ehpadrba.fr;F;2020-10-04
490002425;admissionsvihiers@lyshyrome.fr;F;2020-10-04
490002433;accueil@residencelestroenes.fr;F;2020-10-04
490002441;ehpad@champtoceaux.fr;F;2020-10-04
490002532;direction@ehpad-landemont-lefuilet.fr;F;2020-10-04
490002706;direction@residencerogersalmon.fr;F;2020-10-04
490002730;accueil@mrnazareth.fr;F;2020-10-04
490002748;mrgeste.direction@wanadoo.fr;F;2020-10-04
490002755;direction.saintveterin@orange.fr;F;2020-10-04
490002763;direction@ehpad-landemont-lefuilet.fr;F;2020-10-04
490002771;residence.sacre-coeur@residences-de-levre.fr;F;2020-10-04
490002789;beausoleil.residence@wanadoo.fr;F;2020-10-04
490002797;accueil@labuissaie.fr;F;2020-10-04
490002805;mdrclairefontaine@hotmail.fr;F;2020-10-04
490002813;mrnoyant@wanadoo.fr;F;2020-10-04
490002821;accueil@mdrlepin.com;F;2020-10-04
490002854;residence@sevret.fr;F;2020-10-04
490002862;direction@v-ensemble.org;F;2020-10-04
490002888;secretariat@residenceabbaye.fr;F;2020-10-04
490002896;residencedulattay@orange.fr;F;2020-10-04
490002920;mrtessoualle@orange.fr;F;2020-10-04
490002946;ehpad_steanne@orange.fr;F;2020-10-04
490002953;contact@adasa-ehpadstjoseph.com;F;2020-10-04
490002961;accueil.couleursdutemps@mfam49-53.fr;F;2020-10-04
490003027;direction@residencedesacacias.fr;F;2020-10-04
490003225;accueil.belaccueil@mfam49-53.fr;F;2020-10-04
490003654;accueil.saintmartin@anjou-mr.org;F;2020-10-04
490003662;accueil@augustines-angers.fr;F;2020-10-04
490003720;accueil.epire@anjou-mr.org;F;2020-10-04
490003761;direction.saintjoseph@anjou-mr.org;F;2020-10-04
490003787;direction@v-ensemble.org;F;2020-10-04
490003795;contact@leprieure49montilliers.com;F;2020-10-04
490003811;accueil.oreeduparc@mfam49-53.fr;F;2020-10-04
490003829;accueil.noisetiers@mfam.fr;F;2020-10-04
490003894;accueil.stjean@beaupreauenmauges.fr;F;2020-10-04
490003928;contact@residence-tharreau.fr;F;2020-10-04
490003936;residencelescharmilles49@orange.fr;F;2020-10-04
490003944;residence.lescedres49@orange.fr;F;2020-10-04
490003977;ehpa-champsfleuris@ville-lespontsdece.fr;F;2020-10-04
490003993;contact@maisondaccueil.net;F;2020-10-04
490004025;residenceautonomielesfontaines@orange.fr;F;2020-10-04
490004215;contact@annedemelun.fr;F;2020-10-04
490007424;direction@v-ensemble.org;F;2020-10-04
490007432;accueil@msajd.fr;F;2020-10-04
490007473;accueil.euphrasie@anjou-mr.org;F;2020-10-04
490007481;direction.saintcharles@anjou-mr.org;F;2020-10-04
490007556;accueil.saintemarie@anjou-mr.org;F;2020-10-04
490008844;ehpad-chanteriviere-secretariat@ch-cholet.fr;F;2020-10-04
490011517;direction@ch-cnp.fr;F;2020-10-14
490019601;residence.chanteriviere@ch-cholet.fr;F;2020-10-04
490019635;accueil@res3moulins.fr;F;2020-10-04
490019643;contact@maisondaccueil.net;F;2020-10-04
490019668;residence-la-perriere@orange.fr;F;2020-10-04
490019676;secretariat@residence-lebreton.fr;F;2020-10-04
490020476;direction-moncellieres@orange.fr;F;2020-10-04
490530896;secretariat.leclairlogis@sevremoine.fr;F;2020-10-04
490530987;secretariat@ehpad-valanjou.fr;F;2020-10-04
490531266;accueil@res3moulins.fr;F;2020-10-04
490531860;info@residence-bellefontaine.fr;F;2020-10-04
490535648;accueil.picasso@mfam49-53.fr;F;2020-10-04
490536026;direction@ch-saumur.fr;F;2020-10-04
490536042;direction@ch-saumur.fr;F;2020-10-04
490536059;direction@hopital-baugeois-vallee.fr;F;2020-10-04
490536067;direction@hopital-baugeois-vallee.fr;F;2020-10-04
490536075;direction@ch-erdreloire.fr;F;2020-10-04
490536083;direction@hopital-chalonnes.fr;F;2020-10-04
490536109;direction@hopital-longue.fr;F;2020-10-04
490536133;admissionschemille@lyshyrome.fr;F;2020-10-04
490536141;admission@chdouelafontaine.fr;F;2020-10-04
490536158;direction@hopital-longue.fr;F;2020-10-04
490536174;direction@ch-chateaubriant.fr;F;2020-10-04
490536182;residences@lesligeriennes.fr;F;2020-10-04
490536216;direction@vssj.fr;F;2020-10-04
490536562;direction@les-capucins-angers.fr;F;2020-10-04
490536976;residence.valdelisle@orange.fr;F;2020-10-04
490537040;direction@les-capucins-angers.fr;F;2020-10-04
490537156;foyer.henridouet@orange.fr;F;2020-10-04
490537180;foyer.logement@mairie-trelaze.fr;F;2020-10-04
490537230;foyerlogementvernoil@orange.fr;F;2020-10-04
490538626;accueil.logisdesjardins@mfam49-53.fr;F;2020-10-04
490538675;secretariat@residenceportlavallee.fr;F;2020-10-04
490538832;direction.sainteanne@groupe-aplus.com;F;2020-10-04
490538840;direction.angers@agepartenaires.com;F;2020-10-04
490539103;hopital@hl-pouance.fr;F;2020-10-04
490539178;residencelesjoncheres@gmail.com;F;2020-10-04
490539186;comptabilite@residence-lebreton.fr;F;2020-10-04
490539236;direction.plesse@lna-sante.com;F;2020-10-04
490539376;residence.lesjonquilles@lrs49.fr;F;2020-10-04
490540390;ehpad@wanadoo.fr;F;2020-04-20
490540408;residence-la-perriere@orange.fr;F;2020-10-04
490540416;accueil.lagrandmaison@mfam49-53.fr;F;2020-10-04
490540481;secretariat@les2clochers.fr;F;2020-10-04
490540606;foyerlogement49@orange.fr;F;2020-10-04
490541208;residencelepinette@wanadoo.fr;F;2020-10-04
490542206;mairie@tuffalun.fr;F;2020-10-04
500000088;direction@ch-estran.fr;F;2020-10-04
500000450;direction@ch-stlo.fr;F;2020-10-04
500002332;retraite.stjoseph@wanadoo.fr;F;2020-10-04
500002431;direction.esperance@orange.fr;F;2020-10-04
500002720;secretariat@ehpad-barenton.fr;F;2020-10-04
500002746;mr.carquebut@wanadoo.fr;F;2020-10-04
500002753;ehpad@mr-delivet.fr;F;2020-10-04
500002761;accueil@ehpad-periers.com;F;2020-10-04
500002779;ehpad.lahayepesnel@orange.fr;F;2020-10-04
500002803;ehpad-de-montebourg@orange.fr;F;2020-10-04
500002811;accueil@ehpad-periers.com;F;2020-10-04
500002829;accueil@ehpad-percy.fr;F;2020-10-04
500002837;direction@hopital-carentan.fr;F;2020-10-04
500002845;accueil@ehpad-sme.fr;F;2020-10-04
500002878;mr.sartilly@wanadoo.fr;F;2020-10-04
500002886;secretariat@ehpad-leteilleul.fr;F;2020-10-04
500002894;direction@ehpad-agon-coutainville.fr;F;2020-10-04
500003959;ccas@ville-cherbourg.fr;F;2020-10-04
500004122;ehpad.beregovoy@cherbourg.fr;F;2020-10-04
500004189;accueil@maisonretraitebrehal.fr;F;2020-10-04
500004197;ehpad.lepaysvalognais@ch-cotentin.fr;F;2020-10-04
500004221;secretariat@hopital-mortain.fr;F;2020-10-04
500004239;direction@ch-coutances.fr;F;2020-10-04
500004270;direction@ch-sthilaire-harcouet.fr;F;2020-10-14
500004536;secretariat.ehpad-octeville@ch-cotentin.fr;F;2020-10-04
500004585;direction.bucaille@orange.fr;F;2020-10-04
500004718;direction@maisondusaintcoeurdemarie.fr;F;2020-10-04
500004783;secretariat.ehpadpicauville@fbs50.fr;F;2020-10-04
500004833;contact@leshirondelles.asso.fr;F;2020-10-04
500004841;contact@residence-schmitt.com;F;2020-10-04
500005012;ccas@cherbourg.fr;F;2020-10-04
500005020;mairie.tessy@wanadoo.fr;F;2020-10-04
500005038;direction.ehpad@ccas.coutances.fr;F;2020-10-04
500009196;ccas@cherbourg.fr;F;2020-10-04
500012133;direction@ch-avranches-granville.fr;F;2020-10-04
500012174;direction@ch-avranches-granville.fr;F;2020-10-04
500012208;secretariat-direction@hopital-carentan.fr;F;2020-10-04
500012216;direction@ch-coutances.fr;F;2020-10-04
500012224;secretariat@hopital-mortain.fr;F;2020-10-04
500012232;accueil@ehpad-periers.com;F;2020-10-04
500012240;contact@etabs-stjames.fr;F;2020-10-04
500012604;mairie.quettehou@wanadoo.fr;F;2020-10-04
500012638;contact.residenceautonomieledonjon@orange.fr;F;2020-10-04
500012653;ccas@cherbourg.fr;F;2020-10-04
500013081;direction@ch-avranches-granville.fr;F;2020-10-04
500013099;direction@ch-avranches-granville.fr;F;2020-10-04
500013305;ccas@cherbourg.fr;F;2020-10-04
500013479;accueil@percyennormandie.fr;F;2020-10-04
500013511;ccas@cherbourg.fr;F;2020-10-04
500013891;mapa.reffuveille@orange.fr;F;2020-10-04
500013925;mairie@gavray.net;F;2020-10-04
500014113;contact.saint-michel@philogeris.com;F;2020-10-04
500014204;residencelagerfleur@orange.fr;F;2020-10-04
500014279;ccas@cherbourg.fr;F;2020-10-04
500014378;contact@leshirondelles.asso.fr;F;2020-10-04
500014550;direction.cias@orange.fr;F;2020-10-04
500014584;direction@ch-coutances.fr;F;2020-10-04
500014592;mairie.hambye@wanadoo.fr;F;2020-10-04
500014683;direction.cias@orange.fr;F;2020-10-04
500016365;ehpad.ccas.bricquebec@orange.fr;F;2020-10-04
500016522;mairie.stpois@wanadoo.fr;F;2020-10-04
500016621;direction.residence-labbaye@fondationpartageetvie.org;F;2020-10-04
500016670;direction@ehpad4saisons.fr;F;2020-10-04
500016720;marpa.leschaumieres@orange.fr;F;2020-10-04
500016753;mairie.sartilly@wanadoo.fr;F;2020-10-04
500016837;ehpad-creances@orange.fr;F;2020-10-04
500016845;ehpad-lessay@orange.fr;F;2020-10-04
500016985;residence.parcfleuri@gmail.com;F;2020-10-04
500016993;ehpad@mairie-tourlaville.fr;F;2020-10-04
500017538;residence.rougesgorges@resalia.com;F;2020-10-04
500018940;direction.cias@orange.fr;F;2020-10-04
500018957;direction.cias@orange.fr;F;2020-10-04
500019229;reception.lagoelette@korian.fr;F;2020-10-04
500019278;secretariat.ehpadmartinvast@fbs50.fr;F;2020-10-04
500019674;residence-autonomie@conde-sur-vire.fr;F;2020-10-04
500019914;accueil@ehpadlesdunes.fr;F;2020-10-04
500019989;direction@ch-coutances.fr;F;2020-10-04
500020656;accueil@demeuredumaupas.com;F;2020-10-04
500020763;secretariat@ehpadlevallon.fr;F;2020-10-04
500021779;ehpadlevallon@yahoo.fr;F;2018-07-11
500023874;mairie.contact@carentan.fr;F;2020-10-04
500023916;marpadujardinsecret@gmail.com;F;2020-10-04
500024047;direction@ehpad-agon-coutainville.fr;F;2020-10-04
510000110;direction-verzenay@mdr-verzenay.fr;F;2020-10-04
510002090;accueil@ehpad-avize.fr;F;2020-10-04
510003536;hebergement@ch-chalonsenchampagne.fr;F;2020-10-04
510003577;contact@ch-argonne.fr;F;2020-10-04
510003668;admissionehpad.jeandorbais@probtp.com;F;2020-10-04
510003783;secretariat.sarrail@chalonsenchampagne.fr;F;2020-10-04
510003817;direction@asso-jean23.fr;F;2020-10-04
510003866;foyeraviat@gmail.com;F;2020-10-04
510003957;association@arfo.fr;F;2020-10-04
510004070;contact@aapa.fr;F;2020-10-04
510004344;administration@msj51.fr;F;2020-10-04
510004369;accueil@lesourirechampenois.fr;F;2020-10-04
510004377;accueil.stmartin@habitat-humanisme.org;F;2020-10-04
510006661;admission.hameau@ch-epernay.fr;F;2020-10-04
510008766;contact@residencesbellevue.fr;F;2020-10-04
510010127;admission@hl-fismes.fr;F;2020-10-04
510010176;direction@ch-epernay.fr;F;2020-10-04
510010317;direction@montmirail-hopital-local.fr;F;2020-10-04
510010374;direction@ch-chalonsenchampagne.fr;F;2020-10-04
510010499;association@arfo.fr;F;2020-10-04
510010630;contact@gham.fr;F;2020-10-04
510011018;residencelecedre@ville-eperney.fr;F;2020-10-04
510011976;direction-grand-jardin@groupe-sos.org;F;2020-10-04
510011984;reception.placeroyale@korian.fr;F;2020-10-04
510016009;lescharmilles.marpa@orange.fr;F;2020-10-04
510017478;marpa.les.sources@orange.fr;F;2020-10-04
510018278;accueil.loisy@villabeausoleil.com;F;2020-10-04
510022700;marpa6@wanadoo.fr;F;2020-10-04
510025604;accueil@lesourirechampenois.fr;F;2020-10-04
510025695;administration@msj51.fr;F;2020-10-04
510025844;association@arfo.fr;F;2020-10-04
510025851;association@arfo.fr;F;2020-10-04
520000381;ccas.residences.seniors@mairie-saintdizier.fr;F;2020-10-04
520001868;direction@chhm.fr;F;2020-10-04
520003385;marpa.residenceleslilas@gmail.com;F;2020-10-04
520780396;direction.mr.nogent@orange.fr;F;2020-10-04
520780420;mr.chateauvillain@wanadoo.fr;F;2020-10-04
520780453;ehpadpoissons@orange.fr;F;2020-10-04
520780461;mr.sommevoire@wanadoo.fr;F;2020-10-04
520781527;direction@ch-saintdizier.fr;F;2020-10-04
520781535;hopital@hl-wassy.fr;F;2020-10-04
520781543;hopital@hl-joinville.fr;F;2020-10-04
520781584;secretariat.direction@ch-chaumont.fr;F;2020-10-04
520781592;direction@hopitalbourbonne.fr;F;2020-10-04
520781733;secretariat-saint-augustin@groupe-sos.org;F;2020-10-04
520781741;foyereugeniebaudel@orange.fr;F;2020-10-04
520781766;direction-lien@groupe-sos.org;F;2020-10-04
520781774;ccas@ville-chaumont.fr;F;2020-10-04
520781782;ccas.residences.seniors@mairie-saintdizier.fr;F;2020-10-04
520782178;admissions@hopital-montier.com;F;2020-10-04
520782202;ehpadlangres@ch-langres.fr;F;2020-10-04
520783150;foyer.bourmont@gmail.com;F;2020-10-04
520783432;administration@ehpadvaldemeuse.fr;F;2020-10-04
520783614;direction@hopitalbourbonne.fr;F;2020-10-04
520783622;ehpadlangres@ch-langres.fr;F;2020-10-04
520784521;foyer.marie.pocard@orange.fr;F;2020-10-04
530002211;ehpadavaloirs@orange.fr;F;2020-10-15
530002260;secretariat.alexain@ehpad-marinbouille.fr;F;2020-10-04
530002278;administration@ehpadlavarenne.fr;F;2020-10-04
530002294;compta@polepaph.fr;F;2020-10-15
530002302;secretariat.mr.ballots@orange.fr;F;2020-10-04
530002310;administration@ehpadlacharmille.fr;F;2020-10-04
530002328;residence.levollier.bouere@wanadoo.fr;F;2020-10-04
530002344;mr.fougerolles-du-plessis@wanadoo.fr;F;2020-10-04
530002351;accueil@ehpadsaintlaurennt.com;F;2020-10-04
530002369;residencevillagefleuri@wanadoo.fr;F;2020-10-04
530002377;contact@ehpad-landivy.fr;F;2020-10-04
530002393;secretariat.martigne@ladouceurdevivre.fr;F;2020-10-04
530002419;mrmontenay@wanadoo.fr;F;2020-10-04
530002427;secretariat.montsurs@ladouceurdevivre.fr;F;2020-10-04
530002435;accueil@ehpadlacolmont.fr;F;2020-10-04
530002443;administration@ehpadlaversale.fr;F;2020-10-04
530002476;accueil.bellevue@orange.fr;F;2020-10-04
530002518;ehpad@ehpadjavron.fr;F;2020-10-04
530002534;mrvaiges@orange.fr;F;2020-10-04
530002674;mairie.stouen@wanadoo.fr;F;2020-10-04
530003409;residence.hestia@laval.fr;F;2020-10-04
530003441;foyerlogementrenaze@orange.fr;F;2020-10-04
530003938;marpa.chatillonsurcolmont@orange.fr;F;2020-10-04
530005818;direction@misericorde-laval.fr;F;2020-10-04
530006758;residence@perrine-thulard.org;F;2020-10-04
530007079;foyerlogementquelaines@orange.fr;F;2020-10-04
530009034;residence.ferrie@laval.fr;F;2020-10-04
530029164;direction@misericorde-laval.fr;F;2020-10-04
530029198;mrsoulgesurouette@wanadoo.fr;F;2020-10-04
530029297;direction.laresidence@orange.fr;F;2020-10-04
530029305;residence.epine@laval.fr;F;2018-05-30
530029313;residence.bonaccueil-ehpad@orange.fr;F;2020-10-04
530029321;residenceeugenemarie@gmail.com;F;2020-10-04
530029347;ehpad.stberthevin@orange.fr;F;2020-10-04
530030170;direction@hopitallocal-evron.fr;F;2020-10-04
530031350;direction@hopitalvillaines.com;F;2020-10-04
530031368;direction@hopitallocal-evron.fr;F;2020-10-04
530031376;direction@ch-mayenne.fr;F;2020-10-04
530031384;direction@ch-mayenne.fr;F;2020-10-04
530031764;residence.jacquelin@ville-ernee.fr;F;2020-10-04
530032739;accueil@hlsom.com;F;2020-10-04
530032754;direction@ch-ernee.fr;F;2020-10-04
530032762;accueil@hlsom.com;F;2020-10-04
530032770;accueil@hlsom.com;F;2020-10-04
530032960;foyerlacroixille@orange.fr;F;2020-10-04
530032978;ccas.bonchamp@orange.fr;F;2020-10-04
530033067;direction@ch-mayenne.fr;F;2020-10-04
530033133;administration.lecastelli@korian.fr;F;2020-10-06
530033257;mairie.chailland@wanadoo.fr;F;2020-10-04
530033273;ccaslehorps@wanadoo.fr;F;2020-10-04
530033380;marpa.ballee@orange.fr;F;2020-10-04
530033547;direction@ch-mayenne.fr;F;2020-10-04
540000775;secretariat-lilas@groupe-sos.org;F;2020-10-04
540000791;contact@ehpad-quinquet.fr;F;2020-10-04
540002342;secretariat@ehpad-vezelise.fr;F;2020-10-04
540002466;mrrosieres@wanadoo.fr;F;2020-10-04
540002557;direction@hli-3hsante.fr;F;2020-10-04
540002573;secretariat@mr-gerbeviller.fr;F;2020-10-04
540002599;secretariat.direction@hopital-pompey.fr;F;2020-10-04
540002607;contact@ehpad-stlouis.fr;F;2020-10-04
540002623;mdr.stfrancoisassise@wanadoo.fr;F;2020-10-04
540002631;mrthiaucourt.direction@orange.fr;F;2020-10-04
540003118;accueilstremy@fondationsaintcharlesnancy.fr;F;2020-10-04
540003126;accueilstefamille@fondationsaintcharlesnancy.fr;F;2020-10-04
540003142;accueilstetherese@fondationsaintcharlesnancy.fr;F;2020-10-04
540003498;accueil@mdrsaintjoseph.fr;F;2020-10-04
540004363;secretariat.direction@hopital-pompey.fr;F;2020-10-04
540004512;contact@mutuelle-sablons.fr;F;2020-10-04
540004579;secretariat-iris@groupe-sos.org;F;2020-10-04
540004611;accueil.poincare@mdr.fvdp.org;F;2020-10-04
540004942;ccas@ville-laneuveville-devant-nancy.fr;F;2020-10-04
540004983;residence.crosmarie@mairie-toul.fr;F;2020-10-04
540005063;residencechevarde@mairie-nancy.fr;F;2020-10-04
540005071;residencemouilleron@mairie-nancy.fr;F;2020-10-04
540005097;residenceboudonville@mairie-nancy.fr;F;2020-10-04
540005170;residence.douzain@mairie-toul.fr;F;2020-10-04
540005352;hopital@ch-pontamousson.fr;F;2020-10-04
540005360;direction@hli-3hsante.fr;F;2020-10-04
540005543;foyer@blenod.com.fr;F;2020-10-04
540005592;foyer.clerbout@neuves-maisons.fr;F;2020-10-04
540006061;mairie@pompey.fr;F;2020-10-04
540006137;secretariat@ville-badonviller.fr;F;2020-10-04
540006418;residence.picquot@mairie-toul.fr;F;2020-10-04
540006459;secretariat.usld.st@chu-nancy.fr;F;2020-10-04
540006608;direction@ch-toul.fr;F;2020-10-15
540006657;direction@ch-saint-nicolas.fr;F;2020-10-04
540006665;direction@hli-3hsante.fr;F;2020-10-04
540006673;direction@hli-3hsante.fr;F;2020-10-04
540006772;direction@ch-luneville.fr;F;2020-10-04
540006780;direction@ch-luneville.fr;F;2020-10-04
540008208;direction@ehpadleparc.fr;F;2020-10-04
540008232;administration@hibiscusresidence.com;F;2020-10-04
540008281;contact@mairie-heillecourt.fr;F;2020-10-04
540008364;direction@ch-toul.fr;F;2020-10-04
540008372;accueilstsauveur@fondationsaintcharlesnancy.fr;F;2020-10-04
540008703;accueil.baschateau@mdr.fvdp.org;F;2020-10-04
540008737;direction@ch-saint-nicolas.fr;F;2020-10-04
540009024;accueil@villa-sp-fourier.com;F;2020-10-04
540009479;direction@epsfaulx.com;F;2020-10-04
540009826;residencepichon@mairie-nancy.fr;F;2020-10-04
540009834;residencedonop@mairie-nancy.fr;F;2020-10-04
540009917;direction@asspo.fr;F;2020-10-04
540009966;directionbaccarat@free.fr;F;2020-10-04
540012747;direction@mhb-baccarat.fr;F;2020-10-04
540013232;secretariat.usld.st@chu-nancy.fr;F;2020-10-04
540013323;reception.plaisance@korian.fr;F;2020-10-04
540018488;direction-michel-dinet@groupe-sos.org;F;2020-10-04
540018975;secretariat@mr-verriere.fr;F;2020-10-04
540018983;direction@atnf.fr;F;2020-10-04
540019239;accueildejourles3rivieres@fede54.admr.org;F;2020-10-04
540019247;secretariat.direction@hopital-pompey.fr;F;2020-10-04
540020807;secretariat-clairiere@groupe-sos.org;F;2020-10-04
540023389;ehpad.homecourt@ohs.asso.fr;F;2020-10-04
540024510;direction@ahj.fr;F;2020-10-04
550000079;contact@ehpadargonne.fr;F;2020-10-04
550000087;maison-de-retraite.stenay@wanadoo.fr;F;2020-10-04
550000210;direction@mr-vaucouleurs-void.fr;F;2020-10-04
550002216;contact@ehpaddun.fr;F;2020-10-04
550002224;administration@mretain.fr;F;2020-10-04
550002232;direction@mr-gondrecourt.fr;F;2020-10-04
550002257;contact@ehpaddargonne.fr;F;2020-10-04
550002265;residencedidon@orange.fr;F;2020-10-04
550002273;contact@ehpaddargonne.fr;F;2020-10-04
550002281;direction-void@mr-vaucouleurs-void.fr;F;2020-10-04
550003321;gerontologie@pssm.fr;F;2020-10-04
550003370;hopital@ch-saint-mihiel.fr;F;2020-10-04
550003602;ehpad.blanpain@barleduc.fr;F;2020-10-04
550003610;contact55@alys.fr;F;2020-10-04
550003628;contact55@alys.fr;F;2020-10-04
550003701;foyer.logements.coquillottes@cias.meusegrandsud.fr;F;2020-10-04
550003727;contact@maison-retraite-barat-dupont.fr;F;2020-10-04
550003826;residence@commercy.fr;F;2020-10-04
550004592;ehpad.couchot@barleduc.fr;F;2020-10-04
550004634;secretariatdirection@ch-verdun.fr;F;2020-10-04
550005177;secretariatdirection@ch-verdun.fr;F;2020-10-04
550005250;ehpadsaintgeorges@ohs.asso.fr;F;2020-10-04
550005581;direction@pssm.fr;F;2020-10-04
550006340;gerontologie@pssm.fr;F;2020-10-04
550006357;secretariat.triaucourt@ehpad-les-eaux-vives.fr;F;2020-10-04
550006365;secretariat.souilly@ephad-les-eaux-vives.fr;F;2020-10-04
550006373;secretariat.pierrefitte@ephad-les-eaux-vives.fr;F;2020-10-04
550006829;ehpadspincourt@orange.fr;F;2020-10-04
560000267;la-chaumiere-accueil@mrlachaumiere.fr;F;2020-10-04
560002230;contact@leclosdesgrandschenes.com;F;2020-10-04
560002248;secretariat@tiaieul.fr;F;2020-10-04
560002271;contact@esms-ferel.fr;F;2020-10-04
560002297;accueil@papillondor.net;F;2020-10-04
560002305;direction-oceane56@orange.fr;F;2020-10-04
560002313;mdrnoyalpontivy@yahoo.fr;F;2020-10-04
560002321;mrquestembert@wanadoo.fr;F;2020-10-04
560002339;accueil@ehpad-quiberon.fr;F;2020-10-04
560002370;ehpad@ehpad-allaire.fr;F;2020-10-15
560002396;administration@ehpad-guer.fr;F;2020-10-04
560003626;accueil@residences-mareva.fr;F;2020-10-04
560003923;mapa@sarzeau.fr;F;2020-10-04
560004202;contact@angel56.fr;F;2020-10-04
560004301;secretariat-direction@hl-lepalais.fr;F;2020-10-04
560004368;accueil@kerlaouen.com;F;2020-10-04
560004756;ehpad@mairie-vannes.fr;F;2020-10-04
560004764;residence.pasteur@mairie-vannes.fr;F;2020-10-04
560004798;secretariat.direction@ch-centre-bretagne.fr;F;2020-10-04
560004830;residence.autonomie@arzon.fr;F;2020-10-04
560004871;foyer.logement.carentoir@wanadoo.fr;F;2020-10-04
560004889;foyerlogement-carnac@orange.fr;F;2020-10-04
560004905;residencedelanvaux@wanadoo.fr;F;2020-10-04
560004913;residenceautonomie.guemene56@orange.fr;F;2020-10-04
560004921;ehpadgroix@orange.fr;F;2020-10-04
560004947;contactehpad@mairie-hennebont.fr;F;2020-10-04
560004970;foyerresidencekerderff@orange.fr;F;2020-10-04
560004988;ehpadleglouahec@gmail.com;F;2020-10-04
560005092;foyer-logement-malestroit@wanadoo.fr;F;2020-10-04
560005118;ehpad.meneac@orange.fr;F;2020-10-04
560005142;residence.autonomie@ccas-nivillac.fr;F;2020-10-04
560005159;ehpadsaintantoine@ploermel.bzh;F;2020-10-04
560005183;residencelesdunes@ville-quiberon.fr;F;2020-10-04
560005449;accueil.joachim@orange.fr;F;2020-10-04
560005472;asso.lann-eol@wanadoo.fr;F;2020-10-04
560005613;secretariat.direction@hlguemene.fr;F;2020-10-04
560006488;ehpad-lecoutaller@ville-lanester.fr;F;2020-10-04
560006520;foyer.logement.plumeliau@wanadoo.fr;F;2020-10-04
560006553;ehpadtremer@orange.fr;F;2020-10-04
560006652;secretariat.direction@ghbs.bzh;F;2020-10-04
560006702;secretariat.direction@chbi.fr;F;2020-10-04
560006710;secretariat@hopital-faouet.fr;F;2020-10-04
560006736;contact@ch-nivillac.fr;F;2020-10-04
560006751;accueil@hl-josselin.fr;F;2020-10-04
560006777;ehpad@hopital-carentoir.fr;F;2020-10-04
560006785;secretariat-ehpad.pratel@ch-bretagne-atlantique.fr;F;2020-10-04
560006819;ehpadlanguidic@orange.fr;F;2020-10-04
560007593;foyerlogement.questembert@orange.fr;F;2020-10-04
560007742;residence.autonomie.guer@gmail.com;F;2020-10-04
560007767;directioncurie@ploemeur.net;F;2020-10-04
560009219;accueil1.villatohannic@lna-sante.com;F;2020-10-04
560009250;directionpluvigner@orange.fr;F;2020-10-04
560009565;accueil.kerneth@arradon.fr;F;2020-10-04
560009615;secretariat.direction@ch-centre-bretagne.fr;F;2020-10-04
560009649;accueil@residences-mareva.fr;F;2020-10-04
560009664;residencedumidi@wanadoo.fr;F;2020-10-04
560009672;residence.lapeupleraie@orange.fr;F;2020-10-04
560009904;ehpad@saint-ave.fr;F;2020-10-04
560010076;residence-accueil@lefaouet.fr;F;2020-10-04
560010084;residence.leonvinet.ileauxmoines@orange.fr;F;2020-10-04
560011777;mapapleucadeuc@mutualite29-56.fr;F;2020-10-04
560011876;mapa.leroc@orange.fr;F;2020-10-04
560011892;saintmarcel.mairie@wanadoo.fr;F;2020-10-04
560012148;mapaploerdut@mutualite29-56.fr;F;2020-10-04
560012189;mapaguern@mutualite29-56.fr;F;2020-10-04
560012239;residence-anne-de-bretagne@wanadoo.fr;F;2020-10-04
560012254;marpamerlevenez@gmail.com;F;2020-10-15
560012270;mapamoreac@mutualite29-56.fr;F;2020-10-04
560012346;residence-plaisance@orange.fr;F;2020-10-04
560015372;direction@ehpad-rozavel.fr;F;2020-10-04
560015406;mapa.lavraiecroix@orange.fr;F;2020-10-04
560015414;mapapleugriffet@mutualite29-56.fr;F;2020-10-04
560017899;mapaplescop@mutualite29-56.fr;F;2020-10-04
560023186;contact.ledivit@ajl.asso.fr;F;2020-10-04
560023988;ehpad.kervenanec@mairie-lorient.fr;F;2020-10-04
560024036;accueil@barr-heol.fr;F;2020-10-04
560024549;direction@ghbs.bzh;F;2020-10-04
560024648;secretariat-ehpad.pratel@ch-bretagne-atlantique.fr;F;2020-10-04
560024887;residence.teretmer@ploemeur.net;F;2020-10-04
560025660;laresidencedesormes@orange.fr;F;2020-10-04
560025686;secretariat.direction@ghbs.bzh;F;2020-10-04
560025892;mapaplouhinec@mutualite29-56.fr;F;2020-10-04
560026395;accueil.oceane@lenobleage.fr;F;2020-10-04
570000463;secretariat-chenes@groupe-sos.org;F;2020-10-04
570000802;maisonretraite.vic@wanadoo.fr;F;2020-10-04
570000927;secretariat-saint-joseph@groupe-sos.org;F;2020-10-04
570001081;contact@lavacquiniere.fr;F;2020-10-04
570001107;secretariat@lavacquiniere.fr;F;2020-10-04
570001867;secretariat@epsgorze.fr;F;2020-10-04
570002105;direction-ehpad@aofpah.fr;F;2020-10-04
570002311;direction@ehpad-steveronique.fr;F;2020-10-04
570002360;mdrdelasalle.metz@cegetel.net;F;2020-10-04
570003418;secretariat-mirabelliers@groupe-sos.org;F;2020-10-04
570003459;secretariat-cerisiers@groupe-sos.org;F;2020-10-04
570003749;secretariat-alisiers@groupe-sos.org;F;2020-10-04
570003947;secretariat.direction@hpdir-metz.fr;F;2020-10-04
570004291;secretariat.stvincent@mdr.fvdp.org;F;2020-10-04
570004341;secretariat-cedres@groupe-sos.org;F;2020-10-04
570004390;secretariat-oliviers@groupe-sos.org;F;2020-10-04
570004416;secretariat@ndblauberg.fr;F;2020-10-04
570004424;direction-ste-madeleine57@orange.fr;F;2020-10-04
570004457;secretariat.direction@unisante.fr;F;2020-10-04
570004663;association.stchristophe@astc.fr;F;2020-10-04
570005298;residence-ste-madeleine57@orange.fr;F;2020-10-04
570005363;accueil@amli.asso.fr;F;2020-10-04
570005371;accueil@amli.asso.fr;F;2020-10-04
570005421;accueil@amli.asso.fr;F;2020-10-04
570005439;accueil@amli.asso.fr;F;2020-10-04
570008425;residence-ste-barbe@aofpah.fr;F;2020-10-04
570009787;residencemyosotis-bitche@wanadoo.fr;F;2020-10-04
570009829;residence.du.centre@orange.fr;F;2020-10-04
570009993;direction@ehpad-lacharmille.fr;F;2020-10-04
570010009;residence.schweitzer@wanadoo.fr;F;2020-10-04
570010058;info@residence-chatrian.fr;F;2020-10-04
570011932;residence.leslilas@orange.fr;F;2020-10-04
570012690;mapa@nerim.fr;F;2020-10-04
570013078;secretariat-charmes@groupe-sos.org;F;2020-10-04
570013102;direction-acacias@groupe-sos.org;F;2020-10-04
570013128;contact@mrph.fr;F;2020-10-04
570013151;direction.saint-joseph.jouy@nerim.fr;F;2020-10-04
570013565;ehpad-clervant@fondationbompard.asso.fr;F;2020-10-04
570013656;secretariat-les-peupliers@groupe-sos.org;F;2020-10-04
570013680;direction@morlanne.fr;F;2020-10-04
570013714;secretariat-tournebride@groupe-sos.org;F;2020-10-04
570013771;ehpad.heureuse@amapa.fr;F;2020-10-04
570013789;mdr.stechretienne@wanadoo.fr;F;2020-10-04
570014126;residence-du-parc2@wanadoo.fr;F;2020-10-04
570014159;ehpad@vds57.fr;F;2020-10-04
570014209;direction-castel@groupe-sos.org;F;2019-07-19
570014381;secretariat-hetre-pourpre@groupe-sos.org;F;2020-10-04
570014605;secretariat-tilleuls@groupe-sos.org;F;2020-10-04
570014639;secretariat-platanes@groupe-sos.org;F;2020-10-04
570014688;accueil.amanvillers@free.fr;F;2020-10-04
570014712;secretariat.glycines@theras-sante.fr;F;2020-10-04
570014852;secretariat-erables@groupe-sos.org;F;2020-10-04
570014886;secretariat.stpierre@theras-sante.fr;F;2020-10-04
570015073;secretariat-belvedere@groupe-sos.org;F;2020-10-04
570015198;secretariat-saules@groupe-sos.org;F;2020-10-04
570015297;secretariat-source-du-breuil@groupe-sos.org;F;2020-10-04
570015438;prevert.direction@amapa.fr;F;2020-10-04
570015768;ehpad.vignelles.secretariat@amapa.fr;F;2020-10-04
570015818;secretariat-pins@groupe-sos.org;F;2020-10-04
570015834;direction.vaxy@groupecolisee.fr;F;2020-10-04
570016014;secretariat.direction@ch-sarrebourg.fr;F;2020-10-04
570021964;ehpad.pepiniere.secretariat@amapa.fr;F;2020-10-04
570022376;direction@ahom.fr;F;2020-10-04
570022681;secretariat-sequoias@groupe-sos.org;F;2020-10-04
570022707;secretariat-closfleuri@groupe-sos.org;F;2020-10-04
570022905;ehpad-hygie@fondation-bompard.asso.fr;F;2020-10-04
570023192;accueil.lekem@alpha-sante.fr;F;2020-10-04
570023374;ehpad.acacias.direction@amapa.fr;F;2020-10-04
570023416;secretariat-lauriers@groupe-sos.org;F;2020-10-04
570023564;direction-coquelicots@groupe-sos.org;F;2020-10-04
570023572;secretariat-kissel@groupe-sos.org;F;2020-10-04
570023598;direction@villadavril.fr;F;2020-10-04
570023853;secretariat.direction@hpdir-metz.fr;F;2020-10-04
570023861;direction@ahom.fr;F;2020-10-04
570023879;accueil.lekem@groupe-sos.org;F;2020-10-04
570023887;secretariat-witten@groupe-sos.org;F;2020-10-04
570023952;secretariat-foret@groupe-sos.org;F;2020-10-04
570024000;direction-sources@groupe-sos.org;F;2020-10-04
570024018;secretariat.direction@hpdir-metz.fr;F;2020-10-04
570024075;secretariat@epsgorze.fr;F;2020-10-04
570024125;direction@ch-lorquin.fr;F;2020-10-04
570024547;info@leprieuredelafensch.fr;F;2020-10-04
570024711;secretariat-plateau@groupe-sos.org;F;2020-10-04
570024844;direction.stjulienlesmetz@groupecolisee.com;F;2020-10-04
570027128;accueil.boulay@villabeausoleil.com;F;2020-10-04
570027391;direction-ehpad@aofpah.fr;F;2020-10-04
580000768;st-genest.direction@arpavie.fr;F;2020-10-04
580000974;direction@ch-nevers.fr;F;2020-10-04
580004919;contact@champdeladame.fr;F;2020-10-04
580005585;direction@csbazois.org;F;2020-10-04
580780724;direction@ehpadvarzy.fr;F;2020-10-04
580780849;mrachun@wanadoo.fr;F;2020-10-04
580780872;contact@ehpad-sudmorvan.fr;F;2020-10-04
580781052;ehpad@mr-cosac.com;F;2020-10-04
580781144;secretariat.direction@chhd-lacharite.fr;F;2020-10-04
580781185;direction.nevers@agepartenaires.com;F;2020-10-04
580782100;secretariat-clos@groupe-sos.org;F;2020-10-04
580782134;direction@ch-decize.fr;F;2020-10-04
580970119;direction@hopital-cosne.fr;F;2020-10-04
580970473;ehpadentrains@coallia.org;F;2020-10-04
580970994;secretariat.direction@chhd-lacharite.fr;F;2020-10-04
580971026;direction@hopital-cosne.fr;F;2020-10-04
580971034;direction@ch-nevers.fr;F;2020-10-04
580971133;ehpad.daniel-benoist@ville-nevers.fr;F;2020-10-04
580971299;accueil@lesjardinsdeslaignes.fr;F;2020-10-04
580971588;administration@cls-st-pierre.fr;F;2020-10-04
580971620;secretariat-feuillantines@groupe-sos.org;F;2020-10-04
580971646;direction@ch-nevers.fr;F;2020-10-04
580972016;direction@ch-nevers.fr;F;2020-10-04
580972131;residenceberegovoy@orange.fr;F;2020-10-04
580972149;les-colchiques.ehpad@wanadoo.fr;F;2020-10-04
580972529;mapad@ville-varennes-vauzelles.fr;F;2020-10-04
580972594;secretariat@ehpadmillay.fr;F;2020-10-04
580972719;administration@cls-st-pierre.fr;F;2020-10-04
590001749;contact@polyclinique-grande-synthe.com;F;2020-10-04
590006862;infoehpadccas@mairie-lille.fr;F;2020-10-04
590007266;direction.villeneuve@lesorchidees.fr;F;2020-10-04
590007373;contact@residence-domaine-du-lac.com;F;2020-10-04
590010468;gerontologie@ch-tourcoing.fr;F;2020-10-04
590013959;infoehpadccas@mairie-lille.fr;F;2020-10-04
590014999;secretariat-tulipiers@groupe-sos.org;F;2020-10-04
590020269;ccas-espacebelair@wanadoo.fr;F;2020-10-04
590020608;contact@residencearagon.fr;F;2020-10-04
590020848;contact@les-feuillantines.com;F;2020-10-04
590020988;ehpad_les_charmilles@ville-saint-saulve.fr;F;2020-10-04
590025268;residenceduparc2@wanadoo.fr;F;2020-10-04
590025599;accueil.jour@ville-mons-en-baroeul.fr;F;2020-10-04
590026209;contact@acces-asso.fr;F;2020-10-04
590032959;accueildejourlamenie@gmail.com;F;2020-10-04
590033957;contact.tourcoing@lesorchidees.fr;F;2020-10-04
590034617;contact@leslysduhainaut.com;F;2020-10-04
590034898;direction@ghlh.fr;F;2020-10-04
590034997;contact@apreva-rms.fr;F;2020-10-04
590035002;contact@apreva-rms.fr;F;2020-10-04
590035010;contact@apreva-rms.fr;F;2020-10-04
590035341;infoehpadccas@mairie-lille.fr;F;2020-10-04
590035366;gerontologie@ch-tourcoing.fr;F;2020-10-04
590035945;infoehpadccas@mairie-lille.fr;F;2020-10-04
590037719;contact@acces-asso.fr;F;2020-10-04
590037727;secretariat-magnolias@groupe-sos.org;F;2020-10-04
590037768;contact-ehpad@ville-ronchin.fr;F;2020-10-04
590037909;contact@ehpad-4vents.fr;F;2020-10-04
590038097;infoehpadccas@mairie-lille.fr;F;2020-10-04
590038238;accueil.godenettes@cdesages.com;F;2020-10-04
590038279;accueiljour.roses@orange.fr;F;2020-10-04
590038568;secretariat.reinedespres@orpea.net;F;2020-10-04
590039798;ehpad.neuville@floralys.fr;F;2020-10-04
590039822;ehpad.douai@floralys.fr;F;2020-10-04
590039889;residence.roses@orange.fr;F;2020-10-04
590043261;contact@maison-pays-cousolre.com;F;2020-10-04
590045555;accueil@paul-cordonnier.fr;F;2020-10-04
590045605;accueil@ehpad-leers.fr;F;2020-10-04
590046801;contact@apreva-rms.fr;F;2020-10-04
590046819;contact@apreva-rms.fr;F;2020-10-04
590046827;contact@apreva-rms.fr;F;2020-10-04
590046934;direction.villereau@sgmr-ouest.com;F;2020-10-04
590047023;contact@lesjardinsdessens.net;F;2020-10-04
590047700;reception.samara@korian.fr;F;2020-10-04
590048039;residence.isabeau@ch-roubaix.fr;F;2020-10-04
590048054;ehpad@ch-somain.fr;F;2020-10-04
590048062;gerontologie@ch-tourcoing.fr;F;2020-10-04
590048070;direction@ch-wasquehal.fr;F;2020-10-04
590048104;residence.fraternite@ch-roubaix.fr;F;2020-10-04
590048294;maisondesdunes.ccasdunkerque@orange.fr;F;2020-10-04
590049037;direction@ch-lequesnoy.fr;F;2020-10-04
590049656;accueiljour@ccas-tourcoing.fr;F;2020-10-04
590050340;gerontologie@ch-tourcoing.fr;F;2020-10-04
590057006;ehpadritournelle@afeji.org;F;2020-10-04
590782751;mrestaires@orange-business.fr;F;2020-10-04
590782769;residence.bouchery@wanadoo.fr;F;2020-10-04
590782777;ehpad.pontbertin@probtp.com;F;2020-10-04
590782785;residencedebeaupre@wanadoo.fr;F;2020-10-04
590782801;mrmerville@wanadoo.fr;F;2020-10-04
590782827;secretariat@ehpad-morbecque.com;F;2020-10-04
590782868;vieux-berquin.mr@wanadoo.fr;F;2020-10-04
590782991;direction@ehpadhondschoote.fr;F;2020-10-04
590783262;ehpad.villasenecta@wanadoo.fr;F;2020-10-04
590783270;accueil@ehpadintercommunal.fr;F;2020-10-04
590783288;mr.bollezeele@wanadoo.fr;F;2020-10-04
590783296;contact@ehpad-bondues.fr;F;2020-10-04
590783304;direction@ehpad-dronsart.fr;F;2020-10-04
590783312;administration@ehpadbourbourg.fr;F;2020-10-15
590783346;resid.hautsdeflandre@wanadoo.fr;F;2020-10-04
590783353;contact@ehpad-paysdeconde.fr;F;2020-10-04
590783361;secretariat.lesogiers@orange.fr;F;2020-10-04
590783379;pevele.secretariat2@gmail.com;F;2020-10-04
590783395;mdr.esquelbecq@wanadoo.fr;F;2020-10-04
590783411;administration@loreedumont.fr;F;2020-10-04
590783429;contact@lesaulnes-hem.fr;F;2020-10-04
590783437;contact@ehpad-herlies.fr;F;2020-10-04
590783445;direction@ehpad-landrecies.fr;F;2020-10-15
590783460;residence.forestier@orange.fr;F;2020-10-04
590783486;accueil@provincesdunord.fr;F;2020-10-04
590783494;direction@ch-saint-amand-les-eaux.fr;F;2020-10-04
590783502;contact@ehpad-mouvaux.fr;F;2020-10-04
590783551;contact@ehpad-sainghin.fr;F;2020-10-04
590783577;direction@ehpad-solesmes.fr;F;2020-10-04
590783593;pevele.secretariat@gmail.com;F;2020-10-04
590783601;residence@cheminvert-trelon.fr;F;2020-10-04
590783619;residence.obert.wambrechies@wanadoo.fr;F;2020-10-04
590783635;direction@ch-wasquehal.fr;F;2020-10-04
590783817;foyerlongchamp@mairie-lyslezlannoy.com;F;2020-10-04
590783882;contact@ccas-roubaix.fr;F;2020-10-04
590783965;ehpadmoulin@villeneuvedascq.fr;F;2020-10-04
590783981;residencedelaroseliere@ville-wattrelos.fr;F;2020-10-04
590785713;contact@lescharmettes.org;F;2020-10-04
590785721;ehpadaccueil@ghicl.net;F;2020-10-04
590786976;direction@ch-saint-amand-les-eaux.fr;F;2020-10-04
590787271;ehpad.arleux@floralys.fr;F;2020-10-04
590787289;accueilehpad@aulnoye-aymeries.fr;F;2020-10-04
590787297;ccas.cambrai@orange.fr;F;2020-10-04
590787313;accueillogis@mav.asso.fr;F;2020-10-04
590787321;ehpad.fechain@floralys.fr;F;2020-10-04
590787347;residence.autonomie@fourmies.fr;F;2020-10-04
590787362;contact@acces-asso.fr;F;2020-10-04
590787842;ccas.vaneeghem@orange.fr;F;2020-10-04
590787909;foyerbeausejour@auby.fr;F;2020-10-04
590788030;accueil.ehpad@ville-mons-en-baroeul.fr;F;2020-10-04
590788352;ehpad.standre@tempsdevie.fr;F;2020-10-15
590788378;residencedelahouzarde@ville-wattrelos.fr;F;2020-10-04
590788444;mdr.desainthilaire@wanadoo.fr;F;2020-10-04
590788493;accueilmerici@wanadoo.fr;F;2020-10-04
590788683;contact@feron-vrau.com;F;2020-10-04
590789848;residence.beaupre@haubourdin.fr;F;2020-10-04
590789897;mdrstegenevieve@orange.fr;F;2020-10-04
590789905;residence.van.kempen@wanadoo.fr;F;2020-10-15
590789947;mdr.desainthilaire@wanadoo.fr;F;2020-10-04
590789962;residencelesmarronniers@univi.fr;F;2020-10-04
590789970;residenceclairbois@poleemmah.fr;F;2020-10-04
590790002;residencelebosquet@poleemmah.fr;F;2020-10-04
590790010;secretariat@notredamedesanges.org;F;2020-10-04
590790101;ehpad.maisondesroses@amapa.fr;F;2020-10-04
590790119;ehpad.maubeuge@tempsdevie.fr;F;2020-10-04
590790531;direction@sapinsbleusperenchies.fr;F;2020-10-04
590791315;direction@ch-armentieres.fr;F;2020-10-04
590792537;residence.quietude@ville-wasquehal.fr;F;2020-10-04
590794343;secretariat@latreille.org;F;2020-10-04
590796561;foyer@ville-raismes.fr;F;2020-10-04
590796603;residence.lille@tempsdevie.fr;F;2020-10-04
590796942;contact@residenceduparc.fr;F;2020-10-04
590797064;accueil.cedres@ville-mons-en-baroeul.fr;F;2020-10-04
590797072;direction@ledomainedelariviere.fr;F;2020-10-15
590797338;foyer.soleil0993@orange.fr;F;2020-10-04
590801601;contact@residence-les-oyats.fr;F;2020-10-04
590801619;residence-bajart@ch-lequesnoy.fr;F;2020-10-04
590801627;accueil@residence-saint-jean.fr;F;2020-10-15
590804233;accueil@hopital-comines.fr;F;2020-10-04
590804274;direction@ch-armentieres.fr;F;2020-10-04
590804290;secretariat.usld@ch-avesnes.fr;F;2020-10-04
590804308;secretariat.ehpad@ch-avesnes.fr;F;2020-10-04
590804316;direction@ch-bailleul.fr;F;2020-10-04
590804381;direction@ghlh.fr;F;2020-10-14
590804399;direction@ch-hautmont.fr;F;2020-10-04
590804407;direction@ch-hautmont.fr;F;2020-10-04
590804415;direction@ch-hazebrouck.fr;F;2020-10-04
590804431;direction@ch-labassee.fr;F;2020-10-04
590804449;direction.lesbateliers@chru-lille.fr;F;2020-10-04
590804456;direction@ghlh.fr;F;2020-10-04
590804480;secretariat.direction@ch-roubaix.fr;F;2020-10-04
590804498;direction@ch-saint-amand-les-eaux.fr;F;2020-10-04
590804548;usld@ch-somain.fr;F;2020-10-04
590804662;direction@ch-lequesnoy.fr;F;2020-10-04
590804969;ehpadorchies@orange.fr;F;2020-10-04
590805362;ehpad.maroilles@tempsdevie.fr;F;2020-10-04
590805412;accueil@paul-cordonnier.fr;F;2020-10-04
590805677;residence.roses@orange.fr;F;2020-10-04
590805685;ehpad@association-bethanie.fr;F;2020-10-04
590806337;residence.harmonie@ville-wasquehal.fr;F;2020-10-04
590806345;residenceduparc@ville-wattrelos.fr;F;2020-10-04
590806667;foyerlogement@ville-armentiers.fr;F;2020-10-04
590808812;contact@residence-les-hortensias.com;F;2020-10-04
590809067;reception.lesmarquises@korian.fr;F;2020-10-04
590809166;contact@acces-asso.fr;F;2020-10-04
590809554;accueiljeanmenu@mav.asso.fr;F;2020-10-04
590809570;contact@acces-asso.fr;F;2020-10-04
590811329;contact.croix@lesorchidees.fr;F;2020-10-04
590811485;direction@ch-wasquehal.fr;F;2020-10-04
590812095;contact@acces-asso.fr;F;2020-10-04
590812244;gerontologie@ch-tourcoing.fr;F;2020-10-04
590813523;direction2@r-gd.com;F;2020-10-04
590814141;direction-onze-villes@groupe-sos.org;F;2020-10-04
590814810;ehpad.flers@floralys.fr;F;2020-10-04
590814851;infoehpadccas@mairie-lille.fr;F;2020-10-04
590815023;ehpad.residencevalerie@gmail.com;F;2020-10-04
590815122;residence.weppes@croix-rouge.fr;F;2020-10-04
590815767;administration.abbaye@korian.fr;F;2020-10-04
590815882;contact.roubaix@lesorchidees.fr;F;2020-10-04
590815957;edilysaccueil@afeji.org;F;2020-10-04
590816286;secretariat.direction@arche-ambroise-pare.fr;F;2020-10-04
590816435;contact@leshautsdamandi.com;F;2020-10-04
590817375;contact.lannoy@lesorchidees.fr;F;2020-10-04
600001184;directiongrandvilliers@fr.oleane.com;F;2020-10-04
600001762;contact@residoise.fr;F;2020-10-04
600002638;contact@residoise.fr;F;2020-10-04
600008031;contact@residoise.fr;F;2020-10-04
600008049;contact@residoise.fr;F;2020-10-04
600008098;contact@residoise.fr;F;2020-10-04
600009542;contact@residoise.fr;F;2020-10-04
600009732;secretariat-genets@groupe-sos.org;F;2020-10-04
600010557;accueil.beauvaisis@orpea.net;F;2020-10-04
600011498;direction@hopital-pont-sainte-maxence.fr;F;2020-10-04
600012553;accueil@ch-crepyenvalois.fr;F;2020-10-04
600100564;accueil@fondation-conde.com;F;2020-10-04
600100622;contact@fondationdeberny.fr;F;2020-10-04
600100978;residence.saint-jacques@wanadoo.fr;F;2020-10-04
600101307;secretariat@mr-antilly.fr;F;2020-10-04
600101323;ehpad.bresles@orange.fr;F;2020-10-04
600101331;mr.breteuil@wanadoo.fr;F;2020-10-04
600101372;accueilehpad.mouy@gmail.com;F;2020-10-04
600101398;contact@mr-verberie.fr;F;2020-10-04
600101547;ehpad.attichy@tempsdevie.fr;F;2020-10-04
600102073;secretariat.domfront@lacompassion.fr;F;2020-10-04
600102461;accueil.plailly@groupecolisee.com;F;2020-10-04
600102602;contact@residence-de-la-foret.com;F;2020-10-04
600102636;ehpad.songeons@tempsdevie.fr;F;2020-10-04
600103105;secretariat.beauvais@lacompassion.fr;F;2020-10-04
600103196;info@mairie-creil.fr;F;2020-10-04
600103311;contact@residoise.fr;F;2020-10-04
600103337;contact@residoise.fr;F;2020-10-04
600103360;contact@residoise.fr;F;2020-10-04
600105225;accueil@ch-crepyenvalois.fr;F;2020-10-04
600105308;direction@ght-novo.fr;F;2020-10-04
600105381;accueil@fondation-conde.com;F;2020-10-04
600106165;contact@residoise.fr;F;2020-10-04
600106181;contact@residoise.fr;F;2020-10-04
600106199;contact@residoise.fr;F;2020-10-04
600106280;contact@residoise.fr;F;2020-10-04
600106785;secretariat@ch-grandvilliers.fr;F;2020-10-04
600107478;direction@ghpso.fr;F;2020-10-04
600107486;direction@ghpso.fr;F;2020-10-04
600107510;direction@ch-pont.fr;F;2020-10-04
600107536;direction@ch-chaumontenvexin.fr;F;2020-10-04
600107544;secretariat.direction@ch-clermont.fr;F;2020-10-04
600107551;secretariat.direction@ch-clermont.fr;F;2020-10-04
600107593;secretariat@hl-nanteuil.fr;F;2020-10-04
600107668;geriatrie.secretariat@ch-compiegnenoyon.fr;F;2020-10-04
600107890;usld@ch-crepyenvalois.fr;F;2020-10-04
600108187;contact@residoise.fr;F;2020-10-04
600108203;contact@residoise.fr;F;2020-10-04
600109367;contact@residoise.fr;F;2020-10-04
600109565;contact@residoise.fr;F;2020-10-04
600110092;contact@residoise.fr;F;2020-10-04
600110381;contact@residoise.fr;F;2020-10-04
600110480;contact@residoise.fr;F;2020-10-04
600110670;contact@lesjardinsdenampcel.fr;F;2020-10-04
600111041;geriatrie.secretariat@ch-compiegnenoyon.fr;F;2020-10-04
600111066;contact@closerie-des-tilleuls.com;F;2020-10-04
600111405;secretariatdirection@hl-crevecoeur.com;F;2020-10-04
600111827;contact@residence-lagedor.com;F;2020-10-04
600112072;contact@residoise.fr;F;2020-10-04
600112098;contact@residoise.fr;F;2020-10-04
600112502;contact@residoise.fr;F;2020-10-04
600112700;ccasdelamorlaye@orange.fr;F;2020-10-04
600112718;contact@residoise.fr;F;2020-10-04
600113690;contact@residoise.fr;F;2020-10-04
610002446;mairielasauvagere@wanadoo.fr;F;2020-10-04
610004798;contact@residence-la-vie.com;F;2020-10-04
610005449;reception.lediamant@korian.fr;F;2020-10-04
610006363;residence.opale@hom-age.fr;F;2020-10-04
610006488;contact@ehpad-putanges.com;F;2020-10-04
610006975;marpa-dupays-demortree@orange.fr;F;2020-10-04
610780777;ehpad.notredame@orange.fr;F;2020-10-04
610780967;direction.leshautsvents@orange.fr;F;2020-10-04
610781270;ehpad@mrsainteanne.fr;F;2020-10-04
610781338;residencefleurie@wanadoo.fr;F;2020-10-04
610781619;secretariat@saintemarie.asso.fr;F;2020-10-04
610782260;ehpad.cias@paysdelaigle.fr;F;2020-10-04
610784050;direction@ch-alencon.fr;F;2020-10-04
610784167;secretariat@ehpadandaine.fr;F;2020-10-04
610784175;maison.retraite.ecouche@wanadoo.fr;F;2020-10-04
610784191;secretariat@ehpadandaine.fr;F;2020-10-04
610784241;hopital@hopital-belleme.fr;F;2020-10-04
610784266;direction@ch-flers.fr;F;2020-10-04
610784498;sees.ehpad.direction@anais.asso.fr;F;2020-10-04
610784530;mr.occagnes@orange.fr;F;2020-10-04
610784639;direction@ch-argentan.fr;F;2020-10-04
610787111;mairieletheil61@wanadoo.fr;F;2020-10-04
610787137;ccas.saintescolasse@orange.fr;F;2020-10-04
610787319;direction@ch-laigle.fr;F;2020-10-04
610787376;admissions1@ch-mortagne.fr;F;2020-10-04
610787749;direction@ch-vimoutiers.fr;F;2020-10-04
610787814;direction@ch-laigle.fr;F;2020-10-04
610789091;mairie-chanu@wanadoo.fr;F;2020-10-04
610789869;residence.neyret@club-internet.fr;F;2020-10-04
610790248;direction@ehpad-laurentides.fr;F;2020-10-04
610790669;direction@ch-laigle.fr;F;2020-10-04
610790677;direction@ch-laigle.fr;F;2020-10-04
610790693;admissions1@ch-mortagne.fr;F;2020-10-04
620003277;secretariat@lesverrieres.fr;F;2020-10-04
620003285;ehpad.curie@sivom-bethunois.fr;F;2020-10-04
620003335;marpa.preures@wanadoo.fr;F;2020-10-04
620003632;ehpadlonguenesse@vieactive.asso.fr;F;2020-10-04
620003723;direction@ehpad-slb.fr;F;2020-10-04
620003905;geriatrie@gh-artoisternois.fr;F;2020-10-04
620004747;residence-les-4-saisons@wanadoo.fr;F;2020-10-04
620004762;stenhuis.direction@arpavie.fr;F;2020-10-04
620004846;accueil_oceane@ch.boulogne.fr;F;2020-10-04
620009068;ccas.residencesautonomie@etaples-sur-mer.net;F;2020-10-04
620016808;contact@les-jardins-de-lievin.com;F;2020-10-04
620017699;ehpad.gonnehem@gmail.com;F;2020-10-04
620017889;marpalabergerie@orange.fr;F;2020-10-04
620018044;ehpad.degeorge@sivom-bethunois.fr;F;2020-10-04
620018135;admissions.ehpad@calais.fr;F;2020-10-04
620018499;ehpad.audruicq@tempsdevie.fr;F;2020-10-15
620018663;residence.belle.fontaine@orange.fr;F;2020-10-04
620018820;secretariat.myosotis@bruaysis.fr;F;2020-10-04
620022749;ehpadmarles@vieactive.asso.fr;F;2020-10-04
620022848;ehpadpierremauroy@apreva-rms.fr;F;2020-10-04
620022939;direction@ehpad-b-devulder.fr;F;2020-10-04
620024448;accueil@ehpadleslilas.fr;F;2020-10-04
620024489;ehpadcoquelles@vieactive.asso.fr;F;2020-10-04
620024661;ehpadcourrieres@vieactive.asso.fr;F;2020-10-04
620024679;marpa@campagnesartois.fr;F;2020-10-04
620024778;marpalessources@orange.fr;F;2020-10-04
620024851;contact@stefamille-groupehouzel.fr;F;2020-10-04
620026104;accueil.oyeplage@groupecolisee.com;F;2020-10-04
620026112;direction.residence-lepaindalouette@fces.fr;F;2020-10-04
620026120;ehpadisbergues@vieactive.asso.fr;F;2020-10-04
620026187;geriatrie@gh-artoisternois.fr;F;2020-10-04
620026211;ch-hesdin@ch-hesdin.fr;F;2020-10-04
620027037;direction@ch-airelys.fr;F;2020-10-04
620027060;direction@ch-stomer.fr;F;2020-10-04
620027110;ehpadoignies@vieactive.asso.fr;F;2020-10-04
620027136;accueil.leforest@apreva-rms.fr;F;2020-10-04
620027391;marpa.novavilla@orange.fr;F;2020-10-04
620027573;geriatrie@gh-artoisternois.fr;F;2020-10-04
620029637;marpa-pays-de-lumbres1@orange.fr;F;2020-10-04
620030254;ehpad.boulogne@tempsdevie.fr;F;2020-10-04
620031369;direction@marpa-locon.fr;F;2020-10-04
620032888;direction@ch-airelys.fr;F;2020-10-04
620100065;direction@ehpad-lampin.fr;F;2020-10-04
620100867;ehpad.amettes@pandevie.fr;F;2020-10-04
620101857;directionarnoul@nordnet.fr;F;2020-10-04
620101873;mdr-aubigny@orange.fr;F;2020-10-04
620101915;mdrguines@wanadoo.fr;F;2020-10-04
620101923;ehpad.lestrem@wanadoo.fr;F;2020-10-04
620101964;accueil@ehpadcroisilles.fr;F;2020-10-04
620102269;direction@ndb-groupehouzel.fr;F;2020-10-15
620104927;foyerlogementadmr@orange.fr;F;2020-10-04
620104968;accueilccas@mairie-lillers.fr;F;2020-10-04
620105056;contact@residence-hermant.fr;F;2020-10-04
620105098;ehpadmarles@vieactive.asso.fr;F;2020-10-04
620105106;contact@ville-isbergues.fr;F;2020-10-04
620105171;ccasgerontologie@ville-boulogne-sur-mer.fr;F;2020-10-04
620105221;ehpadsaintalbert@gmail.com;F;2020-10-04
620105239;association.saint.camille@wanadoo.fr;F;2020-10-04
620105262;accueil.desvres@gmail.com;F;2020-10-04
620105270;ehpad.ecques@tempsdevie.fr;F;2020-10-04
620105288;ehpad.hardinghen@tempsdevie.fr;F;2020-10-04
620105296;ehpad.laventie@tempsdevie.fr;F;2020-10-04
620105304;directionlesmouettes@orange.fr;F;2020-10-04
620105312;st-nicolas-secretariat@accueiletrelais.fr;F;2020-10-04
620105429;residenceguymollet.asso@lavieactive.fr;F;2020-10-04
620105445;foyerleonblum@orange.fr;F;2020-10-04
620105510;residence.frachon@mairie-montigny.fr;F;2020-10-04
620105619;direction.lesgenetsdrocourt@gmail.com;F;2020-10-04
620105635;foyer-logement-frevent@orange.fr;F;2020-10-04
620105916;secretariat-stfrancois@alliance-ehpad.fr;F;2020-10-04
620106104;contact@chateau-cuinchy.com;F;2020-10-04
620106112;ehpadbouvigny@vieactive.asso.fr;F;2020-10-04
620106948;residence.henrihotte@mairie-mericourt.fr;F;2020-10-04
620108613;ccasgerontologie@ville-boulogne-sur-mer.fr;F;2020-10-04
620109769;direction@ccas-outreau.org;F;2020-10-04
620109777;ccasgerontologie@ville-boulogne-sur-mer.fr;F;2020-10-04
620109785;ccasgerontologie@ville-boulogne-sur-mer.fr;F;2020-10-04
620110973;admissions.ehpad@ch-calais.fr;F;2020-10-04
620110999;direction@ch-airelys.fr;F;2020-10-04
620111005;direction@ch-stomer.fr;F;2020-10-04
620111013;accueil-ehpad@ch-carvin.fr;F;2020-10-04
620111146;ch-hesdin@ch-hesdin.fr;F;2020-10-04
620111195;geriatrie@ch-arras.fr;F;2020-10-04
620114728;direction@ch-idac-camiers.fr;F;2020-10-04
620114868;ehpad.noyelles@ahnac.com;F;2020-10-04
620117226;contact@residence-vieille-eglise.com;F;2020-10-04
620117598;direction.mazingarbe@sgmr-ouest.com;F;2020-10-04
620117747;ehpad.delaby@ahnac.com;F;2020-10-04
620117754;ehpadnoyelles@vieactive.asso.fr;F;2020-10-04
620117762;ehpadsailly@vieactive.asso.fr;F;2020-10-04
620117960;resid.les.hauts.de.france@orange.fr;F;2020-10-04
620118133;ehpad.lens@orange.fr;F;2020-10-04
620118257;ehpadvimy@vieactive.asso.fr;F;2020-10-04
620118299;direction@ch-calais.fr;F;2020-10-04
620118505;direction@ch-henin.fr;F;2020-10-04
620118653;accueil@les-remparts-lillers.com;F;2020-10-04
620119206;mapad.edith-piaf@wanadoo.fr;F;2020-10-04
620119222;secretariat.elsatriolet@bruaysis.fr;F;2020-10-04
630002111;mapad@ceyrat.fr;F;2020-10-04
630002475;marpa.perignat@wanadoo.fr;F;2020-10-04
630002608;residence.chandalon@laposte.net;F;2020-10-04
630003218;direction@stjo-chamalieres.fr;F;2020-10-04
630003598;ehpad@cournon-auvergne.fr;F;2020-10-15
630005759;marpa.st-sauves@orange.fr;F;2020-10-04
630007169;contact@residence-des-oliviers.com;F;2020-10-04
630008209;ehpadmenat@paysdesainteloy.fr;F;2020-10-04
630008258;direction@ccas-clermont-ferrand.fr;F;2020-10-04
630008688;ccas.jardinalois63@gmail.com;F;2020-10-04
630009322;mr.pontgibaud@wanadoo.fr;F;2020-10-15
630009355;ehpadlafontaine@wanadoo.fr;F;2020-10-04
630009405;direction@ccas-clermont-ferrand.fr;F;2020-10-04
630009595;ehpad-stamantrochesavine@orange.fr;F;2020-10-04
630009686;administration.loradou@korian.fr;F;2020-10-04
630010031;secretariat@residence-paul-valery.com;F;2020-10-04
630010163;direction@ccas-clermont-ferrand.fr;F;2020-10-04
630011401;secretariat-lescampellis@sud-generations.fr;F;2020-10-04
630011682;ehpad.louispasteur@mairie-lempdes.fr;F;2020-10-04
630011716;residence.lesrivesdithaque@groupe-mieuxvivre.fr;F;2020-10-04
630012086;direction@ccas-clermont-ferrand.fr;F;2020-10-04
630180040;ehpad.bristol@wanadoo.fr;F;2020-10-04
630781037;contact@mr-aigueperse.fr;F;2020-10-04
630781151;contact@savarounes.fr;F;2020-10-04
630781227;direction@mrmonrepos.fr;F;2020-10-04
630781235;administration@mr-effiat.fr;F;2020-10-04
630781458;direction@ehpad-arlanc.fr;F;2020-10-04
630781474;mdr.courpiere@wanadoo.fr;F;2020-10-04
630781482;ehpadculhat@gmail.com;F;2020-10-04
630781490;accueil@ehpadmillesourires.fr;F;2020-10-04
630781516;ehpad.montaigut@wanadoo.fr;F;2020-10-04
630781524;accueil@mdrpionsat.fr;F;2020-10-04
630781532;ehpad-le-cedre@wanadoo.fr;F;2020-10-04
630781540;ehpad.tilleuls@orange.fr;F;2020-10-04
630781557;accueil@ehpad-ste-elisabeth.fr;F;2020-10-04
630781565;ehpadlemontel@orange.fr;F;2020-10-04
630781573;ehpad-leverger@orange.fr;F;2020-10-04
630781599;ehpadsauxillanges@orange.fr;F;2020-10-15
630781615;accueil@ehpadbargoin.fr;F;2020-10-04
630781623;secretariat@ehpad-viverols.fr;F;2020-10-04
630781631;ehpad.volvic@wanadoo.fr;F;2020-10-04
630783355;ehpad.lebosquet@cias.rlv.eu;F;2020-10-04
630783371;direction@ccas-clermont-ferrand.fr;F;2020-10-04
630783470;direction@ch-riom.fr;F;2020-10-04
630783488;direction@ch-ambert.fr;F;2020-10-04
630783504;direction@ch-thiers.fr;F;2020-10-04
630784478;ehpadlamisericorde@gmail.com;F;2020-10-04
630784510;accueil@lacolombe.eu;F;2020-10-04
630784544;mr.combronde@wanadoo.fr;F;2020-10-04
630784577;contact@residencejeannedarc.org;F;2020-10-04
630784676;ehpadsaintjoseph.lezoux@orange.fr;F;2020-10-04
630784775;secretariat.laprovidence@orange.fr;F;2020-10-04
630784783;accueil@ehpad-lasaintefamille.fr;F;2020-10-04
630784841;secretariat@ehpad-jeanson63.fr;F;2020-10-04
630784858;ehpadlatour@gmail.com;F;2020-10-04
630785269;foyer.logement.steloy@wanadoo.fr;F;2020-10-04
630785749;foyerlogement@paysdesainteloy.fr;F;2020-10-04
630785814;ehpad.villa.saint.jean@ccass-sbe.org;F;2020-10-04
630785962;secretariat@villaclaudine.fr;F;2020-10-04
630786119;residenceautonomie.lacascade@ccasissoire.fr;F;2020-10-04
630786184;direction@ccas-clermont-ferrand.fr;F;2020-10-04
630787059;direction@ch-thiers.fr;F;2020-10-04
630787067;direction@ccas-clermont-ferrand.fr;F;2020-10-04
630787513;direction@ch-ambert.fr;F;2020-10-04
630787687;ehpad-manzat@comcom-csm.fr;F;2020-10-04
630788057;secretariat@hl-billom.fr;F;2020-10-04
630788073;secretariat@hl-billom.fr;F;2020-10-04
630788081;direction@ehpad-brassac.fr;F;2020-10-04
630788107;direction@hopital-montdore.com;F;2020-10-04
630788198;maisonderetraite.job@ugecam-alpc.fr;F;2020-10-04
630790038;chatilles.cias@cctdm.fr;F;2020-10-04
630790095;foyerlesnympheas@orange.fr;F;2020-10-04
630790301;direction.chatelguyon@groupecolisee.com;F;2020-10-04
630790467;direction@ccas-clermont-ferrand.fr;F;2020-10-04
630790988;ehpad-ancizes@comcom-csm.fr;F;2020-10-04
630791580;direction.renouard@orpea.net;F;2020-10-04
630791788;mapad-giat@wanadoo.fr;F;2020-10-04
630791861;ehpad.lestonnelles@ville-romagnat.fr;F;2020-10-04
630791895;direction@hopital-montdore.com;F;2020-10-04
640003836;direction@centregeronto-pnj.com;F;2020-10-04
640007449;residence.oihana@gmail.com;F;2020-10-04
640008348;accueil-harriola@adapa-cotebasque.org;F;2020-10-04
640008389;accueil-harriola@adapa-cotebasque.org;F;2020-10-04
640008918;direction@mrlb64.fr;F;2020-10-04
640010179;administration@ehpad-arribet.fr;F;2020-10-04
640010609;administration@ehpad-arribet.fr;F;2020-10-04
640011029;administration@ehpad-arribet.fr;F;2020-10-04
640012118;ehpadgoxaleku@orange.fr;F;2020-10-04
640012159;marpa-de-lembeye@orange.fr;F;2020-10-04
640013371;accueil.lebosquet@apajh.asso.fr;F;2020-10-04
640014098;accueil-seque@adapa-cotesbasque.fr;F;2020-10-04
640014189;accueil-maharin@adapa-cotebasque.org;F;2020-10-04
640014635;ehpad-lepresaintgermain@foyersdesaines.fr;F;2020-10-04
640015111;secretariat@ehpad-letemple.fr;F;2020-10-04
640015178;direction@cgpnj.com;F;2020-10-04
640015236;residence.esquirette@wanadoo.fr;F;2020-10-04
640015285;accueil@adarpea.fr;F;2020-10-04
640015582;direction.arditeya@gmail.com;F;2020-10-04
640018370;direction@centregeronto-pnj.com;F;2020-10-04
640780292;direction@fondationluro.fr;F;2020-10-04
640781324;accueil@maison-saintantoine.com;F;2020-10-04
640781696;direction-ecureuil@wanadoo.fr;F;2020-10-04
640781787;ehpad.lesfoyers@johnbost.fr;F;2020-10-15
640781803;ehpad@osteys.org;F;2020-10-04
640781969;accueil@ehpadgarlin.com;F;2020-10-04
640781985;secretariat@ehpad-monein.fr;F;2020-10-04
640785382;secretariat.direction@ch-orthez.fr;F;2020-10-04
640785416;ch.oloron@ch-oloron.fr;F;2020-10-04
640785465;ccas@mairie-morlaas.fr;F;2020-10-04
640785564;secretariat.camou@capa-oloron.fr;F;2020-10-04
640785614;mdrbeaurivage@wanadoo.fr;F;2020-10-04
640785630;direction-albret@club-internet.fr;F;2020-10-04
640785655;contact@leschenes.fr;F;2020-10-04
640785671;accueil@residencedeslierres.fr;F;2020-10-04
640785713;contact@stelisa.com;F;2020-10-04
640785754;foyer.soleil@bayonne.fr;F;2020-10-04
640785770;ehpad.harambillet.ccas@bayonne.fr;F;2020-10-04
640785911;administratif-nay@association-saint-joseph.fr;F;2020-10-04
640785945;administratif-igon@association-saint-joseph.fr;F;2020-10-04
640785986;ehpadhaizpean@hendaye.com;F;2020-10-04
640786026;direction@centregeronto-pnj.com;F;2020-10-04
640786158;ehpad.lastrilles@orange.fr;F;2020-10-04
640786281;direction@centregeronto-pnj.com;F;2020-10-04
640786984;andaula.direction@ehpad-asea64.fr;F;2020-10-04
640789558;accueil@elizahegi.com;F;2020-10-04
640790358;resid-ste-croix@wanadoo.fr;F;2020-10-04
640791893;direction@ch-pau.fr;F;2020-10-04
640791943;direction@ch-mauleon.fr;F;2020-10-04
640791984;secretariat.direction@ch-orthez.fr;F;2020-10-04
640792016;ch.oloron@ch-oloron.fr;F;2020-10-04
640792958;contact@hesperie-sas.com;F;2020-10-04
640794426;direction@residencedubaretous.fr;F;2020-10-04
640794517;direction@colchiques-retraite-pau.fr;F;2020-10-04
640794822;mdr.argelas@wanadoo.fr;F;2020-10-04
640795514;ehpad@les-pins.fr;F;2020-10-04
640795753;ehpad@bidart.fr;F;2020-10-04
640795811;direction@ambroisie-sas.com;F;2020-10-04
640795837;contact@beaumanoir.fr;F;2020-10-04
640795845;accueil.saintjoseph@orpea.net;F;2020-10-04
640795894;secretariat@leparcdhiver.com;F;2020-10-04
640795928;retraitecaudron@orange.fr;F;2020-10-04
640796017;retraite.laruns@wanadoo.fr;F;2020-10-04
640796025;administration@ehpad-arribet.fr;F;2020-10-04
640796041;accueil@etxetoa.fr;F;2020-10-04
640796082;direction@acanthe-sas.com;F;2020-10-04
640796165;residence-bidache@orange.fr;F;2020-10-04
640796199;accueil@elizahegi.com;F;2020-10-04
640796264;marpa0996@orange.fr;F;2020-10-04
640796298;secretariat.direction@ch-orthez.fr;F;2020-10-04
650004039;residencevaldeneste@orange.fr;F;2020-10-04
650004427;residence.les.fougeres@wanadoo.fr;F;2020-10-04
650005192;administration@ehpad-argeles.com;F;2020-10-04
650005200;administration@ehpad-argeles.com;F;2020-10-04
650005648;stade.direction@arpavie.fr;F;2020-10-04
650780778;ehpad@curiesembres.fr;F;2020-10-04
650780877;administration@ehpad-argeles.com;F;2020-10-04
650781057;mdr.maubourguet@wanadoo.fr;F;2020-10-04
650782105;ehpad@epas65.fr;F;2020-10-04
650783756;ehpad.castelnau@anras.fr;F;2020-10-04
650783772;residencelasarribas@wanadoo.fr;F;2020-10-04
650783780;residence-du-pelam@wanadoo.fr;F;2020-10-04
650783798;ehpad.ossun@anras.fr;F;2020-10-04
650783806;accueil.frere-jean@wanadoo.fr;F;2020-10-04
650785744;ehpadgalan@ch-lannemezan.fr;F;2020-10-04
650786650;direction@ch-lourdes.fr;F;2020-10-04
650787112;ehpadramondias@wanadoo.fr;F;2020-10-04
650788458;mdr.lamadone@wanadoo.fr;F;2020-10-04
650788664;marpadesbaronnies@orange.fr;F;2020-10-04
650789126;direction.residence-lefoyerdupetitjer@fces.fr;F;2020-10-04
660003880;direction.camelias@lna-sante.com;F;2020-10-04
660004938;ehpad-francis-panicot@orange.fr;F;2020-10-04
660005257;ccas@toulouges.fr;F;2020-10-04
660005323;oliveraie.ehpad@association-sauvy.fr;F;2020-10-04
660005679;ehpad.pia@lerubandargent.fr;F;2020-10-04
660006289;accueil@rm-pezilla.fr;F;2020-10-04
660007261;secretariat.direction@pole-sanitaire-cerdan.eu;F;2020-10-04
660007287;ehpad.alenya@gmail.com;F;2020-10-04
660007329;accueil@rm-saintjean.fr;F;2020-10-04
660009051;hopital@hopital-prades.fr;F;2020-10-04
660780958;contact@ehpad-thuir.fr;F;2020-10-04
660781139;residence.retraite.paul.reig@wanadoo.fr;F;2020-10-04
660781154;contact@ehpad-illesurtet.fr;F;2020-10-04
660781162;residence-forcareal.millas@wanadoo.fr;F;2020-10-04
660781170;mdr.prats@wanadoo.fr;F;2020-10-04
660781196;mdr.stlaurent@orange.fr;F;2020-10-04
660781204;accueil@ehpad-ceret.fr;F;2020-10-04
660781378;mdrelne@wanadoo.fr;F;2020-10-04
660781485;hopital@hopital-prades.fr;F;2020-10-04
660782566;contact@villasaintfrancois.fr;F;2020-10-04
660784448;direction@ccasduboulou.fr;F;2020-10-04
660784687;accueil@ehpad-peyrestortes.fr;F;2020-10-04
660785353;accueil@ehpad-salses.fr;F;2020-10-27
660785437;azema.residence@orange.fr;F;2020-10-04
660785528;accueil@les-lauriers-roses.fr;F;2020-10-04
660785544;contact@mrlescapucines.fr;F;2020-10-04
660785569;accueil@residencejardinstjacques.fr;F;2020-10-04
660785684;accueil@vivre3age.com;F;2020-10-04
660785775;accueil@lacatalane.fr;F;2020-10-04
660786906;hopital@hopital-pradres.fr;F;2020-10-04
660787029;de-la-tour.direction@arpavie.fr;F;2020-10-04
660790270;accueil.catalogne@korian.fr;F;2020-10-04
670003581;mr.chatenois@wanadoo.fr;F;2020-10-04
670003615;accueil@gentilhome.fr;F;2020-10-04
670003631;mr.wolfisheim@orange.fr;F;2020-10-04
670003995;residencerothau@odelia.eu;F;2020-10-04
670006048;direction@ajpa.fr;F;2020-10-15
670006279;direction-paul-bertololy@groupe-sos.org;F;2020-10-04
670006428;direction-melezes@groupe-sos.org;F;2020-10-04
670006568;ehpad.danube@abrapa.asso.fr;F;2020-10-04
670006618;mdr.3fleurs@abrapa.asso.fr;F;2020-10-04
670007988;ehpad.stjoseph@abrapa.asso.fr;F;2020-10-04
670008978;accueildejour.strasbourg@ose-france.org;F;2020-10-04
670010479;ehpad.elisabeth@abrapa.asso.fr;F;2020-10-04
670011758;direction@ehpad-alumnat.fr;F;2020-10-04
670013853;direction-tilleul@groupe-sos.org;F;2020-10-04
670015155;direction@ehpad-bouxwiller.fr;F;2020-10-04
670016898;accueil@illmatt.fr;F;2020-10-04
670019249;direction@ghso.fr;F;2020-10-04
670780246;accueil.stcharles@mdr.fvdp.org;F;2020-10-04
670780535;secretariat-julie-gsell@groupe-sos.org;F;2020-10-04
670780618;mdrstoltzgrimm@orange.fr;F;2020-10-04
670780667;mdr-rhinau@wanadoo.fr;F;2020-10-04
670780782;elisa.accueil@orange.fr;F;2020-10-04
670781046;secretariatmarieroberta@hotmail.fr;F;2020-10-04
670781053;secretariat.mrdambach@orange.fr;F;2020-10-04
670781061;mrepfig@wanadoo.fr;F;2020-10-04
670781079;info@ehpad-hochfelden.fr;F;2020-10-04
670781087;secretariatschirmeck@orange.fr;F;2020-10-04
670782085;mdr.salem@orange.fr;F;2020-10-04
670783216;contact@alliance-st-thomas-seniors.fr;F;2020-10-04
670783331;accueil@ehpadville.fr;F;2020-10-04
670784420;admissions.geriatrie.selestat@ghso.fr;F;2020-10-04
670787787;accueil@mdr.fvdp.org;F;2020-10-04
670787795;mdrsacrecoeur@wanadoo.fr;F;2020-10-04
670787803;secretariat@niederbourg.fr;F;2020-10-04
670787829;accueil@diaconat-bischwiller.fr;F;2020-10-04
670787852;ehpad.koenigshoffen@abrapa.asso.fr;F;2020-10-04
670787860;ehpad.illkirch@abrapa.asso.fr;F;2020-10-04
670787878;accueil.caritas@orange.fr;F;2020-10-04
670790112;ehpad.stephanie@abrapa.asso.fr;F;2020-10-04
670790963;residence.krutenau@abrapa.asso.fr;F;2020-10-04
670791003;residence.leshalles@abrapa.asso.fr;F;2020-10-04
670791011;residence-huck@ville-bischheim.fr;F;2020-10-04
670791045;residence.stguillaume@abrapa.asso.fr;F;2020-10-04
670791052;ccas@ville.selestat.fr;F;2020-10-04
670791276;secretariat@bartischgut.com;F;2020-10-04
670791284;contact@ehpad-missionsafricaines.fr;F;2020-10-04
670792738;mairie@ville-de-benfeld.fr;F;2020-10-04
670792977;ehpad@ch-saverne.fr;F;2020-10-04
670793025;direction@ch-saverne.fr;F;2020-10-04
670793165;residence.wissembourg@abrapa.asso.fr;F;2020-10-04
670793363;secretariat@ehpad-drulingen.fr;F;2020-10-04
670793371;retraite-sans-souci@wanadoo.fr;F;2020-10-04
670793603;geriatrie.admissions@ch-selestat.fr;F;2020-10-04
670793652;direction@ghso.fr;F;2020-10-04
670793660;contact@ehpadbarr.fr;F;2020-10-04
670793686;accueil@illmatt.fr;F;2020-10-04
670793694;direction@ehpad-bouxwiller.fr;F;2020-10-04
670793702;contact@ch-lagrafenbourg.fr;F;2020-10-04
670793710;accueil@hl-erstein.fr;F;2020-10-04
670793728;accueil@residenceleried.fr;F;2020-10-04
670793736;hopital.local@hopital-molsheim.fr;F;2020-10-04
670793751;secretariat@hopital-rosheim.fr;F;2020-10-04
670793769;hopital.sarreunion@wanadoo.fr;F;2020-10-04
670793777;admissions@hl-wasselone.fr;F;2020-10-04
670793926;residence.petitefrance@abrapa.asso.fr;F;2020-10-04
670794510;ehpad.starbogast@abrapa.asso.fr;F;2020-10-04
670794635;contact@amreso-bethel.fr;F;2020-10-04
670794882;contact@ch-lagrafenbourg.fr;F;2020-10-04
670795277;accueil.stgothard@mdr.fvdp.org;F;2020-10-04
670795475;direction@ch-epsan.fr;F;2020-10-04
670795525;ehpad.marzolff@abrapa.asso.fr;F;2020-10-04
670795590;mdr.brulig@abrapa.asso.fr;F;2020-10-04
670795624;mdr.drusenheim@wanadoo.fr;F;2020-10-04
670795699;residence.haguenau@abrapa.asso.fr;F;2020-10-04
670795822;direction@ch-erstein.fr;F;2020-10-04
670796341;contact@kirchberg67.fr;F;2020-10-04
670796408;accueil@ehpad-roseliere.fr;F;2020-10-04
670796879;mairie.plaine@wanadoo.fr;F;2020-10-04
670796895;accueil.lairdutemps@korian.fr;F;2020-10-04
670797349;maison-de-retraite-saint-martin@wanadoo.fr;F;2020-10-04
670797752;direction.residence-lesoultzerland@fces.fr;F;2020-10-15
670797778;mdr.coquelicots@wanadoo.fr;F;2020-10-04
670798438;ehpad.lutzelhouse@abrapa.asso.fr;F;2020-10-04
670798974;info@benedictines-rosheim.com;F;2020-10-04
670799600;direction@ghsv.org;F;2020-10-04
670799691;direction@amreso-bethel.fr;F;2020-10-04
680001047;secretariat@hiva.fr;F;2020-10-04
680001070;secretariat@mr-soultzmatt.fr;F;2020-10-04
680002086;accueil.ammerschwihr@residence-weiss.fr;F;2020-10-04
680002144;secretariat@ehpad-lesmagnolias.fr;F;2020-10-04
680002151;contact@le-beau-regard.com;F;2020-10-04
680002177;mdrlesequoia@wanadoo.fr;F;2020-10-04
680002185;accueil@blanche-castille.fr;F;2020-10-04
680003019;direction@cdrs-colmar.fr;F;2020-10-04
680003068;accueil.leserables@ch-guebwiller.fr;F;2020-10-04
680003076;accueil@petit-chateau-68.com;F;2020-10-04
680003324;direction@cdrs-colmar.fr;F;2020-10-04
680003365;accueil@lesfontaines-lutterbach.fr;F;2020-10-04
680003456;accueildejour.kembs@orange.fr;F;2020-10-04
680004090;contact@henb.fr;F;2020-10-04
680004413;le.foyer.du.parc@wanadoo.fr;F;2020-10-04
680004470;accueil@fondation-dollfus.fr;F;2020-10-04
680004496;administratif.lacotonnade@korian.fr;F;2020-10-04
680004520;residence.gilles@wanadoo.fr;F;2020-10-04
680005238;accueil_ecureuils@apa.asso.fr;F;2020-10-04
680009768;info@apa.asso.fr;F;2020-10-04
680009818;info@apa.asso.fr;F;2020-10-04
680011236;ehpad@ch-altkirch.fr;F;2020-10-04
680011244;direction@ch-cernay.fr;F;2020-10-04
680011251;direction@ch-pfastatt.fr;F;2020-10-04
680011269;accueil@ch-thann.fr;F;2020-10-04
680011285;administration@hlisi.fr;F;2020-10-14
680011293;accueil.kaysersberg@residence-weiss.fr;F;2020-10-04
680011335;direction58@hopital-munster-haslach.fr;F;2020-10-04
680011376;administration@hopital-ribeauville.fr;F;2020-10-04
680011384;contact@ehpad-rixheim.fr;F;2020-10-04
680011392;direction@ch-rouffach.fr;F;2020-10-04
680011400;hopital-de-sierentz@wanadoo.fr;F;2020-10-04
680011426;secretariat@hiva.fr;F;2020-10-04
680011434;ehpadbrand@ehpadbrand-turckheim.fr;F;2020-10-04
680011871;hopital-soultz@wanadoo.fr;F;2020-10-04
680011897;administration@hopital-ribeauville.fr;F;2020-10-04
680012044;direction@ch-cernay.fr;F;2020-10-04
680012051;ehpad@ch-altkirch.fr;F;2020-10-04
680012069;secretariat-direction@ch-mulhouse.fr;F;2020-10-04
680012077;secretariat-direction@ch-mulhouse.fr;F;2020-10-04
680012481;accueil-arc@apa.asso.fr;F;2020-10-04
680012838;direction@ehpad-quatelbach.fr;F;2020-10-15
680013240;direction@ghca.fr;F;2020-10-04
680013695;accueil@residence-argenson.fr;F;2020-10-04
680014040;direction@lesmolenes.fr;F;2020-10-04
680014149;accueil@ehpad-saint-louis.fr;F;2020-10-04
680014859;direction-colmar@diaconat-mulhouse.fr;F;2020-10-14
680015369;secretariat@lesfontaines-kembs.com;F;2020-10-04
680015468;accueil@lesfontaines-horbourg-wihr.com;F;2020-10-04
680016268;marpa-de-la-doller@orange.fr;F;2020-10-04
680016870;ehpad-lescollines@orange.fr;F;2020-10-04
680016904;marpa.brechaumont@orange.fr;F;2020-10-04
680017373;marpa.seppois@gmail.com;F;2020-10-04
680017894;contact@asame.fr;F;2020-10-04
680018751;info@apa.asso.fr;F;2020-10-04
680019015;administration@ehpad-bergheim.fr;F;2020-10-04
680019064;info@apa.asso.fr;F;2020-10-04
680019387;secretariat-direction@ch-mulhouse.fr;F;2020-10-04
680019924;info@apa.asso.fr;F;2020-10-04
680020104;info@apa.asso.fr;F;2020-10-04
680020534;residenceapalib@apa.asso.fr;F;2020-10-04
690006887;contact@hopital-fourviere.fr;F;2020-10-04
690007083;direction.ccas@irigny.fr;F;2020-10-04
690007174;contact@residence-larochedajoux.fr;F;2020-10-04
690007307;ehpad.lachaux@croix-rouge.fr;F;2020-10-04
690007315;accueil@cmbayere.fr;F;2020-10-04
690010509;secretariat@mtcouderc.fr;F;2020-10-04
690011218;contact@hopital-fourviere.fr;F;2020-10-04
690011978;secretariat@lemontet.org;F;2020-10-04
690015508;accueildejour@ovpar.fr;F;2020-10-04
690023015;accueil@la-solidage.fr;F;2020-10-04
690023593;residence.charles.trenet@wanadoo.fr;F;2020-10-04
690023809;reception.claudebernard@korian.fr;F;2020-10-04
690025143;ehpad.alouette@gmail.com;F;2020-10-04
690025192;accueil@ehpadbuers.fr;F;2020-10-04
690025531;gustave-prost.direction@arpavie.fr;F;2020-10-04
690027289;ccas@mairie-meyzieu.fr;F;2020-10-04
690027388;reception.bellecombe@korian.fr;F;2020-10-04
690030705;ccas-residences@ville-bron.fr;F;2020-10-04
690031588;info@polydom.com;F;2020-10-04
690031869;contact@hoparb.com;F;2020-10-04
690031901;hopital.antoine.charial@chu-lyon.fr;F;2020-10-04
690031919;hopital.pierre.garraud@chu-lyon.fr;F;2020-10-04
690031935;direction@ch-condrieu.fr;F;2020-10-04
690031968;residencedespinslentilly@orange.fr;F;2020-10-04
690034491;contact@residence-paul-eluard.com;F;2020-10-04
690034772;ssiad3@smdlyon.fr;F;2020-10-04
690035803;marpa.lafleurisienne@orange.fr;F;2020-10-04
690039771;accueil@ehpad-chaponnay.fr;F;2020-10-04
690781521;mdrbonsecours@orange.fr;F;2020-10-04
690782644;contact@ehpad-michellamy.fr;F;2020-10-04
690782941;mdr-cublize@wanadoo.fr;F;2020-10-04
690782982;direction@ehpad-mornant.com;F;2020-10-04
690785423;contact@ehpad-michellamy.fr;F;2020-10-04
690785431;direction@ehpadmanoir.com;F;2020-10-04
690785449;accueil@ehpadlarochette.com;F;2020-10-04
690785514;direction@girondines.fr;F;2020-10-04
690785530;direction@apeb.fr;F;2020-10-04
690785555;ehpad.la.salette@ccass-sbe.org;F;2020-10-04
690785589;secretariat@dethel.fr;F;2020-10-04
690785647;accueil.straphael@habitat-humanisme.org;F;2020-10-04
690785670;mdrlapasserelle@wanadoo.fr;F;2020-10-04
690785720;maisonaccueilprovidence@laposte.net;F;2020-10-04
690785787;residence-bonsecours@wanadoo.fr;F;2020-10-04
690785811;direction@maisonstjoseph.fr;F;2020-10-04
690787346;ehpad.direction@lhopitalnordouest.fr;F;2020-10-04
690787510;hopital.de.belleville@hopital-belleville.fr;F;2020-10-04
690787643;contact@ehpad-lescollonges.fr;F;2020-10-04
690788062;residencelesarcades@mairie-brignais.fr;F;2020-10-04
690788088;ccas-residences@ville-bron.fr;F;2020-10-04
690788112;ccas.ehpa.decines@orange.fr;F;2020-10-04
690788591;residence.croizat@mairie-vaulxenvelin.fr;F;2020-10-04
690788641;residence-dubure@wanadoo.fr;F;2020-10-04
690788922;residence.californie@ville-oullins.fr;F;2020-10-04
690790340;contact@residencesainteanne.fr;F;2020-10-04
690790357;ehpad.laroseraie@croix-rouge.fr;F;2020-10-04
690793583;direction@clinique-vaugneray.fr;F;2020-10-04
690797824;direction@hli-cours.fr;F;2020-10-04
690797873;direction@hli-cours.fr;F;2020-10-04
690797972;direction@chdml.fr;F;2020-10-04
690799994;secretariat-geriatrie@ch-fidesien.fr;F;2020-10-04
690800016;hopital.de.beaujeu@hopital-beaujeu.fr;F;2020-10-04
690800040;direction@hli-cours.fr;F;2020-10-04
690800057;direction@hli-cours.fr;F;2020-10-04
690800099;direction@hl-amplepuis.fr;F;2020-10-04
690801089;contact@la-grande-charriere.com;F;2020-10-04
690801139;contact@acsh-vilanova.fr;F;2020-10-04
690801576;accueil@la-vigie.fr;F;2020-10-04
690802046;contact@charmes-des-sources.com;F;2020-10-04
690802061;contact@hoparb.com;F;2020-10-04
690802327;contact@leslandiers.fr;F;2020-10-04
690802343;ehpad.eolienne@wanadoo.fr;F;2020-10-04
690802368;saintlaurent.direction@gmail.com;F;2020-10-04
690802434;valmy.direction@arpavie.fr;F;2020-10-04
690802517;direction@ehpadmargaux.fr;F;2020-10-04
690802756;ehpadladimerie@mairie-chaponost.fr;F;2020-10-04
690803093;direction@clinique-vaugneray.fr;F;2020-10-04
690806484;contact@jardins-danne.fr;F;2020-10-04
700001019;ehpad@ch-gray.fr;F;2020-10-04
700001050;marpa.marnay@wanadoo.fr;F;2020-10-04
700003759;usld@ahbfc.fr;F;2020-10-04
700004179;direction@gh70.fr;F;2020-10-04
700004880;contact@eliad-fc.fr;F;2020-10-04
700005127;contact@eliad-fc.fr;F;2020-10-04
700005382;foyerlogementrioz@fede70.admr.org;F;2020-10-04
700780224;secretariat@nddescedres.fr;F;2020-10-04
700780240;direction@ch-gray.fr;F;2020-10-04
700780273;mr.scey@orange.fr;F;2020-10-04
700780281;direction@gh70.fr;F;2020-10-04
700780729;mr.saulx@orange.fr;F;2020-10-04
700781768;secretariatehpad@ch-gray.fr;F;2020-10-04
700781776;direction@ch-gray.fr;F;2020-10-04
700781784;direction@ch-gray.fr;F;2020-10-04
700781859;contact@mcombattant.fr;F;2020-10-04
700781867;contact@ahbfc.fr;F;2020-10-04
700782014;direction@gh70.fr;F;2020-10-04
700782022;direction@gh70.fr;F;2020-10-04
700782048;direction@gh70.fr;F;2020-10-04
700783335;direction@gh70.fr;F;2020-10-04
700783343;direction@gh70.fr;F;2020-10-04
700783665;direction@gh70.fr;F;2020-10-04
700784341;contact@ahfc.fr;F;2020-10-04
700784358;direction@maspa70.fr;F;2020-10-04
700784788;contact@ahbfc.fr;F;2020-10-04
700784929;mairielavoncourt@wanadoo.fr;F;2020-10-04
700785082;marpa.combeaufontaine@wanadoo.fr;F;2020-10-04
700785389;contact@ahbfc.fr;F;2020-10-04
700785561;ehpadcirey@fede70.admr.org;F;2020-10-04
710002007;marpa.cleret@wanadoo.fr;F;2020-10-04
710002239;chmacon@ch-macon.fr;F;2020-10-04
710004409;info.la-providence@admr.org;F;2020-10-04
710006909;accueil.paraylemonial@groupecolisee.com;F;2020-10-04
710010083;direction-paray@lesopalines.fr;F;2020-10-04
710011487;ehpad-mervans@orange.fr;F;2020-10-04
710011750;residenceduvaldejoux@orange.fr;F;2020-10-04
710013509;accueil.jour@ch-paray.fr;F;2020-10-04
710013988;ehpad.chalon@ch-chalon71.fr;F;2020-10-04
710014275;chmacon@ch-macon.fr;F;2020-10-04
710780024;administration@ehpad-sennecey-st-ambreuil.fr;F;2020-10-04
710780073;accueil@ehpad-epinac71.fr;F;2020-10-04
710780289;chmacon@ch-macon.fr;F;2020-10-04
710780545;contact@foyersaintemarie.fr;F;2020-10-04
710780586;admin@ehpad-montcenis.fr;F;2020-10-04
710780594;ehpad.mont-st-vincent@orange.fr;F;2020-10-04
710780693;ehpadpierre.accueil@orange.fr;F;2020-10-04
710780727;administration@ehpad-romaneche.fr;F;2020-09-28
710780743;administration@ehpad-sennecey-st-ambreuil.fr;F;2020-10-04
710780750;ehpad-st-desert@orange.fr;F;2020-10-04
710780867;contact@ehpad-salornay.fr;F;2020-10-04
710780891;ehpad.bouthier@orange.fr;F;2020-10-04
710780974;ehpad.saintremy@ch-chalon71.fr;F;2020-10-04
710781113;accueil@ehpad-coublanc.fr;F;2020-10-04
710781121;contact@ehpad-couches71.fr;F;2020-10-04
710781246;residencelecreusot@odelia.eu;F;2020-10-04
710781303;mrcuisery@wanadoo.fr;F;2020-10-04
710781394;ehpadciel.accueil@orange.fr;F;2020-10-04
710781576;secretariat@champ-fleury.com;F;2020-10-04
710781659;accueil@ehpad-vlg.fr;F;2020-10-04
710785304;contact@residence-camille-claudel.com;F;2020-10-04
710785361;secretariat.autun@lacompassion.fr;F;2020-10-04
710785379;contact@lacompassion.fr;F;2020-10-04
710785502;ccas.digoin@orange.fr;F;2020-10-04
710785528;foyer@louhans-chateaurenaud.fr;F;2020-10-04
710785536;ccas@ville-macon.fr;F;2020-10-04
710785551;foyerdespeupliers@montceaulesmines.fr;F;2020-10-04
710785569;residencedeverneuil@orange.fr;F;2020-10-04
710940131;residence.farastier@orange.fr;F;2020-10-04
710970013;accueil@ehpad-rl.fr;F;2020-10-04
710970252;direction@ch-aligre.fr;F;2020-10-04
710970336;hopital.louhans@ch-louhans.fr;F;2020-10-04
710972282;direction@ch-autun.fr;F;2020-10-04
710972332;direction@ch-charolles.fr;F;2020-10-04
710972365;secretariat.direction@ch-paray.fr;F;2020-10-04
710972423;chmacon@ch-macon.fr;F;2020-10-04
710972506;direction@hopital-tramayes.fr;F;2020-10-04
710972548;secretariat.direction@ch-chagny.fr;F;2020-10-04
710972647;residenceautonomie-citefleurie@creches-sur-saone.com;F;2020-10-04
710972811;residencehubiliac@saintmarcel.com;F;2020-10-04
710972910;secretariat.direction@ch-paray.fr;F;2020-10-04
710972969;administration@ehpad-chauffailles.fr;F;2020-10-04
710973025;administration@ehpad-digoin.fr;F;2020-10-04
710973306;residence-stjulien@wanadoo.fr;F;2020-10-04
710973314;contact@charreconduit.fr;F;2020-10-04
710973595;direction@ch-autun.fr;F;2020-10-04
710973645;chmacon@ch-macon.fr;F;2020-10-04
710974478;direction@muriers.fr;F;2020-10-04
710974650;contact@villa-victor-hugo.com;F;2020-10-04
710974718;hopital.louhans@hopital-local-louhans.fr;F;2020-10-15
710974817;contact@domisol.asso.fr;F;2020-10-04
710975087;louhans.direction@sofinam.fr;F;2020-10-04
710975145;marpa.simard@orange.fr;F;2020-10-04
710976564;accueil@ehpad-vlg.fr;F;2020-10-04
710976861;direction@ch-laguiche.fr;F;2020-10-04
710976903;stberainsoussanvignes.mairie@wanadoo.fr;F;2020-10-04
710977067;secretariat.chatenoy@orpea.net;F;2020-10-04
710977604;foyeraccueil@orange.fr;F;2020-10-04
710977927;marpa.anais@orange.fr;F;2020-10-04
710978040;marpamatour@orange.fr;F;2020-10-04
720000116;mr.mansigne@orange.fr;F;2020-10-04
720000546;mr.besse@wanadoo.fr;F;2020-10-04
720000801;accueil.beaumont@pgns.fr;F;2020-10-04
720002039;ehpad.auvers@cegvs.fr;F;2020-10-04
720002047;retraite.ballon@wanadoo.fr;F;2020-10-04
720002070;ehpad.brulon@cegvs.fr;F;2020-10-04
720002088;direction@ehpadfresnay.fr;F;2020-10-04
720002104;mrloue@wanadoo.fr;F;2020-10-04
720002120;accueil@ehpad-marolles.fr;F;2020-10-04
720002138;direction@maison-retraite-mayet.fr;F;2020-10-04
720002146;maisonderetraitemontmirail@orange.fr;F;2020-10-04
720002153;secretariat@ehpad-delante.fr;F;2020-10-04
720002161;contact@ehpad-amicie.fr;F;2020-10-04
720002179;ehpad.roeze@cegvs.fr;F;2020-10-04
720002187;residencefontenay@wanadoo.fr;F;2020-10-04
720002195;contact@ehpadlahoussaye.fr;F;2020-10-04
720002260;mr-crapez-accueil@orange.fr;F;2020-10-04
720004142;association.st.raphael@orange.fr;F;2020-10-04
720004472;ehpa.vauguyon@lemans.fr;F;2020-10-04
720004522;mairie@sille-le-guillaume.fr;F;2020-10-04
720004654;foyerlogement@ville-allonnes.fr;F;2020-10-04
720004670;ccas@bonnetable.fr;F;2020-10-04
720004688;ccas@montvalsurloir.fr;F;2020-10-04
720004696;mairie@connerre.fr;F;2020-10-04
720004712;ccasecommoy@hotmail.fr;F;2020-10-04
720004738;ccas@ville-lafleche.fr;F;2020-10-04
720004746;ccas@ville-lafleche.fr;F;2020-10-04
720004795;ccas-cias@sablesursarthe.fr;F;2020-10-04
720005958;info@cmsbm.org;F;2020-10-04
720006006;direction@ch-saintcalais.fr;F;2020-10-04
720006550;direction-mamers@ch-alencon.fr;F;2020-10-04
720006790;direction@lareposance.net;F;2020-10-04
720007087;contact@ehpadlapetitebruyere.fr;F;2020-10-04
720007111;ehpad.vallon@cegvs.fr;F;2020-10-04
720007228;secretariat@ehpadalberttrotte.fr;F;2020-10-04
720008093;ehpad.beaulieu@wanadoo.fr;F;2020-10-04
720008101;accueil.mdrparce@wanadoo.fr;F;2020-10-04
720008184;ccas@arnage.fr;F;2020-10-04
720008200;mairie-fresnay@wanadoo.fr;F;2020-10-04
720008226;ccas@ville-lafleche.fr;F;2020-10-04
720008234;secretariat@ville-lelude.fr;F;2020-10-04
720008721;foyerlajeuliniere@gmail.com;F;2020-10-04
720011758;accueil.sille@pgns.fr;F;2020-10-04
720011766;ehpad-sable@pole-pssl.fr;F;2020-10-04
720011782;direction@ch-saintcalais.fr;F;2020-10-04
720011899;ehpadchanterie72@orange.fr;F;2020-10-04
720011915;hesperides72.secretariat@wanadoo.fr;F;2020-10-04
720011980;secretariat@calt.asso.fr;F;2020-10-04
720012202;ehpad-lafleche@pole-pssl.fr;F;2020-10-04
720012293;accueil.bonnetable@pgns.fr;F;2020-10-04
720013119;mdr.abbaye.tuffe@wanadoo.fr;F;2020-10-04
720013192;mairie.vaas@wanadoo.fr;F;2020-10-04
720013390;residenceduparc@sarthefibre.fr;F;2020-10-04
720013580;contact@hopital-lude.com;F;2020-10-04
720013598;mr-pontvallain-accueil@orange.fr;F;2020-10-15
720013622;ehpad@lemans.fr;F;2020-10-04
720013648;accueil.lefoulon@groupecolisee.com;F;2020-10-15
720013671;front-de-sarthe.direction@arpavie.fr;F;2020-10-04
720013697;foyerlogement.stpaterne@orange.fr;F;2020-10-04
720014067;direction@fondation-gcoulon.fr;F;2020-10-04
720014075;ehpad.les3vallees@coulaines.fr;F;2020-10-04
720014109;contact@champdelormeau.com;F;2020-10-04
720014471;accueil.montheard@lenobleage.fr;F;2020-10-04
720014513;direction@ch-saintcalais.fr;F;2020-10-04
720014539;contact@hopital-lude.com;F;2020-10-04
720014968;direction-mamers@ch-alencon.fr;F;2020-10-04
720015742;ehpa.guemaulny@lemans.fr;F;2020-10-04
720015759;accueil.beaumont@pgns.fr;F;2020-10-04
720017581;direction@lasouvenance.net;F;2020-10-04
720017938;accueilmyosotis@lareposance.net;F;2020-10-04
720018522;ssiad.sable@ahs-sarthe.asso.fr;F;2020-10-04
720018753;direction-mamers@ch-alencon.fr;F;2020-10-04
720019041;foyerlogement.lasuze@orange.fr;F;2020-10-04
720019074;mairie.mamers@wanadoo.fr;F;2020-10-04
720019090;mairie.saintremydesille@wanadoo.fr;F;2020-10-04
720020346;ehpa.letrianon@ccas.ville-lemans.fr;F;2020-10-04
720020411;direction@fondation-gcoulon.fr;F;2020-10-04
720020817;mrmarolles@wanadoo.fr;F;2020-10-04
730000692;ehpad.niveole@arlysere.fr;F;2020-10-04
730001369;alzheimersavoie.accueildejour@orange.fr;F;2020-10-04
730002938;residenceduparc.cognin@orange.fr;F;2020-10-04
730004728;direction@ch-metropole-savoie.fr;F;2020-10-04
730005519;secretariat@ccas-quietude.org;F;2020-10-04
730005659;direction@hopital-dubettier.com;F;2020-10-04
730006228;accueil@cias-residence-beatrice.org;F;2020-10-04
730006368;secretariat@monferine.com;F;2020-10-04
730008018;direction@cias-frontenex.fr;F;2020-10-04
730009719;hebergement@cias-sierss.fr;F;2020-10-04
730010329;secretariat.charmilles@ccas-chambery.fr;F;2020-10-04
730780442;direction@ch-bsm.fr;F;2020-10-04
730780509;foyer-notre-dame@ccass-sbe.org;F;2020-10-04
730780608;direction@ehpad-aiguebelle.fr;F;2020-10-04
730780616;accueil@ehpad-beaufort73.fr;F;2020-10-04
730780632;direction@ehpad-la-rochette.com;F;2020-10-04
730783743;secretariat@monferine.com;F;2020-10-04
730783776;ccas@saintjeandemaurienne.fr;F;2020-10-04
730783784;secretariat@ccas-quietude.org;F;2020-10-04
730783792;accueil@cias-residence-beatrice.org;F;2020-10-04
730783800;cias.frontenex@wanadoo.fr;F;2020-10-04
730783818;residenceduparc.cognin@orange.fr;F;2020-10-04
730783842;ehpa-laroseliere@bourgsaintmaurice.fr;F;2020-10-04
730783891;direction@ccas-modane.fr;F;2020-10-04
730783917;accueil@maison-saint-benoit.fr;F;2020-10-04
730783925;administration@ehpad-bozel.fr;F;2020-10-04
730783982;direction@ch-sjm.fr;F;2020-10-04
730785359;direction@ch-metropole-savoie.fr;F;2020-10-04
730785367;direction@ch-metropole-savoie.fr;F;2020-10-04
730785391;direction@ch-modane.fr;F;2020-10-04
730785417;direction@ehpad-montmelian.fr;F;2020-10-04
730785425;direction@ch-sjm.fr;F;2020-10-04
730785433;direction@hopital-dubettier.com;F;2020-10-04
730789823;ccas-cognin@orange.fr;F;2020-10-04
730789930;secretariat-ehpad@versantsdaime.fr;F;2020-10-04
730789955;direction@ch-metropole-savoie.fr;F;2020-10-04
730789989;ehpad.belfontaine@orange.fr;F;2020-10-04
730790722;direction@ehpad-la-bailly.fr;F;2020-10-04
740001623;cias@grandannecy.fr;F;2020-10-04
740003918;contact@epi2a.fr;F;2020-10-04
740008024;info@residence-laclairiere.fr;F;2020-10-04
740008032;residencecervens@odelia.eu;F;2020-10-04
740008164;foyerdumontblanc@gmail.com;F;2020-10-04
740009121;accueil@ehpadhautchablais.fr;F;2020-10-04
740009154;ciasadmissions@grandannecy.fr;F;2020-10-04
740009311;accueil@ehpadhautchablais.fr;F;2020-10-04
740009360;ehpad@cluses.fr;F;2020-10-04
740010921;contact@epi2a.fr;F;2020-10-04
740010939;ehpad.val-montjoie.secretariat@amapa.fr;F;2020-10-04
740010954;direction.ehpad@cias-annemasse-agglo.fr;F;2020-10-04
740011291;ehpad.labartavelle@grandannecy.fr;F;2020-10-04
740011390;contact@epi2a.fr;F;2020-10-04
740011671;secretariatdirection@ch-hopitauxduleman.fr;F;2020-10-04
740012125;secretariatdirection@ch-hopitauxduleman.fr;F;2020-10-04
740012133;accueil.gerontologie@ch-rumilly.fr;F;2020-10-04
740013172;accueil.gerontologie@rumilly.fr;F;2020-10-04
740013354;direction.sources@lna-sante.com;F;2020-10-04
740781232;administration@ehpadavet.fr;F;2020-10-04
740781489;ehpadalfredblanc@orange.fr;F;2020-10-04
740781497;accueil@lesmontsargentes.fr;F;2020-10-04
740781513;contact@ehpad-taninges.fr;F;2020-10-04
740783063;foyer.lespervenches@grandannecy.fr;F;2020-10-04
740784392;direction@ehpadfrangy.fr;F;2020-10-04
740784400;ccas-clair-horizon@ville-evian.fr;F;2020-10-04
740784475;direction.eau-vive@annemasse.fr;F;2020-10-04
740784491;cias@agglo-annecy.fr;F;2020-10-04
740784509;ehpad.residenceheureuse@grandannecy.fr;F;2020-10-04
740784517;cias@grandannecy.fr;F;2020-10-04
740785415;residence.duleman@omeris.com;F;2020-10-04
740785779;cias@grandannecy.fr;F;2020-10-04
740786496;foyerleman@wanadoo.fr;F;2020-10-04
740787536;secretariat.direction@ch-andrevetan.fr;F;2020-10-04
740788070;secretariatdirection@ch-hopitauxduleman.fr;F;2020-10-04
740788179;residence.lacour@grandannecy.fr;F;2020-10-04
740789060;accueil@lesbalconsdulac.fr;F;2020-10-04
740789417;ehpad-vivre-ensemble@wanadoo.fr;F;2020-10-04
740789656;secretariatdirection@ch-hopitauxduleman.fr;F;2020-10-04
740790118;direction@ehpad-magland.fr;F;2020-10-04
740790241;ehpad-gruffy@wanadoo.fr;F;2020-10-04
740790316;mapad.seyssel@wanadoo.fr;F;2020-10-04
750000366;accueil@jardinsdemontmartre.com;F;2020-10-04
750002552;contact@residencedesevres.com;F;2020-10-04
750003360;reception.lesarcades@korian.fr;F;2020-10-04
750003642;administration.terrassesduxxeme@korian.fr;F;2020-10-04
750003972;direction@gambetta.repotel.fr;F;2020-10-04
750007809;contact@residence-club-le-montsouris.com;F;2020-10-04
750008278;accueildejour@ose-france.org;F;2020-10-04
750030298;accueildejour@ose-france.org;F;2020-10-04
750038564;reception.magenta@korian.fr;F;2020-10-04
750041402;secretariat@residencemarais.com;F;2020-10-04
750041659;direction@jardinsdebelleville.com;F;2020-10-04
750041790;accueil.amaraggi@casip-cojasor.fr;F;2020-10-04
750047714;ehpadsaintaugustin@ndbs.org;F;2020-10-04
750047722;direction@fondation-ove.fr;F;2020-10-04
750050387;contact@villajeandominique.fr;F;2020-10-04
750055808;contact-celestins@coallia.org;F;2020-10-04
750058729;contact.broca@brc.aphp.fr;F;2020-10-04
750058745;direction.secretariat@rth.aphp.fr;F;2020-10-04
750800559;direction@augustines-paris.fr;F;2020-10-04
750800658;secretariat@villa-jules-janin.com;F;2020-10-04
750800666;direction@ehpad-fir.com;F;2020-10-04
750800708;administration@laprovidence.paris;F;2020-10-04
750800898;foyer.paris@apf.asso.fr;F;2020-10-04
750801474;direction@jardindesmoines.com;F;2020-10-04
750802829;foyerlogement@f-d-r.org;F;2020-10-04
750803538;lamartine.direction@arpavie.fr;F;2020-10-04
750804213;solanacees.direction@arpavie.fr;F;2020-10-04
750814949;accueil-administratif@ehpad-lesairelles.fr;F;2020-10-04
750828709;reception.lesamandiers@korian.fr;F;2020-10-04
750828774;association-de-gerontologie13@wanadoo.fr;F;2020-10-04
750832156;residences@avh.asso.fr;F;2020-10-14
750832586;reception.monceau@korian.fr;F;2020-10-04
760011171;administration@chdl-darnetal.fr;F;2020-10-04
760023218;accueil-lescharmettes@gonfreville-l-orcher.fr;F;2020-10-04
760023358;accueil@lesjardinsmatisse.fr;F;2020-10-04
760023572;info@la-boiseraie.fr;F;2020-10-04
760023697;direction-ehpad@tourville-la-riviere.fr;F;2020-10-04
760026732;contact@residencecarola.fr;F;2020-10-04
760027557;contact@ehpad-havre.fr;F;2020-10-04
760028621;direction.residence-jacquesbonvoisin@fces.fr;F;2020-10-04
760028639;ehpad.jeanferrat@mfn-ssam.fr;F;2020-10-04
760033449;ccas@rouen.fr;F;2020-10-04
760035352;marpa.lavarenne@orange.fr;F;2020-10-04
760035568;ehpad@chi-elbeuf-louviers.fr;F;2020-10-04
760037614;contact@ehpad-havre.fr;F;2020-10-04
760037622;contact@ehpad-havre.fr;F;2020-10-04
760781609;direction@ehpad-letreport.fr;F;2020-10-04
760781633;direction@epd-grugny.fr;F;2020-10-04
760782193;cormeilles-direction@wanadoo.fr;F;2020-10-04
760782201;contact@ehpad-buchy.fr;F;2020-10-04
760782268;ehpad.envermeu@wanadoo.fr;F;2020-10-04
760782284;residence.bouicmanoury@orange.fr;F;2020-10-04
760782292;contact@ehpad-la-feuillie.fr;F;2020-10-04
760782318;contact@ehpad-gaillefontaine.fr;F;2020-10-04
760782326;contact@ehpad-grainville.fr;F;2020-10-04
760782359;accueil@village-des-aubepins.fr;F;2020-10-04
760782375;ehpad-les-myosotis@wanadoo.fr;F;2020-10-04
760782383;accueil@cote-de-velours.fr;F;2020-10-04
760782409;residence.lascie@wanadoo.fr;F;2020-10-04
760782417;accueil@ehpad-saint-saens.fr;F;2020-10-04
760782755;mdr.rogerville@wanadoo.fr;F;2020-10-04
760790642;accueil@maisondelacompassion.fr;F;2020-10-04
760790667;secretariat.castel@smsj.fr;F;2020-10-04
760790758;accueil.village@gmail.com;F;2020-10-04
760790840;contact@la-buissonniere.fr;F;2020-10-04
760790923;foyersaintjoseph@wanadoo.fr;F;2020-10-04
760790949;contact.sapins@filseine.fr;F;2020-10-04
760790956;direction.lechateaublanc@probtp.com;F;2020-10-04
760791046;mairie-auffay@wanadoo.fr;F;2020-10-04
760791103;secretariat.ccas@bolbec.fr;F;2020-10-04
760791129;secretariat@si-plateau-est.fr;F;2020-10-04
760791202;ccas@mairie-deville-les-rouen.fr;F;2020-10-04
760791236;ccas@duclair.fr;F;2020-10-04
760791251;residencedusud@ccas-elbeuf.fr;F;2020-10-04
760791285;ccas@terres-de-caux.fr;F;2020-10-04
760791293;mairie@fontaine-le-dun.fr;F;2020-10-04
760791319;ccas@gournay-en-bray.fr;F;2020-10-04
760791327;mairie.hericourt.en.caux@wanadoo.fr;F;2020-10-04
760791343;contact@ville-lehoulme.fr;F;2020-10-04
760791384;accueil.ccas@ville-nd-bondeville.fr;F;2020-10-04
760791400;secretariat@si-plateau-est.fr;F;2020-10-04
760791467;ccas@petit-quevilly.fr;F;2020-10-04
760791525;mairie@mairie-sotteville-les-rouen.fr;F;2020-10-04
760791574;resid.jean-bart.suffren@orange.fr;F;2020-10-04
760791673;accueil-bois-de-bleville@groupe-sos.org;F;2020-10-04
760791681;ehpad.stjust@mfn-ssam.fr;F;2020-10-04
760791699;lamartine-le-havre.direction@arpavie.fr;F;2020-10-04
760791947;contact@ville-montivilliers.fr;F;2020-10-04
760792085;mairie@valdesaane.com;F;2020-10-04
760800094;mairie@offranville.fr;F;2020-10-04
760800631;contact@ehpad-havre.fr;F;2020-10-04
760800730;accueil@hautesbruyeres.fr;F;2020-10-04
760801969;ccas@caudebecleselbeuf.fr;F;2020-10-04
760801985;ccas@ville-isneauville.fr;F;2020-10-04
760802066;secretariat.ccas@bolbec.fr;F;2020-10-04
760802082;ccas@pierrotin.fr;F;2020-10-04
760802108;mairie@mairie-sotteville-les-rouen.fr;F;2020-10-04
760802256;mairie.yebleron@wanadoo.fr;F;2020-10-04
760802355;mairie@lafrenaye.fr;F;2020-10-04
760802629;direction.lavisitation@gmail.com;F;2020-10-04
760802660;direction@chi-cauxvalleedeseine.fr;F;2020-10-04
760802892;secretariatdirection@ch-de-eu.fr;F;2020-10-04
760802900;direction@chi-cauxvalleedeseine.fr;F;2020-10-04
760802934;accueil@hopstval.fr;F;2020-10-04
760802959;direction.hopital@wanadoo.fr;F;2020-10-04
760802975;hopital@hl-saintromain.fr;F;2020-10-04
760802991;contact@ehpad-havre.fr;F;2020-10-04
760803007;administration@chdl-darnetal.fr;F;2020-10-04
760804773;ccas@mairie-montville.fr;F;2020-10-04
760913590;ehpad.notredamedegravenchon@coallia.org;F;2020-10-04
760913608;contact@ville-montivilliers.fr;F;2020-10-04
760914440;ccas@montsaintaignan.fr;F;2020-10-04
760914507;ccas@terres-de-caux.fr;F;2020-10-04
760914515;mairie@rives-en-seine.fr;F;2020-10-04
760914531;mairie@cany-barville.fr;F;2020-10-04
760914556;info@mairie-quincampoix.fr;F;2020-10-04
760914838;residencecroizat@ser76.com;F;2020-10-04
760915397;ehpad.lehavre@croix-rouge.fr;F;2020-10-04
760918052;direction@residence-saint-antoine.fr;F;2020-10-04
760918722;mdr@boisjoli.fr;F;2020-10-04
760919282;mapad.lasource@wanadoo.fr;F;2020-10-04
760919381;ccas@ville-fecamp.fr;F;2020-10-04
760919647;ehpad.le.mesnil.esnard@wanadoo.fr;F;2020-10-04
760920066;resid.valfleuri@wanadoo.fr;F;2020-10-04
760920413;contact@chg-lafilandiere.fr;F;2020-10-04
760920702;marpalebeausoleil@wanadoo.fr;F;2020-10-04
760921304;accueilmatinsbleus@orange.fr;F;2020-10-04
760921726;contact@ehpad-havre.fr;F;2020-10-04
760922062;ehpad@chi-elbeuf-louviers.fr;F;2020-10-04
760922070;ehpad@chi-elbeuf-louviers.fr;F;2020-10-04
770001345;accueil@residencebaccara.com;F;2020-10-04
770003341;contact@les7moulins.com;F;2020-10-04
770003382;ehpad.leparcfleuri@orange.fr;F;2020-10-04
770016939;accueilmelun@vieactive.fr;F;2020-10-04
770017119;contact@residence-francois-villon.com;F;2020-10-04
770019321;marpa.rozay@gmail.com;F;2020-10-04
770019396;accueil.meuliere@lna-sante.com;F;2020-10-04
770020444;marpa.varennes77@gmail.com;F;2020-10-04
770020642;secretariat.direction@ch-nemours.fr;F;2020-10-04
770021939;accueil-jardins-avon@ehpad-sedna.fr;F;2020-10-04
770022655;contact.coubert@ugecamidf.fr;F;2020-10-04
770420040;accueil@maisondesartistespad.fr;F;2020-10-04
770700938;accueil@ehpadseverin.fr;F;2020-10-15
770700979;contact@ehpad-fouquet.fr;F;2020-10-04
770700987;accueil@ehpad-rebais.fr;F;2020-10-15
770701001;mrbeaumont@wanadoo.fr;F;2020-10-04
770701019;accueil@lefilargent.fr;F;2020-10-04
770701027;direction@ch-montereau.fr;F;2020-10-04
770701076;contact@ehpaddammartin.fr;F;2020-10-04
770701084;contact@ehpad-leclosfleuri.fr;F;2020-10-04
770707586;secretariat.direction@ch-nemours.fr;F;2020-10-04
770790095;direction-chateau-du-poitou@groupe-sos.org;F;2020-10-04
770790749;accueil@ehpad-lfg.fr;F;2020-10-04
770802213;foyer.flamant@chelles.fr;F;2020-10-04
770802239;residence.lorraine@fontainebleau.fr;F;2020-10-04
770802254;residence-serenite@lagny-sur-marne.fr;F;2020-10-04
770802262;tournelles.direction@arpavie.fr;F;2020-10-04
770802288;residence.longueville77@gmail.com;F;2020-10-04
770802296;foyerbellefeuille@ville-montereau77.fr;F;2020-10-04
770802304;ccas@saint-fargeau-ponthierry.fr;F;2020-10-04
770802312;residencemesanges@vairessurmarne.fr;F;2020-10-04
770802320;administratif@sourcenadon.fr;F;2020-10-04
770802338;foyerresidence@orange.fr;F;2020-10-04
770802650;contact@chateau-de-louche.com;F;2020-10-04
770802668;residence@ehpad-malka.fr;F;2020-10-04
770802692;direction@essaimgatinais.asso.fr;F;2020-10-04
770802718;direction@ehpad-lagarenne.com;F;2020-10-04
770802726;laguette.secretariat@f-d-r.org;F;2020-10-04
770803468;direction@chateau-plessispicard.com;F;2020-10-04
770803682;direction.stmammes@agepartenaires.com;F;2020-10-04
770803716;direction@ch-jouarre.fr;F;2020-10-04
770808632;direction@ch-fontainebleau.fr;F;2020-10-04
770809200;direction@ch-montereau.fr;F;2020-10-04
770809218;direction@ch-montereau.fr;F;2020-10-04
770810406;secretariat-aubetin@groupe-sos.org;F;2020-10-04
770811222;direction@savigny.repotel.fr;F;2020-10-04
770811560;direction@residencelehameau.com;F;2020-10-04
770811628;plantagenets.direction@arpavie.fr;F;2020-10-04
770811784;accueil@epgtournan.fr;F;2020-10-04
770813814;direction@ch-jouarre.fr;F;2020-10-04
770813939;accueil-jardins-avon@ehpad-sedna.com;F;2020-10-15
770814085;colombiere.direction@arpavie.fr;F;2020-10-04
770814655;direction@agos-claye.fr;F;2020-10-04
770814671;contact@les-jardins-du-loing.fr;F;2020-10-04
770814804;accueil.harmonie@lenobleage.fr;F;2020-10-04
770814846;accueil.levillage@orpea.net;F;2020-10-04
770814861;accueil.etang@groupe-aplus.com;F;2020-10-04
770814895;contact@residence-ermitage.fr;F;2020-10-04
770814929;residence.rosabonheur@fontainebleau.fr;F;2020-10-04
770815223;direction@lieusaint.repotel.fr;F;2020-10-04
770815330;mairie.chenoise@wanadoo.fr;F;2020-10-04
770815827;administration.detente@korian.fr;F;2020-10-04
770816601;direction@residencedeuxmoulins.com;F;2020-10-04
780000204;accueil.epidaure78@lna-sante.com;F;2020-10-04
780000360;secretariat@hgchevreuse.fr;F;2020-10-04
780006458;direction.marconi@lna-sante.com;F;2020-10-04
780010328;secretariatdedirection@hopital-gms-plaisir.fr;F;2020-10-04
780010369;accueildejourdumerantais@hopital-gms-plaisir.fr;F;2020-10-04
780013579;contact@hopitalhoudan.fr;F;2020-10-04
780014858;contact@hopitalhoudan.fr;F;2020-10-04
780017653;marpa.breval@hotmail.fr;F;2020-10-04
780018206;accueil@leparcdudonjon.fr;F;2020-10-04
780018560;direction.bonnieres@orpea.net;F;2020-10-04
780018792;residence.mantes@fondationbellan.org;F;2020-10-04
780020087;direction@ch-mantes-la-jolie.fr;F;2020-10-04
780022356;reception.chateaudelacouldre@korian.fr;F;2020-10-04
780022752;accueil.buchelay@orpea.net;F;2020-10-04
780022976;contact@saj-ies-magny.fr;F;2018-04-18
780700688;contact@lepineversailles.fr;F;2020-10-04
780700811;fleurie.direction@arpavie.fr;F;2020-10-04
780700860;contact@fces.fr;F;2020-10-04
780700902;residence.septeuil@fondationbellan.org;F;2020-10-04
780700985;ehpad.richaud@ch-versailles.fr;F;2020-10-04
780701041;accueil@epsms-richard.fr;F;2020-10-04
780701066;secretariat-ehpad-ablis@orange.fr;F;2020-10-04
780701082;admissions.lesaulnettes@orange.fr;F;2020-10-04
780701439;accueil.sartrouville@agefo.fr;F;2020-10-04
780701504;direction.lesglycines@teneris.fr;F;2020-10-04
780701538;direction.maisons-laffitte@sgmr-ouest.com;F;2020-10-04
780701637;accueil@ehpadmnd.fr;F;2020-10-04
780701710;contact@augustines-saintgermain.fr;F;2020-10-04
780701793;laresidence@isatis.asso.fr;F;2020-10-04
780701884;anne-de-bretagne.direction@arpavie.fr;F;2020-10-04
780701900;ccas-rambouillet@wanadoo.fr;F;2020-10-04
780800306;contact@chimm.fr;F;2020-10-04
780800363;admissions@hopitalmontfort.fr;F;2020-10-04
780800587;contact@hopitalhoudan.fr;F;2020-10-04
780800892;direction@chi-poissy-st-germain.fr;F;2020-10-04
780801981;foyer-pompidou@mairie-acheres78.fr;F;2020-10-04
780801999;fermettes.direction@arpavie.fr;F;2020-10-04
780802013;residence.renaissance@ville-lacellesaintcloud.fr;F;2020-10-04
780802021;residenceletilleul@orange.fr;F;2020-10-04
780802039;grands-chenes.direction@arpavie.fr;F;2020-10-04
780802047;ccas@lechesnay-rocquencourt.fr;F;2020-10-04
780802070;residence-les-belles-vues@ville-houilles.fr;F;2020-10-04
780802138;accueil@maurepas.repotel.fr;F;2020-10-04
780802146;residence-mansart@marlyleroi.fr;F;2020-10-04
780802153;edouard-behuret.direction@arpavie.fr;F;2020-10-04
780802203;foyerlogement@levesinet.fr;F;2020-10-04
780802302;ccas@ville-verneuil-sur-seine.fr;F;2020-10-04
780802351;accueil.stgermain@agefo.fr;F;2020-10-04
780802468;direction@roseraie-croissy.com;F;2020-10-04
780803433;ccas@mairie-magnanville.fr;F;2020-10-04
780803995;hopital@ch-rambouillet.fr;F;2020-10-04
780804027;contact@hopitalhoudan.fr;F;2020-10-04
780804035;secretariat@hgchevreuse.fr;F;2020-10-04
780804126;portiques.direction@arpavie.fr;F;2020-10-04
780804811;madeleine-wagner.direction@arpavie.fr;F;2020-10-04
780804845;administration.lecoeurvolant@korian.fr;F;2020-10-04
780805966;secretariat.direction@hopital-gms-plaisir.fr;F;2020-10-04
780821641;roseraie.direction@arpavie.fr;F;2020-10-04
780822052;juliette-victor.direction@arpavie.fr;F;2020-10-04
780822466;reception.hameauduroy@korian.fr;F;2020-10-04
780823084;reception.lessaules@korian.fr;F;2020-10-04
780823654;administration.val-essonne@korian.fr;F;2020-10-04
780823795;tilleuls.direction@arpavie.fr;F;2020-10-04
780823878;contact@residence-rose-des-vents.com;F;2020-10-04
780823928;direction@voisins.repotel.fr;F;2020-10-04
780824587;secretariatdedirection@hopital-gms-plaisir.fr;F;2020-10-04
780824876;clos-de-pries.direction@arpavie.fr;F;2020-10-04
780824942;accueil.relaistendresse@teneris.fr;F;2020-10-04
780825493;residencelescytises@epone.fr;F;2020-10-04
780826038;reception.villapegase@korian.fr;F;2020-10-15
780826137;clemenceau.residence@wanadoo.fr;F;2020-10-04
780826244;reception.quieta@korian.fr;F;2020-10-04
780826293;info@laresidenceleprieure.fr;F;2020-10-04
790000277;ehpad.airvault@ehpad-thouet.fr;F;2020-10-04
790000285;accueil@lelac79.fr;F;2020-10-04
790000293;ehpadchefboutonne@wanadoo.fr;F;2020-10-04
790000301;accueil@epms-chize.fr;F;2020-10-04
790000319;accueil@ehpad-faye-labbesse.fr;F;2020-10-04
790000327;accueil@fondationbrothier.fr;F;2020-10-04
790000343;mrmenigoute@wanadoo.fr;F;2020-10-04
790000368;administration@mr-lamothestheray.fr;F;2020-10-04
790000376;contact@residence-oiron.fr;F;2020-10-04
790000384;ehpad.stloup@ehpad-thouet.fr;F;2020-10-04
790000400;mdr.vasles@laposte.net;F;2020-10-06
790000418;accueil@aba79.fr;F;2020-10-04
790000426;accueil@ehpad3cbrioux.fr;F;2020-10-04
790000459;secretariat@ehpad-courlay.fr;F;2020-10-04
790002026;mr.residencedelaplaine.thenezay@wanadoo.fr;F;2020-10-04
790002034;ehpadlezay@cap-lezay.eu;F;2020-10-04
790002042;direction@ehpadchanterelles.fr;F;2020-10-04
790002059;direction@residencedevallois.fr;F;2020-10-04
790003545;info@ehpadlacressonniere.fr;F;2020-10-04
790003586;cias@cap-lezay.eu;F;2020-10-04
790003594;accueil@epcms-lacoudraie.fr;F;2020-10-04
790003628;accueilresidencemoliere.thouars@orange.fr;F;2020-10-04
790003750;ehpad.pamproux@wanadoo.fr;F;2020-10-04
790003768;secretariat@ehpad-bethanie-nla.fr;F;2020-10-04
790006092;direction@ch-hvsm.fr;F;2020-10-04
790006100;direction@ch-hvsm.fr;F;2020-10-04
790006118;direction@hopital-mauleon.fr;F;2020-10-04
790006746;ehpadalienor@orange.fr;F;2020-10-04
790007124;residencelesvignes@orange.fr;F;2020-10-04
790007207;ccas2@mauleon.fr;F;2020-10-04
790007231;marpa.couture@wanadoo.fr;F;2020-10-04
790007884;direction@chnds.fr;F;2020-10-04
790008791;accueil@bleuets79.fr;F;2020-10-04
790009864;direction@sacrecoeur79.fr;F;2020-10-04
790009880;foyer.residence.sauze-vaussais@orange.fr;F;2020-10-04
790009898;ehpad-emilienbouin@orange.fr;F;2020-10-04
790011332;foyer-logement@cc-parthenay.fr;F;2020-10-04
790011373;direction@hl-stmaixent.fr;F;2020-10-04
790011878;accueil@logisdesfrancs.com;F;2020-10-04
790012405;residence.gambetta@ville-thouars.fr;F;2020-10-04
790012538;charmilles.secretariat@orange.fr;F;2020-10-04
790012850;direction@sacrecoeur79.fr;F;2020-10-04
790013288;residence.sevileano@fede79.admr.org;F;2020-10-04
790013429;accueil@hopital-mauleon.fr;F;2020-10-04
790013452;direction@chnds.fr;F;2020-10-04
790013908;foyerlogement.epannes@orange.fr;F;2020-10-04
790014302;accueil@epcms-lacoudraie.fr;F;2020-10-04
790014534;accueilresidenceduparc@orange.fr;F;2020-10-04
790014708;ehpadlesrocs@wanadoo.fr;F;2020-10-04
790014757;administration.homedelebaupin@korian.fr;F;2020-10-15
790015796;ehpad.lesbabelottes@wanadoo.fr;F;2020-10-04
790015861;administration.laveniseverte@korian.fr;F;2020-10-15
790015903;direction@stjoseph-chiche.fr;F;2020-10-04
790016034;secretariat@abies79.fr;F;2020-10-04
790016588;accueil@ehpad-les-jardins-aiffres.fr;F;2020-10-04
790016737;direction@chnds.fr;F;2020-10-04
790018188;direction@chnds.fr;F;2020-10-04
800000622;ehpad.oisemont@epissos.fr;F;2020-10-04
800000648;secretariat.mdr.cayeux@orange.fr;F;2020-10-04
800000739;ehpad-striquier@orange.fr;F;2020-10-04
800000754;residence.joseph.petit@wanadoo.fr;F;2020-10-04
800002289;ehpad.airaines@epissos.fr;F;2020-10-04
800002305;ehpad.domart.en.ponthieu@live.fr;F;2020-10-04
800003717;accueil.residence.tilleuls@gmail.com;F;2020-10-04
800003915;ehpad.poix@epissos.fr;F;2020-10-04
800003923;secretariat.mariemarthe@arassoc.fr;F;2020-10-04
800003998;ehpad.accueil@ch-abbeville.fr;F;2020-10-04
800004004;admission@ch-corbie.fr;F;2020-10-15
800004061;direction@chibs.fr;F;2020-10-04
800004160;secretariat.direction@ch-peronne.fr;F;2020-10-04
800004186;direction.secretariat@chimr.fr;F;2020-10-04
800004285;contact@residencevalleedelaluce.fr;F;2020-10-04
800004293;administration.larivierebleue@korian.fr;F;2020-10-04
800005712;direction.secretariat@chimr.fr;F;2020-10-04
800006165;direction@ch-corbie.fr;F;2020-10-04
800006207;direction@chibs.fr;F;2020-10-04
800006249;secretariat.direction@ch-peronne.fr;F;2020-10-04
800006264;usld-ehpadsecretariat@chu-amiens.fr;F;2020-10-04
800006322;direction.secretariat@chimr.fr;F;2020-10-04
800006330;secretariatmdr@ch-albert.fr;F;2020-10-15
800006512;admission@ch-corbie.fr;F;2020-10-15
800007650;direction@ch-doullens.fr;F;2020-10-04
800009375;mapalongueau@orange.fr;F;2020-10-04
800009417;direction.secretariat@chimr.fr;F;2020-10-04
800009425;direction@chibs.fr;F;2020-10-04
800009656;marpa.des.villers@cc2so.fr;F;2020-10-04
800010472;reception.samarobriva@korian.fr;F;2020-10-04
800010589;accueil.jardinshenriville@lna-sante.com;F;2020-10-04
800012098;marpa.lesnacres@orange.fr;F;2020-10-04
800014706;marpa.combles@orange.fr;F;2020-10-04
800014904;secretariat@ehpad-saint-joseph.org;F;2020-10-04
800014961;marpa.rosieres@orange.fr;F;2020-10-04
800015505;secretariat.valdancre@pcp80.com;F;2020-10-04
800015513;marpa-nouvion@orange.fr;F;2020-10-04
800016990;usld-ehpadsecretariat@chu-amiens.fr;F;2020-10-04
800017196;usld-ehpadsecretariat@chu-amiens.fr;F;2020-10-04
800018202;marpa-matigny80@orange.fr;F;2020-10-04
810000364;contact@maisonderetraiteduparc.fr;F;2020-10-04
810000414;mdrstvincent@wanadoo.fr;F;2020-10-04
810002089;mr.rabastens@free.fr;F;2020-10-04
810003418;mapad@ch-albi.rss.fr;F;2020-10-04
810003590;accueil@residencedubosc.fr;F;2020-10-04
810003608;accueil@ehpad-cordes.fr;F;2020-10-04
810003632;residence81@orange.fr;F;2020-10-04
810003657;accueil@plaisance.fr;F;2020-10-04
810003764;accueil.stvincent81@ccass-sbe.org;F;2020-10-04
810003772;accueil@residence-stjoseph.fr;F;2020-10-04
810003806;secretariat@saint-joseph.asso.fr;F;2020-10-04
810003822;ehpadclosdesiloe@wanadoo.fr;F;2020-10-04
810003863;maisonderetraitemoffre@wanadoo.fr;F;2020-10-04
810004044;ehpad81@gmail.com;F;2020-10-04
810004051;contact.ehpad@umt-terresdoc.fr;F;2020-10-04
810004119;marpa-le-segali.association@wanadoo.fr;F;2020-10-04
810004218;direction@ch-gaillac.fr;F;2020-10-04
810007948;monges.admissions@chic-cm.fr;F;2020-10-04
810008169;contact@accueil-jour.admr-alban.fr;F;2020-10-04
810008219;accueil@lfplaisance.fr;F;2020-10-04
810008458;accueil-dame-guiraude@orange.fr;F;2020-10-04
810009472;mr-saix@orange.fr;F;2020-10-04
810009613;ehpad-montdragon@cclpa.fr;F;2020-10-04
810010173;accueil@ehpadpuygouzon.fr;F;2020-10-04
810010348;ehpad.pampelonne@filieris.fr;F;2020-10-04
810010538;direction@ch-gaillac.fr;F;2020-10-04
810099747;mr.rabastens@free.fr;F;2020-10-04
810100206;residence-midi@chic-cm.fr;F;2020-10-04
810100297;direction.hopital@ch-albi.rss.fr;F;2020-10-04
810100313;secretariat.direction@ch-lavaur.fr;F;2020-10-04
810100370;admissions-usld@chic-cm.fr;F;2020-10-04
810100420;direction@ch-gaillac.fr;F;2020-10-04
810100776;direction@ehpad-agir.fr;F;2020-10-04
810100883;monges.admissions@chic-cm.fr;F;2020-10-04
810100917;secretariat@residence-elie-gasc.fr;F;2020-10-04
810101204;marpa384@orange.fr;F;2020-10-04
810101261;hopital-graulhet@wanadoo.fr;F;2020-10-04
810101279;hopital.graulhet@wanadoo.fr;F;2020-10-04
810101386;direction@mdrlislesurtarn.com;F;2020-10-04
810101642;ccas@mairie-graulhet.fr;F;2020-10-04
810101675;ehpad@maisonduboutge.fr;F;2020-10-04
810102160;contact@residencelegrandchamp.fr;F;2020-10-04
820000222;ehpadleparc@maisons-retraites.eu;F;2020-10-04
820000255;accueil@ehpadlauzerte.fr;F;2020-10-04
820000305;mdr.direction82@orange.fr;F;2020-10-04
820000339;mdrgrisolles@orange.fr;F;2020-10-04
820000354;accueil.mr.verdun@orange.fr;F;2020-10-04
820000370;ehpadleparc@maisons-retraites.eu;F;2020-10-04
820000388;maison.retraite.lamagistere@wanadoo.fr;F;2020-10-04
820003465;direction@ch-montauban.fr;F;2020-10-04
820003473;admissions.ehpad@ch-cm.fr;F;2020-10-04
820003903;administration@ch-cm.fr;F;2020-10-14
820004083;secretariat@chturenne.fr;F;2020-10-04
820004422;administratif@chdes2rives.fr;F;2020-10-04
820005163;accueil@residence-du-fort.com;F;2020-10-04
820005403;direction@ch-montauban.fr;F;2020-10-04
820005437;direction@ch-montauban.fr;F;2020-10-04
820005569;mairie.la.ville.dieu.du.temple@info82.com;F;2020-10-04
820005668;residencedulac2@wanadoo.fr;F;2020-10-04
820005676;residence.septfontoise@asei.asso.fr;F;2020-10-04
820005932;secretariat-3lacs@orange.fr;F;2020-10-04
820006344;accueil@ehpadangegardien.fr;F;2020-10-04
820006559;marpa.montaigu@wanadoo.fr;F;2020-10-04
820007375;contact-montauban@apas82.fr;F;2020-10-04
820007821;contact@apas82.fr;F;2020-10-04
820007854;mapasapiac@ville-montauban.fr;F;2020-10-04
820008225;ehpad.negrepelisse@info82.com;F;2020-10-04
820008282;ehpad@apim-82.com;F;2020-10-04
820008530;residence.pagomal@montbeton.fr;F;2020-10-15
820008803;accueil@les-floralies.eu;F;2020-10-04
820008985;maison.retraite.protestante.82@wanadoo.fr;F;2020-10-04
820008993;residencemutualistestorens@udm82.fr;F;2020-10-04
820009488;contact@apas82.fr;F;2020-10-04
820009595;administration@ch-cm.fr;F;2020-10-04
820009603;administration@ch-cm.fr;F;2020-10-04
820009611;administration@ch-cm.fr;F;2020-10-04
820009629;administratif@chdes2rives.fr;F;2020-10-04
820009660;secretariat@chturenne.fr;F;2020-10-04
830003968;accueil.pleiades@lna-sante.com;F;2020-10-04
830004339;ehpad.draguignan@ville-draguignan.fr;F;2020-10-04
830004529;direction.marvivo@lna-sante.com;F;2020-10-04
830004628;reception.lecapsicie@korian.fr;F;2020-10-04
830006128;direction.marvivo@lna-sante.com;F;2020-10-04
830007209;direction@hv-leluc.com;F;2020-10-04
830007449;contact@lestamaris.fr;F;2020-10-04
830009718;ehpad@ville-lagarde.fr;F;2020-10-04
830011219;direction.solliespont@groupecolisee.com;F;2020-10-04
830011318;secretariat@ehpad-pierrefeu.fr;F;2020-10-04
830011599;administration@lesclematites.fr;F;2020-10-04
830015939;ehpad.jeanlachenaud@ajl.asso.fr;F;2020-10-04
830015988;secretariat.direction@ch-brignoles.fr;F;2020-10-04
830016309;ehpad3tilleuls@st-maximin.fr;F;2020-10-04
830016689;contact@notre-dame-de-paracol.com;F;2020-10-04
830017109;accueildejour@brignoles.fr;F;2020-10-04
830018222;marpalabeille@gmail.com;F;2020-10-04
830018560;administration@residence-palmera.com;F;2020-10-04
830019196;residences.autonomie@ccas-hyeres.fr;F;2020-10-04
830019204;residences.autonomie@ccas-hyeres.fr;F;2020-10-04
830020731;direction.ollioules@orpea.net;F;2020-10-04
830101242;mr.lebeausset@wanadoo.fr;F;2020-10-04
830101283;secretariat-home-armenien@orange.fr;F;2020-10-04
830101291;accueil@notre-dame-anges.org;F;2020-10-04
830101325;mdrgrimaud@gmail.com;F;2020-10-15
830101432;administration@ehpad-ops.fr;F;2020-10-04
830101440;mdr.carces@wanadoo.fr;F;2020-10-04
830101473;accueil@ehpad-saint-francois.fr;F;2020-10-04
830101481;direction@hv-leluc.com;F;2020-10-04
830101507;direction@mdrpignans.fr;F;2020-10-04
830101515;accueil-mr-rians@laposte.net;F;2020-10-04
830101549;contact@residence-lasource.fr;F;2020-10-04
830101556;mdr-seillans@orange.fr;F;2020-10-04
830101564;ehpad.felixpey@gmail.com;F;2020-10-04
830200119;peirin.accueil@orange.fr;F;2020-10-04
830200150;accueil@collinestemusse.fr;F;2020-10-04
830200176;accueil@verger-sanary.com;F;2020-10-04
830200218;direction.platanes@wanadoo.fr;F;2020-10-04
830200358;foyerlogementssalernes@wanadoo.fr;F;2020-10-04
830200408;residenceleverdon@orange.fr;F;2020-10-04
830200424;residence-acacias@ville-saintraphael.fr;F;2020-10-04
830200457;contact@ccas-hyeres.fr;F;2020-10-04
830200465;contact.marquisanne@adapei83.fr;F;2020-10-04
830201117;administration.rosaire@korian.fr;F;2020-10-04
830201125;residence.wetzel@carqueiranne.fr;F;2020-10-04
830201158;secretariat@foyerfalquette.fr;F;2020-10-04
830201166;contact@lesgenets83.fr;F;2020-10-04
830206207;foyer-logement-roger-mistral@wanadoo.fr;F;2020-10-04
830206447;contact@maison-retraite-montaurelien.fr;F;2020-10-04
830206587;residences.autonomie@ccas-hyeres.fr;F;2020-10-04
830208484;accueil_marie_dominique@club-internet.fr;F;2020-10-04
830211173;direction@ch-saint-tropez.fr;F;2020-10-04
830212148;contact.marquisanne@adapei83.fr;F;2020-10-04
830212429;direction-vallondesabeilles@sud-generations.fr;F;2020-10-04
830212742;secretariat.direction@ch-brignoles.fr;F;2020-10-04
830212783;contact@long-sejour-montdazur.fr;F;2020-10-04
830212874;direction.aiguemarine@lna-sante.com;F;2020-10-04
830213047;direction-notredame@sud-generations.fr;F;2020-10-04
830213054;contact@sainte-philomene.fr;F;2020-10-04
830213088;direction.loujas@orange.fr;F;2020-10-04
830213922;direction@ehpad-bellevue.com;F;2020-10-15
830213930;reception.lespinsbleus@korian.fr;F;2020-10-04
830213955;contact@lalexandra.fr;F;2020-10-04
830214029;mdr.templiers@wanadoo.fr;F;2020-10-04
830214433;ehpad@lacroixvalmer.fr;F;2020-10-04
830214508;secretariat.lesserves@orange.fr;F;2020-10-04
830214599;contact@residence-retraite-ndp.com;F;2020-10-04
830215182;direction@lesjardins-de-thalassa.com;F;2020-10-04
830215349;contact@residencelespalmiers.com;F;2020-10-04
830215539;plenitude-ehpad@orange.fr;F;2020-10-04
830215661;ccas@bandol.fr;F;2020-10-04
830215711;figanieres.ehpad@aliceadsl.fr;F;2020-10-15
830216172;information@renaissancemayol.fr;F;2020-10-15
840002059;ehpad.cadenet.direction@orange.fr;F;2020-10-04
840002067;direction.ehpad.aubignan@gmail.com;F;2020-10-04
840002075;administration@ehpad-beaumesdevenise.fr;F;2020-10-04
840002083;accueil@ehpad7rivieres.fr;F;2020-10-04
840002091;administration@rjdb.fr;F;2020-10-04
840002109;direction@residenceprospermathieu.fr;F;2020-10-04
840002125;secretariat-cucuron@orange.fr;F;2020-10-04
840002133;direction.mdrjonquieres@orange.fr;F;2020-10-04
840002141;administration@ehpad-malaucene.fr;F;2020-10-04
840002158;mazan.ehpad@orange.fr;F;2020-10-04
840002166;mrpiolenc@ch-orange.fr;F;2020-10-04
840002174;ehpad.sablet@orange-business.fr;F;2020-10-04
840002190;accueil@residence-jrippert.fr;F;2020-10-15
840002208;admin@adep84.fr;F;2020-10-04
840002216;accueil@ehpaddesorgues.fr;F;2020-10-04
840002224;ehpad.les.cigales@ehpadlethor.fr;F;2020-10-04
840002513;contact@quinsan.fr;F;2020-10-04
840006084;ehpad@ch-valreas.fr;F;2020-10-04
840006118;secretariat@mr-bedoin.fr;F;2020-10-04
840006225;direction@les-floralies84.org;F;2020-10-04
840006381;residenceleclosdeslavandes@wanadoo.fr;F;2020-10-04
840006506;foyerlogementrustin@orange.fr;F;2020-10-04
840007298;foyerlogement.stmartin@laposte.net;F;2020-10-04
840007587;direction@ch-orange.fr;F;2020-10-04
840007595;direction@ch-pertuis.fr;F;2020-10-04
840007660;accueil@hl-bollene.fr;F;2020-10-04
840007678;secretariatdirection@hl-gordes.fr;F;2020-10-04
840007694;secretariat@hl-sault.fr;F;2020-10-04
840007777;direction@vlcgargas.fr;F;2020-10-04
840007785;contact@beau-soleil.org;F;2020-10-04
840007793;direction.leronquet@sorgues.fr;F;2020-10-04
840011019;contact@residence-saint-roch.fr;F;2020-10-04
840011662;direction@ch-carpentras.fr;F;2020-10-04
840011688;direction-lepontet@lesopalines.fr;F;2020-10-04
840011720;accueil@res-saintandre.fr;F;2020-10-04
840012470;direction@ch-avignon.fr;F;2020-10-04
840012678;secretariat@hopital-islesursorgue.fr;F;2020-10-04
840012751;direction@retraite-amandines.com;F;2020-10-04
840013767;contact@ehpad-albionnaise.com;F;2020-10-04
840015598;direction-closdelagarance@sud-generations.fr;F;2020-10-04
840017693;residenceleclosdeslavandes@wanadoo.fr;F;2020-10-04
840017701;direction@ch-orange.fr;F;2020-10-04
850000266;accueil@hl-noirmoutier.fr;F;2020-10-04
850000423;direction@residence-equaiziere.com;F;2020-10-04
850002155;accueil@lesmathurins.com;F;2020-10-04
850002163;direction@hl-bouin.fr;F;2020-10-04
850002171;direction@mr-lachaizelevicomte.fr;F;2020-10-04
850002189;ehpadlesroches@wanadoo.fr;F;2020-10-04
850002197;accueil.ch@residenceaufildesmaines.fr;F;2020-10-04
850002221;accueil@ehpad-montfort.fr;F;2020-10-04
850002254;accueil@ehpadlamoulinotte.fr;F;2020-10-04
850002429;direction@etoiledusoir.fr;F;2020-10-04
850003112;direction@ehpad-beausejour.fr;F;2020-10-15
850003120;ehpad.assemblee@gmail.com;F;2020-10-04
850003146;direction@foyer-mimosas.com;F;2020-10-15
850003161;secretariat.bellevue@wanadoo.fr;F;2020-10-04
850003195;foyer.sainte.anne@wanadoo.fr;F;2020-10-04
850003203;ehpad.ardillers@orange.fr;F;2020-10-04
850003229;direction@ehpadermitage.fr;F;2020-10-04
850003245;accueil@ciasfontenay.fr;F;2020-10-04
850003252;contact@residenceyvescougnaud.fr;F;2020-10-04
850003260;accueil.arbraseve@cias-canton-rocheserviere.fr;F;2020-10-04
850003302;accueil.ehpadlaforet@orange.fr;F;2020-10-04
850003310;accueil@lehavredupayre.fr;F;2020-10-04
850003377;direction@ch-lvo.fr;F;2020-10-04
850003484;direction@ehpadmaillezais.fr;F;2020-10-04
850003492;les.collines.accueil@pouzauges.fr;F;2020-10-04
850003583;secretariat@ehpad-laferriere.fr;F;2020-10-04
850003781;ehpad.stgabriel@wanadoo.fr;F;2020-10-04
850003807;ehpadstesophie@stjosephstesophie.fr;F;2020-10-15
850003815;ehpadmaille@orange.fr;F;2020-10-04
850003831;contact@residence-fleurie.fr;F;2020-10-04
850003856;ehpadlesglycines@wanadoo.fr;F;2020-10-04
850003898;direction.ehpadstdenis@orange.fr;F;2020-10-04
850003906;accueilleruleau@wanadoo.fr;F;2020-10-04
850003914;accueil@ehpad-laflocelliere.fr;F;2020-10-04
850003963;ehpadstjoseph@stjosephstesophie.fr;F;2020-10-15
850004870;marpa2@wanadoo.fr;F;2020-10-04
850004896;leserables.ehpad@wanadoo.fr;F;2020-10-04
850005018;marpa.roseaux@wanadoo.fr;F;2020-10-04
850006651;accueil@residence-capline.com;F;2020-10-04
850006669;marpa.arcenciel@orange.fr;F;2020-10-04
850007758;direction-mormaison@orange.fr;F;2020-10-04
850007899;direction@lesursulines.fr;F;2020-10-04
850009085;marpalameilleraie@orange.fr;F;2020-10-04
850009317;foyerlogement-falleron@wanadoo.fr;F;2020-10-04
850009390;ehpadbienvenue@dompierre-sur-yon.fr;F;2020-10-04
850009952;accueil@ehpadsagesse85.fr;F;2020-10-04
850011255;marpa.clairdelune@orange.fr;F;2020-10-04
850011503;direction.olonne@lna-sante.com;F;2020-10-04
850011842;lacledesol.accueil@orange.fr;F;2020-10-04
850011958;residence.simonnemoreau@admr85.org;F;2020-10-04
850012493;residence.larocterie@admr85.org;F;2020-10-04
850013251;direction@puv-lapommeraie.fr;F;2020-10-04
850013343;accueil@ch-chataigneraie.fr;F;2020-10-04
850016627;ehpad.leschataigniers@wanadoo.fr;F;2020-10-04
850016676;contact@leseptierdor.fr;F;2020-10-04
850017658;direction@ch-mazurelle.fr;F;2020-10-04
850018235;marpa@essartsenbocage.fr;F;2020-10-04
850020124;direction@ch-lvo.fr;F;2020-10-04
850020298;contact@residencesmortagne.fr;F;2020-10-04
850020389;secretariat.direction@chfontenaylecomte.fr;F;2020-10-04
850020405;direction.lucon@chd-vendee.fr;F;2020-10-14
850020439;accueil@hl-noirmoutier.fr;F;2020-10-04
850020470;accueil@ehpad-saintjean.com;F;2020-10-04
850020488;direction@ch-lvo.fr;F;2020-10-14
850020504;direction@ch-lvo.fr;F;2020-10-04
850020579;accueil@hl-chataigneraie.idhl.fr;F;2020-10-04
850021049;secretariat.hebergement@ch-cotedelumiere.fr;F;2020-10-04
850021270;direction.montaigu@chd-vendee.fr;F;2020-10-04
850021528;marpa-stefoy@orange.fr;F;2020-10-04
850021544;residencelouiscaiveau@wanadoo.fr;F;2020-10-04
850021866;direction@ch-mazurelle.fr;F;2020-10-04
850021999;residence.de.lherm@gmail.com;F;2020-10-04
850022385;accueil.berthomiere@orange.fr;F;2020-10-04
850022419;ehpad.la.tranche@wanadoo.fr;F;2020-10-15
850022781;ehpad.bretignollesmer@wanadoo.fr;F;2020-10-04
850022831;residence.pierre.rose@wanadoo.fr;F;2020-10-04
850022864;ehpad@mairie-mouilleronlecaptif.fr;F;2020-10-04
850023060;secretariat@residence-scdl.fr;F;2020-10-04
850023086;residencelasource@orange.fr;F;2020-10-04
850023102;secretariat@ehpadlechenevert.fr;F;2020-10-04
850023110;marpa.tiffauges@orange.fr;F;2020-10-04
850023136;accueil@ciasfontenay.fr;F;2020-10-04
850023912;marpa.lestilleuls@wanadoo.fr;F;2020-10-04
850023946;marpalesmyosotis@orange.fr;F;2020-10-04
850023961;contact@ehpadlacharmille.com;F;2020-10-04
850023987;marpa@mouchamps.com;F;2020-10-04
850024092;marpaleslavandieres@orange.fr;F;2020-10-04
850024456;direction@unionchretienne.fr;F;2020-10-04
850024746;ehpad.laroseraie@orange.fr;F;2020-10-04
850024951;accueil@handiespoir.fr;F;2020-10-04
850025172;ehpad.leshirondelles@wanadoo.fr;F;2020-10-04
850025230;ehpad.vaire@orange.fr;F;2020-10-04
850025602;ehpad.cordeliers@lessablesdolonne.fr;F;2020-10-15
850025701;marpa.auventdesmarais@gmail.com;F;2020-10-04
850025917;accueil@residenceguillonneau-challans.fr;F;2020-10-04
850025925;laresidenceduparc@admr85.org;F;2020-10-04
850026030;contact@marpalajosinette.fr;F;2020-10-04
850026105;marpa-residenceharmonie@orange.fr;F;2020-10-04
850026121;direction.tailfleuri@gmail.com;F;2020-10-04
850026170;information@puvlestamaris.fr;F;2020-10-04
850026196;marpa@reaumur.fr;F;2020-10-04
850027301;direction.marpa@laboissieredeslandes.fr;F;2020-10-04
850027913;direction@lesursulines.fr;F;2020-10-04
860006329;contact@ehpadgencay.fr;F;2020-10-04
860008549;info@logisvaldeboivre.fr;F;2020-10-04
860009778;logement-foyer-rouille@orange.fr;F;2020-10-04
860009943;ehpad-verrieres@departement86.fr;F;2020-10-04
860010388;ehpad-accueil@naintre.fr;F;2020-10-04
860010628;direction.lestournesols@gmail.com;F;2020-10-04
860010768;ehpadcouhe.direction@orange.fr;F;2020-10-04
860011444;accueil.ehpadlafontaine86@gmail.com;F;2020-10-15
860011683;ehpad@jaunay-clan.fr;F;2020-10-04
860012244;saint-sauvant-ccas@departement86.fr;F;2020-10-04
860012319;residence.renecrozet@poitiers.fr;F;2020-10-04
860012848;residence.margueriteletillier@poitiers.fr;F;2020-10-04
860780501;administration@ehpadlescapucines.fr;F;2020-10-04
860780717;direction@ehpad-la-brunetterie.org;F;2020-10-04
860780774;direction.lesgrandschenes@orange.fr;F;2020-10-04
860780790;contact@ehpadgencay.fr;F;2020-10-04
860780808;mairie@ville-loudun.fr;F;2020-10-04
860780816;direction.ehpad@naintre.fr;F;2020-10-06
860780840;residence.marienoel@poitiers.fr;F;2020-10-04
860780857;residence.renecrozet@poitiers.fr;F;2020-10-04
860780865;residencemarielouisetroubat@poitiers.fr;F;2020-10-04
860781996;ehpad.admission@ch-montmorillon.fr;F;2020-10-04
860782069;foyer-logement-availleslimouzine@orange.fr;F;2020-10-04
860784487;accueil.lescedres@orange.fr;F;2020-10-04
860784529;residence.oasis@ville-montmorillon.fr;F;2020-10-04
860785112;foyerlefloreal@gmail.com;F;2020-10-04
860785682;direction@ghnv.fr;F;2020-10-04
860789403;info@ehpad-lareverie.fr;F;2020-10-04
860789734;accueil.echeneau@groupe-aplus.com;F;2020-10-04
860789767;ehpad-secretariat@orange.fr;F;2020-10-06
860789916;mr-chaunay@orange.fr;F;2020-10-04
860789981;ehpad.latille@orange.fr;F;2020-10-04
860790005;ehpad-mouterre-sur-blourde@departement86.fr;F;2020-10-04
860790021;foyerresidenceduvaldevonne@orange.fr;F;2020-10-04
860790195;foyerlogementdecouhe@wanadoo.fr;F;2020-10-04
860790260;contact.ehpad@migne-auxances.fr;F;2020-10-04
860791037;administration.agapanthe@korian.fr;F;2020-10-04
860791128;contact@ehpad-pleumartin.fr;F;2020-10-04
870001740;accueildejour@mutualitelimousine.fr;F;2020-10-04
870003647;ehpad@puychat.fr;F;2020-10-04
870003720;direction@ch-st-yrieix.fr;F;2020-10-04
870003738;ehpad@pelaudine.fr;F;2020-10-04
870003746;secretariat.direction@ccm-ambazac.fr;F;2020-10-04
870003753;mr.rochechouart@croix-rouge.fr;F;2020-10-04
870003787;administration@ehpad-chalus.fr;F;2020-10-04
870003803;residenceducedre@wanadoo.fr;F;2020-10-04
870003829;foyer.raymondcoudert@wanadoo.fr;F;2020-10-04
870003886;residence.fleurie@ville-isle.fr;F;2020-10-04
870003902;ehpad.chateauponsac@wanadoo.fr;F;2020-10-04
870003910;ccasbellac@wanadoo.fr;F;2020-10-04
870005782;secretariat@ehpad-nantiat.fr;F;2020-10-04
870005790;direction@ch-st-yrieix.fr;F;2020-10-04
870005832;direction@chimb.fr;F;2020-10-04
870005857;ehpad.chateauponsac@wanadoo.fr;F;2020-10-04
870005949;secretariat@ehpad.cussac.fr;F;2020-10-04
870005972;residenceadeline@ehpad-pierrebuffiere.fr;F;2020-10-04
870005998;secretariat_ccas@ville-limoges.fr;F;2020-10-04
870006251;residence.lavaloine@wanadoo.fr;F;2020-10-04
870006277;administration@ehpad-nexon.fr;F;2020-10-04
870006913;mrbessines-accueil@sil.fr;F;2020-10-04
870006921;accueil@ehpad-jmahaut.fr;F;2020-10-04
870008133;direction@himb.fr;F;2020-10-04
870008745;direction@himb.fr;F;2020-10-04
870009222;residencelesbriances@ehpad-saintgermain.fr;F;2020-10-04
870010089;direction@ehpad-rochechouart.fr;F;2020-10-04
870010758;residenceleschenes@sil.fr;F;2020-10-04
870014487;direction@ch-stjunien.fr;F;2020-10-04
870016342;secretariat@soinsante-limoges.com;F;2020-10-04
870016417;ehpad.masrome@ville-limoges.fr;F;2020-10-04
880001763;reception.villaspinale@korian.fr;F;2020-10-04
880004999;secretariat-noisetiers@groupe-sos.org;F;2020-10-04
880005848;direction-bruyeres@groupe-sos.org;F;2020-10-04
880780564;accueil@laresidence-ozanam.fr;F;2020-10-04
880780697;secretariat@ehpad-dompaire.com;F;2020-10-04
880780713;maisonderetraite.eloyes@orange.fr;F;2020-10-04
880780788;contact@accueil-vologne.com;F;2020-10-04
880781059;mr-xertigny@wanadoo.fr;F;2020-10-04
880781141;contact@mrcharmes.fr;F;2020-10-04
880781158;mdrcorcieux@wanadoo.fr;F;2020-10-04
880781190;secretariat.plombieres@chasvm-valdajol.fr;F;2020-10-04
880781216;secretariat.val@chasvm-valdajol.fr;F;2020-10-04
880783139;direction@ch-ouestvosgien.fr;F;2020-10-04
880783386;ehpadlesolem@wanadoo.fr;F;2020-10-04
880783402;accueil@ehpad-lechatelet.fr;F;2020-10-04
880783428;maisonderetraite@labresse.fr;F;2020-10-04
880783444;ehpad.essegney@fms88.com;F;2020-10-04
880783451;contact@deodat88.fr;F;2020-10-04
880783543;direction@laccueil.net;F;2020-10-04
880783584;ehpad-lescharmes@ville-saintdie.fr;F;2020-10-04
880783592;accueil@homefleuri.com;F;2020-10-04
880783634;secretariat-dinoze@amamb.fr;F;2020-10-04
880785530;hopital-local.bussang@wanadoo.fr;F;2020-10-04
880786314;hopital@hl-chatel.fr;F;2020-10-04
880786322;direction@le-couaroge.fr;F;2020-10-04
880786330;contact@ehpad-darney.fr;F;2020-10-04
880786363;contact@hl-lamarche.fr;F;2020-10-04
880786371;direction@sante-lorraine.fr;F;2020-10-04
880786421;direction@hl-valmadon.fr;F;2020-10-04
880786447;residenceleonwerth@ch-remiremont.fr;F;2020-10-04
880786462;residenceantoine@orange.fr;F;2020-10-04
880786637;secretariat.usld@ch-remiremont.fr;F;2020-10-04
880788088;contact@lepontdugue.fr;F;2020-10-04
880788757;contact@ville-saintdie.fr;F;2020-10-04
880788773;direction@ch-ouestvosgien.fr;F;2020-10-04
880788849;direction@ch-ed.fr;F;2020-10-04
880789185;contact.stjeanportieux@mp88.fr;F;2020-10-04
880789268;ccas@remiremont.fr;F;2020-10-04
880789292;ccas@ville-vittel.fr;F;2020-10-04
890000110;contact@ehpad-nantou.fr;F;2020-10-04
890000276;direction@residenceadelie.fr;F;2020-10-04
890000425;direction@ch-sens.fr;F;2020-10-04
890002090;contact@ehpad-leshortensias.net;F;2020-10-04
890002124;direction@ehpadbouron.fr;F;2020-10-04
890002132;direction@ehpad-coulanges-sur-yonne.com;F;2020-10-15
890002140;contact@ehpad-courson.fr;F;2020-10-04
890002173;pontadmissions@orange.fr;F;2020-10-04
890002181;contact@ehpad-ravieres.fr;F;2020-10-04
890002199;contact@ehpad-stfargeau.fr;F;2020-10-04
890002215;contact@ehpad-toucy.fr;F;2020-10-04
890002223;contact@mrvermenton.com;F;2020-10-04
890002249;pontadmissions@orange.fr;F;2020-10-04
890002256;contact@ehpad-charny.fr;F;2020-10-04
890002272;contact@residencesaintjulien.fr;F;2020-10-04
890002330;ehpad-migennes@orange.fr;F;2020-10-04
890002421;contact@residence-gandrille.fr;F;2020-10-04
890002447;contact@coteaux.fr;F;2020-10-15
890002637;direction@ch-avallon.fr;F;2020-10-04
890002645;direction@ch-joigny.fr;F;2020-10-04
890002686;residence.mauricevillatte@wanadoo.fr;F;2020-10-04
890002751;mrtanlay@wanadoo.fr;F;2020-10-04
890004229;info@memoiresdebourgogne.com;F;2020-10-04
890005879;direction@hl-villeneuve.fr;F;2020-10-04
890007883;residencecolbert@free.fr;F;2020-10-04
890970023;asso.stloup@orange.fr;F;2020-10-04
890970270;foyer-bretauche@wanadoo.fr;F;2020-10-04
890970577;direction@ch-sens.fr;F;2020-10-04
890971492;direction@ch-auxerre.fr;F;2020-10-04
890971526;direction@residenceflore.com;F;2020-10-04
890971542;contact@residence-les-forges.com;F;2020-10-04
890971583;direction@ch-joigny.fr;F;2020-10-04
890971633;direction@ch-tonnerre.fr;F;2020-10-04
890971682;direction@hl-villeneuve.fr;F;2020-10-04
890972037;contact@residencejn.com;F;2020-10-04
890972227;direction@mdry.fr;F;2020-10-04
890972375;residence.club@wanadoo.fr;F;2020-10-04
890972441;secretariat.lesplatanes@orange.fr;F;2020-10-04
890972508;ehpad.aillanttholon@croix-rouge.fr;F;2020-10-04
890972920;direction@ch-sens.fr;F;2020-10-04
890973043;compta@lesjolisbois.fr;F;2020-10-15
890973118;directionboislancy@orange.fr;F;2020-10-04
890975683;ehpadlaprovidence@gmail.com;F;2020-10-04
900000647;direction@chsld-lechenois.fr;F;2020-10-04
900001538;foyerlouisclerc@orange.fr;F;2020-10-04
900001918;marpa.grandvillars@orange.fr;F;2020-10-04
900002056;direction@chsld-lechenois.fr;F;2020-10-04
900002189;ehpad.miotte@mut25.fr;F;2020-10-04
900002411;residence.pierre.bonnef@pompidou-belfort.com;F;2020-10-04
900003260;residence-stjoseph@giromagny.org;F;2020-10-04
900003328;direction@chlsd-lechenois.fr;F;2020-10-04
900003427;direction@chlsd-lechenois.fr;F;2020-10-04
900003435;residence.vauban@pompidou-belfort.com;F;2020-10-04
910002187;louis-pasteur.direction@arpavie.fr;F;2020-10-04
910002310;associationdelacour@wanadoo.fr;F;2020-10-04
910002351;foyer-logement@savigny.org;F;2020-10-04
910004159;residence.ballancourt@wanadoo.fr;F;2020-10-04
910006279;camille-desmoulins.direction@arpavie.fr;F;2020-10-04
910008358;accueil.bretigny@orpea.net;F;2020-10-04
910013978;accueilepinay@vieactive.asso.fr;F;2020-10-04
910015189;accueildejoursaintcheron@coallia.org;F;2020-10-04
910016377;ehpad.lamartiniere@ajl.asso.fr;F;2020-10-04
910016849;marpa.senart@orange.fr;F;2020-10-04
910017250;secretariat-mr@gpspv.fr;F;2020-10-04
910019058;contact@residence-le-plateau.com;F;2020-10-04
910019413;direction@ehpad91.fr;F;2020-10-04
910019462;direction@ehpad91.fr;F;2020-10-04
910021062;contact-bruyeres@coallia.org;F;2020-10-04
910021138;accueil.draveil@ehpad91.fr;F;2020-10-04
910021153;marpa.milly@orange.fr;F;2020-10-04
910021955;secretariat.direction@jfr.aphp.fr;F;2020-10-04
910040054;accueil.dourdan@ehpad91.fr;F;2020-10-12
910040112;accueil@massy-vilmorin.com;F;2020-10-04
910040245;st-thibault.direction@arpavie.fr;F;2020-10-04
910460096;direction@bois-verrieres.com;F;2020-10-04
910700319;accueil@rrcs.fr;F;2020-10-04
910700327;ehpad.leon-mauge@orange.fr;F;2020-10-04
910700426;accueil@brunoy.repotel.fr;F;2020-10-04
910700715;maisonderetraitedegommier@orange.fr;F;2020-10-04
910700723;direction@ehpad-charaintru.fr;F;2020-10-04
910701358;direction@ehpad91.fr;F;2020-10-04
910701374;boissiere.direction@arpavie.fr;F;2020-10-04
910701382;accueil@fondation-gutierrez.fr;F;2020-10-04
910701408;mardelles-direction@arpavie.fr;F;2020-10-04
910701424;accueil@massabielle.net;F;2020-10-04
910701515;direction.leboisjoli@probonon.fr;F;2020-10-04
910701564;ccas@longjumeau.fr;F;2020-10-04
910701614;reception.leflore@korian.fr;F;2020-10-04
910701622;direction@melavie.fr;F;2020-10-04
910701663;direction.lemanoir@teneris.fr;F;2020-10-04
910701697;accueil.saintry@orpea.net;F;2020-10-04
910701713;direction.lestilleuls@teneris.fr;F;2020-10-04
910701853;ehpad.lesmyosotis@gh-nord-essonne.fr;F;2020-10-04
910702232;gabriel-fontaine.direction@arpavie.fr;F;2020-10-04
910702265;beguinage.direction@arpavie.fr;F;2020-10-04
910800440;residence.parc91@orange.fr;F;2020-10-04
910800473;mesanges.direction@arpavie.fr;F;2020-10-04
910800499;jean-rostand.direction@arpavie.fr;F;2020-10-04
910800929;direction@ch-etampes.fr;F;2020-10-04
910801000;foyer-logement@savigny.org;F;2020-10-04
910801026;residencerameau@laposte.net;F;2020-10-04
910807023;accueilccas@orange.fr;F;2020-10-04
910807130;ccas.marcoussis@wanadoo.fr;F;2020-10-04
910808807;contact@residence-sofia.fr;F;2020-10-04
910811116;tournebride.direction@arpavie.fr;F;2020-10-04
910811728;usld@ch-arpajon.fr;F;2020-10-04
910812544;accueil.morignychampigny@groupecolisee.com;F;2020-10-04
910812593;accueil.athis@lemoulinvert.org;F;2020-10-04
910813138;contact@villanger.fr;F;2020-10-04
910813583;contact.asphodia@lna-sante.com;F;2020-10-04
910814078;ehpadbreuillet@coallia.org;F;2020-10-04
910815026;direction.epinay@agepartenaires.com;F;2020-10-04
910815992;lesmagnolias.hopital@hpgm.fr;F;2020-10-04
920000155;accueil.gerhome@lna-sante.com;F;2020-10-04
920004439;neuf-muses.direction@arpavie.fr;F;2020-10-04
920005279;contact@fondation-odilon-lannelongue.fr;F;2020-10-04
920005329;marcelle-devaud.direction@arpavie.fr;F;2020-10-04
920006129;direction.bagneux@orpea.net;F;2020-10-04
920006772;ehpadneuilly@ehpadneuilly.com;F;2020-10-04
920006863;direction@ehpadlev.fr;F;2020-10-04
920017308;accueil.chaville@villabeausoleil.com;F;2020-10-04
920019098;residencelabruyere@almage.com;F;2020-10-04
920024106;reception.lessarments@korian.fr;F;2020-10-04
920025202;administratifnanterre@vieactive.asso.fr;F;2020-10-04
920026507;accueil@ehpad-villa-borghese.fr;F;2020-10-04
920028982;administration.limperial@korian.fr;F;2020-10-04
920033032;reception.castelvoltaire@korian.fr;F;2020-10-04
920040060;accueil@pins-boulogne.com;F;2020-10-04
920040201;val-content.direction@arpavie.fr;F;2020-10-04
920040466;cote-noire.direction@arpavie.fr;F;2020-10-04
920460060;accueil@faiencerie-sceaux.com;F;2020-10-04
920710381;mdr-parc@orange.fr;F;2020-10-04
920710431;direction@ehpadsainte-emilie.fr;F;2020-10-04
920710621;contact@fondation-aulagnier.fr;F;2020-10-04
920710670;direction@issy.repotel.fr;F;2020-10-04
920710696;accueil@ehpad-lesmarronniers.fr;F;2020-10-04
920710704;secretariat.chatelet@fondationdiaconesses.org;F;2020-10-15
920710712;residence.boiscolombes@fondationbellan.org;F;2020-10-04
920710738;secretariat@ehpademilie.org;F;2020-10-04
920710746;residences.lelegard@ch4v.fr;F;2020-10-04
920710753;contact@ehpad-renaudin.fr;F;2020-10-04
920710811;vallee.direction@arpavie.fr;F;2020-10-04
920710829;ehpa-ccas@mairieasnieres.fr;F;2020-10-04
920710845;direction@residence-madeleine-verdier.fr;F;2020-10-04
920710860;ehpadneuilly@ehpadneuilly.com;F;2020-10-04
920711629;residencelameridienne@wanadoo.fr;F;2020-10-04
920711793;heures-claires.direction@arpavie.fr;F;2020-10-04
920711835;ccas@ville-antony.fr;F;2020-10-29
920711942;camille-cartier.direction@arpavie.fr;F;2020-10-04
920711967;direction.gennevilliers@repotel.fr;F;2020-10-04
920712064;marie-nodier.direction@arpavie.fr;F;2020-10-04
920800505;korian.administration@korian.fr;F;2020-10-04
920800828;direction.gcsms@mapad.onmicrosoft.com;F;2020-10-04
920802162;champfleury.direction@arpavie.fr;F;2020-10-04
920803467;terrasses-de-meudon.direction@arpavie.fr;F;2020-10-04
920803673;taratres.direction@arpavie.fr;F;2020-10-04
920803681;direction.ehpad@ch-rueil.fr;F;2020-10-04
920803996;accueil.montrouge@villabeausoleil.com;F;2020-10-04
920804077;residence.jeanrostand@ch4v.fr;F;2020-10-04
920804143;jours-heureux.direction@arpavie.fr;F;2020-10-04
920804317;sapins-bleus.direction@arpavie.fr;F;2020-10-04
920805025;direction@lesabondances.fr;F;2020-10-04
920805298;martignon.direction@arpavie.fr;F;2020-10-15
920806387;monfort.accueil@chatillon92.fr;F;2020-10-04
920807450;theophile-gautier.direction@arpavie.fr;F;2020-10-04
920808508;nadar-de-la-pagerie.direction@arpavie.fr;F;2020-10-04
920809811;direction@fondation-roguet.fr;F;2020-10-04
920809852;direction@fondation-roguet.fr;F;2020-10-04
920810918;vanne.direction@arpavie.fr;F;2020-10-04
920810942;lannelongue.direction@arpavie.fr;F;2020-10-04
920811304;direction@lachartraine.fr;F;2020-10-04
920812062;accueil.epidaure92@lna-sante.com;F;2020-10-04
920813094;reception.lestybilles@korian.fr;F;2020-10-04
920813797;reception.villaimperatrice@korian.fr;F;2020-10-04
920813862;direction@chcn.net;F;2020-10-04
920813896;parc.direction@arpavie.fr;F;2020-10-04
920814399;contact.arcade@lna-sante.com;F;2020-10-04
920814712;administration.mathurins@korian.fr;F;2020-10-04
920815610;accueil@residence-fontaine.fr;F;2020-10-04
930003397;ehpad.tremblay@lemoulinvert.org;F;2020-10-04
930007109;ehpad.drancy@lemoulinvert.asso.fr;F;2020-10-04
930015359;jacques-offenbach.direction@arpavie.fr;F;2020-10-04
930016951;residence-deglantine@orange.fr;F;2020-10-04
930019344;direction-4saisons@orange.fr;F;2020-10-04
930019369;ehpad.courneuve@lemoulinvert.org;F;2020-10-04
930019468;accueilmaisondusoleil@isatis.asso.fr;F;2020-10-04
930021084;secretariat-hector-berlioz@groupe-sos.org;F;2020-10-04
930021571;contact@residence-marie.com;F;2020-10-04
930021597;petronille.direction@arpavie.fr;F;2020-10-04
930023056;emile-zola.direction@arpavie.fr;F;2020-10-04
930023148;direction-noisy@lesopalines.fr;F;2020-10-04
930023163;accueil.drancy@villabeausoleil.com;F;2020-10-04
930023700;victor-hugo.direction@arpavie.fr;F;2020-10-04
930027073;ehpad.romainville@fondationbellan.org;F;2020-10-04
930420013;direction-oasis@groupe-sos.org;F;2020-10-04
930460068;direction@ehpadgm.org;F;2020-10-04
930460084;direction@ehpad-cmazier.fr;F;2020-10-04
930700208;accueil.lesfloralies@probtp.com;F;2020-10-04
930700257;cite-floreal.direction@arpavie.fr;F;2020-10-04
930700281;vert-galant.direction@arpavie.fr;F;2020-10-04
930701586;direction@ehpad-la-roseraie.fr;F;2020-10-04
930703152;ccas@mairie-saint-ouen.fr;F;2020-10-04
930704200;bocage.direction@arpavie.fr;F;2020-10-04
930705710;foyer@villedupre.fr;F;2020-10-04
930810635;marcel-bou.direction@arpavie.fr;F;2020-10-04
930810924;residence.basilique@ville-st-denis.fr;F;2020-10-04
930810932;residence.basilique@ville-st-denis.fr;F;2020-10-04
930815311;pins.direction@arpavie.fr;F;2020-10-04
930815527;accueil.lesfloralies@probtp.com;F;2020-10-04
930816723;beaux-monts.direction@arpavie.fr;F;2020-10-04
930816905;ehpad.stouen@lemoulinvert.org;F;2020-10-04
930817531;ehpad.aulnay@coallia.org;F;2020-10-04
930817580;clairieres.direction@arpavie.fr;F;2020-10-04
940000136;foyersoleil.bordieres@ville-creteil.fr;F;2020-10-04
940000169;foyer.soleil@mairie-champigny94.fr;F;2020-10-04
940000201;arcades.direction@arpavie.fr;F;2020-10-04
940003858;contact.vincennes@lna-sante.com;F;2020-10-04
940003882;residence.guittard@orange.fr;F;2020-10-04
940006638;direction.valenton@orpea.net;F;2020-10-04
940007909;direction@rpt94.fr;F;2020-10-04
940007958;accueil@residence-beauregard.fr;F;2020-10-04
940012339;direction-orangerie@refugecheminots.asso.fr;F;2020-10-04
940015019;secretariat-erik-satie@groupe-sos.org;F;2020-10-04
940017627;residence.kelman@casip-cojasor.fr;F;2020-10-04
940018963;admissions@fondation-favier.fr;F;2020-10-04
940020779;secretariat-direction@le-grand-age.fr;F;2020-10-04
940021439;secretariat-direction@mri-fontenay-sous-bois.fr;F;2020-10-04
940022205;contact.caudacienne@lna-sante.com;F;2020-10-04
940022379;admissions@fondation-favier.fr;F;2020-10-04
940022585;renon.direction@arpavie.fr;F;2020-10-04
940022841;contact.charlesfoix@cfx.aphp.fr;F;2020-10-04
940710122;admissions@fondation-favier.fr;F;2020-10-04
940712797;admissions@fondation-favier.fr;F;2020-10-04
940714660;accueil@gourlet-bontemps.fr;F;2020-10-04
940800683;accueilsaintfrancois@monsieurvincent.asso.fr;F;2020-10-04
940800816;accueil@ehpadafrica.fr;F;2020-10-04
940801285;direction@parc-santeny.com;F;2020-10-04
940803190;secretariat-direction@le-grand-age.fr;F;2020-10-04
940803240;ccas@joinvillelepont.fr;F;2020-10-04
940803265;ccas@joinvillelepont.fr;F;2020-10-04
940803273;ccas@joinvillelepont.fr;F;2020-10-04
940803745;maryse-bastie.direction@arpavie.fr;F;2020-10-04
940803828;residencejeannealbret@charentonlepont.fr;F;2020-10-04
940803935;chene-rouge.direction@arpavie.fr;F;2020-10-04
940804321;lozaits.direction@arpavie.fr;F;2020-10-04
940804347;hameau-de-mesly.direction@arpavie.fr;F;2020-10-04
940805039;residence-du-moulin@ville-cachan.fr;F;2020-10-04
940805096;residence.villarenee@wanadoo.fr;F;2020-10-04
940805260;secretariat.vignes@chiv.fr;F;2020-10-04
940805450;ccas@choisyleroi.fr;F;2020-10-04
940806037;residence.lestilleuls.sucy@orange.fr;F;2020-10-04
940806045;ehpad.artistes@wanadoo.fr;F;2020-10-04
940807530;secretariat-direction@le-grand-age.fr;F;2020-10-04
940807670;arletty.direction@arpavie.fr;F;2020-10-04
940807795;direction@rpt94.fr;F;2020-10-04
940808033;direction@rpt94.fr;F;2020-10-04
940811532;terrasses-de-sucy.direction@arpavie.fr;F;2020-10-04
940811789;accueil@villeneuve-saint-georges.fr;F;2020-10-04
940812175;robert-landry.direction@arpavie.fr;F;2020-10-04
940812506;secretariat.vignes@chiv.fr;F;2020-10-04
940813074;direction.sevigne@lna-sante.com;F;2020-10-04
940814742;verdi.direction@arpavie.fr;F;2020-10-04
940816432;residenceveil@isatis.asso.fr;F;2020-10-04
950000117;primeveres.direction@arpavie.fr;F;2020-10-04
950000372;direction@ghi-vexin.fr;F;2020-10-04
950002808;residence.desjardins@orange.fr;F;2020-10-04
950005009;accueil-neuville@epinomis.fr;F;2020-10-04
950009738;accueil-semiramis@epinomis.fr;F;2020-10-04
950014589;accueil.bouffemont@groupecolisee.com;F;2020-10-04
950015958;residence.goussainville@groupe-mieuxvivre.fr;F;2020-10-04
950040303;bonne-rencontre.direction@arpavie.fr;F;2020-10-04
950130021;direction@ehpad-pdfc.fr;F;2020-10-04
950460022;mr.montmorency@croix-rouge.fr;F;2020-10-04
950780304;mr@croix-rouge.fr;F;2020-10-04
950780353;info@residence-bellefontaine.fr;F;2020-10-04
950780395;ehpad@zemgor.com;F;2020-10-04
950780429;petits-balcons.direction@arpavie.fr;F;2020-10-04
950780551;accueil.cormeilles@villabeausoleil.com;F;2020-10-04
950780718;residence.carnelle@orange.fr;F;2020-10-04
950781682;cedres.direction@arpavie.fr;F;2020-10-04
950783225;fontaine.direction@arpavie.fr;F;2020-10-04
950783241;sablonniere.direction@arpavie.fr;F;2020-10-04
950783282;jeanne-darc.direction@arpavie.fr;F;2020-10-04
950783423;accueil.parmain@orpea.net;F;2020-10-04
950783464;direction@chabrand-thibault.com;F;2020-10-04
950783498;residence-utrillo.sannois@wanadoo.fr;F;2020-10-04
950783506;ccas-administration@viarmes.fr;F;2020-10-04
950800227;contact@residence-le-castel.com;F;2020-10-04
950800243;parc-fleuri.direction@arpavie.fr;F;2020-10-04
950800250;ehpad.anniebeauchais@croix-rouge.fr;F;2020-10-04
950801399;direction@ghi-vexin.fr;F;2020-10-04
950801449;direction@ght-novo.fr;F;2020-10-04
950801563;accueil.coteaux@ch-simoneveil.fr;F;2020-10-04
950801597;direction@ghi-vexin.fr;F;2020-10-14
950802033;accueil.soisy@agefo.fr;F;2020-10-04
950802496;contact@residence-les-pensees.com;F;2020-10-04
950802504;administration@lacommanderiedeshospitaliers.fr;F;2020-10-04
950802520;contact@lacerisaie.net;F;2020-10-04
950802546;accueil.saintvalery@orpea.net;F;2020-10-04
950802553;secretariat@villajeannedarc.fr;F;2020-10-04
950802579;direction.tamaris@vivaltovie.com;F;2020-10-04
950802686;accueil.wallon@ch-simoneveil.fr;F;2020-10-04
950805945;myosotis.direction@arpavie.fr;F;2020-10-04
950805994;yvonne-colas.direction@arpavie.fr;F;2020-10-04
950806042;jean-moracchini.direction@arpavie.fr;F;2020-10-04
950806331;residence.eglantier@aaas.fr;F;2020-10-04
950806372;pivoines.direction@arpavie.fr;F;2020-10-04
950806521;accueil.stbrice@agefo.fr;F;2020-10-04
950806539;closeraie.direction@arpavie.fr;F;2020-10-04
950806893;bastide.direction@arpavie.fr;F;2020-10-04
950807206;direction.gratien@sgmr-ouest.com;F;2020-10-04
950807370;direction@chantepiemancier.fr;F;2020-10-04
950807404;direction.saintpry@vivaltovie.com;F;2020-10-04
950807537;residence.lepatio@groupe-mieuxvivre.fr;F;2020-10-15
950807974;moliere.direction@arpavie.fr;F;2020-10-04
950808519;contact@maisonduparc.net;F;2020-10-04
950808865;helene-moutet.direction@arpavie.fr;F;2020-10-04
950808956;reception.lacroiseebleue@korian.fr;F;2020-10-04
950809269;direction-arcenciel@mapad.fr;F;2020-10-15
970100434;contact@chgeront-gpe.fr;F;2020-10-04
970108890;direction.bethanyhome@orange.fr;F;2020-10-04
970108908;contact@chgeront-gpe.fr;F;2020-10-04
970109302;accueil@soleyanou.fr;F;2020-10-04
970109658;residence.emeraude971@orange.fr;F;2020-10-04
970109856;reception-accueil@serpacaraibes.com;F;2020-10-04
970110078;ehpad.lesperlesgrises@gmail.com;F;2020-10-04
970111126;contact@akamanman.fr;F;2020-10-04
970111415;contact@chcbe-gpe.fr;F;2020-10-04
970202982;direction.mr.gliricidias@orange.fr;F;2020-10-04
970203048;secretariat@les-madrepores.fr;F;2020-10-04
970203477;foyer.de.tabitha@gmail.com;F;2020-10-04
970203519;contact@chilbp.fr;F;2020-10-04
970204293;direction@hopital-blondet.fr;F;2020-10-15
970204327;direction@ch3ilets.com;F;2020-10-04
970206330;infos@le-tempsdevivre.com;F;2020-10-04
970208856;oasis.ehpad@orange.fr;F;2020-10-04
970208948;ehpadresidencelorchidee@orange.fr;F;2020-10-15
970209029;accueil@ehpad-terrevillage.fr;F;2020-10-04
970209763;direction.marieolga-ancet@fondationpartageetvie.org;F;2020-10-04
970210340;accueil@floreaetangzabricot.com;F;2020-10-04
970210373;ehpadstehildegarde@gmail.com;F;2020-10-04
970210779;direction@ch-colson.fr;F;2020-10-04
970211181;direction@chnc972.fr;F;2020-10-04
970212866;accueildejour@case972.fr;F;2020-10-04
970212882;secretariat@asscam-ssiad.fr;F;2020-10-04
970303822;ehpadebene@wanadoo.fr;F;2020-10-04
970463048;direction@ch-sudreunion.fr;F;2020-10-04
$adresses_publiques_donnees$;
  v_bloc text;
  v_lignes integer;
  v_en_base integer;
  v_ecrites integer;
  v_remplacees integer;
  v_ouvertes integer;
  v_oppositions integer;
  v_ouvertes_avant text;
BEGIN
  v_bloc := btrim(v_donnees, E'\n');
  IF pg_catalog.md5(v_bloc) <> '6dc0d75a074214ed5ac3e390b0ae1d50' THEN
    RAISE EXCEPTION 'ADRESSES_PUBLIQUES_DONNEES_ALTEREES : le bloc de données ne correspond plus à son empreinte (md5 %).', pg_catalog.md5(v_bloc);
  END IF;

  WITH d AS (
    SELECT split_part(l, ';', 1) AS finess, split_part(l, ';', 2) AS email,
           split_part(l, ';', 3) AS classe, split_part(l, ';', 4) AS maj, l AS ligne
    FROM regexp_split_to_table(v_bloc, E'\n') AS l
  )
  SELECT count(*) INTO v_lignes
  FROM d
  WHERE d.ligne ~ '^[0-9]{9};[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,};F;[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    AND NOT private.fn_growth_email_mssante(d.email);
  IF v_lignes <> 5138
     OR (SELECT count(DISTINCT split_part(l, ';', 1)) FROM regexp_split_to_table(v_bloc, E'\n') AS l) <> 5138 THEN
    RAISE EXCEPTION 'ADRESSES_PUBLIQUES_DONNEES_INVALIDES : % ligne(s) conforme(s) sur 5138 attendues (format, messagerie fermée ou FINESS en double).', v_lignes;
  END IF;

  -- Photographie des adresses ouvertes des établissements du bloc, avant l'écriture.
  SELECT pg_catalog.md5(COALESCE(string_agg(p.finess || ';' || p.email, E'\n' ORDER BY p.finess), ''))
    INTO v_ouvertes_avant
  FROM public.prospects_etablissements p
  WHERE p.finess IN (SELECT split_part(l, ';', 1) FROM regexp_split_to_table(v_bloc, E'\n') AS l)
    AND NULLIF(btrim(p.email), '') IS NOT NULL
    AND btrim(p.email) ~* '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$'
    AND NOT private.fn_growth_email_mssante(p.email);

  WITH d AS (
    SELECT split_part(l, ';', 1) AS finess, split_part(l, ';', 2) AS email,
           split_part(l, ';', 3) AS classe, split_part(l, ';', 4) AS maj
    FROM regexp_split_to_table(v_bloc, E'\n') AS l
  ),
  etat AS (
    SELECT d.*, p.statut_sourcing,
           (NULLIF(btrim(p.email), '') IS NOT NULL
            AND btrim(p.email) ~* '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$'
            AND NOT private.fn_growth_email_mssante(p.email)) AS adresse_ouverte
    FROM d JOIN public.prospects_etablissements p ON p.finess = d.finess
  ),
  ecrit AS (
    UPDATE public.prospects_etablissements p
       SET email_provenance = jsonb_strip_nulls(jsonb_build_object(
             'email', e.email,
             'source_code', 'ANNUAIRE_PERSONNES_AGEES_DATA_GOUV',
             'source_url', 'https://www.data.gouv.fr/datasets/etablissements-ehpad-esld-residences-autonomie-accueils-de-jour',
             'source_publie_le', '2020-11-11',
             'source_maj_le', e.maj,
             'releve_le', '2026-11-24',
             'classe', 'FONCTION',
             'remplace', NULLIF(btrim(p.email), ''))),
           email = e.email,
           maj_le = now()
      FROM etat e
     WHERE p.finess = e.finess
       AND e.statut_sourcing <> 'OPPOSITION'
       AND NOT e.adresse_ouverte
    RETURNING (p.email_provenance ? 'remplace') AS remplacee
  )
  SELECT (SELECT count(*) FROM etat),
         (SELECT count(*) FROM ecrit),
         (SELECT count(*) FROM ecrit WHERE remplacee),
         (SELECT count(*) FROM etat WHERE adresse_ouverte AND statut_sourcing <> 'OPPOSITION'),
         (SELECT count(*) FROM etat WHERE statut_sourcing = 'OPPOSITION')
    INTO v_en_base, v_ecrites, v_remplacees, v_ouvertes, v_oppositions;

  -- Invariants de l'import (sinon toute la migration est annulée).
  IF v_ecrites + v_ouvertes + v_oppositions <> v_en_base THEN
    RAISE EXCEPTION 'ADRESSES_PUBLIQUES_IMPORT_INCOHERENT : % écrites + % ouvertes conservées + % oppositions <> % établissements retrouvés.',
      v_ecrites, v_ouvertes, v_oppositions, v_en_base;
  END IF;
  IF (SELECT pg_catalog.md5(COALESCE(string_agg(p.finess || ';' || p.email, E'\n' ORDER BY p.finess), ''))
      FROM public.prospects_etablissements p
      WHERE p.finess IN (SELECT split_part(l, ';', 1) FROM regexp_split_to_table(v_bloc, E'\n') AS l)
        AND p.email_provenance IS NULL
        AND NULLIF(btrim(p.email), '') IS NOT NULL
        AND btrim(p.email) ~* '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$'
        AND NOT private.fn_growth_email_mssante(p.email)) IS DISTINCT FROM v_ouvertes_avant THEN
    RAISE EXCEPTION 'ADRESSES_PUBLIQUES_IMPORT_ADRESSE_OUVERTE_MODIFIEE : une adresse ouverte existante a été modifiée par l''import.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.prospects_etablissements p
             WHERE p.statut_sourcing = 'OPPOSITION' AND p.email_provenance IS NOT NULL) THEN
    RAISE EXCEPTION 'ADRESSES_PUBLIQUES_IMPORT_OPPOSITION_TOUCHEE : un prospect en opposition porte une provenance.';
  END IF;

  RAISE NOTICE 'ADRESSES_PUBLIQUES_IMPORT : % lignes dans le bloc, % établissements retrouvés en base, % adresses écrites (dont % à la place d''une adresse en messagerie fermée ou mal formée), % adresses ouvertes existantes conservées, % prospects en opposition laissés tels quels.',
    v_lignes, v_en_base, v_ecrites, v_remplacees, v_ouvertes, v_oppositions;
END;
$adresses_publiques_import$;

-- ---------------------------------------------------------------------------
-- 3. Origine d'une adresse et mention d'opposition (source unique)
-- ---------------------------------------------------------------------------
-- Provenance VALIDE de l'adresse p_email du prospect p_finess, ou NULL : pas de
-- provenance, ou provenance d'une autre adresse (l'adresse a changé depuis).
CREATE OR REPLACE FUNCTION private.fn_growth_email_source(p_finess text, p_email text)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO ''
AS $body$
  SELECT p.email_provenance
  FROM public.prospects_etablissements p
  WHERE p.finess = p_finess
    AND NULLIF(btrim(p_email), '') IS NOT NULL
    AND p.email_provenance->>'email' = lower(btrim(p_email));
$body$;

-- Mention d'opposition d'un email de prospection, selon l'origine de l'adresse.
-- Source UNIQUE pour les premiers contacts et les relances : ne jamais
-- re-décider localement.
--   * annuaire des établissements pour personnes âgées : même phrase
--     d'opposition que la mention historique, origine exacte ;
--   * établissement dont le prospect ne porte AUCUNE provenance (ou fiche
--     sans prospect) : la mention historique (FINESS et Annuaire Santé),
--     comme avant ce lot ;
--   * tout le reste : NULL, donc aucun brouillon (l'agent compte ces cibles
--     dans exclus_sans_mention) — origine inconnue de ce code, saisie manuelle
--     (SAISIE_MANUELLE), et toute adresse qui n'est pas celle que décrit la
--     provenance du prospect (adresse changée depuis l'import, fiche CRM
--     corrigée à la main). Ajouter une source = ajouter sa mention ici, avec
--     ses sources dans la PR (CLAUDE.md, HARD STOP n°4).
-- Limite connue, antérieure à ce lot : une adresse saisie à la main dans
-- Sales, ou portée par une fiche CRM créée à la main, n'a pas de provenance et
-- reçoit la mention historique (docs/AGENTS_CROISSANCE.md §4 ter).
CREATE OR REPLACE FUNCTION private.fn_growth_mention_opposition(p_finess text, p_email text)
RETURNS text
LANGUAGE sql
STABLE
SET search_path TO ''
AS $body$
  SELECT CASE
    WHEN s.origine->>'source_code' = 'ANNUAIRE_PERSONNES_AGEES_DATA_GOUV' THEN private.fn_growth_config(
      'prospection_mention_opposition_annuaire_pa',
      'Votre adresse de contact provient de l''annuaire public des établissements pour personnes âgées (pour-les-personnes-agees.gouv.fr, données ouvertes publiées sur data.gouv.fr). Si vous ne souhaitez plus être contacté par Jolene, répondez simplement « STOP » à cet email : nous ne vous écrirons plus.')
    WHEN s.origine IS NULL AND NOT EXISTS (
      SELECT 1 FROM public.prospects_etablissements p
      WHERE p.finess = p_finess AND p.email_provenance IS NOT NULL
    ) THEN private.fn_growth_config('prospection_mention_opposition', NULL)
  END
  FROM (SELECT private.fn_growth_email_source(p_finess, p_email) AS origine) s;
$body$;

REVOKE ALL ON FUNCTION private.fn_growth_email_source(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.fn_growth_mention_opposition(text, text) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Décompte : adresses utilisables venues d'un annuaire public
-- ---------------------------------------------------------------------------
-- Corps LIVE (20261124123500) repris à l'identique, plus une clé.
CREATE OR REPLACE FUNCTION private.fn_growth_cibles_prospection()
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO ''
AS $body$
  SELECT jsonb_build_object(
    'departements', to_jsonb(private.fn_growth_config_liste('agents_departements_cibles', '75,92,56')),
    'etablissements_cibles', count(*),
    'adresses_fermees', count(*) FILTER (WHERE c.email_ferme),
    'adresses_utilisables', count(*) FILTER (WHERE c.email_utilisable),
    -- Dont celles qui viennent d'un annuaire public ouvert (provenance valide).
    'adresses_annuaire_public', count(*) FILTER (
      WHERE c.email_utilisable
        AND COALESCE(private.fn_growth_email_source(c.finess, c.email)->>'source_code', 'SAISIE_MANUELLE') <> 'SAISIE_MANUELLE'),
    'adresses_restantes', count(*) FILTER (WHERE c.email_utilisable AND c.disponible),
    'telephones_utilisables', count(*) FILTER (WHERE c.telephone_utilisable),
    'telephones_restants', count(*) FILTER (WHERE c.telephone_utilisable AND c.disponible))
  FROM private.fn_growth_prospects_cibles() c;
$body$;

REVOKE ALL ON FUNCTION private.fn_growth_cibles_prospection() FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Agent 1 — prospection email : mention et source selon l'origine de l'adresse
-- ---------------------------------------------------------------------------
-- Corps LIVE (20261124123500) repris à l'identique, à six endroits près :
-- trois variables, la mention et la provenance lues avant de rédiger un premier
-- contact (une origine sans mention est comptée et passée), la mention relue
-- pour chaque relance, la source et la provenance dans le contexte du brouillon
-- (premier contact, puis relance), le compteur exclus_sans_mention dans le résultat. Le verrou « mention
-- historique absente » reste en tête.
CREATE OR REPLACE FUNCTION private.fn_growth_agent_prospection()
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO ''
AS $body$
DECLARE
  v_depts text[] := private.fn_growth_config_liste('agents_departements_cibles', '75,92,56');
  v_quota integer := private.fn_growth_config_int('agents_prospection_quota_jour', 20, 0, 100);
  v_file_max integer := private.fn_growth_config_int('agents_prospection_file_max', 60, 0, 500);
  v_signature text := private.fn_growth_config('prospection_signature', E'Gabrielle\nFondatrice de Jolene');
  v_mention text := private.fn_growth_config('prospection_mention_opposition', NULL);
  v_deja integer;
  v_file integer;
  v_place integer;
  v_crees integer := 0;
  v_relances integer := 0;
  v_exclus_stop integer := 0;
  v_n integer;
  r record;
  c record;
  v_sujet text;
  v_corps text;
  v_lien text;
  v_accroche text;
  v_tension text;
  v_etape smallint;
  v_mention_cible text;
  v_source jsonb;
  v_sans_mention integer := 0;
BEGIN
  -- Sans mention d'opposition, aucun brouillon de prospection (verrou explicite).
  IF v_mention IS NULL THEN
    RAISE EXCEPTION 'growth_config.prospection_mention_opposition absente : brouillons de prospection bloqués (docs/AGENTS_CROISSANCE.md §Conformité)';
  END IF;

  SELECT count(*) INTO v_deja
  FROM public.growth_brouillons b
  WHERE b.agent = 'PROSPECTION_ETABLISSEMENT' AND b.sequence_etape = 1
    -- Un brouillon expiré par la correction MSSanté (20261116143942) ne consomme pas le quota du jour.
    AND NOT (b.statut = 'EXPIRE' AND b.motif_rejet IS NOT DISTINCT FROM private.fn_growth_motif_expiration_mssante())
    AND b.cree_le >= date_trunc('day', now() AT TIME ZONE 'Europe/Paris') AT TIME ZONE 'Europe/Paris';
  SELECT count(*) INTO v_file
  FROM public.growth_brouillons b
  WHERE b.agent = 'PROSPECTION_ETABLISSEMENT' AND b.statut = 'BROUILLON';
  v_place := greatest(0, least(v_quota - v_deja, v_file_max - v_file));

  -- Étape 1 : nouveaux prospects des marchés cibles, jamais contactés.
  -- Les départements alternent (rang par département) : la tension BMO ne
  -- doit pas concentrer toute la file sur un seul marché pilote.
  FOR r IN
    SELECT q.*
    FROM (
    SELECT s.*,
           s.pts_type + s.pts_email + s.pts_tel + s.pts_signal + s.pts_tension AS score_total,
           row_number() OVER (
             PARTITION BY s.departement
             ORDER BY s.pts_type + s.pts_email + s.pts_tel + s.pts_signal + s.pts_tension DESC, s.nom, s.finess
           ) AS rang_departement
    FROM (
      SELECT p.finess, p.nom, p.type_jolene, btrim(p.email) AS email, p.telephone,
             p.ville, p.departement,
             p.pts_type,
             CASE
               WHEN split_part(lower(p.email), '@', 1)
                    ~ '^(contact|accueil|direction|directeur|directrice|secretariat|info|rh|recrutement|admin|standard)'
                 THEN 10
               WHEN split_part(lower(p.email), '@', 2)
                    ~ '^(gmail|hotmail|yahoo|outlook|orange|wanadoo|free|sfr|laposte|live)\.'
                 THEN 0
               ELSE 5 END AS pts_email,
             CASE WHEN NULLIF(btrim(p.telephone), '') IS NOT NULL THEN 10 ELSE 0 END AS pts_tel,
             p.pts_signal, p.pts_tension, p.bmo
      -- Univers ciblé unique (départements, types, adresse ouverte, cible libre).
      FROM private.fn_growth_prospects_cibles() p
      WHERE p.email_utilisable AND p.disponible
    ) s
    ) q
    ORDER BY q.rang_departement, q.score_total DESC, q.nom, q.finess
  LOOP
    EXIT WHEN v_crees >= v_place;

    IF private.fn_growth_destinataire_bloque('PROSPECT_ETABLISSEMENT', r.finess, r.email, r.telephone, NULL) IS NOT NULL THEN
      v_exclus_stop := v_exclus_stop + 1;
      CONTINUE;
    END IF;
    -- Une même adresse (siège, groupe) ne reçoit qu'une séquence.
    IF EXISTS (
      SELECT 1 FROM public.growth_brouillons b
      WHERE lower(b.destinataire_email) = lower(r.email)
        AND (b.statut IN ('BROUILLON', 'VALIDE', 'ENVOYE')
             OR (b.statut = 'EXPIRE' AND b.valide_le IS NOT NULL))
    ) THEN
      CONTINUE;
    END IF;
    -- Mention d'opposition selon l'origine de l'adresse (source unique). Une
    -- origine sans mention ne reçoit aucun brouillon : comptée, puis passée.
    v_source := private.fn_growth_email_source(r.finess, r.email);
    v_mention_cible := private.fn_growth_mention_opposition(r.finess, r.email);
    IF v_mention_cible IS NULL THEN
      v_sans_mention := v_sans_mention + 1;
      CONTINUE;
    END IF;

    v_tension := NULL;
    IF r.bmo IS NOT NULL AND (r.bmo->>'difficulte_pct')::numeric >= 40 THEN
      v_tension := format(
        'Dans votre département (%s), France Travail recense %s projets de recrutement d''aides-soignants en %s, dont %s %% jugés difficiles par les employeurs (enquête BMO).',
        r.departement, r.bmo->>'projets', r.bmo->>'annee', r.bmo->>'difficulte_pct');
    END IF;

    IF r.type_jolene = 'ECOLE_SANTE' THEN
      v_lien := private.fn_growth_lien('/devenir-soignant', 'prospection', 'email',
        'agent-prospection', 'ecole-' || r.departement);
      v_sujet := 'Missions pour vos jeunes diplômés';
      v_corps := concat_ws(E'\n\n',
        'Bonjour,',
        'Je suis Gabrielle, fondatrice de Jolene, une plateforme qui met en relation des soignants et des établissements de santé pour des missions courtes : vacations, CDD courts et remplacements. L''inscription est gratuite pour les soignants.',
        format('Nous démarrons dans votre secteur et aimerions faire connaître Jolene aux jeunes diplômés de %s. Seriez-vous ouvert à un échange de 15 minutes pour voir comment la présenter à vos promotions (affiche, courte intervention ou information aux diplômés) ?', r.nom),
        'Présentation pour les soignants : ' || v_lien,
        'Bien cordialement,' || E'\n' || v_signature,
        v_mention_cible);
    ELSE
      v_accroche := CASE r.type_jolene
        WHEN 'EHPAD' THEN 'Pour un EHPAD, Jolene permet de couvrir un arrêt, un week-end ou une période de congés avec des aides-soignants et infirmiers, sans passer par une agence.'
        WHEN 'HANDICAP' THEN 'Pour un établissement médico-social, Jolene permet de trouver des aides-soignants, AES et infirmiers pour une absence ou un renfort ponctuel.'
        WHEN 'DOMICILE' THEN 'Pour un service de soins à domicile, Jolene permet de trouver des aides-soignants et infirmiers pour une absence ou un pic d''activité.'
        WHEN 'CENTRE_SANTE' THEN 'Pour un centre de santé, Jolene permet de trouver des remplaçants (médecins, infirmiers, kinésithérapeutes) pour une vacation ou une période de congés.'
        ELSE 'Pour un établissement de soins, Jolene permet de publier un besoin de renfort (infirmiers, aides-soignants, IBODE, IADE) et de recevoir des candidatures de professionnels vérifiés.'
      END;
      v_lien := private.fn_growth_lien('/recruter-soignants', 'prospection', 'email',
        'agent-prospection', lower(r.type_jolene) || '-' || r.departement);
      v_sujet := left('Renforts soignants pour ' || r.nom, 140);
      v_corps := concat_ws(E'\n\n',
        'Bonjour,',
        'Je suis Gabrielle, fondatrice de Jolene, une plateforme qui met directement en relation les établissements de santé et des soignants vérifiés pour des missions courtes : vacations, CDD courts et remplacements.',
        v_accroche,
        v_tension,
        E'Concrètement :\n- vous publiez une mission en quelques minutes ;\n- l''identité et les qualifications professionnelles des soignants sont contrôlées, notamment via le RPPS lorsqu''il existe ;\n- contrats et facturation sont générés automatiquement ;\n- 15 % HT de commission sur le montant de la mission, sans abonnement ni frais d''entrée : vous ne payez que si vous recrutez.',
        'Nous démarrons dans votre secteur et je vous propose d''accompagner personnellement la publication de votre première mission. Seriez-vous disponible 15 minutes cette semaine pour en parler ?',
        'Pour découvrir le fonctionnement : ' || v_lien,
        'Bien cordialement,' || E'\n' || v_signature,
        v_mention_cible);
    END IF;

    INSERT INTO public.growth_brouillons (
      agent, canal, cible_type, cible_id, destinataire_nom, destinataire_email,
      departement, profession, sequence_etape, sujet, corps, lien, contexte,
      score, idempotence_key, expire_le
    ) VALUES (
      'PROSPECTION_ETABLISSEMENT', 'EMAIL', 'PROSPECT_ETABLISSEMENT', r.finess,
      r.nom, r.email, r.departement, NULL, 1, v_sujet, v_corps, v_lien,
      jsonb_build_object(
        'type_etablissement', r.type_jolene,
        'ville', r.ville,
        'telephone', NULLIF(btrim(r.telephone), ''),
        'source', CASE WHEN v_source IS NULL
          THEN 'FINESS (établissement) + Annuaire Santé (email)'
          ELSE 'FINESS (établissement) + annuaire pour-les-personnes-agees.gouv.fr (email, jeu ouvert data.gouv.fr)' END,
        -- Origine de l'adresse : source, page du jeu, dates. L'ancienne adresse
        -- en messagerie fermée ne suit pas le brouillon.
        'email_source', v_source - 'remplace',
        'score', jsonb_build_object(
          'type', r.pts_type, 'email', r.pts_email, 'telephone', r.pts_tel,
          'signal_boamp_90j', r.pts_signal, 'tension_bmo_as', r.pts_tension),
        'bmo_as', r.bmo),
      r.score_total, 'prospection:' || r.finess || ':etape1', now() + interval '14 days'
    )
    ON CONFLICT (idempotence_key) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_crees := v_crees + v_n;
  END LOOP;

  -- Étapes 2 et 3 : relances des contacts CRM dont l'échéance est passée,
  -- sans réponse, toujours contactables. La cadence reste celle du CRM.
  FOR c IN
    SELECT sc.id, sc.nom, btrim(sc.email) AS email, sc.telephone, sc.finess,
           sc.departement, sc.type_etab, sc.sequence_etape
    FROM public.sales_contacts sc
    WHERE sc.type = 'ETABLISSEMENT'
      AND sc.sequence_active IS TRUE
      AND sc.prochaine_action_le <= now()
      AND sc.derniere_action_type = 'EMAIL_ENVOYE'
      AND sc.statut IN ('CONTACTE', 'RELANCE')
      AND COALESCE(sc.reponse, 'EN_ATTENTE') = 'EN_ATTENTE'
      AND sc.ne_plus_contacter IS NOT TRUE
      AND COALESCE(sc.archive, false) IS FALSE
      AND sc.sequence_etape BETWEEN 1 AND 2
      AND NULLIF(btrim(sc.email), '') IS NOT NULL
      -- MSSanté : une relance y serait rejetée comme le premier email.
      AND NOT private.fn_growth_email_mssante(sc.email)
      -- Seuls les contacts ouverts par cet agent : la mention de source reste exacte.
      AND EXISTS (
        SELECT 1 FROM public.growth_brouillons b0
        WHERE b0.agent = 'PROSPECTION_ETABLISSEMENT' AND b0.statut = 'ENVOYE'
          AND b0.cible_type = 'PROSPECT_ETABLISSEMENT' AND b0.cible_id = sc.finess
      )
    ORDER BY sc.prochaine_action_le
    LIMIT 50
  LOOP
    IF private.fn_growth_destinataire_bloque('CONTACT_CRM', c.id::text, c.email, c.telephone, c.finess) IS NOT NULL THEN
      v_exclus_stop := v_exclus_stop + 1;
      CONTINUE;
    END IF;
    -- La relance porte la mention de l'adresse à laquelle elle part.
    v_mention_cible := private.fn_growth_mention_opposition(c.finess, c.email);
    IF v_mention_cible IS NULL THEN
      v_sans_mention := v_sans_mention + 1;
      CONTINUE;
    END IF;
    v_etape := (c.sequence_etape + 1)::smallint;
    v_lien := private.fn_growth_lien('/recruter-soignants', 'prospection', 'email',
      'agent-prospection-relance', 'etape' || v_etape || '-' || COALESCE(c.departement, 'na'));
    IF v_etape = 2 THEN
      v_sujet := left('Re : renforts soignants pour ' || c.nom, 140);
      v_corps := concat_ws(E'\n\n',
        'Bonjour,',
        'Je me permets de revenir vers vous au sujet de Jolene. Si un remplacement se profile dans les prochaines semaines, je peux publier la mission avec vous au téléphone, en une dizaine de minutes.',
        'Le fonctionnement en bref : ' || v_lien,
        'Bien cordialement,' || E'\n' || v_signature,
        v_mention_cible);
    ELSE
      v_sujet := left('Dernier message — Jolene pour ' || c.nom, 140);
      v_corps := concat_ws(E'\n\n',
        'Bonjour,',
        'Dernier message de ma part : je ne vous relancerai plus. Si un besoin de renfort soignant devient d''actualité, il suffit de répondre à cet email et je vous rappelle.',
        v_lien,
        'Bien cordialement,' || E'\n' || v_signature,
        v_mention_cible);
    END IF;

    INSERT INTO public.growth_brouillons (
      agent, canal, cible_type, cible_id, destinataire_nom, destinataire_email,
      departement, sequence_etape, sujet, corps, lien, contexte, idempotence_key, expire_le
    ) VALUES (
      'PROSPECTION_ETABLISSEMENT', 'EMAIL', 'CONTACT_CRM', c.id::text, c.nom, c.email,
      c.departement, v_etape, v_sujet, v_corps, v_lien,
      jsonb_build_object('finess', c.finess, 'type_etablissement', c.type_etab,
        'telephone', NULLIF(btrim(c.telephone), ''), 'relance_crm', true,
        -- Origine de l'adresse de la relance, sans l'ancienne adresse fermée.
        'email_source', private.fn_growth_email_source(c.finess, c.email) - 'remplace'),
      'prospection:crm:' || c.id || ':etape' || v_etape, now() + interval '7 days'
    )
    ON CONFLICT (idempotence_key) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_relances := v_relances + v_n;
  END LOOP;

  RETURN jsonb_build_object(
    'brouillons_crees', v_crees + v_relances,
    'premiers_contacts', v_crees,
    'relances', v_relances,
    'places_du_jour', v_place,
    -- Places restées vides alors que toutes les cibles disponibles ont été examinées.
    'places_non_pourvues', greatest(0, v_place - v_crees),
    'exclus_stop', v_exclus_stop,
    -- Adresses dont l'origine n'a pas de mention d'opposition connue : aucun brouillon.
    'exclus_sans_mention', v_sans_mention,
    'departements', to_jsonb(v_depts),
    -- Décompte après ce passage : un zéro n'est plus muet (écran d'administration).
    'cibles', private.fn_growth_cibles_prospection());
END;
$body$;

REVOKE ALL ON FUNCTION private.fn_growth_agent_prospection() FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. Agent 5 — liste d'appels : d'abord les cibles qu'aucun email ne peut joindre
-- ---------------------------------------------------------------------------
-- Corps LIVE (20261124123500) repris à l'identique, à un critère de tri près.
CREATE OR REPLACE FUNCTION private.fn_growth_agent_appels()
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO ''
AS $body$
DECLARE
  v_quota integer := private.fn_growth_config_int('agents_appels_quota_semaine', 30, 0, 200);
  v_file_max integer := private.fn_growth_config_int('agents_appels_file_max', 60, 0, 500);
  v_semaine timestamptz := date_trunc('week', now() AT TIME ZONE 'Europe/Paris') AT TIME ZONE 'Europe/Paris';
  v_deja integer;
  v_file integer;
  v_place integer;
  v_crees integer := 0;
  v_exclus_stop integer := 0;
  v_numeros_deja_en_file integer := 0;
  v_examines integer := 0;
  v_n integer;
  v_numero text;
  r record;
BEGIN
  SELECT count(*) INTO v_deja
  FROM public.growth_brouillons b
  WHERE b.agent = 'APPEL_ETABLISSEMENT' AND b.cree_le >= v_semaine;
  SELECT count(*) INTO v_file
  FROM public.growth_brouillons b
  WHERE b.agent = 'APPEL_ETABLISSEMENT' AND b.statut = 'BROUILLON';
  v_place := greatest(0, least(v_quota - v_deja, v_file_max - v_file));

  FOR r IN
    SELECT q.*
    FROM (
      SELECT c.*,
             c.pts_type + c.pts_signal + c.pts_tension AS score_total,
             row_number() OVER (
               PARTITION BY c.departement
               -- Un établissement joignable par email attend l'agent email : les fiches
               -- d'appel vont d'abord à ceux qu'aucun email ne peut joindre.
               ORDER BY c.email_utilisable, c.pts_type + c.pts_signal + c.pts_tension DESC, c.nom, c.finess
             ) AS rang_departement
      FROM private.fn_growth_prospects_cibles() c
      WHERE c.telephone_utilisable AND c.disponible
    ) q
    ORDER BY q.rang_departement, q.score_total DESC, q.nom, q.finess
  LOOP
    -- Pas de borne avant les contrôles cible par cible : la boucle s'arrête
    -- quand les places sont pourvues, sinon elle examine toutes les cibles.
    EXIT WHEN v_crees >= v_place;
    v_examines := v_examines + 1;

    IF private.fn_growth_appel_bloque(r.finess, btrim(r.email), r.telephone) IS NOT NULL THEN
      v_exclus_stop := v_exclus_stop + 1;
      CONTINUE;
    END IF;
    -- Un même numéro (standard partagé, siège) n'est proposé qu'une fois, sous
    -- la même règle que la cible : seule une fiche jamais validée puis expirée
    -- le libère.
    v_numero := private.fn_growth_telephone_national(r.telephone);
    IF EXISTS (
      SELECT 1 FROM public.growth_brouillons b
      WHERE b.canal = 'TELEPHONE'
        AND private.fn_growth_telephone_national(b.contexte->>'telephone') = v_numero
        AND NOT (b.statut = 'EXPIRE' AND b.valide_le IS NULL)
    ) THEN
      v_numeros_deja_en_file := v_numeros_deja_en_file + 1;
      CONTINUE;
    END IF;

    INSERT INTO public.growth_brouillons (
      agent, canal, cible_type, cible_id, destinataire_nom, departement,
      corps, contexte, score, idempotence_key, expire_le
    ) VALUES (
      'APPEL_ETABLISSEMENT', 'TELEPHONE', 'PROSPECT_ETABLISSEMENT', r.finess,
      r.nom, r.departement, private.fn_growth_script_appel(r.type_jolene),
      jsonb_build_object(
        'type_etablissement', r.type_jolene,
        'ville', r.ville,
        'telephone', btrim(r.telephone),
        'source', 'Annuaires publics des établissements de santé (répertoire FINESS et Annuaire Santé)',
        'semaine', to_char(now() AT TIME ZONE 'Europe/Paris', 'IYYY-"S"IW'),
        'score', jsonb_build_object(
          'type', r.pts_type, 'signal_boamp_90j', r.pts_signal, 'tension_bmo_as', r.pts_tension)),
      r.score_total, 'appel:' || r.finess, now() + interval '14 days'
    )
    ON CONFLICT (idempotence_key) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_crees := v_crees + v_n;
  END LOOP;

  RETURN jsonb_build_object(
    'brouillons_crees', v_crees,
    'fiches_appel', v_crees,
    'places_de_la_semaine', v_place,
    -- Places restées vides alors que toutes les cibles disponibles ont été examinées.
    'places_non_pourvues', greatest(0, v_place - v_crees),
    'quota_semaine', v_quota,
    'fiches_de_la_semaine', v_deja + v_crees,
    'file_max', v_file_max,
    'fiches_en_file', v_file + v_crees,
    'candidats_examines', v_examines,
    'exclus_stop', v_exclus_stop,
    'numeros_deja_en_file', v_numeros_deja_en_file);
END;
$body$;

REVOKE ALL ON FUNCTION private.fn_growth_agent_appels() FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7. Post-conditions (sinon toute la migration est annulée)
-- ---------------------------------------------------------------------------
DO $adresses_publiques_apres$
DECLARE
  p record;
  v_n integer;
BEGIN
  FOR p IN
    SELECT v.signature, f.prosecdef, f.proconfig
    FROM (VALUES
      ('private.fn_growth_email_source(text,text)'),
      ('private.fn_growth_mention_opposition(text,text)'),
      ('private.fn_growth_cibles_prospection()'),
      ('private.fn_growth_agent_prospection()'),
      ('private.fn_growth_agent_appels()')
    ) AS v(signature)
    LEFT JOIN pg_catalog.pg_proc f ON f.oid = pg_catalog.to_regprocedure(v.signature)
  LOOP
    IF p.prosecdef IS NOT FALSE
      OR p.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
      OR pg_catalog.has_function_privilege('anon', p.signature, 'EXECUTE')
      OR pg_catalog.has_function_privilege('authenticated', p.signature, 'EXECUTE')
    THEN
      RAISE EXCEPTION 'ADRESSES_PUBLIQUES_POSTCONDITION : % (prosecdef %, search_path %) : attributs ou droits inattendus.',
        p.signature, p.prosecdef, p.proconfig;
    END IF;
  END LOOP;

  -- Sans prospect ni provenance : pas d'origine, et la mention historique, telle que configurée.
  IF private.fn_growth_email_source('POSTCONDITION', 'postcondition@jolene.invalid') IS NOT NULL
    OR private.fn_growth_mention_opposition('POSTCONDITION', 'postcondition@jolene.invalid')
       IS DISTINCT FROM private.fn_growth_config('prospection_mention_opposition', NULL)
  THEN
    RAISE EXCEPTION 'ADRESSES_PUBLIQUES_POSTCONDITION : une adresse sans provenance doit recevoir la mention historique.';
  END IF;
  -- Un établissement dont la provenance décrit une autre adresse : aucune mention pour celle-ci.
  SELECT count(*) INTO v_n
  FROM (SELECT pe.finess FROM public.prospects_etablissements pe
        WHERE pe.email_provenance IS NOT NULL ORDER BY pe.finess LIMIT 50) h
  WHERE private.fn_growth_mention_opposition(h.finess, 'postcondition@jolene.invalid') IS NOT NULL;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'ADRESSES_PUBLIQUES_POSTCONDITION : % établissement(s) à provenance prêtent une mention à une adresse qu''elle ne décrit pas.', v_n;
  END IF;
  -- L'adresse enregistrée sur un prospect sans provenance garde la mention historique, telle que configurée.
  SELECT count(*) INTO v_n
  FROM (SELECT pe.finess, pe.email FROM public.prospects_etablissements pe
        WHERE pe.email_provenance IS NULL AND NULLIF(btrim(pe.email), '') IS NOT NULL
        ORDER BY pe.finess LIMIT 50) h
  WHERE private.fn_growth_mention_opposition(h.finess, h.email)
        IS DISTINCT FROM private.fn_growth_config('prospection_mention_opposition', NULL);
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'ADRESSES_PUBLIQUES_POSTCONDITION : % adresse(s) sans provenance ne reçoivent pas la mention historique.', v_n;
  END IF;

  -- Chaque provenance écrite décrit l'adresse du prospect, ouverte, et sa mention existe.
  SELECT count(*) INTO v_n
  FROM public.prospects_etablissements pe
  WHERE pe.email_provenance IS NOT NULL
    AND (pe.email IS DISTINCT FROM pe.email_provenance->>'email'
         OR private.fn_growth_email_mssante(pe.email)
         OR private.fn_growth_email_source(pe.finess, pe.email) IS NULL
         OR private.fn_growth_mention_opposition(pe.finess, pe.email) IS NULL
         OR private.fn_growth_mention_opposition(pe.finess, pe.email)
            IS NOT DISTINCT FROM private.fn_growth_config('prospection_mention_opposition', NULL));
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'ADRESSES_PUBLIQUES_POSTCONDITION : % adresse(s) importée(s) sans provenance valide, en messagerie fermée ou sans mention propre.', v_n;
  END IF;

  IF (private.fn_growth_cibles_prospection()->>'adresses_annuaire_public') IS NULL THEN
    RAISE EXCEPTION 'ADRESSES_PUBLIQUES_POSTCONDITION : le décompte ne porte pas adresses_annuaire_public.';
  END IF;
END;
$adresses_publiques_apres$;
