import { useEffect, useMemo, useRef, useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { Search, HelpCircle, Loader2, ChevronRight, ArrowLeft, Mail } from 'lucide-react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { useRole } from '@/hooks/useRole';
import { FooterLegal } from '@/components/FooterLegal';
import { ModalContacterJolene } from '@/components/ModalContacterJolene';

interface ArticleResume {
  id: string;
  slug: string;
  titre: string;
  audience: 'SOIGNANT' | 'ETABLISSEMENT' | 'COMMUN';
  categorie: string;
  extrait: string;
  mis_a_jour_le: string;
}

export default function PageAide() {
  usePageTitle('Centre d\'aide');
  const navigate = useNavigate();
  const { user } = useAuth();
  const { role } = useRole();
  const [searchParams, setSearchParams] = useSearchParams();
  const [query, setQuery] = useState(searchParams.get('q') || '');
  const [audience, setAudience] = useState<'TOUS' | 'SOIGNANT' | 'ETABLISSEMENT'>(
    searchParams.get('aud') === 'SOIGNANT' ? 'SOIGNANT' : searchParams.get('aud') === 'ETABLISSEMENT' ? 'ETABLISSEMENT' : 'TOUS',
  );
  const audienceChoisie = useRef(searchParams.has('aud'));
  const [articles, setArticles] = useState<ArticleResume[]>([]);
  const [loading, setLoading] = useState(true);
  const [erreur, setErreur] = useState(false);
  const [tentative, setTentative] = useState(0);
  const [contactOpen, setContactOpen] = useState(false);

  // L'URL suit les filtres sans attendre une réponse réseau.
  useEffect(() => {
    const sp = new URLSearchParams();
    if (query.trim()) sp.set('q', query.trim());
    if (audience !== 'TOUS') sp.set('aud', audience);
    if (sp.toString() !== searchParams.toString()) setSearchParams(sp, { replace: true });
  }, [query, audience, searchParams, setSearchParams]);

  useEffect(() => {
    // Le défaut s'applique une fois ; « Tous » choisi volontairement reste actif.
    if (!audienceChoisie.current && (role === 'SOIGNANT' || role === 'ADMIN_ETABLISSEMENT')) {
      audienceChoisie.current = true;
      setAudience(role === 'SOIGNANT' ? 'SOIGNANT' : 'ETABLISSEMENT');
    }
  }, [role]);

  useEffect(() => {
    let actif = true;
    const controller = new AbortController();
    let delai: ReturnType<typeof setTimeout> | undefined;
    setLoading(true);
    setErreur(false);
    const t = setTimeout(async () => {
      delai = setTimeout(() => controller.abort(), 15_000);
      try {
        const audParam = audience === 'TOUS' ? null : audience;
        const { data, error } = await supabase.rpc('fn_rechercher_aide' as any, {
          p_query: query.trim() || null,
          p_audience: audParam,
        }).abortSignal(controller.signal);
        if (!actif) return;
        if (error) throw error;
        setArticles((data as any)?.articles || []);
      } catch {
        if (actif) setErreur(true);
      } finally {
        clearTimeout(delai);
        if (actif) setLoading(false);
      }
    }, 250);
    return () => { actif = false; clearTimeout(t); clearTimeout(delai); controller.abort(); };
  }, [query, audience, tentative]);

  // Group by category
  const grouped = useMemo(() => {
    const m = new Map<string, ArticleResume[]>();
    for (const a of articles) {
      const arr = m.get(a.categorie) || [];
      arr.push(a);
      m.set(a.categorie, arr);
    }
    return Array.from(m.entries());
  }, [articles]);

  const audienceLabel = (aud: string) =>
    aud === 'SOIGNANT' ? 'Soignant' : aud === 'ETABLISSEMENT' ? 'Établissement' : 'Commun';
  const nettoyerExtrait = (texte: string) => texte
    .replace(/^#{1,6}\s+/gm, '')
    .replace(/\*\*(.*?)\*\*/g, '$1')
    .replace(/`([^`]+)`/g, '$1')
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    .replace(/\s+/g, ' ')
    .trim();

  return (
    <div className="min-h-[100dvh] bg-background">
      <header className="border-b border-border bg-card sticky top-0 z-30" style={{ paddingTop: 'env(safe-area-inset-top)' }}>
        <div className="max-w-5xl mx-auto px-4 py-4 flex items-center gap-3">
          <button onClick={() => user ? navigate(-1) : navigate('/')} className="flex items-center gap-1 text-muted-foreground hover:text-foreground -ml-1 p-1" aria-label="Retour">
            <ArrowLeft className="h-5 w-5" aria-hidden="true" />
          </button>
          <div className="flex items-center gap-2">
            <HelpCircle className="h-6 w-6 text-primary" />
            <h1 className="text-xl font-bold text-foreground">Centre d'aide</h1>
          </div>
        </div>
      </header>

      <main className="max-w-5xl mx-auto px-4 py-6 pb-24 space-y-6">
        {/* Recherche + filtres */}
        <div className="space-y-3">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-5 w-5 text-muted-foreground" />
            <input
              type="search"
              aria-label="Rechercher dans le centre d'aide"
              value={query}
              onChange={e => setQuery(e.target.value)}
              placeholder="Rechercher dans l'aide (mandat, facture, pointage...)"
              className="w-full pl-10 pr-4 py-3 rounded-xl border border-border bg-card text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/30"
              autoFocus
            />
          </div>
          <div className="flex flex-wrap gap-2">
            {(['TOUS', 'SOIGNANT', 'ETABLISSEMENT'] as const).map(a => (
              <button
                key={a}
                onClick={() => { audienceChoisie.current = true; setAudience(a); }}
                aria-pressed={audience === a}
                className={`px-3 py-1.5 rounded-full text-sm font-medium transition-colors ${audience === a ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground hover:bg-muted/80'}`}
              >
                {a === 'TOUS' ? 'Tous' : audienceLabel(a)}
              </button>
            ))}
          </div>
        </div>

        {loading ? (
          <div className="flex items-center justify-center py-20">
            <Loader2 className="h-8 w-8 animate-spin text-primary" />
          </div>
        ) : erreur ? (
          <div role="alert" className="text-center py-12 space-y-3">
            <p className="text-foreground">Impossible de charger les articles. Vérifiez votre connexion et réessayez.</p>
            <button type="button" onClick={() => setTentative(value => value + 1)} className="btn-primary">Réessayer</button>
          </div>
        ) : articles.length === 0 ? (
          <div className="text-center py-12">
            <p className="text-muted-foreground">
              {query.trim() ? `Aucun article ne correspond à "${query}".` : 'Aucun article disponible.'}
            </p>
            <p className="text-xs text-muted-foreground mt-2">
              Pas trouvé ?{' '}
              <button onClick={() => setContactOpen(true)} className="text-primary hover:underline">
                Contactez Jolene
              </button>
            </p>
          </div>
        ) : (
          <div className="space-y-6">
            {grouped.map(([categorie, items]) => (
              <section key={categorie}>
                <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground mb-3">{categorie}</h2>
                <div className="space-y-2">
                  {items.map(a => (
                    <Link
                      key={a.id}
                      to={`/aide/${a.slug}`}
                      className="block rounded-xl border border-border bg-card p-4 hover:border-primary/40 hover:bg-card/80 transition-colors group"
                    >
                      <div className="flex items-start justify-between gap-3">
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2 mb-1">
                            <h3 className="font-semibold text-foreground group-hover:text-primary transition-colors">{a.titre}</h3>
                            <span className={`text-xs font-bold px-2 py-0.5 rounded-full ${a.audience === 'SOIGNANT' ? 'bg-primary text-primary-foreground' : a.audience === 'ETABLISSEMENT' ? 'bg-info text-info-foreground' : 'bg-foreground text-background'}`}>
                              {audienceLabel(a.audience)}
                            </span>
                          </div>
                          <p className="text-sm text-muted-foreground line-clamp-2">{nettoyerExtrait(a.extrait)}</p>
                        </div>
                        <ChevronRight className="h-5 w-5 text-muted-foreground group-hover:text-primary shrink-0 mt-1" />
                      </div>
                    </Link>
                  ))}
                </div>
              </section>
            ))}

            {/* Re-homing du contact (le FAB « ? » global a été retiré) :
                accès permanent au formulaire depuis le centre d'aide. */}
            <div className="rounded-xl border border-border bg-card p-4 flex items-center justify-between gap-3">
              <div>
                <p className="text-sm font-semibold text-foreground">Pas trouvé de réponse ?</p>
                <p className="text-xs text-muted-foreground">Notre équipe répond par email sous 24 h ouvrées.</p>
              </div>
              <button
                onClick={() => setContactOpen(true)}
                className="btn-primary text-sm shrink-0 inline-flex items-center gap-1.5"
              >
                <Mail className="h-4 w-4" /> Contacter Jolene
              </button>
            </div>
          </div>
        )}
      </main>

      <ModalContacterJolene open={contactOpen} onClose={() => setContactOpen(false)} source="centre-aide" />
      <FooterLegal />
    </div>
  );
}
