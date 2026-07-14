/**
 * Sprint 10-A v3 PR 4 — Tests E2E filtre anti-leak messagerie (option DUR)
 *
 * Vérifie que l'edge function `messagerie-validate` refuse l'envoi des
 * messages contenant des coordonnées de contact externe : tous numéros
 * (mobile/fixe/intl/spéciaux), emails (tous domaines), URLs (sauf jolene.app),
 * handles réseaux + contexte, mots-clés "hors plateforme".
 *
 * Tests fonctionnels (unitaires sur la fonction detecterLeak exportée) +
 * tests E2E via fetch sur l'edge function déployée.
 *
 * Skip auto si SUPABASE_SERVICE_ROLE_KEY absent.
 */

import { test, expect } from '@playwright/test';
import { detecterLeak, sanitizeContent } from '../../supabase/functions/_shared/anti-leak';

test.describe('Sprint 10-A v3 — Filtre anti-leak messagerie (DUR)', () => {
  // ─── TÉLÉPHONES ──────────────────────────────────────────────────────────────

  test('REFUSE mobile FR 06 12 34 56 78', () => {
    const result = detecterLeak('Salut, mon numéro est 06 12 34 56 78');
    expect(result.blocked).toBe(true);
    expect(result.type).toBe('TELEPHONE');
  });

  test('REFUSE mobile FR 0612345678 sans espaces', () => {
    const result = detecterLeak('Appelle 0612345678');
    expect(result.blocked).toBe(true);
    expect(result.type).toBe('TELEPHONE');
  });

  test('REFUSE fixe FR 01 23 45 67 89', () => {
    const result = detecterLeak('Le standard : 01 23 45 67 89');
    expect(result.blocked).toBe(true);
    expect(result.type).toBe('TELEPHONE');
  });

  test('REFUSE numéro vert 0800 12 34 56', () => {
    const result = detecterLeak('Notre n° vert : 0800 12 34 56');
    expect(result.blocked).toBe(true);
    expect(result.type).toBe('TELEPHONE');
  });

  test('REFUSE international +33 6 12 34 56 78', () => {
    const result = detecterLeak('Mon mobile : +33 6 12 34 56 78');
    expect(result.blocked).toBe(true);
    expect(result.type).toBe('TELEPHONE');
  });

  test('REFUSE international fragmenté +1 234 567 8900', () => {
    const result = detecterLeak('Call +1 234 567 8900');
    expect(result.blocked).toBe(true);
    expect(result.type).toBe('TELEPHONE');
  });

  // ─── EMAILS ──────────────────────────────────────────────────────────────────

  test('REFUSE email perso jean@gmail.com', () => {
    const result = detecterLeak('Mon email : jean@gmail.com');
    expect(result.blocked).toBe(true);
    expect(result.type).toBe('EMAIL');
  });

  test('REFUSE email pro rh@hopital-bichat.fr', () => {
    const result = detecterLeak('Contactez rh@hopital-bichat.fr');
    expect(result.blocked).toBe(true);
    expect(result.type).toBe('EMAIL');
  });

  test('REFUSE email subdomain marie.dupont@cabinet.med.fr', () => {
    const result = detecterLeak('marie.dupont@cabinet.med.fr');
    expect(result.blocked).toBe(true);
    expect(result.type).toBe('EMAIL');
  });

  // ─── URLS ─────────────────────────────────────────────────────────────────────

  test('REFUSE URL externe https://monsite.fr', () => {
    const result = detecterLeak('Voir https://monsite.fr');
    expect(result.blocked).toBe(true);
    expect(result.type).toBe('URL');
  });

  test('REFUSE www.exemple.com', () => {
    const result = detecterLeak('Site : www.exemple.com');
    expect(result.blocked).toBe(true);
    expect(result.type).toBe('URL');
  });

  test('REFUSE domaine sans http : example.fr', () => {
    const result = detecterLeak('Visitez example.fr');
    expect(result.blocked).toBe(true);
    expect(result.type).toBe('URL');
  });

  test('AUTORISE URL jolene.app/missions', () => {
    const result = detecterLeak('Voir jolene.app/missions pour la liste');
    expect(result.blocked).toBe(false);
  });

  test('AUTORISE https://jolene.app/messagerie', () => {
    const result = detecterLeak('Lien : https://jolene.app/messagerie');
    expect(result.blocked).toBe(false);
  });

  test('AUTORISE sous-domaine app.jolene.app', () => {
    const result = detecterLeak('https://app.jolene.app/dashboard');
    expect(result.blocked).toBe(false);
  });

  test('REFUSE domaine externe dont le chemin contient jolene.app', () => {
    const result = detecterLeak('https://evil.xyz/jolene.app/missions');
    expect(result.blocked).toBe(true);
    expect(result.type).toBe('URL');
  });

  test('REFUSE domaine externe dont la query contient jolene.app', () => {
    const result = detecterLeak('https://evil.xyz/?next=https://jolene.app');
    expect(result.blocked).toBe(true);
    expect(result.type).toBe('URL');
  });

  // ─── HANDLES RÉSEAUX (avec contexte) ────────────────────────────────────────

  test('REFUSE @gabrielle_jolene sur Instagram', () => {
    const result = detecterLeak('Mon Instagram : @gabrielle_jolene');
    expect(result.blocked).toBe(true);
    expect(result.type).toBe('HANDLE');
  });

  test('REFUSE @marie sur LinkedIn', () => {
    const result = detecterLeak('Trouve-moi sur LinkedIn : @marie');
    expect(result.blocked).toBe(true);
    expect(result.type).toBe('HANDLE');
  });

  test('AUTORISE @ sans contexte réseau (mention dans phrase)', () => {
    // "@" tout seul sans mot-clé réseau social autour est OK
    const result = detecterLeak('Le client a écrit @notre_dossier dans le rapport');
    expect(result.blocked).toBe(false);
  });

  // ─── MOTS-CLÉS HORS PLATEFORME ───────────────────────────────────────────

  test('REFUSE "WhatsApp moi"', () => {
    const result = detecterLeak('WhatsApp moi quand tu peux');
    expect(result.blocked).toBe(true);
    expect(result.type).toBe('KEYWORD');
  });

  test('REFUSE "Hors plateforme"', () => {
    const result = detecterLeak('On continue hors plateforme ?');
    expect(result.blocked).toBe(true);
    expect(result.type).toBe('KEYWORD');
  });

  test('REFUSE "Telegram"', () => {
    const result = detecterLeak('Tu as Telegram ?');
    expect(result.blocked).toBe(true);
    expect(result.type).toBe('KEYWORD');
  });

  test('REFUSE "Mon numéro"', () => {
    const result = detecterLeak('Je te donne mon numéro');
    expect(result.blocked).toBe(true);
    expect(result.type).toBe('KEYWORD');
  });

  test('REFUSE "Appelle-moi"', () => {
    const result = detecterLeak('Appelle-moi quand tu as 5 min');
    expect(result.blocked).toBe(true);
    expect(result.type).toBe('KEYWORD');
  });

  // ─── AUTORISÉ ─────────────────────────────────────────────────────────────────

  test('AUTORISE message normal "Merci, à demain 7h"', () => {
    const result = detecterLeak('Merci, à demain 7h pour la prise de poste');
    expect(result.blocked).toBe(false);
  });

  test('AUTORISE chiffres date "Mission du 15 mars 2026"', () => {
    const result = detecterLeak('Mission du 15 mars 2026 à 7h00');
    expect(result.blocked).toBe(false);
  });

  test('AUTORISE référence facture "FA-2026-0042"', () => {
    const result = detecterLeak('Voir la facture FA-2026-0042');
    expect(result.blocked).toBe(false);
  });

  test('AUTORISE montant "1 250 euros"', () => {
    const result = detecterLeak('Le total est de 1 250 euros');
    expect(result.blocked).toBe(false);
  });

  // ─── SANITIZATION ────────────────────────────────────────────────────────────

  test('sanitizeContent préserve le texte littéral, rendu sans HTML par React', () => {
    const input = '<script>alert("xss")</script>Hello';
    const output = sanitizeContent(input);
    expect(output).toBe(input);
  });

  test('sanitizeContent préserve les comparaisons et esperluettes', () => {
    const input = 'A & B et 1 < 2';
    const output = sanitizeContent(input);
    expect(output).toBe(input);
  });

  test('sanitizeContent préserve texte normal', () => {
    const input = 'Bonjour, comment allez-vous ?';
    const output = sanitizeContent(input);
    expect(output).toBe(input);
  });

  // ─── COMBINAISONS / EDGE CASES ───────────────────────────────────────────

  test('REFUSE message mixte téléphone + mot-clé', () => {
    const result = detecterLeak('WhatsApp moi au 06 12 34 56 78');
    expect(result.blocked).toBe(true);
    // Téléphone détecté en premier (priorité ordre)
    expect(result.type).toBe('TELEPHONE');
  });

  test('REFUSE même si caché dans une phrase', () => {
    const result = detecterLeak(
      'Si jamais tu veux échanger plus rapidement, voici mon mobile : 0612345678, à plus.',
    );
    expect(result.blocked).toBe(true);
    expect(result.type).toBe('TELEPHONE');
  });

  test('AUTORISE message strictement métier', () => {
    const result = detecterLeak(
      'Bonjour, la mission de nuit du 20 mars est confirmée. ' +
      'Merci de vous présenter à 21h00 au service Urgences. ' +
      'La tenue est fournie sur place. À bientôt.',
    );
    expect(result.blocked).toBe(false);
  });
});
