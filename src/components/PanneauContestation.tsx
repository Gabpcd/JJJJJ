import React, { useState, useEffect, useCallback } from 'react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { AlertTriangle, Send, Clock, CheckCircle, Shield, MessageSquare, Ban, ArrowRight, Handshake } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { useRole } from '@/hooks/useRole';
import { sanitizeText } from '@/lib/sanitize';
import { extraireMessageErreur } from '@/lib/erreurs';
import { capturerErreurSentry } from '@/lib/sentry';
import { toast } from 'sonner';

interface Litige {
  id: string;
  mission_id: string;
  presence_id: string;
  soignant_id: string;
  etablissement_id: string;
  motif: string;
  reponse: string | null;
  resolution: string | null;
  statut: string;
  initie_par: string;
  cree_le: string;
  resolu_le: string | null;
  resolu_par: string | null;
  accord_soignant: boolean | null;
  accord_etablissement: boolean | null;
  accord_soignant_le: string | null;
  accord_etablissement_le: string | null;
}

interface Props {
  presenceId: string;
  missionId: string;
  etablissementId: string;
  soignantId: string;
  presenceValideeLe: string | null;
  role: 'SOIGNANT' | 'ETABLISSEMENT';
  onUpdate?: () => void;
}

// Lot 13 : fenêtre de contestation alignée sur la spec (72 h, comme
// l'auto-validation) — l'ancienne valeur 48 h créait un écart avec le
// wording produit et la CGU §4.6.
const DELAI_CONTESTATION_MS = 72 * 60 * 60 * 1000;

const STATUT_CONFIG: Record<string, { label: string; icon: React.ReactNode; color: string }> = {
  CONTESTEE: { label: 'Contestée', icon: <AlertTriangle className="h-3.5 w-3.5" />, color: 'text-warning' },
  EN_DISCUSSION: { label: 'En discussion', icon: <MessageSquare className="h-3.5 w-3.5" />, color: 'text-primary' },
  RESOLUE_SOIGNANT: { label: 'Résolue (soignant)', icon: <CheckCircle className="h-3.5 w-3.5" />, color: 'text-success' },
  RESOLUE_ETABLISSEMENT: { label: 'Résolue (établissement)', icon: <CheckCircle className="h-3.5 w-3.5" />, color: 'text-success' },
  RESOLUE_ADMIN: { label: 'Résolue (admin)', icon: <Shield className="h-3.5 w-3.5" />, color: 'text-primary' },
  FERME: { label: 'Fermé', icon: <Ban className="h-3.5 w-3.5" />, color: 'text-muted-foreground' },
};

export function PanneauContestation({
  presenceId, missionId, etablissementId, soignantId, presenceValideeLe, role, onUpdate,
}: Props) {
  const { user } = useAuth();
  const { role: roleGlobal } = useRole();
  const estAdminPlateforme = (roleGlobal as string) === 'ADMIN_PLATEFORME';
  const [litige, setLitige] = useState<Litige | null>(null);
  const [loading, setLoading] = useState(true);
  const [motif, setMotif] = useState('');
  const [reponse, setReponse] = useState('');
  const [envoi, setEnvoi] = useState(false);
  const [showForm, setShowForm] = useState(false);

  const charger = useCallback(async () => {
    const { data } = await supabase
      .from('litiges')
      .select('id, presence_id, mission_id, soignant_id, etablissement_id, initie_par, motif, reponse, statut, resolution, resolu_le, resolu_par, cree_le, accord_soignant, accord_etablissement, accord_soignant_le, accord_etablissement_le')
      .eq('presence_id', presenceId)
      .order('cree_le', { ascending: false })
      .limit(1)
      .maybeSingle();
    setLitige(data);
    setLoading(false);
  }, [presenceId]);

  useEffect(() => { charger(); }, [charger]);

  const dansFenetre = presenceValideeLe
    ? (Date.now() - new Date(presenceValideeLe).getTime()) < DELAI_CONTESTATION_MS
    : false;

  // Les deux rôles peuvent contester dans la fenêtre (72 h) si aucun litige.
  const peutContester = dansFenetre && !litige;

  // The other party can respond when status is CONTESTEE or EN_DISCUSSION
  const estInitiateur = litige?.initie_par === (role === 'SOIGNANT' ? 'SOIGNANT' : 'ETABLISSEMENT');
  const estRepondant = litige && !estInitiateur;
  const statutOuvert = litige?.statut === 'CONTESTEE' || litige?.statut === 'EN_DISCUSSION';
  const peutRepondre = estRepondant && statutOuvert && !litige?.reponse;
  // Initiator can reply again if status moved to EN_DISCUSSION and there's a response
  const peutRelancer = estInitiateur && litige?.statut === 'EN_DISCUSSION' && !!litige?.reponse;
  // Parties can move to EN_DISCUSSION, only admin can resolve/close
  const peutPasserEnDiscussion = (peutRepondre || peutRelancer) && litige?.statut === 'CONTESTEE';

  const estResolu = litige && ['RESOLUE_SOIGNANT', 'RESOLUE_ETABLISSEMENT', 'RESOLUE_ADMIN', 'FERME'].includes(litige.statut);

  const roleActeur = role === 'SOIGNANT' ? 'SOIGNANT' : 'ADMIN_ETABLISSEMENT';
  const roleLabel = role === 'SOIGNANT' ? 'soignant' : 'établissement';
  const autreRoleLabel = role === 'SOIGNANT' ? 'établissement' : 'soignant';

  const creerContestation = async () => {
    if (!user || !motif.trim()) return;
    setEnvoi(true);
    try {
      const { data: litigeResult, error } = await supabase.rpc('fn_ouvrir_litige_rate_limited' as any, {
        p_mission_id: missionId,
        p_motif: sanitizeText(motif.trim()),
      });
      if (error) throw error;
      if (litigeResult?.error) throw new Error(litigeResult.error);

      await supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user.id, p_type_acteur: roleActeur,
        p_action: 'PRESENCE_CONTESTATION', p_type_ressource: 'presence',
        p_id_ressource: presenceId, p_cle_s3: null,
        p_details: { motif: motif.trim(), mission_id: missionId, initie_par: role },
        p_ip: null, p_navigateur: navigator.userAgent,
      });

      // Notify the other party
      const destId = role === 'SOIGNANT' ? etablissementId : soignantId;
      const destType = role === 'SOIGNANT' ? 'ETABLISSEMENT' : 'SOIGNANT';
      const lien = role === 'SOIGNANT' ? '/etablissement/presences' : '/soignant/presences';
      await supabase.rpc('fn_creer_notification', {
        p_destinataire_id: destId, p_type_destinataire: destType,
        p_type: 'CONTESTATION_PRESENCE',
        p_titre: 'Présence contestée',
        p_corps: `Le ${roleLabel} a contesté une présence validée.`,
        p_lien: lien, p_type_ressource: 'presence', p_id_ressource: presenceId,
      });

      toast.success('Contestation envoyée');
      setMotif('');
      setShowForm(false);
      charger();
      onUpdate?.();
    } catch (err: any) {
      capturerErreurSentry(err, 'PanneauContestation', 'contester_presence');
      toast.error(extraireMessageErreur(err));
    } finally {
      setEnvoi(false);
    }
  };

  const envoyerReponse = async () => {
    if (!user || !litige || !reponse.trim()) return;
    setEnvoi(true);
    try {
      const { data: rpcResult, error } = await supabase.rpc('fn_repondre_litige' as any, {
        p_litige_id: litige.id,
        p_reponse: sanitizeText(reponse.trim()),
      });
      if (error) throw error;
      if (rpcResult?.error) throw new Error(rpcResult.error);

      toast.success('Réponse envoyée');
      setReponse('');
      charger();
      onUpdate?.();
    } catch (err: any) {
      capturerErreurSentry(err, 'PanneauContestation', 'repondre_litige');
      toast.error(extraireMessageErreur(err));
    } finally {
      setEnvoi(false);
    }
  };

  // Admin-only: resolve or close a litige via RPC
  const resoudreAdmin = async (resolution: 'RESOLUE_SOIGNANT' | 'RESOLUE_ETABLISSEMENT' | 'FERME') => {
    if (!user || !litige) return;
    setEnvoi(true);
    try {
      const { data, error } = await supabase.rpc('fn_resoudre_litige' as any, {
        p_litige_id: litige.id,
        p_resolution: resolution,
      });
      if (error) throw error;
      if (data?.error) throw new Error(data.error);

      toast.success('Litige résolu');
      charger();
      onUpdate?.();
    } catch (err: any) {
      capturerErreurSentry(err, 'PanneauContestation', 'resoudre_admin');
      toast.error(extraireMessageErreur(err));
    } finally {
      setEnvoi(false);
    }
  };

  if (loading) return null;
  if (!litige && !peutContester) return null;

  // Amicable closure logic
  const monAccord = role === 'SOIGNANT' ? litige?.accord_soignant : litige?.accord_etablissement;
  const autreAccord = role === 'SOIGNANT' ? litige?.accord_etablissement : litige?.accord_soignant;
  const peutProposerCloture = litige && statutOuvert && !estResolu && !monAccord;
  const autreAPropose = litige && statutOuvert && !estResolu && autreAccord && !monAccord;
  const enAttenteCloture = litige && statutOuvert && !estResolu && monAccord && !autreAccord;

  const proposerCloture = async () => {
    if (!user || !litige) return;
    setEnvoi(true);
    try {
      const { data, error } = await supabase.rpc('fn_proposer_cloture_litige' as any, {
        p_litige_id: litige.id,
      });
      if (error) throw error;
      if (data?.error) throw new Error(data.error);

      if (data?.statut === 'cloture_validee') {
        toast.success('✅ Litige clôturé à l\'amiable !');
      } else {
        toast.success('Proposition de clôture envoyée');
      }
      charger();
      onUpdate?.();
    } catch (err: any) {
      capturerErreurSentry(err, 'PanneauContestation', 'proposer_cloture');
      toast.error(extraireMessageErreur(err));
    } finally {
      setEnvoi(false);
    }
  };

  const initiePar = litige?.initie_par === 'SOIGNANT' ? 'du soignant' : "de l'établissement";

  return (
    <div className="border border-border rounded-xl overflow-hidden mt-2">
      {/* Header */}
      <div className="bg-muted/50 px-3 py-2 flex items-center gap-2 text-xs font-semibold text-foreground">
        <MessageSquare className="h-3.5 w-3.5 text-primary" />
        Contestation
        {litige && (
          <span className={`ml-auto flex items-center gap-1 ${STATUT_CONFIG[litige.statut]?.color || 'text-muted-foreground'}`}>
            {STATUT_CONFIG[litige.statut]?.icon}
            {STATUT_CONFIG[litige.statut]?.label || litige.statut}
          </span>
        )}
      </div>

      <div className="p-3 space-y-3">
        {/* Timeline */}
        {litige && (
          <div className="space-y-3">
            {/* Step 1: Initial contestation */}
            <div className="flex gap-2">
              <div className="w-6 h-6 rounded-full bg-warning/20 flex items-center justify-center flex-shrink-0 mt-0.5">
                <AlertTriangle className="h-3 w-3 text-warning" />
              </div>
              <div className="flex-1">
                <p className="text-xs font-semibold text-foreground">
                  Contestation {initiePar}
                </p>
                <p className="text-xs text-muted-foreground">
                  {format(new Date(litige.cree_le), "d MMM yyyy 'à' HH:mm", { locale: fr })}
                </p>
                <p className="text-sm text-foreground mt-1 bg-muted/50 rounded-lg px-3 py-2">{litige.motif}</p>
              </div>
            </div>

            {/* Step 2: Response (EN_DISCUSSION) */}
            {litige.reponse && (
              <div className="flex gap-2">
                <div className="w-6 h-6 rounded-full bg-primary/20 flex items-center justify-center flex-shrink-0 mt-0.5">
                  <ArrowRight className="h-3 w-3 text-primary" />
                </div>
                <div className="flex-1">
                  <p className="text-xs font-semibold text-foreground">
                    Réponse {litige.initie_par === 'SOIGNANT' ? "de l'établissement" : 'du soignant'}
                  </p>
                  <p className="text-sm text-foreground mt-1 bg-muted/50 rounded-lg px-3 py-2">{litige.reponse}</p>
                </div>
              </div>
            )}

            {/* Step 3: Resolution */}
            {litige.resolution && litige.statut !== 'RESOLUE_ADMIN' && (
              <div className="flex gap-2">
                <div className="w-6 h-6 rounded-full bg-success/20 flex items-center justify-center flex-shrink-0 mt-0.5">
                  <CheckCircle className="h-3 w-3 text-success" />
                </div>
                <div className="flex-1">
                  <p className="text-xs font-semibold text-foreground">Résolution</p>
                  {litige.resolu_le && (
                    <p className="text-xs text-muted-foreground">
                      {format(new Date(litige.resolu_le), "d MMM yyyy 'à' HH:mm", { locale: fr })}
                    </p>
                  )}
                  <p className="text-sm text-foreground mt-1 bg-success/5 border border-success/20 rounded-lg px-3 py-2">{litige.resolution}</p>
                </div>
              </div>
            )}

            {/* Admin decision */}
            {litige.statut === 'RESOLUE_ADMIN' && litige.resolution && (
              <div className="flex gap-2">
                <div className="w-6 h-6 rounded-full bg-primary/20 flex items-center justify-center flex-shrink-0 mt-0.5">
                  <Shield className="h-3 w-3 text-primary" />
                </div>
                <div className="flex-1">
                  <p className="text-xs font-semibold text-foreground">Décision de l'admin plateforme</p>
                  {litige.resolu_le && (
                    <p className="text-xs text-muted-foreground">
                      {format(new Date(litige.resolu_le), "d MMM yyyy 'à' HH:mm", { locale: fr })}
                    </p>
                  )}
                  <p className="text-sm text-foreground mt-1 bg-primary/5 border border-primary/20 rounded-lg px-3 py-2">{litige.resolution}</p>
                </div>
              </div>
            )}

            {/* Pending states */}
            {litige.statut === 'CONTESTEE' && !litige.reponse && (
              <div className="flex items-center gap-2 text-xs text-muted-foreground bg-muted/30 rounded-lg px-3 py-2">
                <Clock className="h-3.5 w-3.5" />
                En attente de la réponse {autreRoleLabel === 'soignant' ? 'du soignant' : "de l'établissement"}…
                <span className="ml-auto text-[11px]">72h pour répondre</span>
              </div>
            )}

            {litige.statut === 'EN_DISCUSSION' && !estResolu && (
              <div className="flex items-center gap-2 text-xs text-muted-foreground bg-primary/5 rounded-lg px-3 py-2">
                <MessageSquare className="h-3.5 w-3.5 text-primary" />
                Discussion en cours — si pas de résolution sous 72h, l'admin plateforme tranchera.
              </div>
            )}
          </div>
        )}

        {/* Create contestation (either role) */}
        {peutContester && !showForm && (
          <button
            onClick={() => setShowForm(true)}
            className="flex items-center gap-1.5 text-xs font-semibold text-warning hover:text-warning/80 transition-colors"
          >
            <AlertTriangle className="h-3.5 w-3.5" /> Contester cette présence
          </button>
        )}

        {peutContester && showForm && (
          <div className="space-y-2">
            <textarea
              value={motif}
              onChange={(e) => setMotif(e.target.value.slice(0, 500))}
              placeholder={role === 'SOIGNANT'
                ? 'Les heures validées ne correspondent pas à ma présence réelle…'
                : 'Le soignant n\'était pas présent ou les heures sont incorrectes…'}
              rows={3}
              className="w-full rounded-lg border border-border bg-background px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground resize-none focus:outline-none focus:ring-2 focus:ring-primary/50"
            />
            <div className="flex items-center gap-2">
              <button
                onClick={creerContestation}
                disabled={!motif.trim() || envoi}
                className="flex items-center gap-1.5 bg-warning text-warning-foreground text-xs font-semibold px-3 py-2 rounded-xl disabled:opacity-50 hover:bg-warning/90 transition-colors"
              >
                <Send className="h-3.5 w-3.5" /> {envoi ? 'Envoi…' : 'Envoyer la contestation'}
              </button>
              <button onClick={() => { setShowForm(false); setMotif(''); }} className="text-xs text-muted-foreground hover:text-foreground">
                Annuler
              </button>
            </div>
            <p className="text-[11px] text-muted-foreground">
              Vous avez 72 h après la validation pour contester. Sans résolution sous 72 h, l'admin plateforme tranchera.
            </p>
          </div>
        )}

        {/* Respond (other party — move to EN_DISCUSSION only) */}
        {(peutRepondre || (peutRelancer && !estAdminPlateforme)) && (
          <div className="space-y-2 border-t border-border pt-3">
            <p className="text-xs font-semibold text-foreground">
              Répondre à la contestation
            </p>
            <textarea
              value={reponse}
              onChange={(e) => setReponse(e.target.value.slice(0, 500))}
              placeholder="Votre réponse à la contestation…"
              rows={3}
              className="w-full rounded-lg border border-border bg-background px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground resize-none focus:outline-none focus:ring-2 focus:ring-primary/50"
            />
            <div className="flex items-center gap-2">
              <button
                onClick={envoyerReponse}
                disabled={!reponse.trim() || envoi}
                className="flex items-center gap-1.5 bg-primary text-primary-foreground text-xs font-semibold px-3 py-2 rounded-xl disabled:opacity-50 hover:opacity-90 transition-opacity"
              >
                <Send className="h-3.5 w-3.5" /> {envoi ? 'Envoi…' : 'Répondre'}
              </button>
              <p className="text-[11px] text-muted-foreground">{reponse.length}/500</p>
            </div>
          </div>
        )}

        {/* Amicable closure */}
        {!estAdminPlateforme && litige && statutOuvert && !estResolu && (
          <div className="border-t border-border pt-3">
            {enAttenteCloture && (
              <div className="flex items-center gap-2 text-xs text-muted-foreground bg-muted/30 rounded-lg px-3 py-2">
                <Clock className="h-3.5 w-3.5" />
                En attente d'accord de l'autre partie pour la clôture à l'amiable
              </div>
            )}
            {autreAPropose && (
              <button
                onClick={proposerCloture}
                disabled={envoi}
                className="flex items-center gap-1.5 bg-success/10 text-success text-xs font-semibold px-3 py-2 rounded-xl disabled:opacity-50 hover:bg-success/20 transition-colors border border-success/20"
              >
                <CheckCircle className="h-3.5 w-3.5" /> ✅ Accepter la clôture à l'amiable
              </button>
            )}
            {peutProposerCloture && !autreAPropose && (
              <button
                onClick={proposerCloture}
                disabled={envoi}
                className="flex items-center gap-1.5 bg-accent text-accent-foreground text-xs font-semibold px-3 py-2 rounded-xl disabled:opacity-50 hover:bg-accent/80 transition-colors border border-border"
              >
                <Handshake className="h-3.5 w-3.5" /> 🤝 Proposer la clôture à l'amiable
              </button>
            )}
          </div>
        )}

        {/* Admin-only: resolution buttons */}
        {estAdminPlateforme && litige && statutOuvert && (
          <div className="space-y-2 border-t border-border pt-3">
            <p className="text-xs font-semibold text-foreground flex items-center gap-1.5">
              <Shield className="h-3.5 w-3.5 text-primary" /> Actions administrateur
            </p>
            <div className="flex flex-wrap gap-2">
              <button
                onClick={() => resoudreAdmin('RESOLUE_SOIGNANT')}
                disabled={envoi}
                className="flex items-center gap-1.5 bg-success/10 text-success text-xs font-semibold px-3 py-2 rounded-xl disabled:opacity-50 hover:bg-success/20 transition-colors border border-success/20"
              >
                <CheckCircle className="h-3.5 w-3.5" /> Résoudre en faveur du soignant
              </button>
              <button
                onClick={() => resoudreAdmin('RESOLUE_ETABLISSEMENT')}
                disabled={envoi}
                className="flex items-center gap-1.5 bg-primary/10 text-primary text-xs font-semibold px-3 py-2 rounded-xl disabled:opacity-50 hover:bg-primary/20 transition-colors border border-primary/20"
              >
                <CheckCircle className="h-3.5 w-3.5" /> Résoudre en faveur de l'établissement
              </button>
              <button
                onClick={() => resoudreAdmin('FERME')}
                disabled={envoi}
                className="flex items-center gap-1.5 bg-muted text-muted-foreground text-xs font-semibold px-3 py-2 rounded-xl disabled:opacity-50 hover:bg-muted/80 transition-colors border border-border"
              >
                <Ban className="h-3.5 w-3.5" /> Fermer
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
