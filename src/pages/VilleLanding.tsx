import React, { useEffect, useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { SEOHead } from '@/components/SEOHead';
import { SEOPageLayout } from '@/components/SEOPageLayout';
import { PROFESSIONS_SEO, getVilleBySlug, VILLES_SEO } from '@/lib/seo-data';
import { MissionsPubliquesSEO } from '@/components/MissionsPubliquesSEO';
import { MapPin, Users, Building2, Clock, ArrowRight, Stethoscope, Activity } from 'lucide-react';

function AnimatedCounter({ target, suffix = '' }: { target: number; suffix?: string }) {
  const [count, setCount] = useState(0);

  useEffect(() => {
    const duration = 1500;
    const steps = 40;
    const increment = target / steps;
    let current = 0;
    const interval = setInterval(() => {
      current += increment;
      if (current >= target) {
        setCount(target);
        clearInterval(interval);
      } else {
        setCount(Math.floor(current));
      }
    }, duration / steps);
    return () => clearInterval(interval);
  }, [target]);

  return <span>{count.toLocaleString('fr-FR')}{suffix}</span>;
}

const etapes = [
  { num: '1', titre: 'Inscrivez-vous gratuitement', desc: 'Créez votre compte en 2 minutes. Renseignez votre profession et votre zone géographique.' },
  { num: '2', titre: 'Validez votre profil', desc: 'Téléversez votre diplôme, votre RPPS lorsqu’il existe et les pièces requises par le contrat (dont la RCP pour le libéral).' },
  { num: '3', titre: 'Acceptez vos missions', desc: 'Recevez des propositions de missions près de chez vous et postulez en un clic.' },
];

export default function VilleLanding() {
  const { ville: villeSlug } = useParams<{ ville: string }>();
  const navigate = useNavigate();
  const ville = villeSlug ? getVilleBySlug(villeSlug) : undefined;

  // Capitalize slug as fallback display name
  const villeNom = ville?.nom || (villeSlug ? villeSlug.charAt(0).toUpperCase() + villeSlug.slice(1).replace(/-/g, ' ') : 'votre ville');
  const villeDept = ville?.departement || '';

  return (
    <>
      <SEOHead
        title={`Missions soignants à ${villeNom} | Jolene Santé`}
        description={`Missions de remplacement santé à ${villeNom}${villeDept ? ` (${villeDept})` : ''} : infirmiers, aides-soignants et professionnels de santé. Inscription gratuite et contrats clairement indiqués.`}
        url={`https://jolene.app/emploi-soignant/${villeSlug}`}
      />
      <SEOPageLayout
        heroTitle={`Missions soignants à ${villeNom}`}
        heroSubtitle={`Trouvez des remplacements et CDD courts en santé à ${villeNom}${villeDept ? ` (${villeDept})` : ''}. Hôpitaux, cliniques, EHPAD et établissements médico-sociaux.`}
        ctaText="Voir les missions disponibles"
        ctaHref="/inscription/soignant"
      >
        {/* Professions grid */}
        <section className="py-16 md:py-20">
          <div className="max-w-6xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-4">
              Professions recherchées à {villeNom}
            </h2>
            <p className="text-center text-muted-foreground max-w-2xl mx-auto mb-12">
              Les établissements de santé de {villeNom} recrutent activement des professionnels qualifiés dans toutes les spécialités.
            </p>
            <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
              {PROFESSIONS_SEO.map((p) => (
                <button
                  key={p.valeur}
                  onClick={() => navigate('/inscription/soignant')}
                  className="group bg-card border border-border rounded-xl p-5 text-left hover:border-primary/40 hover:shadow-md transition-all"
                >
                  <div className="flex items-center justify-between mb-2">
                    <h3 className="font-semibold text-foreground text-sm group-hover:text-primary transition-colors">{p.label}</h3>
                    <ArrowRight className="h-4 w-4 text-muted-foreground group-hover:text-primary transition-colors" />
                  </div>
                  <p className="text-xs text-muted-foreground leading-relaxed">{p.description}</p>
                  <p className="text-xs font-semibold text-primary mt-2">{p.salaire_moyen}</p>
                </button>
              ))}
            </div>
          </div>
        </section>

        {/* Stats section */}
        <section className="py-16 md:py-20 bg-muted/50">
          <div className="max-w-5xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-12">
              Jolene en chiffres
            </h2>
            <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-8">
              <div className="text-center">
                <div className="w-14 h-14 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto mb-4">
                  <Users className="h-7 w-7 text-primary" />
                </div>
                <p className="text-3xl font-extrabold text-foreground"><AnimatedCounter target={5000} suffix="+" /></p>
                <p className="text-sm text-muted-foreground mt-1">Soignants inscrits</p>
              </div>
              <div className="text-center">
                <div className="w-14 h-14 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto mb-4">
                  <Building2 className="h-7 w-7 text-primary" />
                </div>
                <p className="text-3xl font-extrabold text-foreground"><AnimatedCounter target={800} suffix="+" /></p>
                <p className="text-sm text-muted-foreground mt-1">Établissements partenaires</p>
              </div>
              <div className="text-center">
                <div className="w-14 h-14 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto mb-4">
                  <Stethoscope className="h-7 w-7 text-primary" />
                </div>
                <p className="text-3xl font-extrabold text-foreground"><AnimatedCounter target={15} /></p>
                <p className="text-sm text-muted-foreground mt-1">Professions couvertes</p>
              </div>
              <div className="text-center">
                <div className="w-14 h-14 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto mb-4">
                  <Clock className="h-7 w-7 text-primary" />
                </div>
                <p className="text-3xl font-extrabold text-foreground"><AnimatedCounter target={24} suffix="h" /></p>
                <p className="text-sm text-muted-foreground mt-1">Délai moyen de placement</p>
              </div>
            </div>
          </div>
        </section>

        {/* Comment ça marche */}
        <section className="py-16 md:py-20">
          <div className="max-w-4xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-12">Comment ça marche</h2>
            <div className="space-y-8">
              {etapes.map((e) => (
                <div key={e.num} className="flex gap-5 items-start">
                  <div className="w-10 h-10 rounded-full bg-primary text-primary-foreground flex items-center justify-center font-bold text-lg shrink-0">{e.num}</div>
                  <div>
                    <h3 className="font-semibold text-foreground text-lg">{e.titre}</h3>
                    <p className="text-muted-foreground mt-1">{e.desc}</p>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* Other cities */}
        <section className="py-16 md:py-20 bg-muted/50">
          <div className="max-w-5xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-8">
              Missions soignants dans d'autres villes
            </h2>
            <div className="flex flex-wrap justify-center gap-3">
              {VILLES_SEO.filter(v => v.slug !== villeSlug).slice(0, 12).map((v) => (
                <a
                  key={v.slug}
                  href={`/emploi-soignant/${v.slug}`}
                  className="inline-flex items-center gap-1.5 bg-card border border-border rounded-lg px-4 py-2 text-sm font-medium text-foreground hover:border-primary/40 hover:text-primary transition-colors"
                >
                  <MapPin className="h-3.5 w-3.5" />
                  {v.nom}
                </a>
              ))}
            </div>
          </div>
        </section>
        <MissionsPubliquesSEO ville={villeNom} campagne={`seo-ville-${villeSlug || ''}`} />
      </SEOPageLayout>
    </>
  );
}
