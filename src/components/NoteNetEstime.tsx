/**
 * Note de bas de page unique expliquant l'astérisque « Net estimé* » affiché
 * sur les surfaces revenus / missions du soignant (Aperçu revenus, Accueil,
 * liste missions, recherche). Source unique → libellé cohérent partout : avant,
 * l'astérisque « pendait » sans définition selon les écrans.
 *
 * Formulation volontairement neutre en régime : « cotisations sociales estimées »
 * couvre le salarié (cotisations salariales ~22 %) comme le libéral (charges
 * provisionnées) sans sur-promettre un chiffre exact.
 */
export function NoteNetEstime({ className = '' }: { className?: string }) {
  return (
    <p className={`text-[11px] text-muted-foreground ${className}`}>
      * Net estimé après cotisations sociales estimées. Le montant définitif est
      confirmé après validation des présences par l'établissement.
    </p>
  );
}
