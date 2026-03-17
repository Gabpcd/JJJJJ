import React from 'react';
import { MapPin } from 'lucide-react';

interface ConsentementGPSProps {
  onAccepter: () => void;
  onRefuser: () => void;
}

export function ConsentementGPS({ onAccepter, onRefuser }: ConsentementGPSProps) {
  return (
    <div className="fixed inset-0 z-[300] flex items-center justify-center bg-background">
      <div className="max-w-lg mx-4 text-center space-y-6">
        <div className="mx-auto w-16 h-16 rounded-full bg-primary/10 flex items-center justify-center">
          <MapPin className="h-8 w-8 text-primary" />
        </div>
        <h1 className="text-2xl font-bold text-foreground">📍 Autorisation de géolocalisation</h1>
        <div className="card-base text-left space-y-4">
          <p className="text-sm text-foreground leading-relaxed">
            Jolene utilise votre position GPS <strong>uniquement au moment du pointage d'arrivée et de départ</strong> pour vérifier votre présence sur site.
          </p>
          <div className="bg-primary/5 border border-primary/20 rounded-xl p-4 space-y-2">
            <p className="text-sm font-semibold text-foreground">✅ Ce que nous faisons :</p>
            <ul className="text-xs text-muted-foreground space-y-1 list-disc list-inside">
              <li>Relevé ponctuel au moment du clic sur "Pointer"</li>
              <li>Comparaison avec l'adresse de l'établissement</li>
              <li>Données conservées <strong>1 an</strong> puis supprimées</li>
            </ul>
          </div>
          <div className="bg-destructive/5 border border-destructive/20 rounded-xl p-4 space-y-2">
            <p className="text-sm font-semibold text-foreground">❌ Ce que nous ne faisons PAS :</p>
            <ul className="text-xs text-muted-foreground space-y-1 list-disc list-inside">
              <li>Votre position n'est PAS suivie en continu</li>
              <li>Aucun traçage en arrière-plan</li>
              <li>Aucun partage avec des tiers</li>
            </ul>
          </div>
          <p className="text-[11px] text-muted-foreground/70 italic">
            Base légale : consentement (Art. 6.1.a RGPD). Vous pouvez retirer votre consentement à tout moment depuis votre profil.
          </p>
        </div>
        <div className="flex gap-3">
          <button onClick={onRefuser} className="btn-secondary flex-1 py-3">
            Je refuse
          </button>
          <button onClick={onAccepter} className="btn-primary flex-1 py-3">
            ✅ J'accepte
          </button>
        </div>
      </div>
    </div>
  );
}
