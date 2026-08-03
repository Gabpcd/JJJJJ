import { useState, useEffect } from 'react';
import { CreditCard, Banknote, FileText, Loader2, Eye, CheckCircle, Edit2, AlertTriangle, Scale, Clock } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Input } from '@/components/ui/input';
import { Checkbox } from '@/components/ui/checkbox';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { toast } from 'sonner';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { useNavigate } from 'react-router-dom';
import { useEtabPermissions } from '@/hooks/useEtabPermissions';

interface Props {
  missionId: string;
  soignantAssigneId: string;
  etablissementId: string;
  onStartConnectPay: () => void;
  soignantHasConnect: boolean;
}

type ModeRecommande = 'STRIPE_CONNECT' | 'VIREMENT_PAIE' | 'VIREMENT_NOTE_HONORAIRES';

interface InfoPaiement {
  mode_recommande: ModeRecommande;
  montant_soignant: number;
  montant_soignant_estime?: boolean;
  commission_ttc: number;
  total: number;
  iban_last4?: string;
  type_exercice?: string;
  type_contrat_applique?: string;
}

const isRefValid = (ref: string) => {
  const t = ref.trim();
  return t.length >= 6 && /\d{2,}/.test(t) && /[A-Za-z]/.test(t);
};

export function WorkflowPaiementMission({ missionId, soignantAssigneId, etablissementId, onStartConnectPay, soignantHasConnect }: Props) {
  const navigate = useNavigate();
  const {
    loading: permissionsLoading,
    permissions,
    error: permissionsError,
    recharger: rechargerPermissions,
  } = useEtabPermissions(etablissementId);
  const canReadFinance = permissions.lecture_paiement || permissions.paiement;
  const canManagePayments = permissions.paiement;
  const [info, setInfo] = useState<InfoPaiement | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);
  const [declaring, setDeclaring] = useState(false);
  const [reference, setReference] = useState('');
  const [montantNetReel, setMontantNetReel] = useState('');
  const [montantNetDu, setMontantNetDu] = useState('');
  const [attestation, setAttestation] = useState(false);
  const [ribLoading, setRibLoading] = useState(false);
  const [ribData, setRibData] = useState<string | null>(null);
  const [paiementExistant, setPaiementExistant] = useState<any>(null);
  const [showModifRef, setShowModifRef] = useState(false);
  const [newRef, setNewRef] = useState('');
  const [modifLoading, setModifLoading] = useState(false);
  const [stripeTransfer, setStripeTransfer] = useState<any>(null);

  useEffect(() => {
    if (permissionsLoading) return;
    if (permissionsError) {
      setInfo(null);
      setPaiementExistant(null);
      setStripeTransfer(null);
      setLoadError('Impossible de vérifier vos droits de paiement.');
      setLoading(false);
      return;
    }
    if (!canReadFinance) {
      setInfo(null);
      setPaiementExistant(null);
      setStripeTransfer(null);
      setLoadError(null);
      setLoading(false);
      return;
    }
    let cancelled = false;
    const load = async () => {
      setLoading(true);
      setLoadError(null);
      setInfo(null);
      setPaiementExistant(null);
      setStripeTransfer(null);
      setRibData(null);
      setMontantNetReel('');
      setMontantNetDu('');
      try {
        const [modeResponse, paiementResponse, transferResponse] = await Promise.all([
          supabase.rpc('fn_mode_paiement_mission' as any, { p_mission_id: missionId }),
          supabase.from('paiements_soignant')
            .select('*')
            .eq('mission_id', missionId)
            .in('statut', ['DECLARE', 'CONFIRME', 'CONTESTE', 'RESOLU'])
            .order('cree_le', { ascending: false })
            .limit(1),
          supabase.from('stripe_transfers')
            .select('id, statut, montant_total, montant_soignant, montant_commission, charge_le')
            .eq('mission_id', missionId)
            .in('statut', ['EN_ATTENTE', 'CHARGE_REUSSI', 'TRANSFERE', 'PAYE'])
            .order('cree_le', { ascending: false })
            .limit(1),
        ]);
        if (modeResponse.error) throw modeResponse.error;
        if (paiementResponse.error) throw paiementResponse.error;
        if (transferResponse.error) throw transferResponse.error;
        if (!Array.isArray(paiementResponse.data) || !Array.isArray(transferResponse.data)) {
          throw new Error('Historique de paiement incomplet');
        }
        const modeData = modeResponse.data as (InfoPaiement & { error?: string }) | null;
        if (!modeData || modeData.error || !modeData.mode_recommande) {
          throw new Error(modeData?.error || 'Mode de paiement indisponible');
        }
        if (cancelled) return;
        setInfo(modeData);
        if (paiementResponse.data?.length) setPaiementExistant(paiementResponse.data[0]);
        if (transferResponse.data?.length) setStripeTransfer(transferResponse.data[0]);
      } catch (error) {
        if (cancelled) return;
        const message = error instanceof Error && error.message
          ? error.message
          : error && typeof error === 'object' && 'message' in error
            ? String(error.message)
            : 'Données de paiement indisponibles';
        setLoadError(`Impossible de charger le paiement : ${message}`);
      } finally {
        if (!cancelled) setLoading(false);
      }
    };
    void load();
    return () => { cancelled = true; };
  }, [canReadFinance, missionId, permissionsError, permissionsLoading, reloadToken]);

  const retryLoad = () => {
    if (permissionsError) {
      void rechargerPermissions();
      return;
    }
    setReloadToken((value) => value + 1);
  };

  const consulterRib = async () => {
    if (!canManagePayments) {
      toast.error('Votre rôle ne permet pas de consulter les coordonnées bancaires.');
      return;
    }
    const preview = window.open('about:blank', '_blank');
    if (!preview) {
      toast.error('Autorisez les fenêtres contextuelles pour consulter le RIB.');
      return;
    }
    preview.opener = null;

    setRibLoading(true);
    try {
      const { data, error } = await supabase.rpc('fn_consulter_rib_soignant' as any, { p_mission_id: missionId });
      if (error) throw error;
      const result = data as any;
      if (result?.error) throw new Error(result.error);
      if (result?.s3_cle || result?.s3_bucket) {
        if (!result?.s3_cle || !result?.s3_bucket) throw new Error('Référence du RIB incomplète');
        const { data: urlData, error: urlError } = await supabase.storage
          .from(result.s3_bucket)
          .createSignedUrl(result.s3_cle, 300);
        if (urlError || !urlData?.signedUrl) throw urlError || new Error('Lien du RIB indisponible');
        preview.location.replace(urlData.signedUrl);
        setRibData('opened');
        return;
      }
      preview.close();
      setRibData(result?.iban || result);
    } catch (e: any) {
      preview.close();
      toast.error(e?.message || 'Impossible de consulter le RIB');
    } finally {
      setRibLoading(false);
    }
  };

  const declarerPaiement = async () => {
    if (!canManagePayments) {
      toast.error('Votre rôle ne permet pas de déclarer un paiement.');
      return;
    }
    if (!isRefValid(reference)) {
      toast.error('La référence doit contenir au moins 6 caractères, dont 2 chiffres et 1 lettre (ex : VIR-2026-001)');
      return;
    }
    if (!attestation) {
      toast.error('Veuillez cocher l\'attestation sur l\'honneur pour déclarer le paiement');
      return;
    }
    const estPaiementSalarie = info?.mode_recommande === 'VIREMENT_PAIE';
    const montantDeclare = estPaiementSalarie
      ? Number(montantNetReel.replace(',', '.'))
      : Number(info?.montant_soignant ?? 0);
    const montantDu = estPaiementSalarie
      ? Number(montantNetDu.replace(',', '.'))
      : montantDeclare;
    if (!Number.isFinite(montantDeclare) || montantDeclare <= 0) {
      toast.error(estPaiementSalarie
        ? 'Saisissez le montant net exact figurant sur le bulletin officiel.'
        : 'Montant de paiement invalide.');
      return;
    }
    if (!Number.isFinite(montantDu) || montantDu <= 0) {
      toast.error('Le montant total dû doit être positif.');
      return;
    }
    if (estPaiementSalarie && Math.abs(montantDeclare - montantDu) > 0.005) {
      toast.error('Le montant versé doit correspondre exactement au total net dû. Les paiements partiels ne sont pas acceptés.');
      return;
    }
    setDeclaring(true);
    try {
      const { data, error } = estPaiementSalarie
        ? await supabase.rpc('fn_declarer_paiement_soignant_v2' as any, {
            p_mission_id: missionId,
            p_montant_verse: montantDeclare,
            p_montant_total_du: montantDu,
            p_reference: reference.trim(),
            p_methode: 'VIREMENT',
            p_date_paiement: new Date().toISOString().slice(0, 10),
            p_attestation_sur_l_honneur: attestation,
          })
        : await supabase.rpc('fn_declarer_paiement_soignant' as any, {
            p_mission_id: missionId,
            p_montant: montantDeclare,
            p_reference: reference.trim(),
            p_attestation_sur_l_honneur: attestation,
          });
      if (error) throw error;
      const result = data as any;
      if (result?.error) {
        if (result?.use_stripe_connect) {
          toast.info('Ce soignant utilise Stripe Connect — redirection vers le paiement par carte');
          onStartConnectPay();
          return;
        }
        throw new Error(result.error);
      }
      toast.success('Paiement déclaré — le soignant sera notifié');
      setReference('');
      setMontantNetReel('');
      setMontantNetDu('');
      // Reload payment status
      const { data: pData } = await supabase.from('paiements_soignant')
        .select('*').eq('mission_id', missionId)
        .in('statut', ['DECLARE', 'CONFIRME', 'CONTESTE', 'RESOLU'])
        .order('cree_le', { ascending: false }).limit(1);
      if (pData?.length) setPaiementExistant(pData[0]);
    } catch (e: any) {
      toast.error(e?.message || 'Erreur lors de la déclaration');
    }
    setDeclaring(false);
  };

  const modifierReference = async () => {
    if (!canManagePayments || !isRefValid(newRef) || !paiementExistant) return;
    setModifLoading(true);
    try {
      const { data, error } = await supabase.rpc('fn_modifier_reference_paiement' as any, {
        p_paiement_id: paiementExistant.id,
        p_nouvelle_reference: newRef.trim(),
      });
      if (error) throw error;
      if ((data as any)?.error) throw new Error((data as any).error);
      toast.success('Référence modifiée');
      setPaiementExistant({ ...paiementExistant, reference_virement: newRef.trim() });
      setShowModifRef(false);
    } catch (e: any) {
      toast.error(e?.message || 'Erreur');
    }
    setModifLoading(false);
  };

  if (loading) {
    return (
      <div className="card-base flex items-center justify-center py-4">
        <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (loadError) {
    return (
      <div className="card-base border-destructive/30 bg-destructive/5 space-y-3" role="alert">
        <div className="flex items-start gap-2">
          <AlertTriangle className="h-4 w-4 text-destructive shrink-0 mt-0.5" />
          <div>
            <p className="text-sm font-semibold text-foreground">Paiement indisponible</p>
            <p className="text-xs text-muted-foreground mt-1">{loadError}</p>
          </div>
        </div>
        <BoutonY2K size="sm" variant="secondary" onClick={retryLoad}>
          Réessayer
        </BoutonY2K>
      </div>
    );
  }

  if (!info) return null;

  const fmt = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);

  // If payment already declared, show status
  if (paiementExistant) {
    const p = paiementExistant;
    const canModifyRef = p.statut === 'DECLARE' && !p.confirme_par_soignant;
    const fmtDate = (iso: string | null | undefined) =>
      iso ? format(new Date(iso), "d MMM yyyy 'à' HH'h'mm", { locale: fr }) : null;

    // Mapping statut → affichage (cohérent avec docs/logique-paiements-v1.md §6)
    const statutUI = (() => {
      switch (p.statut) {
        case 'CONFIRME':
          return {
            icon: CheckCircle,
            iconClass: 'text-success',
            borderClass: 'border-success/30',
            bgClass: 'bg-success/5',
            titre: 'Paiement confirmé par le soignant',
            sousTitre: p.confirme_par_soignant_le
              ? `Confirmé le ${fmtDate(p.confirme_par_soignant_le)}`
              : 'Le soignant a confirmé avoir reçu le paiement',
            badgeLabel: 'CONFIRMÉ',
            badgeClass: 'bg-success/10 text-success border-success/30',
          };
        case 'CONTESTE':
          return {
            icon: AlertTriangle,
            iconClass: 'text-warning',
            borderClass: 'border-warning/40',
            bgClass: 'bg-warning/5',
            titre: 'Paiement contesté — litige en cours',
            sousTitre: p.motif_contestation
              ? `Motif : ${p.motif_contestation}`
              : 'Le soignant conteste ce paiement',
            badgeLabel: 'CONTESTÉ',
            badgeClass: 'bg-warning/10 text-warning border-warning/40',
          };
        case 'RESOLU':
          return {
            icon: Scale,
            iconClass: 'text-muted-foreground',
            borderClass: 'border-border',
            bgClass: 'bg-muted/30',
            titre: 'Litige résolu',
            sousTitre: p.modifie_le
              ? `Résolu le ${fmtDate(p.modifie_le)}`
              : 'Le litige a été résolu entre les parties',
            badgeLabel: 'RÉSOLU',
            badgeClass: 'bg-muted text-muted-foreground border-border',
          };
        case 'DECLARE':
        default:
          return {
            icon: Clock,
            iconClass: 'text-primary',
            borderClass: 'border-primary/30',
            bgClass: 'bg-primary/5',
            titre: 'Paiement déclaré — en attente du soignant',
            sousTitre: p.date_paiement
              ? `Déclaré pour le ${format(new Date(p.date_paiement), 'd MMM yyyy', { locale: fr })}`
              : 'Le soignant doit confirmer ou contester',
            badgeLabel: 'EN ATTENTE',
            badgeClass: 'bg-primary/10 text-primary border-primary/30',
          };
      }
    })();

    const StatutIcon = statutUI.icon;

    return (
      <div className={`card-base ${statutUI.borderClass} ${statutUI.bgClass} space-y-3`}>
        <div className="flex items-start justify-between gap-3">
          <div className="flex items-start gap-2 min-w-0">
            <StatutIcon className={`h-4 w-4 ${statutUI.iconClass} shrink-0 mt-0.5`} />
            <div className="min-w-0">
              <p className="text-sm font-semibold text-foreground">{statutUI.titre}</p>
              <p className="text-xs text-muted-foreground mt-0.5">{statutUI.sousTitre}</p>
            </div>
          </div>
          <span className={`text-[10px] font-semibold px-2 py-0.5 rounded-full border shrink-0 ${statutUI.badgeClass}`}>
            {statutUI.badgeLabel}
          </span>
        </div>

        <div className="text-xs space-y-1 border-t border-border/60 pt-2">
          <p className="text-muted-foreground">
            Méthode : <span className="text-foreground font-medium">{p.stripe_transfer_id ? 'Stripe Connect' : p.methode === 'NOTE_HONORAIRES' ? "Note d'honoraires" : p.methode === 'STRIPE_CONNECT' ? 'Stripe Connect' : 'Virement'}</span>
          </p>
          {p.reference_virement && (
            <p className="text-muted-foreground">
              Référence : <span className="text-foreground font-mono font-medium">{p.reference_virement}</span>
            </p>
          )}
          {/* Si paiement Stripe Connect : afficher le montant TOTAL débité à l'étab
              (honoraires soignant + commission Jolene capturée à la source), pas
              juste le net soignant — évite la confusion "seul 132€ a été débité". */}
          {p.stripe_transfer_id && info ? (
            <>
              <p className="text-muted-foreground">
                Montant débité : <span className="text-foreground font-semibold">{fmt(p.montant_net + info.commission_ttc)}</span>
              </p>
              <p className="text-[10px] text-muted-foreground/80 pl-1">
                = {fmt(p.montant_net)} honoraires soignant + {fmt(info.commission_ttc)} commission Jolene
              </p>
            </>
          ) : (
            <>
              <p className="text-muted-foreground">
                Montant versé : <span className="text-foreground font-medium">{fmt(p.montant_net)}</span>
              </p>
              {p.montant_du_reference != null && (
                <p className="text-muted-foreground">
                  Total dû déclaré : <span className="text-foreground font-medium">{fmt(p.montant_du_reference)}</span>
                  {p.solde_restant > 0 && (
                    <span className="ml-1 font-semibold text-warning">· reste {fmt(p.solde_restant)}</span>
                  )}
                </p>
              )}
            </>
          )}
        </div>

        {p.statut === 'CONTESTE' && (
          <BoutonY2K
            size="sm"
            variant="secondary"
            className="gap-1.5 text-xs border-warning/40 text-warning hover:bg-warning/10"
            onClick={() => navigate('/etablissement/litiges')}
            iconeGauche={<Scale className="h-3 w-3" />}
          >
            Voir le litige
          </BoutonY2K>
        )}

        {canManagePayments && canModifyRef && (
          <BoutonY2K size="sm" variant="secondary" className="gap-1.5 text-xs" onClick={() => { setNewRef(p.reference_virement || ''); setShowModifRef(true); }} iconeGauche={<Edit2 className="h-3 w-3" />}>
            Modifier la référence
          </BoutonY2K>
        )}
        <Dialog open={canManagePayments && showModifRef} onOpenChange={setShowModifRef}>
          <DialogContent>
            <DialogHeader><DialogTitle>Modifier la référence de paiement</DialogTitle></DialogHeader>
            <div className="space-y-3 mt-2">
              <Input value={newRef} onChange={e => setNewRef(e.target.value)} placeholder="Ex: VIR-2026-03-001" />
              <div className="flex justify-end gap-2">
                <BoutonY2K variant="ghost" onClick={() => setShowModifRef(false)}>Annuler</BoutonY2K>
                <BoutonY2K onClick={modifierReference} disabled={modifLoading || !isRefValid(newRef)} loading={modifLoading}>
                  {modifLoading ? 'Modification…' : 'Enregistrer'}
                </BoutonY2K>
              </div>
            </div>
          </DialogContent>
        </Dialog>
      </div>
    );
  }

  // Stripe transfer already exists (paid or in progress)
  if (stripeTransfer) {
    const isVerse = ['TRANSFERE', 'PAYE'].includes(stripeTransfer.statut);
    const paiementConfirme = stripeTransfer.statut === 'CHARGE_REUSSI';
    return (
      <div className={`card-base space-y-2 ${isVerse ? 'border-success/20' : 'border-primary/20'}`}>
        <p className="text-sm font-semibold text-foreground flex items-center gap-2">
          {isVerse ? (
            <><CheckCircle className="h-4 w-4 text-success" /> Paiement Stripe effectué</>
          ) : paiementConfirme ? (
            <><Loader2 className="h-4 w-4 animate-spin text-primary" /> Paiement reçu — transfert en cours</>
          ) : (
            <><Loader2 className="h-4 w-4 animate-spin text-primary" /> Paiement Stripe en cours</>
          )}
        </p>
        <div className="text-xs space-y-1">
          <p className="text-muted-foreground">Commission Jolene : <span className="text-foreground font-medium">{fmt(stripeTransfer.montant_commission)}</span></p>
          <p className="text-muted-foreground">Honoraires soignant : <span className="text-foreground font-medium">{fmt(stripeTransfer.montant_soignant)}</span></p>
          <p className="text-muted-foreground">Total : <span className="text-foreground font-semibold">{fmt(stripeTransfer.montant_total)}</span></p>
          {stripeTransfer.charge_le && (
            <p className="text-muted-foreground">Date : <span className="text-foreground font-medium">{new Date(stripeTransfer.charge_le).toLocaleDateString('fr-FR')}</span></p>
          )}
        </div>
        {!isVerse && (
          <p className="text-[10px] text-muted-foreground">
            {paiementConfirme
              ? 'Le paiement est confirmé ; le transfert vers le soignant est encore en cours.'
              : 'Le transfert vers le soignant sera effectué automatiquement après confirmation du paiement.'}
          </p>
        )}
      </div>
    );
  }

  // Stripe Connect: paiement automatique
  if (info.mode_recommande === 'STRIPE_CONNECT' && soignantHasConnect) {
    return (
      <div className="card-base border-primary/20 space-y-3">
        <p className="text-sm font-semibold text-foreground flex items-center gap-2">
          <CreditCard className="h-4 w-4 text-primary" /> Paiement Stripe Connect
        </p>
        <div className="text-xs text-muted-foreground space-y-1">
          <p>Commission Jolene : {fmt(info.commission_ttc)}</p>
          <p>Honoraires soignant : {fmt(info.montant_soignant)}</p>
          <p className="font-semibold text-foreground">Total : {fmt(info.total)}</p>
        </div>
        {canManagePayments ? (
          <BoutonY2K size="sm" onClick={onStartConnectPay} className="gap-2" iconeGauche={<CreditCard className="h-4 w-4" />}>
            💳 Payer via Stripe
          </BoutonY2K>
        ) : (
          <p className="text-xs text-muted-foreground">Consultation uniquement — paiement non autorisé pour votre rôle.</p>
        )}
      </div>
    );
  }

  // Paiement manuel avec référence obligatoire. Pour un salarié, la valeur
  // remontée par le mode de paiement est seulement une estimation avant PAS :
  // l'employeur doit saisir explicitement le net du bulletin officiel.
  const estVirementSalarie = info.mode_recommande === 'VIREMENT_PAIE';
  const methodeLabel = estVirementSalarie ? 'Virement de rémunération salariée' : "Note d'honoraires";
  const icone = estVirementSalarie ? Banknote : FileText;
  const Icone = icone;
  const trimmedRef = reference.trim();
  const montantNetReelNombre = Number(montantNetReel.replace(',', '.'));
  const montantNetReelValide = Number.isFinite(montantNetReelNombre) && montantNetReelNombre > 0;
  const montantNetDuNombre = Number(montantNetDu.replace(',', '.'));
  const montantNetDuValide = Number.isFinite(montantNetDuNombre)
    && montantNetDuNombre > 0
    && montantNetReelNombre <= montantNetDuNombre;
  // Feedback aligné sur isRefValid : ≥6 caractères, ≥2 chiffres, ≥1 lettre.
  const refTooShort = trimmedRef.length > 0 && trimmedRef.length < 6;
  const refNoDigit = trimmedRef.length >= 6 && !/\d{2,}/.test(trimmedRef);
  const refNoLetter = trimmedRef.length >= 6 && /\d{2,}/.test(trimmedRef) && !/[A-Za-z]/.test(trimmedRef);

  return (
    <div className="card-base border-primary/20 space-y-3">
      <p className="text-sm font-semibold text-foreground flex items-center gap-2">
        <Icone className="h-4 w-4 text-primary" /> {methodeLabel}
      </p>
      <div className="text-xs text-muted-foreground space-y-1">
        {estVirementSalarie ? (
          <>
            <p>Estimation indicative avant PAS : <span className="font-medium text-foreground">{fmt(info.montant_soignant)}</span></p>
            <p>Le virement doit reprendre le net à payer exact du bulletin officiel établi par l'établissement employeur.</p>
          </>
        ) : (
          <p>Honoraires à verser au soignant : <span className="font-medium text-foreground">{fmt(info.montant_soignant)}</span></p>
        )}
        <p>Méthode : <span className="font-medium text-foreground">{estVirementSalarie ? 'Virement SEPA' : methodeLabel}</span></p>
      </div>

      {/* RIB soignant — uniquement pour les missions salariées (bulletin de paie) */}
      {canManagePayments && info.mode_recommande === 'VIREMENT_PAIE' && (
        info.iban_last4 ? (
          <p className="text-xs text-muted-foreground">
            RIB : ****{info.iban_last4}
          </p>
        ) : (
          <div className="flex items-center gap-2">
            {ribData ? (
              ribData === 'opened' ? (
                <p className="text-xs text-success">📄 RIB ouvert dans un nouvel onglet</p>
              ) : (
                <p className="text-xs text-muted-foreground">IBAN : {ribData}</p>
              )
            ) : (
              <BoutonY2K size="sm" variant="ghost" className="gap-1 text-xs h-7" onClick={consulterRib} disabled={ribLoading} loading={ribLoading} iconeGauche={ribLoading ? undefined : <Eye className="h-3 w-3" />}>
                📄 Voir le RIB (PDF)
              </BoutonY2K>
            )}
          </div>
        )
      )}

      {canManagePayments ? (
      <>
      {estVirementSalarie && (
        <div className="space-y-2">
          <label htmlFor={`montant-net-du-${missionId}`} className="text-xs font-medium text-foreground">
            Montant net total dû selon le bulletin officiel *
          </label>
          <Input
            id={`montant-net-du-${missionId}`}
            type="number"
            inputMode="decimal"
            min="0.01"
            step="0.01"
            placeholder="Ex : 500.00"
            value={montantNetDu}
            onChange={e => setMontantNetDu(e.target.value)}
            className="text-sm"
          />
          <label htmlFor={`montant-net-reel-${missionId}`} className="text-xs font-medium text-foreground">
            Montant réellement versé aujourd’hui *
          </label>
          <Input
            id={`montant-net-reel-${missionId}`}
            type="number"
            inputMode="decimal"
            min="0.01"
            step="0.01"
            placeholder="Ex : 346.85"
            value={montantNetReel}
            onChange={e => setMontantNetReel(e.target.value)}
            aria-describedby={`montant-net-reel-aide-${missionId}`}
            className="text-sm"
          />
          <p id={`montant-net-reel-aide-${missionId}`} className="text-[10px] text-muted-foreground">
            Le règlement doit correspondre exactement au total net dû. Les paiements partiels ne sont pas acceptés.
          </p>
        </div>
      )}
      <div className="space-y-2">
        <label htmlFor={`reference-paiement-${missionId}`} className="text-xs font-medium text-foreground">Référence de paiement *</label>
        <Input
          id={`reference-paiement-${missionId}`}
          placeholder="Ex: VIR-2026-03-001"
          value={reference}
          onChange={e => setReference(e.target.value)}
          className="text-sm"
        />
        <p className="text-[10px] text-muted-foreground">
          Numéro de virement bancaire, référence de chèque ou numéro de facture —
          au moins 6 caractères avec lettres et chiffres (ex : VIR-2026-001).
        </p>
        {refTooShort && (
          <p className="text-[10px] text-destructive">Minimum 6 caractères</p>
        )}
        {refNoDigit && (
          <p className="text-[10px] text-destructive">Au moins 2 chiffres requis (ex : le numéro de votre virement)</p>
        )}
        {refNoLetter && (
          <p className="text-[10px] text-destructive">Au moins une lettre requise (ex : VIR-2026-001)</p>
        )}
      </div>
      <label className="flex items-start gap-2 cursor-pointer">
        <Checkbox checked={attestation} onCheckedChange={v => setAttestation(!!v)} className="mt-0.5" />
        <span className="text-[11px] text-muted-foreground">
          {estVirementSalarie
            ? "J'atteste sur l'honneur avoir viré le montant net exact indiqué sur le bulletin officiel du soignant. Toute fausse déclaration engage ma responsabilité."
            : "J'atteste sur l'honneur avoir effectué ce virement au soignant. Toute fausse déclaration engage ma responsabilité."}
        </span>
      </label>
      <BoutonY2K
        size="sm"
        variant="secondary"
        onClick={declarerPaiement}
        disabled={declaring || !isRefValid(reference) || !attestation || (estVirementSalarie && (!montantNetReelValide || !montantNetDuValide))}
        loading={declaring}
        className="gap-2"
        iconeGauche={declaring ? undefined : <Banknote className="h-4 w-4" />}
      >
        {declaring ? 'Déclaration…' : 'Déclarer le paiement effectué'}
      </BoutonY2K>
      </>
      ) : (
        <p className="text-xs text-muted-foreground">Consultation uniquement — paiement non autorisé pour votre rôle.</p>
      )}
    </div>
  );
}
