/** Affichage seulement. ROUND(numeric, 2) positif : HT, puis TVA, en centimes. */
export function estimerCommissionEnCentimes(
  honorairesCents: number,
  tauxPourcent: number,
): { ht: number; tva: number } | null {
  if (!Number.isSafeInteger(honorairesCents) || honorairesCents < 0
      || !Number.isFinite(tauxPourcent) || tauxPourcent < 0 || tauxPourcent > 100) return null;
  // Conserve le taux décimal reçu, y compris les taux groupe avec plus de deux
  // décimales : aucun nouvel arrondi du taux ni approximation EPSILON.
  const [mantisse, exposant = '0'] = String(tauxPourcent).toLowerCase().split('e');
  const [entier, fraction = ''] = mantisse.split('.');
  const echelle = fraction.length - Number(exposant);
  const numerateurTaux = BigInt(entier + fraction) * (echelle < 0 ? 10n ** BigInt(-echelle) : 1n);
  const denominateurTaux = echelle > 0 ? 10n ** BigInt(echelle) : 1n;
  const arrondir = (numerateur: bigint, denominateur: bigint) =>
    (2n * numerateur + denominateur) / (2n * denominateur);
  const ht = arrondir(BigInt(honorairesCents) * numerateurTaux, 100n * denominateurTaux);
  const tva = arrondir(ht * 20n, 100n);
  if (ht + tva + BigInt(honorairesCents) > BigInt(Number.MAX_SAFE_INTEGER)) return null;
  return { ht: Number(ht), tva: Number(tva) };
}
