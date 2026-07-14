/**
 * Test — fn_admin_stripe_connect_stats
 *
 * Vérifie que la RPC retourne les 6 métriques financières
 * avec les bonnes colonnes (montant_soignant, montant_commission, montant_total).
 * Régression : avant le fix, SUM(montant) crashait car la colonne n'existe pas.
 */

import { describe, it, expect } from 'vitest';
import { createClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.VITE_SUPABASE_URL || 'https://flripxtsyegjshnhzjkz.supabase.co';
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

const skip = !serviceRoleKey;

describe.skipIf(skip)('fn_admin_stripe_connect_stats', () => {
  const supabase = createClient(supabaseUrl, serviceRoleKey || 'test-only-placeholder');

  it('la RPC ne crash plus (ancien bug: column montant does not exist)', async () => {
    const { data, error } = await supabase.rpc('fn_admin_stripe_connect_stats' as any);
    expect(error).toBeNull();
    expect(data).not.toBeNull();
  });

  it('retourne les 6 métriques financières enrichies', async () => {
    const { data } = await supabase.rpc('fn_admin_stripe_connect_stats' as any);
    expect(data).toHaveProperty('total_verse_soignants');
    expect(data).toHaveProperty('en_attente_soignants');
    expect(data).toHaveProperty('total_commission_jolene');
    expect(data).toHaveProperty('en_attente_commission');
    expect(data).toHaveProperty('volume_total');
    expect(data).toHaveProperty('volume_en_attente');
  });

  it('retourne les compteurs Connect', async () => {
    const { data } = await supabase.rpc('fn_admin_stripe_connect_stats' as any);
    expect(data).toHaveProperty('total_comptes');
    expect(data).toHaveProperty('complets');
    expect(data).toHaveProperty('en_cours');
  });

  it('ne retourne PAS les anciens champs ambigus', async () => {
    const { data } = await supabase.rpc('fn_admin_stripe_connect_stats' as any);
    expect(data).not.toHaveProperty('total_transfere');
    expect(data).not.toHaveProperty('total_en_attente');
  });

  it('les valeurs sont des nombres (pas null, pas string)', async () => {
    const { data } = await supabase.rpc('fn_admin_stripe_connect_stats' as any);
    expect(typeof data.total_verse_soignants).toBe('number');
    expect(typeof data.total_commission_jolene).toBe('number');
    expect(typeof data.volume_total).toBe('number');
    expect(typeof data.total_comptes).toBe('number');
  });

  it('volume_total = verse_soignants + commission_jolene (cohérence mathématique)', async () => {
    const { data } = await supabase.rpc('fn_admin_stripe_connect_stats' as any);
    const verse = Number(data.total_verse_soignants) || 0;
    const commission = Number(data.total_commission_jolene) || 0;
    const volume = Number(data.volume_total) || 0;

    // volume_total = montant_soignant + montant_commission (par construction)
    // Tolérance flottante de 0.01€
    expect(Math.abs(volume - (verse + commission))).toBeLessThanOrEqual(0.01);
  });

  it('en_attente values sont >= 0', async () => {
    const { data } = await supabase.rpc('fn_admin_stripe_connect_stats' as any);
    expect(Number(data.en_attente_soignants)).toBeGreaterThanOrEqual(0);
    expect(Number(data.en_attente_commission)).toBeGreaterThanOrEqual(0);
    expect(Number(data.volume_en_attente)).toBeGreaterThanOrEqual(0);
  });
});
