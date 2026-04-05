import React, { useState, useEffect } from 'react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { usePageTitle } from '@/hooks/usePageTitle';
import { extraireMessageErreur } from '@/lib/erreurs';
import { CheckCircle, XCircle, Download, FileText, Loader2 } from 'lucide-react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

export default function AdminReclamations() {
  usePageTitle('Reclamations scoring');
  const { afficherNotification } = useNotification();
  const [reclamations, setReclamations] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [traitement, setTraitement] = useState<string | null>(null);
  const [pointsInput, setPointsInput] = useState<Record<string, number>>({});

  const charger = async () => {
    setLoading(true);
    const { data } = await supabase
      .from('reclamations_scoring')
      .select('*')
      .order('cree_le', { ascending: false })
      .limit(100);

    if (data && data.length > 0) {
      // Enrich with soignant names
      const soignantIds = [...new Set((data as any[]).map(r => r.soignant_id))];
      const { data: soignants } = await supabase
        .from('soignants')
        .select('id, prenom, nom, score_fiabilite')
        .in('id', soignantIds);

      const enriched = (data as any[]).map(r => ({
        ...r,
        soignant: soignants?.find(s => s.id === r.soignant_id) || null,
      }));
      setReclamations(enriched);
    } else {
      setReclamations([]);
    }
    setLoading(false);
  };

  useEffect(() => { charger(); }, []);

  const traiter = async (id: string, decision: 'ACCEPTEE' | 'REFUSEE') => {
    setTraitement(id);
    const points = decision === 'ACCEPTEE' ? (pointsInput[id] || 10) : 0;

    const { data, error } = await supabase.rpc('fn_traiter_reclamation' as any, {
      p_reclamation_id: id,
      p_statut: decision,
      p_points_restaures: points,
    });

    if (error) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
    } else if (data && typeof data === 'object' && (data as any).success === false) {
      afficherNotification({ type: 'erreur', message: (data as any).error || 'Erreur lors du traitement.' });
    } else {
      afficherNotification({ type: 'succes', message: decision === 'ACCEPTEE' ? `Réclamation acceptée, +${points} points restaurés` : 'Réclamation refusée.' });
      await charger();
    }
    setTraitement(null);
  };

  const telechargerJustificatif = async (cle: string, nom: string) => {
    const win = window.open('', '_blank');
    const { data } = await supabase.storage.from('jolene-documents').createSignedUrl(cle, 300);
    if (data?.signedUrl && win) {
      win.location.href = data.signedUrl;
    }
  };

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  const enAttente = reclamations.filter(r => r.statut === 'EN_ATTENTE');
  const traitees = reclamations.filter(r => r.statut !== 'EN_ATTENTE');

  return (
    <LayoutAdmin>
      <h1 className="text-xl font-bold text-foreground mb-6">Réclamations scoring</h1>

      {enAttente.length === 0 && traitees.length === 0 && (
        <div className="text-center py-12">
          <p className="text-muted-foreground">Aucune réclamation pour le moment.</p>
        </div>
      )}

      {enAttente.length > 0 && (
        <div className="space-y-4 mb-8">
          <h2 className="text-base font-semibold text-foreground">En attente ({enAttente.length})</h2>
          {enAttente.map(r => (
            <div key={r.id} className="card-base border-l-4 border-warning space-y-3">
              <div className="flex items-start justify-between">
                <div>
                  <p className="font-semibold text-foreground">
                    {r.soignant?.prenom} {r.soignant?.nom}
                    <span className="ml-2 text-xs text-muted-foreground">Score: {r.soignant?.score_fiabilite}/100</span>
                  </p>
                  <p className="text-xs text-muted-foreground mt-0.5">
                    {format(new Date(r.cree_le), 'd MMM yyyy HH:mm', { locale: fr })}
                  </p>
                </div>
                <span className="badge-base bg-warning/10 text-warning text-xs">{r.motif}</span>
              </div>

              {r.details && <p className="text-sm text-foreground bg-muted/50 rounded-lg p-3">{r.details}</p>}

              {r.justificatif_s3_cle && (
                <button
                  onClick={() => telechargerJustificatif(r.justificatif_s3_cle, r.justificatif_nom_fichier)}
                  className="flex items-center gap-2 text-sm text-primary hover:underline"
                >
                  <FileText className="h-4 w-4" />
                  {r.justificatif_nom_fichier || 'Télécharger le justificatif'}
                </button>
              )}

              <div className="flex items-center gap-3 pt-2">
                <div className="flex items-center gap-2">
                  <label className="text-xs text-muted-foreground">Points à accorder (0-100) :</label>
                  <input
                    type="number"
                    min={1}
                    max={30}
                    value={pointsInput[r.id] || 10}
                    onChange={e => setPointsInput(prev => ({ ...prev, [r.id]: Number(e.target.value) }))}
                    className="input-base w-20 text-sm"
                  />
                </div>
                <div className="flex-1" />
                <button
                  onClick={() => traiter(r.id, 'ACCEPTEE')}
                  disabled={traitement === r.id}
                  className="btn-primary text-xs py-1.5 px-3 flex items-center gap-1 disabled:opacity-50"
                >
                  {traitement === r.id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <CheckCircle className="h-3.5 w-3.5" />}
                  Accepter (+{pointsInput[r.id] || 10} pts)
                </button>
                <button
                  onClick={() => traiter(r.id, 'REFUSEE')}
                  disabled={traitement === r.id}
                  className="btn-danger text-xs py-1.5 px-3 flex items-center gap-1 disabled:opacity-50"
                >
                  <XCircle className="h-3.5 w-3.5" /> Refuser
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      {traitees.length > 0 && (
        <div className="space-y-3">
          <h2 className="text-base font-semibold text-muted-foreground">Traitées ({traitees.length})</h2>
          {traitees.map(r => (
            <div key={r.id} className="flex items-center justify-between p-3 bg-muted/30 rounded-xl">
              <div>
                <span className="text-sm text-foreground">{r.soignant?.prenom} {r.soignant?.nom}</span>
                <span className="text-xs text-muted-foreground ml-2">{r.motif}</span>
              </div>
              <span className={`badge-base text-[10px] ${r.statut === 'ACCEPTEE' ? 'bg-success/10 text-success' : 'bg-destructive/10 text-destructive'}`}>
                {r.statut === 'ACCEPTEE' ? `✅ +${r.points_accordes} pts` : '❌ Refusée'}
              </span>
            </div>
          ))}
        </div>
      )}
    </LayoutAdmin>
  );
}
