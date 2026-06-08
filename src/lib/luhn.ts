/**
 * Validation SIRET avec algorithme de Luhn.
 * Pour chaque chiffre en position paire (depuis la droite, 0-indexed),
 * doubler la valeur ; si > 9, soustraire 9. Somme divisible par 10 = valide.
 */
export function validerSiret(siret: string): { valide: boolean; message: string } {
  const cleaned = siret.replace(/\s/g, '');

  if (!/^\d{14}$/.test(cleaned)) {
    return { valide: false, message: 'Le SIRET doit contenir 14 chiffres' };
  }

  if (/^0+$/.test(cleaned)) {
    return { valide: false, message: 'SIRET invalide' };
  }

  let sum = 0;
  for (let i = 0; i < 14; i++) {
    let digit = parseInt(cleaned[i], 10);
    // Position paire depuis la droite = index impair depuis la gauche (0-indexed)
    // Positions depuis la droite: pos 13-i. Paire = (13-i) % 2 === 0 => i impair? Non.
    // Standard Luhn: en partant de la droite, position 0 = dernier chiffre (pas doublé),
    // position 1 = doublé, position 2 = pas doublé, etc.
    // Position depuis la droite = 13 - i. Doublé si (13 - i) % 2 === 1 => i % 2 === 0
    if (i % 2 === 0) {
      digit *= 2;
      if (digit > 9) digit -= 9;
    }
    sum += digit;
  }

  if (sum % 10 !== 0) {
    return { valide: false, message: 'Ce numéro SIRET est invalide. Vérifiez les 14 chiffres sur votre avis de situation INSEE.' };
  }

  return { valide: true, message: 'SIRET valide' };
}
