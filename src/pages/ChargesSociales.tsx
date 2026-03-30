import { useState, useEffect, useMemo } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { Calculator, Calendar, Shield, Building2, PieChart } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { format, differenceInDays } from 'date-fns';
import { fr } from 'date-fns/locale';
import { PieChart as RechartsPie, Pie, Cell, ResponsiveContainer, Tooltip } from 'recharts';

const TAUX_URSSAF = 0.212; // 21.2% for regulated health professionals
const CARPIMKO_FORFAIT = 1800; // approximate annual fixed contribution
const CARPIMKO_PROPORTIONNEL_TAUX = 0.016; // 1.6% proportional

function getProchainTrimestreURSSAF(): Date {
  const now = new Date();
  const y = now.getFullYear();
  const echeances = [
    new Date(y, 0, 5), // 5 Jan (Q4 previous)
    new Date(y, 3, 5), // 5 Apr (Q1)
    new Date(y, 6, 5), // 5 Jul (Q2)
    new Date(y, 9, 5), // 5 Oct (Q3)
  ];
  const prochaine = echeances.find(d => d > now) || new Date(y + 1, 0, 5);
  return prochaine;
}

function getEcheanceCARPIMKO(): Date {
  const now = new Date();
  const avrilCette = new Date(now.getFullYear(), 3, 1);
  return avrilCette > now ? avrilCette : new Date(now.getFullYear() + 1, 3, 1);
}

function getEcheanceCFE(): Date {
  const now = new Date();
  const decCette = new Date(now.getFullYear(), 11, 15);
  return decCette > now ? decCette : new Date(now.getFullYear() + 1, 11, 15);
}

function Countdown({ date }: { date: Date }) {
  const jours = differenceInDays(date, new Date());
  const color = jours <= 14 ? 'text-destructive' : jours <= 30 ? 'text-warning' : 'text-muted-foreground';
  return (
    <span className={`text-xs font-medium ${color}`}>
      {jours <= 0 ? 'Échue' : `dans ${jours} jour${jours > 1 ? 's' : ''}`}
    </span>
  );
}

const PIE_COLORS = ['hsl(var(--primary))', 'hsl(var(--accent))', 'hsl(var(--destructive))', 'hsl(var(--muted))'];

export default function ChargesSociales() {
  usePageTitle('Mes charges');
  const { user } = useAuth();
  const [loading, setLoading] = useState(true);
  const [caCumule, setCaCumule] = useState(0);
  const [rcpExpiration, setRcpExpiration] = useState<string | null>(null);
  const [soignant, setSoignant] = useState<any>(null);

  useEffect(() => {
    if (!user) return;
    const load = async () => {
      const annee = new Date().getFullYear();
      const debutAnnee = new Date(annee, 0, 1).toISOString();

      const [{ data: missions }, { data: docs }, { data: sg }] = await Promise.all([
        supabase
          .from('missions')
          .select('total_brut')
          .eq('soignant_assigne_id', user.id)
          .eq('statut', 'TERMINEE')
          .gte('fin_le', debutAnnee),
        supabase
          .from('documents_soignants')
          .select('valide_jusqua')
          .eq('soignant_id', user.id)
          .eq('type_document', 'RCP_ASSURANCE')
          .eq('statut_verification', 'VERIFIE')
          .is('supprime_le', null)
          .order('valide_jusqua', { ascending: false })
          .limit(1),
        supabase.from('soignants').select('prenom, nom, profession, statut_liberal, assujetti_tva').eq('id', user.id).single(),
      ]);

      const ca = (missions || []).reduce((s: number, m: any) => s + (m.total_brut || 0), 0);
      setCaCumule(ca);
      if (docs && docs.length > 0) setRcpExpiration(docs[0].valide_jusqua);
      setSoignant(sg);
      setLoading(false);
    };
    load();
  }, [user]);

  const urssaf = useMemo(() => caCumule * TAUX_URSSAF, [caCumule]);
  const carpimkoProportionnel = useMemo(() => caCumule * CARPIMKO_PROPORTIONNEL_TAUX, [caCumule]);
  const carpimkoTotal = useMemo(() => CARPIMKO_FORFAIT + carpimkoProportionnel, [carpimkoProportionnel]);
  const rcpEstime = 400; // Estimated annual RCP cost
  const totalCharges = urssaf + carpimkoTotal + rcpEstime;
  const revenuNet = caCumule - totalCharges;

  const pieData = useMemo(() => [
    { name: 'URSSAF', value: Math.round(urssaf) },
    { name: 'CARPIMKO', value: Math.round(carpimkoTotal) },
    { name: 'RCP', value: rcpEstime },
    { name: 'Revenu net', value: Math.max(0, Math.round(revenuNet)) },
  ], [urssaf, carpimkoTotal, revenuNet]);

  const prochainURSSAF = getProchainTrimestreURSSAF();
  const echeanceCARPIMKO = getEcheanceCARPIMKO();
  const echeanceCFE = getEcheanceCFE();

  if (loading) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role="SOIGNANT">
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
          <Calculator className="h-6 w-6 text-primary" /> Mes charges sociales
        </h1>
        <p className="text-sm text-muted-foreground mt-1">Estimations basées sur votre CA libéral {new Date().getFullYear()}</p>
      </div>

      {/* CA banner */}
      <div className="card-base mb-6 text-center">
        <p className="text-sm text-muted-foreground">Chiffre d'affaires libéral cumulé {new Date().getFullYear()}</p>
        <p className="text-3xl font-bold text-primary mt-1">{caCumule.toFixed(0)} €</p>
      </div>

      {/* Charges cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
        {/* URSSAF */}
        <div className="card-base">
          <div className="flex items-center gap-2 mb-3">
            <div className="rounded-xl p-2 bg-primary/10"><Building2 className="h-5 w-5 text-primary" /></div>
            <div>
              <h3 className="font-semibold text-foreground">URSSAF</h3>
              <p className="text-xs text-muted-foreground">Cotisations sociales trimestrielles</p>
            </div>
          </div>
          <div className="space-y-2">
            <div className="flex justify-between text-sm">
              <span className="text-muted-foreground">Taux applicable</span>
              <span className="font-medium text-foreground">21,2%</span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-muted-foreground">Estimation annuelle</span>
              <span className="font-bold text-foreground">{urssaf.toFixed(0)} €</span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-muted-foreground">Par trimestre (~)</span>
              <span className="font-medium text-foreground">{(urssaf / 4).toFixed(0)} €</span>
            </div>
            <div className="bg-muted/30 rounded-lg p-2 flex items-center justify-between">
              <div className="flex items-center gap-1.5">
                <Calendar className="h-3.5 w-3.5 text-muted-foreground" />
                <span className="text-xs text-muted-foreground">Prochaine échéance : {format(prochainURSSAF, 'd MMM yyyy', { locale: fr })}</span>
              </div>
              <Countdown date={prochainURSSAF} />
            </div>
          </div>
        </div>

        {/* CARPIMKO */}
        <div className="card-base">
          <div className="flex items-center gap-2 mb-3">
            <div className="rounded-xl p-2 bg-accent/10"><Shield className="h-5 w-5 text-accent-foreground" /></div>
            <div>
              <h3 className="font-semibold text-foreground">CARPIMKO</h3>
              <p className="text-xs text-muted-foreground">Caisse de retraite complémentaire</p>
            </div>
          </div>
          <div className="space-y-2">
            <div className="flex justify-between text-sm">
              <span className="text-muted-foreground">Forfait annuel</span>
              <span className="font-medium text-foreground">{CARPIMKO_FORFAIT} €</span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-muted-foreground">Part proportionnelle (1,6%)</span>
              <span className="font-medium text-foreground">{carpimkoProportionnel.toFixed(0)} €</span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-muted-foreground">Total estimé</span>
              <span className="font-bold text-foreground">{carpimkoTotal.toFixed(0)} €</span>
            </div>
            <div className="bg-muted/30 rounded-lg p-2 flex items-center justify-between">
              <div className="flex items-center gap-1.5">
                <Calendar className="h-3.5 w-3.5 text-muted-foreground" />
                <span className="text-xs text-muted-foreground">Échéance : {format(echeanceCARPIMKO, 'd MMM yyyy', { locale: fr })}</span>
              </div>
              <Countdown date={echeanceCARPIMKO} />
            </div>
          </div>
        </div>

        {/* RCP */}
        <div className="card-base">
          <div className="flex items-center gap-2 mb-3">
            <div className="rounded-xl p-2 bg-destructive/10"><Shield className="h-5 w-5 text-destructive" /></div>
            <div>
              <h3 className="font-semibold text-foreground">Assurance RCP</h3>
              <p className="text-xs text-muted-foreground">Responsabilité civile professionnelle</p>
            </div>
          </div>
          <div className="space-y-2">
            {rcpExpiration ? (
              <>
                <div className="flex justify-between text-sm">
                  <span className="text-muted-foreground">Expiration</span>
                  <span className="font-medium text-foreground">{format(new Date(rcpExpiration), 'd MMM yyyy', { locale: fr })}</span>
                </div>
                <div className="bg-muted/30 rounded-lg p-2 flex items-center justify-between">
                  <span className="text-xs text-muted-foreground">Statut</span>
                  {new Date(rcpExpiration) > new Date() ? (
                    <span className="text-xs font-medium text-primary">✅ Valide</span>
                  ) : (
                    <span className="text-xs font-medium text-destructive">❌ Expirée — à renouveler</span>
                  )}
                </div>
              </>
            ) : (
              <p className="text-sm text-destructive">⚠️ Aucune RCP vérifiée. Téléversez votre attestation dans Documents.</p>
            )}
          </div>
        </div>

        {/* CFE */}
        <div className="card-base">
          <div className="flex items-center gap-2 mb-3">
            <div className="rounded-xl p-2 bg-muted"><Building2 className="h-5 w-5 text-muted-foreground" /></div>
            <div>
              <h3 className="font-semibold text-foreground">CFE</h3>
              <p className="text-xs text-muted-foreground">Cotisation foncière des entreprises</p>
            </div>
          </div>
          <div className="space-y-2">
            <p className="text-sm text-muted-foreground">Montant variable selon votre commune. Exonérée la 1ère année.</p>
            <div className="bg-muted/30 rounded-lg p-2 flex items-center justify-between">
              <div className="flex items-center gap-1.5">
                <Calendar className="h-3.5 w-3.5 text-muted-foreground" />
                <span className="text-xs text-muted-foreground">Échéance : {format(echeanceCFE, 'd MMM yyyy', { locale: fr })}</span>
              </div>
              <Countdown date={echeanceCFE} />
            </div>
          </div>
        </div>
      </div>

      {/* Pie chart */}
      {caCumule > 0 && (
        <div className="card-base mb-6">
          <h2 className="text-lg font-bold text-foreground mb-4 flex items-center gap-2">
            <PieChart className="h-5 w-5 text-primary" /> Répartition de votre CA
          </h2>
          <div className="flex flex-col md:flex-row items-center gap-6">
            <ResponsiveContainer width={220} height={220}>
              <RechartsPie>
                <Pie data={pieData} dataKey="value" nameKey="name" cx="50%" cy="50%" innerRadius={50} outerRadius={90} paddingAngle={2}>
                  {pieData.map((_, i) => <Cell key={i} fill={PIE_COLORS[i % PIE_COLORS.length]} />)}
                </Pie>
                <Tooltip
                  contentStyle={{ backgroundColor: 'hsl(var(--card))', border: '1px solid hsl(var(--border))', borderRadius: '8px' }}
                  formatter={(value: number) => [`${value} €`]}
                />
              </RechartsPie>
            </ResponsiveContainer>
            <div className="space-y-2 flex-1">
              {pieData.map((d, i) => (
                <div key={d.name} className="flex items-center justify-between text-sm">
                  <div className="flex items-center gap-2">
                    <div className="w-3 h-3 rounded-full" style={{ backgroundColor: PIE_COLORS[i % PIE_COLORS.length] }} />
                    <span className="text-foreground">{d.name}</span>
                  </div>
                  <span className="font-medium text-foreground">{d.value} € ({caCumule > 0 ? Math.round((d.value / caCumule) * 100) : 0}%)</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      <div className="bg-muted/30 border border-border rounded-xl p-4 text-center">
        <p className="text-sm text-muted-foreground">
          ⚠️ Ces estimations sont indicatives. Consultez votre comptable pour les montants exacts.
        </p>
      </div>
    </LayoutApp>
  );
}