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
  commission_ttc: number;
  total: number;
  iban_soignant?: string;
  type_exercice?: string;
}

const isRefValid = (ref: string) => {
  const t = ref.trim();
  return t.length >= 6 && /\d{2,}/.test(t) && /[A-Za-z]/.test(t);
};

export function WorkflowPaiementMission({ missionId, soignantAssigneId, etablissementId, onStartConnectPay, soignantHasConnect }: Props) {
  const navigate = useNavigate();
  const [info, setInfo] = useState<InfoPaiement | null>(null);
  const [loading, setLoading] = useState(true);
  const [declaring, setDeclaring] = useState(false);
  const [reference, setReference] = useState('');
  const [attestation, setAttestation] = useState(false);
  const [ribLoading, setRibLoading] = useState(false);
  const [ribData, setRibData] = useState<string | null>(null);
  const [paiementExistant, setPaiementExistant] = useState<any>(null);
  const [showModifRef, setShowModifRef] = useState(false);
  const [newRef, setNewRef] = useState('');
  const [modifLoading, setModifLoading] = useState(false);
  const [stripeTransfer, setStripeTransfer] = useState<any>(null);

  useEffect(() => {
    const load = async () => {
      const [{ data: modeData, error: modeErr }, { data: paiementData }, { data: transferData }] = await Promise.all([
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
          .in('statut', ['EN_ATTENTE', 'TRANSFERE'])
          .order('cree_le', { ascending: false })
          .limit(1),
      ]);
      if (!modeErr && modeData) {
        setInfo(modeData as unknown as InfoPaiement);
      }
      if (paiementData && paiementData.length > 0) {
        setPaiementExistant(paiementData[0]);
      }
      if (transferData && transferData.length > 0) {
        setStripeTransfer(transferData[0]);
      }
      setLoading(false);
    };
    load();
  }, [missionId]);

  const consulterRib = async () => {
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
    if (!isRefValid(reference)) {
      toast.error('La référence doit contenir au moins 6 caractères, dont 2 chiffres et 1 lettre (ex : VIR-2026-001)');
      return;
    }
    if (!attestation) {
      toast.error('Veuillez cocher l\'attestation sur l\'honneur pour déclarer le paiement');
      return;
    }
    setDeclaring(true);
    try {
      const { data, error } = await supabase.rpc('fn_declarer_paiement_soignant' as any, {
        p_mission_id: missionId,
        p_montant: info?.montant_soignant || 0,
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
    if (!isRefValid(newRef) || !paiementExistant) return;
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
            <p className="text-muted-foreground">
              Montant : <span className="text-foreground font-medium">{fmt(p.montant_net)}</span>
            </p>
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

        {canModifyRef && (
          <BoutonY2K size="sm" variant="secondary" className="gap-1.5 text-xs" onClick={() => { setNewRef(p.reference_virement || ''); setShowModifRef(true); }} iconeGauche={<Edit2 className="h-3 w-3" />}>
            Modifier la référence
          </BoutonY2K>
        )}
        <Dialog open={showModifRef} onOpenChange={setShowModifRef}>
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
    const isTransfere = stripeTransfer.statut === 'TRANSFERE';
    return (
      <div className={`card-base space-y-2 ${isTransfere ? 'border-success/20' : 'border-primary/20'}`}>
        <p className="text-sm font-semibold text-foreground flex items-center gap-2">
          {isTransfere ? (
            <><CheckCircle className="h-4 w-4 text-success" /> Paiement Stripe effectué</>
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
        {!isTransfere && (
          <p className="text-[10px] text-muted-foreground">Le transfert vers le soignant sera effectué automatiquement après confirmation du paiement.</p>
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
        <BoutonY2K size="sm" onClick={onStartConnectPay} className="gap-2" iconeGauche={<CreditCard className="h-4 w-4" />}>
          💳 Payer via Stripe
        </BoutonY2K>
      </div>
    );
  }

  // Manual payment with required reference
  const methodeLabel = info.mode_recommande === 'VIREMENT_NOTE_HONORAIRES' ? "Note d'honoraires" : 'Bulletin de paie';
  const icone = info.mode_recommande === 'VIREMENT_NOTE_HONORAIRES' ? FileText : Banknote;
  const Icone = icone;
  const trimmedRef = reference.trim();
  // Feedback aligné sur isRefValid : ≥6 caractères, ≥2 chiffres, ≥1 lettre.
  const refTooShort = trimmedRef.length > 0 && trimmedRef.length < 6;
  const refNoDigit = trimmedRef.length >= 6 && !/\d{2,}/.test(trimmedRef);
  const refNoLetter = trimmedRef.length >= 6 && /\d{2,}/.test(trimmedRef) && !/[A-Za-z]/.test(trimmedRef);

  return (
    <div className="card-base border-primary/20 space-y-3">
      <p className="text-sm font-semibold text-foreground flex items-center gap-2">
        <Icone className="h-4 w-4 text-primary" /> Paiement par {methodeLabel.toLowerCase()}
      </p>
      <div className="text-xs text-muted-foreground space-y-1">
        <p>Net à payer au soignant : {fmt(info.montant_soignant)}</p>
        <p>Méthode : <span className="font-medium text-foreground">{methodeLabel}</span></p>
      </div>

      {/* RIB soignant — uniquement pour les missions salariées (bulletin de paie) */}
      {info.mode_recommande === 'VIREMENT_PAIE' && (
        info.iban_soignant ? (
          <p className="text-xs text-muted-foreground">
            RIB : ****{info.iban_soignant}
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

      <div className="space-y-2">
        <label className="text-xs font-medium text-foreground">Référence de paiement *</label>
        <Input
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
          J'atteste sur l'honneur avoir effectué ce virement au soignant. Toute fausse déclaration engage ma responsabilité.
        </span>
      </label>
      <BoutonY2K size="sm" variant="secondary" onClick={declarerPaiement} disabled={declaring || !isRefValid(reference) || !attestation} loading={declaring} className="gap-2" iconeGauche={declaring ? undefined : <Banknote className="h-4 w-4" />}>
        {declaring ? 'Déclaration…' : 'Déclarer le paiement effectué'}
      </BoutonY2K>
    </div>
  );
}
