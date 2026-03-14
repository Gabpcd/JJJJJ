import React, { useMemo } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { SEOHead } from '@/components/SEOHead';
import { articlesBlog, getTagClasses, getArticleGradient } from '@/lib/blog-data';
import { ArrowLeft, ArrowRight, Clock, Calendar, Link2, Linkedin, MessageCircle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { toast } from 'sonner';

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' });
}

function markdownToHtml(md: string): string {
  let html = md
    // h3
    .replace(/^### (.+)$/gm, '<h3 class="text-lg font-bold text-foreground mt-8 mb-3">$1</h3>')
    // h2
    .replace(/^## (.+)$/gm, '<h2 class="text-xl font-bold text-foreground mt-10 mb-4">$1</h2>')
    // bold
    .replace(/\*\*(.+?)\*\*/g, '<strong class="font-semibold text-foreground">$1</strong>')
    // italic
    .replace(/\*(.+?)\*/g, '<em>$1</em>')
    // unordered lists
    .replace(/^- (.+)$/gm, '<li class="ml-4 list-disc text-muted-foreground">$1</li>')
    // table rows (basic)
    .replace(/^\|(.+)\|$/gm, (_, content) => {
      const cells = content.split('|').map((c: string) => c.trim());
      if (cells.every((c: string) => /^-+$/.test(c))) return '';
      const tag = cells[0] === '' ? 'th' : 'td';
      return `<tr>${cells.map((c: string) => `<${tag} class="border border-border px-3 py-2 text-sm">${c}</${tag}>`).join('')}</tr>`;
    })
    // paragraphs
    .replace(/\n\n/g, '</p><p class="text-muted-foreground leading-relaxed mb-4">')
  ;

  // wrap in paragraphs
  html = `<p class="text-muted-foreground leading-relaxed mb-4">${html}</p>`;
  // wrap table rows
  html = html.replace(/(<tr>.*?<\/tr>)+/gs, (match) => `<table class="w-full border-collapse border border-border my-6">${match}</table>`);
  // wrap list items
  html = html.replace(/(<li.*?<\/li>)+/gs, (match) => `<ul class="space-y-1 my-4">${match}</ul>`);
  // clean empty paragraphs
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
          <h1 className="text-2xl font-bold text-foreground mb-2">Article introuvable</h1>
          <Button variant="outline" onClick={() => navigate('/blog')}>Retour au blog</Button>
        </div>
      </div>
    );
  }

  const url = `https://app.soindirect.com/blog/${article.slug}`;
  const contenuHtml = markdownToHtml(article.contenu);

  const copierLien = () => {
    navigator.clipboard.writeText(url);
    toast({ title: 'Lien copié !', description: 'Le lien de l\'article a été copié dans le presse-papiers.' });
  };

  return (
    <>
      <SEOHead
        title={`${article.titre} | Blog Soin Direct`}
        description={article.extrait}
        url={url}
      />
      <div className="min-h-screen bg-background text-foreground">
        {/* Header */}
        <header className="sticky top-0 z-50 bg-card/80 backdrop-blur-lg border-b border-border">
          <div className="max-w-6xl mx-auto px-4 h-14 flex items-center">
            <button onClick={() => navigate('/blog')} className="flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground transition-colors">
              <ArrowLeft className="h-4 w-4" /> Blog
            </button>
          </div>
        </header>

        <div className="max-w-6xl mx-auto px-4 py-10 md:py-16 lg:flex lg:gap-12">
          {/* Main content */}
          <article className="lg:flex-1 max-w-[720px] mx-auto lg:mx-0">
            {/* Hero gradient */}
            <div className={`h-48 md:h-56 rounded-xl bg-gradient-to-br ${getArticleGradient(idx)} mb-8`} />

            {/* Meta */}
            <div className="flex flex-wrap items-center gap-3 mb-6">
              <span className={`text-xs font-semibold px-2.5 py-1 rounded-full ${getTagClasses(article.tag)}`}>{article.tag}</span>
              <span className="flex items-center gap-1 text-xs text-muted-foreground"><Calendar className="h-3.5 w-3.5" />{formatDate(article.date)}</span>
              <span className="flex items-center gap-1 text-xs text-muted-foreground"><Clock className="h-3.5 w-3.5" />{article.tempsLecture} min de lecture</span>
            </div>

            <h1 className="text-2xl md:text-3xl font-extrabold text-foreground leading-tight mb-8">{article.titre}</h1>

            {/* Content */}
            <div className="prose-custom" dangerouslySetInnerHTML={{ __html: contenuHtml }} />

            {/* Share */}
            <div className="border-t border-border mt-12 pt-8">
              <p className="text-sm font-semibold text-foreground mb-4">Partager cet article</p>
              <div className="flex gap-3">
                <Button variant="outline" size="sm" onClick={copierLien} className="gap-2">
                  <Link2 className="h-4 w-4" /> Copier le lien
                </Button>
                <Button variant="outline" size="sm" asChild className="gap-2">
                  <a href={`https://www.linkedin.com/sharing/share-offsite/?url=${encodeURIComponent(url)}`} target="_blank" rel="noopener noreferrer">
                    <Linkedin className="h-4 w-4" /> LinkedIn
                  </a>
                </Button>
                <Button variant="outline" size="sm" asChild className="gap-2">
                  <a href={`https://wa.me/?text=${encodeURIComponent(article.titre + ' — ' + url)}`} target="_blank" rel="noopener noreferrer">
                    <MessageCircle className="h-4 w-4" /> WhatsApp
                  </a>
                </Button>
              </div>
            </div>

            {/* CTA */}
            <div className="mt-12 bg-primary/5 border border-primary/20 rounded-xl p-6 md:p-8 text-center">
              <p className="font-bold text-foreground text-lg mb-2">Vous êtes soignant ?</p>
              <p className="text-sm text-muted-foreground mb-5">Rejoignez Soin Direct et accédez à des missions de remplacement en toute conformité.</p>
              <Button onClick={() => navigate('/inscription/soignant')} className="gap-2">
                Rejoignez Soin Direct <ArrowRight className="h-4 w-4" />
              </Button>
            </div>
          </article>

          {/* Sidebar */}
          <aside className="hidden lg:block w-72 shrink-0 mt-16">
            <div className="sticky top-24">
              <h3 className="text-sm font-semibold text-foreground mb-4">Articles similaires</h3>
              <div className="space-y-4">
                {similaires.map((a, i) => (
                  <a
                    key={a.slug}
                    href={`/blog/${a.slug}`}
                    className="block group"
                  >
                    <div className={`h-24 rounded-lg bg-gradient-to-br ${getArticleGradient(articlesBlog.indexOf(a))} mb-2`} />
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
