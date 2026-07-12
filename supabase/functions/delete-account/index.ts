/**
 * Suppression de compte self-service.
 *
 * La transaction metier d'anonymisation reste dans les RPC PostgreSQL. Cette
 * Edge Function complete le flux en revoquant les refresh tokens puis en
 * supprimant logiquement l'utilisateur Supabase Auth. Le soft-delete Auth est
 * volontaire : plusieurs preuves legales conservent une FK vers auth.users.
 * Le compte devient inutilisable et son identite Auth est anonymisee sans
 * casser ces obligations de conservation.
 */

import { createClient } from 'npm:@supabase/supabase-js@2.99.2';
import { jsonResponse, preflightResponse } from '../_shared/cors.ts';
import { verifyUserOrServiceRole } from '../_shared/admin-auth.ts';
import { applyRateLimit, getClientIp } from '../_shared/rate-limit.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return preflightResponse(req);
  if (req.method !== 'POST') return jsonResponse(req, { error: 'Methode non autorisee' }, 405);

  try {
    const auth = await verifyUserOrServiceRole(req);
    if (!auth.ok) return jsonResponse(req, { error: auth.error }, auth.status);
    if (auth.isServiceRole || !auth.userId) {
      return jsonResponse(req, { error: 'Suppression self-service uniquement' }, 403);
    }
    if (auth.role === 'ADMIN' || auth.role === 'ADMIN_PLATEFORME') {
      return jsonResponse(req, { error: 'Un compte administrateur doit etre retire par un autre administrateur' }, 403);
    }
    if (applyRateLimit('delete-account', `${auth.userId}:${getClientIp(req)}`, { max: 3, windowMs: 60_000 })) {
      return jsonResponse(req, { error: 'Demande deja en cours' }, 429);
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') || '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      return jsonResponse(req, { error: 'Configuration serveur incomplete' }, 500);
    }

    const bearer = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '').trim();
    const userClient = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false },
      global: { headers: { Authorization: `Bearer ${bearer}` } },
    });
    const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });

    const [
      { data: soignant, error: soignantError },
      { data: etablissement, error: etablissementError },
      { data: memberships, error: membershipError },
      { data: groupAdmins, error: groupAdminsError },
    ] = await Promise.all([
      admin.from('soignants').select('id, supprime_le').eq('id', auth.userId).maybeSingle(),
      admin.from('etablissements').select('id, supprime_le').eq('id', auth.userId).maybeSingle(),
      admin.from('membres_etablissement')
        .select('id, etablissement_id, role, actif')
        .eq('user_id', auth.userId)
        .eq('actif', true),
      admin.from('admins_groupe_sante')
        .select('id, groupe_id, role')
        .eq('utilisateur_id', auth.userId),
    ]);
    if (soignantError || etablissementError || membershipError || groupAdminsError) {
      console.error('[delete-account] lecture profil impossible', {
        soignant: soignantError?.code,
        etablissement: etablissementError?.code,
        memberships: membershipError?.code,
        groupes: groupAdminsError?.code,
      });
      return jsonResponse(req, { error: 'Verification du compte impossible' }, 503);
    }

    // Ne jamais anonymiser une seule moitie d'un compte historiquement croise.
    // Le garde d'inscription empeche les nouveaux cas; un cas legacy est gele
    // pour revue explicite sans supprimer de donnees au hasard.
    if (soignant && etablissement) {
      await admin.from('alertes_systeme').insert({
        type_alerte: 'AUTH_PROFILE_CONFLICT',
        severite: 'CRITICAL',
        source: 'delete-account',
        message: 'Suppression bloquee: profils soignant et etablissement simultanes',
        details: { user_id: auth.userId },
      }).then(() => {}).catch(() => {});
      return jsonResponse(req, {
        error: 'Votre compte nécessite une vérification manuelle avant suppression.',
        error_code: 'ACCOUNT_PROFILE_CONFLICT',
      }, 409);
    }

    // Cette verification vaut aussi pour un soignant/etablissement qui serait
    // membre d'autres structures. Le proprietaire de son propre etablissement
    // est gere par la RPC de suppression etablissement.
    for (const membership of memberships || []) {
      if (membership.role !== 'PROPRIETAIRE' || membership.etablissement_id === etablissement?.id) continue;
      const { count, error } = await admin
        .from('membres_etablissement')
        .select('id', { head: true, count: 'exact' })
        .eq('etablissement_id', membership.etablissement_id)
        .eq('role', 'PROPRIETAIRE')
        .eq('actif', true)
        .neq('user_id', auth.userId);
      if (error) {
        console.error('[delete-account] comptage proprietaires impossible', error.code);
        return jsonResponse(req, { error: 'Verification des responsabilites impossible' }, 503);
      }
      if (!count) {
        return jsonResponse(req, {
          error: "Transferez d'abord le role de proprietaire a un autre membre.",
          error_code: 'DERNIER_PROPRIETAIRE',
        }, 409);
      }
    }
    for (const groupAdmin of groupAdmins || []) {
      if (groupAdmin.role !== 'PROPRIETAIRE') continue;
      const { count, error } = await admin
        .from('admins_groupe_sante')
        .select('id', { head: true, count: 'exact' })
        .eq('groupe_id', groupAdmin.groupe_id)
        .eq('role', 'PROPRIETAIRE')
        .neq('utilisateur_id', auth.userId);
      if (error) return jsonResponse(req, { error: 'Verification des responsabilites groupe impossible' }, 503);
      if (!count) {
        return jsonResponse(req, {
          error: "Transferez d'abord la propriete du groupe de sante.",
          error_code: 'DERNIER_PROPRIETAIRE_GROUPE',
        }, 409);
      }
    }

    let anonymisation: Record<string, unknown> = { success: true, deja_anonymise: false };

    if (soignant) {
      if (!soignant.supprime_le) {
        const { data, error } = await userClient.rpc('fn_supprimer_compte_rate_limited');
        if (error) return jsonResponse(req, { error: error.message }, 409);
        anonymisation = (data || {}) as Record<string, unknown>;
        if (anonymisation.error || anonymisation.success === false) {
          return jsonResponse(req, anonymisation, 409);
        }
      } else {
        anonymisation.deja_anonymise = true;
      }
    } else if (etablissement) {
      if (!etablissement.supprime_le) {
        const { data, error } = await userClient.rpc('fn_supprimer_compte_etablissement_rate_limited');
        if (error) return jsonResponse(req, { error: error.message }, 409);
        anonymisation = (data || {}) as Record<string, unknown>;
        if (anonymisation.error || anonymisation.success === false) {
          return jsonResponse(req, anonymisation, 409);
        }
      } else {
        anonymisation.deja_anonymise = true;
      }
    } else if ((memberships || []).length > 0) {
      // Un collaborateur supprime son propre compte, jamais l'etablissement.
      // Le dernier proprietaire doit d'abord transferer ses responsabilites.
      // La desactivation commune est effectuee juste apres cette branche.
    } else {
      // Inscription interrompue : il n'existe pas encore de profil public, mais
      // l'utilisateur Auth doit tout de meme pouvoir exercer son droit.
      anonymisation = { success: true, profil_incomplet: true };
    }

    if ((memberships || []).length > 0) {
      const { error } = await admin
        .from('membres_etablissement')
        .update({ actif: false, maj_le: new Date().toISOString() })
        .eq('user_id', auth.userId)
        .eq('actif', true);
      if (error) return jsonResponse(req, { error: 'Retrait des equipes impossible' }, 500);
      await admin.from('journaux_audit').insert({
        acteur_id: auth.userId,
        type_acteur: 'ADMIN_ETABLISSEMENT',
        action: 'RGPD_SUPPRESSION_COMPTE_MEMBRE_ETABLISSEMENT',
        type_ressource: 'auth_user',
        id_ressource: auth.userId,
        details: { memberships_desactives: memberships?.length || 0 },
      }).then(() => {}).catch(() => {});
    }
    if ((groupAdmins || []).length > 0) {
      const { error } = await admin
        .from('admins_groupe_sante')
        .delete()
        .eq('utilisateur_id', auth.userId);
      if (error) return jsonResponse(req, { error: 'Retrait des groupes impossible' }, 500);
      await admin.from('journaux_audit').insert({
        acteur_id: auth.userId,
        type_acteur: 'ADMIN_ETABLISSEMENT',
        action: 'RGPD_SUPPRESSION_COMPTE_ADMIN_GROUPE',
        type_ressource: 'auth_user',
        id_ressource: auth.userId,
        details: { groupes_quittes: groupAdmins?.length || 0 },
      }).then(() => {}).catch(() => {});
    }

    // Nettoyage des donnees purement techniques qui peuvent exister avant la
    // creation du profil ou hors des RPC historiques.
    await Promise.allSettled([
      admin.from('tokens_push').delete().eq('utilisateur_id', auth.userId),
      admin.from('tokens_calendrier').delete().eq('soignant_id', auth.userId),
      admin.from('calendar_connections').delete().eq('utilisateur_id', auth.userId),
      admin.from('preferences_notifications').delete().eq('utilisateur_id', auth.userId),
      admin.from('preferences_notifications_par_evenement').delete().eq('utilisateur_id', auth.userId),
      admin.from('filtres_sauvegardes').delete().eq('utilisateur_id', auth.userId),
    ]);

    // Revoque tous les refresh tokens avant le soft-delete. Les access tokens
    // deja emis sont neutralises en base par la policy restrictive
    // fn_compte_auth_actif() ajoutee dans la migration P0.
    const { error: signOutError } = await admin.auth.admin.signOut(bearer, 'global');
    if (signOutError) {
      console.warn('[delete-account] revocation refresh tokens', signOutError.message);
    }

    const { error: deleteError } = await admin.auth.admin.deleteUser(auth.userId, true);
    if (deleteError) {
      console.error('[delete-account] soft-delete Auth impossible', deleteError.message);
      // Etat de repli fail-safe : bloque toute reconnexion et retire le role. La
      // reponse reste en erreur afin qu'une relance operateur termine la purge.
      const { data: current } = await admin.auth.admin.getUserById(auth.userId);
      await admin.auth.admin.updateUserById(auth.userId, {
        ban_duration: '876000h',
        app_metadata: {
          ...(current?.user?.app_metadata || {}),
          role: 'DELETED',
          deleted_at: new Date().toISOString(),
        },
      });
      await admin.from('alertes_systeme').insert({
        type_alerte: 'AUTH_DELETE_FAILED',
        severite: 'CRITICAL',
        source: 'delete-account',
        message: 'Compte public anonymise mais soft-delete Auth a terminer',
        details: { user_id: auth.userId, error: deleteError.message.slice(0, 300) },
      }).then(() => {}).catch(() => {});
      return jsonResponse(req, {
        error: 'Compte bloque et anonymise; suppression Auth en cours de finalisation',
        error_code: 'AUTH_DELETE_PENDING',
      }, 503);
    }

    return jsonResponse(req, {
      success: true,
      auth_deleted: true,
      anonymisation,
    });
  } catch (error) {
    console.error('[delete-account] erreur', error);
    return jsonResponse(req, { error: 'Erreur interne' }, 500);
  }
});
