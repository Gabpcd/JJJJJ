import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { AlertTriangle, Banknote, FileText, Building2, Users, Loader2, ExternalLink } from 'lucide-react';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { format, differenceInDays } from 'date-fns';
import { fr } from 'date-fns/locale';
import { EmptyState } from '@/components/ui/EmptyState';
import { TableOuCartes, type ColonneTableau } from '@/components/ui/TableOuCartes';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';

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
/* Session C : contenu embarqué comme onglet « Obligations » de
   /etablissement/facturation (l'ancienne page /etablissement/obligations
   redirige). */
export function ObligationsFinancieresContent() {
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

  if (loading) return <ChargementPage />;
  if (!obligations) {
    return <p className="text-muted-foreground">Données non disponibles.</p>;
  }

  const totalDu = Number(obligations.total_du ?? 0);
  const totalSoignants = Number(obligations.total_soignants_du ?? 0);
  const totalCommissions = Number(obligations.total_commissions_du ?? 0);

  return (
    <div>
      <p className="text-sm text-muted-foreground mb-4">
        Vue consolidée de vos dettes en attente : soignants à payer + commissions Jolene + factures publiques.
      </p>

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
          {(() => {
            const colonnes: ColonneTableau<MissionNonPayee>[] = [
              { cle: 'mission', titre: 'Mission' },
              { cle: 'soignant', titre: 'Soignant' },
              { cle: 'fin', titre: 'Fin mission' },
              { cle: 'retard', titre: 'Retard' },
              { cle: 'montant', titre: 'Net à payer', align: 'right' },
              { cle: 'actions', titre: '', align: 'right', largeur: 'w-28' },
            ];
            return (
              <TableOuCartes
                colonnes={colonnes}
                donnees={missionsNonPayees}
                getId={(m) => m.mission_id}
                onClickLigne={(m) => navigate(`/etablissement/missions/${m.mission_id}`)}
                etatVide={
                  <EmptyState
                    icone={<Users />}
                    mascotte="happy"
                    titre="Aucune mission en attente de paiement"
                    description="Toutes vos missions terminées ont été réglées."
                    variant="success"
                    compact
                  />
                }
                renduCellule={(m, col) => {
                  const jours = m.jours_depuis_fin ?? differenceInDays(new Date(), new Date(m.fin_le));
                  const urgent = jours >= 30;
                  switch (col.cle) {
                    case 'mission':
                      return (
                        <div>
                          <p className="font-medium text-foreground line-clamp-1" title={m.intitule}>{m.intitule}</p>
                          {m.a_paiement_conteste && (
                            <span className="text-[10px] text-destructive inline-flex items-center gap-0.5">
                              <AlertTriangle className="h-3 w-3" /> Paiement contesté
                            </span>
                          )}
                        </div>
                      );
                    case 'soignant':
                      return (
                        <div>
                          <p className="text-sm">{m.soignant_nom}</p>
                          <p className="text-xs text-muted-foreground">{m.soignant_profession}{m.type_contrat_applique && ` · ${m.type_contrat_applique}`}</p>
                        </div>
                      );
                    case 'fin':
                      return <span className="text-xs whitespace-nowrap">{format(new Date(m.fin_le), 'dd MMM yyyy', { locale: fr })}</span>;
                    case 'retard':
                      return jours > 0
                        ? <span className={`text-xs font-medium ${urgent ? 'text-destructive' : 'text-warning'}`}>{jours}j{urgent && <AlertTriangle className="inline-block h-3 w-3 ml-0.5 align-text-bottom" aria-hidden="true" />}</span>
                        : <span className="text-xs text-muted-foreground">—</span>;
                    case 'montant':
                      return <span className="font-bold text-foreground tabular-nums">{formatEur(m.net_a_payer)}</span>;
                    case 'actions':
                      return (
                        <BoutonY2K size="sm" variant="primary" className="h-8 text-xs" onClick={(e) => { e.stopPropagation(); navigate(`/etablissement/missions/${m.mission_id}`); }}>
                          Régler
                        </BoutonY2K>
                      );
                    default:
                      return null;
                  }
                }}
                renduCarte={(m) => (
                  <MissionNonPayeeCardContent
                    mission={m}
                    onVoir={() => navigate(`/etablissement/missions/${m.mission_id}`)}
                  />
                )}
              />
            );
          })()}
        </section>
      )}

      {(filtre === 'TOUS' || filtre === 'SOIGNANTS') && paiementsEnAttente.length > 0 && (
        <section className="mb-6">
          <h2 className="text-lg font-bold text-foreground mb-3 flex items-center gap-2">
            <FileText className="h-5 w-5 text-warning" /> Paiements déclarés en attente de confirmation soignant
          </h2>
          {(() => {
            const colonnes: ColonneTableau<PaiementEnAttente>[] = [
              { cle: 'mission', titre: 'Mission' },
              { cle: 'soignant', titre: 'Soignant' },
              { cle: 'date', titre: 'Déclaré le' },
              { cle: 'montant', titre: 'Montant', align: 'right' },
              { cle: 'actions', titre: '', align: 'right', largeur: 'w-24' },
            ];
            return (
              <TableOuCartes
                colonnes={colonnes}
                donnees={paiementsEnAttente}
                getId={(p) => p.paiement_id}
                onClickLigne={(p) => navigate(`/etablissement/missions/${p.mission_id}`)}
                renduCellule={(p, col) => {
                  switch (col.cle) {
                    case 'mission':
                      return <span className="font-medium text-foreground line-clamp-1" title={p.mission_intitule}>{p.mission_intitule}</span>;
                    case 'soignant':
                      return <span className="text-sm">{p.soignant_nom}{p.soignant_profession ? ` · ${p.soignant_profession}` : ''}</span>;
                    case 'date':
                      return p.date_paiement
                        ? <span className="text-xs whitespace-nowrap">{format(new Date(p.date_paiement), 'dd MMM yyyy', { locale: fr })}</span>
                        : <span className="text-xs text-muted-foreground">—</span>;
                    case 'montant':
                      return <span className="text-base font-bold text-warning tabular-nums">{formatEur(p.montant_net)}</span>;
                    case 'actions':
                      return (
                        <BoutonY2K size="sm" variant="secondary" className="h-8 text-xs" onClick={(e) => { e.stopPropagation(); navigate(`/etablissement/missions/${p.mission_id}`); }}>
                          Voir
                        </BoutonY2K>
                      );
                    default:
                      return null;
                  }
                }}
                renduCarte={(p) => (
                  <div className="space-y-2">
                    <div className="flex items-start justify-between gap-2">
                      <div className="min-w-0 flex-1">
                        <p className="text-sm font-medium text-foreground line-clamp-1" title={p.mission_intitule}>{p.mission_intitule}</p>
                        <p className="text-xs text-muted-foreground">{p.soignant_nom}{p.soignant_profession ? ` · ${p.soignant_profession}` : ''}</p>
                        {p.date_paiement && (
                          <p className="text-[11px] text-muted-foreground">
                            Déclaré le {format(new Date(p.date_paiement), 'dd MMM yyyy', { locale: fr })}
                          </p>
                        )}
                      </div>
                      <span className="text-base font-bold text-warning tabular-nums shrink-0">{formatEur(p.montant_net)}</span>
                    </div>
                    <BoutonY2K
                      size="sm"
                      variant="primary"
                      className="w-full min-h-[44px]"
                      onClick={(e) => { e.stopPropagation(); navigate(`/etablissement/missions/${p.mission_id}`); }}
                    >
                      Voir la mission
                    </BoutonY2K>
                  </div>
                )}
              />
            );
          })()}
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
              mascotte="happy"
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
        <p className="font-semibold text-foreground mb-1">À propos de cet onglet</p>
        <ul className="list-disc list-inside space-y-1">
          <li>Vue consolidée et actualisée en temps réel de tout ce qui reste à régler.</li>
          <li>Les actions de paiement (carte, virement, Chorus Pro) se font depuis l'onglet Facturation.</li>
        </ul>
      </div>
    </div>
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

function MissionNonPayeeCardContent({ mission, onVoir }: { mission: MissionNonPayee; onVoir: () => void }) {
  const jours = mission.jours_depuis_fin ?? differenceInDays(new Date(), new Date(mission.fin_le));
  const urgent = jours >= 30;
  return (
    <div className={`space-y-2 ${urgent ? '-m-4 p-4 border-2 border-destructive/40 bg-destructive/5 rounded-lg' : ''}`}>
      <div className="flex flex-col gap-2">
        <div className="min-w-0 flex-1">
          <p className="text-sm font-medium text-foreground line-clamp-2">{mission.intitule}</p>
          <p className="text-xs text-muted-foreground">
            {mission.soignant_nom} · {mission.soignant_profession}
            {mission.type_contrat_applique && ` · ${mission.type_contrat_applique}`}
          </p>
          <p className="text-[11px] text-muted-foreground mt-0.5">
            Terminée le {format(new Date(mission.fin_le), 'dd MMM yyyy', { locale: fr })}
            {jours > 0 && (
              <span className={urgent ? 'text-destructive font-semibold' : 'text-warning'}>
                {' '}— il y a {jours} jour{jours > 1 ? 's' : ''}
                {urgent && <> <AlertTriangle className="inline-block h-3 w-3 align-text-bottom" aria-hidden="true" /> Retard important</>}
              </span>
            )}
          </p>
          {mission.a_paiement_conteste && (
            <p className="text-[11px] text-destructive mt-0.5 inline-flex items-center gap-1">
              <AlertTriangle className="h-3 w-3" /> Paiement contesté par le soignant
            </p>
          )}
        </div>
        <div className="flex items-center justify-between gap-3 pt-2 border-t border-border">
          <div>
            <p className="text-base font-bold text-foreground tabular-nums">{formatEur(mission.net_a_payer)}</p>
            <p className="text-[11px] text-muted-foreground">net soignant</p>
          </div>
          <BoutonY2K size="sm" variant="primary" className="min-h-[44px]" onClick={(e) => { e.stopPropagation(); onVoir(); }}>
            Régler
          </BoutonY2K>
        </div>
      </div>
    </div>
  );
}

function formatEur(v: number): string {
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR', maximumFractionDigits: 2 }).format(v ?? 0);
}
