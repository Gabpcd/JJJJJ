import { useCallback, useEffect, useMemo, useState } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementAdmin } from '@/components/admin/ChargementAdmin';
import { supabase } from '@/integrations/supabase/client';
import { CarteKPIY2K } from '@/components/y2k/CarteKPIY2K';
import { CardY2K, CardY2KHeader, CardY2KTitle, CardY2KContent } from '@/components/y2k/CardY2K';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { Input } from '@/components/ui/input';
import { Users, Building2, Megaphone, RefreshCw, TrendingUp, Info, Save } from 'lucide-react';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend, PieChart, Pie, Cell } from 'recharts';
import { AdminAcquisitionRadar } from '@/components/admin/AdminAcquisitionRadar';
import { toast } from 'sonner';

const fmt = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 }).format(isFinite(v) ? v : 0);

const COULEURS_CANAL: Record<string, string> = {
  PARRAINAGE: '#E91E8C', SOCIAL: '#9B5DE5', PAID: '#F15BB5', SEO: '#00BBF9',
  EMAIL: '#00F5D4', CAMPAGNE: '#FEE440', REFERRAL: '#FF99C8', DIRECT: '#A0A0B0',
};
const LIBELLE_CANAL: Record<string, string> = {
  PARRAINAGE: 'Parrainage', SOCIAL: 'Réseaux sociaux', PAID: 'Publicité payante',
  SEO: 'Recherche (SEO)', EMAIL: 'Email', CAMPAGNE: 'Campagne (UTM)',
  REFERRAL: 'Site référent', DIRECT: 'Direct',
};

function couleur(canal: string) { return COULEURS_CANAL[canal] || '#A0A0B0'; }
function libelle(canal: string) { return LIBELLE_CANAL[canal] || canal; }

export default function AdminAcquisition() {
  usePageTitle('Acquisition');
  const [loading, setLoading] = useState(true);
  const [data, setData] = useState<any>(null);
  const [periode, setPeriode] = useState(90);
  // Dépense pub par canal (saisie manuelle) → CAC réel
  const [depenses, setDepenses] = useState<Record<string, number>>({});
  const [savingCanal, setSavingCanal] = useState<string | null>(null);

  const charger = useCallback(async () => {
    setLoading(true);
    const debut = new Date();
    debut.setDate(debut.getDate() - periode);
    const [canauxResultat, depensesResultat] = await Promise.all([
      supabase.rpc('fn_admin_acquisition_canaux' as never, { p_jours: periode } as never),
      supabase.from('acquisition_depenses' as any)
        .select('canal, montant_ht')
        .gte('periode_fin', debut.toISOString().slice(0, 10)),
    ]);
    const res = canauxResultat.data;
    if (res) setData(res);
    if (!depensesResultat.error) {
      const parCanal = ((depensesResultat.data || []) as unknown as Array<{ canal: string; montant_ht: number }>).reduce<Record<string, number>>(
        (acc, ligne) => {
          const cle = ligne.canal.toUpperCase();
          acc[cle] = (acc[cle] || 0) + Number(ligne.montant_ht || 0);
          return acc;
        },
        {},
      );
      setDepenses(parCanal);
    }
    setLoading(false);
  }, [periode]);

  useEffect(() => { void charger(); }, [charger]);

  const enregistrerDepense = async (canal: string) => {
    const cle = canal.toUpperCase();
    const fin = new Date();
    const debut = new Date(fin);
    debut.setDate(debut.getDate() - periode);
    setSavingCanal(cle);
    const { error } = await supabase.rpc('fn_admin_acquisition_enregistrer_depense' as never, {
      p_canal: cle,
      p_campagne: '',
      p_periode_debut: debut.toISOString().slice(0, 10),
      p_periode_fin: fin.toISOString().slice(0, 10),
      p_montant_ht: depenses[cle] || 0,
      p_notes: `Saisie admin — fenêtre ${periode} jours`,
    } as never);
    setSavingCanal(null);
    if (error) {
      toast.error(`Dépense non enregistrée : ${error.message}`);
      return;
    }
    toast.success(`Dépense ${libelle(cle)} enregistrée.`);
  };

  const canaux = useMemo(() => (data?.par_canal || []) as any[], [data]);
  const campagnes = useMemo(() => (data?.par_campagne || []) as any[], [data]);

  const totalInscriptions = useMemo(
    () => canaux.reduce((s, c) => s + (c.soignants || 0) + (c.etablissements || 0), 0),
    [canaux],
  );

  if (loading) return <LayoutAdmin><ChargementAdmin titre="Acquisition par canal" /></LayoutAdmin>;

  return (
    <LayoutAdmin>
      <div className="space-y-6">
        <AdminAcquisitionRadar />

        <div className="border-t border-border pt-6">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div>
            <h1 className="text-xl font-bold text-foreground">Attribution et coût d’acquisition</h1>
            <p className="text-sm text-muted-foreground">D'où viennent vos inscrits — {periode} derniers jours</p>
          </div>
          <div className="flex gap-2">
            {[30, 90, 180, 365].map(j => (
              <BoutonY2K key={j} size="sm" variant={periode === j ? 'primary' : 'secondary'} onClick={() => setPeriode(j)}>
                {j}j
              </BoutonY2K>
            ))}
            <BoutonY2K variant="ghost" size="sm" onClick={charger} iconeGauche={<RefreshCw className="h-4 w-4" />} aria-label="Rafraîchir" />
          </div>
        </div>

        {/* KPIs */}
        <div className="grid grid-cols-2 lg:grid-cols-3 gap-4">
          <CarteKPIY2K icone={<Users className="h-4 w-4" />} valeur={data?.total_soignants ?? 0} label="Soignants inscrits" variant="holographic" />
          <CarteKPIY2K icone={<Building2 className="h-4 w-4" />} valeur={data?.total_etabs ?? 0} label="Établissements inscrits" variant="default" />
          <CarteKPIY2K icone={<Megaphone className="h-4 w-4" />} valeur={canaux.length} label="Canaux actifs" variant="default" />
        </div>

        {totalInscriptions === 0 ? (
          <CardY2K hoverLift={false}>
            <CardY2KContent>
              <div className="text-center py-8">
                <Megaphone className="h-8 w-8 text-muted-foreground mx-auto mb-2" />
                <p className="text-sm text-muted-foreground">Aucune inscription sur la période.</p>
                <p className="text-xs text-muted-foreground mt-1">
                  Dès le lancement, chaque inscription sera attribuée à son canal (UTM, parrainage, réseaux, SEO…).
                  Partagez vos liens avec des paramètres de suivi pour identifier vos campagnes.
                </p>
              </div>
            </CardY2KContent>
          </CardY2K>
        ) : (
          <>
            {/* Répartition par canal */}
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
              <CardY2K hoverLift={false}>
                <CardY2KHeader><CardY2KTitle className="text-sm">Inscriptions par canal</CardY2KTitle></CardY2KHeader>
                <CardY2KContent>
                  <ResponsiveContainer width="100%" height={260}>
                    <BarChart data={canaux} layout="vertical" margin={{ left: 20 }}>
                      <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
                      <XAxis type="number" tick={{ fontSize: 11 }} />
                      <YAxis type="category" dataKey="canal" tickFormatter={libelle} tick={{ fontSize: 11 }} width={90} />
                      <Tooltip formatter={(v: number, n: string) => [v, n === 'soignants' ? 'Soignants' : 'Établissements']} labelFormatter={libelle} />
                      <Legend formatter={(v) => v === 'soignants' ? 'Soignants' : 'Établissements'} />
                      <Bar dataKey="soignants" stackId="a" fill="hsl(var(--primary))" radius={[0, 0, 0, 0]} />
                      <Bar dataKey="etablissements" stackId="a" fill="#9B5DE5" radius={[0, 4, 4, 0]} />
                    </BarChart>
                  </ResponsiveContainer>
                </CardY2KContent>
              </CardY2K>

              <CardY2K hoverLift={false}>
                <CardY2KHeader><CardY2KTitle className="text-sm">Part de chaque canal</CardY2KTitle></CardY2KHeader>
                <CardY2KContent>
                  <ResponsiveContainer width="100%" height={260}>
                    <PieChart>
                      <Pie
                        data={canaux.map(c => ({ name: libelle(c.canal), value: (c.soignants || 0) + (c.etablissements || 0), canal: c.canal }))}
                        dataKey="value" nameKey="name" cx="50%" cy="50%" outerRadius={90}
                        label={(e: any) => `${e.name} (${e.value})`}
                      >
                        {canaux.map((c, i) => <Cell key={i} fill={couleur(c.canal)} />)}
                      </Pie>
                      <Tooltip />
                    </PieChart>
                  </ResponsiveContainer>
                </CardY2KContent>
              </CardY2K>
            </div>

            {/* Tableau canal + CAC (dépense éditable) */}
            <CardY2K hoverLift={false}>
              <CardY2KHeader>
                <CardY2KTitle className="text-sm flex items-center gap-2">
                  <TrendingUp className="h-4 w-4" /> Détail + CAC par canal
                  <span title="Saisissez la dépense pub d'un canal pour calculer son coût d'acquisition réel"><Info className="h-3 w-3 text-muted-foreground" /></span>
                </CardY2KTitle>
              </CardY2KHeader>
              <CardY2KContent>
                <div className="overflow-x-auto">
                  <table className="w-full text-sm">
                    <thead>
                      <tr className="text-left text-xs text-muted-foreground border-b">
                        <th className="py-2 pr-3">Canal</th>
                        <th className="py-2 px-2 text-right">Soignants</th>
                        <th className="py-2 px-2 text-right">Établ.</th>
                        <th className="py-2 px-2 text-right">Activés</th>
                        <th className="py-2 px-2 text-right">Dépense (€)</th>
                        <th className="py-2 pl-2 text-right">CAC</th>
                        <th className="py-2 pl-2"><span className="sr-only">Enregistrer</span></th>
                      </tr>
                    </thead>
                    <tbody>
                      {canaux.map((c) => {
                        const inscrits = (c.soignants || 0) + (c.etablissements || 0);
                        const canalCle = String(c.canal).toUpperCase();
                        const depense = depenses[canalCle] || 0;
                        const cac = depense > 0 && inscrits > 0 ? depense / inscrits : 0;
                        const tauxActiv = c.soignants > 0 ? Math.round((c.soignants_actifs / c.soignants) * 100) : 0;
                        return (
                          <tr key={c.canal} className="border-b last:border-0">
                            <td className="py-2 pr-3">
                              <span className="inline-flex items-center gap-2">
                                <span className="h-2.5 w-2.5 rounded-full" style={{ background: couleur(c.canal) }} />
                                {libelle(c.canal)}
                              </span>
                            </td>
                            <td className="py-2 px-2 text-right">{c.soignants || 0}</td>
                            <td className="py-2 px-2 text-right">{c.etablissements || 0}</td>
                            <td className="py-2 px-2 text-right">{c.soignants_actifs || 0} <span className="text-[10px] text-muted-foreground">({tauxActiv}%)</span></td>
                            <td className="py-2 px-2 text-right">
                              <Input
                                aria-label={`Dépense publicitaire pour le canal ${libelle(c.canal)}`}
                                type="number"
                                min="0"
                                step="0.01"
                                value={depenses[canalCle] ?? ''}
                                onChange={e => setDepenses(prev => ({ ...prev, [canalCle]: Number(e.target.value) }))}
                                className="h-8 w-24 ml-auto text-right"
                                placeholder="0"
                              />
                            </td>
                            <td className="py-2 pl-2 text-right font-semibold">{cac > 0 ? fmt(cac) : '—'}</td>
                            <td className="py-2 pl-2">
                              <BoutonY2K
                                size="sm"
                                variant="ghost"
                                aria-label={`Enregistrer la dépense du canal ${libelle(c.canal)}`}
                                disabled={savingCanal === canalCle}
                                onClick={() => void enregistrerDepense(canalCle)}
                              >
                                <Save className="h-4 w-4" />
                              </BoutonY2K>
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
                <p className="text-[11px] text-muted-foreground mt-2">
                  Le CAC se calcule = dépense saisie ÷ inscrits du canal. « Activés » = soignants ayant déjà postulé à ≥1 mission.
                </p>
              </CardY2KContent>
            </CardY2K>

            {/* Campagnes */}
            {campagnes.length > 0 && (
              <CardY2K hoverLift={false}>
                <CardY2KHeader><CardY2KTitle className="text-sm">Meilleures campagnes</CardY2KTitle></CardY2KHeader>
                <CardY2KContent>
                  <div className="space-y-2">
                    {campagnes.slice(0, 10).map((c, i) => (
                      <div key={i} className="flex items-center justify-between text-sm border-b last:border-0 py-1.5">
                        <span className="text-foreground">{c.campagne}</span>
                        <BadgeY2K variant="info">{c.inscriptions} inscrit{c.inscriptions > 1 ? 's' : ''}</BadgeY2K>
                      </div>
                    ))}
                  </div>
                </CardY2KContent>
              </CardY2K>
            )}
          </>
        )}
        </div>
      </div>
    </LayoutAdmin>
  );
}
