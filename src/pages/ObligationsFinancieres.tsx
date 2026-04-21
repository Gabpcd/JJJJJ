import React, { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { SkeletonDashboard } from '@/components/SkeletonCard';
import { FadeInView } from '@/components/FadeInView';
import { EtatVide } from '@/components/EtatVide';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { useNavigate } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';
import { useNotification } from '@/contexts/NotificationContext';
import { extraireMessageErreur } from '@/lib/erreurs';
import { ENTREPRISE } from '@/constantes/entreprise';
import { AlertTriangle, CheckCircle, CreditCard, Clock, FileText, Banknote, ExternalLink } from 'lucide-react';
import { toast } from 'sonner';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog';
import { Label } from '@/components/ui/label';
import { Checkbox } from '@/components/ui/checkbox';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { EmbeddedCheckoutProvider, EmbeddedCheckout } from '@stripe/react-stripe-js';
import { stripePromise } from '@/lib/stripe';

const fmt = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
const isRefValid = (ref: string) => {
  const t = ref.trim();
  return t.length >= 6 && /\d{2,}/.test(t) && /[A-Za-z]/.test(t);
};

function RetardBadge({ jours }: { jours: number }) {
  if (jours < 15) return null;
  if (jours < 30) return <Badge className="bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400">⏳ {jours}j</Badge>;
  if (jours < 60) return <Badge className="bg-destructive/10 text-destructive">🔴 {jours}j de retard</Badge>;
  return <Badge className="bg-destructive text-destructive-foreground">⛔ {jours}j — risque de suspension</Badge>;
}

function TypeExerciceBadge({ type }: { type: string }) {
  const map: Record<string, { label: string; cls: string }> = {
    SALARIE: { label: 'Salarié', cls: 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400' },
    LIBERAL: { label: 'Libéral', cls: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400' },
    MIXTE: { label: 'Mixte', cls: 'bg-violet-100 text-violet-700 dark:bg-violet-900/30 dark:text-violet-400' },
  };
  const info = map[type] || { label: type, cls: 'bg-muted text-muted-foreground' };
  return <Badge className={info.cls}>{info.label}</Badge>;
}

function ResumeCard({
  value,
  label,
  detail,
  onClick,
  accent,
}: {
  value: string;
  label: string;
  detail: string;
  onClick?: () => void;
  accent?: 'destructive' | 'success' | 'default';
}) {
  const borderCls = accent === 'destructive' ? 'border-destructive/30' : accent === 'success' ? 'border-success/30' : '';
  const bgCls = accent === 'destructive' ? 'bg-destructive/5' : accent === 'success' ? 'bg-success/5' : '';
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={!onClick}
      className={`card-kpi text-center w-full ${borderCls} ${bgCls} ${onClick ? 'cursor-pointer' : 'cursor-default'}`}
    >
      <p className="text-2xl font-bold text-foreground">{value}</p>
      <p className="text-xs text-muted-foreground mt-1">{label}</p>
      {onClick && (
        <p className="mt-2 inline-flex items-center gap-1 text-xs text-primary">
          <ExternalLink className="h-3.5 w-3.5" />
          {detail}
        </p>
      )}
    </button>
  );
}

export default function ObligationsFinancieres() {
  usePageTitle('Obligations financières');
  const navigate = useNavigate();
  const { user, etablissementId } = useEtablissementScope();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [data, setData] = useState<any>(null);
  const [declaringId, setDeclaringId] = useState<string | null>(null);
  const [declaringRef, setDeclaringRef] = useState<Record<string, string>>({});
  const [connectPayingId, setConnectPayingId] = useState<string | null>(null);

  const charger = async () => {
    if (!user || !etablissementId) return;
    try {
      const { data: res, error } = await supabase.rpc('fn_obligations_financieres' as any);
      if (error) throw error;
      setData(res);
    } catch (e: any) {
      toast.error(extraireMessageErreur(e));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    charger();
  }, [user, etablissementId]);

  // [CP-C-1] Dialog de déclaration paiement soignant
  type MethodePaiement = 'VIREMENT' | 'CHEQUE' | 'BULLETIN_PAIE' | 'NOTE_HONORAIRES';
  const [declarerDialogMission, setDeclarerDialogMission] = useState<any | null>(null);
  const [declarerMontant, setDeclarerMontant] = useState<string>('');
  const [declarerMethode, setDeclarerMethode] = useState<MethodePaiement>('VIREMENT');
  const [declarerReference, setDeclarerReference] = useState<string>('');
  const [declarerDatePaiement, setDeclarerDatePaiement] = useState<string>('');
  const [declarerAttestation, setDeclarerAttestation] = useState<boolean>(false);

  const ouvrirDialogDeclarer = (mission: any) => {
    setDeclarerDialogMission(mission);
    setDeclarerMontant(String(Number(mission.net_a_payer || 0).toFixed(2)));
    setDeclarerMethode('VIREMENT');
    setDeclarerReference('');
    setDeclarerDatePaiement(new Date().toISOString().split('T')[0]);
    setDeclarerAttestation(false);
  };

  const fermerDialogDeclarer = () => {
    setDeclarerDialogMission(null);
    setDeclaringId(null);
  };

  const validerDeclarationPaiement = async () => {
    if (!declarerDialogMission) return;
    const missionId = declarerDialogMission.mission_id;
    const montantNum = Number(declarerMontant);
    if (!montantNum || montantNum <= 0) {
      toast.error('Montant invalide');
      return;
    }
    const refRequired = declarerMethode !== 'BULLETIN_PAIE';
    if (refRequired && !isRefValid(declarerReference)) {
      toast.error('La référence doit contenir au moins 5 caractères dont un chiffre.');
      return;
    }
    if (!declarerAttestation) {
      toast.error('Vous devez cocher l\'attestation sur l\'honneur.');
      return;
    }

    setDeclaringId(missionId);
    try {
      const { data, error } = await supabase.rpc('fn_declarer_paiement_soignant' as any, {
        p_mission_id: missionId,
        p_montant: montantNum,
        p_methode: declarerMethode,
        p_reference: declarerReference.trim(),
        p_date_paiement: declarerDatePaiement,
        p_attestation_sur_l_honneur: true,
      });
      if (error) throw error;
      const res = data as any;
      if (res?.error === 'ATTESTATION_REQUISE') {
        toast.error('Attestation sur l\'honneur obligatoire');
        return;
      }
      if (res?.error === 'use_stripe_connect') {
        toast.info('Ce soignant a Stripe Connect actif — utilisez le paiement Stripe');
        fermerDialogDeclarer();
        return;
      }
      if (res?.error) throw new Error(res.message || res.error);

      // Invoke send-email PAIEMENT_SOIGNANT_DECLARE (non-bloquant)
      try {
        const methodeLabels: Record<MethodePaiement, string> = {
          VIREMENT: 'Virement bancaire',
          CHEQUE: 'Chèque',
          BULLETIN_PAIE: 'Bulletin de paie',
          NOTE_HONORAIRES: 'Note d\'honoraires',
        };
        await supabase.functions.invoke('send-email', {
          body: {
            type: 'PAIEMENT_SOIGNANT_DECLARE',
            destinataire_id: res.soignant_id,
            data: {
              soignant_prenom: declarerDialogMission.soignant_prenom || declarerDialogMission.soignant_nom?.split(' ')[0] || '',
              montant_formatte: montantNum.toFixed(2),
              methode: declarerMethode,
              methode_libelle: methodeLabels[declarerMethode],
              reference_virement: declarerReference || '',
              date_paiement: declarerDatePaiement,
              date_paiement_fr: new Date(declarerDatePaiement).toLocaleDateString('fr-FR'),
              etablissement_nom: data?.etablissement_nom || '',
              mission_intitule: res.mission_intitule || declarerDialogMission.mission_intitule || '',
              deep_link: '/soignant/mes-gains',
            },
          },
        });
      } catch (emailErr) {
        // eslint-disable-next-line no-console
        console.error('send-email PAIEMENT_SOIGNANT_DECLARE failed:', emailErr);
      }

      toast.success('Paiement déclaré — le soignant a été notifié pour confirmation');
      fermerDialogDeclarer();
      charger();
    } catch (e: any) {
      toast.error(extraireMessageErreur(e));
    } finally {
      setDeclaringId(null);
    }
  };

  const [connectClientSecret, setConnectClientSecret] = useState<string | null>(null);

  const payerStripeConnect = async (missionId: string) => {
    setConnectPayingId(missionId);
    try {
      const { data: result, error } = await supabase.functions.invoke('stripe-connect-pay-mission', {
        body: { mission_id: missionId },
      });
      if (result?.already_paid) {
        toast.info(result.message || 'Ce paiement a déjà été effectué');
        if (typeof charger === 'function') charger();
        return;
      }
      // [CP-STRIPE-2] Facture honoraires pas encore générée : message explicite
      if (result?.error === 'FACTURE_NON_GENEREE') {
        toast.error(result.message || "Facture honoraires non générée. Cliquez sur 'Générer facture' avant de payer.", {
          duration: 8000,
        });
        return;
      }
      if (error) {
        toast.error(result?.message || result?.error || error.message || 'Erreur lors du paiement');
        return;
      }
      if (result?.error) throw new Error(result.message || result.error);
      if (result?.url) { window.location.href = result.url; return; }
      if (result?.client_secret) { setConnectClientSecret(result.client_secret); return; }
      toast.error('Aucune URL de paiement reçue');
    } catch (e: any) {
      toast.error(extraireMessageErreur(e));
    } finally {
      setConnectPayingId(null);
    }
  };

  const allerSection = (sectionId?: string) => {
    if (!sectionId) return;
    document.getElementById(sectionId)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  };

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><SkeletonDashboard /></LayoutApp>;

  if (data && data.total_du === 0) {
    return (
      <LayoutApp role="ADMIN_ETABLISSEMENT">
        <div className="space-y-6">
          <h1 className="text-2xl font-bold">💰 Mes obligations financières</h1>
          <div className="p-8 rounded-2xl bg-success/10 text-center space-y-2">
            <CheckCircle className="w-12 h-12 text-success mx-auto" />
            <p className="text-xl font-bold text-success">✅ Aucune obligation financière en cours</p>
            <p className="text-muted-foreground">Tous vos paiements sont à jour.</p>
          </div>
        </div>
      </LayoutApp>
    );
  }

  if (!data) {
    return (
      <LayoutApp role="ADMIN_ETABLISSEMENT">
        <EtatVide titre="Erreur de chargement" sousTitre="Impossible de charger vos obligations financières." />
      </LayoutApp>
    );
  }

  const missionsNonPayees = data.missions_non_payees || [];
  const paiementsEnAttente = data.paiements_soignants_en_attente || [];
  const paiementsConfirmes = data.paiements_soignants_confirmes || [];
  const facturesImpayees = data.factures_impayees || [];
  const missionsNonFacturees = data.missions_non_facturees || [];

  const sectionTotal = missionsNonPayees.length > 0
    ? 'section-missions-a-payer'
    : facturesImpayees.length > 0
      ? 'section-factures-impayees'
      : paiementsEnAttente.length > 0
        ? 'section-paiements-en-attente'
        : missionsNonFacturees.length > 0
          ? 'section-commissions-a-venir'
          : 'section-paiements-confirmes';

  const sectionSoignants = missionsNonPayees.length > 0
    ? 'section-missions-a-payer'
    : paiementsEnAttente.length > 0
      ? 'section-paiements-en-attente'
      : undefined;

  const sectionCommissions = facturesImpayees.length > 0
    ? 'section-factures-impayees'
    : missionsNonFacturees.length > 0
      ? 'section-commissions-a-venir'
      : undefined;

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-bold">💰 Mes obligations financières</h1>
          <p className="text-muted-foreground">Vue unique de tous les impayés : soignants + commissions Jolene.</p>
        </div>

        <FadeInView>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <ResumeCard
              value={fmt(data.total_du)}
              label="Total impayé"
              detail="Voir tout le détail"
              onClick={() => allerSection(sectionTotal)}
              accent={data.total_du > 0 ? 'destructive' : 'success'}
            />
            <ResumeCard
              value={fmt(data.total_soignants_du)}
              label={`Soignants à régler · ${data.nb_missions_non_payees} mission(s)`}
              detail="Voir les paiements soignants"
              onClick={sectionSoignants ? () => allerSection(sectionSoignants) : undefined}
            />
            <ResumeCard
              value={fmt(data.total_commissions_du)}
              label={`Commissions Jolene · ${data.nb_factures_impayees} facture(s)`}
              detail="Voir les commissions impayées"
              onClick={sectionCommissions ? () => allerSection(sectionCommissions) : undefined}
            />
          </div>
        </FadeInView>

        {missionsNonPayees.length > 0 && (
          <FadeInView delay={100}>
            <Card id="section-missions-a-payer">
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <AlertTriangle className="w-5 h-5 text-warning" />
                  Missions à payer aux soignants ({missionsNonPayees.length})
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-3">
                {missionsNonPayees.map((m: any) => {
                  const typeContratMission = m.type_contrat_applique as 'SALARIE' | 'LIBERAL' | null | undefined;
                  const isSalarie = typeContratMission === 'SALARIE';
                  const isLiberal = typeContratMission === 'LIBERAL';
                  const modePaiementLabel = isSalarie
                    ? 'Bulletin de paie (virement SEPA)'
                    : isLiberal
                    ? (m.mode_paiement_soignant === 'STRIPE_CONNECT' ? 'Note d\'honoraires (Stripe Connect)' : 'Note d\'honoraires (virement)')
                    : null;
                  // BUG-UI-OBLIG-1 Fix#3 — Stripe réservé aux missions LIBERAL
                  // avec mode de paiement STRIPE_CONNECT et soignant onboardé.
                  // Les missions SALARIE passent toujours par virement SEPA (bulletin).
                  const peutPayerStripe =
                    isLiberal
                    && m.mode_paiement_soignant === 'STRIPE_CONNECT'
                    && m.soignant_stripe_connect;
                  return (
                  <div key={m.mission_id} className="p-4 rounded-lg border space-y-3">
                    <div className="flex items-start justify-between gap-3">
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 flex-wrap">
                          <button onClick={() => navigate(`/etablissement/missions/${m.mission_id}`)} className="font-semibold text-sm text-primary hover:underline text-left">
                            {m.intitule}
                          </button>
                          {m.soignant_id ? (
                            <button onClick={() => navigate(`/etablissement/soignants/${m.soignant_id}`)} className="text-xs text-muted-foreground hover:text-primary hover:underline text-left">
                              {m.soignant_nom}
                            </button>
                          ) : (
                            <span className="text-xs text-muted-foreground">{m.soignant_nom}</span>
                          )}
                          <TypeExerciceBadge type={m.soignant_type_exercice} />
                          <RetardBadge jours={m.jours_depuis_fin} />
                        </div>
                        <p className="text-xs text-muted-foreground mt-1">
                          {m.soignant_profession} · {Math.round(m.heures || 0)}h pointées
                        </p>
                        <p className="text-xs text-muted-foreground">
                          {m.debut_le && new Date(m.debut_le).toLocaleDateString('fr-FR')} → {m.fin_le && new Date(m.fin_le).toLocaleDateString('fr-FR')}
                        </p>
                        {typeContratMission && (
                          <div className="flex items-center gap-2 mt-2 flex-wrap">
                            <Badge className={isSalarie
                              ? 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400'
                              : 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400'}
                            >
                              Contrat {isSalarie ? 'salarié (CDDU)' : 'libéral'}
                            </Badge>
                            {modePaiementLabel && (
                              <span className="text-xs text-muted-foreground">→ {modePaiementLabel}</span>
                            )}
                          </div>
                        )}
                      </div>
                      <div className="text-right shrink-0">
                        <p className="font-bold">{fmt(m.net_a_payer)}</p>
                        {m.montant_commission_ttc > 0 && (
                          <p className="text-[10px] text-muted-foreground">+ {fmt(m.montant_commission_ttc)} com.</p>
                        )}
                      </div>
                    </div>

                    {peutPayerStripe ? (
                      <Button
                        size="sm"
                        onClick={() => payerStripeConnect(m.mission_id)}
                        disabled={connectPayingId === m.mission_id}
                        className="w-full"
                      >
                        <CreditCard className="w-4 h-4 mr-2" />
                        {connectPayingId === m.mission_id ? 'Redirection…' : '💳 Payer via Stripe'}
                      </Button>
                    ) : (
                      <Button
                        size="sm"
                        onClick={() => ouvrirDialogDeclarer(m)}
                        disabled={declaringId === m.mission_id}
                        className="w-full"
                      >
                        <Banknote className="w-4 h-4 mr-2" />
                        Déclarer un paiement
                      </Button>
                    )}
                  </div>
                  );
                })}
              </CardContent>
            </Card>
          </FadeInView>
        )}

        {paiementsEnAttente.length > 0 && (
          <FadeInView delay={200}>
            <Card id="section-paiements-en-attente">
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <Clock className="w-5 h-5 text-amber-500" />
                  Paiements en attente de confirmation ({paiementsEnAttente.length})
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-3">
                {paiementsEnAttente.map((p: any) => (
                  <div key={p.paiement_id} className="flex items-center justify-between gap-3 p-3 rounded-lg border">
                    <div className="min-w-0 flex-1">
                      <button onClick={() => navigate(`/etablissement/missions/${p.mission_id}`)} className="font-medium text-sm text-primary hover:underline text-left">
                        {p.mission_intitule}
                      </button>
                      <p className="text-xs text-muted-foreground">
                        {p.soignant_nom} · {p.soignant_profession} · {p.methode} · Réf: {p.reference_virement}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        Déclaré le {p.date_paiement && new Date(p.date_paiement).toLocaleDateString('fr-FR')}
                      </p>
                    </div>
                    <div className="text-right shrink-0">
                      <p className="font-bold">{fmt(p.montant_net)}</p>
                      <Badge className="bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400">En attente</Badge>
                    </div>
                  </div>
                ))}
              </CardContent>
            </Card>
          </FadeInView>
        )}

        {facturesImpayees.length > 0 && (
          <FadeInView delay={300}>
            <Card id="section-factures-impayees">
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <FileText className="w-5 h-5 text-destructive" />
                  Factures Jolene impayées ({facturesImpayees.length})
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-3">
                {facturesImpayees.map((f: any) => (
                  <div key={f.facture_id} className="p-4 rounded-lg border space-y-3">
                    <div className="flex items-center justify-between gap-3">
                      <div>
                        <p className="font-semibold text-sm">{f.numero_facture}</p>
                        <p className="text-xs text-muted-foreground">
                          {f.nombre_missions} mission(s) · Échéance : {f.date_echeance && new Date(f.date_echeance).toLocaleDateString('fr-FR')}
                        </p>
                      </div>
                      <div className="text-right shrink-0">
                        <p className="font-bold">{fmt(f.montant_ttc)}</p>
                        <p className="text-[10px] text-muted-foreground">{fmt(f.montant_ht)} HT + {fmt(f.montant_tva)} TVA</p>
                      </div>
                    </div>
                    <div className="flex gap-2">
                      <Button size="sm" onClick={() => navigate(`/etablissement/facturation/${f.facture_id}`)}>
                        <CreditCard className="w-4 h-4 mr-1" /> Payer par carte
                      </Button>
                      <Button size="sm" variant="outline" onClick={() => navigate(`/etablissement/facturation?tab=commissions`)}>
                        <Banknote className="w-4 h-4 mr-1" /> Virement
                      </Button>
                    </div>
                  </div>
                ))}
              </CardContent>
            </Card>
          </FadeInView>
        )}

        {paiementsConfirmes.length > 0 && (
          <FadeInView delay={400}>
            <Card id="section-paiements-confirmes">
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <CheckCircle className="w-5 h-5 text-success" />
                  Derniers paiements confirmés ({paiementsConfirmes.length})
                </CardTitle>
              </CardHeader>
              <CardContent>
                <div className="overflow-x-auto">
                  <table className="w-full text-sm">
                    <thead>
                      <tr className="border-b text-left text-muted-foreground">
                        <th className="pb-2 pr-3">Date</th>
                        <th className="pb-2 pr-3">Soignant</th>
                        <th className="pb-2 pr-3">Mission</th>
                        <th className="pb-2 pr-3">Montant</th>
                        <th className="pb-2 pr-3">Réf.</th>
                        <th className="pb-2">Confirmé</th>
                      </tr>
                    </thead>
                    <tbody>
                      {paiementsConfirmes.map((p: any) => (
                        <tr key={p.paiement_id} className="border-b last:border-0">
                          <td className="py-2 pr-3 text-xs">{p.confirme_par_soignant_le && new Date(p.confirme_par_soignant_le).toLocaleDateString('fr-FR')}</td>
                          <td className="py-2 pr-3">{p.soignant_nom}</td>
                          <td className="py-2 pr-3">{p.mission_intitule}</td>
                          <td className="py-2 pr-3 font-medium">{fmt(p.montant_net)}</td>
                          <td className="py-2 pr-3 text-xs text-muted-foreground">{p.reference_virement}</td>
                          <td className="py-2"><Badge className="bg-success/10 text-success">✅</Badge></td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </CardContent>
            </Card>
          </FadeInView>
        )}

        {missionsNonFacturees.length > 0 && (
          <FadeInView delay={500}>
            <Card id="section-commissions-a-venir">
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <FileText className="w-5 h-5 text-muted-foreground" />
                  Commissions à venir ({missionsNonFacturees.length})
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-2">
                <p className="text-xs text-muted-foreground mb-3">Missions terminées pas encore facturées par Jolene</p>
                {missionsNonFacturees.map((m: any) => (
                  <div key={m.mission_id} className="flex items-center justify-between gap-3 p-3 rounded-lg border">
                    <div>
                      <button onClick={() => navigate(`/etablissement/missions/${m.mission_id}`)} className="font-medium text-sm text-primary hover:underline text-left">
                        {m.intitule}
                      </button>
                      <p className="text-xs text-muted-foreground">
                        Terminée le {m.fin_le && new Date(m.fin_le).toLocaleDateString('fr-FR')}
                      </p>
                    </div>
                    <div className="text-right shrink-0">
                      <p className="font-medium text-sm">{fmt(m.montant_commission_ttc)}</p>
                      <p className="text-[10px] text-muted-foreground">{fmt(m.montant_commission_ht)} HT</p>
                    </div>
                  </div>
                ))}
              </CardContent>
            </Card>
          </FadeInView>
        )}
      </div>

      {/* Embedded Stripe Checkout pour paiement mission */}
      {connectClientSecret && (
        <Dialog open={!!connectClientSecret} onOpenChange={(v) => { if (!v) { setConnectClientSecret(null); charger(); } }}>
          <DialogContent className="max-w-[calc(100%-1rem)] sm:max-w-lg max-h-[90vh] overflow-y-auto">
            <DialogHeader>
              <DialogTitle>Paiement mission</DialogTitle>
              <DialogDescription>Réglez les honoraires du soignant et la commission Jolene.</DialogDescription>
            </DialogHeader>
            <EmbeddedCheckoutProvider stripe={stripePromise} options={{ clientSecret: connectClientSecret }}>
              <EmbeddedCheckout />
            </EmbeddedCheckoutProvider>
          </DialogContent>
        </Dialog>
      )}

      {/* [CP-C-1] Dialog déclaration paiement soignant */}
      {declarerDialogMission && (
        <Dialog open={!!declarerDialogMission} onOpenChange={(open) => { if (!open) fermerDialogDeclarer(); }}>
          <DialogContent className="max-w-[calc(100%-1rem)] sm:max-w-lg max-h-[90vh] overflow-y-auto">
            <DialogHeader>
              <DialogTitle>Déclarer un paiement au soignant</DialogTitle>
              <DialogDescription>
                {declarerDialogMission.mission_intitule || 'Mission'} — {declarerDialogMission.soignant_nom || ''}
              </DialogDescription>
            </DialogHeader>

            <div className="space-y-4 py-2">
              <div>
                <Label htmlFor="declarer-montant">Montant payé (€ net)</Label>
                <Input
                  id="declarer-montant"
                  type="number"
                  step="0.01"
                  value={declarerMontant}
                  onChange={(e) => setDeclarerMontant(e.target.value)}
                  placeholder="0.00"
                />
                <p className="text-xs text-muted-foreground mt-1">
                  Montant estimé : {fmt(Number(declarerDialogMission.net_a_payer || 0))}
                </p>
              </div>

              <div>
                <Label htmlFor="declarer-methode">Méthode de paiement</Label>
                <Select
                  value={declarerMethode}
                  onValueChange={(v) => setDeclarerMethode(v as MethodePaiement)}
                >
                  <SelectTrigger id="declarer-methode">
                    <SelectValue placeholder="Choisir une méthode" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="VIREMENT">Virement bancaire</SelectItem>
                    <SelectItem value="CHEQUE">Chèque</SelectItem>
                    <SelectItem value="BULLETIN_PAIE">Bulletin de paie</SelectItem>
                    <SelectItem value="NOTE_HONORAIRES">Note d'honoraires</SelectItem>
                  </SelectContent>
                </Select>
              </div>

              <div>
                <Label htmlFor="declarer-reference">
                  Référence {declarerMethode === 'BULLETIN_PAIE' ? '(optionnelle)' : '(obligatoire, min. 5 car. + 1 chiffre)'}
                </Label>
                <Input
                  id="declarer-reference"
                  value={declarerReference}
                  onChange={(e) => setDeclarerReference(e.target.value)}
                  placeholder={
                    declarerMethode === 'VIREMENT' ? 'Réf. virement bancaire'
                      : declarerMethode === 'CHEQUE' ? 'N° chèque'
                      : declarerMethode === 'BULLETIN_PAIE' ? 'N° bulletin (facultatif)'
                      : 'Réf. note d\'honoraires'
                  }
                />
              </div>

              <div>
                <Label htmlFor="declarer-date">Date du paiement</Label>
                <Input
                  id="declarer-date"
                  type="date"
                  value={declarerDatePaiement}
                  max={new Date().toISOString().split('T')[0]}
                  onChange={(e) => setDeclarerDatePaiement(e.target.value)}
                />
              </div>

              <div className="rounded-lg border border-warning/40 bg-warning/5 p-3">
                <div className="flex items-start gap-2">
                  <Checkbox
                    id="declarer-attestation"
                    checked={declarerAttestation}
                    onCheckedChange={(c) => setDeclarerAttestation(c === true)}
                    className="mt-0.5"
                  />
                  <Label
                    htmlFor="declarer-attestation"
                    className="text-xs text-foreground leading-relaxed cursor-pointer"
                  >
                    <strong>J'atteste sur l'honneur</strong> avoir effectivement payé ce soignant conformément au
                    Code du travail (pour un salarié) ou au Code de commerce (pour un libéral) en contrepartie
                    de la prestation effectuée dans le cadre de cette mission. Cette déclaration m'engage au
                    regard de l'URSSAF et de l'administration fiscale. Une déclaration frauduleuse m'expose à
                    des sanctions pénales (article 441-1 du Code pénal).
                  </Label>
                </div>
              </div>
            </div>

            <DialogFooter className="gap-2">
              <Button variant="outline" onClick={fermerDialogDeclarer}>
                Annuler
              </Button>
              <Button
                onClick={validerDeclarationPaiement}
                disabled={
                  !declarerAttestation ||
                  declaringId === declarerDialogMission.mission_id ||
                  !declarerMontant ||
                  Number(declarerMontant) <= 0 ||
                  (declarerMethode !== 'BULLETIN_PAIE' && !isRefValid(declarerReference))
                }
              >
                {declaringId === declarerDialogMission.mission_id ? 'Envoi…' : 'Valider la déclaration'}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      )}
    </LayoutApp>
  );
}
