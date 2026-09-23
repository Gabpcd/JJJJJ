import { useNavigate } from 'react-router-dom';
import { MapPin, Clock, ArrowRight, Flame, AlertCircle } from 'lucide-react';
import { useMissionsPubliques } from '@/hooks/useMissionsPubliques';
import { lienInscriptionRecherche, memoriserRecherchePublique } from '@/lib/recherchePubliqueInscription';

interface Props {
  profession?: string;   // valeur enum (IDE, AS…) ou undefined = toutes
  ville?: string;        // nom de ville ou undefined = toutes
  campagne: string;      // slug pour l'UTM (ex. "seo-paris", "seo-ide")
}

function libelleContrat(type: string | null | undefined) {
  if (type === 'LIBERAL') return 'Mission libérale';
  if (type === 'TOUS') return 'Salarié ou libéral selon éligibilité';
  return 'CDD salarié';
}

/**
 * Liste publique de missions ouvertes (RPC anon fn_missions_publiques_recherche)
 * pour les landing pages SEO ville/métier. CTA inscription avec UTM tracées.
 */
export function MissionsPubliquesSEO({ profession, ville, campagne }: Props) {
  const navigate = useNavigate();
  const { missions, total, loading, erreur, rechercher } = useMissionsPubliques(profession, ville);
  const ouvrirInscription = () => {
    memoriserRecherchePublique({ profession, ville });
    navigate(lienInscriptionRecherche({ profession, ville }, campagne));
  };

  return (
    <section className="py-12 md:py-16">
      <div className="max-w-5xl mx-auto px-4">
        <h2 className="text-2xl md:text-3xl font-bold text-foreground mb-2">
          {!loading && !erreur && missions && missions.length > 0
            ? `${total} mission${total > 1 ? 's' : ''} disponible${total > 1 ? 's' : ''} en ce moment`
            : 'Découvrez les missions disponibles'}
        </h2>
        {loading && <p role="status" className="text-muted-foreground mt-4">Recherche des missions…</p>}
        {erreur && (
          <div role="alert" className="mt-4 rounded-xl border border-destructive/30 bg-destructive/5 p-4">
            <p className="flex items-center gap-2 font-semibold"><AlertCircle className="h-5 w-5" aria-hidden="true" />Recherche indisponible</p>
            <p className="mt-1 text-sm text-muted-foreground">{erreur}</p>
            <button type="button" onClick={() => void rechercher(profession, ville)} className="btn-secondary mt-3 min-h-[44px]">Réessayer</button>
          </div>
        )}
        {!loading && !erreur && missions?.length === 0 && (
          <p className="mt-4 text-muted-foreground">Aucune mission ne correspond à ces critères pour le moment.</p>
        )}
        {!!missions?.length && <>
        <p className="text-muted-foreground mt-3 mb-6">{loading || erreur ? 'Résultats de la recherche précédente.' : 'Missions réelles publiées par des établissements vérifiés.'}</p>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4" aria-busy={loading}>
          {missions.slice(0, 6).map((m) => (
            <div key={m.id} className="rounded-2xl border border-border bg-card p-4 flex flex-col gap-2">
              <div className="flex items-start justify-between gap-2">
                <span className="font-semibold text-foreground line-clamp-2">{m.intitule}</span>
                {m.est_urgente && (
                  <span className="inline-flex items-center gap-1 text-xs font-medium text-red-600 shrink-0">
                    <Flame className="h-3.5 w-3.5" /> Urgent
                  </span>
                )}
              </div>
              <p className="text-sm text-muted-foreground inline-flex items-center gap-1">
                <MapPin className="h-3.5 w-3.5" /> {m.ville}{m.code_postal ? ` (${m.code_postal})` : ''}
              </p>
              <p className="text-sm text-muted-foreground inline-flex items-center gap-1">
                <Clock className="h-3.5 w-3.5" />
                {new Date(m.debut_le).toLocaleDateString('fr-FR')} → {new Date(m.fin_le).toLocaleDateString('fr-FR')}
              </p>
              <p className="text-xs font-semibold text-foreground">{libelleContrat(m.type_contrat_recherche)}</p>
              <p className="text-base font-bold text-primary">{Number(m.taux_horaire_base).toFixed(0)} €/h</p>
            </div>
          ))}
        </div>
        </>}
        <div className="mt-6 text-center">
          <button
            onClick={ouvrirInscription}
            className="btn-primary inline-flex items-center gap-2 px-6 py-3 text-base"
          >
            Voir toutes les missions et postuler <ArrowRight className="h-4 w-4" />
          </button>
          <p className="text-xs text-muted-foreground mt-2">Inscription gratuite · sans engagement</p>
        </div>
      </div>
    </section>
  );
}
