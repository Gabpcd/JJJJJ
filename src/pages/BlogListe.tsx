import React from 'react';
import { useNavigate } from 'react-router-dom';
import { SEOHead } from '@/components/SEOHead';
import { Clock, Calendar } from 'lucide-react';
import { articlesBlog, getTagClasses, getArticleGradient } from '@/lib/blog-data';
import { SEOPageLayout } from '@/components/SEOPageLayout';

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' });
}

export default function BlogListe() {
  const navigate = useNavigate();

  return (
    <>
      <SEOHead
        title="Blog Jolene | Actualités santé et staffing"
        description="Retrouvez nos articles sur le passage en libéral, la réglementation du staffing médical, le remplacement en pharmacie et les actualités Jolene."
        url="https://app.joleneapp.com/blog"
      />
      <SEOPageLayout
        heroTitle="Le blog Jolene"
        heroSubtitle="Guides pratiques, décryptages réglementaires et conseils pour les soignants et les établissements de santé."
        ctaText="Créer mon compte gratuitement"
        ctaHref="/inscription/soignant"
      >
        <section className="py-16 md:py-20">
          <div className="max-w-5xl mx-auto px-4">
            <div className="grid md:grid-cols-2 gap-8">
              {articlesBlog.map((article, i) => (
                <article
                  key={article.slug}
                  className="group cursor-pointer bg-card border border-border rounded-xl overflow-hidden hover:shadow-lg transition-shadow"
                  onClick={() => navigate(`/blog/${article.slug}`)}
                >
                  {/* Gradient placeholder image */}
                  <div className={`h-44 bg-gradient-to-br ${getArticleGradient(i)} flex items-end p-5`}>
                    <span className={`text-xs font-semibold px-2.5 py-1 rounded-full ${getTagClasses(article.tag)}`}>
                      {article.tag}
                    </span>
                  </div>
                  <div className="p-5">
                    <h2 className="text-lg font-bold text-foreground group-hover:text-primary transition-colors line-clamp-2 mb-2">
                      {article.titre}
                    </h2>
                    <p className="text-sm text-muted-foreground line-clamp-2 mb-4">{article.extrait}</p>
                    <div className="flex items-center gap-4 text-xs text-muted-foreground">
                      <span className="flex items-center gap-1"><Calendar className="h-3.5 w-3.5" />{formatDate(article.date)}</span>
                      <span className="flex items-center gap-1"><Clock className="h-3.5 w-3.5" />{article.tempsLecture} min</span>
                    </div>
                  </div>
                </article>
              ))}
            </div>
          </div>
        </section>
      </SEOPageLayout>
    </>
  );
}
