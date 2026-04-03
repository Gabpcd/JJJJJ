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
import { AlertTriangle, CheckCircle, CreditCard, Clock, FileText, Users, Banknote, ExternalLink } from 'lucide-react';
import { toast } from 'sonner';

const fmt = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
const isRefValid = (ref: string) => ref.trim().length >= 5 && /\d/.test(ref);

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

  useEffect(() => { charger(); }, [user, etablissementId]);

  const declarer = async (missionId: string) => {
    const ref = declaringRef[missionId] || '';
    if (!isRefValid(ref)) {
      toast.error('La référence doit contenir au moins 5 caractères dont un chiffre.');
      return;
    }
    setDeclaringId(missionId);
    try {
      const { error } = await supabase.rpc('fn_declarer_paiement_soignant' as any, {
        p_mission_id: missionId,
        p_reference_virement: ref.trim(),
      });
      if (error) throw error;
      toast.success('Paiement déclaré avec succès');
      charger();
    } catch (e: any) {
      toast.error(extraireMessageErreur(e));
    } finally {
      setDeclaringId(null);
    }
  };

  const payerStripeConnect = async (missionId: string) => {
    setConnectPayingId(missionId);
    try {
      const { data: result, error } = await supabase.functions.invoke('stripe-connect-pay-mission', {
        body: { mission_id: missionId },
      });
      if (error) throw error;
      if (result?.url) window.location.href = result.url;
    } catch (e: any) {
      toast.error(extraireMessageErreur(e));
    } finally {
      setConnectPayingId(null);
    }
  };

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><SkeletonDashboard /></LayoutApp>;

  // All clear state
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
        <EtatVide titre="Erreur de chargement" message="Impossible de charger vos obligations financières." />
      </LayoutApp>
    );
  }

  const missionsNonPayees = data.missions_non_payees || [];
  const paiementsEnAttente = data.paiements_soignants_en_attente || [];
  const paiementsConfirmes = data.paiements_soignants_confirmes || [];
  const facturesImpayees = data.factures_impayees || [];
  const missionsNonFacturees = data.missions_non_facturees || [];

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <div className="space-y-6">
        {/* Header */}
        <div>
          <h1 className="text-2xl font-bold">💰 Mes obligations financières</h1>
          <p className="text-muted-foreground">Récapitulatif de tous vos paiements en attente</p>
        </div>

        {/* Summary cards */}
        <FadeInView>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <Card className={`border-2 ${data.total_du > 0 ? 'border-destructive/30 bg-destructive/5' : 'border-success/30 bg-success/5'}`}>
              <CardContent className="pt-6 text-center">
                <p className="text-3xl font-bold">{fmt(data.total_du)}</p>
                <p className="text-sm text-muted-foreground mt-1">🔴 Total dû</p>
              </CardContent>
            </Card>
            <Card>
              <CardContent className="pt-6 text-center">
                <p className="text-2xl font-bold">{fmt(data.total_soignants_du)}</p>
                <p className="text-sm text-muted-foreground mt-1">👩‍⚕️ Soignants · {data.nb_missions_non_payees} mission(s)</p>
              </CardContent>
            </Card>
            <Card>
              <CardContent className="pt-6 text-center">
                <p className="text-2xl font-bold">{fmt(data.total_commissions_du)}</p>
                <p className="text-sm text-muted-foreground mt-1">📄 Commission Jolene · {data.nb_factures_impayees} facture(s)</p>
              </CardContent>
            </Card>
          </div>
        </FadeInView>

        {/* Section 1: Missions à payer */}
        {missionsNonPayees.length > 0 && (
          <FadeInView delay={100}>
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <AlertTriangle className="w-5 h-5 text-warning" />
                  Missions à payer aux soignants ({missionsNonPayees.length})
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-3">
                {missionsNonPayees.map((m: any) => (
                  <div key={m.mission_id} className="p-4 rounded-lg border space-y-3">
                    <div className="flex items-start justify-between gap-3">
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 flex-wrap">
                          <button onClick={() => navigate(`/etablissement/missions/${m.mission_id}`)} className="font-semibold text-sm text-primary hover:underline text-left">
                            {m.intitule}
                          </button>
                          <TypeExerciceBadge type={m.soignant_type_exercice} />
                          <RetardBadge jours={m.jours_depuis_fin} />
                        </div>
                        <p className="text-xs text-muted-foreground mt-1">
                          {m.soignant_nom} · {m.soignant_profession} · {Math.round(m.heures || 0)}h
                        </p>
                        <p className="text-xs text-muted-foreground">
                          {m.debut_le && new Date(m.debut_le).toLocaleDateString('fr-FR')} → {m.fin_le && new Date(m.fin_le).toLocaleDateString('fr-FR')}
                        </p>
                      </div>
                      <div className="text-right shrink-0">
                        <p className="font-bold">{fmt(m.net_a_payer)}</p>
                        {m.montant_commission_ttc > 0 && (
                          <p className="text-[10px] text-muted-foreground">+ {fmt(m.montant_commission_ttc)} com.</p>
                        )}
                      </div>
                    </div>

                    {/* Action: Stripe Connect or manual */}
                    {m.soignant_stripe_connect ? (
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
                      <div className="flex items-center gap-2">
                        <Input
                          placeholder="Référence virement (min. 5 car.)"
                          value={declaringRef[m.mission_id] || ''}
                          onChange={(e) => setDeclaringRef(prev => ({ ...prev, [m.mission_id]: e.target.value }))}
                          className="text-sm"
                        />
                        <Button
                          size="sm"
                          onClick={() => declarer(m.mission_id)}
                          disabled={declaringId === m.mission_id || !isRefValid(declaringRef[m.mission_id] || '')}
                        >
                          {declaringId === m.mission_id ? '…' : 'Déclarer'}
                        </Button>
                      </div>
                    )}
                  </div>
                ))}
              </CardContent>
            </Card>
          </FadeInView>
        )}

        {/* Section 2: Paiements en attente de confirmation */}
        {paiementsEnAttente.length > 0 && (
          <FadeInView delay={200}>
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <Clock className="w-5 h-5 text-amber-500" />
                  Paiements en attente de confirmation ({paiementsEnAttente.length})
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-3">
                {paiementsEnAttente.map((p: any) => (
                  <div key={p.paiement_id} className="flex items-center justify-between p-3 rounded-lg border">
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

        {/* Section 3: Factures Jolene impayées */}
        {facturesImpayees.length > 0 && (
          <FadeInView delay={300}>
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <FileText className="w-5 h-5 text-destructive" />
                  Factures Jolene impayées ({facturesImpayees.length})
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-3">
                {facturesImpayees.map((f: any) => (
                  <div key={f.facture_id} className="p-4 rounded-lg border space-y-3">
                    <div className="flex items-center justify-between">
                      <div>
                        <p className="font-semibold text-sm">{f.numero_facture}</p>
                        <p className="text-xs text-muted-foreground">
                          {f.nombre_missions} mission(s) · Échéance : {f.date_echeance && new Date(f.date_echeance).toLocaleDateString('fr-FR')}
                        </p>
                      </div>
                      <div className="text-right">
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

        {/* Section 4: Derniers paiements confirmés */}
        {paiementsConfirmes.length > 0 && (
          <FadeInView delay={400}>
            <Card>
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

        {/* Section 5: Commissions à venir */}
        {missionsNonFacturees.length > 0 && (
          <FadeInView delay={500}>
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <FileText className="w-5 h-5 text-muted-foreground" />
                  Commissions à venir ({missionsNonFacturees.length})
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-2">
                <p className="text-xs text-muted-foreground mb-3">Missions terminées pas encore facturées par Jolene</p>
                {missionsNonFacturees.map((m: any) => (
                  <div key={m.mission_id} className="flex items-center justify-between p-3 rounded-lg border">
                    <div>
                      <button onClick={() => navigate(`/etablissement/missions/${m.mission_id}`)} className="font-medium text-sm text-primary hover:underline text-left">
                        {m.intitule}
                      </button>
                      <p className="text-xs text-muted-foreground">
                        Terminée le {m.fin_le && new Date(m.fin_le).toLocaleDateString('fr-FR')}
                      </p>
                    </div>
                    <div className="text-right">
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
    </LayoutApp>
  );
}
