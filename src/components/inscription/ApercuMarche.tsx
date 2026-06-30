import { useEffect, useState } from 'react';
import { Sparkles, Building2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { getLabelProfession } from '@/lib/constantes';
import { cn } from '@/lib/utils';

interface Apercu {
  nb_missions: number;
  taux_max: number | null;
  taux_moyen: number | null;
  nb_etablissements: number;
  zone: 'rayon' | 'national';
}

const fmtTaux = (v: number) =>
  new Intl.NumberFormat('fr-FR', { maximumFractionDigits: 0 }).format(v);

/**
 * Aperçu du marché pendant l'inscription (Session E-2) — montre la valeur
 * AVANT l'effort documentaire. Composant silencieux : rien tant que les
 * données ne sont pas là, jamais d'erreur visible (l'inscription ne doit
 * jamais dépendre de lui).
 */
export function ApercuMarche({
  profession,
  lat,
  lng,
  rayonKm,
  className,
}: {
  profession?: string | null;
  lat?: number | null;
  lng?: number | null;
  rayonKm?: number | null;
  className?: string;
}) {
  const [apercu, setApercu] = useState<Apercu | null>(null);

  useEffect(() => {
    let annule = false;
    const t = setTimeout(async () => {
      const geo = lat != null && lng != null;
      const { data, error } = await supabase.rpc('fn_apercu_marche_profession' as any, {
        p_profession: profession || null,
        p_lat: geo ? lat : null,
        p_lng: geo ? lng : null,
        p_rayon_km: geo ? (rayonKm ?? 30) : null,
      });
      if (!annule && !error && data) setApercu(data as unknown as Apercu);
    }, 300);
    return () => { annule = true; clearTimeout(t); };
  }, [profession, lat, lng, rayonKm]);

  if (!apercu) return null;

  const labelProf = profession ? getLabelProfession(profession) : null;

  if (apercu.nb_missions > 0) {
    return (
      <div className={cn('p-3 rounded-xl border border-primary/30 bg-gradient-to-r from-primary/10 to-primary/5 flex items-start gap-2', className)} role="status">
        <Sparkles className="h-4 w-4 text-primary shrink-0 mt-0.5" />
        <p className="text-sm text-foreground">
          <strong>{apercu.nb_missions} mission{apercu.nb_missions > 1 ? 's' : ''}</strong>
          {labelProf ? <> {labelProf}</> : null}{' '}
          {apercu.zone === 'rayon' ? 'dans ton rayon' : 'ouvertes en ce moment'}
          {apercu.taux_max != null && apercu.taux_max > 0 && (
            <> · jusqu'à <strong>{fmtTaux(Number(apercu.taux_max))} €/h</strong></>
          )}
        </p>
      </div>
    );
  }

  if (apercu.nb_etablissements > 0) {
    return (
      <div className={cn('p-3 rounded-xl border border-primary/20 bg-primary/5 flex items-start gap-2', className)} role="status">
        <Building2 className="h-4 w-4 text-primary shrink-0 mt-0.5" />
        <p className="text-sm text-foreground">
          <strong>{apercu.nb_etablissements} établissement{apercu.nb_etablissements > 1 ? 's' : ''} de santé</strong>{' '}
          {apercu.zone === 'rayon' ? 'près de chez toi' : 'déjà inscrits'} — complète ton profil
          pour être prévenu·e en premier dès qu'une mission est publiée.
        </p>
      </div>
    );
  }

  return null;
}
