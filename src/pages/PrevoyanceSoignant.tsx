import { useState, useEffect } from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EtatVide } from '@/components/EtatVide';
import { ModalConfirmation } from '@/components/ModalConfirmation';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { ShieldCheck } from 'lucide-react';

function fmt(v: number): string {
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

export default function PrevoyanceSoignant() {
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [plans, setPlans] = useState<any[]>([]);
  const [souscriptions, setSouscriptions] = useState<any[]>([]);
  const [soignant, setSoignant] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [planASouscrire, setPlanASouscrire] = useState<any>(null);

  useEffect(() => {
    if (!user) return;
    Promise.all([
      supabase.from('plans_prevoyance').select('*').eq('est_actif', true).order('prime_mensuelle', { ascending: true }),
      supabase.from('souscriptions_prevoyance').select('*, plans_prevoyance(*)').eq('soignant_id', user.id),
      supabase.from('soignants').select('heures_cumulees, prevoyance_inscrit').eq('id', user.id).single(),
    ]).then(([{ data: p }, { data: s }, { data: sg }]) => {
      setPlans((p as any[]) || []);
      setSouscriptions((s as any[]) || []);
      setSoignant(sg);
      setLoading(false);
    });
  }, [user]);

  async function souscrire(plan: any) {
    if (!user) return;
    const { error } = await supabase.from('souscriptions_prevoyance').insert({
      soignant_id: user.id,
      plan_id: plan.id,
    } as any);
    if (error) { afficherNotification({ type: 'erreur', message: error.message }); return; }

    await supabase.from('soignants').update({
      prevoyance_inscrit: true,
      prevoyance_fournisseur: plan.fournisseur,
      modifie_le: new Date().toISOString(),
    } as any).eq('id', user.id);

    await supabase.rpc('fn_ecrire_audit_safe', {
      p_acteur_id: user.id, p_type_acteur: 'SOIGNANT',
      p_action: 'DONNEES_PERSO_MODIFICATION',
      p_type_ressource: 'soignant', p_id_ressource: user.id,
      p_cle_s3: null,
      p_details: { action: 'souscription_prevoyance', plan: plan.nom },
      p_ip: null, p_navigateur: navigator.userAgent,
    });

    afficherNotification({ type: 'succes', message: `✅ Souscription au plan ${plan.nom} confirmée !` });
    setPlanASouscrire(null);
    // Refresh
    const { data: s } = await supabase.from('souscriptions_prevoyance').select('*, plans_prevoyance(*)').eq('soignant_id', user.id);
    setSouscriptions((s as any[]) || []);
  }

  if (loading) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  const heures = soignant?.heures_cumulees ?? 0;
  const souscrit = souscriptions.some(s => s.statut === 'ACTIF');

  return (
    <LayoutApp role="SOIGNANT">
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground">🛡️ Prévoyance</h1>
        <p className="text-sm text-muted-foreground mt-1">Protégez-vous avec les plans subventionnés Soin Direct</p>
      </div>

      {souscrit && (
        <div className="bg-success/5 border border-success/20 rounded-xl p-4 mb-6 flex items-center gap-3">
          <ShieldCheck className="h-6 w-6 text-success" />
          <div>
            <p className="text-sm font-semibold text-success">Prévoyance active</p>
            <p className="text-xs text-muted-foreground">Vous bénéficiez de +3 points de fiabilité</p>
          </div>
        </div>
      )}

      {plans.length > 0 ? (
        <div className="space-y-4">
          {plans.map(plan => {
            const dejasouscrit = souscriptions.some(s => s.plan_id === plan.id);
            const eligible = heures >= (plan.heures_minimum_requises || 0);
            const subvention = plan.subvention_plateforme_pourcent || 0;
            const coutReel = plan.prime_mensuelle * (1 - subvention / 100);

            return (
              <div key={plan.id} className="card-base">
                <h3 className="text-base font-bold text-foreground mb-1">🛡️ {plan.nom} — {plan.fournisseur}</h3>
                {plan.description && <p className="text-sm text-muted-foreground mb-3">{plan.description}</p>}
                <div className="space-y-1 text-sm mb-4">
                  <p>💰 Prime : <span className="font-semibold">{fmt(plan.prime_mensuelle)}/mois</span></p>
                  {subvention > 0 && (
                    <>
                      <p>🎁 Subvention Soin Direct : <span className="font-semibold text-primary">-{subvention}%</span> (max {fmt(plan.subvention_max_mensuelle || 0)}/mois)</p>
                      <p>→ Votre coût : <span className="font-bold text-foreground">~{fmt(coutReel)}/mois</span></p>
                    </>
                  )}
                  {(plan.heures_minimum_requises || 0) > 0 && (
                    <p className="text-xs text-muted-foreground">Conditions : min. {plan.heures_minimum_requises}h travaillées</p>
                  )}
                </div>

                {dejasouscrit ? (
                  <div className="badge-base bg-success/10 text-success">✅ Souscrit — Actif</div>
                ) : !eligible ? (
                  <div className="badge-base bg-muted text-muted-foreground">🔒 Encore {Math.round((plan.heures_minimum_requises || 0) - heures)}h avant éligibilité</div>
                ) : (
                  <button onClick={() => setPlanASouscrire(plan)} className="btn-primary text-sm">Souscrire</button>
                )}
              </div>
            );
          })}
        </div>
      ) : (
        <EtatVide icone={ShieldCheck} titre="Aucun plan disponible" sousTitre="Les plans de prévoyance seront bientôt disponibles." />
      )}

      {planASouscrire && (
        <ModalConfirmation
          ouvert={true}
          onFermer={() => setPlanASouscrire(null)}
          titre={`Souscrire au plan ${planASouscrire.nom} ?`}
          message={`Vous allez souscrire pour ${fmt(planASouscrire.prime_mensuelle)}/mois. Soin Direct subventionne ${planASouscrire.subvention_plateforme_pourcent || 0}% de la prime. Votre score de fiabilité gagnera +3 points.`}
          labelConfirmer="Confirmer la souscription"
          variante="primaire"
          onConfirmer={() => souscrire(planASouscrire)}
        />
      )}
    </LayoutApp>
  );
}
