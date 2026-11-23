/**
 * Fenêtre d'un cron pg_cron à période fixe, pour les tests joués contre la base partagée.
 *
 * Un test qui place une donnée dans un état que le cron transforme (mission datée dans le passé,
 * par exemple) a une section critique : si le cron passe pendant qu'elle s'exécute, il échoue sans
 * défaut du produit. Ce module calcule l'attente qui place toute la section entre deux passages.
 * Fonction pure, sans horloge ni réseau : l'appelant fournit l'heure et attend lui-même.
 *
 * Mesure de référence (cron.job_run_details, 23 885 passages d'« auto-transitions-missions » du
 * 10/06 au 23/11/2026) : démarrage au plus 1,0 s après la minute dans 99 % des cas, durée au plus
 * 0,84 s dans 99 % des cas.
 */

const UNE_HEURE_MS = 3_600_000;

/**
 * @param {number} maintenantMs Horodatage Unix en millisecondes.
 * @param {{ periodeMs: number, sectionCritiqueMs: number, margeApresPassageMs: number }} fenetre
 *   periodeMs : période du cron, diviseur d'une heure (« *\/10 * * * * » → 600 000) ;
 *   sectionCritiqueMs : durée pendant laquelle le cron ne doit pas passer ;
 *   margeApresPassageMs : temps laissé au cron pour démarrer et se terminer après la minute.
 * @returns {number} Millisecondes à attendre avant d'entrer dans la section critique (0 si aucune).
 */
export function delaiAvantFenetreCron(maintenantMs, { periodeMs, sectionCritiqueMs, margeApresPassageMs }) {
  const entierPositif = valeur => Number.isSafeInteger(valeur) && valeur > 0;
  if (!Number.isSafeInteger(maintenantMs) || maintenantMs < 0) throw new Error('FENETRE_CRON_HEURE_INVALIDE');
  // Un cron « */N » tombe sur les multiples de N minutes de chaque heure : ils coïncident avec les
  // multiples de la période depuis l'époque Unix seulement si la période divise une heure.
  if (!entierPositif(periodeMs) || UNE_HEURE_MS % periodeMs !== 0) throw new Error('FENETRE_CRON_PERIODE_INVALIDE');
  if (!entierPositif(sectionCritiqueMs) || !entierPositif(margeApresPassageMs)
    || sectionCritiqueMs + margeApresPassageMs >= periodeMs) throw new Error('FENETRE_CRON_SECTION_INVALIDE');
  const depuisDernierPassage = maintenantMs % periodeMs;
  // Le passage qui vient de sonner n'a peut-être pas fini.
  if (depuisDernierPassage < margeApresPassageMs) return margeApresPassageMs - depuisDernierPassage;
  const avantProchainPassage = periodeMs - depuisDernierPassage;
  // La section ne tiendrait pas avant le prochain passage : la commencer après lui.
  if (avantProchainPassage <= sectionCritiqueMs) return avantProchainPassage + margeApresPassageMs;
  return 0;
}

/**
 * Cron « auto-transitions-missions » (« *\/10 * * * * », fn_auto_transitions_missions) : expire une
 * mission OUVERTE commencée depuis plus d'une heure et termine une mission ASSIGNEE finie depuis
 * plus de quinze minutes.
 */
export const FENETRE_AUTO_TRANSITIONS_MISSIONS = Object.freeze({
  periodeMs: 600_000,
  sectionCritiqueMs: 45_000,
  margeApresPassageMs: 10_000,
});
