import React, { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { SEOHead } from '@/components/SEOHead';
import { ClipboardList, Users, CheckCircle, MapPin, FileText, Navigation, TrendingUp, UserCheck, PercentCircle, Scale, Receipt, ShieldCheck, HeartPulse, ArrowRight, Search, Loader2 } from 'lucide-react';
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from '@/components/ui/accordion';
import { PROFESSIONS } from '@/lib/constantes';
import { supabase } from '@/integrations/supabase/client';
import { useDebounce } from '@/hooks/useDebounce';
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
    <div ref={ref} className="text-center">
      <p className="text-4xl md:text-5xl font-extrabold text-primary tabular-nums">
        {prefix}{valeur.toLocaleString('fr-FR')}{suffixe}
      </p>
    </div>
  );
}

/* ─── Scroll reveal wrapper ─── */
function RevealOnScroll({ children, className = '', delay = 0 }: { children: React.ReactNode; className?: string; delay?: number }) {
  const ref = useRef<HTMLDivElement>(null);
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const observer = new IntersectionObserver(
      ([entry]) => { if (entry.isIntersecting) setVisible(true); },
      { threshold: 0.15 }
    );
    if (ref.current) observer.observe(ref.current);
    return () => observer.disconnect();
  }, []);

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
  { q: 'Comment fonctionne la commission ?', a: 'Jolene facture une commission dégressive à l\'établissement, calculée sur le montant brut de la mission. Plus vous publiez de missions, plus le taux baisse. Aucun frais pour le soignant.' },
  { q: 'Jolene est-il une agence d\'intérim ?', a: 'Non. Jolene est une plateforme de mise en relation. Le contrat est signé directement entre l\'établissement et le soignant. Nous ne sommes pas employeur.' },
  { q: 'Comment sont vérifiés les soignants ?', a: 'Chaque soignant est vérifié via le Répertoire Partagé des Professionnels de Santé (RPPS). Diplômes, assurance RCP et pièce d\'identité sont contrôlés avant toute mission.' },
  { q: 'Quels types de contrats sont générés ?', a: 'La plateforme génère automatiquement des CDD d\'usage ou des contrats de vacation conformes au Code du Travail, signés électroniquement par les deux parties.' },
  { q: 'Comment fonctionne le pointage ?', a: 'Le soignant pointe son arrivée et son départ via l\'application mobile avec géolocalisation GPS. Le périmètre est vérifié automatiquement par rapport à l\'adresse de l\'établissement.' },
  { q: 'Puis-je passer en libéral via Jolene ?', a: 'Oui. Notre parcours 3 200 heures vous accompagne vers l\'installation en libéral avec un suivi personnalisé, des partenaires (comptabilité, assurance, banque) et une prise en charge partielle des frais.' },
];

/* ─── Public mission search section ─── */
function RechercheMissionsPublique({ navigate }: { navigate: ReturnType<typeof useNavigate> }) {
  const [profession, setProfession] = useState('');
  const [ville, setVille] = useState('');
  const [loading, setLoading] = useState(false);
  const [results, setResults] = useState<any[] | null>(null);
  const [totalCount, setTotalCount] = useState(0);
  const [searched, setSearched] = useState(false);

  const handleSearch = async () => {
    setLoading(true);
    setSearched(true);
    const { data, error } = await supabase.rpc('fn_missions_publiques_recherche', {
      p_profession: profession || null,
      p_ville: ville.trim() || null,
    });
    if (error) {
      console.error('Erreur recherche missions publiques:', error);
    }
    setResults(data || []);
    setTotalCount(data?.[0]?.total_count ?? 0);
    setLoading(false);
  };

  // Auto-load missions on mount (all professions, no city filter)
  useEffect(() => {
    handleSearch();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const formatDate = (d: string) => new Date(d).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' });

  return (
    <section className="py-16 md:py-20 bg-card border-b border-border">
      <div className="max-w-4xl mx-auto px-4">
        <RevealOnScroll>
          <div className="text-center mb-8">
            <h2 className="text-2xl md:text-3xl font-bold mb-2">Découvrez les missions disponibles</h2>
            <p className="text-muted-foreground">Cherchez par profession et localisation — sans inscription.</p>
          </div>

          <div className="flex flex-col sm:flex-row gap-3 max-w-2xl mx-auto mb-8">
            <select
              value={profession}
              onChange={(e) => setProfession(e.target.value)}
              className="flex-1 h-12 rounded-xl border border-input bg-background px-4 text-sm focus:outline-none focus:ring-2 focus:ring-ring"
            >
              <option value="">Toutes les professions</option>
              {PROFESSIONS.map((p) => (
                <option key={p.valeur} value={p.valeur}>{p.label}</option>
              ))}
            </select>
            <input
              type="text"
              placeholder="Ville ou code postal"
              value={ville}
              onChange={(e) => setVille(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && handleSearch()}
              className="flex-1 h-12 rounded-xl border border-input bg-background px-4 text-sm focus:outline-none focus:ring-2 focus:ring-ring"
            />
            <button
              onClick={handleSearch}
              disabled={loading}
              className="h-12 px-6 rounded-xl bg-primary text-primary-foreground font-semibold text-sm flex items-center justify-center gap-2 hover:bg-primary/90 transition-colors disabled:opacity-50 shrink-0"
            >
              {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Search className="h-4 w-4" />}
              Voir les missions
            </button>
          </div>

          {/* Results */}
          {searched && !loading && results && (
            <div className="space-y-3">
              {results.length > 0 ? (
                <>
                  <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                    {results.slice(0, 5).map((m) => (
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
                          <span className="mt-2 inline-block text-[10px] font-bold uppercase tracking-wider text-destructive bg-destructive/10 rounded-full px-2 py-0.5">Urgent</span>
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
                  <p className="text-muted-foreground mb-2">Pas de mission pour le moment dans votre zone.</p>
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
  const navigate = useNavigate();
  const [heroVisible, setHeroVisible] = useState(false);

  useEffect(() => {
    requestAnimationFrame(() => setHeroVisible(true));
  }, []);

  return (
    <>
      <SEOHead
        title="Jolene — Staffing médical simplifié"
        description="Plateforme de mise en relation entre établissements de santé et soignants qualifiés. Publiez des missions, signez vos contrats et pointez en ligne."
        url="https://app.joleneapp.com/"
      />
    <div className="min-h-screen bg-background text-foreground overflow-x-hidden">
      {/* ═══ Header ═══ */}
      <header className="sticky top-0 z-50 bg-card/80 backdrop-blur-lg border-b border-border">
        <div className="max-w-6xl mx-auto px-4 h-16 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <HeartPulse className="h-7 w-7 text-primary" />
            <span className="text-xl font-bold text-foreground">Jolene</span>
          </div>
          <div className="flex items-center gap-4">
            <a href="/blog" className="text-sm font-medium text-muted-foreground hover:text-foreground transition-colors hidden sm:inline">Blog</a>
            <a href="/a-propos" className="text-sm font-medium text-muted-foreground hover:text-foreground transition-colors hidden sm:inline">À propos</a>
            <a href="/tarifs" className="text-sm font-medium text-muted-foreground hover:text-foreground transition-colors hidden sm:inline">Tarifs</a>
            <button onClick={() => navigate('/connexion')} className="text-sm font-semibold text-primary hover:text-primary/80 transition-colors">
              Se connecter
            </button>
          </div>
        </div>
      </header>

      {/* ═══ Section 1 — Hero ═══ */}
      <section className="relative overflow-hidden">
        {/* Background */}
        <div className="absolute inset-0 bg-gradient-to-br from-primary/10 via-background to-accent-navy/10 dark:from-primary/5 dark:to-[hsl(222,47%,11%)]" />
        {/* Decorative SVGs */}
        <svg className="absolute top-10 right-[10%] w-64 h-64 opacity-[0.06] dark:opacity-[0.04]" viewBox="0 0 200 200"><circle cx="100" cy="100" r="90" stroke="currentColor" className="text-primary" strokeWidth="2" fill="none" /><circle cx="100" cy="100" r="50" stroke="currentColor" className="text-primary" strokeWidth="1.5" fill="none" /></svg>
        <svg className="absolute bottom-10 left-[5%] w-48 h-48 opacity-[0.06] dark:opacity-[0.04]" viewBox="0 0 100 100"><rect x="20" y="40" width="60" height="20" rx="3" fill="currentColor" className="text-primary" /><rect x="40" y="20" width="20" height="60" rx="3" fill="currentColor" className="text-primary" /></svg>
        <svg className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[500px] h-[500px] opacity-[0.03]" viewBox="0 0 400 400"><circle cx="200" cy="200" r="180" stroke="currentColor" className="text-primary" strokeWidth="1" fill="none" /><circle cx="200" cy="200" r="120" stroke="currentColor" className="text-primary" strokeWidth="0.5" fill="none" /></svg>

        <div className={`relative max-w-3xl mx-auto px-4 pt-20 pb-24 md:pt-28 md:pb-32 text-center transition-all duration-1000 ease-out ${heroVisible ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-6'}`}>
          <h1 className="text-4xl md:text-6xl font-extrabold leading-[1.1] tracking-tight mb-6">
            Trouvez le bon soignant.{' '}
            <span className="text-primary">En quelques clics.</span>
          </h1>
          <p className="text-lg md:text-xl text-muted-foreground max-w-2xl mx-auto mb-10 leading-relaxed">
            La plateforme qui connecte les établissements de santé avec des soignants qualifiés et vérifiés.
          </p>
          <div className="flex flex-col sm:flex-row gap-4 justify-center">
            <button
              onClick={() => navigate('/inscription/soignant')}
              className="inline-flex items-center justify-center gap-2 bg-primary hover:bg-primary/90 text-primary-foreground rounded-xl px-8 py-4 font-semibold text-base transition-all duration-200 shadow-lg shadow-primary/20 hover:shadow-xl hover:shadow-primary/30 hover:-translate-y-0.5"
            >
              Je suis soignant <ArrowRight className="h-4 w-4" />
            </button>
            <button
              onClick={() => navigate('/inscription/etablissement')}
              className="inline-flex items-center justify-center gap-2 border-2 border-foreground text-foreground hover:bg-foreground hover:text-background rounded-xl px-8 py-4 font-semibold text-base transition-all duration-200"
            >
              Je suis un établissement <ArrowRight className="h-4 w-4" />
            </button>
          </div>
        </div>
      </section>

      {/* ═══ Section 1b — Recherche missions publique ═══ */}
      <RechercheMissionsPublique navigate={navigate} />

      {/* ═══ Section 2 — Comment ça marche ═══ */}
      <section className="py-20 md:py-28 bg-card">
        <div className="max-w-5xl mx-auto px-4">
          <RevealOnScroll>
            <h2 className="text-2xl md:text-4xl font-bold text-center mb-4">Comment ça marche</h2>
            <p className="text-muted-foreground text-center mb-14 max-w-lg mx-auto">Trois étapes pour pourvoir un poste en toute sérénité.</p>
          </RevealOnScroll>
          <div className="grid md:grid-cols-3 gap-8 md:gap-12">
            {[
              { icon: ClipboardList, num: '1', titre: 'Publiez une mission', desc: 'Décrivez le poste, les horaires et le taux. La mission est visible en temps réel.' },
              { icon: Users, num: '2', titre: 'Recevez des candidatures', desc: 'Les soignants qualifiés postulent. Consultez leurs profils vérifiés et choisissez.' },
              { icon: CheckCircle, num: '3', titre: 'Gérez tout en ligne', desc: 'Contrat, pointage, facturation : tout est automatisé et conforme.' },
            ].map((step, i) => (
              <RevealOnScroll key={i} delay={i * 150}>
                <div className="flex flex-col items-center text-center group">
                  <div className="w-20 h-20 rounded-2xl bg-primary/10 dark:bg-primary/15 flex items-center justify-center mb-5 group-hover:bg-primary/20 transition-colors duration-300">
                    <step.icon className="h-9 w-9 text-primary" strokeWidth={1.5} />
                  </div>
                  <span className="text-xs font-bold text-primary uppercase tracking-widest mb-2">Étape {step.num}</span>
                  <h3 className="text-lg font-bold text-foreground mb-2">{step.titre}</h3>
                  <p className="text-sm text-muted-foreground leading-relaxed">{step.desc}</p>
                </div>
              </RevealOnScroll>
            ))}
          </div>
        </div>
      </section>

      {/* ═══ Section 3 — Chiffres clés ═══ */}
      <section className="py-20 md:py-24 bg-background">
        <div className="max-w-5xl mx-auto px-4">
          <RevealOnScroll>
            <h2 className="text-2xl md:text-4xl font-bold text-center mb-14">En chiffres</h2>
          </RevealOnScroll>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-8 md:gap-6">
            {[
              { cible: 15, suffixe: '+', label: 'professions' },
              { cible: 24, suffixe: '/7', label: 'missions jour et nuit' },
              { cible: 100, suffixe: '%', label: 'conforme Code du travail' },
              { cible: 0, suffixe: '€', label: "d'abonnement" },
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

      {/* ═══ Section 4 — Double proposition de valeur ═══ */}
      <section className="py-20 md:py-28 bg-card">
        <div className="max-w-5xl mx-auto px-4">
          <RevealOnScroll>
            <h2 className="text-2xl md:text-4xl font-bold text-center mb-14">Une plateforme, deux expériences</h2>
          </RevealOnScroll>
          <div className="grid md:grid-cols-2 gap-6 md:gap-8">
            {/* Soignants */}
            <RevealOnScroll delay={0}>
              <div className="rounded-2xl border border-primary/20 bg-primary/5 dark:bg-primary/10 p-8 md:p-10 h-full">
                <h3 className="text-xl font-bold text-foreground mb-6">Pour les soignants</h3>
                <ul className="space-y-4">
                  {[
                    { icon: MapPin, text: 'Missions près de chez vous' },
                    { icon: FileText, text: 'Contrats générés automatiquement' },
                    { icon: Navigation, text: 'Pointage GPS sécurisé' },
                    { icon: TrendingUp, text: 'Parcours vers le libéral' },
                  ].map((item, i) => (
                    <li key={i} className="flex items-start gap-3">
                      <div className="mt-0.5 w-8 h-8 rounded-lg bg-primary/10 dark:bg-primary/20 flex items-center justify-center shrink-0">
                        <item.icon className="h-4 w-4 text-primary" />
                      </div>
                      <span className="text-foreground font-medium">{item.text}</span>
                    </li>
                  ))}
                </ul>
                <button
                  onClick={() => navigate('/inscription/soignant')}
                  className="mt-8 inline-flex items-center gap-2 text-primary font-semibold text-sm hover:underline underline-offset-4"
                >
                  Créer mon profil <ArrowRight className="h-4 w-4" />
                </button>
              </div>
            </RevealOnScroll>

            {/* Établissements */}
            <RevealOnScroll delay={150}>
              <div className="rounded-2xl border border-border bg-foreground/[0.03] dark:bg-foreground/[0.05] p-8 md:p-10 h-full">
                <h3 className="text-xl font-bold text-foreground mb-6">Pour les établissements</h3>
                <ul className="space-y-4">
                  {[
                    { icon: UserCheck, text: 'Soignants vérifiés (RPPS)' },
                    { icon: PercentCircle, text: 'Commission dégressive' },
                    { icon: Scale, text: 'Conformité Code du travail' },
                    { icon: Receipt, text: 'Facturation automatisée' },
                  ].map((item, i) => (
                    <li key={i} className="flex items-start gap-3">
                      <div className="mt-0.5 w-8 h-8 rounded-lg bg-muted flex items-center justify-center shrink-0">
                        <item.icon className="h-4 w-4 text-foreground" />
                      </div>
                      <span className="text-foreground font-medium">{item.text}</span>
                    </li>
                  ))}
                </ul>
                <button
                  onClick={() => navigate('/inscription/etablissement')}
                  className="mt-8 inline-flex items-center gap-2 text-foreground font-semibold text-sm hover:underline underline-offset-4"
                >
                  Publier une mission <ArrowRight className="h-4 w-4" />
                </button>
              </div>
            </RevealOnScroll>
          </div>
        </div>
      </section>

      {/* ═══ Section 5 — Confiance ═══ */}
      <section className="py-16 md:py-20 bg-background">
        <div className="max-w-5xl mx-auto px-4">
          <RevealOnScroll>
            <p className="text-sm font-semibold text-muted-foreground uppercase tracking-widest text-center mb-8">Ils nous font confiance</p>
          </RevealOnScroll>
          <RevealOnScroll delay={100}>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 max-w-2xl mx-auto mb-10">
              {/* Carte GLS */}
              <div className="flex items-center gap-4 rounded-xl border border-border bg-card p-5">
                <div className="w-14 h-14 rounded-xl bg-primary/10 flex items-center justify-center shrink-0">
                  <span className="text-lg font-extrabold text-primary tracking-tight">GLS</span>
                </div>
                <div>
                  <p className="font-bold text-foreground text-sm">Groupe Leader Santé</p>
                  <p className="text-xs text-muted-foreground">Réseau de 600+ pharmacies d'officine</p>
                </div>
              </div>
              {/* Carte CB */}
              <div className="flex items-center gap-4 rounded-xl border border-border bg-card p-5">
                <div className="w-14 h-14 rounded-xl bg-accent-navy/10 dark:bg-foreground/10 flex items-center justify-center shrink-0">
                  <span className="text-lg font-extrabold text-accent-navy dark:text-foreground tracking-tight">CB</span>
                </div>
                <div>
                  <p className="font-bold text-foreground text-sm">Clinique des Bluets</p>
                  <p className="text-xs text-muted-foreground">Maternité et chirurgie — Paris</p>
                </div>
              </div>
            </div>
            <p className="text-xs text-muted-foreground text-center mb-10">Lettre d'intention signée</p>
          </RevealOnScroll>
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
        <div className="absolute inset-0 bg-gradient-to-br from-primary/10 via-background to-primary/5" />
        <div className="relative max-w-3xl mx-auto px-4 text-center">
          <RevealOnScroll>
            <h2 className="text-2xl md:text-4xl font-bold mb-4">Prêt à simplifier votre staffing médical ?</h2>
            <p className="text-muted-foreground mb-10 max-w-lg mx-auto">Rejoignez des centaines d'établissements et de soignants qui utilisent Jolene au quotidien.</p>
            <div className="flex flex-col sm:flex-row gap-4 justify-center">
              <button
                onClick={() => navigate('/inscription/soignant')}
                className="inline-flex items-center justify-center gap-2 bg-primary hover:bg-primary/90 text-primary-foreground rounded-xl px-8 py-4 font-semibold text-base transition-all duration-200 shadow-lg shadow-primary/20 hover:shadow-xl hover:shadow-primary/30 hover:-translate-y-0.5"
              >
                Je suis soignant <ArrowRight className="h-4 w-4" />
              </button>
              <button
                onClick={() => navigate('/inscription/etablissement')}
                className="inline-flex items-center justify-center gap-2 border-2 border-foreground text-foreground hover:bg-foreground hover:text-background rounded-xl px-8 py-4 font-semibold text-base transition-all duration-200"
              >
                Je suis un établissement <ArrowRight className="h-4 w-4" />
              </button>
            </div>
          </RevealOnScroll>
        </div>
      </section>

      {/* ═══ Footer ═══ */}
      <footer className="border-t border-border bg-card py-12 md:py-16">
        <div className="max-w-6xl mx-auto px-4">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-8 md:gap-12">
            {/* Col 1 */}
            <div className="col-span-2 md:col-span-1">
              <div className="flex items-center gap-2 mb-3">
                <HeartPulse className="h-5 w-5 text-primary" />
                <span className="font-bold text-foreground">Jolene</span>
              </div>
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
                <li><a href="/pharmacie-remplacement" className="hover:text-foreground transition-colors">Remplacement pharmacie</a></li>
                <li><a href="/blog" className="hover:text-foreground transition-colors">Blog</a></li>
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
            <p className="text-xs text-muted-foreground">© 2026 Jolene SAS — Tous droits réservés</p>
          </div>
        </div>
      </footer>
    </div>
    </>
  );
}
