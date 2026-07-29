import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const read = (path: string) => readFileSync(join(process.cwd(), path), 'utf8');

const migration = read('supabase/migrations/20260714004020_verrouiller_acces_admin_lancement.sql');
const sansMfa = read('supabase/migrations/20260729121419_requalifier_donnees_prelaunch_et_supprimer_mfa_admin.sql');
const familleGabrielle = read('supabase/migrations/20260722163518_completer_type_compte_admin_gabrielle.sql');
const app = read('src/App.tsx');
const routeProtegee = read('src/components/RouteProtegee.tsx');
const equipe = read('src/pages/admin/AdminEquipe.tsx');
const accesHook = read('src/hooks/useAccesAdmin.ts');
const edgeAuth = read('supabase/functions/_shared/admin-auth.ts');

const groupesCanoniques = [
  'Dashboard',
  'Utilisateurs',
  'Missions',
  'Litiges & contrats',
  'Finances',
  'Messagerie',
  'Conformité & Technique',
  'Fondateur',
];

describe('garde admin fail-closed de lancement', () => {
  it('protège toutes les routes /admin, redirections historiques incluses', () => {
    const routesAdmin = app
      .split('\n')
      .filter((line) => line.includes('<Route path="/admin'));

    expect(routesAdmin.length).toBeGreaterThanOrEqual(50);
    for (const route of routesAdmin) {
      expect(route).toContain('<RouteAdminProtegee accesRequis={ADMIN_ACCESS.');
      expect(route).not.toContain("rolesAutorises={['ADMIN_PLATEFORME']}");
    }
    expect(app).toContain('path="/acces-admin-indisponible"');
  });

  it('exige côté serveur les huit groupes et un compte sain, sans MFA', () => {
    for (const groupe of groupesCanoniques) {
      expect(sansMfa).toContain(`'${groupe}'`);
    }
    expect(sansMfa).toContain('CREATE OR REPLACE FUNCTION public.est_admin_valide()');
    expect(sansMfa).toContain("u.raw_app_meta_data ->> 'role' = 'ADMIN_PLATEFORME'");
    expect(sansMfa).toContain('u.email_confirmed_at IS NOT NULL');
    expect(sansMfa).toContain('ea.actif IS TRUE');
    expect(sansMfa).toContain('DELETE FROM auth.mfa_factors');
    expect(sansMfa).not.toContain("auth.jwt() ->> 'aal'");
    expect(familleGabrielle).toContain('INSERT INTO public.types_comptes_auth');
    expect(familleGabrielle).toContain("'ADMIN'");
    expect(familleGabrielle).toContain("'gabrielle.pcd@outlook.com'");
    expect(routeProtegee).not.toContain('AdminMfaGate');
    expect(routeProtegee).not.toContain('ADMIN_EMAILS_SANS_MFA');
    expect(sansMfa).toContain(']::text[] <@ COALESCE(ea.acces_groupes, ARRAY[]::text[])');
    expect(migration).toContain('JOIN public.equipe_admin ea ON ea.user_id = u.id');
    expect(migration).not.toContain('admin historique hors equipe');
    expect(migration).not.toMatch(/NOT EXISTS \([\s\S]*?equipe_admin ea_any/);
    expect(migration).toContain("RAISE EXCEPTION 'Acces admin refuse au lancement'");
  });

  it('aligne les Edge Functions sur le registre full-only et le rôle canonique', () => {
    for (const groupe of groupesCanoniques) {
      expect(edgeAuth).toContain(`'${groupe}'`);
    }
    expect(edgeAuth).toContain("return role === 'ADMIN_PLATEFORME'");
    expect(edgeAuth).not.toContain("new Set(['ADMIN', 'ADMIN_PLATEFORME'])");
    expect(edgeAuth).toContain(".select('actif, acces_groupes')");
    expect(edgeAuth).toContain('if (!hasFullLaunchAdminAccess(equipe))');
    const userGuard = edgeAuth.slice(
      edgeAuth.indexOf('export async function verifyUserOrServiceRole'),
      edgeAuth.indexOf('/** Verifie que la requete provient'),
    );
    const adminGuard = edgeAuth.slice(
      edgeAuth.indexOf('export async function verifyAdminOrServiceRole'),
      edgeAuth.indexOf('/** Récupère le client Supabase'),
    );
    expect(userGuard).not.toContain('if (!isConfirmedAuthUser(');
    expect(adminGuard).toContain(
      'if (!isConfirmedAuthUser({ email_confirmed_at: auth.emailConfirmedAt }))',
    );
    expect(edgeAuth).not.toContain('getClaims(');
    expect(edgeAuth).not.toContain("auth.aal !== 'aal2'");
    expect(edgeAuth).toContain("status: 403, error: 'Acces administrateur complet requis'");
  });

  it('neutralise les RPC SECURITY DEFINER qui lisaient directement le rôle', () => {
    for (const rpc of [
      'fn_admin_acquisition_canaux',
      'fn_admin_cockpit_fondateur',
      'fn_admin_creer_compte_employe',
    ]) {
      expect(migration).toContain(`${rpc}_interne_lancement`);
    }
    expect(migration).toContain('CREATE SCHEMA IF NOT EXISTS private AUTHORIZATION postgres');
    expect(migration.match(/FROM PUBLIC, anon, authenticated, service_role;/g)).toHaveLength(4);
    expect(migration.match(/IF NOT public\.est_admin\(\) THEN/g)?.length).toBeGreaterThanOrEqual(3);
    expect(migration).toContain(
      'SET search_path TO pg_catalog, public, auth, extensions;',
    );
  });

  it('n’écrit aucune donnée existante pendant la migration', () => {
    expect(migration).not.toMatch(/\bUPDATE\s+public\.equipe_admin\b/i);
    expect(migration).not.toMatch(/\bDELETE\s+FROM\b/i);
    expect(migration).not.toMatch(/\bTRUNCATE\b/i);
    expect(migration).not.toMatch(/\bINSERT\s+INTO\s+(?:public\.)?equipe_admin\b/i);
  });

  it('force aussi les huit groupes dans l’interface de gestion', () => {
    expect(equipe).toContain('acces_groupes: [...ADMIN_ACCESS_GROUPS]');
    expect(equipe).toContain('p_acces_groupes: [...ADMIN_ACCESS_GROUPS]');
    expect(equipe).toContain("L'accès partiel est temporairement désactivé");
    expect(equipe).not.toContain('toggleAcces');
    expect(equipe).not.toContain('type="checkbox"');
  });

  it('garde le frontend fermé en attente ou en erreur serveur', () => {
    expect(accesHook).toContain('const [accesTotal, setAccesTotal] = useState(false)');
    expect(accesHook).toContain('if (error || !data)');
    expect(accesHook).toContain('setAccesTotal(false)');
    expect(accesHook).toContain('setGroupes([])');
  });
});
