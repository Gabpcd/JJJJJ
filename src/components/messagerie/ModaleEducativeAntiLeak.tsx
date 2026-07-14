/**
 * `<ModaleEducativeAntiLeak />` — Sprint 10-B PR 4
 *
 * Modale éducative s'ouvrant quand l'edge function `messagerie-validate`
 * (Sprint 10-A v3 PR 2) refuse un message contenant des coordonnées de
 * contact externe (téléphone, email, URL, handle réseau, mots-clés
 * hors-plateforme).
 *
 * Le message original reste dans l'input de l'utilisateur (pas effacé) :
 * il peut ainsi le réécrire sans tout recommencer.
 *
 * Style : Y2K Gen Z (visuel uniquement), ton de voix sobre PRO (vouvoiement,
 * pas d'argot, pas d'emojis dans le texte).
 *
 * Usage :
 *   <ModaleEducativeAntiLeak
 *     ouvert={modaleOuverte}
 *     onFermer={() => setModaleOuverte(false)}
 *     detectedType="TELEPHONE"
 *   />
 */
import { Mascotte } from '@/components/mascotte/Mascotte';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import {
  DialogResponsive,
  DialogResponsiveContent,
  DialogResponsiveHeader,
  DialogResponsiveTitle,
  DialogResponsiveDescription,
  DialogResponsiveBody,
  DialogResponsiveFooter,
} from '@/components/ui/DialogResponsive';
import type { DetectedType } from '@/lib/messagerieEnvoi';

export type { DetectedType } from '@/lib/messagerieEnvoi';

interface Props {
  ouvert: boolean;
  onFermer: () => void;
  detectedType: DetectedType | null;
}

const DESCRIPTIONS: Record<DetectedType, string> = {
  TELEPHONE: 'Les numéros de téléphone ne peuvent pas être échangés via la messagerie Jolene.',
  EMAIL: 'Les adresses email ne peuvent pas être échangées via la messagerie Jolene.',
  URL: 'Les liens externes ne peuvent pas être partagés via la messagerie Jolene.',
  HANDLE: "Les noms d'utilisateurs de réseaux sociaux ne peuvent pas être partagés via la messagerie Jolene.",
  KEYWORD: 'Cette mention pourrait suggérer un échange hors plateforme.',
};

const EXPLICATION = "Toutes les communications doivent rester sur la plateforme pour votre protection mutuelle et le bon fonctionnement de la mission. En cas de besoin pratique, contactez le support Jolene.";

export function ModaleEducativeAntiLeak({ ouvert, onFermer, detectedType }: Props) {
  const description = detectedType ? DESCRIPTIONS[detectedType] : DESCRIPTIONS.KEYWORD;

  return (
    <DialogResponsive open={ouvert} onOpenChange={(v) => { if (!v) onFermer(); }}>
      <DialogResponsiveContent maxWidth="md">
        <DialogResponsiveHeader>
          <DialogResponsiveTitle>Pour votre sécurité</DialogResponsiveTitle>
          <DialogResponsiveDescription>
            Règle de protection des échanges avant la confirmation d'une mission.
          </DialogResponsiveDescription>
        </DialogResponsiveHeader>
        <DialogResponsiveBody>
          <div className="flex flex-col items-center text-center gap-4">
            <Mascotte etat="thinking" taille="lg" />
            <p className="text-base font-semibold text-foreground">{description}</p>
            <p className="text-sm text-muted-foreground leading-relaxed">{EXPLICATION}</p>
          </div>
        </DialogResponsiveBody>
        <DialogResponsiveFooter>
          <BoutonY2K variant="primary" size="md" onClick={onFermer} className="w-full sm:w-auto">
            J'ai compris, je modifie mon message
          </BoutonY2K>
        </DialogResponsiveFooter>
      </DialogResponsiveContent>
    </DialogResponsive>
  );
}
