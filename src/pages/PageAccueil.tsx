import { usePageTitle } from '@/hooks/usePageTitle';
import React, { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { SEOHead } from '@/components/SEOHead';
import { ClipboardList, Users, CheckCircle, MapPin, FileText, Navigation, TrendingUp, UserCheck, PercentCircle, Scale, Receipt, ShieldCheck, ArrowRight, Search, Loader2 } from 'lucide-react';
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from '@/components/ui/accordion';
import { SelectProfession } from '@/components/SelectProfession';
import { Mascotte } from '@/components/mascotte/Mascotte';
import { LogoJolene } from '@/components/LogoJolene';
import { useDebounce } from '@/hooks/useDebounce';
import { publicSupabase } from '@/integrations/supabase/public-client';
import { supabase } from '@/integrations/supabase/client';
import { logger } from '@/lib/logger';
/* ─── Animated counter ─── */
function CompteurAnime({ cible, suffixe, prefix }: { cible: number; suffixe?: string; prefix?: string }) {
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
      { threshold: 0.3 }
    );
    if (ref.current) observer.observe(ref.current);
    return () => observer.disconnect();
  }, [cible]);

  return (
    <div
      ref={ref}
      className="text-center"
      role="img"
      aria-label={`${prefix ?? ''}${cible.toLocaleString('fr-FR')}${suffixe ?? ''}`}
    >
      <p aria-hidden="true" className="text-4xl md:text-5xl font-extrabold text-primary tabular-nums">
        {prefix}{valeur.toLocaleString('fr-FR')}{suffixe}
      </p>
    </div>
  );
}

/* ─── Scroll reveal wrapper ─── */
function RevealOnScroll({ children, className = '', delay = 0 }: { children: React.ReactNode; className?: string; delay?: number }) {
  const ref = useRef<HTMLDivElement>(null);
  // prefers-reduced-motion : pas d'animation d'apparition — le contenu est
  // visible immédiatement (sinon le texte sous la ligne de flottaison reste à
  // opacité 0 tant qu'on ne scrolle pas : illisible pour ces utilisateurs, et
  // axe-core le signalait à juste titre en color-contrast).
  const [visible, setVisible] = useState(() =>
    typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches
  );

  useEffect(() => {
    if (visible) return;
    const observer = new IntersectionObserver(
      ([entry]) => { if (entry.isIntersecting) setVisible(true); },
      { threshold: 0.15 }
    );
    if (ref.current) observer.observe(ref.current);
    return () => observer.disconnect();
  }, [visible]);

  return (
    <div
      ref={ref}
      className={`transition-all duration-700 ease-out ${visible ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-8'} ${className}`}
      style={{ transitionDelay: `${delay}ms` }}
    >
      {children}
    </div>
  );
}

/* ─── FAQ data ─── */
const faqData = [
  { q: 'Comment fonctionne la commission ?', a: 'Jolene facture à l\'établissement une commission de 15 % HT sur la rémunération brute totale due au soignant, soit 18 % TTC avec la TVA de 20 % (base, majorations et indemnités le cas échéant ; taux HT négocié possible pour les groupes). Aucun frais pour le soignant.' },
  { q: 'Jolene est-il une agence d\'intérim ?', a: 'Non. Jolene est une plateforme de mise en relation. Le contrat est signé directement entre l\'établissement et le soignant. Nous ne sommes pas employeur.' },
  { q: 'Comment sont vérifiés les soignants ?', a: 'La vérification est automatique : identité professionnelle, numéro RPPS lorsqu’il existe, diplôme et pièces requises pour le contrat de la mission sont contrôlés. L’assurance RCP est demandée pour les missions libérales.' },
  { q: 'Quels types de contrats sont générés ?', a: 'La plateforme génère automatiquement des CDD, y compris des CDD courts, signés électroniquement par les deux parties. Le libéral n’est proposé que pour les missions explicitement ouvertes par la matrice profession × établissement.' },
  { q: 'Comment fonctionne le pointage ?', a: 'Le soignant pointe son arrivée et son départ via l\'application mobile avec géolocalisation GPS. Le périmètre est vérifié automatiquement par rapport à l\'adresse de l\'établissement.' },
  { q: 'Puis-je passer en libéral via Jolene ?', a: 'Oui, si votre profession peut s\'exercer en libéral (infirmier, kiné, sage-femme…). Notre parcours 3 200 heures vous accompagne vers l\'installation en libéral avec un suivi personnalisé, des partenaires (comptabilité, assurance, banque) et une prise en charge partielle des frais.' },
];

/* ─── Public mission search section ─── */
function normaliserResultatsMissionsPubliques(data: unknown): any[] {
  if (Array.isArray(data)) return data;
  if (data && typeof data === 'object') {
    const maybeObject = data as { missions?: unknown; data?: unknown };
    if (Array.isArray(maybeObject.missions)) return maybeObject.missions;
    if (Array.isArray(maybeObject.data)) return maybeObject.data;
  }
  return [];
}

function RechercheMissionsPublique({ navigate }: { navigate: ReturnType<typeof useNavigate> }) {
  const [profession, setProfession] = useState('');
  const [ville, setVille] = useState('');
  const [loading, setLoading] = useState(false);
  const [results, setResults] = useState<any[] | null>(null);
  const [totalCount, setTotalCount] = useState(0);
  const [searched, setSearched] = useState(false);
  const professionDebounced = useDebounce(profession, 250);
  const villeDebounced = useDebounce(ville, 250);

  const handleSearch = async (nextProfession = professionDebounced, nextVille = villeDebounced) => {
    setLoading(true);
    setSearched(true);

    const professionValue = nextProfession?.trim() || null;
    const villeValue = nextVille?.trim() || null;

    // RPC granté à anon ET authenticated. Sur la page d'accueil (publique, sans
    // session active), le client `supabase` peut échouer avec AbortError quand le
    // refresh token lock est volé entre onglets. On préfère donc le client public
    // dédié (storageKey isolée, pas de refresh) — fallback vers `supabase` si
    // session active pour profiter de l'éventuel cache.
    const { data: { session } } = await supabase.auth.getSession();
    const client = session ? supabase : publicSupabase;
    const { data, error } = await client.rpc('fn_missions_publiques_recherche', {
      p_profession: professionValue,
      p_ville: villeValue,
    } as any);

    logger.debug('missions recherche raw:', { data, error, professionValue, villeValue });

    if (error) {
      // AbortError = annulation côté SDK (lock multi-tabs, navigation, etc.) —
      // pas un vrai échec. Le user verra simplement "Pas de mission" temporairement.
      const isAbort = error?.name === 'AbortError' || /Lock was stolen|aborted|AbortError/i.test(error?.message || '');
      if (isAbort) {
        logger.debug('missions recherche abandonnée (AbortError ignoré)');
      } else {
        logger.error('Erreur recherche missions publiques', error);
      }
      setResults([]);
      setTotalCount(0);
      setLoading(false);
      return;
    }

    const parsedResults = normaliserResultatsMissionsPubliques(data);
    logger.debug('missions recherche parsed:', parsedResults);
    setResults(parsedResults);
    setTotalCount(parsedResults[0]?.total_count ?? parsedResults.length ?? 0);
    setLoading(false);
  };

  useEffect(() => {
    handleSearch(professionDebounced, villeDebounced);
  }, [professionDebounced, villeDebounced]);

  const formatDate = (d: string) => new Date(d).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' });

  return (
    <section className="py-16 md:py-20 bg-card border-b border-border">
      <div className="max-w-4xl mx-auto px-4">
        <RevealOnScroll>
          <div className="text-center mb-8">
            <h2 className="text-2xl md:text-3xl font-bold mb-2 text-foreground">Découvrez les missions disponibles</h2>
            <p className="text-muted-foreground">Cherchez par profession et localisation — sans inscription. Laissez la ville vide pour tout voir.</p>
          </div>

          <div className="flex flex-col sm:flex-row gap-3 max-w-2xl mx-auto mb-8">
            <div className="flex-1">
              <label htmlFor="hero-profession" className="sr-only">Profession à rechercher</label>
              <SelectProfession
                value={profession}
                onChange={setProfession}
                placeholder="Toutes les professions"
                triggerId="hero-profession"
              />
            </div>
            <label htmlFor="hero-ville" className="sr-only">Ville ou code postal</label>
            <input
              id="hero-ville"
              type="text"
              placeholder="Ville ou code postal (optionnel)"
              value={ville}
              onChange={(e) => setVille(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && handleSearch(profession, ville)}
              className="flex-1 h-12 rounded-xl border border-input bg-background px-4 text-sm focus:outline-none focus:ring-2 focus:ring-ring"
            />
            <button
              onClick={() => handleSearch(profession, ville)}
              disabled={loading}
              className="h-12 px-6 rounded-xl bg-primary text-primary-foreground font-semibold text-sm flex items-center justify-center gap-2 hover:bg-primary/90 transition-colors disabled:opacity-50 shrink-0"
            >
              {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Search className="h-4 w-4" />}
              Voir les missions
            </button>
          </div>

          {/* Results */}
          {!loading && results && (
            <div className="space-y-3">
              {results.length > 0 ? (
                <>
                  <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                    {results.map((m) => (
                      <div key={m.id} className="rounded-xl border border-border bg-background p-4 hover:shadow-md transition-shadow">
                        <p className="font-semibold text-foreground text-sm mb-1 line-clamp-1">{m.intitule}</p>
                        <p className="text-xs text-muted-foreground mb-2">
                          Établissement à {m.ville} {m.code_postal ? `(${m.code_postal})` : ''}
                        </p>
                        <div className="flex items-center justify-between text-xs">
                          <span className="text-muted-foreground">
                            {formatDate(m.debut_le)} → {formatDate(m.fin_le)}
                          </span>
                          <span className="font-bold text-primary">{Number(m.taux_horaire_base).toFixed(0)}€/h</span>
                        </div>
                        {m.est_urgente && (
                          <span className="mt-2 inline-block text-xs font-bold uppercase tracking-wider text-destructive-foreground bg-destructive rounded-full px-2 py-0.5">Urgent</span>
                        )}
                      </div>
                    ))}
                  </div>
                  <p className="text-center text-sm text-muted-foreground mt-4">
                    <span className="font-semibold text-foreground">{totalCount} mission{totalCount > 1 ? 's' : ''} disponible{totalCount > 1 ? 's' : ''}</span>
                    {' — '}
                    <button onClick={() => navigate('/inscription/soignant')} className="text-primary font-semibold hover:underline underline-offset-4">
                      Créez votre compte pour postuler →
                    </button>
                  </p>
                </>
              ) : (
                <div className="text-center py-8 rounded-xl border border-dashed border-border bg-muted/30">
                  <p className="text-muted-foreground mb-2">
                    {ville.trim() ? 'Pas de mission pour le moment dans cette zone.' : 'Pas de mission pour le moment pour cette profession.'}
                  </p>
                  <button onClick={() => navigate('/inscription/soignant')} className="text-primary font-semibold text-sm hover:underline underline-offset-4">
                    Inscrivez-vous pour être alerté →
                  </button>
                </div>
              )}
            </div>
          )}
        </RevealOnScroll>
      </div>
    </section>
  );
}

export default function PageAccueil() {
  usePageTitle('Jolene');
  const navigate = useNavigate();
  // prefers-reduced-motion : le hero est visible immédiatement (pas de fondu
  // d'opacité 1 s). Sinon, sous ce réglage, le sous-titre et les badges en
  // text-muted-foreground sont scannés par axe-core EN PLEIN fondu (opacité
  // intermédiaire → contraste effectif réduit → color-contrast SERIOUS).
  // La media-query globale (index.css) ne neutralise que des classes nommées,
  // pas l'utilitaire Tailwind `transition-all` posé inline ici — d'où le besoin
  // de gérer le cas en JS, comme RevealOnScroll.
  const [heroVisible, setHeroVisible] = useState(
    () => typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches,
  );

  useEffect(() => {
    if (heroVisible) return;
    requestAnimationFrame(() => setHeroVisible(true));
  }, [heroVisible]);

  return (
    <>
      <SEOHead
        title="Jolene Santé — Missions soignants & remplacements vérifiés"
        description="Jolene Santé connecte établissements de santé et soignants vérifiés (diplôme, RPPS, assurance) pour des missions et remplacements ponctuels. Inscription gratuite, contrats automatisés."
        url="https://jolene.app/"
        jsonLd={{
          "@context": "https://schema.org",
          "@type": "WebApplication",
          "name": "Jolene",
          "url": "https://jolene.app",
          "description": "Plateforme de staffing médical pour établissements de santé et soignants qualifiés en France.",
          "applicationCategory": "HealthApplication",
          "operatingSystem": "Web, iOS, Android",
          "offers": { "@type": "Offer", "price": "0", "priceCurrency": "EUR", "description": "Inscription gratuite pour les soignants" },
          "creator": { "@type": "Organization", "name": "Jolene SASU", "url": "https://jolene.app", "address": { "@type": "PostalAddress", "streetAddress": "103 rue de Vaugirard", "addressLocality": "Paris", "postalCode": "75006", "addressCountry": "FR" } }
        }}
      />
    <div className="min-h-[100dvh] bg-background text-foreground overflow-x-hidden">
      {/* ═══ Header ═══ */}
      <header className="sticky top-0 z-50 bg-card/80 backdrop-blur-lg border-b border-border">
        <div className="max-w-6xl mx-auto px-4 h-16 flex items-center justify-between">
          <LogoJolene
            imageClassName="h-7 w-7"
            nomClassName="text-xl text-rose"
          />
          <div className="flex items-center gap-4">
<a href="/a-propos" className="text-sm font-medium text-muted-foreground hover:text-foreground transition-colors hidden sm:inline">À propos</a>
            <a href="/tarifs" className="text-sm font-medium text-muted-foreground hover:text-foreground transition-colors hidden sm:inline">Tarifs</a>
            <button onClick={() => navigate('/connexion')} className="text-sm font-semibold text-primary hover:text-primary/80 transition-colors" data-testid="header-cta-connexion">
              Se connecter
            </button>
          </div>
        </div>
      </header>

      <main id="contenu-principal">
      {/* ═══ Section 1 — Hero ═══ */}
      <section className="relative overflow-hidden">
        {/* Vibrant gradient background */}
        <div className="absolute inset-0" style={{ background: 'linear-gradient(135deg, hsl(330 85% 60% / 0.12) 0%, hsl(270 60% 50% / 0.1) 30%, hsl(215 80% 55% / 0.08) 60%, hsl(174 72% 48% / 0.06) 100%)' }} />
        {/* Fun decorative blobs */}
        <div className="absolute top-20 right-[15%] w-72 h-72 rounded-full opacity-[0.08]" style={{ background: 'radial-gradient(circle, hsl(330 85% 60%), transparent 70%)' }} />
        <div className="absolute bottom-10 left-[10%] w-56 h-56 rounded-full opacity-[0.06]" style={{ background: 'radial-gradient(circle, hsl(215 80% 55%), transparent 70%)' }} />
        <div className="absolute top-1/3 left-1/2 w-96 h-96 rounded-full opacity-[0.04]" style={{ background: 'radial-gradient(circle, hsl(270 60% 50%), transparent 70%)' }} />

        <div className={`relative max-w-3xl mx-auto px-4 pt-14 pb-20 md:pt-20 md:pb-28 text-center transition-all duration-1000 ease-out ${heroVisible ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-6'}`}>
          <div className="flex justify-center mb-4">
            <Mascotte etat="happy" taille="md" />
          </div>
          <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-primary/10 text-primary text-sm font-semibold mb-6">
            ✨ Missions, contrats, paie : tout-en-un
          </div>
          <h1 className="text-4xl md:text-6xl font-extrabold leading-[1.1] tracking-tight mb-6">
            Le remplacement santé,{' '}
            <span className="bg-clip-text text-transparent" style={{ backgroundImage: 'linear-gradient(135deg, hsl(330 85% 55%), hsl(270 60% 50%), hsl(215 80% 55%))' }}>
              enfin simple.
            </span>
          </h1>
          <p className="text-lg md:text-xl text-muted-foreground max-w-2xl mx-auto mb-8 leading-relaxed">
            Établissements et soignants connectés en direct. Contrat signé
            en ligne, pointage GPS, paiement suivi — zéro paperasse.
          </p>
          <div className="flex flex-col sm:flex-row gap-4 justify-center">
            <button
              onClick={() => navigate('/inscription/soignant')}
              className="inline-flex items-center justify-center gap-2 text-white rounded-2xl px-5 py-3 sm:px-8 sm:py-4 font-semibold text-base transition-all duration-200 shadow-lg hover:shadow-xl hover:-translate-y-0.5"
              style={{ background: 'linear-gradient(135deg, hsl(330 85% 55%), hsl(270 60% 50%))' }}
              data-testid="hero-cta-soignant"
            >
              🩺 Je suis soignant <ArrowRight className="h-4 w-4" />
            </button>
            <button
              onClick={() => navigate('/inscription/etablissement')}
              className="inline-flex items-center justify-center gap-2 text-white rounded-2xl px-5 py-3 sm:px-8 sm:py-4 font-semibold text-base transition-all duration-200 shadow-lg hover:shadow-xl hover:-translate-y-0.5"
              style={{ background: 'linear-gradient(135deg, hsl(215 80% 55%), hsl(174 72% 48%))' }}
              data-testid="hero-cta-etab"
            >
              🏥 Je suis un établissement <ArrowRight className="h-4 w-4" />
            </button>
          </div>
          {/* Micro-preuves : que des faits produit, pas de chiffres inventés */}
          <div className="flex flex-wrap justify-center gap-x-5 gap-y-2 mt-7 text-xs sm:text-sm text-muted-foreground">
            <span className="inline-flex items-center gap-1.5"><CheckCircle className="h-3.5 w-3.5 text-primary" /> 0 € pour les soignants</span>
            <span className="inline-flex items-center gap-1.5"><CheckCircle className="h-3.5 w-3.5 text-primary" /> Diplômes vérifiés par IA</span>
            <span className="inline-flex items-center gap-1.5"><CheckCircle className="h-3.5 w-3.5 text-primary" /> Contrats signés en ligne</span>
            <span className="inline-flex items-center gap-1.5"><CheckCircle className="h-3.5 w-3.5 text-primary" /> Toutes professions de santé, salariat &amp; libéral</span>
          </div>
        </div>
      </section>

      {/* ═══ Section 1b — Recherche missions publique ═══ */}
      <RechercheMissionsPublique navigate={navigate} />

      {/* ═══ Section 2 — Double proposition de valeur (remontée : le visiteur
          s'identifie d'abord, le « comment » vient ensuite) ═══ */}
      <section className="py-20 md:py-28 bg-background">
        <div className="max-w-5xl mx-auto px-4">
          <RevealOnScroll>
            <h2 className="text-2xl md:text-4xl font-bold text-center mb-14">Une plateforme, deux expériences 🤝</h2>
          </RevealOnScroll>
          <div className="grid md:grid-cols-2 gap-6 md:gap-8">
            {/* Soignants */}
            <RevealOnScroll delay={0}>
              <div className="rounded-2xl p-8 md:p-10 h-full border-0 shadow-lg" style={{ background: 'linear-gradient(135deg, hsl(330 85% 60% / 0.08), hsl(270 60% 50% / 0.05))' }}>
                <h3 className="text-xl font-bold text-foreground mb-6">🩺 Pour les soignants</h3>
                <ul className="space-y-4">
                  {[
                    { emoji: '📍', text: 'Missions près de chez vous, en liste ou en swipe' },
                    { emoji: '💶', text: 'Rémunération affichée avant de postuler, paiement suivi' },
                    { emoji: '📄', text: 'Contrats générés et signés en ligne' },
                    { emoji: '🚀', text: 'Parcours accompagné vers le libéral (3 200 h)' },
                  ].map((item, i) => (
                    <li key={i} className="flex items-start gap-3">
                      <span className="text-xl mt-0.5">{item.emoji}</span>
                      <span className="text-foreground font-medium">{item.text}</span>
                    </li>
                  ))}
                </ul>
                <button
                  onClick={() => navigate('/inscription/soignant')}
                  className="mt-8 inline-flex items-center gap-2 text-white font-semibold text-sm rounded-xl px-6 py-3 transition-all hover:-translate-y-0.5 shadow-md"
                  style={{ background: 'linear-gradient(135deg, hsl(330 85% 55%), hsl(270 60% 50%))' }}
                >
                  Créer mon profil gratuit ✨ <ArrowRight className="h-4 w-4" />
                </button>
              </div>
            </RevealOnScroll>

            {/* Établissements */}
            <RevealOnScroll delay={150}>
              <div className="rounded-2xl p-8 md:p-10 h-full border-0 shadow-lg" style={{ background: 'linear-gradient(135deg, hsl(215 80% 55% / 0.08), hsl(174 72% 48% / 0.05))' }}>
                <h3 className="text-xl font-bold text-foreground mb-6">🏥 Pour les établissements</h3>
                <ul className="space-y-4">
                  {[
                    { emoji: '✅', text: 'Soignants vérifiés : identité, diplôme, RPPS et pièces adaptées à la mission' },
                    { emoji: '⚡', text: 'Remplaçant trouvé en urgence, garantie no-show' },
                    { emoji: '⚖️', text: 'DPAE, loi Rist, Code du travail : conformité intégrée' },
                    { emoji: '🧾', text: 'Facturation automatisée, Chorus Pro inclus' },
                  ].map((item, i) => (
                    <li key={i} className="flex items-start gap-3">
                      <span className="text-xl mt-0.5">{item.emoji}</span>
                      <span className="text-foreground font-medium">{item.text}</span>
                    </li>
                  ))}
                </ul>
                <button
                  onClick={() => navigate('/inscription/etablissement')}
                  className="mt-8 inline-flex items-center gap-2 text-white font-semibold text-sm rounded-xl px-6 py-3 transition-all hover:-translate-y-0.5 shadow-md"
                  style={{ background: 'linear-gradient(135deg, hsl(215 80% 55%), hsl(174 72% 48%))' }}
                >
                  Publier ma première mission 🎯 <ArrowRight className="h-4 w-4" />
                </button>
              </div>
            </RevealOnScroll>
          </div>
        </div>
      </section>

      {/* ═══ Section 3 — Comment ça marche ═══ */}
      <section className="py-20 md:py-28 bg-card">
        <div className="max-w-5xl mx-auto px-4">
          <RevealOnScroll>
            <h2 className="text-2xl md:text-4xl font-bold text-center mb-4">Comment ça marche 🚀</h2>
            <p className="text-muted-foreground text-center mb-14 max-w-lg mx-auto">Trois étapes, côté soignant comme côté établissement</p>
          </RevealOnScroll>
          <div className="grid md:grid-cols-3 gap-8 md:gap-12">
            {[
              { icon: ClipboardList, num: '1', emoji: '📝', titre: 'Publiez ou postulez', desc: 'L\'établissement publie sa mission avec horaires et taux. Le soignant postule ou accepte en 1 clic.' },
              { icon: Users, num: '2', emoji: '✍️', titre: 'Le contrat se signe en ligne', desc: 'Contrat conforme généré automatiquement, signé électroniquement par les deux parties.' },
              { icon: CheckCircle, num: '3', emoji: '🎉', titre: 'Tout le reste est automatique', desc: 'Pointage GPS, facture, paiement, déclarations : zéro paperasse pour les deux côtés.' },
            ].map((step, i) => (
              <RevealOnScroll key={i} delay={i * 150}>
                <div className="flex flex-col items-center text-center group">
                  <div className="w-20 h-20 rounded-2xl flex items-center justify-center mb-5 shadow-lg group-hover:scale-105 transition-transform duration-300" style={{ background: i === 0 ? 'linear-gradient(135deg, hsl(330 85% 60% / 0.15), hsl(330 85% 60% / 0.05))' : i === 1 ? 'linear-gradient(135deg, hsl(270 60% 50% / 0.15), hsl(270 60% 50% / 0.05))' : 'linear-gradient(135deg, hsl(174 72% 48% / 0.15), hsl(174 72% 48% / 0.05))' }}>
                    <span className="text-3xl">{step.emoji}</span>
                  </div>
                  <span className="text-xs font-bold uppercase tracking-widest mb-2 bg-clip-text text-transparent" style={{ backgroundImage: 'linear-gradient(135deg, hsl(330 85% 55%), hsl(270 60% 50%))' }}>Étape {step.num}</span>
                  <h3 className="text-lg font-bold text-foreground mb-2">{step.titre}</h3>
                  <p className="text-sm text-muted-foreground leading-relaxed">{step.desc}</p>
                </div>
              </RevealOnScroll>
            ))}
          </div>
        </div>
      </section>

      {/* ═══ Section 3 — Chiffres clés ═══ */}
      <section className="py-20 md:py-24 relative overflow-hidden">
        <div className="absolute inset-0 opacity-[0.04]" style={{ background: 'linear-gradient(135deg, hsl(330 85% 60%), hsl(270 60% 50%), hsl(215 80% 55%))' }} />
        <div className="relative max-w-5xl mx-auto px-4">
          <RevealOnScroll>
            <h2 className="text-2xl md:text-4xl font-bold text-center mb-14">En chiffres 📊</h2>
          </RevealOnScroll>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-8 md:gap-6">
            {[
              { cible: 15, suffixe: '+', label: '👩‍⚕️ professions', emoji: '💼' },
              { cible: 24, suffixe: '/7', label: '🌙 missions jour et nuit', emoji: '⏰' },
              { cible: 100, suffixe: '%', label: '✅ conforme Code du travail', emoji: '⚖️' },
              { cible: 0, suffixe: '€', label: "💸 d'abonnement", emoji: '🆓' },
            ].map((c, i) => (
              <RevealOnScroll key={i} delay={i * 100}>
                <div className="text-center">
                  <CompteurAnime cible={c.cible} suffixe={c.suffixe} />
                  <p className="text-sm text-muted-foreground mt-2 font-medium">{c.label}</p>
                </div>
              </RevealOnScroll>
            ))}
          </div>
        </div>
      </section>

      {/* ═══ Section 5 — Conformité ═══ */}
      <section className="py-16 md:py-20 bg-background">
        <div className="max-w-5xl mx-auto px-4">
          <RevealOnScroll delay={200}>
            <div className="flex flex-wrap justify-center gap-4">
              {['Conforme RGPD', 'Conforme Code du Travail', 'Signature électronique eIDAS'].map((badge) => (
                <span key={badge} className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-primary/10 dark:bg-primary/15 text-primary text-sm font-semibold">
                  <ShieldCheck className="h-4 w-4" /> {badge}
                </span>
              ))}
            </div>
          </RevealOnScroll>
        </div>
      </section>

      {/* ═══ Section 6 — FAQ ═══ */}
      <section className="py-20 md:py-28 bg-card">
        <div className="max-w-3xl mx-auto px-4">
          <RevealOnScroll>
            <h2 className="text-2xl md:text-4xl font-bold text-center mb-12">Questions fréquentes</h2>
          </RevealOnScroll>
          <RevealOnScroll delay={100}>
            <Accordion type="single" collapsible className="space-y-2">
              {faqData.map((faq, i) => (
                <AccordionItem key={i} value={`faq-${i}`} className="border border-border rounded-xl px-5 data-[state=open]:bg-muted/50 transition-colors">
                  <AccordionTrigger className="text-left text-[15px] font-semibold hover:no-underline py-5">
                    {faq.q}
                  </AccordionTrigger>
                  <AccordionContent className="text-muted-foreground leading-relaxed pb-5">
                    {faq.a}
                  </AccordionContent>
                </AccordionItem>
              ))}
            </Accordion>
          </RevealOnScroll>
        </div>
      </section>

      {/* ═══ Section 7 — CTA final ═══ */}
      <section className="relative py-20 md:py-28 overflow-hidden">
        <div className="absolute inset-0" style={{ background: 'linear-gradient(135deg, hsl(330 85% 60% / 0.08) 0%, hsl(270 60% 50% / 0.06) 50%, hsl(215 80% 55% / 0.04) 100%)' }} />
        <div className="relative max-w-3xl mx-auto px-4 text-center">
          <RevealOnScroll>
            <h2 className="text-2xl md:text-4xl font-bold mb-4">Prêt à simplifier vos remplacements ? 🎉</h2>
            <p className="text-muted-foreground mb-10 max-w-lg mx-auto">Inscription gratuite en 2 minutes — première mission possible dès aujourd'hui 🩷</p>
            <div className="flex flex-col sm:flex-row gap-4 justify-center">
              <button
                onClick={() => navigate('/inscription/soignant')}
                className="inline-flex items-center justify-center gap-2 text-white rounded-2xl px-5 py-3 sm:px-8 sm:py-4 font-semibold text-base transition-all duration-200 shadow-lg hover:shadow-xl hover:-translate-y-0.5"
                style={{ background: 'linear-gradient(135deg, hsl(330 85% 55%), hsl(270 60% 50%))' }}
                data-testid="bottom-cta-soignant"
              >
                🩺 Je suis soignant <ArrowRight className="h-4 w-4" />
              </button>
              <button
                onClick={() => navigate('/inscription/etablissement')}
                className="inline-flex items-center justify-center gap-2 text-white rounded-2xl px-5 py-3 sm:px-8 sm:py-4 font-semibold text-base transition-all duration-200 shadow-lg hover:shadow-xl hover:-translate-y-0.5"
                style={{ background: 'linear-gradient(135deg, hsl(215 80% 55%), hsl(174 72% 48%))' }}
                data-testid="bottom-cta-etab"
              >
                🏥 Je suis un établissement <ArrowRight className="h-4 w-4" />
              </button>
            </div>
          </RevealOnScroll>
        </div>
      </section>
      </main>

      {/* ═══ Footer ═══ */}
      <footer className="border-t border-border bg-card py-12 md:py-16">
        <div className="max-w-6xl mx-auto px-4">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-8 md:gap-12">
            {/* Col 1 */}
            <div className="col-span-2 md:col-span-1">
              <LogoJolene
                className="mb-3"
                imageClassName="h-5 w-5"
                nomClassName="text-rose"
              />
              <p className="text-sm text-muted-foreground leading-relaxed">La plateforme de confiance pour le remplacement et le staffing en santé.</p>
            </div>
            {/* Col 2 */}
            <div>
              <h4 className="font-semibold text-foreground text-sm mb-3">Plateforme</h4>
              <ul className="space-y-2 text-sm text-muted-foreground">
                <li><a href="/inscription/soignant" className="hover:text-foreground transition-colors">Soignants</a></li>
                <li><a href="/inscription/etablissement" className="hover:text-foreground transition-colors">Établissements</a></li>
                <li><a href="/tarifs" className="hover:text-foreground transition-colors">Tarifs</a></li>
                <li><a href="/a-propos" className="hover:text-foreground transition-colors">À propos</a></li>
                <li><a href="/telecharger" className="hover:text-foreground transition-colors">Télécharger</a></li>
              </ul>
            </div>
            {/* Col 3 — Ressources */}
            <div>
              <h4 className="font-semibold text-foreground text-sm mb-3">Ressources</h4>
              <ul className="space-y-2 text-sm text-muted-foreground">
                <li><a href="/devenir-soignant" className="hover:text-foreground transition-colors">Devenir soignant</a></li>
                <li><a href="/recruter-soignants" className="hover:text-foreground transition-colors">Recruter des soignants</a></li>
                <li><a href="/infirmiere-liberale" className="hover:text-foreground transition-colors">Passer en libéral</a></li>
              </ul>
            </div>
            {/* Col 4 */}
            <div>
              <h4 className="font-semibold text-foreground text-sm mb-3">Légal</h4>
              <ul className="space-y-2 text-sm text-muted-foreground">
                <li><a href="/cgu" className="hover:text-foreground transition-colors">CGU</a></li>
                <li><a href="/cgv" className="hover:text-foreground transition-colors">CGV</a></li>
                <li><a href="/confidentialite" className="hover:text-foreground transition-colors">Confidentialité</a></li>
                <li><a href="/mentions-legales" className="hover:text-foreground transition-colors">Mentions légales</a></li>
              </ul>
            </div>
          </div>
          <div className="border-t border-border mt-10 pt-6 text-center">
            <p className="text-xs text-muted-foreground">© 2026 Jolene SASU — Tous droits réservés</p>
          </div>
        </div>
      </footer>
    </div>
    </>
  );
}
