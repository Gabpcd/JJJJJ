import React from 'react';
import { useNavigate } from 'react-router-dom';
import { SEOHead } from '@/components/SEOHead';
import { Clock, Calendar, Stethoscope, Scale, Pill, FileText, Rocket, ArrowRight, Sparkles } from 'lucide-react';
import { articlesBlog, getTagClasses, getArticleGradient, getArticleIconName } from '@/lib/blog-data';
import { SEOPageLayout } from '@/components/SEOPageLayout';
import { FadeInView } from '@/components/FadeInView';

const iconMap: Record<string, React.ElementType> = {
  Stethoscope, Scale, Pill, FileText, Rocket,
};

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

export default function BlogListe() {
  const navigate = useNavigate();
  const featured = articlesBlog[0];
  const rest = articlesBlog.slice(1);

  return (
    <>
      <SEOHead
        title="Blog Jolene | Actualités santé et staffing"
        description="Retrouvez nos articles sur le passage en libéral, la réglementation du staffing médical, le remplacement en pharmacie et les actualités Jolene."
        url="https://app.jolene.app/blog"
      />
      <SEOPageLayout
        heroTitle="Le blog Jolene ✨"
        heroSubtitle="Guides pratiques, décryptages réglementaires et conseils pour les soignants et les établissements de santé."
        ctaText="Créer mon compte gratuitement"
        ctaHref="/inscription/soignant"
      >
        <section className="py-12 md:py-20">
          <div className="max-w-6xl mx-auto px-4">
            {/* Featured article — big hero card */}
            <FadeInView>
              <article
                className="group cursor-pointer relative overflow-hidden rounded-2xl mb-12 shadow-lg hover:shadow-2xl transition-all duration-500"
                onClick={() => navigate(`/blog/${featured.slug}`)}
              >
                <div className={`h-64 md:h-80 bg-gradient-to-br ${getArticleGradient(0, featured.slug)} relative`}>
                  {/* Decorative circles */}
                  <div className="absolute top-6 right-6 w-32 h-32 rounded-full bg-white/10 blur-xl" />
                  <div className="absolute bottom-10 left-10 w-20 h-20 rounded-full bg-white/10 blur-lg" />

                  {/* Icon */}
                  {(() => {
                    const iconName = getArticleIconName(featured.slug);
                    const IconComp = iconName ? iconMap[iconName] : null;
                    return IconComp ? <IconComp className="absolute top-8 right-8 h-20 w-20 text-white/20" strokeWidth={1} /> : null;
                  })()}

                  {/* Content overlay */}
                  <div className="absolute inset-0 bg-gradient-to-t from-black/60 via-black/20 to-transparent" />
                  <div className="absolute bottom-0 left-0 right-0 p-6 md:p-10">
                    <div className="flex items-center gap-3 mb-3">
                      <span className="text-2xl">{articleEmojis[featured.slug] || '📖'}</span>
                      <span className={`text-xs font-bold px-3 py-1 rounded-full bg-white/20 text-white backdrop-blur-sm`}>
                        {featured.tag}
                      </span>
                      <span className="flex items-center gap-1 text-xs text-white/80"><Clock className="h-3 w-3" />{featured.tempsLecture} min</span>
                    </div>
                    <h2 className="text-xl md:text-3xl font-extrabold text-white leading-tight mb-2 group-hover:translate-x-1 transition-transform">
                      {featured.titre}
                    </h2>
                    <p className="text-sm md:text-base text-white/80 line-clamp-2 max-w-2xl">{featured.extrait}</p>
                    <div className="mt-4 inline-flex items-center gap-2 text-sm font-semibold text-white group-hover:gap-3 transition-all">
                      Lire l'article <ArrowRight className="h-4 w-4" />
                    </div>
                  </div>
                </div>
              </article>
            </FadeInView>

            {/* Grid of remaining articles */}
            <div className="grid md:grid-cols-2 gap-6">
              {rest.map((article, i) => {
                const iconName = getArticleIconName(article.slug);
                const IconComp = iconName ? iconMap[iconName] : null;
                const emoji = articleEmojis[article.slug] || '📖';
                return (
                  <FadeInView key={article.slug} delay={i * 100}>
                    <article
                      className="group cursor-pointer bg-card border border-border rounded-2xl overflow-hidden hover:shadow-xl hover:-translate-y-1 transition-all duration-300"
                      onClick={() => navigate(`/blog/${article.slug}`)}
                    >
                      <div className={`h-40 bg-gradient-to-br ${getArticleGradient(i + 1, article.slug)} flex items-center justify-center relative overflow-hidden`}>
                        {/* Decorative blob */}
                        <div className="absolute -top-4 -right-4 w-24 h-24 rounded-full bg-white/10 blur-lg" />
                        <span className="text-5xl opacity-80 group-hover:scale-110 transition-transform duration-500">{emoji}</span>
                        {IconComp && <IconComp className="absolute bottom-3 right-3 h-10 w-10 text-white/15" strokeWidth={1} />}
                        <span className={`absolute top-3 left-3 text-xs font-bold px-3 py-1 rounded-full ${getTagClasses(article.tag)}`}>
                          {article.tag}
                        </span>
                      </div>
                      <div className="p-5">
                        <h2 className="text-lg font-bold text-foreground group-hover:text-primary transition-colors line-clamp-2 mb-2">
                          {article.titre}
                        </h2>
                        <p className="text-sm text-muted-foreground line-clamp-2 mb-4">{article.extrait}</p>
                        <div className="flex items-center justify-between">
                          <div className="flex items-center gap-3 text-xs text-muted-foreground">
                            <span className="flex items-center gap-1"><Calendar className="h-3.5 w-3.5" />{formatDate(article.date)}</span>
                            <span className="flex items-center gap-1"><Clock className="h-3.5 w-3.5" />{article.tempsLecture} min</span>
                          </div>
                          <ArrowRight className="h-4 w-4 text-primary opacity-0 group-hover:opacity-100 transition-opacity" />
                        </div>
                      </div>
                    </article>
                  </FadeInView>
                );
              })}
            </div>

            {/* Fun CTA banner */}
            <FadeInView delay={400}>
              <div className="mt-16 rounded-2xl bg-gradient-to-r from-primary via-rose-500 to-amber-400 p-[2px]">
                <div className="rounded-2xl bg-card p-8 md:p-10 text-center">
                  <p className="text-3xl mb-2">🩷</p>
                  <h3 className="text-xl font-bold text-foreground mb-2">Vous avez une idée d'article ?</h3>
                  <p className="text-sm text-muted-foreground mb-5">On adore écrire sur les sujets qui vous intéressent. Dites-nous ce que vous aimeriez lire !</p>
                  <a
                    href="mailto:contact@jolene.app?subject=Idée d'article pour le blog Jolene"
                    className="inline-flex items-center gap-2 bg-gradient-to-r from-primary to-rose-500 text-white font-semibold px-6 py-3 rounded-xl hover:shadow-lg hover:scale-105 transition-all"
                  >
                    ✉️ Nous écrire
                  </a>
                </div>
              </div>
            </FadeInView>
          </div>
        </section>
      </SEOPageLayout>
    </>
  );
}
