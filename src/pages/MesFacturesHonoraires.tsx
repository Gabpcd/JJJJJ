import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { FileText, Download, Loader2, CheckCircle, Clock, AlertTriangle, Info, Zap, X, MessageSquareWarning } from 'lucide-react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { EmptyState } from '@/components/ui/EmptyState';
import { TableOuCartes, type ColonneTableau } from '@/components/ui/TableOuCartes';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { ModalCessionCreance } from '@/components/ModalCessionCreance';
import { WizardOuvertureLitige } from '@/components/litige/WizardOuvertureLitige';
import { useAffacturageActif } from '@/hooks/useAffacturageActif';
import { telechargerFactureHonorairesPDF } from '@/lib/facture-honoraires-pdf';
import {
  enrichirFacturesHonoraires,
  factureEstAvoir,
  facturePdfDisponible,
  libelleStatutFacture,
  montantTtcSigneFacture,
  totalFacturesComptabilisables,
  totalFacturesEnAttente,
  totalFacturesPayees,
} from '@/lib/factureHonorairesUi';

const fmt = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(Number(v) || 0);

const STATUT_CONFIG: Record<string, { label: string; icon: JSX.Element; color: string }> = {
  BROUILLON: { label: 'Brouillon', icon: <Clock className="h-3 w-3" />, color: 'bg-muted text-muted-foreground' },
  EN_GENERATION: { label: 'Génération en cours', icon: <Clock className="h-3 w-3" />, color: 'bg-warning/10 text-warning' },
  EMISE: { label: 'Émise', icon: <FileText className="h-3 w-3" />, color: 'bg-primary/10 text-primary' },
  EN_ATTENTE_PAIEMENT: { label: 'En attente de paiement', icon: <Clock className="h-3 w-3" />, color: 'bg-warning/10 text-warning' },
  EN_RETARD: { label: 'En retard', icon: <AlertTriangle className="h-3 w-3" />, color: 'bg-destructive/10 text-destructive' },
  PAYEE: { label: 'Payée', icon: <CheckCircle className="h-3 w-3" />, color: 'bg-success/10 text-success' },
  FACTORISEE: { label: 'Avance reçue', icon: <CheckCircle className="h-3 w-3" />, color: 'bg-success/20 text-success' },
  ANNULEE: { label: 'Annulée', icon: <AlertTriangle className="h-3 w-3" />, color: 'bg-muted text-muted-foreground' },
  REMPLACEE: { label: 'Remplacée', icon: <Info className="h-3 w-3" />, color: 'bg-muted text-muted-foreground' },
  ERREUR_GENERATION: { label: 'Erreur de génération', icon: <AlertTriangle className="h-3 w-3" />, color: 'bg-destructive/10 text-destructive' },
  REMBOURSE: { label: 'Remboursée', icon: <Info className="h-3 w-3" />, color: 'bg-muted text-muted-foreground' },
};

function configStatut(statut: string | null | undefined) {
  return STATUT_CONFIG[statut ?? ''] ?? {
    label: libelleStatutFacture(statut),
    icon: <AlertTriangle className="h-3 w-3" />,
    color: 'bg-destructive/10 text-destructive',
  };
}

function etatVerificationDocument(facture: any) {
  if (facture.type_document !== 'FACTURE' || !facture.emise_le) return null;
  if (facture.statut_litige === 'EN_ATTENTE_LITIGE') {
    return {
      label: 'Correction en cours',
      color: 'text-warning',
      ouverte: false,
      litigeActif: true,
    };
  }
  if (facture.contestee_le) {
    return {
      label: 'Document déjà revu',
      color: 'text-muted-foreground',
      ouverte: false,
      litigeActif: false,
    };
  }
  if (facture.acceptee_explicitement_le) {
    const echeance = facture.verification_echeance_le
      ? new Date(facture.verification_echeance_le).getTime()
      : 0;
    return { label: 'Validée par vous', color: 'text-success', ouverte: echeance > Date.now(), litigeActif: false };
  }
  const echeance = facture.verification_echeance_le
    ? new Date(facture.verification_echeance_le).getTime()
    : 0;
  if (echeance > Date.now()) {
    return { label: 'À vérifier', color: 'text-warning', ouverte: true, litigeActif: false };
  }
  return { label: 'Acceptée après délai', color: 'text-muted-foreground', ouverte: false, litigeActif: false };
}

function libelleTvaDocument(facture: any): string {
  if (facture.regime_tva_snapshot === 'EXONERE_ART_261_4_1') return 'Soins exonérés de TVA';
  if (facture.regime_tva_snapshot === 'FRANCHISE_EN_BASE_ART_293_B') return 'TVA non applicable';
  if (facture.exoneration_tva === false || Number(facture.taux_tva) > 0) {
    return `TVA ${Number(facture.taux_tva || 0).toLocaleString('fr-FR')} %`;
  }
  return 'Régime TVA historique';
}

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
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [factures, setFactures] = useState<any[]>([]);
  const [mandatSigne, setMandatSigne] = useState(false);
  const [erreurChargement, setErreurChargement] = useState<string | null>(null);
  const [reloadKey, setReloadKey] = useState(0);

  useEffect(() => {
    if (!user) return;
    let actif = true;
    (async () => {
      setErreurChargement(null);
      try {
        const [
          { data: sgData, error: soignantError },
          { data: facts, error: facturesError },
          { data: metadonnees, error: metadonneesError },
        ] = await Promise.all([
          supabase.from('soignants').select('mandat_facturation_signe').eq('id', user.id).maybeSingle(),
          supabase.rpc('fn_mes_factures_honoraires' as any),
          supabase
            .from('factures_honoraires')
            .select('id, mission_id, type_document, montant_signe, montant_tva, taux_tva, exoneration_tva, regime_tva_snapshot, cree_le, template_version, numero_semaine_iso, periode_debut, periode_fin, facture_precedente_id, date_remboursement, emise_le, notifiee_soignant_le, verification_echeance_le, acceptee_explicitement_le, contestee_le, statut_litige')
            .eq('soignant_id', user.id),
        ]);
        if (soignantError) throw soignantError;
        if (facturesError) throw facturesError;
        // Le RPC de production ne renvoie pas encore type_document. Sans cette
        // lecture RLS, un AVOIR pourrait être pris pour une facture émise.
        if (metadonneesError) throw metadonneesError;
        if (!actif) return;
        setMandatSigne(!!sgData?.mandat_facturation_signe);
        setFactures(enrichirFacturesHonoraires(
          (facts as any[]) || [],
          (metadonnees as any[]) || [],
        ));
      } catch (error: any) {
        if (!actif) return;
        setErreurChargement(error?.message || 'Impossible de charger les factures.');
      } finally {
        if (actif) setLoading(false);
      }
    })();
    return () => { actif = false; };
  }, [user, reloadKey]);

  const [cessionModal, setCessionModal] = useState<{ id: string; numero: string; montant: number } | null>(null);
  const [factureLitige, setFactureLitige] = useState<{
    facture: any;
    initialType: 'PAIEMENT' | 'AUTRE';
  } | null>(null);
  const [acceptationEnCours, setAcceptationEnCours] = useState<string | null>(null);
  const [filtreStatut, setFiltreStatut] = useState<string>('tous');
  // Cession de créance / avance Defacto masquée tant que l'affacturage est off.
  const affacturageActif = useAffacturageActif();
  const [filtreAnnee, setFiltreAnnee] = useState<string>('toutes');
  const [filtreMois, setFiltreMois] = useState<string>('tous');
  const tentativesEchouees = useMemo(
    () => factures.filter((facture) => facture.statut === 'ERREUR_GENERATION'),
    [factures],
  );
  const facturesMetier = useMemo(
    () => factures.filter((facture) => facture.statut !== 'ERREUR_GENERATION'),
    [factures],
  );

  const anneesDisponibles = useMemo(() => {
    const annees = new Set<string>();
    facturesMetier.forEach(f => { if (f.date_emission) annees.add(String(new Date(f.date_emission).getFullYear())); });
    return Array.from(annees).sort((a, b) => b.localeCompare(a));
  }, [facturesMetier]);

  const facturesFiltrees = useMemo(() => {
    return facturesMetier.filter((f: any) => {
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
  }, [facturesMetier, filtreStatut, filtreAnnee, filtreMois]);

  const filtreActif = filtreStatut !== 'tous' || filtreAnnee !== 'toutes' || filtreMois !== 'tous';
  const reinitialiserFiltres = () => {
    setFiltreStatut('tous');
    setFiltreAnnee('toutes');
    setFiltreMois('tous');
  };

  const ouvrirCession = (facture: any) => {
    if (factureEstAvoir(facture)) return;
    setCessionModal({
      id: facture.id,
      numero: facture.numero_facture,
      montant: Number(facture.montant_ttc),
    });
  };

  const onCessionSuccess = () => {
    navigate('/soignant/mes-gains?tab=avances');
  };

  const accepterDocument = async (facture: any) => {
    setAcceptationEnCours(facture.id);
    const { data, error } = await supabase.rpc(
      'fn_accepter_document_facturation_honoraires' as any,
      { p_facture_id: facture.id },
    );
    setAcceptationEnCours(null);
    if (error || !(data as any)?.success) {
      afficherNotification({
        type: 'erreur',
        message: error?.message || (data as any)?.error || 'Impossible de valider ce document.',
      });
      return;
    }
    afficherNotification({ type: 'succes', message: 'Document validé. Merci !' });
    setLoading(true);
    setReloadKey((key) => key + 1);
  };

  const telechargerFacturePDF = telechargerFactureHonorairesPDF;

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20">
        <Loader2 className="h-8 w-8 animate-spin text-primary" />
      </div>
    );
  }

  const totalFacture = totalFacturesComptabilisables(facturesFiltrees);
  const totalPaye = totalFacturesPayees(facturesFiltrees);
  const totalAttente = totalFacturesEnAttente(facturesFiltrees);

  return (
    <>
      <div className="space-y-5">
        {erreurChargement && (
          <div className="rounded-xl border border-destructive/30 bg-destructive/5 p-4" role="alert">
            <p className="font-semibold text-destructive">Impossible de charger les factures</p>
            <p className="mt-1 text-sm text-muted-foreground">{erreurChargement}</p>
            <BoutonY2K size="sm" variant="secondary" className="mt-3" onClick={() => { setLoading(true); setReloadKey(key => key + 1); }}>
              Réessayer
            </BoutonY2K>
          </div>
        )}
        {!erreurChargement && !mandatSigne && (
          <div className="rounded-xl border-2 border-warning/30 bg-warning/5 p-4 flex items-start gap-3">
            <Info className="h-5 w-5 text-warning shrink-0 mt-0.5" />
            <div className="flex-1">
              <p className="font-semibold text-foreground">Mandat de facturation non signé</p>
              <p className="text-sm text-muted-foreground mt-0.5">
                Pour que Jolene puisse produire automatiquement tes factures d'honoraires,
                tu dois d'abord signer le mandat de facturation.
              </p>
              <BoutonY2K onClick={() => navigate('/soignant/mandat-facturation')} className="mt-3 gap-2" size="sm">
                Signer le mandat
              </BoutonY2K>
            </div>
          </div>
        )}

        {/* KPIs */}
        {tentativesEchouees.length > 0 && facturesMetier.length > 0 && (
          <div className="rounded-xl border border-info/20 bg-info/5 p-3 flex items-start gap-3" role="status">
            <Info className="h-4 w-4 text-info shrink-0 mt-0.5" />
            <p className="text-xs text-muted-foreground">
              {tentativesEchouees.length} tentative{tentativesEchouees.length > 1 ? 's techniques ont' : ' technique a'} échoué avant la création du document valide. Elles ne sont ni des factures, ni comptées dans les montants ci-dessous.
            </p>
          </div>
        )}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
          <div className="card-base">
            <p className="text-xs text-muted-foreground">Total net facturé</p>
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

        {facturesMetier.length > 0 && (
          <div className="card-base flex flex-wrap items-center gap-2 py-2.5">
            <span className="text-xs font-semibold text-muted-foreground mr-1">Filtres :</span>
            <select
              value={filtreStatut}
              onChange={e => setFiltreStatut(e.target.value)}
              className="text-xs border border-border rounded-md px-2 py-1 bg-background"
            >
              <option value="tous">Tous statuts</option>
              <option value="BROUILLON">Brouillon</option>
              <option value="EN_GENERATION">Génération en cours</option>
              <option value="EMISE">Émise</option>
              <option value="EN_ATTENTE_PAIEMENT">En attente de paiement</option>
              <option value="EN_RETARD">En retard</option>
              <option value="PAYEE">Payée</option>
              <option value="FACTORISEE">Avance reçue</option>
              <option value="ANNULEE">Annulée</option>
              <option value="REMPLACEE">Remplacée</option>
              <option value="REMBOURSE">Remboursée</option>
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
              {facturesFiltrees.length} / {facturesMetier.length} document{facturesMetier.length > 1 ? 's' : ''}
            </span>
          </div>
        )}

        {(() => {
          const etatVide = erreurChargement
            ? <></>
            : facturesMetier.length === 0
            ? <EmptyState
                icone={<FileText />}
                mascotte={mandatSigne ? 'empty' : 'thinking'}
                titre="Aucune facture d'honoraires pour le moment"
                description={mandatSigne
                  ? 'Les factures apparaîtront dès que tes missions seront terminées et validées.'
                  : "Signe d'abord le mandat de facturation pour commencer à recevoir des factures automatiques."}
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
            { cle: 'numero', titre: 'N° document' },
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
                const config = configStatut(f.statut);
                const estAvoir = factureEstAvoir(f);
                const peutTelecharger = facturePdfDisponible(f.statut);
                const verification = etatVerificationDocument(f);
                switch (col.cle) {
                  case 'numero':
                    return (
                      <span className="inline-flex flex-wrap items-center gap-1.5">
                        <span className="font-mono text-xs font-bold text-foreground">{f.numero_facture}</span>
                        {estAvoir && <span className="rounded bg-destructive/10 px-1.5 py-0.5 text-[9px] font-bold text-destructive">AVOIR</span>}
                      </span>
                    );
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
                    return <span className={`font-semibold tabular-nums ${estAvoir ? 'text-destructive' : 'text-foreground'}`}>{fmt(montantTtcSigneFacture(f))}</span>;
                  case 'statut':
                    return (
                      <div>
                        <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full inline-flex items-center gap-1 ${config.color}`}>
                          {config.icon} {config.label}
                        </span>
                        {verification && <p className={`mt-1 text-[10px] ${verification.color}`}>{verification.label}</p>}
                      </div>
                    );
                  case 'actions':
                    return (
                      <div className="flex flex-wrap items-center justify-end gap-1">
                        {verification?.ouverte && !f.acceptee_explicitement_le && (
                          <BoutonY2K
                            size="sm"
                            className="h-8 gap-1 text-xs"
                            disabled={acceptationEnCours === f.id}
                            onClick={(e) => { e.stopPropagation(); void accepterDocument(f); }}
                          >
                            {acceptationEnCours === f.id
                              ? <Loader2 className="h-3.5 w-3.5 animate-spin" />
                              : <CheckCircle className="h-3.5 w-3.5" />}
                            Valider
                          </BoutonY2K>
                        )}
                        {verification?.ouverte && f.mission_id && (
                          <BoutonY2K
                            size="sm"
                            variant="secondary"
                            className="h-8 gap-1 text-xs"
                            onClick={(e) => {
                              e.stopPropagation();
                              setFactureLitige({ facture: f, initialType: 'PAIEMENT' });
                            }}
                          >
                            <MessageSquareWarning className="h-3.5 w-3.5" /> Erreur
                          </BoutonY2K>
                        )}
                        {verification && !verification.ouverte && !verification.litigeActif && f.mission_id && (
                          <BoutonY2K
                            size="sm"
                            variant="secondary"
                            className="h-8 gap-1 text-xs"
                            onClick={(e) => {
                              e.stopPropagation();
                              setFactureLitige({ facture: f, initialType: 'AUTRE' });
                            }}
                          >
                            <MessageSquareWarning className="h-3.5 w-3.5" /> Revue
                          </BoutonY2K>
                        )}
                        {peutTelecharger && (
                          <BoutonY2K size="sm" variant="secondary" className="h-8 gap-1 text-xs" onClick={(e) => { e.stopPropagation(); telechargerFacturePDF(f.id); }}>
                            <Download className="h-3.5 w-3.5" /> PDF
                          </BoutonY2K>
                        )}
                        {affacturageActif && !estAvoir && (f.statut === 'EMISE' || f.statut === 'EN_RETARD') && (
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
                const config = configStatut(f.statut);
                const estAvoir = factureEstAvoir(f);
                const peutTelecharger = facturePdfDisponible(f.statut);
                const verification = etatVerificationDocument(f);
                return (
                  <div className="space-y-3">
                    <div className="flex items-start justify-between gap-3">
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 mb-1 flex-wrap">
                          <span className="font-mono text-xs font-bold text-foreground">{f.numero_facture}</span>
                          {estAvoir && <span className="rounded bg-destructive/10 px-1.5 py-0.5 text-[9px] font-bold text-destructive">AVOIR</span>}
                          <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full inline-flex items-center gap-1 ${config.color}`}>
                            {config.icon} {config.label}
                          </span>
                          {(!f.template_version || f.template_version === 'v1') && (
                            <span className="text-[9px] px-1.5 py-0.5 rounded bg-muted text-muted-foreground" title="Facture générée avant le format structuré PDF + XML CII">Format historique</span>
                          )}
                        </div>
                        <p className="text-sm text-foreground font-medium line-clamp-1" title={f.mission_intitule || undefined}>{f.mission_intitule || '—'}</p>
                        <p className="text-xs text-muted-foreground line-clamp-1" title={f.etablissement_nom}>{f.etablissement_nom}</p>
                        <p className="text-[10px] text-muted-foreground mt-1">
                          Émise le {f.date_emission ? format(new Date(f.date_emission), 'dd/MM/yyyy', { locale: fr }) : '—'}
                          {f.date_echeance && ` · Échéance ${format(new Date(f.date_echeance), 'dd/MM/yyyy', { locale: fr })}`}
                          {f.date_paiement && ` · Payée le ${format(new Date(f.date_paiement), 'dd/MM/yyyy', { locale: fr })}`}
                        </p>
                        {verification && (
                          <p className={`mt-1 text-[10px] font-medium ${verification.color}`}>
                            {verification.label}
                            {verification.ouverte && f.verification_echeance_le
                              ? ` jusqu'au ${format(new Date(f.verification_echeance_le), 'dd/MM à HH:mm', { locale: fr })}`
                              : ''}
                          </p>
                        )}
                      </div>
                      <div className="text-right shrink-0">
                        <p className={`text-lg font-bold tabular-nums ${estAvoir ? 'text-destructive' : 'text-foreground'}`}>{fmt(montantTtcSigneFacture(f))}</p>
                        <p className="text-[10px] text-muted-foreground">{libelleTvaDocument(f)}</p>
                      </div>
                    </div>
                    <div className="flex flex-wrap gap-2 pt-1">
                      {verification?.ouverte && !f.acceptee_explicitement_le && (
                        <BoutonY2K
                          size="sm"
                          className="gap-1.5 min-h-[44px]"
                          disabled={acceptationEnCours === f.id}
                          onClick={(e) => { e.stopPropagation(); void accepterDocument(f); }}
                        >
                          {acceptationEnCours === f.id
                            ? <Loader2 className="h-4 w-4 animate-spin" />
                            : <CheckCircle className="h-4 w-4" />}
                          Tout est correct
                        </BoutonY2K>
                      )}
                      {verification?.ouverte && f.mission_id && (
                        <BoutonY2K
                          size="sm"
                          variant="secondary"
                          className="gap-1.5 min-h-[44px]"
                          onClick={(e) => {
                            e.stopPropagation();
                            setFactureLitige({ facture: f, initialType: 'PAIEMENT' });
                          }}
                        >
                          <MessageSquareWarning className="h-4 w-4" /> Signaler une erreur
                        </BoutonY2K>
                      )}
                      {verification && !verification.ouverte && !verification.litigeActif && f.mission_id && (
                        <BoutonY2K
                          size="sm"
                          variant="secondary"
                          className="gap-1.5 min-h-[44px]"
                          onClick={(e) => {
                            e.stopPropagation();
                            setFactureLitige({ facture: f, initialType: 'AUTRE' });
                          }}
                        >
                          <MessageSquareWarning className="h-4 w-4" /> Demander une revue
                        </BoutonY2K>
                      )}
                      {peutTelecharger && (
                        <BoutonY2K
                          size="sm"
                          variant="primary"
                          className="flex-1 gap-1.5 min-h-[44px]"
                          onClick={(e) => { e.stopPropagation(); telechargerFacturePDF(f.id); }}
                        >
                          <Download className="h-4 w-4" /> Télécharger le PDF
                        </BoutonY2K>
                      )}
                      {affacturageActif && !estAvoir && (f.statut === 'EMISE' || f.statut === 'EN_RETARD') && (
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
      {factureLitige?.facture?.mission_id && (
        <WizardOuvertureLitige
          missionId={factureLitige.facture.mission_id}
          missionIntitule={factureLitige.facture.mission_intitule}
          factureHonorairesId={factureLitige.facture.id}
          initialType={factureLitige.initialType}
          onClose={() => setFactureLitige(null)}
          onSuccess={() => {
            setFactureLitige(null);
            setLoading(true);
            setReloadKey((key) => key + 1);
          }}
        />
      )}
    </>
  );
}
