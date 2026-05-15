import React, { useMemo } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { SEOHead } from '@/components/SEOHead';
import { articlesBlog, getTagClasses, getArticleGradient } from '@/lib/blog-data';
import { ArrowLeft, ArrowRight, Clock, Calendar, Link2, Linkedin, MessageCircle, Sparkles } from 'lucide-react';
import { sanitizeHTML } from '@/lib/sanitize';
import { Button } from '@/components/ui/button';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { toast } from 'sonner';
import { FadeInView } from '@/components/FadeInView';

const articleEmojis: Record<string, string> = {
  'comment-devenir-idel': '🩺',
  'loi-rist-2025-expliquee': '⚖️',
  'remplacement-pharmacie-guide': '💊',
  'cddu-contrat-usage-sante': '📋',
  'free-transition-liberal': '🚀',
};

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' });
}

function markdownToHtml(md: string): string {
  let html = md
    .replace(/^### (.+)$/gm, '<h3 class="text-lg font-bold text-foreground mt-8 mb-3">$1</h3>')
    .replace(/^## (.+)$/gm, '<h2 class="text-xl font-bold text-foreground mt-10 mb-4">$1</h2>')
    .replace(/\*\*(.+?)\*\*/g, '<strong class="font-semibold text-foreground">$1</strong>')
    .replace(/\*(.+?)\*/g, '<em>$1</em>')
    .replace(/^- (.+)$/gm, '<li class="ml-4 list-disc text-muted-foreground">$1</li>')
    .replace(/^\|(.+)\|$/gm, (_, content) => {
      const cells = content.split('|').map((c: string) => c.trim());
      if (cells.every((c: string) => /^-+$/.test(c))) return '';
      const tag = cells[0] === '' ? 'th' : 'td';
      return `<tr>${cells.map((c: string) => `<${tag} class="border border-border px-3 py-2 text-sm">${c}</${tag}>`).join('')}</tr>`;
    })
    .replace(/\n\n/g, '</p><p class="text-muted-foreground leading-relaxed mb-4">');

  html = `<p class="text-muted-foreground leading-relaxed mb-4">${html}</p>`;
  html = html.replace(/(<tr>.*?<\/tr>)+/gs, (match) => `<table class="w-full border-collapse border border-border my-6">${match}</table>`);
  html = html.replace(/(<li.*?<\/li>)+/gs, (match) => `<ul class="space-y-1 my-4">${match}</ul>`);
  html = html.replace(/<p[^>]*>\s*<\/p>/g, '');

  return html;
}

export default function BlogArticle() {
  const { slug } = useParams<{ slug: string }>();
  const navigate = useNavigate();

  const article = articlesBlog.find((a) => a.slug === slug);
  const idx = articlesBlog.findIndex((a) => a.slug === slug);

  const similaires = useMemo(() => {
    if (!article) return [];
    return articlesBlog.filter((a) => a.slug !== slug).slice(0, 3);
  }, [slug, article]);

  if (!article) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background">
        <div className="text-center">
          <p className="text-4xl mb-4">🔍</p>
          <h1 className="text-2xl font-bold text-foreground mb-2">Article introuvable</h1>
          <BoutonY2K variant="secondary" onClick={() => navigate('/blog')}>Retour au blog</BoutonY2K>
        </div>
      </div>
    );
  }

  const url = `https://jolene.app/blog/${article.slug}`;
  const contenuHtml = sanitizeHTML(markdownToHtml(article.contenu));
  const emoji = articleEmojis[article.slug] || '📖';

  const copierLien = () => {
    navigator.clipboard.writeText(url);
    toast.success('Lien copié dans le presse-papiers 🩷');
  };

  return (
    <>
      <SEOHead
        title={`${article.titre} | Blog Jolene`}
        description={article.extrait}
        url={url}
      />
      <div className="min-h-screen bg-background text-foreground">
        {/* Header */}
        <header className="sticky top-0 z-50 bg-card/80 backdrop-blur-lg border-b border-border">
          <div className="max-w-6xl mx-auto px-4 h-14 flex items-center">
            <button onClick={() => navigate('/blog')} className="flex items-center gap-2 text-sm text-muted-foreground hover:text-primary transition-colors">
              <ArrowLeft className="h-4 w-4" /> Blog
            </button>
          </div>
        </header>

        <div className="max-w-6xl mx-auto px-4 py-10 md:py-16 lg:flex lg:gap-12">
          {/* Main content */}
          <article className="lg:flex-1 max-w-[720px] mx-auto lg:mx-0">
            {/* Hero gradient with emoji */}
            <FadeInView>
              <div className={`h-48 md:h-56 rounded-2xl bg-gradient-to-br ${getArticleGradient(idx)} mb-8 relative overflow-hidden`}>
                <div className="absolute -top-4 -right-4 w-32 h-32 rounded-full bg-white/10 blur-xl" />
                <div className="absolute bottom-6 left-6 w-16 h-16 rounded-full bg-white/10 blur-lg" />
                <span className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 text-6xl md:text-7xl opacity-40">{emoji}</span>
              </div>
            </FadeInView>

            {/* Meta */}
            <FadeInView delay={100}>
              <div className="flex flex-wrap items-center gap-3 mb-6">
                <span className="text-2xl">{emoji}</span>
                <span className={`text-xs font-bold px-3 py-1 rounded-full ${getTagClasses(article.tag)}`}>{article.tag}</span>
                <span className="flex items-center gap-1 text-xs text-muted-foreground"><Calendar className="h-3.5 w-3.5" />{formatDate(article.date)}</span>
                <span className="flex items-center gap-1 text-xs text-muted-foreground"><Clock className="h-3.5 w-3.5" />{article.tempsLecture} min de lecture</span>
              </div>
            </FadeInView>

            <FadeInView delay={150}>
              <h1 className="text-2xl md:text-3xl font-extrabold text-foreground leading-tight mb-8">{article.titre}</h1>
            </FadeInView>

            {/* Content */}
            <div className="prose-custom" dangerouslySetInnerHTML={{ __html: contenuHtml }} />

            {/* Share — colorful */}
            <FadeInView delay={200}>
              <div className="border-t border-border mt-12 pt-8">
                <p className="text-sm font-semibold text-foreground mb-4">Partager cet article 🩷</p>
                <div className="flex gap-3">
                  <BoutonY2K variant="secondary" size="sm" onClick={copierLien} className="rounded-xl" iconeGauche={<Link2 className="h-4 w-4" />}>
                    Copier le lien
                  </BoutonY2K>
                  <Button variant="outline" size="sm" asChild className="gap-2 rounded-xl hover:bg-blue-50 dark:hover:bg-blue-900/20">
                    <a href={`https://www.linkedin.com/sharing/share-offsite/?url=${encodeURIComponent(url)}`} target="_blank" rel="noopener noreferrer">
                      <Linkedin className="h-4 w-4 text-blue-600" /> LinkedIn
                    </a>
                  </Button>
                  <Button variant="outline" size="sm" asChild className="gap-2 rounded-xl hover:bg-green-50 dark:hover:bg-green-900/20">
                    <a href={`https://wa.me/?text=${encodeURIComponent(article.titre + ' — ' + url)}`} target="_blank" rel="noopener noreferrer">
                      <MessageCircle className="h-4 w-4 text-green-600" /> WhatsApp
                    </a>
                  </Button>
                </div>
              </div>
            </FadeInView>

            {/* CTA — gradient border */}
            <FadeInView delay={300}>
              <div className="mt-12 rounded-2xl bg-gradient-to-r from-primary via-rose-500 to-amber-400 p-[2px]">
                <div className="bg-card rounded-2xl p-6 md:p-8 text-center">
                  <p className="text-3xl mb-2">🩷</p>
                  <p className="font-bold text-foreground text-lg mb-2">Vous êtes soignant ?</p>
                  <p className="text-sm text-muted-foreground mb-5">Rejoignez Jolene et accédez à des missions de remplacement en toute conformité.</p>
                  <button
                    onClick={() => navigate('/inscription/soignant')}
                    className="inline-flex items-center gap-2 bg-gradient-to-r from-primary to-rose-500 text-white font-semibold px-6 py-3 rounded-xl hover:shadow-lg hover:scale-105 transition-all"
                  >
                    <Sparkles className="h-4 w-4" /> Rejoindre Jolene <ArrowRight className="h-4 w-4" />
                  </button>
                </div>
              </div>
            </FadeInView>
          </article>

          {/* Sidebar */}
          <aside className="hidden lg:block w-72 shrink-0 mt-16">
            <div className="sticky top-24">
              <h3 className="text-sm font-semibold text-foreground mb-4">Articles similaires ✨</h3>
              <div className="space-y-4">
                {similaires.map((a) => (
                  <a
                    key={a.slug}
                    href={`/blog/${a.slug}`}
                    className="block group"
                  >
                    <div className={`h-24 rounded-xl bg-gradient-to-br ${getArticleGradient(articlesBlog.indexOf(a), a.slug)} mb-2 relative overflow-hidden`}>
                      <span className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 text-3xl opacity-40">
                        {articleEmojis[a.slug] || '📖'}
                      </span>
                    </div>
                    <p className="text-sm font-medium text-foreground group-hover:text-primary transition-colors line-clamp-2">{a.titre}</p>
                    <p className="text-xs text-muted-foreground mt-1">{a.tempsLecture} min</p>
                  </a>
                ))}
              </div>
            </div>
          </aside>
        </div>
      </div>
    </>
  );
}
