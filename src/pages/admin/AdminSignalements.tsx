import { useEffect, useState, useCallback } from 'react';
import { Flag, Loader2, ChevronRight } from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { usePageTitle } from '@/hooks/usePageTitle';
import { EmptyState } from '@/components/ui/EmptyState';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { useNavigate } from 'react-router-dom';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface Signalement {
  id: string;
  signaleur_type: string; signaleur_nom: string | null;
  cible_id: string; cible_type: string; cible_nom: string | null;
  categorie: string; motif: string; mission_id: string | null;
  statut: string; resolution: string | null;
  cree_le: string; traite_le: string | null;
}

const CAT_LABEL: Record<string, string> = {
  COMPORTEMENT_INAPPROPRIE: 'Comportement inapproprié',
  NON_PROFESSIONNALISME: 'Manque de professionnalisme',
  FRAUDE_SUSPECTEE: 'Fraude suspectée',
  FAUX_DOCUMENT: 'Faux document',
  USURPATION_IDENTITE: "Usurpation d'identité",
  SECURITE_DANGER: 'Sécurité / danger',
  AUTRE: 'Autre',
};

const STATUTS = [
  { value: '', label: 'Tous' },
  { value: 'OUVERT', label: 'Ouverts' },
  { value: 'EN_COURS', label: 'En cours' },
  { value: 'TRAITE', label: 'Traités' },
  { value: 'REJETE', label: 'Rejetés' },
];

function statutBadge(s: string): 'warning' | 'info' | 'success' | 'error' {
  if (s === 'OUVERT') return 'warning';
  if (s === 'EN_COURS') return 'info';
  if (s === 'TRAITE') return 'success';
  return 'error';
}

export default function AdminSignalements() {
  usePageTitle('Signalements');
  const { afficherNotification } = useNotification();
  const navigate = useNavigate();
  const [items, setItems] = useState<Signalement[]>([]);
  const [loading, setLoading] = useState(true);
  const [filtre, setFiltre] = useState('');
  const [busy, setBusy] = useState<string | null>(null);

  const charger = useCallback(async () => {
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_admin_lister_signalements' as any, { p_statut: filtre || null });
    if (error) afficherNotification({ type: 'erreur', message: 'Erreur de chargement des signalements.' });
    setItems((data as any) || []);
    setLoading(false);
  }, [filtre, afficherNotification]);

  useEffect(() => { charger(); }, [charger]);

  async function traiter(id: string, statut: string, resolution?: string) {
    setBusy(id);
    const { data, error } = await supabase.rpc('fn_admin_traiter_signalement' as any, { p_id: id, p_statut: statut, p_resolution: resolution || null });
    setBusy(null);
    if (error || !(data as any)?.success) {
      afficherNotification({ type: 'erreur', message: (data as any)?.error || 'Action impossible.' });
      return;
    }
    afficherNotification({ type: 'succes', message: 'Signalement mis à jour.' });
    charger();
  }

  return (
    <LayoutAdmin>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-foreground inline-flex items-center gap-2"><Flag className="h-5 w-5 text-destructive" /> Signalements</h1>
        <p className="text-sm text-muted-foreground mt-1">Signalements d'utilisateurs transmis par les soignants et les établissements.</p>
      </div>

      <div className="flex flex-wrap gap-2 mb-4">
        {STATUTS.map((s) => (
          <button key={s.value} onClick={() => setFiltre(s.value)}
            className={`px-3 py-1.5 rounded-full text-sm font-medium transition-colors ${filtre === s.value ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground hover:bg-muted/70'}`}>
            {s.label}
          </button>
        ))}
      </div>

      {loading ? (
        <div className="flex justify-center py-12"><Loader2 className="h-6 w-6 animate-spin text-primary" /></div>
      ) : items.length === 0 ? (
        <EmptyState icone={<Flag />} mascotte="happy" titre="Aucun signalement" description="Aucun signalement à traiter pour ce filtre." />
      ) : (
        <div className="space-y-3">
          {items.map((s) => (
            <div key={s.id} className="card-base">
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <BadgeY2K variant={statutBadge(s.statut)}>{s.statut}</BadgeY2K>
                    <span className="text-sm font-semibold text-foreground">{CAT_LABEL[s.categorie] || s.categorie}</span>
                  </div>
                  <p className="text-sm text-foreground mt-1">
                    <span className="text-muted-foreground">{s.signaleur_nom || s.signaleur_type}</span>
                    {' → '}
                    <button onClick={() => navigate(s.cible_type === 'SOIGNANT' ? `/admin/utilisateurs/${s.cible_id}` : `/admin/utilisateurs/${s.cible_id}`)}
                      className="font-medium text-primary hover:underline inline-flex items-center gap-0.5">
                      {s.cible_nom || s.cible_type} <ChevronRight className="h-3 w-3" />
                    </button>
                  </p>
                  <p className="text-sm text-foreground/80 mt-2 whitespace-pre-wrap">{s.motif}</p>
                  <p className="text-xs text-muted-foreground mt-2">{format(new Date(s.cree_le), 'dd/MM/yyyy HH:mm', { locale: fr })}</p>
                </div>
              </div>
              {s.statut !== 'TRAITE' && s.statut !== 'REJETE' && (
                <div className="flex flex-wrap gap-2 mt-3 pt-3 border-t border-border">
                  {s.statut === 'OUVERT' && (
                    <BoutonY2K size="sm" variant="secondary" disabled={busy === s.id} onClick={() => traiter(s.id, 'EN_COURS')}>Prendre en charge</BoutonY2K>
                  )}
                  <BoutonY2K size="sm" disabled={busy === s.id} onClick={() => traiter(s.id, 'TRAITE', 'Traité par l\'administration')}>Marquer traité</BoutonY2K>
                  <button disabled={busy === s.id} onClick={() => traiter(s.id, 'REJETE', 'Rejeté (sans suite)')}
                    className="text-sm text-muted-foreground hover:text-destructive px-3 py-1.5">Rejeter</button>
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </LayoutAdmin>
  );
}
