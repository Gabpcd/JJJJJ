import React from 'react';
import { useNavigate } from 'react-router-dom';
import { QRCodeSVG } from 'qrcode.react';
import { SEOHead } from '@/components/SEOHead';
import { SEOPageLayout } from '@/components/SEOPageLayout';
import { Zap, FileText, MapPin, Bell, ArrowRight, Smartphone } from 'lucide-react';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip';

/* ─── Phone mockup SVG ─── */
function PhoneMockup() {
  return (
    <div className="relative mx-auto w-56 md:w-64">
      <svg viewBox="0 0 240 480" fill="none" xmlns="http://www.w3.org/2000/svg" className="w-full drop-shadow-2xl">
        {/* Phone body */}
        <rect x="10" y="10" width="220" height="460" rx="36" className="fill-foreground/10 stroke-border" strokeWidth="2" />
        <rect x="18" y="18" width="204" height="444" rx="30" className="fill-card stroke-border" strokeWidth="1" />
        {/* Notch */}
        <rect x="80" y="24" width="80" height="24" rx="12" className="fill-muted" />
        {/* Screen content */}
        <rect x="30" y="60" width="180" height="10" rx="2" className="fill-primary/60" />
        <rect x="30" y="78" width="120" height="6" rx="2" className="fill-muted-foreground/30" />
        {/* Mission card mock */}
        <rect x="30" y="100" width="180" height="90" rx="10" className="fill-primary/10 stroke-primary/30" strokeWidth="1" />
        <rect x="42" y="112" width="80" height="8" rx="2" className="fill-primary" />
        <rect x="42" y="126" width="140" height="5" rx="1" className="fill-muted-foreground/40" />
        <rect x="42" y="136" width="100" height="5" rx="1" className="fill-muted-foreground/30" />
        <rect x="42" y="152" width="60" height="20" rx="6" className="fill-primary" />
        <rect x="48" y="158" width="48" height="8" rx="2" className="fill-primary-foreground" />
        {/* Second card */}
        <rect x="30" y="200" width="180" height="70" rx="10" className="fill-muted/80 stroke-border" strokeWidth="1" />
        <rect x="42" y="212" width="70" height="7" rx="2" className="fill-foreground/40" />
        <rect x="42" y="225" width="130" height="5" rx="1" className="fill-muted-foreground/30" />
        <rect x="42" y="235" width="90" height="5" rx="1" className="fill-muted-foreground/20" />
        {/* Third card */}
        <rect x="30" y="280" width="180" height="70" rx="10" className="fill-muted/80 stroke-border" strokeWidth="1" />
        <rect x="42" y="292" width="90" height="7" rx="2" className="fill-foreground/40" />
        <rect x="42" y="305" width="110" height="5" rx="1" className="fill-muted-foreground/30" />
        <rect x="42" y="315" width="70" height="5" rx="1" className="fill-muted-foreground/20" />
        {/* Bottom nav */}
        <rect x="30" y="400" width="180" height="44" rx="12" className="fill-muted" />
        <circle cx="66" cy="422" r="8" className="fill-muted-foreground/30" />
        <circle cx="120" cy="422" r="10" className="fill-primary" />
        <circle cx="174" cy="422" r="8" className="fill-muted-foreground/30" />
        {/* Home indicator */}
        <rect x="90" y="450" width="60" height="4" rx="2" className="fill-muted-foreground/40" />
      </svg>
    </div>
  );
}

const features = [
  { icon: Zap, titre: 'Missions en temps réel', desc: 'Recevez les nouvelles missions instantanément et postulez en un clic.' },
  { icon: FileText, titre: 'Contrats dématérialisés', desc: 'Signez vos contrats électroniquement, directement depuis l\'app.' },
  { icon: MapPin, titre: 'Pointage GPS', desc: 'Pointez votre arrivée et votre départ avec géolocalisation vérifiée.' },
  { icon: Bell, titre: 'Notifications push', desc: 'Soyez alerté des nouvelles missions et des messages en temps réel.' },
];

export default function Telecharger() {
  const navigate = useNavigate();

  return (
    <>
      <SEOHead
        title="Télécharger Jolene | App iOS et Android"
        description="Téléchargez Jolene sur iPhone et Android. Trouvez des missions, signez vos contrats et pointez votre arrivée depuis votre téléphone."
        url="https://jolene.app/telecharger"
      />
      <SEOPageLayout
        heroTitle="Jolene dans votre poche"
        heroSubtitle="Trouvez des missions, signez vos contrats et pointez votre arrivée — tout depuis votre téléphone."
        ctaText="Créer mon compte gratuitement"
        ctaHref="/inscription/soignant"
      >
        {/* Phone + Store badges */}
        <section className="py-16 md:py-20">
          <div className="max-w-5xl mx-auto px-4 flex flex-col md:flex-row items-center gap-12">
            <PhoneMockup />
            <div className="flex-1 text-center md:text-left">
              <h2 className="text-2xl md:text-3xl font-bold text-foreground mb-6">Bientôt sur les stores</h2>
              <p className="text-muted-foreground mb-8">L'application Jolene sera disponible sur iOS et Android. Inscrivez-vous dès maintenant pour être notifié du lancement.</p>
              <div className="flex flex-wrap gap-4 justify-center md:justify-start">
                <Tooltip>
                  <TooltipTrigger asChild>
                    <button type="button" aria-label="App Store — bientôt disponible" className="inline-block cursor-default">
                      <svg width="150" height="50" viewBox="0 0 150 50" className="rounded-lg">
                        <rect width="150" height="50" rx="8" className="fill-foreground" />
                        <text x="75" y="18" textAnchor="middle" className="fill-background" fontSize="8" fontFamily="system-ui">Télécharger sur l'</text>
                        <text x="75" y="35" textAnchor="middle" className="fill-background" fontSize="16" fontWeight="600" fontFamily="system-ui">App Store</text>
                      </svg>
                    </button>
                  </TooltipTrigger>
                  <TooltipContent>Bientôt disponible</TooltipContent>
                </Tooltip>
                <Tooltip>
                  <TooltipTrigger asChild>
                    <button type="button" aria-label="Google Play — bientôt disponible" className="inline-block cursor-default">
                      <svg width="170" height="50" viewBox="0 0 170 50" className="rounded-lg">
                        <rect width="170" height="50" rx="8" className="fill-foreground" />
                        <text x="85" y="18" textAnchor="middle" className="fill-background" fontSize="8" fontFamily="system-ui">Disponible sur</text>
                        <text x="85" y="35" textAnchor="middle" className="fill-background" fontSize="16" fontWeight="600" fontFamily="system-ui">Google Play</text>
                      </svg>
                    </button>
                  </TooltipTrigger>
                  <TooltipContent>Bientôt disponible</TooltipContent>
                </Tooltip>
              </div>
            </div>
          </div>
        </section>

        {/* En attendant */}
        <section className="py-16 md:py-20 bg-muted/50">
          <div className="max-w-3xl mx-auto px-4 text-center">
            <Smartphone className="h-10 w-10 text-primary mx-auto mb-4" />
            <h2 className="text-2xl md:text-3xl font-bold text-foreground mb-4">En attendant</h2>
            <p className="text-muted-foreground mb-6">Vous pouvez déjà utiliser Jolene depuis votre navigateur mobile.</p>
            <BoutonY2K onClick={() => navigate('/connexion')} className="mb-10" iconeDroite={<ArrowRight className="h-4 w-4" />}>
              Ouvrir l'app web
            </BoutonY2K>

            <div className="bg-card border border-border rounded-xl p-6 text-left max-w-md mx-auto">
              <h3 className="font-semibold text-foreground mb-4 text-center">Ajouter à l'écran d'accueil</h3>
              <div className="space-y-4 text-sm text-muted-foreground">
                <div>
                  <p className="font-medium text-foreground mb-1">📱 Sur iPhone</p>
                  <p>Safari → Partager (↑) → <strong className="text-foreground">Sur l'écran d'accueil</strong></p>
                </div>
                <div>
                  <p className="font-medium text-foreground mb-1">🤖 Sur Android</p>
                  <p>Chrome → Menu (⋮) → <strong className="text-foreground">Ajouter à l'écran d'accueil</strong></p>
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* Fonctionnalités */}
        <section className="py-16 md:py-20">
          <div className="max-w-5xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-12">Tout ce qu'il vous faut, en poche</h2>
            <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 md:gap-8">
              {features.map((f) => (
                <div key={f.titre} className="text-center">
                  <div className="w-14 h-14 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto mb-4">
                    <f.icon className="h-7 w-7 text-primary" />
                  </div>
                  <h3 className="font-semibold text-foreground mb-2 text-sm">{f.titre}</h3>
                  <p className="text-xs text-muted-foreground leading-relaxed">{f.desc}</p>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* QR Code */}
        <section className="py-16 md:py-20 bg-muted/50">
          <div className="max-w-md mx-auto px-4 text-center">
            <h2 className="text-xl font-bold text-foreground mb-6">Scannez pour accéder à Jolene</h2>
            <div className="bg-card p-6 rounded-2xl inline-block shadow-sm border border-border">
              <QRCodeSVG value="https://jolene.app" size={180} level="M" />
            </div>
            <p className="text-sm text-muted-foreground mt-4">Ouvrez l'appareil photo de votre téléphone et scannez ce code</p>
          </div>
        </section>
      </SEOPageLayout>
    </>
  );
}
