import React, { useState } from 'react';
import { Copy, CheckCircle, MessageCircle } from 'lucide-react';
import { QRCodeSVG } from 'qrcode.react';

interface EncartInvitationProps {
  codeParrainage: string;
}

export function EncartInvitation({ codeParrainage }: EncartInvitationProps) {
  const [copied, setCopied] = useState(false);
  const lienRef = `https://app.joleneapp.com?ref=${codeParrainage}`;
  const messageWhatsApp = encodeURIComponent(
    `Rejoignez Jolene, la plateforme de staffing médical ! Inscrivez-vous avec mon lien et obtenez +50h bonus : ${lienRef}`
  );

  const copierLien = () => {
    navigator.clipboard.writeText(lienRef);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="card-base bg-gradient-to-br from-primary/5 to-info/5 border-primary/20">
      <h2 className="text-base font-semibold text-foreground mb-1 flex items-center gap-2">
        🎁 Invitez vos collègues
      </h2>
      <p className="text-xs text-muted-foreground mb-4">
        Partagez votre lien et obtenez +50h bonus chacun !
      </p>

      <div className="flex flex-col sm:flex-row gap-4 items-center">
        {/* QR Code — generated locally, no third-party service (RGPD compliant) */}
        <div className="shrink-0 bg-background p-2 rounded-lg">
          <QRCodeSVG
            value={lienRef}
            size={120}
            level="M"
            bgColor="transparent"
            fgColor="currentColor"
            className="text-foreground"
          />
        </div>

        <div className="flex-1 space-y-3 w-full">
          {/* Lien */}
          <div className="bg-muted rounded-lg px-3 py-2 text-xs font-mono text-muted-foreground break-all">
            {lienRef}
          </div>

          {/* Boutons */}
          <div className="flex gap-2 flex-wrap">
            <button
              onClick={copierLien}
              className="btn-primary text-xs py-2 px-4 flex items-center gap-1.5"
            >
              {copied ? (
                <><CheckCircle className="h-3.5 w-3.5" /> Copié !</>
              ) : (
                <><Copy className="h-3.5 w-3.5" /> Copier le lien</>
              )}
            </button>

            <a
              href={`https://wa.me/?text=${messageWhatsApp}`}
              target="_blank"
              rel="noopener noreferrer"
              className="btn-secondary text-xs py-2 px-4 flex items-center gap-1.5 bg-[#25D366]/10 text-[#25D366] border-[#25D366]/30 hover:bg-[#25D366]/20"
            >
              <MessageCircle className="h-3.5 w-3.5" /> WhatsApp
            </a>
          </div>
        </div>
      </div>
    </div>
  );
}
