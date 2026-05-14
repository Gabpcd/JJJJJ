import { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EmptyState } from '@/components/ui/EmptyState';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { Shield, Loader2, Save, Info, AlertTriangle } from 'lucide-react';
import { FadeInView } from '@/components/FadeInView';

type PriseEnCharge = 'ETABLISSEMENT' | 'SOIGNANT' | 'PARTAGE';
type TypeCouverture = 'RC_MISSION' | 'ANNULATION' | 'ACCIDENT_TRAVAIL';
type StatutPolice = 'ACTIVE' | 'EXPIREE' | 'SINISTRE';

const LABELS_TYPE: Record<TypeCouverture, string> = {
  RC_MISSION: 'RC Mission',
  ANNULATION: 'Annulation',
  ACCIDENT_TRAVAIL: 'Accident du travail',
};

const STATUT_BADGE: Record<StatutPolice, { label: string; cls: string }> = {
  ACTIVE: { label: 'Active', cls: 'bg-success/10 text-success' },
  EXPIREE: { label: 'Expiree', cls: 'bg-muted text-muted-foreground' },
  SINISTRE: { label: 'Sinistre', cls: 'bg-destructive/10 text-destructive' },
};

const fmt = (v: number) =>
  new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);

const fmtDate = (d: string | null) =>
  d ? new Date(d).toLocaleDateString('fr-FR') : '—';

export default function AssuranceMission() {
  usePageTitle('Assurance Mission');
  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <AssuranceMissionContent />
    </LayoutApp>
  );
}

export function AssuranceMissionContent() {
  const { user } = useAuth();
  const { afficherNotification } = useNotification();

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [configId, setConfigId] = useState<string | null>(null);
  const [assuranceAuto, setAssuranceAuto] = useState(false);
  const [priseEnCharge, setPriseEnCharge] = useState<PriseEnCharge>('ETABLISSEMENT');
  const [partSoignantPourcent, setPartSoignantPourcent] = useState(25);
  const [typeCouverture, setTypeCouverture] = useState<TypeCouverture>('RC_MISSION');
  const [montantCouverture, setMontantCouverture] = useState(1000000);

  const [polices, setPolices] = useState<any[]>([]);
  const [loadingPolices, setLoadingPolices] = useState(true);

  const [sinistreOuvert, setSinistreOuvert] = useState(false);
  const [sinistreMissionId, setSinistreMissionId] = useState('');
  const [sinistreDescription, setSinistreDescription] = useState('');
  const [sinistreMontant, setSinistreMontant] = useState('');
  const [submittingSinistre, setSubmittingSinistre] = useState(false);

  useEffect(() => {
    if (!user) return;
    (async () => {
      const { data } = await supabase
        .from('assurance_config' as any)
        .select('*')
        .eq('etablissement_id', user.id)
        .maybeSingle();
      if (data) {
        setConfigId((data as any).id);
        setAssuranceAuto((data as any).assurance_auto ?? false);
        setPriseEnCharge((data as any).prise_en_charge ?? 'ETABLISSEMENT');
        setPartSoignantPourcent((data as any).part_soignant_pourcent ?? 25);
        setTypeCouverture((data as any).type_couverture ?? 'RC_MISSION');
        setMontantCouverture((data as any).montant_couverture ?? 1000000);
      }
      setLoading(false);
    })();
  }, [user]);

  useEffect(() => {
    if (!user) return;
    (async () => {
      const { data } = await supabase
        .from('assurances_mission' as any)
        .select('*, missions(intitule, debut_le, fin_le)')
        .eq('etablissement_id', user.id)
        .order('cree_le', { ascending: false })
        .limit(50);
      setPolices((data as any[]) || []);
      setLoadingPolices(false);
    })();
  }, [user]);

  const sauvegarder = async () => {
    if (!user) return;
    setSaving(true);
    try {
      const payload = {
        etablissement_id: user.id,
        assurance_auto: assuranceAuto,
        prise_en_charge: priseEnCharge,
        part_soignant_pourcent: priseEnCharge === 'PARTAGE' ? partSoignantPourcent : null,
        type_couverture: typeCouverture,
        montant_couverture: montantCouverture,
      } as any;

      if (configId) {
        const { error } = await supabase
          .from('assurance_config' as any)
          .update(payload)
          .eq('id', configId);
        if (error) throw error;
      } else {
        const { error, data } = await supabase
          .from('assurance_config' as any)
          .insert(payload)
          .select('id')
          .single();
        if (error) throw error;
        if (data) setConfigId((data as any).id);
      }

      afficherNotification({ type: 'succes', message: 'Configuration assurance enregistree' });
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: err?.message || 'Erreur lors de la sauvegarde' });
    } finally {
      setSaving(false);
    }
  };

  const declarerSinistre = async () => {
    if (!user || !sinistreMissionId || !sinistreDescription.trim()) {
      afficherNotification({ type: 'erreur', message: 'Veuillez remplir tous les champs obligatoires.' });
      return;
    }
    setSubmittingSinistre(true);
    try {
      const montant = parseFloat(sinistreMontant) || 0;
      const { error } = await supabase
        .from('assurances_mission' as any)
        .update({
          statut: 'SINISTRE',
          sinistre_description: sinistreDescription.trim(),
          sinistre_montant_estime: montant > 0 ? montant : null,
          sinistre_declare_le: new Date().toISOString(),
        } as any)
        .eq('id', sinistreMissionId);
      if (error) throw error;

      afficherNotification({ type: 'succes', message: 'Sinistre declare avec succes' });
      setSinistreOuvert(false);
      setSinistreMissionId('');
      setSinistreDescription('');
      setSinistreMontant('');

      const { data } = await supabase
        .from('assurances_mission' as any)
        .select('*, missions(intitule, debut_le, fin_le)')
        .eq('etablissement_id', user.id)
        .order('cree_le', { ascending: false })
        .limit(50);
      setPolices((data as any[]) || []);
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: err?.message || 'Erreur lors de la declaration' });
    } finally {
      setSubmittingSinistre(false);
    }
  };

  const policesActives = polices.filter((p: any) => p.statut === 'ACTIVE');

  if (loading) return <ChargementPage />;

  return (
    <>
      <FadeInView>
        <div className="max-w-3xl mx-auto space-y-6">
          <div className="flex items-center gap-3">
            <div className="p-2.5 rounded-xl bg-primary/10">
              <Shield className="h-6 w-6 text-primary" />
            </div>
            <div>
              <h2 className="text-lg font-bold text-foreground">Assurance Mission</h2>
              <p className="text-sm text-muted-foreground">
                Couverture assurantielle pour vos missions de staffing. Protegez vos soignants et votre etablissement.
              </p>
            </div>
          </div>

          <div className="card-base space-y-5">
            <h3 className="text-base font-bold text-foreground">Configuration de l'assurance</h3>

            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-foreground">Assurance automatique</p>
                <p className="text-xs text-muted-foreground">Souscrire automatiquement pour chaque nouvelle mission</p>
              </div>
              <button
                type="button"
                role="switch"
                aria-checked={assuranceAuto}
                onClick={() => setAssuranceAuto(!assuranceAuto)}
                className={`relative inline-flex h-6 w-11 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 ${assuranceAuto ? 'bg-primary' : 'bg-muted'}`}
              >
                <span className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow-lg ring-0 transition duration-200 ${assuranceAuto ? 'translate-x-5' : 'translate-x-0'}`} />
              </button>
            </div>

            <div>
              <label className="block text-sm font-medium text-foreground mb-1.5">Prise en charge</label>
              <select
                value={priseEnCharge}
                onChange={e => setPriseEnCharge(e.target.value as PriseEnCharge)}
                className="input-base"
              >
                <option value="ETABLISSEMENT">Etablissement (100%)</option>
                <option value="SOIGNANT">Soignant (100%)</option>
                <option value="PARTAGE">Partage etablissement / soignant</option>
              </select>
            </div>

            {priseEnCharge === 'PARTAGE' && (
              <div>
                <label className="block text-sm font-medium text-foreground mb-1.5">
                  Part soignant : {partSoignantPourcent}%
                </label>
                <input
                  type="range"
                  min={0}
                  max={50}
                  step={5}
                  value={partSoignantPourcent}
                  onChange={e => setPartSoignantPourcent(Number(e.target.value))}
                  className="w-full accent-primary"
                />
                <div className="flex justify-between text-xs text-muted-foreground mt-1">
                  <span>0%</span>
                  <span>50%</span>
                </div>
              </div>
            )}

            <div>
              <label className="block text-sm font-medium text-foreground mb-1.5">Type de couverture</label>
              <select
                value={typeCouverture}
                onChange={e => setTypeCouverture(e.target.value as TypeCouverture)}
                className="input-base"
              >
                <option value="RC_MISSION">RC Mission (Responsabilite civile)</option>
                <option value="ANNULATION">Annulation de mission</option>
                <option value="ACCIDENT_TRAVAIL">Accident du travail</option>
              </select>
            </div>

            <div>
              <label className="block text-sm font-medium text-foreground mb-1.5">Montant de couverture</label>
              <div className="input-base bg-muted/50 cursor-default">
                {fmt(montantCouverture)}
              </div>
              <p className="text-xs text-muted-foreground mt-1">Plafond de couverture par mission</p>
            </div>

            <div className="rounded-lg border border-primary/20 bg-primary/5 p-3 flex gap-3">
              <Info className="h-5 w-5 text-primary shrink-0 mt-0.5" />
              <div className="text-xs text-primary space-y-1">
                <p className="font-semibold">Partenariat Wakam</p>
                <p>
                  Les polices d'assurance mission sont souscrites aupres de Wakam (ex-La Parisienne Assurances),
                  assureur agree par l'ACPR. Couverture activee des la confirmation de mission.
                </p>
              </div>
            </div>

            <button
              onClick={sauvegarder}
              disabled={saving}
              className="btn-primary w-full flex items-center justify-center gap-2"
            >
              {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
              Enregistrer la configuration
            </button>
          </div>

          <div className="card-base space-y-4">
            <div className="flex items-center justify-between">
              <h3 className="text-base font-bold text-foreground">Polices d'assurance</h3>
              {policesActives.length > 0 && (
                <button
                  onClick={() => setSinistreOuvert(true)}
                  className="btn-secondary text-sm flex items-center gap-1.5"
                >
                  <AlertTriangle className="h-4 w-4" />
                  Declarer un sinistre
                </button>
              )}
            </div>

            {loadingPolices ? (
              <div className="flex items-center justify-center py-8">
                <Loader2 className="h-6 w-6 animate-spin text-primary" />
              </div>
            ) : polices.length === 0 ? (
              <EmptyState
                icone={<Shield />}
                titre="Aucune police d'assurance"
                description="Les polices seront creees automatiquement lors de la confirmation de vos missions."
              />
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b text-left text-muted-foreground">
                      <th className="pb-2 pr-3">Mission</th>
                      <th className="pb-2 pr-3">Soignant</th>
                      <th className="pb-2 pr-3">Type</th>
                      <th className="pb-2 pr-3">Prime</th>
                      <th className="pb-2 pr-3">Statut</th>
                      <th className="pb-2">Couverture</th>
                    </tr>
                  </thead>
                  <tbody>
                    {polices.map((p: any) => {
                      const statut = STATUT_BADGE[p.statut as StatutPolice] || STATUT_BADGE.ACTIVE;
                      const mission = p.missions;
                      return (
                        <tr key={p.id} className="border-b last:border-0">
                          <td className="py-2.5 pr-3">
                            <p className="font-medium text-foreground">{mission?.intitule || '—'}</p>
                            <p className="text-xs text-muted-foreground">
                              {fmtDate(mission?.debut_le)} — {fmtDate(mission?.fin_le)}
                            </p>
                          </td>
                          <td className="py-2.5 pr-3 text-foreground">{p.soignant_nom || '—'}</td>
                          <td className="py-2.5 pr-3">{LABELS_TYPE[p.type_couverture as TypeCouverture] || p.type_couverture || '—'}</td>
                          <td className="py-2.5 pr-3 font-medium">{p.prime != null ? fmt(p.prime) : '—'}</td>
                          <td className="py-2.5 pr-3">
                            <span className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ${statut.cls}`}>
                              {statut.label}
                            </span>
                          </td>
                          <td className="py-2.5">{p.montant_couverture != null ? fmt(p.montant_couverture) : '—'}</td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </div>
      </FadeInView>

      {sinistreOuvert && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50" onClick={() => setSinistreOuvert(false)}>
          <div className="bg-card rounded-xl shadow-xl w-full max-w-md mx-4 p-6 space-y-4" onClick={e => e.stopPropagation()}>
            <h3 className="text-lg font-bold text-foreground">Declarer un sinistre</h3>
            <p className="text-sm text-muted-foreground">Selectionnez la mission concernee et decrivez le sinistre.</p>

            <div>
              <label className="block text-sm font-medium text-foreground mb-1.5">Mission concernee</label>
              <select
                value={sinistreMissionId}
                onChange={e => setSinistreMissionId(e.target.value)}
                className="input-base"
              >
                <option value="">Selectionnez une mission</option>
                {policesActives.map((p: any) => (
                  <option key={p.id} value={p.id}>
                    {p.missions?.intitule || 'Mission'} — {fmtDate(p.missions?.debut_le)}
                  </option>
                ))}
              </select>
            </div>

            <div>
              <label className="block text-sm font-medium text-foreground mb-1.5">
                Description du sinistre <span className="text-destructive">*</span>
              </label>
              <textarea
                value={sinistreDescription}
                onChange={e => setSinistreDescription(e.target.value)}
                placeholder="Decrivez les circonstances du sinistre..."
                rows={4}
                className="input-base resize-none"
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-foreground mb-1.5">Montant estime</label>
              <input
                type="number"
                value={sinistreMontant}
                onChange={e => setSinistreMontant(e.target.value)}
                placeholder="Ex: 5000"
                min={0}
                step={100}
                className="input-base"
              />
              <p className="text-xs text-muted-foreground mt-1">Estimation du montant des dommages en euros</p>
            </div>

            <div className="flex gap-2 pt-2">
              <button
                onClick={() => setSinistreOuvert(false)}
                className="btn-secondary flex-1"
              >
                Annuler
              </button>
              <button
                onClick={declarerSinistre}
                disabled={submittingSinistre || !sinistreMissionId || !sinistreDescription.trim()}
                className="btn-primary flex-1 flex items-center justify-center gap-2"
              >
                {submittingSinistre && <Loader2 className="h-4 w-4 animate-spin" />}
                Declarer le sinistre
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
