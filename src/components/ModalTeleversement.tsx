import { useState, useRef, useCallback, useEffect } from 'react';
import { createPortal } from 'react-dom';
import { X, Upload, Camera } from 'lucide-react';
import { TYPES_DOCUMENTS } from '@/lib/documents';
import { isNative } from '@/lib/platform';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { verifierFichierDocument } from '@/lib/documentUpload';
import { toast } from 'sonner';

// Placeholders adaptés par type de document
const PLACEHOLDERS_LIBELLE: Record<string, string> = {
  'CARTE_IDENTITE': 'Ex : CNI recto-verso',
  'PASSEPORT': 'Ex : Passeport page 2-3',
  'TITRE_SEJOUR': 'Ex : Titre de séjour recto',
  'DIPLOME': 'Ex : Diplôme IDE 2020',
  'RPPS_ADELI': 'Ex : Attestation RPPS ordre infirmier',
  'RCP_ASSURANCE': 'Ex : Attestation RCP 2025-2026',
  'VACCINATIONS': 'Ex : Carnet de vaccination',
  'CASIER_JUDICIAIRE': 'Ex : Extrait B3',
  'RIB': 'Ex : RIB BNP',
  'KBIS': 'Ex : KBIS janvier 2025',
  'ATTESTATION_URSSAF': 'Ex : Attestation URSSAF trimestre',
  'AUTORISATION_EXERCICE': 'Ex : Autorisation ARS',
  'FORMATION_OBLIGATOIRE': 'Ex : Attestation AFGSU',
  'AUTRE': 'Ex : Document complémentaire',
};

interface ModalTeleversementProps {
  typeDocument: string;
  /* Session E : plus de saisie manuelle des dates de validité — elles sont
     extraites automatiquement par la vérification IA (verify-document). */
  onConfirmer: (fichier: File, libelle: string) => Promise<void>;
  onFermer: () => void;
}

export function ModalTeleversement({ typeDocument, onConfirmer, onFermer }: ModalTeleversementProps) {
  const [fichier, setFichier] = useState<File | null>(null);
  const [libelle, setLibelle] = useState('');
  const [envoi, setEnvoi] = useState(false);

  // Reset state à la fermeture pour éviter de réouvrir avec un fichier précédent
  const fermerEtReinitialiser = useCallback(() => {
    setFichier(null);
    setLibelle('');
    onFermer();
  }, [onFermer]);
  const [dragActive, setDragActive] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const cameraRef = useRef<HTMLInputElement>(null);
  const isMobile = typeof window !== 'undefined' && ('ontouchstart' in window || isNative());

  const placeholder = PLACEHOLDERS_LIBELLE[typeDocument] || 'Ex : Description du document';

  const handleFile = useCallback(async (f: File) => {
    const validation = await verifierFichierDocument(f);
    if (validation.ok === false) {
      setFichier(null);
      toast.error(validation.message);
      return;
    }
    setFichier(f);
  }, []);

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setDragActive(false);
    if (e.dataTransfer.files[0]) void handleFile(e.dataTransfer.files[0]);
  }, [handleFile]);

  useEffect(() => {
    const fermerAvecEchap = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && !envoi) fermerEtReinitialiser();
    };
    window.addEventListener('keydown', fermerAvecEchap);
    return () => window.removeEventListener('keydown', fermerAvecEchap);
  }, [envoi, fermerEtReinitialiser]);

  useEffect(() => {
    const overflowPrecedent = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => { document.body.style.overflow = overflowPrecedent; };
  }, []);

  const handleSubmit = async () => {
    if (!fichier) return;
    setEnvoi(true);
    try {
      await onConfirmer(fichier, libelle);
    } finally {
      setEnvoi(false);
    }
  };

  const prendrePhoto = async () => {
    if (isNative()) {
      try {
        const { prendrePhoto: capturer } = await import('@/lib/platform');
        const result = await capturer();
        if (result?.dataUrl) {
          const res = await fetch(result.dataUrl);
          const blob = await res.blob();
          const file = new File([blob], `photo_${Date.now()}.jpg`, { type: blob.type || 'image/jpeg' });
          await handleFile(file);
        }
      } catch {
        toast.error("Impossible d'accéder à la caméra.");
      }
    } else {
      cameraRef.current?.click();
    }
  };

  const contenu = (
    <div className="fixed inset-0 z-[9999] flex min-h-[100dvh] items-start sm:items-center justify-center overflow-y-auto overscroll-contain" style={{ paddingTop: 'max(1rem, env(safe-area-inset-top))', paddingBottom: 'max(1rem, env(safe-area-inset-bottom))', paddingLeft: 'max(1rem, env(safe-area-inset-left))', paddingRight: 'max(1rem, env(safe-area-inset-right))' }}>
      <div className="fixed inset-0 bg-foreground/50" style={{ backdropFilter: 'blur(4px)', WebkitBackdropFilter: 'blur(4px)' }} onClick={() => { if (!envoi) fermerEtReinitialiser(); }} />
      <div role="dialog" aria-modal="true" aria-labelledby="televersement-titre" aria-describedby="televersement-aide" aria-busy={envoi} className="relative bg-card rounded-2xl shadow-xl p-6 max-w-md w-full max-h-[calc(100dvh-2rem)] overflow-y-auto">
        <button type="button" onClick={fermerEtReinitialiser} disabled={envoi} aria-label="Fermer la fenêtre de téléversement" className="absolute top-4 right-4 text-muted-foreground hover:text-foreground disabled:opacity-50">
          <X className="h-5 w-5" />
        </button>

        <h3 id="televersement-titre" className="text-lg font-bold text-foreground mb-1">📤 Téléverser</h3>
        <p className="text-sm text-muted-foreground mb-1">{TYPES_DOCUMENTS[typeDocument] || typeDocument}</p>
        <p id="televersement-aide" className="text-xs text-muted-foreground mb-4">
          Une photo nette suffit — les dates de validité sont lues automatiquement sur votre document.
        </p>

        {/* Mobile : prendre une photo = action n°1, visuellement dominante */}
        {isMobile && (
          <div className="mb-3 space-y-2">
            <input ref={cameraRef} type="file" accept="image/jpeg,image/png,image/webp" capture="environment" className="hidden" onChange={e => { const selected = e.target.files?.[0]; if (selected) void handleFile(selected); e.target.value = ''; }} />
            <BoutonY2K
              variant="primary"
              size="lg"
              className="w-full"
              iconeGauche={<Camera className="h-5 w-5" />}
              onClick={prendrePhoto}
            >
              Prendre une photo
            </BoutonY2K>
            {isNative() && (
              <button
                type="button"
                onClick={async () => {
                  try {
                    const { Camera: CapCamera, CameraResultType, CameraSource } = await import('@capacitor/camera');
                    const photo = await CapCamera.getPhoto({
                      resultType: CameraResultType.DataUrl,
                      source: CameraSource.Photos,
                      quality: 80,
                    });
                    if (photo.dataUrl) {
                      const res = await fetch(photo.dataUrl);
                      const blob = await res.blob();
                      const file = new File([blob], `galerie_${Date.now()}.jpg`, { type: blob.type || 'image/jpeg' });
                      await handleFile(file);
                    }
                  } catch {
                    toast.error("Impossible d'accéder à la galerie.");
                  }
                }}
                className="w-full flex items-center justify-center gap-2 px-4 py-3 bg-secondary/50 border-2 border-dashed border-border rounded-xl text-foreground font-semibold hover:bg-secondary/80 transition min-h-[44px]"
              >
                <Upload className="h-5 w-5" /> Choisir dans la galerie
              </button>
            )}
          </div>
        )}

        {/* Drop zone : primaire desktop, secondaire mobile */}
        <div
          onDragOver={e => { e.preventDefault(); setDragActive(true); }}
          onDragLeave={() => setDragActive(false)}
          onDrop={handleDrop}
          onClick={() => inputRef.current?.click()}
          onKeyDown={event => {
            if (event.key === 'Enter' || event.key === ' ') {
              event.preventDefault();
              inputRef.current?.click();
            }
          }}
          role="button"
          tabIndex={0}
          aria-label="Choisir un document à téléverser"
          aria-describedby="televersement-formats"
          className={`border-2 border-dashed rounded-xl text-center cursor-pointer transition-colors
            ${isMobile ? 'p-4' : 'p-6'}
            ${dragActive ? 'border-primary bg-primary/5' : 'border-border hover:border-primary/50'}
            ${fichier ? 'bg-success/5 border-success/30' : ''}`}
        >
          <input ref={inputRef} type="file" accept="application/pdf,image/jpeg,image/png,image/webp" className="hidden" onChange={e => { const selected = e.target.files?.[0]; if (selected) void handleFile(selected); e.target.value = ''; }} />
          <span id="televersement-formats" className="sr-only">Formats autorisés : PDF, JPEG, PNG ou WebP, 10 Mo maximum.</span>
          {fichier ? (
            <div>
              <p className="text-sm font-medium text-foreground">📎 {fichier.name}</p>
              <p className="text-xs text-muted-foreground mt-1">{(fichier.size / 1024).toFixed(0)} Ko</p>
            </div>
          ) : (
            <>
              {!isMobile && <Upload className="h-8 w-8 text-muted-foreground/40 mx-auto mb-2" />}
              <p className="text-sm text-muted-foreground">{isMobile ? 'ou choisissez un fichier' : 'Glissez votre fichier ici ou cliquez'}</p>
              <p aria-hidden="true" className="text-xs text-muted-foreground/60 mt-1">PDF, JPEG, PNG ou WebP · 10 Mo max</p>
            </>
          )}
        </div>

        {/* Libellé optionnel (les dates de validité sont extraites par l'IA) */}
        <div className="mt-4">
          <label htmlFor="televersement-libelle" className="text-xs text-muted-foreground">Libellé (optionnel)</label>
          <input id="televersement-libelle" value={libelle} onChange={e => setLibelle(e.target.value)} className="input-base text-sm mt-1" placeholder={placeholder} />
        </div>

        <div className="flex gap-3 mt-6">
          <button type="button" onClick={fermerEtReinitialiser} disabled={envoi} className="btn-secondary text-sm flex-1 py-2.5 disabled:opacity-50">Annuler</button>
          <button type="button" onClick={handleSubmit} disabled={!fichier || envoi} className="btn-primary text-sm flex-1 py-2.5 disabled:opacity-50">
            {envoi ? 'Envoi…' : 'Téléverser'}
          </button>
        </div>
      </div>
    </div>
  );

  return createPortal(contenu, document.body);
}
