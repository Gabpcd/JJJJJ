import { useEffect, useMemo, useState } from 'react';
import { useParams, useNavigate, Link } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { SEOHead } from '@/components/SEOHead';
import { FooterLegal } from '@/components/FooterLegal';
import { getLabelProfession } from '@/lib/constantes';
import { MapPin, Clock, Building2, Flame, ArrowRight } from 'lucide-react';
import { LogoJolene } from '@/components/LogoJolene';

function libelleContrat(type: string | null | undefined) {
  if (type === 'LIBERAL') return 'Mission libérale · note d’honoraires';
  if (type === 'TOUS') return 'CDD salarié ou mission libérale selon votre éligibilité';
  return 'CDD salarié · bulletin de paie';
}

/**
 * Page publique d'une mission OUVERTE — indexable par Google for Jobs
 * (JSON-LD schema.org/JobPosting). URL : /mission/:id, listée dans le
 * sitemap dynamique (edge function sitemap-missions). CTA inscription tracé.
 */
export default function MissionPublique() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [mission, setMission] = useState<any | null>(null);
  const [charge, setCharge] = useState(false);

  useEffect(() => {
    if (!id) return;
    (async () => {
      const { data } = await supabase.rpc('fn_mission_publique' as any, { p_id: id });
      setMission(data || null);
      setCharge(true);
    })();
  }, [id]);

  const jsonLd = useMemo(() => {
    if (!mission) return undefined;
    return {
      '@context': 'https://schema.org/',
      '@type': 'JobPosting',
      title: mission.intitule,
      description: mission.description || `Mission ${getLabelProfession(mission.profession_requise) || mission.profession_requise} chez ${mission.etablissement_nom} à ${mission.ville}.`,
      datePosted: mission.cree_le ? new Date(mission.cree_le).toISOString().slice(0, 10) : undefined,
      validThrough: mission.debut_le,
      employmentType: 'TEMPORARY',
      hiringOrganization: {
        '@type': 'Organization',
        name: mission.etablissement_nom,
      },
      jobLocation: {
        '@type': 'Place',
        address: {
          '@type': 'PostalAddress',
          addressLocality: mission.ville,
          postalCode: mission.code_postal,
          addressCountry: 'FR',
        },
      },
      baseSalary: {
        '@type': 'MonetaryAmount',
        currency: 'EUR',
        value: {
          '@type': 'QuantitativeValue',
          value: Number(mission.taux_horaire_base),
          unitText: 'HOUR',
        },
      },
      directApply: false,
      applicantLocationRequirements: { '@type': 'Country', name: 'France' },
    } as Record<string, any>;
  }, [mission]);

  const cta = `/inscription/soignant?utm_source=google-jobs&utm_medium=organic&utm_campaign=mission-publique`;

  return (
    <div className="min-h-[100dvh] bg-background text-foreground flex flex-col">
      <SEOHead
        title={mission ? `${mission.intitule} — ${mission.ville} | Jolene Santé` : 'Mission indisponible — Jolene Santé'}
        description={mission
          ? `Mission ${getLabelProfession(mission.profession_requise) || ''} à ${mission.ville} : ${Number(mission.taux_horaire_base).toFixed(0)} €/h. Consultez les conditions et créez votre compte pour candidater.`
          : 'Cette mission n’est plus disponible.'}
        url={`https://jolene.app/mission/${id}`}
        jsonLd={jsonLd}
        noIndex={charge && !mission}
      />

      <header className="sticky top-0 z-50 bg-card/80 backdrop-blur-lg border-b border-border">
        <div className="max-w-4xl mx-auto px-4 h-16 flex items-center justify-between">
          <a href="/" className="flex items-center gap-2">
            <LogoJolene
              imageClassName="h-7 w-7"
              nomClassName="text-xl text-rose"
            />
          </a>
          <button onClick={() => navigate('/connexion')} className="text-sm font-semibold text-primary hover:text-primary/80 transition-colors">
            Se connecter
          </button>
        </div>
      </header>

      <main className="flex-1">
        {!charge ? (
          <div className="max-w-3xl mx-auto px-4 py-24 text-center text-muted-foreground">Chargement…</div>
        ) : !mission ? (
          <div className="max-w-3xl mx-auto px-4 py-24 text-center space-y-4">
            <h1 className="text-2xl font-bold text-foreground">Cette mission n'est plus disponible</h1>
            <p className="text-muted-foreground">Elle a été pourvue ou clôturée — mais d'autres missions sont publiées chaque jour.</p>
            <Link to={cta} className="btn-primary inline-flex items-center gap-2 px-6 py-3">
              Voir les missions ouvertes <ArrowRight className="h-4 w-4" />
            </Link>
          </div>
        ) : (
          <article className="max-w-3xl mx-auto px-4 py-10 md:py-14">
            <div className="flex items-start justify-between gap-3 mb-3">
              <h1 className="text-2xl md:text-3xl font-bold text-foreground">{mission.intitule}</h1>
              {mission.est_urgente && (
                <span className="inline-flex items-center gap-1 text-sm font-semibold text-red-600 shrink-0 mt-1">
                  <Flame className="h-4 w-4" /> Urgent
                </span>
              )}
            </div>

            <div className="flex flex-wrap gap-x-5 gap-y-2 text-sm text-muted-foreground mb-6">
              <span className="inline-flex items-center gap-1.5">
                <Building2 className="h-4 w-4" /> {mission.etablissement_nom}
              </span>
              <span className="inline-flex items-center gap-1.5">
                <MapPin className="h-4 w-4" /> {mission.ville}{mission.code_postal ? ` (${mission.code_postal})` : ''}
              </span>
              <span className="inline-flex items-center gap-1.5">
                <Clock className="h-4 w-4" />
                {new Date(mission.debut_le).toLocaleDateString('fr-FR')} → {new Date(mission.fin_le).toLocaleDateString('fr-FR')}
              </span>
            </div>

            <div className="rounded-2xl border border-border bg-card p-5 mb-6 flex flex-wrap items-center justify-between gap-4">
              <div>
                <p className="text-sm text-muted-foreground">Rémunération</p>
                <p className="text-3xl font-extrabold text-primary">{Number(mission.taux_horaire_base).toFixed(0)} €/h</p>
                <p className="text-sm font-semibold text-foreground mt-1">
                  {libelleContrat(mission.type_contrat_recherche)}
                </p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Profession</p>
                <p className="text-base font-semibold text-foreground">{getLabelProfession(mission.profession_requise) || mission.profession_requise}</p>
              </div>
              {mission.service && (
                <div>
                  <p className="text-sm text-muted-foreground">Service</p>
                  <p className="text-base font-semibold text-foreground">{mission.service}</p>
                </div>
              )}
            </div>

            {mission.description && (
              <div className="prose prose-sm max-w-none text-foreground mb-8">
                <h2 className="text-lg font-bold mb-2">Description de la mission</h2>
                <p className="whitespace-pre-wrap text-muted-foreground">{mission.description}</p>
              </div>
            )}

            <div className="rounded-2xl bg-gradient-to-r from-primary/10 to-primary/5 border border-primary/20 p-6 text-center space-y-3">
              <h2 className="text-xl font-bold text-foreground">Cette mission vous intéresse ?</h2>
              <p className="text-sm text-muted-foreground">
                Inscription gratuite · établissements vérifiés · conditions et contrat présentés avant l'affectation.
              </p>
              <Link to={cta} className="btn-primary inline-flex items-center gap-2 px-8 py-3 text-base">
                Postuler gratuitement <ArrowRight className="h-4 w-4" />
              </Link>
            </div>
          </article>
        )}
      </main>

      <FooterLegal />
    </div>
  );
}
