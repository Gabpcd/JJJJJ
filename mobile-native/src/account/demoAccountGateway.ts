import { DEMO_CONTEXT } from '../data/demoGateway';
import { DEMO_ESTABLISHMENT_CONTEXT } from '../establishment/demo';
import type { NativeSessionController } from '../session/controller';
import type { NativeAccountGateway, NativeOnboardingContext, NativeQuickRegistration, NativeRegistrationForm, NativeRegistrationIntent, RegistrationResult } from './types';
import { NativeAccountError } from './errors';
import { registrationBody } from './registration';

export const DEMO_ONBOARDING_CONTEXT: NativeOnboardingContext = {
  kind: 'onboarding', userId: 'demo-inscription', email: 'inscription@demo.invalid', emailConfirmed: true,
  parcours: { user_id: 'demo-inscription', type_compte: 'SOIGNANT', modifie_le: '2026-10-26T00:00:00Z',
    donnees: { profession: 'MEDECIN', estEtudiant: true, scolariteFormation: 'MEDECINE_DES', prenom: 'Camille', nom: 'Démo', telephone: '0600000000', dateNaissance: '1997-05-12', typesContrat: ['SALARIE'], rpps: '00000000001' } },
};

/** Pure in-memory simulation. This class never receives a Supabase client. */
export class DemoAccountGateway implements NativeAccountGateway {
  readonly mode = 'demo' as const;
  constructor(private readonly controller: NativeSessionController) {}
  async createAccount(input: NativeQuickRegistration): Promise<RegistrationResult> {
    await this.startRegistration(DEMO_ONBOARDING_CONTEXT.userId, input);
    return { status: 'created' };
  }
  async startRegistration(userId: string, intent: NativeRegistrationIntent) {
    if (!userId.startsWith('demo-')) throw new NativeAccountError('Ce compte n’appartient pas à la démonstration.');
    this.controller.enterDemo({ kind: 'onboarding', userId, email: 'inscription@demo.invalid', emailConfirmed: true,
      parcours: { user_id: userId, type_compte: intent.type, modifie_le: new Date().toISOString(), donnees: { profession: intent.profession, nom: intent.nom } } });
  }
  async saveDraft(userId: string, values: NativeRegistrationForm) {
    const context = this.controller.getSnapshot().context;
    if (context?.kind !== 'onboarding' || context.userId !== userId || !userId.startsWith('demo-') || !context.parcours) throw new NativeAccountError('Rouvrez le parcours de démonstration.');
    this.controller.updateDemoContext({ ...context, parcours: { ...context.parcours, donnees: { ...context.parcours.donnees, ...values }, modifie_le: new Date().toISOString() } });
  }
  async completeRegistration(context: NativeOnboardingContext, values: NativeRegistrationForm) {
    if (!context.parcours) throw new NativeAccountError('Choisissez votre espace.');
    registrationBody(context.parcours.type_compte, values, context.email);
    await this.saveDraft(context.userId, values);
    if (context.parcours.type_compte === 'SOIGNANT') {
      // Keep the fixture identity accepted by DemoGateway, and preserve the declared profession.
      this.controller.enterDemo({ ...DEMO_CONTEXT, kind: 'soignant', profile: { ...DEMO_CONTEXT.profile,
        profession: values.profession, types_contrat_acceptes: JSON.stringify(values.typesContrat),
        type_contrat: values.typesContrat[0] ?? null, tous_documents_valides: false,
      } });
    } else {
      this.controller.enterDemo({ ...DEMO_ESTABLISHMENT_CONTEXT, kind: 'etablissement', membershipRole: DEMO_ESTABLISHMENT_CONTEXT.membershipRole ?? 'PROPRIETAIRE' });
    }
  }
  async getExerciseTypes() { return ['SALARIE', 'LIBERAL']; }
  async getStudentProfessions() { return []; }
  async confirmEmail() { throw new NativeAccountError('La démonstration n’envoie pas d’email de confirmation.'); }
}
