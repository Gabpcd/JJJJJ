import React, { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useNavigate, useParams } from 'react-router-dom';
import { ArrowLeft, Printer, CreditCard, Loader2, CheckCircle, Clock, Download, ChevronDown, ChevronRight, AlertTriangle, RefreshCw } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { StripeEmbeddedCheckout } from '@/components/StripeEmbeddedCheckout';
import { PaiementVirement } from '@/components/PaiementVirement';
import { format, differenceInMinutes } from 'date-fns';
import { fr } from 'date-fns/locale';
import { ENTREPRISE } from '@/constantes/entreprise';
import { capturerErreurSentry } from '@/lib/sentry';
import { logger } from '@/lib/logger';
import { telechargerFactureCommissionPDF } from '@/lib/facture-commission-pdf';
import { useEtabPermissions } from '@/hooks/useEtabPermissions';
import { normaliserLignesFactureCommission } from '@/lib/factureCommissionUi';

const STATUT_COLORS: Record<string, string> = {
  BROUILLON: 'bg-muted text-muted-foreground',
  EMISE: 'bg-primary/10 text-primary',
  VIREMENT_DECLARE: 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400',
  PAYEE: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
  EN_RETARD: 'bg-destructive/10 text-destructive',
  ANNULEE: 'bg-muted text-muted-foreground line-through',
};

const STATUT_LABELS: Record<string, string> = {
  BROUILLON: 'Brouillon',
  EMISE: 'Émise',
  VIREMENT_DECLARE: 'Virement déclaré 🔍',
  PAYEE: 'Payée',
  EN_RETARD: 'En retard',
  ANNULEE: 'Annulée',
};

const MODE_LABELS: Record<string, string> = {
  STRIPE: 'Carte bancaire',
  VIREMENT: 'Virement bancaire',
  SEPA: 'Prélèvement SEPA',
};

const formatEur = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);

const formatHeure = (d: string) => format(new Date(d), 'HH:mm', { locale: fr });
const formatDateCourte = (d: string) => format(new Date(d), 'EEEE dd/MM/yyyy', { locale: fr });

function dureeEntre(debut: string, fin: string): string {
  const mins = differenceInMinutes(new Date(fin), new Date(debut));
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  return m > 0 ? `${h}h${String(m).padStart(2, '0')}` : `${h}h`;
}

function formatTauxPourcent(taux: unknown): string {
  const valeur = Number(taux ?? 0);
  const pourcent = valeur > 0 && valeur <= 1 ? valeur * 100 : valeur;
  return new Intl.NumberFormat('fr-FR', { maximumFractionDigits: 2 }).format(pourcent);
}

/** Groupe les pointages par jour (gère les pauses entre shifts sur une même journée) */
function PresencesJour({ presences }: { presences: any[] }) {
  if (!presences || presences.length === 0) {
    return <p className="text-xs text-muted-foreground italic py-1">Aucun pointage enregistré</p>;
  }

  const parJour: Record<string, any[]> = {};
  presences.forEach(p => {
    const jour = p.pointage_arrivee_le
      ? format(new Date(p.pointage_arrivee_le), 'yyyy-MM-dd')
      : 'inconnu';
    if (!parJour[jour]) parJour[jour] = [];
    parJour[jour].push(p);
  });

  return (
    <div className="space-y-1">
      {Object.entries(parJour).sort().map(([jour, pList]) => (
        <div key={jour} className="flex flex-wrap items-center gap-x-4 gap-y-0.5 text-xs">
          <span className="font-medium text-foreground w-36 capitalize">
            {jour !== 'inconnu' ? formatDateCourte(jour + 'T00:00:00') : '—'}
          </span>
          {pList.map((p) => (
            <span key={p.id} className="text-muted-foreground">
              {p.pointage_arrivee_le ? formatHeure(p.pointage_arrivee_le) : '?'}
              {' → '}
              {p.pointage_depart_le ? formatHeure(p.pointage_depart_le) : '?'}
              {p.pointage_arrivee_le && p.pointage_depart_le && (
                <span className="text-foreground font-medium ml-1">
                  ({dureeEntre(p.pointage_arrivee_le, p.pointage_depart_le)})
                </span>
              )}
              {p.methode_pointage_arrivee && (
                <span className="ml-1 text-[10px] text-muted-foreground/70">
                  [{p.methode_pointage_arrivee}]
                </span>
              )}
              {p.valide_par_etablissement && (
                <CheckCircle className="inline h-3 w-3 ml-0.5 text-green-600" />
              )}
            </span>
          ))}
          {pList.length > 1 && (
            <span className="text-[10px] text-primary font-medium">(pauses entre segments)</span>
          )}
        </div>
      ))}
    </div>
  );
}

/** Carte mission dépliable avec décomposition financière détaillée et pointages */
function MissionDetail({ mission }: { mission: any }) {
  const [open, setOpen] = useState(false);
  const presences = mission.presences || [];

  return (
    <div className="border border-border/60 rounded-lg overflow-hidden mb-3">
      <button
        type="button"
        onClick={() => setOpen(!open)}
        className="w-full flex items-center justify-between p-3 hover:bg-muted/30 transition-colors text-left"
        aria-expanded={open}
      >
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            {open ? (
              <ChevronDown className="h-4 w-4 text-muted-foreground shrink-0" />
            ) : (
              <ChevronRight className="h-4 w-4 text-muted-foreground shrink-0" />
            )}
            <span className="font-semibold text-foreground text-sm">{mission.intitule}</span>
            {mission.soignant_nom && (
              <span className="text-xs text-muted-foreground">· {mission.soignant_nom}</span>
            )}
          </div>
          <div className="flex flex-wrap gap-x-3 gap-y-0.5 text-xs text-muted-foreground mt-1 ml-6">
            {mission.profession && <span>{mission.profession}</span>}
            {mission.service && <span>· {mission.service}</span>}
            <span>
              {mission.debut_le ? format(new Date(mission.debut_le), 'dd/MM/yyyy', { locale: fr }) : '—'}
              {' → '}
              {mission.fin_le ? format(new Date(mission.fin_le), 'dd/MM/yyyy', { locale: fr }) : '—'}
            </span>
            <span>{Number(mission.duree_heures ?? 0)} h retenues</span>
          </div>
        </div>
        <div className="text-right shrink-0 ml-3">
          <p className="text-sm font-bold text-primary">{formatEur(mission.montant_commission_ht ?? 0)}</p>
          <p className="text-[10px] text-muted-foreground">commission HT</p>
        </div>
      </button>

      {open && (
        <div className="border-t border-border/60 bg-muted/20 p-4 space-y-4">
          {mission.ecart_avec_mission_courante && (
            <div className="rounded-lg border border-amber-300/60 bg-amber-50 px-3 py-2 text-xs text-amber-900 dark:border-amber-700/50 dark:bg-amber-950/30 dark:text-amber-100">
              Cette ligne reprend les montants figés sur la facture. La mission a été recalculée après son émission ; les anciennes valeurs de simulation ne sont pas utilisées ici.
            </div>
          )}
          {/* Décomposition financière */}
          {!mission.ecart_avec_mission_courante && <div>
            <h4 className="text-xs font-bold text-foreground mb-2 uppercase tracking-wider">
              💶 Décomposition financière
            </h4>
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-x-6 gap-y-1.5 text-xs">
              <div className="flex justify-between">
                <span className="text-muted-foreground">Taux retenu</span>
                <span className="font-medium">{formatEur(mission.taux_rist_plafonne ?? mission.taux_horaire_base ?? 0)}/h</span>
              </div>
              {mission.rist_plafond_applique && mission.taux_rist_plafonne != null && (
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Taux demandé</span>
                  <span className="font-medium">{formatEur(mission.taux_horaire_base ?? 0)}/h</span>
                </div>
              )}
              <div className="flex justify-between">
                <span className="text-muted-foreground">Heures retenues</span>
                <span className="font-medium">{Number(mission.duree_heures ?? 0)} h</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Brut soignant</span>
                <span className="font-medium">{formatEur(mission.total_brut ?? 0)}</span>
              </div>
              {Number(mission.montant_majoration_nuit ?? 0) > 0 && (
                <div className="flex justify-between">
                  <span className="text-muted-foreground">🌙 Majoration nuit</span>
                  <span className="font-medium">{formatEur(mission.montant_majoration_nuit)}</span>
                </div>
              )}
              {Number(mission.montant_majoration_dimanche ?? 0) > 0 && (
                <div className="flex justify-between">
                  <span className="text-muted-foreground">☀️ Majoration dimanche</span>
                  <span className="font-medium">{formatEur(mission.montant_majoration_dimanche)}</span>
                </div>
              )}
              {Number(mission.montant_majoration_ferie ?? 0) > 0 && (
                <div className="flex justify-between">
                  <span className="text-muted-foreground">🎌 Majoration férié</span>
                  <span className="font-medium">{formatEur(mission.montant_majoration_ferie)}</span>
                </div>
              )}
              {Number(mission.montant_ifm ?? 0) > 0 && (
                <div className="flex justify-between">
                  <span className="text-muted-foreground">IFM ({formatTauxPourcent(mission.taux_ifm)}%)</span>
                  <span className="font-medium">{formatEur(mission.montant_ifm)}</span>
                </div>
              )}
              {Number(mission.montant_icp ?? 0) > 0 && (
                <div className="flex justify-between">
                  <span className="text-muted-foreground">ICP ({formatTauxPourcent(mission.taux_icp)}%)</span>
                  <span className="font-medium">{formatEur(mission.montant_icp)}</span>
                </div>
              )}
            </div>
          </div>}

          {/* Commission Jolene */}
          <div>
            <h4 className="text-xs font-bold text-foreground mb-2 uppercase tracking-wider">
              🏷️ Commission Jolene
            </h4>
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-x-6 gap-y-1.5 text-xs">
              <div className="flex justify-between">
                <span className="text-muted-foreground">Taux HT</span>
                <span className="font-medium">{Number(mission.taux_commission ?? 15)}%</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Com. HT</span>
                <span className="font-semibold text-primary">{formatEur(mission.montant_commission_ht ?? 0)}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">TVA</span>
                <span className="font-medium">{formatEur(mission.montant_commission_tva ?? 0)}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Com. TTC</span>
                <span className="font-bold text-foreground">{formatEur(mission.montant_commission_ttc ?? 0)}</span>
              </div>
            </div>
          </div>

          {/* Pointages détaillés */}
          <div>
            <h4 className="text-xs font-bold text-foreground mb-2 uppercase tracking-wider">
              ⏱️ Pointages détaillés
            </h4>
            <PresencesJour presences={presences} />
          </div>
        </div>
      )}
    </div>
  );
}

export default function DetailFacture() {
  usePageTitle('Détail facture');
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const {
    user,
    etablissementId,
    loading: scopeLoading,
    resolved: scopeResolved,
    error: scopeError,
    retry: retryScope,
  } = useEtablissementScope();
  const permissionCheckEnabled = Boolean(
    !scopeLoading && scopeResolved && !scopeError && user && etablissementId,
  );
  const {
    loading: permissionsLoading,
    permissions,
    error: permissionsError,
    recharger: rechargerPermissions,
  } = useEtabPermissions(etablissementId ?? undefined, permissionCheckEnabled);
  const canReadFinance = permissions.lecture_paiement || permissions.paiement;
  const canManagePayments = permissions.paiement;
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [facture, setFacture] = useState<any>(null);
  const [missions, setMissions] = useState<any[]>([]);
  const [etab, setEtab] = useState<any>(null);
  const [showCheckout, setShowCheckout] = useState(false);
  const [generatingPdf, setGeneratingPdf] = useState(false);
  const [erreurChargement, setErreurChargement] = useState<string | null>(null);
  const requeteCourante = useRef(0);
  const missionsFacturees = useMemo(
    () => facture ? normaliserLignesFactureCommission(missions, facture) : [],
    [facture, missions],
  );

  const charger = useCallback(async () => {
    if (scopeLoading || !scopeResolved || scopeError || permissionsLoading) return;
    if (!user || !id || !etablissementId || !canReadFinance) {
      setLoading(false);
      return;
    }
    const numeroRequete = ++requeteCourante.current;
    setLoading(true);
    setErreurChargement(null);
    setFacture(null);
    setMissions([]);
    setEtab(null);

    try {
      const [resDetail, resE] = await Promise.all([
        supabase.rpc('fn_detail_facture' as any, { p_facture_id: id }),
        supabase.rpc('fn_mon_etablissement_complet' as any),
      ]);
      if (numeroRequete !== requeteCourante.current) return;
      if (resDetail.error) throw resDetail.error;
      if (resE.error) throw resE.error;
      if ((resDetail.data as any)?.error) throw new Error((resDetail.data as any).error);
      if ((resE.data as any)?.error) throw new Error((resE.data as any).error);

      let detail = resDetail.data as any;
      if (typeof detail === 'string') {
        try { detail = JSON.parse(detail); } catch { throw new Error('Réponse facture invalide'); }
      }
      if (Array.isArray(detail) && detail.length === 1) detail = detail[0];
      if (!detail?.facture || !Array.isArray(detail?.missions) || !resE.data) {
        logger.warn('[DetailFacture] réponse incomplète', detail ? Object.keys(detail) : 'null');
        throw new Error('Réponse facture incomplète');
      }

      setFacture(detail.facture);
      setMissions(detail.missions);
      setEtab(resE.data);
    } catch (error) {
      if (numeroRequete !== requeteCourante.current) return;
      capturerErreurSentry(error, 'DetailFacture', 'charger');
      setFacture(null);
      setMissions([]);
      setEtab(null);
      setErreurChargement('Impossible de charger cette facture en toute sécurité.');
    } finally {
      if (numeroRequete === requeteCourante.current) setLoading(false);
    }
  }, [
    canReadFinance,
    etablissementId,
    id,
    permissionsLoading,
    scopeError,
    scopeLoading,
    scopeResolved,
    user,
  ]);

  useEffect(() => {
    void charger();
    return () => { requeteCourante.current += 1; };
  }, [charger]);

  const genererPDF = async () => {
    if (!facture) return;
    setGeneratingPdf(true);
    try {
      await telechargerFactureCommissionPDF(facture.id);
    } catch (err) {
      capturerErreurSentry(err, 'DetailFacture', 'generer_pdf');
      afficherNotification({ type: 'erreur', message: 'Erreur lors de la génération du PDF' });
    } finally {
      setGeneratingPdf(false);
    }
  };

  if (
    scopeLoading
    || (!scopeResolved && !scopeError)
    || (permissionCheckEnabled && permissionsLoading)
    || loading
  ) {
    return <LayoutApp role="ADMIN_ETABLISSEMENT"><ChargementPage /></LayoutApp>;
  }
  if (scopeError || !scopeResolved || !user || !etablissementId) {
    return (
      <LayoutApp role="ADMIN_ETABLISSEMENT">
        <div className="card-base max-w-xl mx-auto text-center space-y-4" role="alert">
          <AlertTriangle className="h-10 w-10 text-destructive mx-auto" />
          <h1 className="text-xl font-bold">Facture indisponible</h1>
          <p className="text-sm text-muted-foreground">Impossible de vérifier votre établissement.</p>
          <button type="button" onClick={retryScope} className="btn-primary text-sm inline-flex items-center gap-2">
            <RefreshCw className="h-4 w-4" /> Réessayer
          </button>
        </div>
      </LayoutApp>
    );
  }
  if (permissionsError || !canReadFinance) {
    return (
      <LayoutApp role="ADMIN_ETABLISSEMENT">
        <div className="card-base max-w-xl mx-auto text-center space-y-4" role="alert">
          <AlertTriangle className="h-10 w-10 text-destructive mx-auto" />
          <h1 className="text-xl font-bold">Accès à la facture refusé</h1>
          <p className="text-sm text-muted-foreground">
            Votre rôle ne dispose pas de la permission de lecture des paiements.
          </p>
          {permissionsError && (
            <button type="button" onClick={() => void rechargerPermissions()} className="btn-primary text-sm inline-flex items-center gap-2">
              <RefreshCw className="h-4 w-4" /> Réessayer
            </button>
          )}
        </div>
      </LayoutApp>
    );
  }
  if (erreurChargement) {
    return (
      <LayoutApp role="ADMIN_ETABLISSEMENT">
        <div className="card-base max-w-xl mx-auto text-center space-y-4" role="alert">
          <AlertTriangle className="h-10 w-10 text-destructive mx-auto" />
          <h1 className="text-xl font-bold">Facture indisponible</h1>
          <p className="text-sm text-muted-foreground">{erreurChargement}</p>
          <button type="button" onClick={() => void charger()} className="btn-primary text-sm inline-flex items-center gap-2">
            <RefreshCw className="h-4 w-4" /> Réessayer
          </button>
        </div>
      </LayoutApp>
    );
  }
  if (!facture) return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <p className="text-center text-muted-foreground py-12">Facture introuvable.</p>
    </LayoutApp>
  );

  const estSepaAutomatique = etab?.mode_paiement_commission === 'SEPA_DEBIT';
  const canPay = canManagePayments
    && (facture.statut === 'EMISE' || facture.statut === 'EN_RETARD')
    && !facture.est_secteur_public
    && !estSepaAutomatique;
  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      {/* Header */}
      <div className="flex items-center justify-between mb-6 no-print">
        <button onClick={() => window.history.length > 2 ? navigate(-1) : navigate('/etablissement/facturation')} className="app-inline-back flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground transition-colors">
          <ArrowLeft className="h-4 w-4" /> Retour
        </button>
        <div className="flex flex-wrap gap-2">
          <button onClick={async () => { await genererPDF(); }} disabled={generatingPdf} className="btn-secondary text-sm flex items-center gap-1.5 disabled:opacity-50">
            {generatingPdf ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />}
            PDF
          </button>
          <button onClick={() => window.print()} className="btn-secondary text-sm flex items-center gap-1.5">
            <Printer className="h-4 w-4" /> Imprimer
          </button>
          {canPay && (
            <button onClick={() => setShowCheckout(true)} className="btn-primary text-sm flex items-center gap-1.5">
              <CreditCard className="h-4 w-4" /> Payer
            </button>
          )}
        </div>
      </div>

      {/* Invoice card */}
      <div className="card-base print-invoice print-full">
        {/* Header facture */}
        <div className="flex flex-col sm:flex-row justify-between gap-4 mb-6 pb-4 border-b border-border">
          <div>
            <h1 className="text-2xl font-black text-foreground">FACTURE</h1>
            <p className="text-lg font-bold text-primary mt-1">{facture.numero_facture}</p>
            <p className="text-sm text-muted-foreground mt-2">
              Émise le {facture.date_emission ? format(new Date(facture.date_emission), 'dd MMMM yyyy', { locale: fr }) : '—'}
            </p>
            {facture.date_echeance && (
              <p className="text-sm text-muted-foreground">
                Échéance : {format(new Date(facture.date_echeance), 'dd MMMM yyyy', { locale: fr })}
              </p>
            )}
            {facture.mode_paiement && (
              <p className="text-xs text-muted-foreground mt-1">
                Mode : {MODE_LABELS[facture.mode_paiement] ?? facture.mode_paiement}
              </p>
            )}
          </div>
          <div className="text-right">
            <p className="text-sm font-bold text-foreground">{ENTREPRISE.nom}</p>
            <p className="text-xs text-muted-foreground">Plateforme de mise en relation</p>
            <p className="text-xs text-muted-foreground mt-2">Facturé à :</p>
            <p className="text-sm font-semibold text-foreground">{etab?.nom}</p>
            <p className="text-xs text-muted-foreground">{etab?.adresse_rue || ''}</p>
            <p className="text-xs text-muted-foreground">{etab?.adresse_code_postal || ''} {etab?.adresse_ville || ''}</p>
            <p className="text-xs text-muted-foreground">SIRET : {etab?.siret}</p>
          </div>
        </div>

        {/* Status */}
        <div className="mb-6 flex items-center gap-2">
          <span className="text-sm text-muted-foreground">Statut :</span>
          <span className={`px-3 py-1 rounded-full text-xs font-bold ${STATUT_COLORS[facture.statut] ?? STATUT_COLORS.BROUILLON}`}>
            {STATUT_LABELS[facture.statut] ?? facture.statut}
          </span>
        </div>

        {facture.statut === 'VIREMENT_DECLARE' && (
          <div className="mb-6 flex items-center gap-2 bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-700/30 rounded-xl p-3">
            <Clock className="h-4 w-4 text-amber-600 dark:text-amber-400 shrink-0" />
            <div>
              <p className="text-sm font-medium text-amber-700 dark:text-amber-300">Virement déclaré — en attente de vérification</p>
              {facture.virement_reference && (
                <p className="text-xs text-amber-600/80 dark:text-amber-400/80">Référence : {facture.virement_reference}</p>
              )}
            </div>
          </div>
        )}

        {/* Missions table */}
        <h2 className="text-sm font-bold text-foreground mb-3 uppercase tracking-wider">
          📋 Missions facturées ({missionsFacturees.length})
        </h2>

        {missionsFacturees.length === 0 ? (
          <p className="text-sm text-muted-foreground italic py-4">Aucune mission liée à cette facture.</p>
        ) : (
          <div className="mb-6">
            <div className="mb-3 rounded-lg border border-primary/20 bg-primary/5 px-3 py-2 text-xs text-muted-foreground">
              Les montants de commission affichés ci-dessous sont ceux du document émis. Toute correction ultérieure doit apparaître sur un avoir ou une facture complémentaire distincte.
            </div>
            <p className="text-xs text-muted-foreground mb-3">
              Cliquez sur une mission pour voir le détail complet (heures, majorations nuit/dimanche/férié, IFM, ICP, commission, pointages).
            </p>
            {missionsFacturees.map((m: any) => (
              <MissionDetail key={m.id} mission={m} />
            ))}
          </div>
        )}

        {/* Totals */}
        <div className="border-t-2 border-border pt-4 space-y-2 max-w-xs ml-auto">
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">Total commissions HT</span>
            <span className="font-medium text-foreground">{formatEur(facture.montant_ht ?? 0)}</span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">TVA ({facture.taux_tva ?? 20}%)</span>
            <span className="font-medium text-foreground">{formatEur(facture.montant_tva ?? 0)}</span>
          </div>
          <div className="flex justify-between text-lg font-bold border-t border-border pt-2">
            <span className="text-foreground">Total TTC</span>
            <span className="text-primary">{formatEur(facture.montant_ttc ?? 0)}</span>
          </div>
          {facture.mode_paiement && (
            <div className="flex justify-between text-xs pt-1">
              <span className="text-muted-foreground">Mode de paiement</span>
              <span className="text-foreground">{MODE_LABELS[facture.mode_paiement] ?? facture.mode_paiement}</span>
            </div>
          )}
        </div>

        {/* Payment info */}
        {facture.statut === 'PAYEE' && facture.date_paiement && (
          <div className="mt-6 flex items-center gap-2 bg-success/10 border border-success/20 rounded-xl p-3">
            <CheckCircle className="h-4 w-4 text-success shrink-0" />
            <p className="text-sm text-success">
              Payée le {format(new Date(facture.date_paiement), 'dd MMMM yyyy', { locale: fr })}
            </p>
          </div>
        )}

        {(facture.statut === 'EMISE' || facture.statut === 'EN_RETARD') && estSepaAutomatique && !facture.est_secteur_public && (
          <div className="mt-6 rounded-xl border border-primary/20 bg-primary/5 p-3 text-sm text-muted-foreground no-print">
            Prélèvement SEPA automatique programmé : aucune carte ni déclaration de virement n’est nécessaire.
          </div>
        )}

        {canPay && (
          <div className="mt-6 no-print">
            <PaiementVirement facture={facture} onUpdate={charger} />
          </div>
        )}

        <div className="mt-8 pt-4 border-t border-border text-[10px] text-muted-foreground text-center">
          <p>{ENTREPRISE.nom} — Plateforme de mise en relation soignants-établissements</p>
          <p>Facture détaillée — Commission sur missions terminées</p>
        </div>
      </div>

      {canManagePayments && showCheckout && facture && !estSepaAutomatique && !facture.est_secteur_public && (
        <StripeEmbeddedCheckout
          factureId={facture.id}
          open={showCheckout}
          onClose={() => setShowCheckout(false)}
          onComplete={() => { setShowCheckout(false); charger(); }}
        />
      )}
    </LayoutApp>
  );
}
