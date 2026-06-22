import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Scale, Clock, CheckCircle2, FileText } from 'lucide-react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EmptyState } from '@/components/ui/EmptyState';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface Reclamation {
  id: string;
  evenement_type: 'SOIGNANT' | 'ETAB';
  evenement_id: string;
  motif_categorie: string;
  texte_libre: string;
  justificatif_storage_path: string | null;
  statut: 'PENDING' | 'TRAITEE';
  decision_admin: 'MAINTENIR' | 'REDUIRE' | 'ANNULER' | null;
  motif_admin: string | null;
  traitee_le: string | null;
  cree_le: string;
}

const MOTIFS_LABELS: Record<string, string> = {
  URGENCE_MEDICALE: '🏥 Urgence médicale',
  DEUIL: '🕊️ Deuil',
  FORCE_MAJEURE: '⚡ Force majeure',
  ERREUR_JOLENE: '🔧 Erreur Jolene',
  CONTEXTE_PARTICULIER: '📝 Contexte particulier',
  AUTRE: '❓ Autre',
};

const DECISIONS_LABELS: Record<string, { label: string; color: string }> = {
  MAINTENIR: { label: 'Maintenu', color: 'text-destructive' },
  REDUIRE: { label: 'Réduit', color: 'text-warning' },
  ANNULER: { label: 'Annulé', color: 'text-success' },
};

export default function MesReclamationsEtab() {
  usePageTitle('Mes réclamations');
  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <MesReclamationsContent />
    </LayoutApp>
  );
}

function MesReclamationsContent() {
  const navigate = useNavigate();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [reclamations, setReclamations] = useState<Reclamation[]>([]);
  const [filtreStatut, setFiltreStatut] = useState<'TOUS' | 'PENDING' | 'TRAITEE'>('TOUS');

  async function charger() {
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_mes_reclamations' as any, {
      p_statut: filtreStatut === 'TOUS' ? null : filtreStatut,
    });
    if (error || !(data as any)?.success) {
      afficherNotification({ type: 'erreur', message: error?.message || 'Erreur chargement.' });
      setLoading(false);
      return;
    }
    setReclamations(((data as any).reclamations || []) as Reclamation[]);
    setLoading(false);
  }

  useEffect(() => { charger(); }, [filtreStatut]);

  if (loading && reclamations.length === 0) return <ChargementPage />;

  const enCours = reclamations.filter(r => r.statut === 'PENDING').length;
  const traitees = reclamations.filter(r => r.statut === 'TRAITEE').length;

  return (
    <>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-foreground inline-flex items-center gap-2">
          <Scale className="h-6 w-6 text-primary" /> Mes réclamations score
        </h1>
        <p className="text-sm text-muted-foreground mt-1">
          Suivez vos contestations d'événements de score. L'admin Jolene tranche sous 72h.
        </p>
      </div>

      <div className="grid grid-cols-2 gap-3 mb-6">
        <div className="rounded-2xl border-2 border-warning/30 bg-warning/5 p-4">
          <p className="text-[10px] uppercase font-semibold text-foreground mb-1 inline-flex items-center gap-1">
            <Clock className="h-3 w-3" /> En attente
          </p>
          <p className="text-2xl font-bold text-warning tabular-nums">{enCours}</p>
        </div>
        <div className="rounded-2xl border-2 border-success/30 bg-success/5 p-4">
          <p className="text-[10px] uppercase font-semibold text-foreground mb-1 inline-flex items-center gap-1">
            <CheckCircle2 className="h-3 w-3" /> Traitées
          </p>
          <p className="text-2xl font-bold text-success tabular-nums">{traitees}</p>
        </div>
      </div>

      <div className="flex gap-2 mb-4">
        {(['TOUS', 'PENDING', 'TRAITEE'] as const).map((s) => (
          <button
            key={s}
            type="button"
            onClick={() => setFiltreStatut(s)}
            className={`text-xs px-3 py-1.5 rounded-full border ${
              filtreStatut === s
                ? 'border-primary bg-primary text-primary-foreground'
                : 'border-border bg-background hover:border-primary/40'
            }`}
          >
            {s === 'TOUS' ? 'Toutes' : s === 'PENDING' ? 'En attente' : 'Traitées'}
          </button>
        ))}
      </div>

      {reclamations.length === 0 ? (
        <EmptyState
          icone={<Scale />}
          mascotte="empty"
          titre="Aucune réclamation"
          description="Contestez un événement de score depuis la page « Mon score »."
          cta={{ label: 'Aller à Mon score', onClick: () => navigate('/etablissement/score') }}
        />
      ) : (
        <ul className="space-y-3">
          {reclamations.map((r) => {
            const decisionInfo = r.decision_admin ? DECISIONS_LABELS[r.decision_admin] : null;
            return (
              <li key={r.id} className="card-base">
                <div className="flex items-start justify-between gap-3 flex-wrap mb-2">
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span
                        className={`text-[11px] px-2 py-0.5 rounded-full font-medium ${
                          r.statut === 'PENDING'
                            ? 'bg-warning/20 text-warning'
                            : 'bg-success/20 text-success'
                        }`}
                      >
                        {r.statut === 'PENDING' ? 'En attente' : 'Traitée'}
                      </span>
                      <span className="text-xs text-muted-foreground">
                        {MOTIFS_LABELS[r.motif_categorie] || r.motif_categorie}
                      </span>
                    </div>
                    <p className="text-xs text-muted-foreground mt-1">
                      Soumise le {format(new Date(r.cree_le), "d MMM yyyy 'à' HH:mm", { locale: fr })}
                    </p>
                  </div>
                  {r.justificatif_storage_path && (
                    <span className="text-[11px] text-muted-foreground inline-flex items-center gap-1">
                      <FileText className="h-3 w-3" /> Justificatif joint
                    </span>
                  )}
                </div>
                <p className="text-sm text-foreground mt-2 italic whitespace-pre-wrap">« {r.texte_libre} »</p>

                {r.statut === 'TRAITEE' && decisionInfo && (
                  <div className="mt-3 pt-3 border-t border-border">
                    <p className="text-xs font-semibold text-foreground inline-flex items-center gap-1">
                      Décision admin : <span className={decisionInfo.color}>{decisionInfo.label}</span>
                    </p>
                    {r.motif_admin && (
                      <p className="text-xs text-muted-foreground mt-1 whitespace-pre-wrap">{r.motif_admin}</p>
                    )}
                    {r.traitee_le && (
                      <p className="text-[11px] text-muted-foreground mt-1">
                        Traitée le {format(new Date(r.traitee_le), "d MMM yyyy 'à' HH:mm", { locale: fr })}
                      </p>
                    )}
                  </div>
                )}
              </li>
            );
          })}
        </ul>
      )}
    </>
  );
}
