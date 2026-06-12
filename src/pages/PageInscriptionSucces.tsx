/**
 * PageInscriptionSucces — page intermédiaire post-inscription.
 *
 * Session E-2 (« la valeur avant l'effort ») : le moment de célébration n'est
 * plus consommé par l'avertissement délivrabilité — celui-ci n'apparaît que
 * pour les domaines Microsoft (Outlook/Hotmail/Live/MSN), seuls réellement
 * concernés. À la place : l'aperçu du marché (missions / établissements de la
 * zone) et un CTA qui nomme la prochaine étape de valeur.
 *
 * Affichée après inscription soignant ET établissement
 * (/inscription/succes?role=soignant|etab, email en sessionStorage).
 */

import React from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { CheckCircle2, AlertTriangle, Mail, ArrowRight } from 'lucide-react';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { usePageTitle } from '@/hooks/usePageTitle';
import { ApercuMarche } from '@/components/inscription/ApercuMarche';

export default function PageInscriptionSucces() {
  usePageTitle('Inscription réussie');
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const role = params.get('role') === 'etab' ? 'etab' : 'soignant';
  // PII hors URL : email + profession récupérés depuis sessionStorage
  let email = '';
  let profession = '';
  try {
    email = sessionStorage.getItem('inscription_email') || '';
    profession = sessionStorage.getItem('inscription_profession') || '';
  } catch { /* sessionStorage indisponible */ }
  const isOutlook = /outlook\.com$|hotmail\.com$|live\.[a-z]{2,3}$|msn\.com$/i.test(email);

  // Cleanup au démontage : ne garder ces infos que pour cette navigation
  React.useEffect(() => {
    return () => {
      try {
        sessionStorage.removeItem('inscription_email');
        sessionStorage.removeItem('inscription_profession');
      } catch { /* noop */ }
    };
  }, []);

  const target = role === 'etab' ? '/etablissement/tableau-de-bord' : '/soignant/tableau-de-bord';

  return (
    <div className="min-h-[100dvh] gradient-hero flex flex-col">
      <div className="flex-1 flex items-center justify-center px-4 py-8">
        <div className="card-base max-w-lg w-full space-y-6">
          {/* Header */}
          <div className="text-center space-y-2">
            <div className="inline-flex h-16 w-16 items-center justify-center rounded-full bg-emerald-100">
              <CheckCircle2 className="h-9 w-9 text-emerald-600" />
            </div>
            <h1 className="text-2xl font-bold text-foreground">Bienvenue sur Jolene !</h1>
            <p className="text-gray-600">
              Votre compte {role === 'etab' ? 'établissement' : 'soignant'} est créé.
            </p>
          </div>

          {/* La valeur d'abord : ce qui attend l'utilisateur de l'autre côté */}
          {role === 'soignant' && <ApercuMarche profession={profession || null} />}

          {/* Email confirmation */}
          {email && (
            <div className="border rounded-lg p-4 bg-blue-50 flex items-start gap-3">
              <Mail className="h-5 w-5 text-blue-600 shrink-0 mt-0.5" />
              <div className="text-sm">
                <p className="font-medium text-blue-900">Email de bienvenue envoyé</p>
                <p className="text-blue-800 mt-1">
                  Vous allez recevoir un email à <strong>{email}</strong> dans quelques instants.
                  {!isOutlook && <span className="text-blue-700"> S'il n'arrive pas, pensez à vérifier vos courriers indésirables.</span>}
                </p>
              </div>
            </div>
          )}

          {/* Avertissement délivrabilité — uniquement pour les domaines Microsoft,
              seuls réellement concernés par la mise en spam des domaines récents */}
          {isOutlook && (
            <div className="border rounded-lg p-4 bg-amber-50 border-amber-200">
              <div className="flex items-start gap-3">
                <AlertTriangle className="h-5 w-5 shrink-0 mt-0.5 text-amber-600" />
                <div className="text-sm space-y-2">
                  <p className="font-medium text-amber-900">Vérifiez votre dossier « Courrier indésirable »</p>
                  <p className="text-amber-800">
                    Outlook met souvent les nouveaux expéditeurs en spam. Si notre email s'y trouve,
                    marquez-le <strong>Pas un courrier indésirable</strong> et ajoutez{' '}
                    <code className="px-1 bg-white/50 rounded">bonjour@jolene.app</code> à vos contacts.
                  </p>
                  <p className="text-xs italic">
                    Plus de détails dans notre{' '}
                    <a href="/aide/je-n-ai-pas-recu-d-email" className="underline">centre d'aide</a>.
                  </p>
                </div>
              </div>
            </div>
          )}

          <BoutonY2K onClick={() => navigate(target)} className="w-full" iconeDroite={<ArrowRight className="h-4 w-4" />}>
            {role === 'etab' ? 'Publier ma première mission' : 'Compléter mon profil — 2 minutes'}
          </BoutonY2K>
        </div>
      </div>
    </div>
  );
}
