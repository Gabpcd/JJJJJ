/**
 * PageInscriptionSucces — page intermédiaire post-inscription qui :
 *   - confirme la création du compte
 *   - prévient les utilisateurs Outlook/Hotmail/Live que les emails
 *     peuvent atterrir en spam (réputation domaine récente)
 *   - donne les actions concrètes pour ne pas rater nos emails
 *   - permet de continuer vers le dashboard
 *
 * Affichée après inscription soignant ET établissement. Le redirect se fait
 * vers /inscription/succes?role=soignant|etab&email=…
 *
 * J2.3.C — UX warmup délivrabilité Outlook.
 */

import React from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { CheckCircle2, AlertTriangle, Mail, ArrowRight } from 'lucide-react';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { usePageTitle } from '@/hooks/usePageTitle';

export default function PageInscriptionSucces() {
  usePageTitle('Inscription réussie');
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const role = params.get('role') === 'etab' ? 'etab' : 'soignant';
  // Email récupéré depuis sessionStorage (PII hors URL pour éviter leak via historique navigateur)
  let email = '';
  try {
    email = sessionStorage.getItem('inscription_email') || '';
  } catch { /* sessionStorage indisponible */ }
  const isOutlook = /outlook\.com$|hotmail\.com$|live\.[a-z]{2,3}$|msn\.com$/i.test(email);

  // Cleanup au démontage : ne garder l'email que pour cette navigation
  React.useEffect(() => {
    return () => { try { sessionStorage.removeItem('inscription_email'); } catch { /* noop */ } };
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

          {/* Email confirmation */}
          {email && (
            <div className="border rounded-lg p-4 bg-blue-50 flex items-start gap-3">
              <Mail className="h-5 w-5 text-blue-600 shrink-0 mt-0.5" />
              <div className="text-sm">
                <p className="font-medium text-blue-900">Email de bienvenue envoyé</p>
                <p className="text-blue-800 mt-1">
                  Vous allez recevoir un email à <strong>{email}</strong> dans quelques instants.
                </p>
              </div>
            </div>
          )}

          {/* Avertissement Outlook : ciblé si email finit en .outlook/.hotmail, mais affiché à tous (peut servir pour Gmail aussi) */}
          <div className={`border rounded-lg p-4 ${isOutlook ? 'bg-amber-50 border-amber-200' : 'bg-gray-50'}`}>
            <div className="flex items-start gap-3">
              <AlertTriangle className={`h-5 w-5 shrink-0 mt-0.5 ${isOutlook ? 'text-amber-600' : 'text-gray-500'}`} />
              <div className="text-sm space-y-2">
                <p className={`font-medium ${isOutlook ? 'text-amber-900' : 'text-gray-900'}`}>
                  {isOutlook
                    ? 'Vérifiez votre dossier "Courrier indésirable"'
                    : 'Astuce : ne ratez pas nos emails'}
                </p>
                <p className={isOutlook ? 'text-amber-800' : 'text-gray-700'}>
                  Notre domaine <code className="px-1 bg-white/50 rounded">jolene.app</code> est récent (avril 2026)
                  {isOutlook
                    ? '. Outlook met souvent les nouveaux domaines en spam. C\'est temporaire — la situation s\'améliore au fur et à mesure que des destinataires interagissent avec nos emails.'
                    : ', donc certains filtres anti-spam peuvent encore le considérer comme inconnu.'}
                </p>
                <div className="space-y-1.5 mt-3">
                  <p className="font-medium">Pour ne plus rater nos emails :</p>
                  <ol className="list-decimal pl-5 space-y-1">
                    <li>Ouvrez votre dossier <strong>Courrier indésirable</strong> (ou Spam)</li>
                    <li>Si vous y trouvez notre email, marquez-le <strong>Pas un courrier indésirable</strong></li>
                    <li>Ajoutez <code className="px-1 bg-white/50 rounded">bonjour@jolene.app</code> à vos contacts</li>
                  </ol>
                </div>
                <p className="text-xs mt-2 italic">
                  Plus de détails dans notre{' '}
                  <a href="/aide/je-n-ai-pas-recu-d-email" className="underline">centre d'aide</a>.
                </p>
              </div>
            </div>
          </div>

          <BoutonY2K onClick={() => navigate(target)} className="w-full" iconeDroite={<ArrowRight className="h-4 w-4" />}>
            Continuer vers mon tableau de bord
          </BoutonY2K>
        </div>
      </div>
    </div>
  );
}
