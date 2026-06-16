/**
 * VerificationEmailEtab — page PUBLIQUE de retour après clic sur le lien de
 * confirmation de l'e-mail professionnel d'un établissement.
 *
 * L'edge function confirm-email-etab valide le token puis redirige ici avec
 * ?statut=ok|expire|invalide|erreur. La page est publique : l'utilisateur peut
 * cliquer depuis son e-mail sans être connecté.
 */

import { useNavigate, useSearchParams } from 'react-router-dom';
import { CheckCircle2, XCircle, Clock, ArrowRight } from 'lucide-react';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { usePageTitle } from '@/hooks/usePageTitle';

type Statut = 'ok' | 'expire' | 'invalide' | 'erreur';

const CONTENU: Record<Statut, { titre: string; message: string; ok: boolean }> = {
  ok: {
    titre: 'Adresse e-mail confirmée',
    message: "Votre adresse e-mail professionnelle est vérifiée. Le rattachement de votre établissement est désormais validé : vous pouvez publier des missions.",
    ok: true,
  },
  expire: {
    titre: 'Lien expiré',
    message: "Ce lien de confirmation a expiré (valable 24 heures). Reconnectez-vous à votre espace établissement pour renvoyer un nouvel e-mail de confirmation.",
    ok: false,
  },
  invalide: {
    titre: 'Lien invalide',
    message: "Ce lien de confirmation est invalide ou a déjà été utilisé. Reconnectez-vous à votre espace établissement pour en renvoyer un.",
    ok: false,
  },
  erreur: {
    titre: 'Une erreur est survenue',
    message: "Nous n'avons pas pu valider votre adresse e-mail. Veuillez réessayer ou contacter support@jolene.app.",
    ok: false,
  },
};

export default function VerificationEmailEtab() {
  usePageTitle('Vérification e-mail établissement');
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const statutParam = params.get('statut');
  const statut: Statut = (['ok', 'expire', 'invalide', 'erreur'].includes(statutParam || '')
    ? statutParam
    : 'erreur') as Statut;
  const contenu = CONTENU[statut];

  return (
    <div className="min-h-[100dvh] gradient-hero flex flex-col">
      <div className="flex-1 flex items-center justify-center px-4 py-8">
        <div className="card-base max-w-lg w-full space-y-6 text-center">
          <div className={`inline-flex h-16 w-16 items-center justify-center rounded-full ${contenu.ok ? 'bg-emerald-100' : statut === 'expire' ? 'bg-amber-100' : 'bg-red-100'}`}>
            {contenu.ok ? (
              <CheckCircle2 className="h-9 w-9 text-emerald-600" />
            ) : statut === 'expire' ? (
              <Clock className="h-9 w-9 text-amber-600" />
            ) : (
              <XCircle className="h-9 w-9 text-red-600" />
            )}
          </div>

          <div className="space-y-2">
            <h1 className="text-2xl font-bold text-foreground">{contenu.titre}</h1>
            <p className="text-gray-600">{contenu.message}</p>
          </div>

          <BoutonY2K
            onClick={() => navigate(contenu.ok ? '/etablissement/tableau-de-bord' : '/etablissement/activer')}
            className="w-full"
            iconeDroite={<ArrowRight className="h-4 w-4" />}
          >
            {contenu.ok ? 'Aller à mon tableau de bord' : 'Retour à la vérification'}
          </BoutonY2K>
        </div>
      </div>
    </div>
  );
}
