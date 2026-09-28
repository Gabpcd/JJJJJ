import { useState, useEffect, useMemo, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { usePageTitle } from '@/hooks/usePageTitle';
import { Calculator, Shield, ChevronRight, Download, ArrowLeft } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { enrichirEtablissements } from '@/lib/etablissements';
import { RappelsFiscaux } from '@/components/RappelsFiscaux';
import { format, isValid } from 'date-fns';
import { telechargerOuPartager } from '@/lib/telechargement';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';

function fmt(v: number | null | undefined) {
  if (v == null) return '—';
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

export default function ChargesSociales() {
  usePageTitle('Mes charges');
  const navigate = useNavigate();
  const { user } = useAuth();
  const [loading, setLoading] = useState(true);
  const [caCumule, setCaCumule] = useState(0);
  const [rcpExpiration, setRcpExpiration] = useState<string | null>(null);
  const [rcpVerifiee, setRcpVerifiee] = useState(false);
  const [soignant, setSoignant] = useState<any>(null);
  const [missions, setMissions] = useState<any[]>([]);
  const [showMissions, setShowMissions] = useState(false);
  const [erreurChargement, setErreurChargement] = useState(false);
  const [reloadKey, setReloadKey] = useState(0);
  const savingRegimeRef = useRef(false);

  useEffect(() => {
    if (!user) return;
    let actif = true;
    const load = async () => {
      setLoading(true); setErreurChargement(false);
      try {
        const annee = new Date().getFullYear();
        const debutAnnee = new Date(annee, 0, 1).toISOString();

        const [missionsResult, docsResult, soignantResult] = await Promise.all([
          supabase
            .from('missions')
            .select('id, intitule, debut_le, fin_le, duree_heures, taux_horaire_base, total_brut, etablissement_id, service')
            .eq('soignant_assigne_id', user.id)
            .eq('statut', 'TERMINEE')
            // Charges sociales = libéral uniquement. On ne compte QUE les missions
            // dont le régime appliqué est LIBERAL (un soignant Mixte ne voit pas ses
            // missions salariées gonfler le récapitulatif libéral). NULL = non déterminé → exclu.
            .eq('type_contrat_applique', 'LIBERAL')
            .gte('fin_le', debutAnnee)
            .order('debut_le', { ascending: false }),
          supabase
            .from('documents_soignants')
            .select('valide_jusqua')
            .eq('soignant_id', user.id)
            .eq('type_document', 'RCP_ASSURANCE')
            .eq('statut_verification', 'VERIFIE')
            .is('supprime_le', null)
            .order('valide_jusqua', { ascending: false })
            .limit(1),
          supabase.from('soignants').select('prenom, nom, profession, statut_liberal, assujetti_tva, regime_fiscal, regime_fiscal_confirme' as any).eq('id', user.id).maybeSingle(),
        ]);

        for (const result of [missionsResult, docsResult, soignantResult]) if (result.error) throw result.error;
        const missionData = missionsResult.data, docs = docsResult.data, sg = soignantResult.data;
        const enriched = missionData ? await enrichirEtablissements(missionData as any) : [];
        if (!actif) return;
        setMissions(enriched as any[]);
        const ca = (enriched as any[]).reduce((s: number, m: any) => s + (m.total_brut || 0), 0);
        setCaCumule(ca);
        setRcpExpiration(docs?.[0]?.valide_jusqua ?? null);
        setRcpVerifiee(Boolean(docs?.length));
        setSoignant(sg);
      } catch {
        if (actif) setErreurChargement(true);
      } finally {
        if (actif) setLoading(false);
      }
    };
    void load();
    return () => { actif = false; };
  }, [user, reloadKey]);

  const microBnc = soignant?.regime_fiscal === 'MICRO_BNC';
  const declarationControlee = soignant?.regime_fiscal === 'DECLARATION_CONTROLEE';
  const regimeConfirme = soignant?.regime_fiscal_confirme === true;
  const [savingRegime, setSavingRegime] = useState(false);

  const choisirRegime = async (regime: 'MICRO_BNC' | 'DECLARATION_CONTROLEE') => {
    if (!user || savingRegimeRef.current) return;
    savingRegimeRef.current = true; setSavingRegime(true);
    try {
      const { data, error } = await supabase.from('soignants')
        .update({ regime_fiscal: regime, regime_fiscal_confirme: true } as any)
        .eq('id', user.id).select('regime_fiscal, regime_fiscal_confirme' as any).single();
      const profilConfirme: unknown = data;
      if (error || !profilConfirme || typeof profilConfirme !== 'object'
        || !('regime_fiscal' in profilConfirme) || profilConfirme.regime_fiscal !== regime
        || !('regime_fiscal_confirme' in profilConfirme) || profilConfirme.regime_fiscal_confirme !== true) {
        throw error || new Error('PROFILE_NOT_UPDATED');
      }
      setSoignant((s: any) => ({ ...s, ...profilConfirme }));
      toast.success(regime === 'MICRO_BNC' ? 'Régime micro-BNC enregistré' : 'Régime déclaration contrôlée enregistré');
    } catch {
      toast.error("Impossible d'enregistrer ton régime fiscal — réessaie.");
    } finally {
      savingRegimeRef.current = false; setSavingRegime(false);
    }
  };

  const carteRegimeFiscal = (
    <div className="card-base mb-6">
      <div className="flex items-center justify-between gap-2 mb-1">
        <h2 className="font-semibold text-foreground">Ton régime fiscal</h2>
        {!regimeConfirme && (
          <span className="text-[10px] font-medium px-2 py-0.5 rounded-full bg-warning/10 text-warning shrink-0">à confirmer</span>
        )}
      </div>
      <p className="text-xs text-muted-foreground mb-3">
        Renseigne le régime de ton activité. Tu peux le modifier ici.
      </p>
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
        <button
          type="button"
          disabled={savingRegime}
          onClick={() => choisirRegime('MICRO_BNC')}
          aria-pressed={microBnc}
          className={`rounded-xl border p-3 text-left transition-colors min-h-[44px] ${
            microBnc ? 'border-primary bg-primary/5' : 'border-border hover:border-primary/40'
          }`}
        >
          <p className="text-sm font-semibold text-foreground">Micro-BNC {microBnc && '✓'}</p>
          <p className="text-[11px] text-muted-foreground mt-0.5">
            Enregistrer Micro-BNC dans mon profil.
          </p>
        </button>
        <button
          type="button"
          disabled={savingRegime}
          onClick={() => choisirRegime('DECLARATION_CONTROLEE')}
          aria-pressed={declarationControlee}
          className={`rounded-xl border p-3 text-left transition-colors min-h-[44px] ${
            declarationControlee ? 'border-primary bg-primary/5' : 'border-border hover:border-primary/40'
          }`}
        >
          <p className="text-sm font-semibold text-foreground">Déclaration contrôlée {declarationControlee && '✓'}</p>
          <p className="text-[11px] text-muted-foreground mt-0.5">
            Enregistrer la déclaration contrôlée dans mon profil.
          </p>
        </button>
      </div>
    </div>
  );

  const totalHeures = useMemo(() => missions.reduce((s, m) => s + (m.duree_heures || 0), 0), [missions]);
  const dateRcp = rcpExpiration && isValid(new Date(rcpExpiration)) ? new Date(rcpExpiration) : null;
  const exporterCSV = () => {
    // Uniquement les données des missions, jamais un barème fiscal supposé.
    const rows = ['Indicateur,Montant ou nombre',
      `Honoraires bruts des missions terminees,${caCumule.toFixed(2)}`,
      `Missions,${missions.length}`, `Heures,${totalHeures}`];
    void telechargerOuPartager(rows.join('\n'), `missions-liberales-jolene-${new Date().getFullYear()}.csv`, 'text/csv');
  };

  if (loading) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  if (erreurChargement) return <LayoutApp role="SOIGNANT">
    <div className="card-base text-center py-12" role="alert">
      <h1 className="text-xl font-bold mb-2">Mes charges sociales</h1>
      <p>Impossible de charger tes informations.</p>
      <button className="btn-primary mt-4" onClick={() => setReloadKey(k => k + 1)}>Réessayer</button>
    </div>
  </LayoutApp>;

  if (!soignant || (soignant.statut_liberal !== 'ACTIF' && soignant.statut_liberal !== 'EN_COURS')) {
    return (
      <LayoutApp role="SOIGNANT">
        <div className="card-base text-center py-12">
          <h1 className="text-lg font-bold text-foreground mb-2">Charges sociales libérales</h1>
          <p className="text-sm text-muted-foreground max-w-md mx-auto">
            Cette page est réservée aux soignants en exercice libéral ou mixte.
          </p>
          <button onClick={() => navigate('/soignant/tableau-de-bord')} className="btn-primary mt-4 text-sm">
            Retour au dashboard
          </button>
        </div>
      </LayoutApp>
    );
  }

  return (
    <LayoutApp role="SOIGNANT">
      {/* Header with back link */}
      <div className="mb-6">
        <button onClick={() => navigate('/soignant/mes-gains')} className="app-inline-back flex items-center gap-1 text-sm text-primary hover:underline mb-2">
          <ArrowLeft className="h-4 w-4" /> Retour aux gains
        </button>
        <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
          <Calculator className="h-6 w-6 text-primary" /> Mes charges sociales
        </h1>
        <p className="text-sm text-muted-foreground mt-1">Suivi de tes missions libérales {new Date().getFullYear()}</p>
      </div>

      {carteRegimeFiscal}
      <RappelsFiscaux profession={soignant.profession} regimeFiscal={soignant.regime_fiscal}
        regimeFiscalConfirme={soignant.regime_fiscal_confirme === true} afficherLienCharges={false} />
      <div className="card-base mb-6">
        <h2 className="font-semibold mb-2">Tes cotisations et tes échéances</h2>
        <p className="text-sm text-muted-foreground">Tes montants personnels ne sont pas synchronisés dans Jolene. Consulte tes espaces officiels pour connaître les sommes à régler et leurs dates.</p>
      </div>
      {missions.length === 0 && <div className="card-base text-center py-8 mb-6">
        <h2 className="font-semibold mb-2">Aucune mission libérale terminée cette année</h2>
        <p className="text-sm text-muted-foreground">Le récapitulatif de tes missions apparaîtra ici.</p>
        <BoutonY2K onClick={() => navigate('/soignant/recherche-missions')} className="mt-5">Trouver une mission</BoutonY2K>
      </div>}

      {missions.length > 0 && <>
      {/* Honoraires des missions terminées, indépendamment de leur encaissement. */}
      <div
        className="card-base mb-6 cursor-pointer hover:border-primary/30 transition-colors"
        role="button"
        tabIndex={0}
        onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); setShowMissions(!showMissions); } }}
        onClick={() => setShowMissions(!showMissions)}
      >
        <div className="text-center">
          <p className="text-sm text-muted-foreground">Honoraires bruts des missions terminées {new Date().getFullYear()}</p>
          <p className="text-xl sm:text-3xl font-bold text-primary mt-1">{fmt(caCumule)}</p>
          <div className="flex justify-center gap-4 mt-2 text-xs text-muted-foreground">
            <span>{missions.length} mission{missions.length > 1 ? 's' : ''}</span>
            <span>{totalHeures}h travaillées</span>
          </div>
        </div>
        <p className="text-[10px] text-primary text-center mt-2">
          {showMissions ? '▲ Masquer le détail' : '▼ Voir le détail des missions'}
        </p>
      </div>

      {/* Mission breakdown */}
      {showMissions && missions.length > 0 && (
        <div className="space-y-1.5 mb-6">
          {missions.map(m => (
            <div
              key={m.id}
              role="button" tabIndex={0}
              onKeyDown={e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); navigate(`/soignant/presences/mission/${m.id}`); } }}
              onClick={() => navigate(`/soignant/presences/mission/${m.id}`)}
              className="flex items-center justify-between py-2 px-3 rounded-lg border border-border hover:bg-muted/20 cursor-pointer transition-colors text-xs"
            >
              <div className="min-w-0 flex-1">
                <p className="font-medium text-foreground truncate">{m.intitule}</p>
                <p className="text-muted-foreground">
                  {format(new Date(m.debut_le), 'd MMM', { locale: fr })} · {m.etablissements?.nom} · {m.duree_heures}h
                </p>
              </div>
              <div className="flex items-center gap-1.5 shrink-0 ml-2">
                <span className="font-bold text-foreground">{fmt(m.total_brut)}</span>
                <ChevronRight className="h-3.5 w-3.5 text-muted-foreground" />
              </div>
            </div>
          ))}
        </div>
      )}

      </>}
      <div className="grid grid-cols-1 gap-4 mb-6">
        {/* RCP */}
        <button type="button" className="card-base text-left cursor-pointer hover:border-primary/30 transition-colors" onClick={() => navigate('/soignant/documents')}>
          <div className="flex items-center gap-2 mb-3">
            <div className="rounded-xl p-2 bg-destructive/10"><Shield className="h-5 w-5 text-destructive" /></div>
            <div className="flex-1">
              <h3 className="font-semibold text-foreground">Assurance RCP</h3>
              <p className="text-xs text-muted-foreground">Responsabilité civile pro.</p>
            </div>
            <ChevronRight className="h-4 w-4 text-muted-foreground" />
          </div>
          {dateRcp ? (
            <div className="space-y-1.5 text-sm">
              <div className="flex justify-between">
                <span className="text-muted-foreground">Expiration</span>
                <span className="font-medium text-foreground">{format(dateRcp, 'd MMM yyyy', { locale: fr })}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Statut</span>
                {dateRcp > new Date() ? (
                  <span className="text-xs font-medium text-success">✅ Valide</span>
                ) : (
                  <span className="text-xs font-medium text-destructive">❌ Expirée</span>
                )}
              </div>
            </div>
          ) : rcpVerifiee ? (
            <p className="text-sm text-muted-foreground">RCP vérifiée — date d’expiration non renseignée. Voir Documents →</p>
          ) : (
            <p className="text-sm text-destructive">⚠️ Aucune RCP vérifiée. Voir Documents →</p>
          )}
        </button>
      </div>
      {missions.length > 0 && <BoutonY2K variant="secondary" onClick={exporterCSV} className="gap-2">
        <Download className="h-4 w-4" /> Exporter le récapitulatif des missions
      </BoutonY2K>}
      <p className="text-xs text-muted-foreground mt-4">Les honoraires des missions terminées ne correspondent pas nécessairement à des sommes déjà encaissées.</p>
    </LayoutApp>
  );
}
