import { useCallback, useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  AlertTriangle,
  Banknote,
  CheckCircle2,
  Clock3,
  Filter,
  MapPin,
  RefreshCw,
  Rocket,
  ScanLine,
  ShieldCheck,
  Stethoscope,
  Target,
  Users,
  XCircle,
} from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementAdmin } from '@/components/admin/ChargementAdmin';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { CardY2K, CardY2KContent, CardY2KHeader, CardY2KTitle } from '@/components/y2k/CardY2K';
import { CarteKPIY2K } from '@/components/y2k/CarteKPIY2K';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { usePageTitle } from '@/hooks/usePageTitle';
import { supabase } from '@/integrations/supabase/client';
import { getLabelProfession, PROFESSIONS } from '@/lib/constantes';
import { toast } from 'sonner';

type ScopeDonnees = 'REEL' | 'TEST' | 'TOUS';

interface ValeurEntonnoir {
  etape: string;
  valeur: number;
}

interface SegmentLancement {
  departement: string;
  profession: string;
  soignants_verifies: number;
  disponibles_7j: number;
  missions_publiees: number;
  missions_ouvertes: number;
  missions_pourvues: number;
}

interface DonneesLancement {
  scope: ScopeDonnees;
  jours: number;
  genere_le: string;
  offre: {
    inscrits: number;
    verifies: number;
    actifs_30j: number;
    disponibles_7j: number;
  };
  demande: {
    etablissements: number;
    etablissements_verifies: number;
    missions_publiees: number;
    missions_ouvertes: number;
    missions_pourvues: number;
    missions_terminees: number;
  };
  conversion: {
    taux_reponse_pct: number;
    taux_pourvoi_pct: number;
    delai_premiere_candidature_h: number;
    delai_pourvoi_h: number;
  };
  qualite: {
    taux_pointage_complet_pct: number;
    taux_paiement_pct: number;
    taux_commission_encaissee_pct: number;
    taux_no_show_pct: number;
    taux_litige_pct: number;
    litiges_ouverts: number;
  };
  alertes: {
    missions_sans_candidat_24h: number;
    pointages_incomplets: number;
    paiements_manquants: number;
    commissions_non_encaissees: number;
  };
  entonnoirs: {
    soignants: ValeurEntonnoir[];
    etablissements: ValeurEntonnoir[];
  };
  segments: SegmentLancement[];
}

interface GateLancement {
  label: string;
  valeur: string;
  cible: string;
  atteint: boolean;
}

const SCOPES: Array<{ valeur: ScopeDonnees; label: string; aide: string }> = [
  { valeur: 'REEL', label: 'Réel', aide: 'Pilotage public, comptes de test exclus' },
  { valeur: 'TEST', label: 'Test', aide: 'Démonstrations et scénarios stores uniquement' },
  { valeur: 'TOUS', label: 'Tous', aide: 'Vue combinée, jamais utilisée pour décider un lancement' },
];

function n(value: number | null | undefined): number {
  return Number(value) || 0;
}

function pct(value: number | null | undefined): string {
  return `${n(value).toLocaleString('fr-FR', { maximumFractionDigits: 1 })} %`;
}

function heures(value: number | null | undefined): string {
  const total = n(value);
  if (total < 1) return `${Math.round(total * 60)} min`;
  return `${total.toLocaleString('fr-FR', { maximumFractionDigits: 1 })} h`;
}

function Entonnoir({ titre, valeurs }: { titre: string; valeurs: ValeurEntonnoir[] }) {
  const maximum = Math.max(...valeurs.map((item) => n(item.valeur)), 1);
  return (
    <CardY2K hoverLift={false} noPadding>
      <CardY2KHeader>
        <CardY2KTitle>{titre}</CardY2KTitle>
      </CardY2KHeader>
      <CardY2KContent>
        <ol className="space-y-3" aria-label={`Entonnoir ${titre.toLowerCase()}`}>
          {valeurs.map((item) => {
            const largeur = Math.max(8, (n(item.valeur) / maximum) * 100);
            return (
              <li key={item.etape}>
                <div className="mb-1 flex items-center justify-between gap-3 text-xs">
                  <span className="text-muted-foreground">{item.etape}</span>
                  <strong className="tabular-nums text-foreground">{n(item.valeur).toLocaleString('fr-FR')}</strong>
                </div>
                <div className="h-2.5 overflow-hidden rounded-full bg-muted" aria-hidden="true">
                  <div className="h-full rounded-full bg-gradient-hero" style={{ width: `${largeur}%` }} />
                </div>
              </li>
            );
          })}
        </ol>
      </CardY2KContent>
    </CardY2K>
  );
}

export default function AdminCockpitLancement() {
  usePageTitle('Cockpit de lancement');
  const navigate = useNavigate();
  const [scope, setScope] = useState<ScopeDonnees>('REEL');
  const [jours, setJours] = useState(30);
  const [departement, setDepartement] = useState('');
  const [profession, setProfession] = useState('');
  const [data, setData] = useState<DonneesLancement | null>(null);
  const [loading, setLoading] = useState(true);

  const charger = useCallback(async () => {
    setLoading(true);
    const { data: resultat, error } = await supabase.rpc('fn_admin_cockpit_lancement' as never, {
      p_scope: scope,
      p_jours: jours,
      p_departement: departement.trim() || null,
      p_profession: profession || null,
    } as never);
    setLoading(false);
    if (error) {
      toast.error(`Cockpit indisponible : ${error.message}`);
      setData(null);
      return;
    }
    setData(resultat as unknown as DonneesLancement);
  }, [departement, jours, profession, scope]);

  useEffect(() => {
    charger();
  }, [charger]);

  const gates = useMemo<GateLancement[]>(() => {
    if (!data) return [];
    return [
      { label: 'Missions réelles terminées', valeur: String(n(data.demande.missions_terminees)), cible: '≥ 5', atteint: n(data.demande.missions_terminees) >= 5 },
      { label: 'Taux de pourvoi', valeur: pct(data.conversion.taux_pourvoi_pct), cible: '≥ 70 %', atteint: n(data.conversion.taux_pourvoi_pct) >= 70 },
      { label: '1re candidature médiane', valeur: heures(data.conversion.delai_premiere_candidature_h), cible: '< 4 h', atteint: n(data.conversion.delai_premiere_candidature_h) > 0 && n(data.conversion.delai_premiere_candidature_h) < 4 },
      { label: 'Pointages complets', valeur: pct(data.qualite.taux_pointage_complet_pct), cible: '≥ 95 %', atteint: n(data.qualite.taux_pointage_complet_pct) >= 95 },
      { label: 'Soignants payés', valeur: pct(data.qualite.taux_paiement_pct), cible: '≥ 95 %', atteint: n(data.qualite.taux_paiement_pct) >= 95 },
      { label: 'Commissions encaissées', valeur: pct(data.qualite.taux_commission_encaissee_pct), cible: '≥ 95 %', atteint: n(data.qualite.taux_commission_encaissee_pct) >= 95 },
      { label: 'Absences sans prévenir', valeur: pct(data.qualite.taux_no_show_pct), cible: '< 3 %', atteint: n(data.qualite.taux_no_show_pct) < 3 },
      { label: 'Missions avec litige', valeur: pct(data.qualite.taux_litige_pct), cible: '< 5 %', atteint: n(data.qualite.taux_litige_pct) < 5 },
    ];
  }, [data]);

  if (loading && !data) {
    return <LayoutAdmin><ChargementAdmin titre="Cockpit de lancement" /></LayoutAdmin>;
  }

  return (
    <LayoutAdmin>
      <main className="space-y-6" aria-labelledby="cockpit-lancement-title">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <h1 id="cockpit-lancement-title" className="flex items-center gap-2 text-xl font-bold text-foreground">
              <Rocket className="h-5 w-5 text-primary" aria-hidden="true" /> Cockpit de lancement
            </h1>
            <p className="text-sm text-muted-foreground">
              Liquidité du marché, conversion et qualité de bout en bout — par profession et département.
            </p>
          </div>
          <BoutonY2K variant="ghost" size="sm" onClick={charger} loading={loading} iconeGauche={<RefreshCw className="h-4 w-4" />}>
            Rafraîchir
          </BoutonY2K>
        </div>

        <section className="rounded-2xl border border-border bg-card p-4" aria-label="Filtres du cockpit">
          <div className="flex flex-col gap-4">
            <div>
              <Label className="mb-2 block text-xs">Nature des données</Label>
              <div className="flex flex-wrap gap-2" role="group" aria-label="Nature des données">
                {SCOPES.map((item) => (
                  <BoutonY2K
                    key={item.valeur}
                    size="sm"
                    variant={scope === item.valeur ? 'primary' : 'secondary'}
                    aria-pressed={scope === item.valeur}
                    title={item.aide}
                    onClick={() => setScope(item.valeur)}
                  >
                    {item.label}
                  </BoutonY2K>
                ))}
              </div>
              <p className="mt-2 text-xs text-muted-foreground">{SCOPES.find((item) => item.valeur === scope)?.aide}</p>
            </div>
            <div className="grid gap-3 sm:grid-cols-3">
              <div>
                <Label htmlFor="launch-period" className="text-xs">Période</Label>
                <select id="launch-period" className="input-base mt-1 h-10 w-full" value={jours} onChange={(event) => setJours(Number(event.target.value))}>
                  <option value={7}>7 jours</option>
                  <option value={30}>30 jours</option>
                  <option value={90}>90 jours</option>
                  <option value={365}>12 mois</option>
                </select>
              </div>
              <div>
                <Label htmlFor="launch-departement" className="text-xs">Département</Label>
                <div className="relative mt-1">
                  <MapPin className="absolute left-3 top-3 h-4 w-4 text-muted-foreground" aria-hidden="true" />
                  <Input id="launch-departement" value={departement} onChange={(event) => setDepartement(event.target.value)} placeholder="Tous ou 75" className="pl-9" maxLength={3} />
                </div>
              </div>
              <div>
                <Label htmlFor="launch-profession" className="text-xs">Profession requise par la mission</Label>
                <select id="launch-profession" className="input-base mt-1 h-10 w-full" value={profession} onChange={(event) => setProfession(event.target.value)}>
                  <option value="">Toutes</option>
                  {PROFESSIONS.map((item) => <option key={item.valeur} value={item.valeur}>{item.label}</option>)}
                </select>
              </div>
            </div>
          </div>
        </section>

        {scope !== 'REEL' && (
          <div className="flex gap-3 rounded-xl border border-amber-400/50 bg-amber-50 p-3 text-sm text-amber-950" role="status">
            <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
            <p>Cette vue sert aux démonstrations et aux contrôles. Les seuils de lancement public doivent être lus sur <strong>Réel</strong>.</p>
          </div>
        )}

        {!data ? (
          <div className="rounded-xl border border-destructive/30 bg-destructive/5 p-4 text-sm text-destructive" role="alert">
            Les métriques n’ont pas pu être chargées.
          </div>
        ) : (
          <>
            <section aria-labelledby="launch-kpi-title">
              <h2 id="launch-kpi-title" className="sr-only">Indicateurs principaux</h2>
              <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
                <CarteKPIY2K icone={<ShieldCheck className="h-4 w-4" />} label="Soignants vérifiés" valeur={n(data.offre.verifies)} contexte={`${n(data.offre.disponibles_7j)} disponibles à J+7`} variant="holographic" onClick={() => navigate('/admin/utilisateurs')} />
                <CarteKPIY2K icone={<Stethoscope className="h-4 w-4" />} label="Missions ouvertes" valeur={n(data.demande.missions_ouvertes)} contexte={`${n(data.demande.missions_publiees)} publiées sur la période`} onClick={() => navigate('/admin/missions?statut=OUVERTE')} />
                <CarteKPIY2K icone={<Target className="h-4 w-4" />} label="Taux de pourvoi" valeur={pct(data.conversion.taux_pourvoi_pct)} contexte={`${n(data.demande.missions_pourvues)} missions pourvues`} variant="soft" />
                <CarteKPIY2K icone={<Clock3 className="h-4 w-4" />} label="1re candidature" valeur={heures(data.conversion.delai_premiere_candidature_h)} contexte="Médiane après publication" />
                <CarteKPIY2K icone={<ScanLine className="h-4 w-4" />} label="Pointages complets" valeur={pct(data.qualite.taux_pointage_complet_pct)} contexte={`${n(data.alertes.pointages_incomplets)} à corriger`} onClick={() => navigate('/admin/alertes-pointage')} />
                <CarteKPIY2K icone={<Banknote className="h-4 w-4" />} label="Soignants payés" valeur={pct(data.qualite.taux_paiement_pct)} contexte={`${n(data.alertes.paiements_manquants)} paiement(s) manquant(s)`} onClick={() => navigate('/admin/finances')} />
                <CarteKPIY2K icone={<Users className="h-4 w-4" />} label="Réponse à une mission" valeur={pct(data.conversion.taux_reponse_pct)} contexte="≥ 1 candidature" />
                <CarteKPIY2K icone={<AlertTriangle className="h-4 w-4" />} label="Litiges ouverts" valeur={n(data.qualite.litiges_ouverts)} contexte={`${pct(data.qualite.taux_litige_pct)} des missions`} onClick={() => navigate('/admin/litiges')} />
              </div>
            </section>

            <section aria-labelledby="launch-gates-title">
              <div className="mb-3 flex items-center justify-between gap-3">
                <div>
                  <h2 id="launch-gates-title" className="font-bold text-foreground">Seuils avant extension du lancement</h2>
                  <p className="text-xs text-muted-foreground">Un seuil rouge bloque l’élargissement géographique ou métier, pas les tests en cours.</p>
                </div>
                <BadgeY2K variant={gates.every((gate) => gate.atteint) && scope === 'REEL' ? 'success' : 'warning'}>
                  {gates.filter((gate) => gate.atteint).length}/{gates.length} atteints
                </BadgeY2K>
              </div>
              <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
                {gates.map((gate) => (
                  <div key={gate.label} className={`rounded-xl border p-3 ${gate.atteint ? 'border-emerald-300 bg-emerald-50/70' : 'border-destructive/30 bg-destructive/5'}`}>
                    <div className="flex items-start justify-between gap-2">
                      <div>
                        <p className="text-xs text-muted-foreground">{gate.label}</p>
                        <p className="mt-1 text-lg font-bold tabular-nums text-foreground">{gate.valeur}</p>
                        <p className="text-[11px] text-muted-foreground">Cible {gate.cible}</p>
                      </div>
                      {gate.atteint ? <CheckCircle2 className="h-5 w-5 text-emerald-600" aria-label="Seuil atteint" /> : <XCircle className="h-5 w-5 text-destructive" aria-label="Seuil non atteint" />}
                    </div>
                  </div>
                ))}
              </div>
            </section>

            <section className="grid gap-4 lg:grid-cols-2" aria-label="Entonnoirs d’activation">
              <Entonnoir titre="Activation soignants" valeurs={data.entonnoirs.soignants || []} />
              <Entonnoir titre="Activation établissements" valeurs={data.entonnoirs.etablissements || []} />
            </section>

            <section aria-labelledby="launch-alerts-title">
              <CardY2K hoverLift={false} noPadding>
                <CardY2KHeader>
                  <CardY2KTitle id="launch-alerts-title">File d’actions avant lancement</CardY2KTitle>
                </CardY2KHeader>
                <CardY2KContent>
                  <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                    <button type="button" onClick={() => navigate('/admin/missions?statut=OUVERTE')} className="rounded-xl border border-border p-3 text-left hover:bg-muted/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary">
                      <p className="text-2xl font-bold tabular-nums">{n(data.alertes.missions_sans_candidat_24h)}</p><p className="text-xs text-muted-foreground">mission(s) sans candidat depuis 24 h</p>
                    </button>
                    <button type="button" onClick={() => navigate('/admin/alertes-pointage')} className="rounded-xl border border-border p-3 text-left hover:bg-muted/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary">
                      <p className="text-2xl font-bold tabular-nums">{n(data.alertes.pointages_incomplets)}</p><p className="text-xs text-muted-foreground">pointage(s) incomplet(s)</p>
                    </button>
                    <button type="button" onClick={() => navigate('/admin/finances')} className="rounded-xl border border-border p-3 text-left hover:bg-muted/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary">
                      <p className="text-2xl font-bold tabular-nums">{n(data.alertes.paiements_manquants)}</p><p className="text-xs text-muted-foreground">paiement(s) soignant manquant(s)</p>
                    </button>
                    <button type="button" onClick={() => navigate('/admin/impayees')} className="rounded-xl border border-border p-3 text-left hover:bg-muted/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary">
                      <p className="text-2xl font-bold tabular-nums">{n(data.alertes.commissions_non_encaissees)}</p><p className="text-xs text-muted-foreground">commission(s) non encaissée(s)</p>
                    </button>
                  </div>
                </CardY2KContent>
              </CardY2K>
            </section>

            <section aria-labelledby="launch-segments-title">
              <div className="mb-3 flex items-center gap-2">
                <Filter className="h-4 w-4 text-primary" aria-hidden="true" />
                <h2 id="launch-segments-title" className="font-bold text-foreground">Liquidité par marché local</h2>
              </div>
              <div className="overflow-x-auto rounded-xl border border-border bg-card">
                <table className="w-full min-w-[760px] text-sm">
                  <caption className="sr-only">Offre et demande par département et profession</caption>
                  <thead className="bg-muted/50 text-left text-xs text-muted-foreground">
                    <tr>
                      <th scope="col" className="px-4 py-3">Dépt.</th>
                      <th scope="col" className="px-4 py-3">Profession mission</th>
                      <th scope="col" className="px-4 py-3 text-right">Vérifiés</th>
                      <th scope="col" className="px-4 py-3 text-right">Dispo. J+7</th>
                      <th scope="col" className="px-4 py-3 text-right">Publiées</th>
                      <th scope="col" className="px-4 py-3 text-right">Ouvertes</th>
                      <th scope="col" className="px-4 py-3 text-right">Pourvues</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-border">
                    {(data.segments || []).map((segment) => (
                      <tr key={`${segment.departement}-${segment.profession}`} className="hover:bg-muted/30">
                        <td className="px-4 py-3 font-semibold">{segment.departement}</td>
                        <td className="px-4 py-3">{getLabelProfession(segment.profession)}</td>
                        <td className="px-4 py-3 text-right tabular-nums">{n(segment.soignants_verifies)}</td>
                        <td className="px-4 py-3 text-right tabular-nums">{n(segment.disponibles_7j)}</td>
                        <td className="px-4 py-3 text-right tabular-nums">{n(segment.missions_publiees)}</td>
                        <td className="px-4 py-3 text-right tabular-nums">{n(segment.missions_ouvertes)}</td>
                        <td className="px-4 py-3 text-right tabular-nums">{n(segment.missions_pourvues)}</td>
                      </tr>
                    ))}
                    {data.segments?.length === 0 && (
                      <tr><td colSpan={7} className="px-4 py-8 text-center text-muted-foreground">Aucune donnée pour ces filtres.</td></tr>
                    )}
                  </tbody>
                </table>
              </div>
            </section>
          </>
        )}
      </main>
    </LayoutAdmin>
  );
}
