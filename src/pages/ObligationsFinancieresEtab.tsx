import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { ArrowLeft, AlertTriangle, Banknote, FileText, Building2, Users, Loader2, ExternalLink } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { usePageTitle } from '@/hooks/usePageTitle';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { format, differenceInDays } from 'date-fns';
import { fr } from 'date-fns/locale';
import { EmptyState } from '@/components/ui/EmptyState';

interface Obligations {
  total_du: number;
  total_soignants_du: number;
  total_commissions_du: number;
  nb_missions_non_payees: number;
  nb_paiements_en_attente: number;
  nb_factures_impayees: number;
  missions_non_payees?: Array<MissionNonPayee>;
  paiements_soignants_en_attente?: Array<PaiementEnAttente>;
  factures?: Array<Facture>;
}

interface MissionNonPayee {
  mission_id: string;
  intitule: string;
  debut_le: string;
  fin_le: string;
  total_brut: number;
  net_a_payer: number;
  montant_commission_ttc: number;
  soignant_nom: string;
  soignant_profession: string;
  soignant_type_exercice?: string;
  type_contrat_applique?: string;
  type_paiement_soignant?: string;
  mode_paiement_soignant?: string;
  heures?: number;
  jours_depuis_fin?: number;
  soignant_stripe_connect?: boolean;
  a_paiement_conteste?: boolean;
}

interface PaiementEnAttente {
  paiement_id: string;
  mission_id: string;
  montant_net: number;
  methode?: string;
  reference_virement?: string;
  date_paiement?: string;
  statut: string;
  mission_intitule: string;
  soignant_nom: string;
  soignant_profession?: string;
}

interface Facture {
  id?: string;
  numero?: string;
  montant_ttc?: number;
  statut?: string;
  date_echeance?: string;
}

type FiltreType = 'TOUS' | 'SOIGNANTS' | 'COMMISSIONS';

/**
 * Page obligations financières consolidée (Sprint 5.5 PR 9).
 *
 * Fix P0-7 audit Sprint 5 : la route /etablissement/obligations redirigeait
 * vers /etablissement/facturation. Aucune page consolidée listant les
 * obligations financières en attente côté étab.
 *
 * Cette page appelle fn_obligations_financieres (RPC backend existante)
 * et présente :
 *  - 3 KPIs en tête (total dû, soignants dus, commissions dues)
 *  - Filtre par type (tous / soignants / commissions Jolene)
 *  - Liste missions non payées avec contexte (jours retard, type contrat, Stripe Connect)
 *  - Liste paiements en attente (déclarés non confirmés)
 *  - Liens vers détail mission + page facturation pour règlement
 */
export default function ObligationsFinancieresEtab() {
  usePageTitle('Obligations financières');
  const navigate = useNavigate();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [obligations, setObligations] = useState<Obligations | null>(null);
  const [filtre, setFiltre] = useState<FiltreType>('TOUS');

  useEffect(() => {
    let cancelled = false;
    async function load() {
      const { data, error } = await supabase.rpc('fn_obligations_financieres' as any);
      if (cancelled) return;
      if (error) {
        afficherNotification({ type: 'erreur', message: error.message });
        setLoading(false);
        return;
      }
      const result = data as any;
      if (result?.error) {
        afficherNotification({ type: 'erreur', message: result.error });
        setLoading(false);
        return;
      }
      setObligations(result as Obligations);
      setLoading(false);
    }
    load();
    return () => { cancelled = true; };
  }, [afficherNotification]);

  const missionsNonPayees = useMemo(() => obligations?.missions_non_payees ?? [], [obligations]);
  const paiementsEnAttente = useMemo(() => obligations?.paiements_soignants_en_attente ?? [], [obligations]);

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><ChargementPage /></LayoutApp>;
  if (!obligations) {
    return (
      <LayoutApp role="ADMIN_ETABLISSEMENT">
        <p className="text-muted-foreground">Données non disponibles.</p>
      </LayoutApp>
    );
  }

  const totalDu = Number(obligations.total_du ?? 0);
  const totalSoignants = Number(obligations.total_soignants_du ?? 0);
  const totalCommissions = Number(obligations.total_commissions_du ?? 0);

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <button onClick={() => navigate(-1)} className="flex items-center gap-1 text-sm text-primary hover:underline mb-2">
        <ArrowLeft className="h-4 w-4" /> Retour
      </button>

      <div className="mb-6">
        <h1 className="text-2xl font-bold text-foreground inline-flex items-center gap-2">
          <Banknote className="h-6 w-6 text-primary" /> Obligations financières
        </h1>
        <p className="text-sm text-muted-foreground mt-1">
          Vue consolidée de vos dettes en attente : soignants à payer + commissions Jolene + factures publiques.
        </p>
      </div>

      {/* KPIs */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-3 mb-6">
        <KPICard
          titre="Total dû"
          montant={totalDu}
          icon={Banknote}
          variant="primary"
          subtitle={`${obligations.nb_missions_non_payees + obligations.nb_factures_impayees} ligne${(obligations.nb_missions_non_payees + obligations.nb_factures_impayees) > 1 ? 's' : ''}`}
        />
        <KPICard
          titre="Soignants à payer"
          montant={totalSoignants}
          icon={Users}
          variant="warning"
          subtitle={`${obligations.nb_missions_non_payees} mission${obligations.nb_missions_non_payees > 1 ? 's' : ''} terminée${obligations.nb_missions_non_payees > 1 ? 's' : ''}`}
          onClick={() => navigate('/etablissement/facturation?tab=missions-a-payer')}
        />
        <KPICard
          titre="Commissions Jolene"
          montant={totalCommissions}
          icon={Building2}
          variant="info"
          subtitle={`${obligations.nb_factures_impayees} facture${obligations.nb_factures_impayees > 1 ? 's' : ''} impayée${obligations.nb_factures_impayees > 1 ? 's' : ''}`}
          onClick={() => navigate('/etablissement/facturation?tab=commissions')}
        />
      </div>

      {/* Filtre */}
      <div className="flex gap-2 mb-4 overflow-x-auto">
        {([
          { v: 'TOUS', label: 'Tous' },
          { v: 'SOIGNANTS', label: `Soignants (${missionsNonPayees.length + paiementsEnAttente.length})` },
          { v: 'COMMISSIONS', label: `Commissions Jolene (${obligations.nb_factures_impayees})` },
        ] as Array<{ v: FiltreType; label: string }>).map((f) => (
          <button
            key={f.v}
            onClick={() => setFiltre(f.v)}
            className={`whitespace-nowrap px-3 py-1.5 rounded-full text-xs font-medium transition-colors ${
              filtre === f.v ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground hover:bg-muted/80'
            }`}
          >
            {f.label}
          </button>
        ))}
      </div>

      {/* Sections */}
      {(filtre === 'TOUS' || filtre === 'SOIGNANTS') && (
        <section className="mb-6">
          <h2 className="text-lg font-bold text-foreground mb-3 flex items-center gap-2">
            <Users className="h-5 w-5 text-primary" /> Missions à payer
          </h2>
          {missionsNonPayees.length === 0 ? (
            <EmptyState
              icone={<Users />}
              titre="Aucune mission en attente de paiement"
              description="Toutes vos missions terminées ont été réglées."
              variant="success"
              compact
            />
          ) : (
            <ul className="space-y-2">
              {missionsNonPayees.map((m) => (
                <MissionNonPayeeCard key={m.mission_id} mission={m} onVoir={() => navigate(`/etablissement/missions/${m.mission_id}`)} />
              ))}
            </ul>
          )}
        </section>
      )}

      {(filtre === 'TOUS' || filtre === 'SOIGNANTS') && paiementsEnAttente.length > 0 && (
        <section className="mb-6">
          <h2 className="text-lg font-bold text-foreground mb-3 flex items-center gap-2">
            <FileText className="h-5 w-5 text-warning" /> Paiements déclarés en attente de confirmation soignant
          </h2>
          <ul className="space-y-2">
            {paiementsEnAttente.map((p) => (
              <li key={p.paiement_id} className="card-base flex flex-col sm:flex-row sm:items-center gap-2 sm:justify-between">
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-medium text-foreground truncate">{p.mission_intitule}</p>
                  <p className="text-xs text-muted-foreground">{p.soignant_nom}{p.soignant_profession ? ` · ${p.soignant_profession}` : ''}</p>
                  {p.date_paiement && (
                    <p className="text-[11px] text-muted-foreground">
                      Déclaré le {format(new Date(p.date_paiement), 'dd MMM yyyy', { locale: fr })}
                    </p>
                  )}
                </div>
                <div className="flex items-center gap-3 shrink-0">
                  <span className="text-base font-bold text-warning">{formatEur(p.montant_net)}</span>
                  <button
                    onClick={() => navigate(`/etablissement/missions/${p.mission_id}`)}
                    className="btn-secondary text-xs py-1.5 px-3"
                  >
                    Voir
                  </button>
                </div>
              </li>
            ))}
          </ul>
        </section>
      )}

      {(filtre === 'TOUS' || filtre === 'COMMISSIONS') && (
        <section className="mb-6">
          <h2 className="text-lg font-bold text-foreground mb-3 flex items-center gap-2">
            <Building2 className="h-5 w-5 text-info" /> Commissions Jolene
          </h2>
          {obligations.nb_factures_impayees === 0 ? (
            <EmptyState
              icone={<Building2 />}
              titre="Aucune commission Jolene impayée"
              description="Toutes les commissions Jolene sont réglées."
              variant="success"
              compact
            />
          ) : (
            <button
              onClick={() => navigate('/etablissement/facturation?tab=commissions')}
              className="card-base w-full flex items-center justify-between hover:border-primary transition-colors"
            >
              <div className="text-left">
                <p className="text-sm font-medium text-foreground">{obligations.nb_factures_impayees} facture{obligations.nb_factures_impayees > 1 ? 's' : ''} en attente</p>
                <p className="text-xs text-muted-foreground mt-0.5">Total : {formatEur(totalCommissions)}</p>
              </div>
              <ExternalLink className="h-4 w-4 text-primary shrink-0" />
            </button>
          )}
        </section>
      )}

      <div className="rounded-xl bg-muted/30 border border-border p-4 text-xs text-muted-foreground">
        <p className="font-semibold text-foreground mb-1">À propos de cette page</p>
        <ul className="list-disc list-inside space-y-1">
          <li>Vue consolidée alimentée par la RPC <code>fn_obligations_financieres</code>.</li>
          <li>Les actions de paiement détaillées (Stripe Connect, déclaration manuelle, Chorus Pro) sont disponibles dans la page facturation.</li>
          <li>Les factures Chorus Pro publiques apparaissent dans la facturation dédiée.</li>
        </ul>
      </div>
    </LayoutApp>
  );
}

function KPICard({
  titre, montant, icon: Icon, variant, subtitle, onClick,
}: {
  titre: string;
  montant: number;
  icon: typeof Banknote;
  variant: 'primary' | 'warning' | 'info';
  subtitle?: string;
  onClick?: () => void;
}) {
  const styles = {
    primary: 'border-primary/30 bg-primary/5 text-primary',
    warning: 'border-warning/30 bg-warning/5 text-warning',
    info: 'border-info/30 bg-info/5 text-info',
  } as const;
  const Component = onClick ? 'button' : 'div';
  return (
    <Component
      onClick={onClick}
      className={`rounded-2xl border-2 p-4 ${styles[variant]} ${onClick ? 'cursor-pointer hover:opacity-90 transition-opacity text-left' : ''}`}
    >
      <div className="flex items-center justify-between mb-2">
        <span className="text-xs font-semibold text-foreground">{titre}</span>
        <Icon className="h-4 w-4" />
      </div>
      <p className="text-2xl font-bold tabular-nums">{formatEur(montant)}</p>
      {subtitle && <p className="text-[11px] mt-1 opacity-80">{subtitle}</p>}
    </Component>
  );
}

function MissionNonPayeeCard({ mission, onVoir }: { mission: MissionNonPayee; onVoir: () => void }) {
  const jours = mission.jours_depuis_fin ?? differenceInDays(new Date(), new Date(mission.fin_le));
  const urgent = jours >= 30;
  return (
    <li className={`card-base ${urgent ? 'border-destructive/40 bg-destructive/5' : ''}`}>
      <div className="flex flex-col sm:flex-row sm:items-center gap-2 sm:justify-between">
        <div className="min-w-0 flex-1">
          <p className="text-sm font-medium text-foreground truncate">{mission.intitule}</p>
          <p className="text-xs text-muted-foreground">
            {mission.soignant_nom} · {mission.soignant_profession}
            {mission.type_contrat_applique && ` · ${mission.type_contrat_applique}`}
          </p>
          <p className="text-[11px] text-muted-foreground mt-0.5">
            Terminée le {format(new Date(mission.fin_le), 'dd MMM yyyy', { locale: fr })}
            {jours > 0 && (
              <span className={urgent ? 'text-destructive font-semibold' : 'text-warning'}>
                {' '}— il y a {jours} jour{jours > 1 ? 's' : ''}
                {urgent && ' ⚠️ Retard important'}
              </span>
            )}
          </p>
          {mission.a_paiement_conteste && (
            <p className="text-[11px] text-destructive mt-0.5 inline-flex items-center gap-1">
              <AlertTriangle className="h-3 w-3" /> Paiement contesté par le soignant
            </p>
          )}
        </div>
        <div className="flex items-center gap-3 shrink-0">
          <div className="text-right">
            <p className="text-base font-bold text-foreground">{formatEur(mission.net_a_payer)}</p>
            <p className="text-[11px] text-muted-foreground">net soignant</p>
          </div>
          <button onClick={onVoir} className="btn-secondary text-xs py-1.5 px-3 whitespace-nowrap">
            Régler
          </button>
        </div>
      </div>
    </li>
  );
}

function formatEur(v: number): string {
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR', maximumFractionDigits: 2 }).format(v ?? 0);
}
