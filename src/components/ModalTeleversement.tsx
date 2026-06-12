import { useState, useRef, useCallback } from 'react';
import { X, Upload, Camera } from 'lucide-react';
import { TYPES_DOCUMENTS } from '@/lib/documents';
import { isNative } from '@/lib/platform';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
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

  // Reset state à la fermeture pour éviter de réouvrir avec un fichier précédent
  const fermerEtReinitialiser = () => {
    setFichier(null);
    setLibelle('');
    onFermer();
  };
  const [envoi, setEnvoi] = useState(false);
  const [dragActive, setDragActive] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const cameraRef = useRef<HTMLInputElement>(null);
  const isMobile = typeof window !== 'undefined' && ('ontouchstart' in window || isNative());

  const placeholder = PLACEHOLDERS_LIBELLE[typeDocument] || 'Ex : Description du document';

  const handleFile = (f: File) => {
    const estSupporte = f.type === 'application/pdf' || f.type.startsWith('image/') || /\.(pdf|png|jpe?g|webp|heic|heif)$/i.test(f.name);
    if (!estSupporte) {
      toast.error('Format non pris en charge. Utilisez un PDF ou une image.');
      return;
    }
    if (f.size > 10 * 1024 * 1024) {
      toast.error('Le fichier ne doit pas dépasser 10 Mo.');
      return;
    }
    setFichier(f);
  };

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setDragActive(false);
    if (e.dataTransfer.files[0]) handleFile(e.dataTransfer.files[0]);
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
          handleFile(file);
        }
      } catch {
        toast.error("Impossible d'accéder à la caméra.");
      }
    } else {
      cameraRef.current?.click();
    }
  };

  return (
    <div className="fixed inset-0 z-[9999] flex items-start justify-center overflow-y-auto overscroll-contain" style={{ paddingTop: 'max(1rem, env(safe-area-inset-top))', paddingBottom: 'max(1rem, env(safe-area-inset-bottom))', paddingLeft: 'max(1rem, env(safe-area-inset-left))', paddingRight: 'max(1rem, env(safe-area-inset-right))' }}>
      <div className="fixed inset-0 bg-foreground/50" style={{ backdropFilter: 'blur(4px)', WebkitBackdropFilter: 'blur(4px)' }} onClick={fermerEtReinitialiser} />
      <div className="relative bg-card rounded-2xl shadow-xl p-6 max-w-md w-full my-auto">
        <button onClick={fermerEtReinitialiser} className="absolute top-4 right-4 text-muted-foreground hover:text-foreground">
          <X className="h-5 w-5" />
        </button>

        <h3 className="text-lg font-bold text-foreground mb-1">📤 Téléverser</h3>
        <p className="text-sm text-muted-foreground mb-1">{TYPES_DOCUMENTS[typeDocument] || typeDocument}</p>
        <p className="text-xs text-muted-foreground mb-4">
          Une photo nette suffit — les dates de validité sont lues automatiquement sur votre document.
        </p>

        {/* Mobile : prendre une photo = action n°1, visuellement dominante */}
        {isMobile && (
          <div className="mb-3 space-y-2">
            <input ref={cameraRef} type="file" accept="image/*,.heic,.heif" capture="environment" className="hidden" onChange={e => e.target.files?.[0] && handleFile(e.target.files[0])} />
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
                      handleFile(file);
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
          className={`border-2 border-dashed rounded-xl text-center cursor-pointer transition-colors
            ${isMobile ? 'p-4' : 'p-6'}
            ${dragActive ? 'border-primary bg-primary/5' : 'border-border hover:border-primary/50'}
            ${fichier ? 'bg-success/5 border-success/30' : ''}`}
        >
          <input ref={inputRef} type="file" accept="application/pdf,image/*,.heic,.heif" className="hidden" onChange={e => e.target.files?.[0] && handleFile(e.target.files[0])} />
          {fichier ? (
            <div>
              <p className="text-sm font-medium text-foreground">📎 {fichier.name}</p>
              <p className="text-xs text-muted-foreground mt-1">{(fichier.size / 1024).toFixed(0)} Ko</p>
            </div>
          ) : (
            <>
              {!isMobile && <Upload className="h-8 w-8 text-muted-foreground/40 mx-auto mb-2" />}
              <p className="text-sm text-muted-foreground">{isMobile ? 'ou choisissez un fichier' : 'Glissez votre fichier ici ou cliquez'}</p>
              <p className="text-xs text-muted-foreground/60 mt-1">PDF ou image · 10 Mo max</p>
            </>
          )}
        </div>

        {/* Libellé optionnel (les dates de validité sont extraites par l'IA) */}
        <div className="mt-4">
          <label htmlFor="televersement-libelle" className="text-xs text-muted-foreground">Libellé (optionnel)</label>
          <input id="televersement-libelle" value={libelle} onChange={e => setLibelle(e.target.value)} className="input-base text-sm mt-1" placeholder={placeholder} />
        </div>

        <div className="flex gap-3 mt-6">
          <button onClick={fermerEtReinitialiser} className="btn-secondary text-sm flex-1 py-2.5">Annuler</button>
          <button onClick={handleSubmit} disabled={!fichier || envoi} className="btn-primary text-sm flex-1 py-2.5 disabled:opacity-50">
            {envoi ? 'Envoi…' : 'Téléverser'}
          </button>
        </div>
      </div>
    </div>
  );
}
