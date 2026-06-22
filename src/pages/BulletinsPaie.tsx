import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { FileText, Download, Loader2, X } from 'lucide-react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { EmptyState } from '@/components/ui/EmptyState';
import { TableOuCartes, type ColonneTableau } from '@/components/ui/TableOuCartes';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { telechargerBulletinPaiePdf } from '@/lib/bulletin-paie-pdf';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

const fmt = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(Number(v) || 0);

const STATUT_CONFIG: Record<string, { label: string; classes: string }> = {
  EMIS: { label: 'Émis', classes: 'bg-primary/10 text-primary' },
  PAYE: { label: 'Payé', classes: 'bg-success/10 text-success' },
  ANNULE: { label: 'Annulé', classes: 'bg-muted text-muted-foreground' },
};

interface BulletinRow {
  id: string;
  numero_bulletin: string;
  mission_id: string;
  etablissement_id: string;
  etablissement_nom: string | null;
  mission_intitule: string | null;
  periode_debut: string;
  periode_fin: string;
  salaire_brut: number;
  total_cotisations_salariales: number;
  net_avant_impot: number;
  ifm: number;
  icp: number;
  statut: string;
  date_emission: string;
  date_paiement: string | null;
}

export default function BulletinsPaie() {
  usePageTitle('Mes bulletins de paie');
  return (
    <LayoutApp role="SOIGNANT">
      <BulletinsPaieContent />
    </LayoutApp>
  );
}

export function BulletinsPaieContent() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [loading, setLoading] = useState(true);
  const [bulletins, setBulletins] = useState<BulletinRow[]>([]);
  const [downloadingId, setDownloadingId] = useState<string | null>(null);
  const [filtreStatut, setFiltreStatut] = useState<string>('tous');
  const [filtreAnnee, setFiltreAnnee] = useState<string>('toutes');

  useEffect(() => {
    if (!user) return;
    (async () => {
      const { data } = await supabase.rpc('fn_mes_bulletins_paie' as any);
      setBulletins((data as unknown as BulletinRow[]) || []);
      setLoading(false);
    })();
  }, [user]);

  const anneesDisponibles = useMemo(() => {
    const annees = new Set<string>();
    bulletins.forEach(b => { if (b.periode_debut) annees.add(String(new Date(b.periode_debut).getFullYear())); });
    return Array.from(annees).sort((a, b) => b.localeCompare(a));
  }, [bulletins]);

  const bulletinsFiltres = useMemo(() => {
    return bulletins.filter(b => {
      if (filtreStatut !== 'tous' && b.statut !== filtreStatut) return false;
      if (filtreAnnee !== 'toutes' && b.periode_debut) {
        const a = String(new Date(b.periode_debut).getFullYear());
        if (a !== filtreAnnee) return false;
      }
      return true;
    });
  }, [bulletins, filtreStatut, filtreAnnee]);

  const filtreActif = filtreStatut !== 'tous' || filtreAnnee !== 'toutes';
  const reinitialiserFiltres = () => { setFiltreStatut('tous'); setFiltreAnnee('toutes'); };

  const totalBrut = bulletinsFiltres.reduce((s, b) => s + Number(b.salaire_brut || 0), 0);
  const totalNet = bulletinsFiltres.reduce((s, b) => s + Number(b.net_avant_impot || 0), 0);
  const totalCotisations = bulletinsFiltres.reduce((s, b) => s + Number(b.total_cotisations_salariales || 0), 0);

  const telecharger = async (id: string) => {
    setDownloadingId(id);
    try {
      await telechargerBulletinPaiePdf(id);
    } catch (err: any) {
      alert(`Erreur lors du téléchargement : ${err?.message || 'inconnue'}`);
    } finally {
      setDownloadingId(null);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20">
        <Loader2 className="h-8 w-8 animate-spin text-primary" />
      </div>
    );
  }

  return (
    <div className="space-y-5">
        <p className="text-xs text-muted-foreground">
          Bulletins émis automatiquement à chaque mission terminée — conformes art. R3243-1 CTW
        </p>

        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
          <div className="card-base">
            <p className="text-xs text-muted-foreground">Brut total</p>
            <p className="text-xl font-bold text-foreground">{fmt(totalBrut)}</p>
          </div>
          <div className="card-base bg-success/5 border-success/20">
            <p className="text-xs text-muted-foreground">Net total perçu</p>
            <p className="text-xl font-bold text-success">{fmt(totalNet)}</p>
          </div>
          <div className="card-base bg-warning/5 border-warning/20">
            <p className="text-xs text-muted-foreground">Cotisations salariales</p>
            <p className="text-xl font-bold text-warning">{fmt(totalCotisations)}</p>
          </div>
        </div>

        {bulletins.length > 0 && (
          <div className="card-base flex flex-wrap items-center gap-2 py-2.5">
            <span className="text-xs font-semibold text-muted-foreground mr-1">Filtres :</span>
            <select
              value={filtreStatut}
              onChange={e => setFiltreStatut(e.target.value)}
              className="text-xs border border-border rounded-md px-2 py-1 bg-background"
            >
              <option value="tous">Tous statuts</option>
              <option value="EMIS">Émis</option>
              <option value="PAYE">Payé</option>
              <option value="ANNULE">Annulé</option>
            </select>
            <select
              value={filtreAnnee}
              onChange={e => setFiltreAnnee(e.target.value)}
              className="text-xs border border-border rounded-md px-2 py-1 bg-background"
            >
              <option value="toutes">Toutes années</option>
              {anneesDisponibles.map(a => <option key={a} value={a}>{a}</option>)}
            </select>
            {filtreActif && (
              <button
                type="button"
                onClick={reinitialiserFiltres}
                className="text-xs text-muted-foreground hover:text-foreground inline-flex items-center gap-1 ml-1"
              >
                <X className="h-3 w-3" /> Réinitialiser
              </button>
            )}
            <span className="text-[10px] text-muted-foreground ml-auto">
              {bulletinsFiltres.length} / {bulletins.length} bulletin{bulletins.length > 1 ? 's' : ''}
            </span>
          </div>
        )}

        {(() => {
          const etatVide = bulletins.length === 0
            ? <EmptyState icone={<FileText />} mascotte="empty" titre="Aucun bulletin de paie pour le moment" description="Les bulletins apparaîtront ici dès que vos missions salariées seront terminées." cta={{ label: 'Trouver une mission', onClick: () => navigate('/soignant/recherche-missions') }} />
            : <EmptyState icone={<FileText />} mascotte="thinking" titre="Aucun bulletin ne correspond aux filtres" cta={{ label: 'Réinitialiser les filtres', onClick: reinitialiserFiltres, variant: 'secondary' }} compact />;

          const colonnes: ColonneTableau<BulletinRow>[] = [
            { cle: 'periode', titre: 'Mois' },
            { cle: 'mission', titre: 'Mission' },
            { cle: 'brut', titre: 'Brut', align: 'right' },
            { cle: 'net', titre: 'Net', align: 'right' },
            { cle: 'statut', titre: 'Statut' },
            { cle: 'actions', titre: '', align: 'right', largeur: 'w-32' },
          ];

          return (
            <TableOuCartes
              colonnes={colonnes}
              donnees={bulletinsFiltres}
              getId={(b) => b.id}
              etatVide={etatVide}
              renduCellule={(b, col) => {
                const config = STATUT_CONFIG[b.statut] || STATUT_CONFIG.EMIS;
                const downloading = downloadingId === b.id;
                switch (col.cle) {
                  case 'periode':
                    return (
                      <span className="text-sm whitespace-nowrap">
                        {format(new Date(b.periode_debut), 'MMM yyyy', { locale: fr })}
                      </span>
                    );
                  case 'mission':
                    return (
                      <div>
                        <p className="font-medium text-foreground line-clamp-1">{b.mission_intitule || '—'}</p>
                        <p className="text-xs text-muted-foreground line-clamp-1">{b.etablissement_nom || '—'}</p>
                      </div>
                    );
                  case 'brut':
                    return <span className="text-sm tabular-nums">{fmt(b.salaire_brut)}</span>;
                  case 'net':
                    return <span className="font-semibold text-foreground tabular-nums">{fmt(b.net_avant_impot)}</span>;
                  case 'statut':
                    return (
                      <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${config.classes}`}>
                        {config.label}
                      </span>
                    );
                  case 'actions':
                    return (
                      <BoutonY2K
                        size="sm"
                        variant="secondary"
                        className="h-8 gap-1 text-xs"
                        disabled={downloading}
                        onClick={(e) => { e.stopPropagation(); telecharger(b.id); }}
                      >
                        {downloading ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Download className="h-3.5 w-3.5" />}
                        PDF
                      </BoutonY2K>
                    );
                  default:
                    return null;
                }
              }}
              renduCarte={(b) => {
                const config = STATUT_CONFIG[b.statut] || STATUT_CONFIG.EMIS;
                const downloading = downloadingId === b.id;
                return (
                  <div className="space-y-3">
                    <div className="flex items-start justify-between gap-3">
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 mb-1 flex-wrap">
                          <span className="font-mono text-xs font-bold text-foreground">{b.numero_bulletin}</span>
                          <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${config.classes}`}>
                            {config.label}
                          </span>
                        </div>
                        <p className="text-sm text-foreground font-medium line-clamp-1">{b.mission_intitule || '—'}</p>
                        <p className="text-xs text-muted-foreground line-clamp-1">{b.etablissement_nom || '—'}</p>
                        <p className="text-[10px] text-muted-foreground mt-1">
                          {format(new Date(b.periode_debut), 'dd/MM/yyyy', { locale: fr })}
                          {' → '}
                          {format(new Date(b.periode_fin), 'dd/MM/yyyy', { locale: fr })}
                        </p>
                      </div>
                      <div className="text-right shrink-0">
                        <p className="text-[10px] text-muted-foreground">Net à payer</p>
                        <p className="text-lg font-bold text-foreground tabular-nums">{fmt(b.net_avant_impot)}</p>
                        <p className="text-[10px] text-muted-foreground">
                          Brut {fmt(b.salaire_brut)}
                        </p>
                      </div>
                    </div>
                    <BoutonY2K
                      size="sm"
                      variant="primary"
                      className="w-full gap-1.5 min-h-[44px]"
                      disabled={downloading}
                      onClick={(e) => { e.stopPropagation(); telecharger(b.id); }}
                    >
                      {downloading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />}
                      Télécharger PDF
                    </BoutonY2K>
                  </div>
                );
              }}
            />
          );
        })()}

        <div className="card-base bg-muted/30 text-xs text-muted-foreground">
          <p>
            <strong className="text-foreground">Conservation :</strong> les bulletins sont conservés
            indéfiniment dans votre espace Jolene. Conformément à l'art. L3243-4 du Code du travail,
            l'employeur doit conserver son double 5 ans minimum. Le salarié doit conserver les siens
            sans limitation de durée (preuve d'activité pour la retraite).
          </p>
        </div>
    </div>
  );
}
