import React, { useState, useEffect, useCallback } from 'react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { AlertTriangle, Send, Clock, CheckCircle, XCircle, Shield, MessageSquare } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { sanitizeText } from '@/lib/sanitize';
import { extraireMessageErreur } from '@/lib/erreurs';
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

const STATUT_LABELS: Record<string, { label: string; icon: React.ReactNode; color: string }> = {
  CONTESTEE: { label: 'Contestée', icon: <AlertTriangle className="h-3.5 w-3.5" />, color: 'text-warning' },
  RESOLUE_SOIGNANT: { label: 'Résolue (soignant)', icon: <CheckCircle className="h-3.5 w-3.5" />, color: 'text-success' },
  RESOLUE_ETABLISSEMENT: { label: 'Résolue (établissement)', icon: <CheckCircle className="h-3.5 w-3.5" />, color: 'text-success' },
  RESOLUE_ADMIN: { label: 'Résolue (admin)', icon: <Shield className="h-3.5 w-3.5" />, color: 'text-primary' },
};

export function PanneauContestation({
  presenceId, missionId, etablissementId, soignantId, presenceValideeLe, role, onUpdate,
}: Props) {
  const { user } = useAuth();
  const [litige, setLitige] = useState<Litige | null>(null);
  const [loading, setLoading] = useState(true);
  const [motif, setMotif] = useState('');
  const [reponse, setReponse] = useState('');
  const [envoi, setEnvoi] = useState(false);
  const [showForm, setShowForm] = useState(false);

  const charger = useCallback(async () => {
    const { data } = await supabase
      .from('litiges')
      .select('*')
      .eq('presence_id', presenceId)
      .order('cree_le', { ascending: false })
      .limit(1)
      .maybeSingle();
    setLitige(data);
    setLoading(false);
  }, [presenceId]);

  useEffect(() => { charger(); }, [charger]);

  // Soignant peut contester dans les 48h après validation
  const peutContester = role === 'SOIGNANT'
    && presenceValideeLe
    && !litige
    && (Date.now() - new Date(presenceValideeLe).getTime()) < 48 * 60 * 60 * 1000;

  // Établissement peut répondre si statut CONTESTEE
  const peutRepondre = role === 'ETABLISSEMENT' && litige?.statut === 'CONTESTEE' && !litige.reponse;

  const creerContestation = async () => {
    if (!user || !motif.trim()) return;
    setEnvoi(true);
    try {
      const { error } = await supabase.from('litiges').insert({
        mission_id: missionId,
        presence_id: presenceId,
        soignant_id: soignantId,
        etablissement_id: etablissementId,
        motif: sanitizeText(motif.trim()),
        statut: 'CONTESTEE',
        initie_par: 'SOIGNANT',
      });
      if (error) throw error;

      // Audit
      await supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user.id,
        p_type_acteur: 'SOIGNANT',
        p_action: 'PRESENCE_CONTESTATION',
        p_type_ressource: 'presence',
        p_id_ressource: presenceId,
        p_cle_s3: null,
        p_details: { motif: motif.trim(), mission_id: missionId },
        p_ip: null,
        p_navigateur: navigator.userAgent,
      });

      // Notification à l'établissement
      await supabase.rpc('fn_creer_notification', {
        p_destinataire_id: etablissementId,
        p_type_destinataire: 'ETABLISSEMENT',
        p_type: 'CONTESTATION_PRESENCE',
        p_titre: 'Présence contestée',
        p_corps: `Un soignant a contesté la validation d'une présence.`,
        p_lien: `/etablissement/presences`,
        p_type_ressource: 'presence',
        p_id_ressource: presenceId,
      });

      toast.success('Contestation envoyée');
      setMotif('');
      setShowForm(false);
      charger();
      onUpdate?.();
    } catch (err: any) {
      toast.error(extraireMessageErreur(err));
    } finally {
      setEnvoi(false);
    }
  };

  const envoyerReponse = async () => {
    if (!user || !litige || !reponse.trim()) return;
    setEnvoi(true);
    try {
      const { error } = await supabase
        .from('litiges')
        .update({
          reponse: sanitizeText(reponse.trim()),
          statut: 'RESOLUE_ETABLISSEMENT',
          resolu_le: new Date().toISOString(),
          resolu_par: user.id,
        })
        .eq('id', litige.id);
      if (error) throw error;

      await supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user.id,
        p_type_acteur: 'ADMIN_ETABLISSEMENT',
        p_action: 'CONTESTATION_REPONSE',
        p_type_ressource: 'litige',
        p_id_ressource: litige.id,
        p_cle_s3: null,
        p_details: { reponse: reponse.trim(), presence_id: presenceId },
        p_ip: null,
        p_navigateur: navigator.userAgent,
      });

      // Notification au soignant
      await supabase.rpc('fn_creer_notification', {
        p_destinataire_id: soignantId,
        p_type_destinataire: 'SOIGNANT',
        p_type: 'REPONSE_CONTESTATION',
        p_titre: 'Réponse à votre contestation',
        p_corps: `L'établissement a répondu à votre contestation de présence.`,
        p_lien: `/soignant/presences`,
        p_type_ressource: 'presence',
        p_id_ressource: presenceId,
      });

      toast.success('Réponse envoyée');
      setReponse('');
      charger();
      onUpdate?.();
    } catch (err: any) {
      toast.error(extraireMessageErreur(err));
    } finally {
      setEnvoi(false);
    }
  };

  if (loading) return null;

  // No contestation and can't create one → nothing to show
  if (!litige && !peutContester) return null;

  return (
    <div className="border border-border rounded-xl overflow-hidden mt-2">
      {/* Header */}
      <div className="bg-muted/50 px-3 py-2 flex items-center gap-2 text-xs font-semibold text-foreground">
        <MessageSquare className="h-3.5 w-3.5 text-primary" />
        Contestation
        {litige && (
          <span className={`ml-auto flex items-center gap-1 ${STATUT_LABELS[litige.statut]?.color || 'text-muted-foreground'}`}>
            {STATUT_LABELS[litige.statut]?.icon}
            {STATUT_LABELS[litige.statut]?.label || litige.statut}
          </span>
        )}
      </div>

      <div className="p-3 space-y-3">
        {/* Existing litige timeline */}
        {litige && (
          <div className="space-y-3">
            {/* Motif */}
            <div className="flex gap-2">
              <div className="w-6 h-6 rounded-full bg-warning/20 flex items-center justify-center flex-shrink-0 mt-0.5">
                <AlertTriangle className="h-3 w-3 text-warning" />
              </div>
              <div className="flex-1">
                <p className="text-xs font-semibold text-foreground">Contestation du soignant</p>
                <p className="text-xs text-muted-foreground">
                  {format(new Date(litige.cree_le), "d MMM yyyy 'à' HH:mm", { locale: fr })}
                </p>
                <p className="text-sm text-foreground mt-1 bg-muted/50 rounded-lg px-3 py-2">{litige.motif}</p>
              </div>
            </div>

            {/* Réponse établissement */}
            {litige.reponse && (
              <div className="flex gap-2">
                <div className="w-6 h-6 rounded-full bg-primary/20 flex items-center justify-center flex-shrink-0 mt-0.5">
                  <MessageSquare className="h-3 w-3 text-primary" />
                </div>
                <div className="flex-1">
                  <p className="text-xs font-semibold text-foreground">Réponse de l'établissement</p>
                  {litige.resolu_le && (
                    <p className="text-xs text-muted-foreground">
                      {format(new Date(litige.resolu_le), "d MMM yyyy 'à' HH:mm", { locale: fr })}
                    </p>
                  )}
                  <p className="text-sm text-foreground mt-1 bg-muted/50 rounded-lg px-3 py-2">{litige.reponse}</p>
                </div>
              </div>
            )}

            {/* Admin resolution */}
            {litige.statut === 'RESOLUE_ADMIN' && litige.resolution && (
              <div className="flex gap-2">
                <div className="w-6 h-6 rounded-full bg-primary/20 flex items-center justify-center flex-shrink-0 mt-0.5">
                  <Shield className="h-3 w-3 text-primary" />
                </div>
                <div className="flex-1">
                  <p className="text-xs font-semibold text-foreground">Décision admin</p>
                  <p className="text-sm text-foreground mt-1 bg-primary/5 border border-primary/20 rounded-lg px-3 py-2">{litige.resolution}</p>
                </div>
              </div>
            )}

            {/* Pending badge */}
            {litige.statut === 'CONTESTEE' && !litige.reponse && (
              <div className="flex items-center gap-2 text-xs text-muted-foreground bg-muted/30 rounded-lg px-3 py-2">
                <Clock className="h-3.5 w-3.5" />
                {role === 'SOIGNANT'
                  ? 'En attente de la réponse de l\'établissement…'
                  : 'Le soignant a contesté cette présence. Veuillez répondre.'}
              </div>
            )}
          </div>
        )}

        {/* Soignant: create contestation form */}
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
              placeholder="Décrivez le motif de votre contestation…"
              rows={3}
              className="w-full rounded-lg border border-border bg-background px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground resize-none focus:outline-none focus:ring-2 focus:ring-primary/50"
            />
            <div className="flex items-center gap-2">
              <button
                onClick={creerContestation}
                disabled={!motif.trim() || envoi}
                className="flex items-center gap-1.5 bg-warning text-warning-foreground text-xs font-semibold px-3 py-2 rounded-xl disabled:opacity-50 hover:bg-warning/90 transition-colors"
              >
                <Send className="h-3.5 w-3.5" /> {envoi ? 'Envoi…' : 'Envoyer'}
              </button>
              <button onClick={() => { setShowForm(false); setMotif(''); }} className="text-xs text-muted-foreground hover:text-foreground">
                Annuler
              </button>
            </div>
            <p className="text-[11px] text-muted-foreground">
              ⏱ Vous avez 48h après la validation pour contester.
            </p>
          </div>
        )}

        {/* Établissement: respond form */}
        {peutRepondre && (
          <div className="space-y-2 border-t border-border pt-3">
            <textarea
              value={reponse}
              onChange={(e) => setReponse(e.target.value.slice(0, 500))}
              placeholder="Votre réponse à la contestation…"
              rows={3}
              className="w-full rounded-lg border border-border bg-background px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground resize-none focus:outline-none focus:ring-2 focus:ring-primary/50"
            />
            <button
              onClick={envoyerReponse}
              disabled={!reponse.trim() || envoi}
              className="flex items-center gap-1.5 bg-primary text-primary-foreground text-xs font-semibold px-3 py-2 rounded-xl disabled:opacity-50 hover:opacity-90 transition-opacity"
            >
              <Send className="h-3.5 w-3.5" /> {envoi ? 'Envoi…' : 'Répondre'}
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
