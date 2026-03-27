import React from 'react';
import { MapPin } from 'lucide-react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from '@/components/ui/dialog';

interface ConsentementGPSProps {
  onAccepter: () => void;
  onRefuser: () => void;
}

export function ConsentementGPS({ onAccepter, onRefuser }: ConsentementGPSProps) {
  return (
    <Dialog open={true} onOpenChange={(open) => { if (!open) onRefuser(); }}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <div className="mx-auto w-14 h-14 rounded-full bg-primary/10 flex items-center justify-center mb-2">
            <MapPin className="h-7 w-7 text-primary" aria-hidden="true" />
          </div>
          <DialogTitle className="text-center text-lg">
            Autorisation de géolocalisation
          </DialogTitle>
          <DialogDescription className="text-center text-sm text-muted-foreground leading-relaxed">
            Jolene utilise votre position pour vérifier que vous êtes bien dans l'établissement lors du pointage.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3 pt-2">
          <div className="bg-primary/5 border border-primary/20 rounded-xl p-4 space-y-2">
            <p className="text-sm font-semibold text-foreground">Ce que nous faisons :</p>
            <ul className="text-xs text-muted-foreground space-y-1 list-disc list-inside">
              <li>Relevé ponctuel au moment du clic sur « Pointer »</li>
              <li>Comparaison avec l'adresse de l'établissement</li>
              <li>Données conservées 1 an puis supprimées</li>
            </ul>
          </div>
          <div className="bg-destructive/5 border border-destructive/20 rounded-xl p-4 space-y-2">
            <p className="text-sm font-semibold text-foreground">Ce que nous ne faisons pas :</p>
            <ul className="text-xs text-muted-foreground space-y-1 list-disc list-inside">
              <li>Votre position n'est pas suivie en continu</li>
              <li>Aucun traçage en arrière-plan</li>
              <li>Aucun partage avec des tiers</li>
            </ul>
          </div>
          <p className="text-[11px] text-muted-foreground/70 italic">
            Base légale : consentement (Art. 6.1.a RGPD). Vous pouvez retirer votre consentement à tout moment depuis votre profil.
          </p>

          <div className="flex gap-3 pt-1">
            <button
              onClick={onRefuser}
              className="flex-1 min-h-[44px] px-4 py-2.5 rounded-lg text-sm font-medium bg-secondary text-secondary-foreground hover:bg-secondary/80 transition-colors"
            >
              Je refuse
            </button>
            <button
              onClick={onAccepter}
              className="flex-1 min-h-[44px] px-4 py-2.5 rounded-lg text-sm font-medium bg-primary text-primary-foreground hover:bg-primary/90 transition-colors"
            >
              Autoriser la localisation
            </button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
