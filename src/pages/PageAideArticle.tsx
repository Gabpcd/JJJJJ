import { useEffect, useState } from 'react';
import { useParams, Link, useNavigate } from 'react-router-dom';
import { ArrowLeft, HelpCircle, Loader2, Calendar } from 'lucide-react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { supabase } from '@/integrations/supabase/client';
import { FooterLegal } from '@/components/FooterLegal';
import DOMPurify from 'dompurify';

interface Article {
  id: string;
  slug: string;
  titre: string;
  contenu: string;
  audience: string;
  categorie: string;
  mis_a_jour_le: string;
}

// Validation URL : refuse javascript:/data:/vbscript: (XSS), accepte http(s)/, mailto:, /relatif.
// Ajoute target="_blank" + rel="noopener noreferrer" pour les liens externes (sécurité tabnabbing).
function safeLink(rawUrl: string, text: string): string {
  const url = rawUrl.trim();
  // Whitelist explicite pour éviter javascript:/data:/vbscript: et autres schemes dangereux
  const isHttps = /^https?:\/\//i.test(url);
  const isMailto = /^mailto:/i.test(url);
  const isRelative = url.startsWith('/') || url.startsWith('#');
  if (!isHttps && !isMailto && !isRelative) {
    // URL non whitelistée → retourner le texte brut sans lien
    return text;
  }
  const href = url.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  const isExternal = isHttps && !url.startsWith('https://jolene.app') && !url.startsWith('https://www.jolene.app');
  const externalAttrs = isExternal ? ' target="_blank" rel="noopener noreferrer"' : '';
  return `<a href="${href}" class="text-primary hover:underline"${externalAttrs}>${text}</a>`;
}

const sanitizeMarkdownHtml = (html: string) => DOMPurify.sanitize(html, {
  ALLOWED_TAGS: ['a', 'strong', 'code'],
  ALLOWED_ATTR: ['href', 'class', 'target', 'rel'],
});

function renderMarkdown(texte: string) {
  const lines = texte.split('\n');
  const elements: JSX.Element[] = [];
  let listBuffer: string[] = [];
  let key = 0;
  const flushList = () => {
    if (listBuffer.length > 0) {
      elements.push(
        <ul key={key++} className="list-disc list-inside space-y-1.5 text-base text-foreground ml-2 mb-3">
          {listBuffer.map((item, i) => (
            <li key={i} dangerouslySetInnerHTML={{ __html: sanitizeMarkdownHtml(item
              .replace(/[<>]/g, m => m === '<' ? '&lt;' : '&gt;')
              .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
              .replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_, txt, url) => safeLink(url, txt))
              .replace(/`([^`]+)`/g, '<code class="bg-muted px-1.5 py-0.5 rounded text-sm">$1</code>')
            ) }} />
          ))}
        </ul>,
      );
      listBuffer = [];
    }
  };
  const renderInline = (s: string) => s
    // Échapper d'abord le HTML brut (contenu issu de la DB articles_aide) pour éviter
    // l'injection (stored XSS). Les balises sûres sont insérées APRÈS par le markdown.
    .replace(/[<>]/g, m => m === '<' ? '&lt;' : '&gt;')
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_, txt, url) => safeLink(url, txt))
    .replace(/`([^`]+)`/g, '<code class="bg-muted px-1.5 py-0.5 rounded text-sm">$1</code>');
  for (const line of lines) {
    if (line.startsWith('# ')) { flushList(); elements.push(<h1 key={key++} className="text-2xl font-bold text-foreground mb-4 mt-2">{line.substring(2)}</h1>); }
    else if (line.startsWith('## ')) { flushList(); elements.push(<h2 key={key++} className="text-lg font-bold text-foreground mt-6 mb-2">{line.substring(3)}</h2>); }
    else if (line.startsWith('### ')) { flushList(); elements.push(<h3 key={key++} className="text-base font-semibold text-foreground mt-4 mb-2">{line.substring(4)}</h3>); }
    else if (line.startsWith('- ')) { listBuffer.push(line.substring(2)); }
    else if (line.match(/^\d+\.\s/)) { listBuffer.push(line.replace(/^\d+\.\s/, '')); }
    else if (line.trim() === '---') { flushList(); elements.push(<hr key={key++} className="border-border my-6" />); }
    else if (line.trim() === '') { flushList(); }
    else { flushList(); elements.push(<p key={key++} className="text-base text-foreground mb-3 leading-relaxed" dangerouslySetInnerHTML={{ __html: sanitizeMarkdownHtml(renderInline(line)) }} />); }
  }
  flushList();
  return elements;
}

export default function PageAideArticle() {
  const { slug } = useParams<{ slug: string }>();
  const navigate = useNavigate();
  const [article, setArticle] = useState<Article | null>(null);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);

  usePageTitle(article?.titre ? `${article.titre} — Aide` : 'Aide');

  useEffect(() => {
    if (!slug) return;
    let cancelled = false;
    (async () => {
      setLoading(true);
      const { data, error } = await supabase
        .from('articles_aide' as any)
        .select('id, slug, titre, contenu, audience, categorie, mis_a_jour_le')
        .eq('slug', slug)
        .eq('publie', true)
        .maybeSingle();
      if (cancelled) return;
      if (error || !data) { setNotFound(true); }
      else { setArticle(data as any); }
      setLoading(false);
    })();
    return () => { cancelled = true; };
  }, [slug]);

  if (loading) {
    return (
      <div className="min-h-[100dvh] bg-background flex items-center justify-center">
        <Loader2 className="h-8 w-8 animate-spin text-primary" />
      </div>
    );
  }

  if (notFound || !article) {
    return (
      <div className="min-h-[100dvh] bg-background">
        <div className="max-w-3xl mx-auto px-4 py-12 text-center">
          <p className="text-lg font-semibold text-foreground">Article introuvable</p>
          <p className="text-sm text-muted-foreground mt-2">Cet article n'existe pas ou a été supprimé.</p>
          <Link to="/aide" className="inline-block mt-6 text-primary hover:underline">← Retour au centre d'aide</Link>
        </div>
      </div>
    );
  }

  const audienceLabel = (aud: string) =>
    aud === 'SOIGNANT' ? 'Soignant' : aud === 'ETABLISSEMENT' ? 'Établissement' : 'Commun';

  return (
    <div className="min-h-[100dvh] bg-background">
      <header className="border-b border-border bg-card">
        <div className="max-w-3xl mx-auto px-4 py-4 flex items-center gap-3">
          <button onClick={() => navigate('/aide')} className="text-muted-foreground hover:text-foreground" aria-label="Retour au centre d'aide">
            <ArrowLeft className="h-5 w-5" />
          </button>
          <div className="flex items-center gap-2">
            <HelpCircle className="h-5 w-5 text-primary" />
            <span className="text-sm text-muted-foreground">Centre d'aide</span>
          </div>
        </div>
      </header>

      <main className="max-w-3xl mx-auto px-4 py-6 pb-24">
        <div className="mb-6 flex flex-wrap items-center gap-2 text-xs">
          <span className={`font-bold px-2 py-0.5 rounded-full ${article.audience === 'SOIGNANT' ? 'bg-primary/10 text-primary' : article.audience === 'ETABLISSEMENT' ? 'bg-info/10 text-info' : 'bg-muted text-muted-foreground'}`}>
            {audienceLabel(article.audience)}
          </span>
          <span className="text-muted-foreground">{article.categorie}</span>
          <span className="text-muted-foreground flex items-center gap-1">
            <Calendar className="h-3 w-3" />
            Mis à jour le {new Date(article.mis_a_jour_le).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' })}
          </span>
        </div>

        <article className="prose prose-slate max-w-none">
          <h1 className="text-3xl font-bold text-foreground mb-6">{article.titre}</h1>
          {renderMarkdown(article.contenu)}
        </article>

        <div className="mt-12 pt-6 border-t border-border">
          <Link to="/aide" className="text-sm text-primary hover:underline">← Retour à toutes les FAQ</Link>
          <p className="text-xs text-muted-foreground mt-3">
            Cet article ne répond pas à votre question ? Contactez <a href="mailto:support@jolene.app" className="text-primary hover:underline">support@jolene.app</a>
          </p>
        </div>
      </main>

      <FooterLegal />
    </div>
  );
}
