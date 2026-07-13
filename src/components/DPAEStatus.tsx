import { useEffect, useState } from 'react';
import { FileText, Copy, ExternalLink, Loader2, CheckCircle, AlertTriangle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';

interface Props {
  contratId: string;
  typeContrat: string | null | undefined;
  /** Numéro DPAE déjà enregistré (si oui, masque le bouton "Générer"). */
  dpaeNumero?: string | null;
}

/**
 * Composant DPAE (PR 6 Sprint 1).
 *
 * Affiche pour les contrats CDD :
 *   - Si pas encore généré : bouton "Générer DPAE pré-remplie" qui appelle
 *     fn_generer_donnees_dpae et affiche le payload à copier sur
 *     net-entreprises.fr.
 *   - Après soumission URSSAF : champ pour saisir le n° DPAE retourné,
 *     enregistré via fn_enregistrer_numero_dpae.
 *
 * Pour les contrats LIBERAL : le composant ne s'affiche pas (DPAE non
 * requise — relation B2B).
 */
export function DPAEStatus({ contratId, typeContrat, dpaeNumero }: Props) {
  const { afficherNotification } = useNotification();
  const [payload, setPayload] = useState<any>(null);
  const [loading, setLoading] = useState(false);
  const [numeroSaisi, setNumeroSaisi] = useState(dpaeNumero || '');
  const [saved, setSaved] = useState(!!dpaeNumero);

  // Ne pas afficher pour les contrats libéraux (DPAE non requise)
  const requiresDpae = typeContrat && ['CDD', 'SALARIE'].includes(typeContrat);

  // Si déjà saisi à l'initial, considérer comme saved
  useEffect(() => {
    if (dpaeNumero) setSaved(true);
  }, [dpaeNumero]);

  if (!requiresDpae) return null;

  async function genererPayload() {
    setLoading(true);
    try {
      const { data, error } = await supabase.rpc('fn_generer_donnees_dpae' as any, { p_contrat_id: contratId });
      if (error) throw error;
      const result = data as any;
      if (!result?.success) {
        afficherNotification({ type: 'erreur', message: result?.error || 'Erreur génération DPAE' });
        return;
      }
      setPayload(result);
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: err?.message || 'Erreur génération DPAE' });
    } finally {
      setLoading(false);
    }
  }

  function copierPayload() {
    if (!payload) return;
    const txt = formatPayloadAsText(payload);
    navigator.clipboard.writeText(txt).then(() => {
      afficherNotification({ type: 'succes', message: 'Données DPAE copiées dans le presse-papier.' });
    }).catch(() => {
      afficherNotification({ type: 'erreur', message: 'Impossible de copier — sélectionnez et copiez manuellement.' });
    });
  }

  async function enregistrerNumero() {
    if (!numeroSaisi.trim()) {
      afficherNotification({ type: 'erreur', message: 'Saisissez le numéro DPAE retourné par URSSAF.' });
      return;
    }
    setLoading(true);
    try {
      const { data, error } = await supabase.rpc('fn_enregistrer_numero_dpae' as any, {
        p_contrat_id: contratId,
        p_dpae_numero: numeroSaisi.trim(),
      });
      if (error) throw error;
      const result = data as any;
      if (!result?.success) {
        afficherNotification({ type: 'erreur', message: result?.error || 'Erreur enregistrement' });
        return;
      }
      setSaved(true);
      afficherNotification({ type: 'succes', message: `Numéro DPAE ${result.dpae_numero} enregistré.` });
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: err?.message || 'Erreur enregistrement' });
    } finally {
      setLoading(false);
    }
  }

  if (saved) {
    return (
      <div className="rounded-xl border border-emerald-200 dark:border-emerald-800 bg-emerald-50/60 dark:bg-emerald-950/30 p-4 flex items-start gap-3">
        <CheckCircle className="h-5 w-5 text-emerald-600 dark:text-emerald-400 shrink-0 mt-0.5" />
        <div>
          <p className="font-semibold text-emerald-900 dark:text-emerald-200">DPAE déclarée</p>
          <p className="text-xs text-emerald-800 dark:text-emerald-300 mt-1">
            Numéro DPAE : <strong className="font-mono">{numeroSaisi}</strong>
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="rounded-xl border border-amber-200 dark:border-amber-800 bg-amber-50/60 dark:bg-amber-950/30 p-4 space-y-3">
      <div className="flex items-start gap-2">
        <AlertTriangle className="h-5 w-5 text-amber-600 dark:text-amber-400 shrink-0 mt-0.5" />
        <div className="flex-1">
          <p className="font-semibold text-amber-900 dark:text-amber-200">DPAE obligatoire — Mission CDD</p>
          <p className="text-xs text-amber-800 dark:text-amber-300 mt-1">
            La Déclaration Préalable à l'Embauche doit être effectuée auprès de l'URSSAF
            avant la prise de poste (art. R1221-2 Code travail).
          </p>
        </div>
      </div>

      {!payload && (
        <button
          type="button"
          onClick={genererPayload}
          disabled={loading}
          className="btn-primary w-full disabled:opacity-50 inline-flex items-center justify-center gap-2"
        >
          {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : <FileText className="h-4 w-4" />}
          Générer DPAE pré-remplie
        </button>
      )}

      {payload && (
        <>
          <div className="bg-background rounded-lg p-3 max-h-72 overflow-auto">
            <pre className="text-[10px] text-foreground font-mono whitespace-pre-wrap">{formatPayloadAsText(payload)}</pre>
          </div>
          <div className="flex flex-col sm:flex-row gap-2">
            <button
              type="button"
              onClick={copierPayload}
              className="btn-secondary inline-flex items-center justify-center gap-2 flex-1"
            >
              <Copy className="h-4 w-4" />
              Copier
            </button>
            <a
              href={payload.urssaf_url || 'https://www.net-entreprises.fr/declaration-prealable-embauche/'}
              target="_blank"
              rel="noopener noreferrer"
              className="btn-primary inline-flex items-center justify-center gap-2 flex-1"
            >
              <ExternalLink className="h-4 w-4" />
              Aller sur Net-Entreprises
            </a>
          </div>

          <div className="border-t border-amber-200 dark:border-amber-800 pt-3 space-y-2">
            <label className="block">
              <span className="text-xs font-semibold text-amber-900 dark:text-amber-200">
                Une fois la DPAE soumise, saisissez le n° retourné par URSSAF :
              </span>
              <input
                type="text"
                value={numeroSaisi}
                onChange={e => setNumeroSaisi(e.target.value)}
                placeholder="Ex : 2026XXXXXXXX"
                className="input-base mt-1 text-sm font-mono"
              />
            </label>
            <button
              type="button"
              onClick={enregistrerNumero}
              disabled={!numeroSaisi.trim() || loading}
              className="btn-primary w-full disabled:opacity-50 inline-flex items-center justify-center gap-2"
            >
              {loading && <Loader2 className="h-4 w-4 animate-spin" />}
              Enregistrer le numéro DPAE
            </button>
          </div>
        </>
      )}
    </div>
  );
}

function formatPayloadAsText(p: any): string {
  const lines: string[] = [];
  lines.push('=== DPAE — Déclaration Préalable à l\'Embauche ===');
  lines.push('');
  lines.push('--- Établissement employeur ---');
  for (const [k, v] of Object.entries(p.etablissement || {})) {
    lines.push(`${k.padEnd(30)} : ${v ?? '—'}`);
  }
  lines.push('');
  lines.push('--- Salarié ---');
  const manquants = ((p.salarie?.champs_a_completer_sur_net_entreprises) || []) as string[];
  for (const [k, v] of Object.entries(p.salarie || {})) {
    if (k === 'champs_a_completer_sur_net_entreprises') continue;
    const flag = (v == null || v === '') && manquants.includes(k) ? ' ⚠ À COMPLÉTER MANUELLEMENT' : '';
    lines.push(`${k.padEnd(30)} : ${v ?? '—'}${flag}`);
  }
  if (manquants.length > 0) {
    lines.push('');
    lines.push(`>> Champs encore manquants côté soignant : ${manquants.join(', ')}`);
    lines.push('   (demandez au soignant de compléter son profil DPAE).');
  }
  lines.push('');
  lines.push('--- Embauche ---');
  for (const [k, v] of Object.entries(p.embauche || {})) {
    lines.push(`${k.padEnd(30)} : ${v ?? '—'}`);
  }
  lines.push('');
  if (p.note) lines.push(p.note);
  return lines.join('\n');
}
