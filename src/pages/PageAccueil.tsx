import React, { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { HeartPulse, Stethoscope, Building2, UserPlus, Search, Banknote } from 'lucide-react';

function CompteurAnime({ cible, suffixe }: { cible: number; suffixe: string }) {
  const [valeur, setValeur] = useState(0);
  const ref = useRef<HTMLDivElement>(null);
  const animated = useRef(false);

  useEffect(() => {
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting && !animated.current) {
          animated.current = true;
          let start = 0;
          const duration = 2000;
          const step = cible / (duration / 16);
          const timer = setInterval(() => {
            start += step;
            if (start >= cible) {
              setValeur(cible);
              clearInterval(timer);
            } else {
              setValeur(Math.floor(start));
            }
          }, 16);
        }
      },
      { threshold: 0.5 }
    );
    if (ref.current) observer.observe(ref.current);
    return () => observer.disconnect();
  }, [cible]);

  return (
    <div ref={ref} className="text-center">
      <p className="text-4xl md:text-5xl font-bold text-primary animate-count-up">
        {valeur.toLocaleString('fr-FR')}{suffixe}
      </p>
    </div>
  );
}

export default function PageAccueil() {
  const navigate = useNavigate();

  const etapes = [
    { icone: UserPlus, titre: 'Créez votre profil', desc: 'En 2 minutes, renseignez vos qualifications' },
    { icone: Search, titre: 'Trouvez des missions', desc: 'Filtrez par lieu, date, spécialité' },
    { icone: Banknote, titre: 'Soyez payé rapidement', desc: 'Paiement sécurisé avec IFM et ICP inclus' },
  ];

  const chiffres = [
    { cible: 2500, suffixe: '+', label: 'soignants inscrits' },
    { cible: 800, suffixe: '+', label: 'établissements partenaires' },
    { cible: 100, suffixe: '%', label: 'conforme Loi Rist' },
  ];

  return (
    <div className="min-h-screen gradient-hero">
      {/* Header */}
      <header className="sticky top-0 z-50 bg-card/80 backdrop-blur-md border-b border-border">
        <div className="max-w-6xl mx-auto px-4 h-16 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <HeartPulse className="h-7 w-7 text-primary" />
            <span className="text-2xl font-bold text-primary-dark">Soin Direct</span>
          </div>
          <button onClick={() => navigate('/connexion')} className="btn-secondary text-sm px-4 py-2">
            Se connecter
          </button>
        </div>
      </header>

      {/* Hero */}
      <section className="max-w-2xl mx-auto px-4 pt-16 pb-20 text-center">
        <h1 className="text-3xl md:text-5xl font-bold text-foreground leading-tight mb-6">
          Soignants et établissements, connectez-vous en un clic
        </h1>
        <p className="text-lg text-muted-foreground mb-10 max-w-xl mx-auto">
          La plateforme de confiance pour le remplacement et l'intérim en santé. 100% conforme Code du Travail et RGPD.
        </p>
        <div className="flex flex-col sm:flex-row gap-4 justify-center">
          <button
            onClick={() => navigate('/inscription/soignant')}
            className="btn-primary text-base px-8 py-4 flex items-center justify-center gap-2"
          >
            <Stethoscope className="h-5 w-5" />
            Je suis soignant
          </button>
          <button
            onClick={() => navigate('/inscription/etablissement')}
            className="btn-secondary text-base px-8 py-4 flex items-center justify-center gap-2"
          >
            <Building2 className="h-5 w-5" />
            Je suis un établissement
          </button>
        </div>
      </section>

      {/* Comment ça marche */}
      <section className="max-w-5xl mx-auto px-4 pb-20">
        <h2 className="text-2xl font-bold text-foreground text-center mb-10">Comment ça marche</h2>
        <div className="grid md:grid-cols-3 gap-6">
          {etapes.map((e, i) => (
            <div key={i} className="card-base text-center hover:shadow-md transition-shadow">
              <div className="mx-auto w-14 h-14 rounded-2xl bg-primary/10 flex items-center justify-center mb-4">
                <e.icone className="h-7 w-7 text-primary" />
              </div>
              <h3 className="font-semibold text-foreground mb-2">{e.titre}</h3>
              <p className="text-sm text-muted-foreground">{e.desc}</p>
            </div>
          ))}
        </div>
      </section>

      {/* Chiffres clés */}
      <section className="bg-card border-y border-border py-16">
        <div className="max-w-5xl mx-auto px-4">
          <h2 className="text-2xl font-bold text-foreground text-center mb-12">Chiffres clés</h2>
          <div className="grid md:grid-cols-3 gap-10">
            {chiffres.map((c, i) => (
              <div key={i} className="text-center">
                <CompteurAnime cible={c.cible} suffixe={c.suffixe} />
                <p className="text-muted-foreground mt-2">{c.label}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="py-8 text-center text-sm text-muted-foreground border-t border-border bg-card">
        <p>© 2026 Soin Direct SAS — Conforme RGPD · HDS · Code du Travail</p>
        <div className="flex gap-4 justify-center mt-2">
          <a href="#" className="hover:text-foreground transition-colors">Mentions légales</a>
          <a href="#" className="hover:text-foreground transition-colors">CGU</a>
        </div>
      </footer>
    </div>
  );
}
