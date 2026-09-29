/**
 * Note de bas de page unique expliquant l'astérisque « Net estimé* » affiché
 * sur les surfaces revenus / missions du soignant (Aperçu revenus, Accueil,
 * liste missions, recherche). Source unique → libellé cohérent partout : avant,
 * l'astérisque « pendait » sans définition selon les écrans.
 *
 * La recherche peut aussi afficher un brut tant que le régime de la mission
 * n'est pas arrêté. La note couvre donc explicitement les deux cas.
 */
export function NoteNetEstime({ className = '' }: { className?: string }) {
  return (
    <p className={`text-[11px] text-muted-foreground ${className}`}>
      * Pour une mission salariée, le net est estimé après cotisations sociales et avant prélèvement à la source.
      Tant que le régime n'est pas choisi, le montant affiché reste une rémunération
      brute indicative. Cette estimation peut différer du net du bulletin officiel établi par
      l’employeur ou son service paie.
    </p>
  );
}
