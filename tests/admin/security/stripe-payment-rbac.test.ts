import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const read = (path: string) => readFileSync(join(process.cwd(), path), 'utf8');

const flows = [
  {
    name: 'réservation de commission mission',
    source: read('supabase/functions/create-mission-payment/index.ts'),
    target: 'mission.etablissement_id',
    disabled: true,
  },
  {
    name: 'paiement Connect de mission',
    source: read('supabase/functions/stripe-connect-pay-mission/index.ts'),
    target: 'mission.etablissement_id',
  },
  {
    name: 'création du Checkout facture',
    source: read('supabase/functions/create-invoice-payment/index.ts'),
    target: 'facture.etablissement_id',
  },
  {
    name: 'confirmation du paiement facture',
    source: read('supabase/functions/confirm-invoice-payment/index.ts'),
    target: 'facture.etablissement_id',
  },
];

const rbacMigration = read(
  'supabase/migrations/20260712230000_p0_securite_auth_rls.sql',
);
const customerHelper = read('supabase/functions/_shared/stripe-customer.ts');
const customerCreators = [
  read('supabase/functions/create-invoice-payment/index.ts'),
  read('supabase/functions/stripe-connect-pay-mission/index.ts'),
  read('supabase/functions/setup-sepa/index.ts'),
];

describe('Stripe — RBAC paiement établissement fail-closed', () => {
  for (const flow of flows) {
    it(`${flow.name} exige un utilisateur et la permission paiement sur la cible`, () => {
      const permissionCall = flow.source.indexOf('"fn_a_permission_etablissement"');
      const permissionGate = flow.source.indexOf('if (hasPaymentPermission !== true)');
      const stripeInit = flow.source.indexOf(
        'const stripeKey = Deno.env.get("STRIPE_SECRET_KEY")',
      );

      expect(flow.source).toContain('verifyUserOrServiceRole(req)');
      expect(flow.source).toContain('auth.isServiceRole || !auth.userId');
      expect(flow.source).toContain('global: { headers: { Authorization: authHeader } }');
      expect(flow.source).toContain('p_permission: "paiement"');
      expect(flow.source).toContain(`p_etablissement_id: ${flow.target}`);
      expect(flow.source).toContain('Vérification des droits de paiement impossible');
      expect(permissionCall).toBeGreaterThan(-1);
      expect(permissionGate).toBeGreaterThan(permissionCall);
      if (flow.disabled) {
        expect(flow.source).toContain('STRIPE_RESERVATION_DISABLED');
        expect(stripeInit).toBe(-1);
      } else {
        expect(stripeInit).toBeGreaterThan(permissionGate);
      }
    });
  }

  it('ne réintroduit aucun ciblage par app_metadata ou table de groupe parallèle', () => {
    for (const flow of flows) {
      expect(flow.source).not.toContain('app_metadata?.etablissement_id');
      expect(flow.source).not.toContain('admins_groupe_sante');
      expect(flow.source).not.toMatch(/userEtabId\s*=.*\|\|\s*user\.id/);
    }
  });

  it('bloque LECTURE_SEULE et POINTAGE_ONLY tout en conservant propriétaire, admin groupe et admin plateforme AAL2', () => {
    const permissionCase = rbacMigration.match(
      /WHEN 'paiement' THEN[^\n]+/,
    )?.[0] ?? '';

    expect(permissionCase).toBe(
      "WHEN 'paiement' THEN v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE')",
    );
    expect(permissionCase).not.toContain('LECTURE_SEULE');
    expect(permissionCase).not.toContain('POINTAGE_ONLY');
    expect(rbacMigration).toContain('IF public.est_admin() THEN RETURN true; END IF;');
    expect(rbacMigration).toContain("COALESCE(auth.jwt() ->> 'aal', '') = 'aal2'");
  });

  it('refuse explicitement le service role sur ces quatre flux interactifs', () => {
    for (const flow of flows) {
      expect(flow.source).toMatch(
        /if \(auth\.isServiceRole \|\| !auth\.userId[^)]*\) \{[\s\S]*?Session utilisateur requise/,
      );
    }
  });

  it('centralise les trois créations Customer actives sans lookup e-mail inter-tenant', () => {
    for (const source of customerCreators) {
      expect(source).toContain('ensureCanonicalEtablissementCustomer(');
      expect(source).not.toContain('customers.create(');
      expect(source).not.toContain('customers.list(');
      expect(source).not.toContain('auth.userEmail');
    }

    const customerSources = readdirSync('supabase/functions', { withFileTypes: true })
      .filter((entry) => entry.isDirectory())
      .map((entry) => `${entry.name}/index.ts`)
      .filter((relativePath) => {
        try {
          return read(`supabase/functions/${relativePath}`).includes('customers.create(');
        } catch {
          return false;
        }
      });
    expect(customerSources).toEqual([]);
    // Une création canonique + un fallback versionné si Stripe rejoue un
    // Customer supprimé ; les deux restent centralisés dans le même helper.
    expect(customerHelper.match(/customers\.create\(/g)).toHaveLength(2);
    expect(customerHelper).not.toContain('customers.list(');
    expect(customerHelper).toContain(
      '{ metadata: { etablissement_id: etablissement.id } }',
    );
  });

  it('fait converger les courses par idempotence Stripe, CAS SQL et relecture du gagnant', () => {
    expect(customerHelper).toContain('customer_etablissement_${etablissementId}');
    expect(customerHelper).toContain('email = (etablissement.email_contact || "")');
    expect(customerHelper).toContain('metadata: { etablissement_id: etablissement.id }');
    expect(customerHelper).toContain('.is("stripe_customer_id", null)');
    expect(customerHelper).toContain(
      'claimQuery.eq("stripe_customer_id", etablissement.stripe_customer_id)',
    );
    expect(customerHelper).toContain('.select("stripe_customer_id")');
    expect(customerHelper).toContain('if (!canonicalId)');
    expect(customerHelper).toContain('validateAndSyncCustomer(');
    expect(customerHelper).toContain('CUSTOMER_TENANT_MISMATCH');
    expect(customerHelper).toContain('audit manuel requis');
  });

  it('interdit qu’un même Customer Stripe soit lié à deux établissements', () => {
    const migration = read(
      'supabase/migrations/20260714012500_securiser_liaison_customer_stripe.sql',
    );
    expect(migration).toContain('CREATE UNIQUE INDEX');
    expect(migration).toContain('ON public.etablissements (stripe_customer_id)');
    expect(migration).toContain('WHERE stripe_customer_id IS NOT NULL');
  });

  it('mappe les erreurs Customer en statuts publics sûrs sur tous les flux', () => {
    const setupSepa = customerCreators[2];
    expect(customerHelper).toContain('stripe.customers.update(customer.id');
    expect(customerHelper).toContain('mapStripeCustomerConfigurationError');
    expect(customerHelper).toContain('status: 422');
    expect(customerHelper).toContain('status: 409');
    expect(customerHelper).toContain('status: 503');
    expect(customerHelper).not.toContain('userMessage: error.message');

    for (const source of customerCreators.slice(0, 2)) {
      expect(source).toContain('mapStripeCustomerConfigurationError(error)');
      expect(source).toContain('.userMessage');
      expect(source).toContain('.status');
      expect(source).not.toContain('userMessage: error.message');
    }

    expect(setupSepa).toContain('error.code === "CUSTOMER_PROFILE_INCOMPLETE"');
    expect(setupSepa).toContain('error.code === "CUSTOMER_TENANT_MISMATCH"');
    expect(setupSepa).toContain('throw new PublicError(422');
    expect(setupSepa).toContain('throw new PublicError(409');
    expect(setupSepa).toContain('throw new PublicError(503');
  });
});
