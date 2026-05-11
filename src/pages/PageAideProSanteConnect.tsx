import { Link } from 'react-router-dom';
import {
  ArrowLeft,
  Smartphone,
  CreditCard,
  ExternalLink,
  HelpCircle,
  Mail,
  Apple,
  PlayCircle,
} from 'lucide-react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { FooterLegal } from '@/components/FooterLegal';

const LIEN_OFFICIEL_PSC = 'https://esante.gouv.fr/produits-services/pro-sante-connect';
const LIEN_OFFICIEL_ECPS = 'https://esante.gouv.fr/produits-services/e-cps';
const LIEN_CONTACT_ANS = 'https://esante.gouv.fr/contact';
const APP_STORE_ECPS = 'https://apps.apple.com/fr/app/e-cps/id1469033607';
const PLAY_STORE_ECPS = 'https://play.google.com/store/apps/details?id=fr.asipsante.esante.wallet.prod';

function LogoPSC({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      viewBox="0 0 32 32"
      aria-hidden="true"
      focusable="false"
    >
      <rect width="32" height="32" rx="6" fill="#0078D7" />
      <path d="M13.5 7h5v6h6v5h-6v6h-5v-6h-6v-5h6V7z" fill="#FFFFFF" />
    </svg>
  );
}

export default function PageAideProSanteConnect() {
  usePageTitle('Aide Pro Santé Connect');

  return (
    <div className="min-h-screen flex flex-col bg-background">
      <main id="main-content" tabIndex={-1} className="flex-1 max-w-3xl w-full mx-auto px-4 py-8">
        <Link to="/aide" className="inline-flex items-center gap-1.5 text-sm text-primary hover:underline mb-6">
          <ArrowLeft className="h-4 w-4" aria-hidden="true" /> Retour au centre d'aide
        </Link>

        <header className="mb-8">
          <div className="flex items-center gap-3 mb-3">
            <LogoPSC className="h-9 w-9 shrink-0" />
            <h1 className="text-2xl font-bold text-foreground">Aide Pro Santé Connect</h1>
          </div>
          <p className="text-sm text-muted-foreground">
            Tout ce qu'il faut savoir pour vous connecter à Jolene avec Pro Santé Connect, le
            système d'authentification officiel des professionnels de santé en France.
          </p>
        </header>

        {/* Section 1 — Qu'est-ce que Pro Santé Connect ? */}
        <section className="card-base mb-6 space-y-3">
          <h2 className="text-lg font-bold text-foreground">Qu'est-ce que Pro Santé Connect ?</h2>
          <p className="text-sm text-foreground leading-relaxed">
            Pro Santé Connect (PSC) est le service public d'authentification des professionnels
            de santé en France. Il permet de vous identifier de manière sécurisée auprès des
            services numériques de santé sans avoir à créer un mot de passe spécifique pour
            chaque plateforme.
          </p>
          <p className="text-sm text-foreground leading-relaxed">
            Il est géré par l'<strong>Agence du Numérique en Santé (ANS)</strong>, l'agence
            publique qui pilote la transformation numérique du système de santé. Pro Santé
            Connect est aujourd'hui le moyen d'identification recommandé pour accéder à des
            services comme Mon Espace Santé, Doctolib Pro ou la téléconsultation.
          </p>
          <p className="text-sm text-foreground leading-relaxed">
            Sur Jolene, Pro Santé Connect est <strong>optionnel</strong>. Vous pouvez aussi vous
            inscrire et vous connecter avec votre adresse email — c'est même la voie principale.
            PSC apporte un confort supplémentaire (vérification automatique du RPPS, inscription
            en 1 clic), mais n'est jamais obligatoire pour utiliser Jolene.
          </p>
          <a
            href={LIEN_OFFICIEL_PSC}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-1 text-sm text-primary hover:underline"
          >
            Site officiel Pro Santé Connect
            <ExternalLink className="h-3 w-3" aria-hidden="true" />
          </a>
        </section>

        {/* Section 2 — Comment obtenir mon e-CPS ? */}
        <section className="card-base mb-6 space-y-4">
          <h2 className="text-lg font-bold text-foreground">Comment obtenir mon e-CPS ?</h2>
          <p className="text-sm text-foreground leading-relaxed">
            L'e-CPS est la version dématérialisée de la carte CPS, installée comme une
            application sur votre smartphone. C'est le moyen le plus simple d'utiliser Pro
            Santé Connect au quotidien.
          </p>

          <ol className="space-y-3 text-sm text-foreground">
            <li className="flex gap-3">
              <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-primary text-primary-foreground text-xs font-bold">1</span>
              <span>
                <strong>Vérifiez que vous êtes inscrit au RPPS.</strong> L'e-CPS est réservée
                aux professionnels enregistrés au répertoire RPPS ou ADELI.
              </span>
            </li>
            <li className="flex gap-3">
              <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-primary text-primary-foreground text-xs font-bold">2</span>
              <span>
                <strong>Téléchargez l'app e-CPS</strong> sur votre smartphone (App Store ou
                Google Play, liens plus bas).
              </span>
            </li>
            <li className="flex gap-3">
              <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-primary text-primary-foreground text-xs font-bold">3</span>
              <span>
                <strong>Lancez l'activation depuis l'app</strong> avec votre numéro RPPS/ADELI
                et votre date de naissance.
              </span>
            </li>
            <li className="flex gap-3">
              <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-primary text-primary-foreground text-xs font-bold">4</span>
              <span>
                <strong>Recevez votre code d'activation</strong> par courrier postal (compter
                quelques jours).
              </span>
            </li>
            <li className="flex gap-3">
              <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-primary text-primary-foreground text-xs font-bold">5</span>
              <span>
                <strong>Saisissez votre code et créez votre code PIN</strong> dans l'app. Votre
                e-CPS est prête, l'activation effective prend 5 minutes une fois le code reçu.
              </span>
            </li>
          </ol>

          <a
            href={LIEN_OFFICIEL_ECPS}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-1 text-sm text-primary hover:underline"
          >
            Page officielle ANS : activer votre e-CPS
            <ExternalLink className="h-3 w-3" aria-hidden="true" />
          </a>
        </section>

        {/* Section 3 — Télécharger l'app */}
        <section className="card-base mb-6 space-y-4">
          <h2 className="text-lg font-bold text-foreground">Télécharger l'app e-CPS</h2>
          <p className="text-sm text-foreground">
            L'application est gratuite et publiée par l'ASIP Santé (ANS).
          </p>
          <div className="flex flex-col sm:flex-row gap-3">
            <a
              href={APP_STORE_ECPS}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center justify-center gap-2 px-4 py-3 rounded-xl bg-foreground text-background hover:opacity-90 transition flex-1"
            >
              <Apple className="h-5 w-5" aria-hidden="true" />
              <div className="text-left">
                <div className="text-[10px] leading-tight">Télécharger sur l'</div>
                <div className="text-sm font-semibold leading-tight">App Store</div>
              </div>
            </a>
            <a
              href={PLAY_STORE_ECPS}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center justify-center gap-2 px-4 py-3 rounded-xl bg-foreground text-background hover:opacity-90 transition flex-1"
            >
              <PlayCircle className="h-5 w-5" aria-hidden="true" />
              <div className="text-left">
                <div className="text-[10px] leading-tight">Disponible sur</div>
                <div className="text-sm font-semibold leading-tight">Google Play</div>
              </div>
            </a>
          </div>
        </section>

        {/* Section 4 — FAQ */}
        <section className="card-base mb-6 space-y-4">
          <div className="flex items-center gap-2">
            <HelpCircle className="h-5 w-5 text-primary" aria-hidden="true" />
            <h2 className="text-lg font-bold text-foreground">Questions fréquentes</h2>
          </div>

          <div className="space-y-4">
            <div>
              <h3 className="text-sm font-semibold text-foreground mb-1">
                Suis-je obligé d'utiliser Pro Santé Connect pour Jolene ?
              </h3>
              <p className="text-sm text-muted-foreground leading-relaxed">
                Non. L'inscription par email est la voie principale et suffit pour utiliser
                toutes les fonctionnalités de Jolene. Pro Santé Connect est proposé en
                complément, pour les professionnels qui ont déjà leur e-CPS activée.
              </p>
            </div>

            <div>
              <h3 className="text-sm font-semibold text-foreground mb-1">
                Mon e-CPS ne fonctionne pas, qui contacter ?
              </h3>
              <p className="text-sm text-muted-foreground leading-relaxed">
                Le support officiel est assuré par l'ANS. Vous pouvez les joindre par email à{' '}
                <a
                  href="mailto:monservicepublic@asipsante.fr"
                  className="text-primary hover:underline"
                >
                  monservicepublic@asipsante.fr
                </a>{' '}
                ou via{' '}
                <a
                  href={LIEN_CONTACT_ANS}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-primary hover:underline inline-flex items-center gap-1"
                >
                  le formulaire de contact ANS
                  <ExternalLink className="h-3 w-3" aria-hidden="true" />
                </a>
                . Jolene ne peut pas dépanner directement l'e-CPS car c'est un service public.
              </p>
            </div>

            <div>
              <h3 className="text-sm font-semibold text-foreground mb-1">
                Quelle est la différence entre carte CPS et e-CPS ?
              </h3>
              <p className="text-sm text-muted-foreground leading-relaxed">
                La <strong>carte CPS</strong> est une carte physique avec puce, à insérer dans
                un lecteur connecté à votre ordinateur (logiciel CryptoLib nécessaire).
                L'<strong>e-CPS</strong> est l'équivalent numérique installé sur votre
                smartphone : pas de lecteur, validation par code PIN ou empreinte. Les deux
                donnent les mêmes droits d'accès, l'e-CPS étant plus pratique au quotidien.
              </p>
            </div>

            <div>
              <h3 className="text-sm font-semibold text-foreground mb-1">
                Combien de temps prend l'activation de la e-CPS ?
              </h3>
              <p className="text-sm text-muted-foreground leading-relaxed">
                L'activation prend 5 minutes une fois que vous avez reçu votre code par
                courrier. Le délai de réception du courrier est de quelques jours en moyenne.
                Anticipez si vous avez besoin de PSC pour une date précise.
              </p>
            </div>

            <div>
              <h3 className="text-sm font-semibold text-foreground mb-1">
                Que faire si j'ai changé de téléphone ?
              </h3>
              <p className="text-sm text-muted-foreground leading-relaxed">
                Vous devez réactiver votre e-CPS sur le nouvel appareil. La procédure est plus
                rapide qu'une activation initiale (pas de courrier postal nécessaire si
                l'ancienne e-CPS est toujours opérationnelle). Voir l'aide ANS pour la
                procédure exacte.
              </p>
            </div>
          </div>
        </section>

        {/* Section 5 — Contact Jolene */}
        <section className="card-base mb-6 space-y-3">
          <div className="flex items-center gap-2">
            <Mail className="h-5 w-5 text-primary" aria-hidden="true" />
            <h2 className="text-lg font-bold text-foreground">Une question sur Jolene et PSC ?</h2>
          </div>
          <p className="text-sm text-foreground leading-relaxed">
            Pour toute question spécifique au fonctionnement de Pro Santé Connect{' '}
            <strong>sur la plateforme Jolene</strong> (et non sur l'e-CPS elle-même, qui
            relève de l'ANS), écrivez-nous à{' '}
            <a href="mailto:support@jolene.app" className="text-primary hover:underline">
              support@jolene.app
            </a>
            .
          </p>
          <div className="flex flex-wrap gap-2 pt-1">
            <Link
              to="/connexion"
              className="inline-flex items-center gap-1.5 text-sm font-medium text-primary hover:underline"
            >
              <CreditCard className="h-4 w-4" aria-hidden="true" />
              Se connecter avec PSC
            </Link>
            <span className="text-muted-foreground/40">•</span>
            <Link
              to="/inscription/soignant"
              className="inline-flex items-center gap-1.5 text-sm font-medium text-primary hover:underline"
            >
              <Smartphone className="h-4 w-4" aria-hidden="true" />
              S'inscrire par email
            </Link>
          </div>
        </section>
      </main>

      <FooterLegal />
    </div>
  );
}
