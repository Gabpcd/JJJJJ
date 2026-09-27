import type { Locator } from '@playwright/test';

export function luminance(couleur: number[]) {
  return couleur.slice(0, 3).reduce((total, composante, index) => {
    const s = composante / 255;
    return total + [0.2126, 0.7152, 0.0722][index]
      * (s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4);
  }, 0);
}

export function rapportContraste(a: number[], b: number[]) {
  const x = luminance(a), y = luminance(b);
  return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
}

export function composerCouleurs(dessus: number[], dessous: number[]) {
  const alpha = dessus[3] / 255, beta = dessous[3] / 255;
  const resultat = alpha + beta * (1 - alpha);
  return resultat === 0 ? [0, 0, 0, 0] : [
    ...dessus.slice(0, 3).map((canal, index) => (canal * alpha + dessous[index] * beta * (1 - alpha)) / resultat),
    resultat * 255,
  ];
}

export function echantillonnerDegrade(arrets: number[][]) {
  return arrets.slice(1).flatMap((arret, index) => Array.from({ length: 65 }, (_, pas) => {
    const t = pas / 64;
    return arret.map((canal, composante) => arrets[index][composante] * (1 - t) + canal * t);
  }));
}

/** Texte découpé dans un dégradé : axe ne mesure pas ses glyphes transparents.
 * Les fonds unis des ancêtres sont composités ; les images et opacités sont
 * rapportées pour que le scénario refuse de les ignorer silencieusement.
 */
export async function mesurerTexteDegrade(cible: Locator) {
  const couleurs = await cible.evaluate(element => {
    const canvas = document.createElement('canvas'); canvas.width = canvas.height = 1;
    const contexte = canvas.getContext('2d')!;
    const rgba = (couleur: string) => {
      contexte.clearRect(0, 0, 1, 1); contexte.fillStyle = couleur; contexte.fillRect(0, 0, 1, 1);
      return Array.from(contexte.getImageData(0, 0, 1, 1).data);
    };
    const style = getComputedStyle(element);
    const ancetres = [];
    for (let parent = element.parentElement; parent; parent = parent.parentElement) {
      const parentStyle = getComputedStyle(parent);
      ancetres.push({ fond: rgba(parentStyle.backgroundColor), image: parentStyle.backgroundImage, opacite: Number(parentStyle.opacity) });
    }
    return {
      texte: element.textContent, image: style.backgroundImage,
      arrets: (style.backgroundImage.match(/rgba?\([^)]+\)/g) ?? []).map(rgba),
      clip: style.backgroundClip, remplissage: style.webkitTextFillColor,
      remplissageRgba: rgba(style.webkitTextFillColor),
      taille: parseFloat(style.fontSize), graisse: style.fontWeight,
      opacite: Number(style.opacity), ancetres,
    };
  });
  const fond = [...couleurs.ancetres].reverse().reduce((dessous, ancetre) => composerCouleurs(ancetre.fond, dessous), [0, 0, 0, 0]);
  const rapports = echantillonnerDegrade(couleurs.arrets).map(texte => rapportContraste(texte, fond));
  return { ...couleurs, fond, minimum: rapports.length ? Math.min(...rapports) : 0 };
}
