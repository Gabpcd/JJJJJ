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
  DialogResponsiveBody,
  DialogResponsiveFooter,
} from '@/components/ui/DialogResponsive';

export type DetectedType = 'TELEPHONE' | 'EMAIL' | 'URL' | 'HANDLE' | 'KEYWORD';

interface Props {
  ouvert: boolean;
  onFermer: () => void;
  detectedType: DetectedType | null;
}

/* 7e-1 (§6.4) : le message PART, les coordonnées sont masquées — la copy
   explique le pourquoi sans punir (montrée une seule fois). */
const DESCRIPTIONS: Record<DetectedType, string> = {
  TELEPHONE: 'Votre message a été envoyé — le numéro de téléphone a été masqué.',
  EMAIL: "Votre message a été envoyé — l'adresse email a été masquée.",
  URL: 'Votre message a été envoyé — le lien externe a été masqué.',
  HANDLE: "Votre message a été envoyé — l'identifiant de réseau social a été masqué.",
  KEYWORD: 'Cette mention pourrait suggérer un échange hors plateforme.',
};

const EXPLICATION = "Avant la confirmation d'une mission, les coordonnées restent sur la plateforme : c'est ce qui garantit le paiement, la protection en cas de litige et les heures comptées vers vos 3 200 h. Dès la mission confirmée, les coordonnées s'échangent librement.";

export function ModaleEducativeAntiLeak({ ouvert, onFermer, detectedType }: Props) {
  const description = detectedType ? DESCRIPTIONS[detectedType] : DESCRIPTIONS.KEYWORD;

  return (
    <DialogResponsive open={ouvert} onOpenChange={(v) => { if (!v) onFermer(); }}>
      <DialogResponsiveContent maxWidth="md">
        <DialogResponsiveHeader>
          <DialogResponsiveTitle>Pour votre sécurité</DialogResponsiveTitle>
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
