import { describe, expect, it, vi } from 'vitest';
import { jsPDF } from 'jspdf';
import { createInfoBlock, PAGE } from './pdf-design-system';

describe('Blocs PDF : retour à la ligne dans la colonne', () => {
 it('conserve intégralement un email long sans sortir de la colonne destinataire', () => {
  const doc = new jsPDF();
  const texte = vi.spyOn(doc, 'text');
  const email = 'connect-test-fcaa6c97-46c1-4da9-8f74-1395aed616c5@example.invalid';
  const y = createInfoBlock(doc, { x:115,y:44,width:81,label:'Facturé à',name:'Établissement synthétique',lines:[email,'Ligne suivante'] });
  const lignes = texte.mock.calls.slice(2).map(([text,x,y]) => ({text:String(text),x:Number(x),y:Number(y)}));
  const morceauxEmail = lignes.slice(0,-1);
  expect(morceauxEmail.length).toBeGreaterThan(1);
  expect(morceauxEmail.map(ligne=>ligne.text).join('')).toBe(email);
  for (const ligne of lignes) expect(ligne.x + doc.getTextWidth(ligne.text)).toBeLessThanOrEqual(PAGE.width-PAGE.margin+0.01);
  expect(lignes.at(-1)?.text).toBe('Ligne suivante');
  expect(lignes.at(-1)!.y).toBeGreaterThan(morceauxEmail.at(-1)!.y);
  expect(y).toBeGreaterThan(lignes.at(-1)!.y);
 });
 it('fait suivre l’adresse après toutes les lignes d’un nom long', () => {
  const doc = new jsPDF(); const texte=vi.spyOn(doc,'text');
  createInfoBlock(doc,{x:115,y:44,width:81,label:'Facturé à',name:'Un établissement de soins au nom particulièrement long qui exige plusieurs lignes',lines:['Adresse conservée']});
  const appels=texte.mock.calls;
  expect(appels.length).toBeGreaterThan(3);
  expect(appels.at(-1)?.[0]).toBe('Adresse conservée');
  expect(Number(appels.at(-1)?.[2])).toBeGreaterThan(Number(appels.at(-2)?.[2]));
 });
});
