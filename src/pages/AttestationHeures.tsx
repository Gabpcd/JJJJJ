import { useState, useEffect, useMemo } from 'react';
import { useSearchParams, useNavigate } from 'react-router-dom';
import { Printer, ArrowLeft, FileText } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { fetchEtablissementsSafe } from '@/lib/etablissements';
import { PROFESSIONS } from '@/lib/constantes';
import { ENTREPRISE } from '@/constantes/entreprise';
import { ChargementPage } from '@/components/ChargementPage';
import { LayoutApp } from '@/components/LayoutApp';
import { LogoJolene } from '@/components/LogoJolene';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { format, startOfMonth, endOfMonth, subMonths, startOfYear, endOfYear } from 'date-fns';
import { fr } from 'date-fns/locale';

function getLabelProfession(code: string) {
  return PROFESSIONS.find(p => p.valeur === code)?.label || code;
}

const RACCOURCIS = [
  { label: 'Ce mois', fn: () => ({ debut: startOfMonth(new Date()), fin: endOfMonth(new Date()) }) },
  { label: 'Mois dernier', fn: () => ({ debut: startOfMonth(subMonths(new Date(), 1)), fin: endOfMonth(subMonths(new Date(), 1)) }) },
  { label: 'Ce trimestre', fn: () => {
    const m = new Date().getMonth();
    const q = Math.floor(m / 3) * 3;
    return { debut: new Date(new Date().getFullYear(), q, 1), fin: new Date(new Date().getFullYear(), q + 3, 0) };
  }},
  { label: 'Cette année', fn: () => ({ debut: startOfYear(new Date()), fin: endOfYear(new Date()) }) },
];

export default function AttestationHeures() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const debut = searchParams.get('debut') || '';
  const fin = searchParams.get('fin') || '';

  // Formulaire de sélection de période (affiché quand debut/fin absents)
  const [formDebut, setFormDebut] = useState(format(startOfMonth(new Date()), 'yyyy-MM-dd'));
  const [formFin, setFormFin] = useState(format(endOfMonth(new Date()), 'yyyy-MM-dd'));
  const [preview, setPreview] = useState({ nb: 0, heures: 0 });
  const [loadingPreview, setLoadingPreview] = useState(false);

  // Preview live du nombre de missions / heures pour la période sélectionnée
  useEffect(() => {
    if (!user || debut || fin) return;
    let cancelled = false;
    const load = async () => {
      setLoadingPreview(true);
      const { data } = await supabase
        .from('missions')
        .select('duree_heures')
        .eq('soignant_assigne_id', user.id)
        .eq('statut', 'TERMINEE')
        .gte('debut_le', formDebut)
        .lte('debut_le', formFin);
      if (cancelled) return;
      const ms = (data as any[]) || [];
      setPreview({ nb: ms.length, heures: ms.reduce((s: number, m: any) => s + (m.duree_heures || 0), 0) });
      setLoadingPreview(false);
    };
    load();
    return () => { cancelled = true; };
  }, [user, formDebut, formFin, debut, fin]);

  function appliquerRaccourci(r: typeof RACCOURCIS[0]) {
    const { debut: d, fin: f } = r.fn();
    setFormDebut(format(d, 'yyyy-MM-dd'));
    setFormFin(format(f, 'yyyy-MM-dd'));
  }

  function genererAttestation() {
    setSearchParams({ debut: formDebut, fin: formFin });
  }

  const [soignant, setSoignant] = useState<any>(null);
  const [missions, setMissions] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!user) return;
    if (!debut || !fin) { setLoading(false); return; }
    const load = async () => {
      const [{ data: sg }, { data: ms }] = await Promise.all([
        supabase.rpc('fn_mon_profil_soignant_complet' as any),
        supabase.from('missions')
          .select('id, intitule, service, debut_le, fin_le, duree_heures, taux_horaire_base, net_a_payer, statut, etablissement_id')
          .eq('soignant_assigne_id', user.id)
          .eq('statut', 'TERMINEE')
          .gte('debut_le', debut)
          .lte('debut_le', fin)
          .order('debut_le', { ascending: true }),
      ]);
      setSoignant(sg);
      // Enrich with safe establishment data
      const missionsArr = (ms as any[]) || [];
      const etabIds = [...new Set(missionsArr.map(m => m.etablissement_id).filter(Boolean))];
      const safeMap = await fetchEtablissementsSafe(etabIds);
      const enriched = missionsArr.map(m => ({
        ...m,
        etablissements: safeMap[m.etablissement_id] || null,
      }));
      setMissions(enriched);

      // Audit HDS
      await supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user.id,
        p_type_acteur: 'SOIGNANT',
        p_action: 'DONNEES_PERSO_EXPORT',
        p_type_ressource: 'soignant',
        p_id_ressource: user.id,
        p_cle_s3: null,
        p_details: {
          type: 'attestation_heures',
          periode: { debut, fin },
          nb_missions: (ms as any[])?.length || 0,
          total_heures: (ms as any[])?.reduce((s: number, m: any) => s + (m.duree_heures || 0), 0) || 0,
        },
        p_ip: null,
        p_navigateur: navigator.userAgent,
      });

      setLoading(false);
    };
    load();
  }, [user, debut, fin]);

  const stats = useMemo(() => {
    const totalHeures = missions.reduce((s, m) => s + (m.duree_heures || 0), 0);
    const etabs = new Set(missions.map(m => m.etablissements?.nom).filter(Boolean));
    return { totalHeures, nbEtabs: etabs.size };
  }, [missions]);

  const identifiant = `ATT-${user?.id?.substring(0, 8) || 'XXXX'}-${Date.now()}`;

  if (loading) return <div className="flex items-center justify-center min-h-[100dvh]"><ChargementPage /></div>;

  if (!debut || !fin) {
    return (
      <LayoutApp role="SOIGNANT">
        <div className="max-w-xl mx-auto space-y-5">
          <div className="flex items-center gap-3">
            <Button variant="ghost" size="icon" className="app-inline-back" aria-label="Retour" onClick={() => navigate(-1)}>
              <ArrowLeft className="h-5 w-5" />
            </Button>
            <div>
              <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
                <FileText className="h-5 w-5 text-primary" /> Attestation d'heures travaillées
              </h1>
              <p className="text-xs text-muted-foreground">Sélectionne la période à couvrir</p>
            </div>
          </div>

          <div className="card-base p-5 space-y-4">
            <div>
              <p className="text-sm font-medium text-foreground mb-2">Période :</p>
              <div className="flex items-center gap-2">
                <div className="flex-1">
                  <label htmlFor="attestation-date-debut" className="text-xs text-muted-foreground">Du</label>
                  <Input id="attestation-date-debut" type="date" value={formDebut} onChange={(e) => setFormDebut(e.target.value)} />
                </div>
                <div className="flex-1">
                  <label htmlFor="attestation-date-fin" className="text-xs text-muted-foreground">Au</label>
                  <Input id="attestation-date-fin" type="date" value={formFin} onChange={(e) => setFormFin(e.target.value)} />
                </div>
              </div>
            </div>

            <div>
              <p className="text-xs text-muted-foreground mb-1.5">Raccourcis :</p>
              <div className="flex flex-wrap gap-1.5">
                {RACCOURCIS.map(r => (
                  <button
                    key={r.label}
                    onClick={() => appliquerRaccourci(r)}
                    className="text-xs bg-muted text-muted-foreground hover:bg-primary/10 hover:text-primary px-3 py-1.5 rounded-full transition-colors"
                  >
                    {r.label}
                  </button>
                ))}
              </div>
            </div>

            <div className="bg-muted/50 rounded-xl p-3 text-center">
              {loadingPreview ? (
                <p className="text-sm text-muted-foreground">Chargement...</p>
              ) : (
                <p className="text-sm font-medium text-foreground">
                  Missions incluses : <span className="text-primary font-bold">{preview.nb} mission{preview.nb > 1 ? 's' : ''}</span> · <span className="text-primary font-bold">{Math.round(preview.heures)}h</span>
                </p>
              )}
            </div>

            <BoutonY2K
              onClick={genererAttestation}
              disabled={preview.nb === 0 || loadingPreview}
              className="w-full"
              iconeGauche={<FileText className="h-4 w-4" />}
            >
              Générer l'attestation
            </BoutonY2K>

            {preview.nb === 0 && !loadingPreview && (
              <p className="text-xs text-muted-foreground text-center italic">
                Aucune mission terminée sur cette période. Essayez une autre plage de dates.
              </p>
            )}
          </div>
        </div>
      </LayoutApp>
    );
  }


  return (
    <div className="min-h-[100dvh] bg-background">
      {/* Toolbar — hidden on print */}
      <div className="no-print sticky top-0 z-50 bg-background border-b border-border px-4 py-3 flex items-center gap-3">
        <button onClick={() => navigate('/soignant/mes-gains')} className="flex items-center gap-1 text-sm text-primary font-medium hover:underline">
          <ArrowLeft className="h-4 w-4" /> Retour à mes gains
        </button>
        <div className="flex-1" />
        <button onClick={() => window.print()} className="flex items-center gap-2 bg-primary text-primary-foreground rounded-xl px-5 py-2.5 font-semibold text-sm hover:opacity-90 transition-opacity">
          <Printer className="h-4 w-4" /> Imprimer / Enregistrer en PDF
        </button>
      </div>

      {/* Attestation content */}
      <div className="attestation max-w-3xl mx-auto p-8 md:p-12">
        {/* Header */}
        <div className="text-center mb-8">
          <LogoJolene
            className="mx-auto mb-1 flex w-fit"
            imageClassName="h-8 w-8"
            nomClassName="text-2xl"
          />
          <h1 className="text-xl font-bold uppercase tracking-wide">Attestation d'heures travaillées</h1>
        </div>

        <div className="border-t border-gray-300 mb-6" />

        {/* Soignant */}
        <div className="mb-6">
          <h2 className="font-bold text-sm uppercase tracking-wide mb-2">Soignant</h2>
          <table className="text-sm">
            <tbody>
              <tr><td className="pr-4 text-gray-600 py-0.5">Nom :</td><td className="font-medium">{soignant?.prenom} {soignant?.nom}</td></tr>
              <tr><td className="pr-4 text-gray-600 py-0.5">Profession :</td><td>{getLabelProfession(soignant?.profession)}</td></tr>
              {soignant?.numero_rpps && <tr><td className="pr-4 text-gray-600 py-0.5">N° RPPS :</td><td>{soignant.numero_rpps}</td></tr>}
              {/* Rétrocompatibilité : ADELI obsolète depuis 2024 (basculé RPPS). Affichage conservé pour anciens comptes qui auraient ce champ rempli en DB. */}
              {soignant?.numero_adeli && <tr><td className="pr-4 text-gray-600 py-0.5">N° ADELI :</td><td>{soignant.numero_adeli}</td></tr>}
            </tbody>
          </table>
        </div>

        {/* Période */}
        <div className="mb-6">
          <h2 className="font-bold text-sm uppercase tracking-wide mb-2">Période</h2>
          <p className="text-sm">Du {format(new Date(debut), 'dd/MM/yyyy')} au {format(new Date(fin), 'dd/MM/yyyy')}</p>
        </div>

        <div className="border-t border-gray-300 mb-6" />

        {/* Détail des missions */}
        <div className="mb-6">
          <h2 className="font-bold text-sm uppercase tracking-wide mb-3">Détail des missions</h2>
          <table className="w-full border-collapse text-sm">
            <thead>
              <tr className="bg-gray-100">
                <th className="border border-gray-300 px-2 py-1.5 text-left font-semibold">Date</th>
                <th className="border border-gray-300 px-2 py-1.5 text-left font-semibold">Établissement</th>
                <th className="border border-gray-300 px-2 py-1.5 text-left font-semibold">FINESS</th>
                <th className="border border-gray-300 px-2 py-1.5 text-left font-semibold">Service</th>
                <th className="border border-gray-300 px-2 py-1.5 text-right font-semibold">Durée</th>
              </tr>
            </thead>
            <tbody>
              {missions.map((m, i) => (
                <tr key={i} className={i % 2 === 0 ? '' : 'bg-gray-50'}>
                  <td className="border border-gray-300 px-2 py-1">{m.debut_le ? format(new Date(m.debut_le), 'dd/MM/yyyy') : '—'}</td>
                  <td className="border border-gray-300 px-2 py-1">{m.etablissements?.nom || '—'}</td>
                  <td className="border border-gray-300 px-2 py-1">{m.etablissements?.finess || '—'}</td>
                  <td className="border border-gray-300 px-2 py-1">{m.service || '—'}</td>
                  <td className="border border-gray-300 px-2 py-1 text-right">{m.duree_heures || 0}h</td>
                </tr>
              ))}
              <tr className="font-bold bg-gray-100">
                <td className="border border-gray-300 px-2 py-1.5" colSpan={4}>TOTAL</td>
                <td className="border border-gray-300 px-2 py-1.5 text-right">{stats.totalHeures}h</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div className="border-t border-gray-300 mb-6" />

        {/* Synthèse */}
        <div className="mb-6">
          <h2 className="font-bold text-sm uppercase tracking-wide mb-2">Synthèse</h2>
          <ul className="text-sm space-y-1">
            <li>Nombre de missions terminées : <strong>{missions.length}</strong></li>
            <li>Total d'heures travaillées : <strong>{stats.totalHeures}h</strong></li>
            <li>Établissements fréquentés : <strong>{stats.nbEtabs}</strong></li>
          </ul>
        </div>

        <div className="border-t border-gray-300 mb-6" />

        {/* Footer légal */}
        <div className="text-xs text-gray-500 space-y-2">
          <p>Document généré automatiquement par {ENTREPRISE.nom}. Présentable à l'Ordre professionnel, la CPAM ou tout organisme compétent.</p>
          <p>Généré le : {format(new Date(), 'dd/MM/yyyy')} · Identifiant : {identifiant}</p>
          <p className="font-medium">{ENTREPRISE.nom} — SIRET {ENTREPRISE.siret} · {ENTREPRISE.adresse}</p>
          <p>Hébergement HDS : {ENTREPRISE.hebergeur} · Conforme RGPD</p>
          <p className="italic mt-2">Les montants financiers ne figurent pas sur cette attestation. Pour les justificatifs de rémunération, consulte tes bulletins de paie.</p>
        </div>
      </div>
    </div>
  );
}
