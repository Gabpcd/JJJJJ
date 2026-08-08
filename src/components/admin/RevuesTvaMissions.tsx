import { useCallback, useEffect, useState } from 'react';
import { AlertTriangle, ExternalLink, Loader2, RefreshCw } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';

type NatureTvaPrestation =
  | 'SOIN_THERAPEUTIQUE_EXONERE'
  | 'PRESTATION_TAXABLE';

interface RevueTvaMission {
  mission_id: string;
  intitule: string;
  etablissement_id: string;
  etablissement_nom: string;
  soignant_id: string;
  soignant_nom: string;
  nature_etablissement: NatureTvaPrestation | null;
  nature_soignant: NatureTvaPrestation | null;
  declaration_le: string | null;
  confirmation_le: string | null;
}

const LABELS: Record<NatureTvaPrestation, string> = {
  SOIN_THERAPEUTIQUE_EXONERE: 'Soin à finalité thérapeutique',
  PRESTATION_TAXABLE: 'Prestation taxable',
};

function labelNature(value: NatureTvaPrestation | null): string {
  return value ? LABELS[value] : 'Non renseignée';
}

function CarteRevueTva({
  revue,
  onTraitee,
}: {
  revue: RevueTvaMission;
  onTraitee: (missionId: string) => void;
}) {
  const navigate = useNavigate();
  const [nature, setNature] = useState<NatureTvaPrestation | ''>(
    revue.nature_etablissement || revue.nature_soignant || '',
  );
  const [motif, setMotif] = useState('');
  const [saving, setSaving] = useState(false);

  const soumettre = async () => {
    if (!nature || motif.trim().length < 10) return;
    setSaving(true);
    try {
      const { data, error } = await supabase.rpc('fn_admin_proposer_nature_tva_mission' as any, {
        p_mission_id: revue.mission_id,
        p_nature_tva_prestation: nature,
        p_motif: motif.trim(),
      });
      if (error || (data as any)?.success === false) {
        throw error || new Error((data as any)?.error || 'Revue impossible.');
      }
      toast.success('Proposition envoyée au soignant pour confirmation.');
      onTraitee(revue.mission_id);
    } catch (error: any) {
      toast.error(error?.message || 'Revue TVA impossible.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <article className="rounded-xl border border-warning/40 bg-card p-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h3 className="font-semibold text-foreground">{revue.intitule}</h3>
          <p className="text-xs text-muted-foreground">
            {revue.etablissement_nom} · {revue.soignant_nom || 'Soignant assigné'}
          </p>
        </div>
        <button
          type="button"
          onClick={() => navigate(`/admin/missions/${revue.mission_id}`)}
          className="inline-flex items-center gap-1 text-xs font-medium text-primary hover:underline"
        >
          Voir la mission <ExternalLink className="h-3 w-3" aria-hidden="true" />
        </button>
      </div>

      <dl className="mt-3 grid gap-2 text-xs sm:grid-cols-2">
        <div className="rounded-lg bg-muted/40 p-3">
          <dt className="text-muted-foreground">Déclaration établissement</dt>
          <dd className="mt-1 font-semibold text-foreground">{labelNature(revue.nature_etablissement)}</dd>
        </div>
        <div className="rounded-lg bg-muted/40 p-3">
          <dt className="text-muted-foreground">Position du soignant</dt>
          <dd className="mt-1 font-semibold text-foreground">{labelNature(revue.nature_soignant)}</dd>
        </div>
      </dl>

      <fieldset className="mt-4 space-y-2" disabled={saving}>
        <legend className="text-xs font-semibold text-foreground">Nature proposée après revue *</legend>
        <p className="text-[11px] text-muted-foreground">
          « Soin » exige un professionnel médical ou paramédical réglementé et une finalité de prévention, diagnostic ou traitement. La qualification ne dépend pas du seul intitulé de mission.
        </p>
        {(Object.entries(LABELS) as Array<[NatureTvaPrestation, string]>).map(([value, label]) => (
          <label key={value} className="flex cursor-pointer items-center gap-2 text-sm text-foreground">
            <input
              type="radio"
              name={`nature-tva-${revue.mission_id}`}
              checked={nature === value}
              onChange={() => setNature(value)}
              className="accent-primary"
            />
            {label}
          </label>
        ))}
      </fieldset>

      <label htmlFor={`motif-tva-${revue.mission_id}`} className="mt-4 block text-xs font-semibold text-foreground">
        Motif communiqué et archivé *
      </label>
      <textarea
        id={`motif-tva-${revue.mission_id}`}
        value={motif}
        onChange={(event) => setMotif(event.target.value.slice(0, 1000))}
        rows={3}
        minLength={10}
        maxLength={1000}
        placeholder="Expliquez les éléments examinés et la raison de la proposition…"
        className="input-base mt-1 resize-y"
        disabled={saving}
      />
      <div className="mt-3 flex flex-wrap items-center justify-between gap-2">
        <p className="text-[11px] text-muted-foreground">
          L'admin propose ; le soignant confirme. La mission reste active et aucune facture n'est émise entre-temps.
        </p>
        <BoutonY2K
          size="sm"
          disabled={!nature || motif.trim().length < 10 || saving}
          onClick={soumettre}
          loading={saving}
        >
          Proposer et demander confirmation
        </BoutonY2K>
      </div>
    </article>
  );
}

export function RevuesTvaMissions() {
  const [revues, setRevues] = useState<RevueTvaMission[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const charger = useCallback(async () => {
    setLoading(true);
    setError(null);
    const { data, error: fetchError } = await supabase.rpc('fn_admin_lister_revues_tva_missions' as any);
    if (fetchError) {
      setRevues([]);
      setError(fetchError.message || 'Chargement impossible.');
    } else {
      setRevues((Array.isArray(data) ? data : []) as RevueTvaMission[]);
    }
    setLoading(false);
  }, []);

  useEffect(() => {
    void charger();
  }, [charger]);

  if (loading) {
    return (
      <div className="flex items-center gap-2 rounded-xl border border-border bg-card p-4 text-sm text-muted-foreground" role="status">
        <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
        Vérification des revues TVA…
      </div>
    );
  }

  if (error) {
    return (
      <div className="rounded-xl border border-destructive/30 bg-destructive/5 p-4" role="alert">
        <p className="text-sm font-semibold text-destructive">Revues TVA indisponibles</p>
        <p className="mt-1 text-xs text-muted-foreground">{error}</p>
        <BoutonY2K size="sm" variant="secondary" className="mt-3" onClick={charger} iconeGauche={<RefreshCw className="h-3.5 w-3.5" />}>
          Réessayer
        </BoutonY2K>
      </div>
    );
  }

  if (revues.length === 0) return null;

  return (
    <section aria-labelledby="revues-tva-title" className="space-y-3">
      <div>
        <h2 id="revues-tva-title" className="flex items-center gap-2 text-sm font-bold text-foreground">
          <AlertTriangle className="h-4 w-4 text-warning" aria-hidden="true" />
          Revues TVA à traiter
          <span className="inline-flex min-w-5 items-center justify-center rounded-full bg-warning px-1.5 text-[11px] font-bold text-warning-foreground">
            {revues.length}
          </span>
        </h2>
        <p className="mt-1 text-xs text-muted-foreground">
          La mission n'est pas bloquée. Seule sa facturation attend une proposition puis la confirmation du soignant.
        </p>
      </div>
      <div className="space-y-3">
        {revues.map((revue) => (
          <CarteRevueTva
            key={revue.mission_id}
            revue={revue}
            onTraitee={(missionId) => setRevues((courantes) => courantes.filter((item) => item.mission_id !== missionId))}
          />
        ))}
      </div>
    </section>
  );
}
