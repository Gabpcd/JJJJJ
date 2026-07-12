import { useEffect, useState } from 'react';
import { AlertTriangle, MapPin, Clock, Smartphone, Loader2, ShieldCheck } from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { usePageTitle } from '@/hooks/usePageTitle';
import { EmptyState } from '@/components/ui/EmptyState';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { CardY2K } from '@/components/y2k/CardY2K';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface KPI {
  teleportations_7j: number;
  mock_gps_7j: number;
  coherence_7j: number;
  qr_gps_eloigne_7j: number;
  total_ouvertes: number;
}

interface Alerte {
  id: string;
  type_alerte: string;
  severite: string;
  source: string;
  message: string;
  details: any;
  resolu_le: string | null;
  cree_le: string;
}

const PAR_PAGE = 50;
const DECISIONS = [
  { value: 'LEGITIME', label: 'Légitime (faux positif)', description: 'Pas de fraude, alerte fermée sans sanction' },
  { value: 'FRAUDE_AVERTISSEMENT', label: 'Fraude — avertissement', description: 'Note la fraude, avertit le soignant, pas de suspension' },
  { value: 'FRAUDE_SUSPENSION_PROPOSEE', label: 'Fraude — proposer suspension', description: 'Une tâche est créée pour que l\'équipe procède à la suspension manuellement' },
  { value: 'IGNORER', label: 'Ignorer', description: 'Faible importance, alerte fermée' },
];

const LIBELLES_SEVERITE: Record<string, string> = {
  CRITICAL: 'Critique',
  WARNING: 'Avertissement',
  INFO: 'Information',
};

const LIBELLES_TYPE_ALERTE: Record<string, string> = {
  TELEPORTATION_DETECTED: 'Téléportation',
  POINTAGE_INCOHERENT: 'Pointage incohérent',
};

export default function AdminAlertesPointage() {
  usePageTitle('Admin · Alertes pointage');
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [kpis, setKpis] = useState<KPI | null>(null);
  const [alertes, setAlertes] = useState<Alerte[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(0);
  const [typeFiltre, setTypeFiltre] = useState<string>('Tous');
  const [statutFiltre, setStatutFiltre] = useState<string>('OUVERTE');
  const [alerteATraiter, setAlerteATraiter] = useState<Alerte | null>(null);

  async function charger() {
    setLoading(true);
    const [resKpi, resListe] = await Promise.all([
      supabase.rpc('fn_admin_resume_alertes_pointage' as any),
      supabase.rpc('fn_admin_lister_alertes_pointage' as any, {
        p_type_filtre: typeFiltre === 'Tous' ? null : typeFiltre,
        p_statut_filtre: statutFiltre === 'Tous' ? null : statutFiltre,
        p_limit: PAR_PAGE,
        p_offset: page * PAR_PAGE,
      }),
    ]);
    if (resKpi.data && (resKpi.data as any).success) {
      setKpis((resKpi.data as any).kpis as KPI);
    }
    if (resListe.data && (resListe.data as any).success) {
      setAlertes((resListe.data as any).alertes as Alerte[]);
      setTotal((resListe.data as any).total as number);
    } else if (resListe.error) {
      afficherNotification({ type: 'erreur', message: resListe.error.message });
    }
    setLoading(false);
  }

  useEffect(() => { charger(); }, [typeFiltre, statutFiltre, page]);

  if (loading && alertes.length === 0) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  const totalPages = Math.ceil(total / PAR_PAGE);

  return (
    <LayoutAdmin>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-foreground inline-flex items-center gap-2">
          <AlertTriangle className="h-6 w-6 text-warning" /> Alertes pointage anti-triche
        </h1>
        <p className="text-sm text-muted-foreground mt-1">
          Alertes détectées automatiquement : téléportation, position GPS falsifiée, incohérence temporelle. Chaque alerte nécessite votre décision.
        </p>
      </div>

      {/* KPI cards */}
      {kpis && (
        <div className="grid grid-cols-2 md:grid-cols-5 gap-3 mb-6">
          <div className="rounded-2xl border-2 border-destructive/30 bg-destructive/5 p-4">
            <div className="flex items-center gap-1.5 mb-1">
              <MapPin className="h-4 w-4 text-destructive" />
              <p className="text-[10px] uppercase font-semibold text-foreground">Téléportations 7j</p>
            </div>
            <p className="text-2xl font-bold text-destructive tabular-nums">{kpis.teleportations_7j}</p>
          </div>
          <div className="rounded-2xl border-2 border-warning/30 bg-warning/5 p-4">
            <div className="flex items-center gap-1.5 mb-1">
              <Smartphone className="h-4 w-4 text-warning" />
              <p className="text-[10px] uppercase font-semibold text-foreground">Mock GPS 7j</p>
            </div>
            <p className="text-2xl font-bold text-warning tabular-nums">{kpis.mock_gps_7j}</p>
          </div>
          <div className="rounded-2xl border-2 border-warning/30 bg-warning/5 p-4">
            <div className="flex items-center gap-1.5 mb-1">
              <Clock className="h-4 w-4 text-warning" />
              <p className="text-[10px] uppercase font-semibold text-foreground">Cohérence 7j</p>
            </div>
            <p className="text-2xl font-bold text-warning tabular-nums">{kpis.coherence_7j}</p>
          </div>
          <div className="rounded-2xl border-2 border-info/30 bg-info/5 p-4">
            <div className="flex items-center gap-1.5 mb-1">
              <MapPin className="h-4 w-4 text-info" />
              <p className="text-[10px] uppercase font-semibold text-foreground">QR &gt; 1km 7j</p>
            </div>
            <p className="text-2xl font-bold text-info tabular-nums">{kpis.qr_gps_eloigne_7j}</p>
          </div>
          <div className={`rounded-2xl border-2 p-4 ${kpis.total_ouvertes > 5 ? 'border-destructive bg-destructive/10' : 'border-primary/30 bg-primary/5'}`}>
            <p className="text-[10px] uppercase font-semibold text-foreground mb-1">Total ouvertes</p>
            <p className={`text-2xl font-bold tabular-nums ${kpis.total_ouvertes > 5 ? 'text-destructive' : 'text-primary'}`}>
              {kpis.total_ouvertes}
            </p>
          </div>
        </div>
      )}

      {/* Filtres */}
      <div className="flex flex-col sm:flex-row gap-2 mb-4">
        <select
          value={typeFiltre}
          onChange={(e) => { setTypeFiltre(e.target.value); setPage(0); }}
          className="input-base sm:w-64"
        >
          <option value="Tous">Tous les types</option>
          <option value="TELEPORTATION_DETECTED">Téléportation</option>
          <option value="POINTAGE_INCOHERENT">Pointage incohérent</option>
        </select>
        <select
          value={statutFiltre}
          onChange={(e) => { setStatutFiltre(e.target.value); setPage(0); }}
          className="input-base sm:w-48"
        >
          <option value="Tous">Tous statuts</option>
          <option value="OUVERTE">Ouverte</option>
          <option value="RESOLUE">Résolue</option>
        </select>
      </div>

      <p className="text-xs text-muted-foreground mb-2">
        {total} alerte{total > 1 ? 's' : ''}
        {loading && <Loader2 className="inline h-3 w-3 animate-spin ml-2" />}
      </p>

      {/* Liste */}
      <ul className="space-y-2">
        {alertes.map((a) => (
          <li key={a.id}><CardY2K hoverLift={false} className={a.resolu_le ? 'opacity-60' : ''}>
            <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-2">
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2 mb-1">
                  <BadgeY2K variant={a.severite === 'CRITICAL' ? 'error' : a.severite === 'WARNING' ? 'warning' : 'info'} size="sm">
                    {LIBELLES_SEVERITE[a.severite] ?? a.severite}
                  </BadgeY2K>
                  <span className="text-xs text-muted-foreground">{LIBELLES_TYPE_ALERTE[a.type_alerte] ?? a.type_alerte}</span>
                  {a.resolu_le && <span className="text-[11px] text-success">Résolue</span>}
                </div>
                <p className="text-sm text-foreground">{a.message}</p>
                <p className="text-[11px] text-muted-foreground mt-1">
                  {format(new Date(a.cree_le), 'dd MMM yyyy HH:mm:ss', { locale: fr })}
                </p>
                <details className="mt-2">
                  <summary className="text-[11px] cursor-pointer text-primary hover:underline">Détails techniques</summary>
                  <pre className="text-[10px] font-mono bg-muted/30 p-2 rounded-lg mt-1 overflow-x-auto">
                    {`source : ${a.source}`}
                    {a.details ? `\n${JSON.stringify(a.details, null, 2)}` : ''}
                  </pre>
                </details>
              </div>
              {!a.resolu_le && (
                <BoutonY2K variant="primary" size="sm" onClick={() => setAlerteATraiter(a)} className="shrink-0">
                  Traiter
                </BoutonY2K>
              )}
            </div>
          </CardY2K></li>
        ))}
        {alertes.length === 0 && !loading && (
          <li className="list-none">
            <EmptyState
              icone={<ShieldCheck />}
              mascotte="happy"
              titre="Aucune alerte détectée"
              description="Aucune alerte anti-triche ne correspond à ces critères. Les alertes (téléportation, mock GPS, incohérence) apparaîtront ici."
              variant="success"
            />
          </li>
        )}
      </ul>

      {/* Pagination */}
      {totalPages > 1 && (
        <div className="flex items-center justify-between mt-4">
          <p className="text-xs text-muted-foreground">Page {page + 1} / {totalPages}</p>
          <div className="flex gap-2">
            <BoutonY2K variant="secondary" size="sm" onClick={() => setPage((p) => Math.max(0, p - 1))} disabled={page === 0}>Précédent</BoutonY2K>
            <BoutonY2K variant="secondary" size="sm" onClick={() => setPage((p) => Math.min(totalPages - 1, p + 1))} disabled={page >= totalPages - 1}>Suivant</BoutonY2K>
          </div>
        </div>
      )}

      {/* Modale traitement */}
      {alerteATraiter && (
        <ModaleTraiterAlerte
          alerte={alerteATraiter}
          onFermer={() => setAlerteATraiter(null)}
          onTraitee={() => {
            setAlerteATraiter(null);
            charger();
          }}
        />
      )}
    </LayoutAdmin>
  );
}

function ModaleTraiterAlerte({ alerte, onFermer, onTraitee }: { alerte: Alerte; onFermer: () => void; onTraitee: () => void }) {
  const { afficherNotification } = useNotification();
  const [decision, setDecision] = useState<string>('');
  const [motif, setMotif] = useState('');
  const [loading, setLoading] = useState(false);

  async function traiter() {
    if (!decision) {
      afficherNotification({ type: 'erreur', message: 'Sélectionnez une décision.' });
      return;
    }
    if (motif.trim().length < 10) {
      afficherNotification({ type: 'erreur', message: 'Motif obligatoire (min 10 caractères).' });
      return;
    }
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_admin_traiter_alerte_pointage' as any, {
      p_alerte_id: alerte.id,
      p_decision: decision,
      p_motif: motif.trim(),
    });
    setLoading(false);
    if (error || !(data as any)?.success) {
      afficherNotification({ type: 'erreur', message: error?.message || (data as any)?.error || 'Erreur.' });
      return;
    }
    afficherNotification({ type: 'succes', message: 'Alerte traitée.' });
    onTraitee();
  }

  return (
    <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4" onClick={onFermer}>
      <div className="bg-card border border-border rounded-2xl max-w-lg w-full p-6 space-y-4 max-h-[90vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
        <h2 className="text-lg font-bold text-foreground">Traiter l'alerte</h2>

        <div className="rounded-lg bg-muted/40 p-3 text-xs">
          <p className="font-semibold text-foreground">{alerte.type_alerte}</p>
          <p className="text-muted-foreground mt-1">{alerte.message}</p>
        </div>

        <div className="space-y-2">
          <p className="text-xs font-medium text-foreground">Décision *</p>
          {DECISIONS.map((d) => (
            <label key={d.value} className={`flex items-start gap-2 rounded-lg border-2 p-3 cursor-pointer ${
              decision === d.value ? 'border-primary bg-primary/5' : 'border-border bg-background hover:border-primary/40'
            }`}>
              <input
                type="radio"
                name="decision"
                value={d.value}
                checked={decision === d.value}
                onChange={(e) => setDecision(e.target.value)}
                className="mt-1"
                disabled={loading}
              />
              <div>
                <p className="text-sm font-medium text-foreground">{d.label}</p>
                <p className="text-[11px] text-muted-foreground">{d.description}</p>
              </div>
            </label>
          ))}
        </div>

        <label className="block">
          <span className="text-xs font-medium text-foreground mb-1 block">Motif * (min 10 caractères)</span>
          <textarea
            value={motif}
            onChange={(e) => setMotif(e.target.value)}
            className="input-base"
            rows={3}
            placeholder="Justification de la décision (conservée pour traçabilité)…"
            disabled={loading}
          />
          <span className="text-[10px] text-muted-foreground">{motif.length} / 10+</span>
        </label>

        <div className="flex gap-2">
          <BoutonY2K variant="secondary" size="md" onClick={onFermer} disabled={loading} className="flex-1">Annuler</BoutonY2K>
          <BoutonY2K variant="primary" size="md" onClick={traiter} disabled={loading || !decision || motif.trim().length < 10} loading={loading} className="flex-1">
            Confirmer la décision
          </BoutonY2K>
        </div>
      </div>
    </div>
  );
}
