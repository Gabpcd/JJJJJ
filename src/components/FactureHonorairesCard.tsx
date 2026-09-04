import { useEffect, useMemo, useState } from 'react';
import { FileText, Download, CheckCircle, Clock, AlertTriangle, Loader2, Info } from 'lucide-react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { supabase } from '@/integrations/supabase/client';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { telechargerFactureHonorairesPDF } from '@/lib/facture-honoraires-pdf';
import {
  factureEstAvoir,
  facturePdfDisponible,
  libelleStatutFacture,
  montantTtcSigneFacture,
  resumerFacturesMission,
  totalFacturesComptabilisables,
} from '@/lib/factureHonorairesUi';

interface Props {
  missionId: string;
  /** Contexte d'affichage — pour adapter le titre/ton. */
  viewerRole?: 'ETAB' | 'SOIGNANT' | 'ADMIN';
}

const fmt = (v: number) =>
  new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(Number(v) || 0);

function formaterDate(valeur: string | null | undefined): string {
  if (!valeur) return '—';
  const date = new Date(valeur);
  return Number.isNaN(date.getTime()) ? '—' : format(date, 'd MMM yyyy', { locale: fr });
}

const STATUT_CONFIG: Record<string, { label: string; Icon: typeof CheckCircle; colorClass: string }> = {
  BROUILLON: { label: 'Brouillon', Icon: Clock, colorClass: 'bg-muted text-muted-foreground' },
  EN_GENERATION: { label: 'Génération en cours', Icon: Clock, colorClass: 'bg-warning/10 text-warning border-warning/20' },
  EMISE: { label: 'Émise', Icon: FileText, colorClass: 'bg-primary/10 text-primary border-primary/20' },
  EN_ATTENTE_PAIEMENT: { label: 'En attente de paiement', Icon: Clock, colorClass: 'bg-warning/10 text-warning border-warning/20' },
  EN_RETARD: { label: 'En retard', Icon: AlertTriangle, colorClass: 'bg-destructive/10 text-destructive border-destructive/20' },
  PAYEE: { label: 'Payée', Icon: CheckCircle, colorClass: 'bg-success/10 text-success border-success/20' },
  FACTORISEE: { label: 'Avance reçue', Icon: CheckCircle, colorClass: 'bg-success/20 text-success border-success/30' },
  ANNULEE: { label: 'Annulée', Icon: AlertTriangle, colorClass: 'bg-muted text-muted-foreground' },
  REMPLACEE: { label: 'Remplacée', Icon: FileText, colorClass: 'bg-muted text-muted-foreground' },
  ERREUR_GENERATION: { label: 'Erreur de génération', Icon: AlertTriangle, colorClass: 'bg-destructive/10 text-destructive border-destructive/20' },
  REMBOURSE: { label: 'Remboursée', Icon: FileText, colorClass: 'bg-muted text-muted-foreground' },
};

function configStatut(statut: string | null | undefined) {
  return STATUT_CONFIG[statut ?? ''] ?? {
    label: libelleStatutFacture(statut),
    Icon: AlertTriangle,
    colorClass: 'bg-destructive/10 text-destructive border-destructive/20',
  };
}

export function FactureHonorairesCard({ missionId, viewerRole = 'ETAB' }: Props) {
  const [factures, setFactures] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [telechargementId, setTelechargementId] = useState<string | null>(null);
  const [erreurChargement, setErreurChargement] = useState<string | null>(null);
  const [erreurTelechargement, setErreurTelechargement] = useState<string | null>(null);
  const [reloadKey, setReloadKey] = useState(0);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      setFactures([]);
      setErreurChargement(null);
      setErreurTelechargement(null);
      const { data, error } = await supabase
        .from('factures_honoraires')
        .select('id, numero_facture, statut, montant_ht, montant_ttc, montant_signe, taux_tva, exoneration_tva, date_emission, date_echeance, date_paiement, date_remboursement, type_document, template_version, cree_le, periode_debut, periode_fin, numero_semaine_iso, annee_iso, est_facture_finale_mission')
        .eq('mission_id', missionId)
        .order('date_emission', { ascending: false })
        .order('cree_le', { ascending: false })
        .order('id', { ascending: false });
      if (!cancelled) {
        if (error) {
          setFactures([]);
          setErreurChargement(error.message || 'Impossible de charger les documents de facturation.');
        } else {
          // Une mission longue produit une facture par semaine : aucune ligne ne
          // doit être remplacée par une sélection arbitraire.
          setFactures((data as any[]) ?? []);
        }
        setLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, [missionId, reloadKey]);

  // ERREUR_GENERATION décrit une tentative technique, pas une pièce comptable.
  // Elle ne doit ni gonfler le compteur ni être présentée comme une facture.
  const facturesMetier = useMemo(
    () => factures.filter((facture) => facture.statut !== 'ERREUR_GENERATION'),
    [factures],
  );
  const nbTentativesEchouees = factures.length - facturesMetier.length;
  const resume = useMemo(() => resumerFacturesMission(facturesMetier), [facturesMetier]);
  const totalNetFacture = useMemo(() => totalFacturesComptabilisables(facturesMetier), [facturesMetier]);
  const nbAvoirs = useMemo(() => facturesMetier.filter(factureEstAvoir).length, [facturesMetier]);

  if (loading) {
    return (
      <div className="card-base flex items-center gap-2 text-xs text-muted-foreground" aria-busy="true">
        <Loader2 className="h-4 w-4 animate-spin text-primary" /> Chargement des documents de facturation…
      </div>
    );
  }
  if (erreurChargement) {
    return (
      <div className="card-base border-destructive/30 bg-destructive/5" role="alert">
        <p className="text-sm font-semibold text-destructive">Documents de facturation indisponibles</p>
        <p className="mt-1 text-xs text-muted-foreground">{erreurChargement}</p>
        <BoutonY2K
          size="sm"
          variant="secondary"
          className="mt-3"
          onClick={() => setReloadKey((valeur) => valeur + 1)}
        >
          Réessayer
        </BoutonY2K>
      </div>
    );
  }
  if (factures.length === 0) return null;

  if (facturesMetier.length === 0) {
    return (
      <div className="card-base border-warning/30 bg-warning/5" role="status">
        <div className="flex items-start gap-2">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-warning" />
          <div>
            <p className="text-sm font-semibold text-foreground">Document d’honoraires en attente</p>
            <p className="mt-1 text-xs text-muted-foreground">
              La génération technique n’a pas abouti. Aucun document ni montant n’est comptabilisé ; Jolene peut relancer l’émission sans créer de doublon.
            </p>
          </div>
        </div>
      </div>
    );
  }

  const handleDownload = async (factureId: string) => {
    setTelechargementId(factureId);
    setErreurTelechargement(null);
    try {
      await telechargerFactureHonorairesPDF(factureId);
    } catch (error) {
      setErreurTelechargement(
        error instanceof Error ? error.message : 'Impossible de télécharger ce document.',
      );
    } finally {
      setTelechargementId(null);
    }
  };

  const titre =
    viewerRole === 'SOIGNANT'
      ? 'Vos documents d’honoraires pour cette mission'
      : viewerRole === 'ADMIN'
      ? 'Documents d’honoraires du soignant'
      : 'Documents d’honoraires du soignant';

  return (
    <div className="card-base space-y-4">
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <FileText className="h-4 w-4 text-primary" />
          <h3 className="font-semibold text-foreground text-sm">{titre}</h3>
        </div>
        <span className="rounded-full border border-border bg-muted/50 px-2 py-0.5 text-[10px] font-bold text-muted-foreground">
          {facturesMetier.length} document{facturesMetier.length > 1 ? 's' : ''}
        </span>
      </div>

      <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
        <div className="rounded-lg bg-muted/40 p-2.5">
          <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Net facturé</p>
          <p className="font-bold tabular-nums text-foreground">{fmt(totalNetFacture)}</p>
        </div>
        <div className="rounded-lg bg-success/5 p-2.5">
          <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Payé</p>
          <p className="font-bold tabular-nums text-success">{fmt(resume.montantPaye)}</p>
        </div>
        <div className={`rounded-lg p-2.5 ${resume.nbEnRetard > 0 ? 'bg-destructive/5' : 'bg-warning/5'}`}>
          <p className="text-[10px] uppercase tracking-wide text-muted-foreground">
            En attente{resume.nbEnRetard > 0 ? ` · ${resume.nbEnRetard} en retard` : ''}
          </p>
          <p className={`font-bold tabular-nums ${resume.nbEnRetard > 0 ? 'text-destructive' : 'text-warning'}`}>
            {fmt(resume.montantEnAttente)}
          </p>
        </div>
      </div>

      {nbAvoirs > 0 && (
        <p className="rounded-lg border border-destructive/20 bg-destructive/5 px-3 py-2 text-xs text-destructive">
          {nbAvoirs} avoir{nbAvoirs > 1 ? 's' : ''} comptabilisé{nbAvoirs > 1 ? 's' : ''} en négatif dans le total net.
        </p>
      )}

      {nbTentativesEchouees > 0 && (
        <p className="flex items-start gap-2 rounded-lg border border-border bg-muted/30 px-3 py-2 text-xs text-muted-foreground" role="status">
          <Info className="mt-0.5 h-3.5 w-3.5 shrink-0" />
          <span>
            {nbTentativesEchouees === 1
              ? '1 tentative technique de génération a échoué puis a été écartée.'
              : `${nbTentativesEchouees} tentatives techniques de génération ont échoué puis ont été écartées.`}
            {' '}Elles ne sont ni des factures ni comptées dans les montants.
          </span>
        </p>
      )}

      {erreurTelechargement && (
        <p className="rounded-lg border border-destructive/20 bg-destructive/5 px-3 py-2 text-xs text-destructive" role="alert">
          {erreurTelechargement}
        </p>
      )}

      <div className="divide-y divide-border rounded-xl border border-border">
        {facturesMetier.map((facture) => {
          const config = configStatut(facture.statut);
          const StatutIcon = config.Icon;
          const estAvoir = factureEstAvoir(facture);
          const downloading = telechargementId === facture.id;
          const peutTelecharger = facturePdfDisponible(facture.statut);
          const periode = facture.numero_semaine_iso
            ? `Semaine ${facture.numero_semaine_iso}${facture.annee_iso ? `/${facture.annee_iso}` : ''}`
            : facture.est_facture_finale_mission === false
              ? 'Facture intermédiaire'
              : 'Facture finale';

          return (
            <div key={facture.id} className="space-y-2 p-3">
              <div className="flex flex-wrap items-start justify-between gap-2">
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-1.5">
                    <span className="font-mono text-xs font-semibold text-foreground">{facture.numero_facture}</span>
                    <span className={`rounded px-1.5 py-0.5 text-[9px] font-bold ${estAvoir ? 'bg-destructive/10 text-destructive' : 'bg-primary/10 text-primary'}`}>
                      {estAvoir ? 'AVOIR' : periode}
                    </span>
                    <span className={`inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[10px] font-bold ${config.colorClass}`}>
                      <StatutIcon className="h-3 w-3" /> {config.label}
                    </span>
                  </div>
                  <p className="mt-1 text-[10px] text-muted-foreground">
                    Émis le {formaterDate(facture.date_emission)}
                    {facture.periode_debut && facture.periode_fin && (
                      <> · Période du {formaterDate(facture.periode_debut)} au {formaterDate(facture.periode_fin)}</>
                    )}
                  </p>
                  <p className="text-[10px] text-muted-foreground">
                    {estAvoir
                      ? facture.date_remboursement
                        ? `Avoir remboursé le ${formaterDate(facture.date_remboursement)}`
                        : 'Avoir émis · régularisation distincte d’un paiement attendu'
                      : facture.date_paiement
                        ? `Payé le ${formaterDate(facture.date_paiement)}`
                        : facture.date_echeance
                          ? `Échéance ${formaterDate(facture.date_echeance)}`
                          : 'Aucune date d’échéance'}
                  </p>
                </div>
                <div className="text-right">
                  <p className={`font-bold tabular-nums ${estAvoir ? 'text-destructive' : 'text-foreground'}`}>
                    {fmt(montantTtcSigneFacture(facture))}
                  </p>
                  {facture.exoneration_tva && <p className="text-[9px] text-muted-foreground">Exonéré TVA</p>}
                </div>
              </div>

              {peutTelecharger && (
                <BoutonY2K
                  size="sm"
                  variant="secondary"
                  className="gap-1.5 text-xs"
                  onClick={() => void handleDownload(facture.id)}
                  disabled={telechargementId !== null}
                  loading={downloading}
                  iconeGauche={downloading ? undefined : <Download className="h-3.5 w-3.5" />}
                  aria-label={`Télécharger le PDF ${facture.numero_facture}`}
                >
                  {downloading ? 'Génération…' : 'PDF'}
                </BoutonY2K>
              )}
            </div>
          );
        })}
      </div>

      {viewerRole === 'ETAB' && (
        <p className="text-[10px] text-muted-foreground/70 italic">
          Documents émis par Jolene au nom du soignant (mandat de facturation — art. 289 I-2 CGI).
          Conservez chaque facture et avoir comme justificatif comptable.
        </p>
      )}
    </div>
  );
}
