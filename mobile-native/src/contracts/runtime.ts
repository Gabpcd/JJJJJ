import type { SupabaseClient } from '@supabase/supabase-js';
import type { NativeAccountContext, NativeEstablishmentContext } from '../account/types';
import { SupabaseContractGateway } from '../workflows/contracts/supabaseGateway';
import { createContractOriginalTransport } from '../workflows/contracts/originalTransport';
import type { ContractContext, ContractGateway } from '../workflows/contracts/types';
import { DemoContractGateway, type DemoContractSession } from './demoGateway';

export function nativeContractContext(context: NativeAccountContext | null): ContractContext | null {
  return context?.kind === 'soignant' ? { kind: 'soignant', userId: context.userId }
    : context?.kind === 'etablissement' ? { kind: 'etablissement', userId: context.userId, etablissementId: context.etablissementId } : null;
}
export function contractScenario(mode: 'demo' | 'staging', raw: string | undefined): boolean {
  const flag = raw?.trim() ?? '';
  if (!['', '0', '1'].includes(flag) || flag === '1' && mode !== 'demo') throw new Error('Le scénario de contrats fictifs est réservé au mode Démonstration et doit être activé avec 1.');
  return flag === '1';
}
export function readOnlyContractDemo(context: Omit<NativeEstablishmentContext, 'membershipRole'>): NativeEstablishmentContext {
  return { ...context, membershipRole: 'LECTURE_SEULE', permissions: { gerer_equipe: false, supprimer_compte: false,
    profil_etab: false, paiement: false, lecture_paiement: false, missions: false, candidatures: false,
    contrats: false, pointage: false, rh: false, lecture: true } };
}
type Digest = (text: string) => Promise<string>;
export function createContractRuntime(input: { mode: 'demo'; currentSession: () => DemoContractSession | null; digestUtf8: Digest; scenario: boolean }
  | { mode: 'staging'; client: SupabaseClient; config: { url: string; publishableKey: string }; digestUtf8: Digest; fetch: typeof fetch }): ContractGateway {
  if (input.mode === 'demo') return new DemoContractGateway({ currentSession: input.currentSession,
    digestUtf8: input.digestUtf8, uncertainSignature: input.scenario });
  return new SupabaseContractGateway(input.client, createContractOriginalTransport(input.config, input.fetch), input.digestUtf8);
}
