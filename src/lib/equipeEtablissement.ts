export interface MembreEquipeMinimal {
  id: string;
  role: string;
  actif: boolean;
}

/**
 * Un propriétaire actif ne peut être rétrogradé ni révoqué si cela laisserait
 * l’établissement sans propriétaire. Le serveur impose aussi cette règle ; ce
 * prédicat évite d’afficher dans l’interface des actions vouées à échouer.
 */
export function estDernierProprietaireActif(
  membre: MembreEquipeMinimal,
  membres: MembreEquipeMinimal[],
): boolean {
  if (!membre.actif || membre.role !== 'PROPRIETAIRE') return false;
  return membres.filter((candidat) => candidat.actif && candidat.role === 'PROPRIETAIRE').length <= 1;
}
