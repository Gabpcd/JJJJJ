import { useState, useEffect } from 'react';
import { Banknote, Check, X, ChevronDown, ChevronUp, Calendar, Clock, Hash, CreditCard, FileText } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { fetchEtablissementsSafe } from '@/lib/etablissements';
import { useAuth } from '@/contexts/AuthContext';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { toast } from 'sonner';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface PaiementDeclare {
  id: string;
  montant: number;
  mission_id: string;
  etablissement_nom: string;
  reference_virement: string | null;
  methode: string | null;
  date_paiement: string | null;
  mission?: {
    intitule: string;
    debut_le: string;
    fin_le: string;
    duree_heures: number | null;
    taux_horaire_base: number;
    total_brut: number | null;
    net_a_payer: number | null;
  } | null;
  presences?: {
    pointage_arrivee_le: string | null;
    pointage_depart_le: string | null;
    methode_pointage_arrivee: string | null;
  }[];
}

function MotifContestationModal({ onConfirm, onCancel }: { onConfirm: (motif: string) => void; onCancel: () => void }) {
  const [motif, setMotif] = useState('');
  return (
    <div className="mt-3 border border-destructive/20 bg-destructive/5 rounded-xl p-3 space-y-2">
      <p className="text-xs font-semibold text-destructive">Motif de contestation :</p>
      <textarea
        value={motif}
        onChange={e => setMotif(e.target.value)}
        placeholder="Décris pourquoi tu contestes ce paiement..."
        className="input-base text-sm py-2"
        rows={2}
        maxLength={500}
      />
      <div className="flex gap-2">
        <BoutonY2K size="sm" variant="destructive" onClick={() => onConfirm(motif || 'Contesté par le soignant')} disabled={!motif.trim()}>
          Envoyer la contestation
        </BoutonY2K>
        <BoutonY2K size="sm" variant="ghost" onClick={onCancel}>Annuler</BoutonY2K>
      </div>
    </div>
  );
}

function formatMethode(m: string | null): string {
  if (!m) return '—';
  if (m === 'VIREMENT') return '🏦 Virement';
  if (m === 'CHEQUE') return '📝 Chèque';
  if (m === 'NOTE_HONORAIRES') return '📄 Note d\'honoraires';
  if (m === 'STRIPE_CONNECT') return '💳 Stripe Connect';
  if (m === 'ESPECES') return '💵 Espèces';
  return m;
}

export function BandeauPaiementDeclare() {
  const { user } = useAuth();
  const [paiements, setPaiements] = useState<PaiementDeclare[]>([]);
  const [processing, setProcessing] = useState<string | null>(null);
  const [expanded, setExpanded] = useState<string | null>(null);
  const [contesting, setContesting] = useState<string | null>(null);

  useEffect(() => {
    if (!user) return;
    const load = async () => {
      const { data } = await supabase
        .from('paiements_soignant' as any)
        .select('id, montant_net, mission_id, etablissement_id, reference_virement, methode, date_paiement')
        .eq('soignant_id', user.id)
        .eq('statut', 'DECLARE') as any;

      if (!data || data.length === 0) return;

      // Enrich with establishment names
      const etabIds = [...new Set(data.map((p: any) => p.etablissement_id))] as string[];
      const safeMap = await fetchEtablissementsSafe(etabIds);
      const etabMap: Record<string, string> = {};
      Object.entries(safeMap).forEach(([id, e]) => { etabMap[id] = (e as any).nom; });

      // Enrich with mission details
      const missionIds = [...new Set(data.map((p: any) => p.mission_id).filter(Boolean))] as string[];
      const missionMap: Record<string, any> = {};
      const presenceMap: Record<string, any[]> = {};

      if (missionIds.length > 0) {
        const { data: missions } = await supabase
          .from('missions')
          .select('id, intitule, debut_le, fin_le, duree_heures, taux_horaire_base, total_brut, net_a_payer')
          .in('id', missionIds);
        if (missions) {
          missions.forEach((m: any) => { missionMap[m.id] = m; });
        }

        const { data: presences } = await supabase
          .from('presences')
          .select('mission_id, pointage_arrivee_le, pointage_depart_le, methode_pointage_arrivee')
          .in('mission_id', missionIds)
          .order('pointage_arrivee_le', { ascending: true });
        if (presences) {
          presences.forEach((p: any) => {
            if (!presenceMap[p.mission_id]) presenceMap[p.mission_id] = [];
            presenceMap[p.mission_id].push(p);
          });
        }
      }

      setPaiements(data.map((p: any) => ({
        id: p.id,
        montant: p.montant_net,
        mission_id: p.mission_id,
        etablissement_nom: etabMap[p.etablissement_id] || 'Établissement',
        reference_virement: p.reference_virement,
        methode: p.methode,
        date_paiement: p.date_paiement,
        mission: p.mission_id ? missionMap[p.mission_id] || null : null,
        presences: p.mission_id ? presenceMap[p.mission_id] || [] : [],
      })));
    };
    load();
  }, [user]);

  const traiter = async (paiementId: string, confirme: boolean, motif?: string) => {
    setProcessing(paiementId);
    try {
      if (confirme) {
        // RPC dédiée (SECURITY DEFINER) — plus sûre qu'un UPDATE direct
        const { data, error } = await supabase.rpc('fn_confirmer_paiement_soignant' as any, {
          p_paiement_id: paiementId,
        });
        if (error) throw error;
        if ((data as any)?.error) throw new Error((data as any).error);
      } else {
        const { data, error } = await supabase.rpc('fn_contester_paiement_soignant' as any, {
          p_paiement_id: paiementId,
          p_motif: motif || 'Contesté par le soignant',
        });
        if (error) throw error;
        if ((data as any)?.error) throw new Error((data as any).error);
      }
      toast.success(confirme ? 'Paiement confirmé ✅' : 'Contestation envoyée');
      setPaiements(prev => prev.filter(p => p.id !== paiementId));
      setContesting(null);
    } catch {
      toast.error('Erreur lors du traitement');
    }
    setProcessing(null);
  };

  if (paiements.length === 0) return null;

  const fmt = (v: number | null | undefined) =>
    v != null ? new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v) : '—';

  return (
    <div className="space-y-3 mb-4">
      {paiements.map(p => {
        const isExpanded = expanded === p.id;
        const isContesting = contesting === p.id;
        return (
          <div key={p.id} className="rounded-xl border border-primary/30 bg-primary/5 overflow-hidden">
            {/* Header — always visible */}
            <div
              className="p-4 cursor-pointer"
              onClick={() => setExpanded(isExpanded ? null : p.id)}
            >
              <div className="flex items-start gap-3">
                <Banknote className="h-5 w-5 text-primary shrink-0 mt-0.5" />
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-semibold text-foreground">
                    💰 {p.etablissement_nom} déclare t'avoir payé{' '}
                    <span className="text-primary">{fmt(p.montant)}</span>
                  </p>
                  {p.mission?.intitule && (
                    <p className="text-xs text-muted-foreground mt-0.5">
                      Mission : {p.mission.intitule}
                    </p>
                  )}
                  <p className="text-xs text-muted-foreground mt-1">
                    Touchez pour voir le détail · Confirmez ou contestez
                  </p>
                </div>
                {isExpanded ? <ChevronUp className="h-4 w-4 text-muted-foreground shrink-0" /> : <ChevronDown className="h-4 w-4 text-muted-foreground shrink-0" />}
              </div>
            </div>

            {/* Expanded detail */}
            {isExpanded && (
              <div className="border-t border-primary/20 bg-card p-4 space-y-3">
                {/* Payment info */}
                <div className="grid grid-cols-2 gap-3 text-xs">
                  <div className="flex items-center gap-1.5">
                    <CreditCard className="h-3.5 w-3.5 text-muted-foreground" />
                    <span className="text-muted-foreground">Méthode :</span>
                    <span className="font-medium text-foreground">{formatMethode(p.methode)}</span>
                  </div>
                  {p.date_paiement && (
                    <div className="flex items-center gap-1.5">
                      <Calendar className="h-3.5 w-3.5 text-muted-foreground" />
                      <span className="text-muted-foreground">Date :</span>
                      <span className="font-medium text-foreground">{format(new Date(p.date_paiement), 'd MMM yyyy', { locale: fr })}</span>
                    </div>
                  )}
                  {p.reference_virement && (
                    <div className="flex items-center gap-1.5 col-span-2">
                      <Hash className="h-3.5 w-3.5 text-muted-foreground" />
                      <span className="text-muted-foreground">Référence :</span>
                      <span className="font-mono font-medium text-foreground">{p.reference_virement}</span>
                    </div>
                  )}
                </div>

                {/* Mission details */}
                {p.mission && (
                  <div className="border border-border rounded-lg p-3 space-y-2">
                    <div className="flex items-center gap-1.5 text-xs">
                      <FileText className="h-3.5 w-3.5 text-primary" />
                      <span className="font-semibold text-foreground">{p.mission.intitule}</span>
                    </div>
                    <div className="grid grid-cols-2 gap-2 text-xs text-muted-foreground">
                      <div className="flex items-center gap-1">
                        <Calendar className="h-3 w-3" />
                        {format(new Date(p.mission.debut_le), 'EEE d MMM yyyy', { locale: fr })}
                      </div>
                      <div className="flex items-center gap-1">
                        <Clock className="h-3 w-3" />
                        {format(new Date(p.mission.debut_le), "HH'h'mm", { locale: fr })} → {format(new Date(p.mission.fin_le), "HH'h'mm", { locale: fr })}
                        {p.mission.duree_heures ? ` (${p.mission.duree_heures}h)` : ''}
                      </div>
                    </div>
                    <div className="flex gap-4 text-xs">
                      <span className="text-muted-foreground">Taux : <strong className="text-foreground">{p.mission.taux_horaire_base} €/h</strong></span>
                      {p.mission.total_brut != null && <span className="text-muted-foreground">Brut : <strong className="text-foreground">{fmt(p.mission.total_brut)}</strong></span>}
                      <span className="text-muted-foreground">Net : <strong className="text-primary">{fmt(p.mission.net_a_payer ?? p.montant)}</strong></span>
                    </div>
                  </div>
                )}

                {/* Presences / pointages */}
                {p.presences && p.presences.length > 0 && (
                  <div className="border border-border rounded-lg p-3">
                    <p className="text-xs font-semibold text-foreground mb-2">Pointages enregistrés</p>
                    <div className="space-y-1.5">
                      {p.presences.map((pr, i) => (
                        <div key={i} className="flex items-center gap-3 text-xs text-muted-foreground bg-muted/30 rounded-lg px-2.5 py-1.5">
                          <span className="font-medium text-foreground min-w-[80px]">
                            {pr.pointage_arrivee_le ? format(new Date(pr.pointage_arrivee_le), 'd MMM', { locale: fr }) : '—'}
                          </span>
                          <span>
                            Arrivée : {pr.pointage_arrivee_le ? format(new Date(pr.pointage_arrivee_le), "HH'h'mm", { locale: fr }) : '—'}
                          </span>
                          <span>
                            Départ : {pr.pointage_depart_le ? format(new Date(pr.pointage_depart_le), "HH'h'mm", { locale: fr }) : '—'}
                          </span>
                          {pr.methode_pointage_arrivee && (
                            <span className="text-[10px] text-muted-foreground/60">
                              ({pr.methode_pointage_arrivee === 'GPS' ? '📍 GPS' : '🔢 Code'})
                            </span>
                          )}
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {/* Actions */}
                <div className="flex gap-2 pt-1">
                  <BoutonY2K
                    size="sm"
                    onClick={(e) => { e.stopPropagation(); traiter(p.id, true); }}
                    disabled={processing === p.id}
                    loading={processing === p.id}
                    className="gap-1.5"
                    iconeGauche={processing === p.id ? undefined : <Check className="h-3.5 w-3.5" />}
                  >
                    Confirmer la réception
                  </BoutonY2K>
                  <BoutonY2K
                    variant="secondary"
                    size="sm"
                    onClick={(e) => { e.stopPropagation(); setContesting(isContesting ? null : p.id); }}
                    disabled={processing === p.id}
                    className="gap-1.5 text-destructive border-destructive/30 hover:bg-destructive/5"
                    iconeGauche={<X className="h-3.5 w-3.5" />}
                  >
                    Contester
                  </BoutonY2K>
                </div>

                {/* Contest form */}
                {isContesting && (
                  <MotifContestationModal
                    onConfirm={(motif) => traiter(p.id, false, motif)}
                    onCancel={() => setContesting(null)}
                  />
                )}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}
