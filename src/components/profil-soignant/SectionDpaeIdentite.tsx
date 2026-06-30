import { useEffect, useState } from 'react';
import { Loader2, IdCard, CheckCircle, AlertCircle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';

interface Props {
  soignantId: string;
  /** Type d'exercice : si LIBERAL, on ne montre pas (DPAE pas requise). */
  typeExercice?: string;
}

const PAYS_USUELS = ['France', 'Algérie', 'Maroc', 'Tunisie', 'Portugal', 'Italie',
  'Espagne', 'Belgique', 'Allemagne', 'Sénégal', 'Côte d\'Ivoire', 'Cameroun',
  'Madagascar', 'Roumanie'];
const NATIONALITES_USUELLES = ['Française', 'Algérienne', 'Marocaine', 'Tunisienne',
  'Portugaise', 'Italienne', 'Espagnole', 'Belge', 'Allemande', 'Sénégalaise',
  'Ivoirienne', 'Camerounaise', 'Malgache', 'Roumaine'];

/**
 * Section "Informations DPAE" du profil soignant.
 *
 * Affichée uniquement pour les soignants salariés / mixtes (les libéraux purs
 * n'ont pas de DPAE — relation B2B). Permet au soignant de renseigner les
 * champs requis par la Déclaration Préalable à l'Embauche URSSAF :
 *   - sexe (M/F)
 *   - lieu de naissance (commune + département si France)
 *   - pays de naissance
 *   - nationalité
 *
 * Données utilisées par fn_generer_donnees_dpae côté étab. Plus le profil
 * est complet, moins l'étab doit re-saisir manuellement sur Net-Entreprises.
 */
export function SectionDpaeIdentite({ soignantId, typeExercice }: Props) {
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [sexe, setSexe] = useState<string>('');
  const [communeNaissance, setCommuneNaissance] = useState('');
  const [departementNaissance, setDepartementNaissance] = useState('');
  const [paysNaissance, setPaysNaissance] = useState('France');
  const [nationalite, setNationalite] = useState('Française');
  const [nir, setNir] = useState<string>('');
  const [nirInitial, setNirInitial] = useState<string>('');
  const [manquants, setManquants] = useState<string[]>([]);

  const cacher = typeExercice === 'LIBERAL';

  useEffect(() => {
    if (cacher) { setLoading(false); return; }
    (async () => {
      setLoading(true);
      const { data, error } = await supabase
        .from('soignants')
        .select('sexe, lieu_naissance_commune, lieu_naissance_departement, pays_naissance, nationalite, numero_securite_sociale' as any)
        .eq('id', soignantId)
        .maybeSingle();
      if (!error && data) {
        const d = data as any;
        setSexe(d.sexe || '');
        setCommuneNaissance(d.lieu_naissance_commune || '');
        setDepartementNaissance(d.lieu_naissance_departement || '');
        setPaysNaissance(d.pays_naissance || 'France');
        setNationalite(d.nationalite || 'Française');
        setNir(d.numero_securite_sociale || '');
        setNirInitial(d.numero_securite_sociale || '');
      }
      const { data: dpaeData } = await supabase.rpc('fn_soignant_dpae_complet' as any, { p_soignant_id: soignantId });
      if (dpaeData) setManquants(((dpaeData as any).manquants || []) as string[]);
      setLoading(false);
    })();
  }, [soignantId, cacher]);

  async function enregistrer() {
    setSaving(true);
    try {
      // 1. Maj infos DPAE (sexe, lieu naissance, nationalité)
      const { data, error } = await supabase.rpc('fn_maj_infos_dpae' as any, {
        p_sexe: sexe || null,
        p_lieu_naissance_commune: communeNaissance || null,
        p_lieu_naissance_departement: departementNaissance || null,
        p_pays_naissance: paysNaissance || null,
        p_nationalite: nationalite || null,
      });
      if (error) throw error;
      if (!(data as any)?.success) {
        afficherNotification({ type: 'erreur', message: (data as any)?.error || 'Erreur enregistrement' });
        return;
      }

      // 2. Maj NIR si modifié (RPC dédiée Sprint 5.5 PR 10 — validation format strict)
      if (nir.trim().length > 0 && nir.trim() !== nirInitial) {
        const { data: nirData, error: nirError } = await supabase.rpc('fn_maj_nir_soignant' as any, {
          p_nir: nir.trim(),
        });
        if (nirError) {
          afficherNotification({ type: 'erreur', message: nirError.message });
          return;
        }
        const result = nirData as any;
        if (!result?.success) {
          const msg = result?.error || (result?.error_code === 'NIR_FORMAT_INVALIDE'
            ? 'Le NIR doit faire 13 ou 15 chiffres au format français.'
            : 'Erreur NIR.');
          afficherNotification({ type: 'erreur', message: msg });
          return;
        }
        setNirInitial(nir.trim());
      }

      // 3. Recharger le statut DPAE
      const { data: dpaeData } = await supabase.rpc('fn_soignant_dpae_complet' as any, { p_soignant_id: soignantId });
      if (dpaeData) setManquants(((dpaeData as any).manquants || []) as string[]);
      afficherNotification({ type: 'succes', message: 'Informations DPAE enregistrées.' });
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: err?.message || 'Erreur réseau' });
    } finally {
      setSaving(false);
    }
  }

  if (cacher) return null;
  if (loading) return <div className="text-sm text-muted-foreground">Chargement…</div>;

  const complet = manquants.length === 0;
  const enFrance = paysNaissance === 'France';

  return (
    <div className="rounded-xl border border-border bg-card p-4 space-y-4">
      <div className="flex items-start gap-3">
        <IdCard className="h-5 w-5 text-primary shrink-0 mt-0.5" />
        <div className="flex-1">
          <h3 className="font-semibold text-foreground">Informations DPAE</h3>
          <p className="text-xs text-muted-foreground mt-1">
            Ces informations sont requises par l'URSSAF pour la Déclaration Préalable à l'Embauche
            de tes contrats CDD. Plus ton profil est complet, plus la déclaration est rapide
            côté établissement.
          </p>
        </div>
        {complet ? (
          <span className="inline-flex items-center gap-1 text-xs text-emerald-700 bg-emerald-50 dark:bg-emerald-950/40 dark:text-emerald-300 px-2 py-1 rounded-full">
            <CheckCircle className="h-3.5 w-3.5" /> Complet
          </span>
        ) : (
          <span className="inline-flex items-center gap-1 text-xs text-amber-700 bg-amber-50 dark:bg-amber-950/40 dark:text-amber-300 px-2 py-1 rounded-full">
            <AlertCircle className="h-3.5 w-3.5" /> Incomplet
          </span>
        )}
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <label className="block">
          <span className="text-xs font-medium text-foreground mb-1 block">Sexe (état civil) *</span>
          <select
            value={sexe}
            onChange={e => setSexe(e.target.value)}
            className="input-base"
          >
            <option value="">— Sélectionne —</option>
            <option value="M">Masculin</option>
            <option value="F">Féminin</option>
          </select>
        </label>

        <label className="block">
          <span className="text-xs font-medium text-foreground mb-1 block">Pays de naissance *</span>
          <input
            list="pays-usuels-dpae"
            type="text"
            value={paysNaissance}
            onChange={e => setPaysNaissance(e.target.value)}
            className="input-base"
            placeholder="France"
          />
          <datalist id="pays-usuels-dpae">
            {PAYS_USUELS.map(p => <option key={p} value={p} />)}
          </datalist>
        </label>

        {enFrance && (
          <>
            <label className="block">
              <span className="text-xs font-medium text-foreground mb-1 block">Commune de naissance *</span>
              <input
                type="text"
                value={communeNaissance}
                onChange={e => setCommuneNaissance(e.target.value)}
                placeholder="Ex : Paris"
                className="input-base"
              />
            </label>

            <label className="block">
              <span className="text-xs font-medium text-foreground mb-1 block">Département (01-95, 2A, 2B, 971-976) *</span>
              <input
                type="text"
                value={departementNaissance}
                onChange={e => setDepartementNaissance(e.target.value.trim().toUpperCase().slice(0, 3))}
                placeholder="Ex : 75"
                className="input-base font-mono"
                maxLength={3}
              />
            </label>
          </>
        )}

        <label className="block sm:col-span-2">
          <span className="text-xs font-medium text-foreground mb-1 block">Nationalité *</span>
          <input
            list="nationalites-usuelles-dpae"
            type="text"
            value={nationalite}
            onChange={e => setNationalite(e.target.value)}
            placeholder="Française"
            className="input-base"
          />
          <datalist id="nationalites-usuelles-dpae">
            {NATIONALITES_USUELLES.map(n => <option key={n} value={n} />)}
          </datalist>
        </label>

        <label className="block sm:col-span-2">
          <span className="text-xs font-medium text-foreground mb-1 block">
            Numéro de sécurité sociale (NIR) *
          </span>
          <input
            type="text"
            value={nir}
            onChange={e => setNir(e.target.value.replace(/[^0-9A-Za-z]/g, '').toUpperCase().slice(0, 15))}
            placeholder="Ex : 184057514213562 (15 chiffres)"
            className="input-base font-mono"
            maxLength={15}
            inputMode="numeric"
            autoComplete="off"
          />
          <p className="text-[10px] text-muted-foreground mt-1">
            Sur ta carte vitale, 13 ou 15 chiffres. Stocké chiffré, transmis uniquement à l'établissement pour la DPAE URSSAF.
          </p>
        </label>
      </div>

      {!complet && manquants.length > 0 && (
        <div className="rounded-lg bg-amber-50/60 dark:bg-amber-950/30 border border-amber-200 dark:border-amber-800 p-3 text-xs text-amber-800 dark:text-amber-300">
          <p className="font-semibold mb-1">Encore à compléter :</p>
          <ul className="list-disc list-inside space-y-0.5">
            {manquants.map(m => <li key={m}>{libelleManquant(m)}</li>)}
          </ul>
        </div>
      )}

      <button
        type="button"
        onClick={enregistrer}
        disabled={saving}
        className="btn-primary w-full disabled:opacity-50 inline-flex items-center justify-center gap-2"
      >
        {saving && <Loader2 className="h-4 w-4 animate-spin" />}
        Enregistrer mes informations DPAE
      </button>
    </div>
  );
}

function libelleManquant(code: string): string {
  const libelles: Record<string, string> = {
    sexe: 'Sexe (M ou F)',
    date_naissance: 'Date de naissance (à compléter en haut de la page profil)',
    lieu_naissance_commune: 'Commune de naissance',
    lieu_naissance_departement: 'Département de naissance',
    pays_naissance: 'Pays de naissance',
    nationalite: 'Nationalité',
    numero_securite_sociale: 'Numéro de sécurité sociale (NIR)',
    adresse: 'Adresse postale (à compléter en haut de la page profil)',
  };
  return libelles[code] || code;
}
