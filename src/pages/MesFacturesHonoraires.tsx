import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { FileText, Download, Loader2, CheckCircle, Clock, AlertTriangle, Info, Zap, X } from 'lucide-react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { EmptyState } from '@/components/ui/EmptyState';
import { TableOuCartes, type ColonneTableau } from '@/components/ui/TableOuCartes';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { ModalCessionCreance } from '@/components/ModalCessionCreance';
import { telechargerFactureHonorairesPDF } from '@/lib/facture-honoraires-pdf';

const fmt = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(Number(v) || 0);

const STATUT_CONFIG: Record<string, { label: string; icon: JSX.Element; color: string }> = {
  BROUILLON: { label: 'Brouillon', icon: <Clock className="h-3 w-3" />, color: 'bg-muted text-muted-foreground' },
  EMISE: { label: 'Émise', icon: <FileText className="h-3 w-3" />, color: 'bg-primary/10 text-primary' },
  EN_RETARD: { label: 'En retard', icon: <AlertTriangle className="h-3 w-3" />, color: 'bg-destructive/10 text-destructive' },
  PAYEE: { label: 'Payée', icon: <CheckCircle className="h-3 w-3" />, color: 'bg-success/10 text-success' },
  FACTORISEE: { label: 'Avance reçue', icon: <CheckCircle className="h-3 w-3" />, color: 'bg-success/20 text-success' },
  ANNULEE: { label: 'Annulée', icon: <AlertTriangle className="h-3 w-3" />, color: 'bg-muted text-muted-foreground' },
};

export default function MesFacturesHonoraires() {
  usePageTitle('Mes factures d\'honoraires');
  return (
    <LayoutApp role="SOIGNANT">
      <MesFacturesHonorairesContent />
    </LayoutApp>
  );
}

export function MesFacturesHonorairesContent() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [loading, setLoading] = useState(true);
  const [factures, setFactures] = useState<any[]>([]);
  const [mandatSigne, setMandatSigne] = useState(false);

  useEffect(() => {
    if (!user) return;
    (async () => {
      const [{ data: sgData }, { data: facts }] = await Promise.all([
        supabase.from('soignants').select('mandat_facturation_signe').eq('id', user.id).maybeSingle(),
        supabase.rpc('fn_mes_factures_honoraires' as any),
      ]);
      setMandatSigne(!!sgData?.mandat_facturation_signe);
      setFactures(facts || []);
      setLoading(false);
    })();
  }, [user]);

  const [cessionModal, setCessionModal] = useState<{ id: string; numero: string; montant: number } | null>(null);
  const [filtreStatut, setFiltreStatut] = useState<string>('tous');
  const [filtreAnnee, setFiltreAnnee] = useState<string>('toutes');
  const [filtreMois, setFiltreMois] = useState<string>('tous');

  const anneesDisponibles = useMemo(() => {
    const annees = new Set<string>();
    factures.forEach(f => { if (f.date_emission) annees.add(String(new Date(f.date_emission).getFullYear())); });
    return Array.from(annees).sort((a, b) => b.localeCompare(a));
  }, [factures]);

  const facturesFiltrees = useMemo(() => {
    return factures.filter((f: any) => {
      if (filtreStatut !== 'tous' && f.statut !== filtreStatut) return false;
      if (filtreAnnee !== 'toutes' && f.date_emission) {
        const annee = String(new Date(f.date_emission).getFullYear());
        if (annee !== filtreAnnee) return false;
      }
      if (filtreMois !== 'tous' && f.date_emission) {
        const mois = String(new Date(f.date_emission).getMonth() + 1).padStart(2, '0');
        if (mois !== filtreMois) return false;
      }
      return true;
    });
  }, [factures, filtreStatut, filtreAnnee, filtreMois]);

  const filtreActif = filtreStatut !== 'tous' || filtreAnnee !== 'toutes' || filtreMois !== 'tous';
  const reinitialiserFiltres = () => {
    setFiltreStatut('tous');
    setFiltreAnnee('toutes');
    setFiltreMois('tous');
  };

  const ouvrirCession = (facture: any) => {
    setCessionModal({
      id: facture.id,
      numero: facture.numero_facture,
      montant: Number(facture.montant_ttc),
    });
  };

  const onCessionSuccess = () => {
    navigate('/soignant/mes-gains?tab=avances');
  };

  const telechargerFacturePDF = telechargerFactureHonorairesPDF;

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20">
        <Loader2 className="h-8 w-8 animate-spin text-primary" />
      </div>
    );
  }

  const totalFacture = facturesFiltrees.reduce((s, f) => s + Number(f.montant_ttc || 0), 0);
  const totalPaye = facturesFiltrees.filter(f => f.statut === 'PAYEE' || f.statut === 'FACTORISEE').reduce((s, f) => s + Number(f.montant_ttc || 0), 0);
  const totalAttente = facturesFiltrees.filter(f => f.statut === 'EMISE' || f.statut === 'EN_RETARD').reduce((s, f) => s + Number(f.montant_ttc || 0), 0);

  return (
    <>
      <div className="space-y-5">
        {!mandatSigne && (
          <div className="rounded-xl border-2 border-warning/30 bg-warning/5 p-4 flex items-start gap-3">
            <Info className="h-5 w-5 text-warning shrink-0 mt-0.5" />
            <div className="flex-1">
              <p className="font-semibold text-foreground">Mandat de facturation non signé</p>
              <p className="text-sm text-muted-foreground mt-0.5">
                Pour que Jolene puisse produire automatiquement vos factures d'honoraires et préparer l'accès au paiement rapide,
                vous devez d'abord signer le mandat de facturation.
              </p>
              <BoutonY2K onClick={() => navigate('/soignant/mandat-facturation')} className="mt-3 gap-2" size="sm">
                Signer le mandat
              </BoutonY2K>
            </div>
          </div>
        )}

        {/* KPIs */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
          <div className="card-base">
            <p className="text-xs text-muted-foreground">Total facturé</p>
            <p className="text-xl font-bold text-foreground">{fmt(totalFacture)}</p>
          </div>
          <div className="card-base border-success/20 bg-success/5">
            <p className="text-xs text-muted-foreground">Encaissé</p>
            <p className="text-xl font-bold text-success">{fmt(totalPaye)}</p>
          </div>
          <div className="card-base border-warning/20 bg-warning/5">
            <p className="text-xs text-muted-foreground">En attente</p>
            <p className="text-xl font-bold text-warning">{fmt(totalAttente)}</p>
          </div>
        </div>

        {factures.length > 0 && (
          <div className="card-base flex flex-wrap items-center gap-2 py-2.5">
            <span className="text-xs font-semibold text-muted-foreground mr-1">Filtres :</span>
            <select
              value={filtreStatut}
              onChange={e => setFiltreStatut(e.target.value)}
              className="text-xs border border-border rounded-md px-2 py-1 bg-background"
            >
              <option value="tous">Tous statuts</option>
              <option value="BROUILLON">Brouillon</option>
              <option value="EMISE">Émise</option>
              <option value="EN_RETARD">En retard</option>
              <option value="PAYEE">Payée</option>
              <option value="FACTORISEE">Avance reçue</option>
              <option value="ANNULEE">Annulée</option>
            </select>
            <select
              value={filtreAnnee}
              onChange={e => setFiltreAnnee(e.target.value)}
              className="text-xs border border-border rounded-md px-2 py-1 bg-background"
            >
              <option value="toutes">Toutes années</option>
              {anneesDisponibles.map(a => <option key={a} value={a}>{a}</option>)}
            </select>
            <select
              value={filtreMois}
              onChange={e => setFiltreMois(e.target.value)}
              className="text-xs border border-border rounded-md px-2 py-1 bg-background"
            >
              <option value="tous">Tous mois</option>
              <option value="01">Janvier</option>
              <option value="02">Février</option>
              <option value="03">Mars</option>
              <option value="04">Avril</option>
              <option value="05">Mai</option>
              <option value="06">Juin</option>
              <option value="07">Juillet</option>
              <option value="08">Août</option>
              <option value="09">Septembre</option>
              <option value="10">Octobre</option>
              <option value="11">Novembre</option>
              <option value="12">Décembre</option>
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
              {facturesFiltrees.length} / {factures.length} facture{factures.length > 1 ? 's' : ''}
            </span>
          </div>
        )}

        {(() => {
          const etatVide = factures.length === 0
            ? <EmptyState
                icone={<FileText />}
                mascotte={mandatSigne ? 'empty' : 'thinking'}
                titre="Aucune facture d'honoraires pour le moment"
                description={mandatSigne
                  ? 'Les factures apparaîtront dès que vos missions seront terminées et validées.'
                  : "Signez d'abord le mandat de facturation pour commencer à recevoir des factures automatiques."}
                variant={mandatSigne ? 'info' : 'warning'}
              />
            : <EmptyState
                icone={<FileText />}
                mascotte="thinking"
                titre="Aucune facture ne correspond aux filtres"
                cta={{ label: 'Réinitialiser les filtres', onClick: reinitialiserFiltres, variant: 'secondary' }}
                compact
              />;

          const colonnes: ColonneTableau<any>[] = [
            { cle: 'numero', titre: 'N° facture' },
            { cle: 'mission', titre: 'Mission' },
            { cle: 'date', titre: 'Émise le' },
            { cle: 'montant', titre: 'Montant', align: 'right' },
            { cle: 'statut', titre: 'Statut' },
            { cle: 'actions', titre: '', align: 'right', largeur: 'w-40' },
          ];

          return (
            <TableOuCartes
              colonnes={colonnes}
              donnees={facturesFiltrees}
              getId={(f: any) => f.id}
              etatVide={etatVide}
              renduCellule={(f: any, col) => {
                const config = STATUT_CONFIG[f.statut] || STATUT_CONFIG.EMISE;
                switch (col.cle) {
                  case 'numero':
                    return <span className="font-mono text-xs font-bold text-foreground">{f.numero_facture}</span>;
                  case 'mission':
                    return (
                      <div>
                        <p className="font-medium text-foreground line-clamp-1" title={f.mission_intitule || undefined}>{f.mission_intitule || '—'}</p>
                        <p className="text-xs text-muted-foreground line-clamp-1" title={f.etablissement_nom}>{f.etablissement_nom}</p>
                      </div>
                    );
                  case 'date':
                    return (
                      <span className="text-xs text-muted-foreground whitespace-nowrap">
                        {f.date_emission ? format(new Date(f.date_emission), 'dd/MM/yyyy', { locale: fr }) : '—'}
                      </span>
                    );
                  case 'montant':
                    return <span className="font-semibold text-foreground tabular-nums">{fmt(f.montant_ttc)}</span>;
                  case 'statut':
                    return (
                      <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full inline-flex items-center gap-1 ${config.color}`}>
                        {config.icon} {config.label}
                      </span>
                    );
                  case 'actions':
                    return (
                      <div className="flex items-center justify-end gap-1">
                        <BoutonY2K size="sm" variant="secondary" className="h-8 gap-1 text-xs" onClick={(e) => { e.stopPropagation(); telechargerFacturePDF(f.id); }}>
                          <Download className="h-3.5 w-3.5" /> PDF
                        </BoutonY2K>
                        {(f.statut === 'EMISE' || f.statut === 'EN_RETARD') && (
                          <BoutonY2K size="sm" className="h-8 gap-1 text-xs" onClick={(e) => { e.stopPropagation(); ouvrirCession(f); }}>
                            <Zap className="h-3 w-3" /> Avance
                          </BoutonY2K>
                        )}
                      </div>
                    );
                  default:
                    return null;
                }
              }}
              renduCarte={(f: any) => {
                const config = STATUT_CONFIG[f.statut] || STATUT_CONFIG.EMISE;
                return (
                  <div className="space-y-3">
                    <div className="flex items-start justify-between gap-3">
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 mb-1 flex-wrap">
                          <span className="font-mono text-xs font-bold text-foreground">{f.numero_facture}</span>
                          <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full inline-flex items-center gap-1 ${config.color}`}>
                            {config.icon} {config.label}
                          </span>
                          {(!f.template_version || f.template_version === 'v1') && (
                            <span className="text-[9px] px-1.5 py-0.5 rounded bg-muted text-muted-foreground" title="Facture générée avec l'ancien template (avant Factur-X)">Format historique</span>
                          )}
                        </div>
                        <p className="text-sm text-foreground font-medium line-clamp-1" title={f.mission_intitule || undefined}>{f.mission_intitule || '—'}</p>
                        <p className="text-xs text-muted-foreground line-clamp-1" title={f.etablissement_nom}>{f.etablissement_nom}</p>
                        <p className="text-[10px] text-muted-foreground mt-1">
                          Émise le {f.date_emission ? format(new Date(f.date_emission), 'dd/MM/yyyy', { locale: fr }) : '—'}
                          {f.date_echeance && ` · Échéance ${format(new Date(f.date_echeance), 'dd/MM/yyyy', { locale: fr })}`}
                          {f.date_paiement && ` · Payée le ${format(new Date(f.date_paiement), 'dd/MM/yyyy', { locale: fr })}`}
                        </p>
                      </div>
                      <div className="text-right shrink-0">
                        <p className="text-lg font-bold text-foreground tabular-nums">{fmt(f.montant_ttc)}</p>
                        <p className="text-[10px] text-muted-foreground">Exonéré TVA</p>
                      </div>
                    </div>
                    <div className="flex flex-wrap gap-2 pt-1">
                      <BoutonY2K
                        size="sm"
                        variant="primary"
                        className="flex-1 gap-1.5 min-h-[44px]"
                        onClick={(e) => { e.stopPropagation(); telechargerFacturePDF(f.id); }}
                      >
                        <Download className="h-4 w-4" /> Télécharger Factur-X
                      </BoutonY2K>
                      {(f.statut === 'EMISE' || f.statut === 'EN_RETARD') && (
                        <BoutonY2K
                          size="sm"
                          variant="secondary"
                          className="gap-1.5 min-h-[44px]"
                          onClick={(e) => { e.stopPropagation(); ouvrirCession(f); }}
                        >
                          <Zap className="h-3.5 w-3.5" /> Recevoir maintenant
                        </BoutonY2K>
                      )}
                    </div>
                  </div>
                );
              }}
            />
          );
        })()}
      </div>

      {cessionModal && (
        <ModalCessionCreance
          open={!!cessionModal}
          onClose={() => setCessionModal(null)}
          factureId={cessionModal.id}
          numeroFacture={cessionModal.numero}
          montant={cessionModal.montant}
          onSuccess={onCessionSuccess}
        />
      )}
    </>
  );
}
