import { useCallback, useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { ArrowLeft, Users, UserPlus, Mail, Crown, Briefcase, ClipboardCheck, Eye, Trash2, Loader2, AlertCircle } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { usePageTitle } from '@/hooks/usePageTitle';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { EmptyState } from '@/components/ui/EmptyState';
import { estDernierProprietaireActif } from '@/lib/equipeEtablissement';
import {
  DialogResponsive,
  DialogResponsiveContent,
  DialogResponsiveHeader,
  DialogResponsiveTitle,
  DialogResponsiveBody,
  DialogResponsiveFooter,
} from '@/components/ui/DialogResponsive';

type Role = 'PROPRIETAIRE' | 'ADMIN_GROUPE' | 'RH' | 'POINTAGE_ONLY' | 'LECTURE_SEULE';
type StatutInvitation = 'EN_ATTENTE' | 'ACCEPTEE' | 'EXPIREE' | 'ANNULEE';

interface Membre {
  id: string;
  user_id: string;
  email: string;
  role: Role;
  accepte_le: string;
  actif: boolean;
}

interface Invitation {
  id: string;
  email_invite: string;
  role_propose: Role;
  statut: StatutInvitation;
  invite_le: string;
  expire_le: string;
}

const ROLE_INFO: Record<Role, { label: string; description: string; icon: typeof Crown; color: string }> = {
  PROPRIETAIRE: { label: 'Propriétaire', description: 'Tous les droits (équipe, paiements, suppression compte)', icon: Crown, color: 'text-primary' },
  ADMIN_GROUPE: { label: 'Admin groupe', description: 'Tout sauf gestion équipe et suppression compte', icon: Briefcase, color: 'text-info' },
  RH: { label: 'Ressources humaines', description: 'Missions, candidatures, contrats, pointage, RH', icon: Briefcase, color: 'text-success' },
  POINTAGE_ONLY: { label: 'Pointage uniquement', description: 'Validation présences, codes secours, QR', icon: ClipboardCheck, color: 'text-warning' },
  LECTURE_SEULE: { label: 'Lecture seule', description: 'Consultation uniquement, aucune action', icon: Eye, color: 'text-muted-foreground' },
};

const ROLES_INVITABLES: Role[] = ['ADMIN_GROUPE', 'RH', 'POINTAGE_ONLY', 'LECTURE_SEULE'];
const ROLES_MODIFIABLES: Role[] = ['PROPRIETAIRE', 'ADMIN_GROUPE', 'RH', 'POINTAGE_ONLY', 'LECTURE_SEULE'];

/**
 * Page gestion équipe étab multi-utilisateurs (Sprint 5.7 PR 2).
 *
 * Affiche :
 *  - Membres actifs avec rôle + actions PROPRIETAIRE-only
 *  - Invitations en attente avec action "Annuler"
 *  - Bouton "Inviter un membre" PROPRIETAIRE-only
 */
export default function EquipeEtablissement() {
  usePageTitle('Équipe');
  const navigate = useNavigate();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [roleCourant, setRoleCourant] = useState<Role | null>(null);
  const [membres, setMembres] = useState<Membre[]>([]);
  const [invitations, setInvitations] = useState<Invitation[]>([]);
  const [modalInviter, setModalInviter] = useState(false);
  const [modalModifierRole, setModalModifierRole] = useState<Membre | null>(null);
  const [modalRevoquer, setModalRevoquer] = useState<Membre | null>(null);

  const estProprietaire = roleCourant === 'PROPRIETAIRE';

  const recharger = useCallback(async () => {
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_lister_membres_etab' as any);
    if (error) {
      afficherNotification({ type: 'erreur', message: error.message });
      setLoading(false);
      return;
    }
    const result = data as any;
    if (!result?.success) {
      afficherNotification({ type: 'erreur', message: result?.error || 'Erreur chargement équipe.' });
      setLoading(false);
      return;
    }
    setRoleCourant(result.role_courant as Role);
    setMembres(result.membres as Membre[]);
    setInvitations(result.invitations as Invitation[]);
    setLoading(false);
  }, [afficherNotification]);

  useEffect(() => { void recharger(); }, [recharger]);

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><ChargementPage /></LayoutApp>;

  if (!roleCourant) {
    return (
      <LayoutApp role="ADMIN_ETABLISSEMENT">
        <div className="rounded-xl bg-destructive/10 border border-destructive/30 p-4 text-sm text-destructive">
          <p className="font-semibold mb-1">Accès refusé</p>
          <p>Vous n'êtes pas membre de cette équipe.</p>
        </div>
      </LayoutApp>
    );
  }

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <button onClick={() => navigate(-1)} className="flex items-center gap-1 text-sm text-primary hover:underline mb-2">
        <ArrowLeft className="h-4 w-4" /> Retour
      </button>

      <div className="mb-6 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold text-foreground inline-flex items-center gap-2">
            <Users className="h-6 w-6 text-primary" /> Mon équipe
          </h1>
          <p className="text-sm text-muted-foreground mt-1">
            Gérez les membres de votre équipe et leurs accès. Votre rôle actuel : <strong>{ROLE_INFO[roleCourant].label}</strong>.
          </p>
        </div>
        {estProprietaire && (
          <button onClick={() => setModalInviter(true)} className="btn-primary inline-flex items-center gap-2">
            <UserPlus className="h-4 w-4" /> Inviter un membre
          </button>
        )}
      </div>

      {/* Membres actifs */}
      <section className="mb-6">
        <h2 className="text-lg font-bold text-foreground mb-3">Membres actifs ({membres.length})</h2>
        {membres.length === 0 ? (
          <EmptyState
            icone={<Users />}
            mascotte="thinking"
            titre="Invitez vos collaborateurs"
            description="Aucun membre actif. Invitez votre équipe RH ou de pointage pour partager la gestion de cet établissement."
            cta={estProprietaire ? {
              label: 'Inviter un membre',
              onClick: () => setModalInviter(true),
            } : undefined}
            compact
          />
        ) : (
          <ul className="space-y-2">
            {membres.map((m) => {
              const info = ROLE_INFO[m.role];
              const Icon = info.icon;
              const estProprietaireUnique = estDernierProprietaireActif(m, membres);
              return (
                <li key={m.id} className="card-base flex flex-col sm:flex-row sm:items-center gap-3 sm:justify-between">
                  <div className="flex items-center gap-3 min-w-0 flex-1">
                    <div className={`flex-shrink-0 ${info.color}`}>
                      <Icon className="h-5 w-5" />
                    </div>
                    <div className="min-w-0 flex-1">
                      <p className="text-sm font-medium text-foreground truncate" title={m.email}>{m.email}</p>
                      <p className="text-xs text-muted-foreground">
                        {info.label} · Membre depuis le {format(new Date(m.accepte_le), 'dd MMM yyyy', { locale: fr })}
                      </p>
                    </div>
                  </div>
                  {estProprietaire && estProprietaireUnique && (
                    <span className="shrink-0 rounded-full bg-primary/10 px-3 py-1.5 text-xs font-medium text-primary" role="status">
                      Propriétaire unique
                    </span>
                  )}
                  {estProprietaire && !estProprietaireUnique && (
                    <div className="flex gap-2 shrink-0">
                      <button
                        onClick={() => setModalModifierRole(m)}
                        className="btn-secondary text-xs py-1.5 px-3"
                      >
                        Modifier rôle
                      </button>
                      <button
                        onClick={() => setModalRevoquer(m)}
                        className="border-2 border-destructive text-destructive rounded-lg px-3 py-1.5 text-xs font-medium hover:bg-destructive/5"
                      >
                        <Trash2 className="h-3.5 w-3.5 inline mr-1" />
                        Révoquer
                      </button>
                    </div>
                  )}
                </li>
              );
            })}
          </ul>
        )}
      </section>

      {/* Invitations en attente */}
      {(estProprietaire || invitations.length > 0) && (
        <section className="mb-6">
          <h2 className="text-lg font-bold text-foreground mb-3">Invitations en attente ({invitations.length})</h2>
          {invitations.length === 0 ? (
            <EmptyState
              icone={<Mail />}
              mascotte="happy"
              titre="Aucune invitation en attente"
              description="Toutes les invitations envoyées ont été acceptées ou ont expiré."
              variant="success"
              compact
            />
          ) : (
            <ul className="space-y-2">
              {invitations.map((inv) => (
                <li key={inv.id} className="card-base flex flex-col sm:flex-row sm:items-center gap-3 sm:justify-between border-warning/30 bg-warning/5">
                  <div className="flex items-center gap-3 min-w-0 flex-1">
                    <Mail className="h-5 w-5 text-warning shrink-0" />
                    <div className="min-w-0 flex-1">
                      <p className="text-sm font-medium text-foreground truncate" title={inv.email_invite}>{inv.email_invite}</p>
                      <p className="text-xs text-muted-foreground">
                        {ROLE_INFO[inv.role_propose].label} · Invité le {format(new Date(inv.invite_le), 'dd MMM yyyy', { locale: fr })}
                        {' · '}
                        Expire le {format(new Date(inv.expire_le), 'dd MMM yyyy', { locale: fr })}
                      </p>
                    </div>
                  </div>
                  {estProprietaire && (
                    <button
                      onClick={() => annulerInvitation(inv, afficherNotification, recharger)}
                      className="btn-secondary text-xs py-1.5 px-3 shrink-0"
                    >
                      Annuler
                    </button>
                  )}
                </li>
              ))}
            </ul>
          )}
        </section>
      )}

      {/* Bloc explicatif rôles */}
      <div className="rounded-xl bg-muted/30 border border-border p-4 text-xs text-muted-foreground">
        <p className="font-semibold text-foreground mb-2">Rôles disponibles</p>
        <ul className="space-y-1.5">
          {(Object.keys(ROLE_INFO) as Role[]).map((r) => {
            const info = ROLE_INFO[r];
            const Icon = info.icon;
            return (
              <li key={r} className="flex items-start gap-2">
                <Icon className={`h-3.5 w-3.5 shrink-0 mt-0.5 ${info.color}`} />
                <span><strong className="text-foreground">{info.label}</strong> — {info.description}</span>
              </li>
            );
          })}
        </ul>
      </div>

      {/* Modals */}
      {modalInviter && (
        <ModaleInviterMembre
          onFermer={() => setModalInviter(false)}
          onInvite={() => { setModalInviter(false); recharger(); }}
        />
      )}
      {modalModifierRole && (
        <ModaleModifierRole
          membre={modalModifierRole}
          onFermer={() => setModalModifierRole(null)}
          onModifie={() => { setModalModifierRole(null); recharger(); }}
        />
      )}
      {modalRevoquer && (
        <ModaleRevoquerMembre
          membre={modalRevoquer}
          onFermer={() => setModalRevoquer(null)}
          onRevoque={() => { setModalRevoquer(null); recharger(); }}
        />
      )}
    </LayoutApp>
  );
}

async function annulerInvitation(inv: Invitation, afficherNotification: (n: any) => void, recharger: () => Promise<void>) {
  if (!confirm(`Annuler l'invitation envoyée à ${inv.email_invite} ?`)) return;
  const { data, error } = await supabase.rpc('fn_annuler_invitation_membre' as any, { p_invitation_id: inv.id });
  if (error || !(data as any)?.success) {
    afficherNotification({ type: 'erreur', message: error?.message || 'Erreur annulation.' });
    return;
  }
  afficherNotification({ type: 'succes', message: 'Invitation annulée.' });
  await recharger();
}

function ModaleInviterMembre({ onFermer, onInvite }: { onFermer: () => void; onInvite: () => void }) {
  const { afficherNotification } = useNotification();
  const [email, setEmail] = useState('');
  const [role, setRole] = useState<Role>('RH');
  const [loading, setLoading] = useState(false);

  async function envoyer() {
    if (!email.trim() || !email.includes('@')) {
      afficherNotification({ type: 'erreur', message: 'E-mail invalide.' });
      return;
    }
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_inviter_membre_etab' as any, {
      p_email: email.trim(),
      p_role: role,
    });
    setLoading(false);
    if (error) {
      afficherNotification({ type: 'erreur', message: error.message });
      return;
    }
    const result = data as any;
    if (!result?.success) {
      const code = result?.error_code;
      const message = codeErreurFr(code) || result?.error || 'Erreur invitation.';
      afficherNotification({ type: 'erreur', message });
      return;
    }
    afficherNotification({
      type: 'succes',
      message: `Invitation créée pour ${email}. L’e-mail est en cours d’envoi.`,
    });
    onInvite();
  }

  return (
    <DialogResponsive open={true} onOpenChange={(o) => { if (!o && !loading) onFermer(); }}>
      <DialogResponsiveContent maxWidth="md">
        <DialogResponsiveHeader>
          <DialogResponsiveTitle>Inviter un membre</DialogResponsiveTitle>
        </DialogResponsiveHeader>
        <DialogResponsiveBody className="space-y-4">
          <label className="block">
            <span className="text-xs font-medium text-foreground mb-1 block">Adresse e-mail *</span>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="input-base"
              placeholder="nom@etablissement.fr"
              autoFocus
              disabled={loading}
            />
          </label>

          <label className="block">
            <span className="text-xs font-medium text-foreground mb-1 block">Rôle proposé *</span>
            <select value={role} onChange={(e) => setRole(e.target.value as Role)} className="input-base" disabled={loading}>
              {ROLES_INVITABLES.map((r) => (
                <option key={r} value={r}>{ROLE_INFO[r].label}</option>
              ))}
            </select>
            <p className="text-[11px] text-muted-foreground mt-1">{ROLE_INFO[role].description}</p>
          </label>

          <div className="rounded-lg bg-amber-50 dark:bg-amber-950/40 border border-amber-200 dark:border-amber-800 p-3 text-xs text-amber-800 dark:text-amber-300 flex gap-2">
            <AlertCircle className="h-4 w-4 shrink-0" />
            <p>Un e-mail d'invitation sera envoyé. Le lien expire dans 7 jours. Le rôle PROPRIETAIRE ne peut être attribué que via promotion d'un membre existant.</p>
          </div>
        </DialogResponsiveBody>
        <DialogResponsiveFooter>
          <button onClick={onFermer} disabled={loading} className="btn-secondary min-h-[44px] disabled:opacity-50">Annuler</button>
          <button onClick={envoyer} disabled={loading || !email.trim()} className="btn-primary min-h-[44px] disabled:opacity-50 inline-flex items-center justify-center gap-2">
            {loading && <Loader2 className="h-4 w-4 animate-spin" />}
            Envoyer l'invitation
          </button>
        </DialogResponsiveFooter>
      </DialogResponsiveContent>
    </DialogResponsive>
  );
}

function ModaleModifierRole({ membre, onFermer, onModifie }: { membre: Membre; onFermer: () => void; onModifie: () => void }) {
  const { afficherNotification } = useNotification();
  const [nouveauRole, setNouveauRole] = useState<Role>(membre.role);
  const [loading, setLoading] = useState(false);

  async function modifier() {
    if (nouveauRole === membre.role) {
      onFermer();
      return;
    }
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_modifier_role_membre' as any, {
      p_membre_id: membre.id,
      p_nouveau_role: nouveauRole,
    });
    setLoading(false);
    if (error) {
      afficherNotification({ type: 'erreur', message: error.message });
      return;
    }
    const result = data as any;
    if (!result?.success) {
      afficherNotification({ type: 'erreur', message: codeErreurFr(result?.error_code) || result?.error || 'Erreur.' });
      return;
    }
    afficherNotification({ type: 'succes', message: `Rôle modifié : ${ROLE_INFO[nouveauRole].label}` });
    onModifie();
  }

  return (
    <DialogResponsive open={true} onOpenChange={(o) => { if (!o && !loading) onFermer(); }}>
      <DialogResponsiveContent maxWidth="md">
        <DialogResponsiveHeader>
          <DialogResponsiveTitle>Modifier le rôle</DialogResponsiveTitle>
        </DialogResponsiveHeader>
        <DialogResponsiveBody className="space-y-4">
          <p className="text-sm text-muted-foreground">Membre : <strong className="text-foreground">{membre.email}</strong></p>

          <label className="block">
            <span className="text-xs font-medium text-foreground mb-1 block">Nouveau rôle *</span>
            <select value={nouveauRole} onChange={(e) => setNouveauRole(e.target.value as Role)} className="input-base" disabled={loading}>
              {ROLES_MODIFIABLES.map((r) => (
                <option key={r} value={r}>{ROLE_INFO[r].label}</option>
              ))}
            </select>
            <p className="text-[11px] text-muted-foreground mt-1">{ROLE_INFO[nouveauRole].description}</p>
          </label>
        </DialogResponsiveBody>
        <DialogResponsiveFooter>
          <button onClick={onFermer} disabled={loading} className="btn-secondary min-h-[44px] disabled:opacity-50">Annuler</button>
          <button onClick={modifier} disabled={loading || nouveauRole === membre.role} className="btn-primary min-h-[44px] disabled:opacity-50 inline-flex items-center justify-center gap-2">
            {loading && <Loader2 className="h-4 w-4 animate-spin" />}
            Modifier
          </button>
        </DialogResponsiveFooter>
      </DialogResponsiveContent>
    </DialogResponsive>
  );
}

function ModaleRevoquerMembre({ membre, onFermer, onRevoque }: { membre: Membre; onFermer: () => void; onRevoque: () => void }) {
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(false);

  async function revoquer() {
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_revoquer_membre' as any, { p_membre_id: membre.id });
    setLoading(false);
    if (error) {
      afficherNotification({ type: 'erreur', message: error.message });
      return;
    }
    const result = data as any;
    if (!result?.success) {
      afficherNotification({ type: 'erreur', message: codeErreurFr(result?.error_code) || result?.error || 'Erreur.' });
      return;
    }
    afficherNotification({ type: 'succes', message: 'Membre révoqué.' });
    onRevoque();
  }

  return (
    <DialogResponsive open={true} onOpenChange={(o) => { if (!o && !loading) onFermer(); }}>
      <DialogResponsiveContent maxWidth="md">
        <DialogResponsiveHeader>
          <DialogResponsiveTitle>Révoquer ce membre ?</DialogResponsiveTitle>
        </DialogResponsiveHeader>
        <DialogResponsiveBody>
          <div className="rounded-lg bg-destructive/10 border border-destructive/30 p-3 text-xs text-destructive flex gap-2">
            <AlertCircle className="h-4 w-4 shrink-0" />
            <p>
              <strong className="block">{membre.email}</strong>
              Ce membre perdra immédiatement son accès à l'établissement. Cette action est réversible (vous pouvez le réinviter ensuite).
            </p>
          </div>
        </DialogResponsiveBody>
        <DialogResponsiveFooter>
          <button onClick={onFermer} disabled={loading} className="btn-secondary min-h-[44px] disabled:opacity-50">Annuler</button>
          <button onClick={revoquer} disabled={loading} className="bg-destructive text-destructive-foreground rounded-xl px-4 py-2 text-sm font-medium hover:bg-destructive/90 disabled:opacity-50 min-h-[44px] inline-flex items-center justify-center gap-2">
            {loading && <Loader2 className="h-4 w-4 animate-spin" />}
            Révoquer
          </button>
        </DialogResponsiveFooter>
      </DialogResponsiveContent>
    </DialogResponsive>
  );
}

function codeErreurFr(code?: string): string | null {
  if (!code) return null;
  switch (code) {
    case 'NON_AUTHENTIFIE': return 'Session expirée, reconnectez-vous.';
    case 'NON_AUTORISE': return 'Vous n\'êtes pas autorisé(e) à effectuer cette action.';
    case 'ROLE_INVALIDE': return 'Rôle invalide.';
    case 'EMAIL_INVALIDE': return 'E-mail invalide.';
    case 'DEJA_MEMBRE': return 'Cet utilisateur est déjà membre de l\'équipe.';
    case 'INVITATION_DEJA_EN_ATTENTE': return 'Une invitation est déjà en attente pour cet e-mail.';
    case 'MEMBRE_INTROUVABLE': return 'Membre introuvable.';
    case 'INVITATION_INTROUVABLE': return 'Invitation introuvable.';
    case 'DERNIER_PROPRIETAIRE': return 'Impossible : il doit toujours rester au moins un propriétaire actif.';
    default: return null;
  }
}
