import { useState, useEffect, useId, useMemo } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { CardY2K, CardY2KHeader, CardY2KTitle, CardY2KContent } from '@/components/y2k/CardY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Calculator, TrendingUp, Target, RefreshCw, Sparkles, Info } from 'lucide-react';
import { AreaChart, Area, LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, ReferenceLine, Legend } from 'recharts';

const fmt = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 }).format(isFinite(v) ? v : 0);
const fmtK = (v: number) => Math.abs(v) >= 1000 ? `${(v / 1000).toFixed(0)}k` : String(Math.round(v));

const CHARGES_FIXES_DEFAUT = 73; // Supabase 25 + Resend 20 + Lovable 20 + Apple 8

const HORIZON_MOIS = 36;

interface Inputs {
  mrr: number;
  clientsActifs: number;
  arpu: number;
  croissanceOrganique: number; // % mensuel
  churn: number;               // % mensuel
  chargesFixes: number;
  coutEquipe: number;
  cac: number;
  budgetMarketing: number;     // €/mois
  coutRecrutements: number;    // €/mois (coût total chargé des futurs recrutements)
  runwayCible: number;         // mois
  buffer: number;              // %
}

function ChampNombre({ label, value, onChange, suffix, aide }: { label: string; value: number; onChange: (v: number) => void; suffix?: string; aide?: string }) {
  const inputId = useId();
  return (
    <div>
      <Label htmlFor={inputId} className="text-xs flex items-center gap-1">
        {label}{suffix ? <span className="text-muted-foreground">({suffix})</span> : null}
        {aide ? <span title={aide}><Info className="h-3 w-3 text-muted-foreground" /></span> : null}
      </Label>
      <Input
        id={inputId}
        type="number"
        value={Number.isFinite(value) ? value : 0}
        onChange={e => onChange(Number(e.target.value))}
        className="h-9"
      />
    </div>
  );
}

export function SimulateurLevee() {
  const [loading, setLoading] = useState(true);
  const [inputs, setInputs] = useState<Inputs>({
    mrr: 0, clientsActifs: 0, arpu: 0, croissanceOrganique: 5, churn: 3,
    chargesFixes: CHARGES_FIXES_DEFAUT, coutEquipe: 0, cac: 0,
    budgetMarketing: 0, coutRecrutements: 0, runwayCible: 18, buffer: 20,
  });

  // Pré-remplissage depuis les métriques temps réel
  const charger = async () => {
    setLoading(true);
    const { data } = await supabase.rpc('fn_admin_cockpit_fondateur' as any);
    if (data) {
      const d = data as any;
      const clients = d.total_etabs || 0;
      const mrr = d.revenue_mois || (d.revenue_total && d.revenue_mensuel?.length ? d.revenue_total / d.revenue_mensuel.length : 0);
      const arpu = clients > 0 ? mrr / clients : 0;
      setInputs(prev => ({
        ...prev,
        mrr: Math.round(mrr),
        clientsActifs: clients,
        arpu: Math.round(arpu),
        coutEquipe: Math.round(d.charges_equipe_mensuel || 0),
      }));
    }
    setLoading(false);
  };

  useEffect(() => { charger(); }, []);

  const set = (k: keyof Inputs) => (v: number) => setInputs(prev => ({ ...prev, [k]: v }));

  // ─── Simulation mois par mois ───
  const sim = useMemo(() => {
    const { mrr, clientsActifs, arpu, croissanceOrganique, churn, chargesFixes, coutEquipe, cac, budgetMarketing, coutRecrutements, runwayCible, buffer } = inputs;

    let clients = clientsActifs;
    let cumul = 0;
    let trough = 0;            // point bas de trésorerie cumulée
    let breakeven = -1;        // 1er mois net positif
    const courbe: { mois: string; tresorerie: number; mrr: number; charges: number }[] = [];

    const arpuEffectif = arpu > 0 ? arpu : (clientsActifs > 0 ? mrr / clientsActifs : 0);

    for (let m = 1; m <= HORIZON_MOIS; m++) {
      const nouveauxMarketing = cac > 0 ? budgetMarketing / cac : 0;
      const nouveauxOrganique = clients * (croissanceOrganique / 100);
      const churned = clients * (churn / 100);
      clients = Math.max(0, clients + nouveauxMarketing + nouveauxOrganique - churned);

      const mrr_m = clients * arpuEffectif;
      const charges_m = chargesFixes + coutEquipe + coutRecrutements + budgetMarketing;
      const net_m = mrr_m - charges_m;
      cumul += net_m;
      if (cumul < trough) trough = cumul;
      if (breakeven === -1 && net_m >= 0) breakeven = m;

      courbe.push({ mois: `M${m}`, tresorerie: Math.round(cumul), mrr: Math.round(mrr_m), charges: Math.round(charges_m) });
    }

    const besoinNet = Math.max(0, -trough);
    const montantALever = besoinNet * (1 + buffer / 100);

    // Unit economics
    const ltv = churn > 0 ? arpuEffectif / (churn / 100) : 0; // LTV = ARPU / churn
    const ltvCac = cac > 0 ? ltv / cac : Infinity;
    const paybackMois = cac > 0 && arpuEffectif > 0 ? cac / arpuEffectif : 0;

    // Runway actuel sans lever (burn mensuel initial)
    const burnInitial = (chargesFixes + coutEquipe + coutRecrutements + budgetMarketing) - mrr;

    return { courbe, trough, besoinNet, montantALever, breakeven, ltv, ltvCac, paybackMois, burnInitial, arpuEffectif, clientsFinaux: Math.round(clients) };
  }, [inputs]);

  // ─── Stratégie d'allocation recommandée ───
  const strategie = useMemo(() => {
    const { ltvCac } = sim;
    let profil: { titre: string; variant: 'success' | 'warning' | 'error' | 'info'; conseil: string; alloc: { poste: string; pct: number }[] };

    if (inputs.cac === 0) {
      profil = {
        titre: '100% organique',
        variant: 'info',
        conseil: "Tu n'as pas encore de coût d'acquisition. Renseigne un CAC test (ex. 150 €) pour voir si tu peux accélérer la croissance avec du budget marketing.",
        alloc: [{ poste: 'Produit & Tech', pct: 40 }, { poste: 'Recrutements', pct: 30 }, { poste: 'Test acquisition', pct: 15 }, { poste: 'Buffer / Ops', pct: 15 }],
      };
    } else if (ltvCac >= 3) {
      profil = {
        titre: `Acquisition très rentable (LTV/CAC ${ltvCac.toFixed(1)}x)`,
        variant: 'success',
        conseil: "Chaque euro de marketing rapporte largement. Alloue agressivement à l'acquisition : tu transformes la levée en croissance directe du MRR.",
        alloc: [{ poste: 'Marketing / Acquisition', pct: 45 }, { poste: 'Recrutements', pct: 25 }, { poste: 'Produit & Tech', pct: 20 }, { poste: 'Buffer / Ops', pct: 10 }],
      };
    } else if (ltvCac >= 1) {
      profil = {
        titre: `Acquisition viable (LTV/CAC ${ltvCac.toFixed(1)}x)`,
        variant: 'warning',
        conseil: "L'acquisition est rentable mais à optimiser (baisser le CAC ou augmenter l'ARPU/rétention). Équilibre marketing et produit.",
        alloc: [{ poste: 'Marketing / Acquisition', pct: 25 }, { poste: 'Recrutements', pct: 30 }, { poste: 'Produit & Tech', pct: 30 }, { poste: 'Buffer / Ops', pct: 15 }],
      };
    } else {
      profil = {
        titre: `Acquisition déficitaire (LTV/CAC ${ltvCac.toFixed(1)}x)`,
        variant: 'error',
        conseil: "Tu perds de l'argent à chaque acquisition. Réduis le marketing, concentre la levée sur le produit et la rétention (baisser le churn) avant de scaler.",
        alloc: [{ poste: 'Produit & Rétention', pct: 45 }, { poste: 'Recrutements', pct: 25 }, { poste: 'Marketing (réduit)', pct: 10 }, { poste: 'Buffer / Ops', pct: 20 }],
      };
    }
    return profil;
  }, [sim, inputs.cac]);

  if (loading) {
    return <div className="flex items-center justify-center py-12"><RefreshCw className="h-6 w-6 animate-spin text-primary" /></div>;
  }

  return (
    <div className="space-y-6">
      {/* Résultat principal */}
      <CardY2K hoverLift={false} className="bg-gradient-hero text-white">
        <div className="p-6 text-center">
          <p className="text-sm opacity-80 flex items-center justify-center gap-2"><Target className="h-4 w-4" /> Montant à lever recommandé</p>
          <p className="text-4xl font-bold my-2">{fmt(sim.montantALever)}</p>
          <p className="text-xs opacity-80">
            Couvre {inputs.runwayCible} mois cible · besoin net {fmt(sim.besoinNet)} + buffer {inputs.buffer}%
            {sim.breakeven > 0 ? ` · breakeven projeté à M${sim.breakeven}` : ' · pas de breakeven sur 36 mois aux paramètres actuels'}
          </p>
        </div>
      </CardY2K>

      {/* Métriques dérivées temps réel */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <div className="rounded-lg border p-3">
          <p className="text-[11px] text-muted-foreground">Burn mensuel actuel</p>
          <p className="text-base font-bold text-foreground">{fmt(sim.burnInitial)}</p>
        </div>
        <div className="rounded-lg border p-3">
          <p className="text-[11px] text-muted-foreground">LTV (ARPU / churn)</p>
          <p className="text-base font-bold text-foreground">{fmt(sim.ltv)}</p>
        </div>
        <div className="rounded-lg border p-3">
          <p className="text-[11px] text-muted-foreground">LTV / CAC</p>
          <p className="text-base font-bold text-foreground">{isFinite(sim.ltvCac) ? `${sim.ltvCac.toFixed(1)}x` : '∞'}</p>
        </div>
        <div className="rounded-lg border p-3">
          <p className="text-[11px] text-muted-foreground">Payback CAC</p>
          <p className="text-base font-bold text-foreground">{sim.paybackMois > 0 ? `${sim.paybackMois.toFixed(1)} mois` : '—'}</p>
        </div>
      </div>

      {/* Inputs éditables */}
      <CardY2K hoverLift={false}>
        <CardY2KHeader>
          <div className="flex items-center justify-between w-full">
            <CardY2KTitle className="text-sm flex items-center gap-2"><Calculator className="h-4 w-4" /> Hypothèses (toutes modifiables)</CardY2KTitle>
            <button onClick={charger} className="text-xs text-muted-foreground hover:text-foreground inline-flex items-center gap-1">
              <RefreshCw className="h-3 w-3" /> Re-synchroniser
            </button>
          </div>
        </CardY2KHeader>
        <CardY2KContent>
          <div className="mb-3">
            <p className="text-[11px] text-muted-foreground">Pré-rempli avec tes données temps réel. Modifie n'importe quelle valeur → le montant à lever se recalcule instantanément.</p>
          </div>
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
            <ChampNombre label="MRR actuel" suffix="€" value={inputs.mrr} onChange={set('mrr')} />
            <ChampNombre label="Clients actifs" value={inputs.clientsActifs} onChange={set('clientsActifs')} />
            <ChampNombre label="ARPU" suffix="€/mois" value={inputs.arpu} onChange={set('arpu')} aide="Revenu moyen par client par mois" />
            <ChampNombre label="Croissance organique" suffix="%/mois" value={inputs.croissanceOrganique} onChange={set('croissanceOrganique')} />
            <ChampNombre label="Churn" suffix="%/mois" value={inputs.churn} onChange={set('churn')} />
            <ChampNombre label="Charges fixes" suffix="€/mois" value={inputs.chargesFixes} onChange={set('chargesFixes')} />
            <ChampNombre label="Coût équipe" suffix="€/mois" value={inputs.coutEquipe} onChange={set('coutEquipe')} aide="Salaires chargés actuels" />
            <ChampNombre label="CAC" suffix="€" value={inputs.cac} onChange={set('cac')} aide="Coût d'acquisition par client" />
            <ChampNombre label="Budget marketing" suffix="€/mois" value={inputs.budgetMarketing} onChange={set('budgetMarketing')} aide="Acquiert budget/CAC nouveaux clients/mois" />
            <ChampNombre label="Coût recrutements" suffix="€/mois" value={inputs.coutRecrutements} onChange={set('coutRecrutements')} aide="Coût chargé des futurs recrutements" />
            <ChampNombre label="Runway cible" suffix="mois" value={inputs.runwayCible} onChange={set('runwayCible')} />
            <ChampNombre label="Buffer sécurité" suffix="%" value={inputs.buffer} onChange={set('buffer')} />
          </div>
        </CardY2KContent>
      </CardY2K>

      {/* Stratégie recommandée */}
      <CardY2K hoverLift={false}>
        <CardY2KHeader>
          <CardY2KTitle className="text-sm flex items-center gap-2"><Sparkles className="h-4 w-4" /> Stratégie d'allocation recommandée</CardY2KTitle>
        </CardY2KHeader>
        <CardY2KContent>
          <div className="flex items-center gap-2 mb-2 flex-wrap">
            <BadgeY2K variant={strategie.variant}>{strategie.titre}</BadgeY2K>
          </div>
          <p className="text-sm text-muted-foreground mb-4">{strategie.conseil}</p>
          <div className="space-y-2">
            {strategie.alloc.map(a => (
              <div key={a.poste}>
                <div className="flex justify-between text-xs mb-1">
                  <span className="text-foreground">{a.poste}</span>
                  <span className="text-muted-foreground">{a.pct}% · {fmt(sim.montantALever * a.pct / 100)}</span>
                </div>
                <div className="h-2 rounded-full bg-muted overflow-hidden">
                  <div className="h-full bg-gradient-hero" style={{ width: `${a.pct}%` }} />
                </div>
              </div>
            ))}
          </div>
        </CardY2KContent>
      </CardY2K>

      {/* Courbe de trésorerie projetée */}
      <CardY2K hoverLift={false}>
        <CardY2KHeader>
          <CardY2KTitle className="text-sm flex items-center gap-2"><TrendingUp className="h-4 w-4" /> Trésorerie cumulée projetée (36 mois)</CardY2KTitle>
        </CardY2KHeader>
        <CardY2KContent>
          <ResponsiveContainer width="100%" height={240}>
            <AreaChart data={sim.courbe}>
              <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
              <XAxis dataKey="mois" tick={{ fontSize: 10 }} interval={2} />
              <YAxis tick={{ fontSize: 10 }} tickFormatter={fmtK} />
              <Tooltip formatter={(v: number) => fmt(v)} />
              <ReferenceLine y={0} stroke="hsl(var(--destructive))" strokeDasharray="4 4" />
              <Area dataKey="tresorerie" name="Trésorerie cumulée" stroke="hsl(var(--primary))" fill="hsl(var(--primary))" fillOpacity={0.2} />
            </AreaChart>
          </ResponsiveContainer>
          <p className="text-[11px] text-muted-foreground mt-2">
            Le point le plus bas ({fmt(sim.trough)}) = trésorerie maximale consommée. C'est ce qu'il faut couvrir avec la levée (+ buffer).
            En M36 : {sim.clientsFinaux} clients projetés.
          </p>
        </CardY2KContent>
      </CardY2K>

      {/* MRR vs charges projeté */}
      <CardY2K hoverLift={false}>
        <CardY2KHeader>
          <CardY2KTitle className="text-sm">MRR vs Charges projetés</CardY2KTitle>
        </CardY2KHeader>
        <CardY2KContent>
          <ResponsiveContainer width="100%" height={220}>
            <LineChart data={sim.courbe}>
              <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
              <XAxis dataKey="mois" tick={{ fontSize: 10 }} interval={2} />
              <YAxis tick={{ fontSize: 10 }} tickFormatter={fmtK} />
              <Tooltip formatter={(v: number) => fmt(v)} />
              <Legend />
              <Line dataKey="mrr" name="MRR" stroke="hsl(var(--primary))" dot={false} strokeWidth={2} />
              <Line dataKey="charges" name="Charges" stroke="hsl(var(--destructive))" dot={false} strokeWidth={2} />
            </LineChart>
          </ResponsiveContainer>
        </CardY2KContent>
      </CardY2K>
    </div>
  );
}
