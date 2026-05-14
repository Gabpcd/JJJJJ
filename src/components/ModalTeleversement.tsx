import { useState, useRef, useCallback } from 'react';
import { X, Upload, Camera } from 'lucide-react';
import { TYPES_DOCUMENTS } from '@/lib/documents';
import { isNative } from '@/lib/platform';
import { toast } from 'sonner';

// Types de documents sans dates de validité
const TYPES_SANS_DATES = ['RIB', 'KBIS'];
const TYPES_SANS_EXPIRATION = ['RIB', 'KBIS', 'DIPLOME', 'CASIER_JUDICIAIRE'];

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
  onConfirmer: (fichier: File, libelle: string, valideDepuis: string, valideJusqua: string) => Promise<void>;
  onFermer: () => void;
  aExpiration?: boolean;
}

export function ModalTeleversement({ typeDocument, onConfirmer, onFermer, aExpiration }: ModalTeleversementProps) {
  const [fichier, setFichier] = useState<File | null>(null);
  const [libelle, setLibelle] = useState('');
  const [valideDepuis, setValideDepuis] = useState('');
  const [valideJusqua, setValideJusqua] = useState('');

  // Reset state à la fermeture pour éviter de réouvrir avec un fichier précédent
  const fermerEtReinitialiser = () => {
    setFichier(null);
    setLibelle('');
    setValideDepuis('');
    setValideJusqua('');
    onFermer();
  };
  const [envoi, setEnvoi] = useState(false);
  const [dragActive, setDragActive] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const cameraRef = useRef<HTMLInputElement>(null);
  const isMobile = typeof window !== 'undefined' && ('ontouchstart' in window || isNative());

  const sansDate = TYPES_SANS_DATES.includes(typeDocument);
  const sansExpiration = TYPES_SANS_EXPIRATION.includes(typeDocument) || aExpiration === false;
  const placeholder = PLACEHOLDERS_LIBELLE[typeDocument] || 'Ex : Description du document';

  const handleFile = (f: File) => {
    const estSupporte = f.type === 'application/pdf' || f.type.startsWith('image/') || /\.(pdf|png|jpe?g|webp|heic|heif)$/i.test(f.name);
    if (!estSupporte) {
      alert('Format non pris en charge. Utilisez un PDF ou une image.');
      return;
    }
    if (f.size > 10 * 1024 * 1024) {
      alert('Le fichier ne doit pas dépasser 10 Mo.');
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
      await onConfirmer(fichier, libelle, valideDepuis, valideJusqua);
    } finally {
      setEnvoi(false);
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
        <p className="text-sm text-muted-foreground mb-4">{TYPES_DOCUMENTS[typeDocument] || typeDocument}</p>

        {/* Drop zone */}
        <div
          onDragOver={e => { e.preventDefault(); setDragActive(true); }}
          onDragLeave={() => setDragActive(false)}
          onDrop={handleDrop}
          onClick={() => inputRef.current?.click()}
          className={`border-2 border-dashed rounded-xl p-6 text-center cursor-pointer transition-colors
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
              <Upload className="h-8 w-8 text-muted-foreground/40 mx-auto mb-2" />
              <p className="text-sm text-muted-foreground">Glissez votre fichier ici ou cliquez</p>
              <p className="text-xs text-muted-foreground/60 mt-1">PDF ou image · 20 Mo max</p>
            </>
          )}
        </div>

        {/* Camera / gallery buttons - mobile only */}
        {isMobile && (
          <div className="mt-3 flex gap-2">
            <input ref={cameraRef} type="file" accept="image/*,.heic,.heif" capture="environment" className="hidden" onChange={e => e.target.files?.[0] && handleFile(e.target.files[0])} />
            <button
              onClick={async () => {
                if (isNative()) {
                  try {
                    const { prendrePhoto } = await import('@/lib/platform');
                    const result = await prendrePhoto();
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
              }}
              className="flex-1 flex items-center justify-center gap-2 px-4 py-3 bg-primary/5 border-2 border-dashed border-primary/30 rounded-xl text-primary font-semibold hover:bg-primary/10 transition min-h-[44px]"
            >
              <Camera className="h-5 w-5" /> Prendre une photo
            </button>
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
                className="flex-1 flex items-center justify-center gap-2 px-4 py-3 bg-secondary/50 border-2 border-dashed border-border rounded-xl text-foreground font-semibold hover:bg-secondary/80 transition min-h-[44px]"
              >
                <Upload className="h-5 w-5" /> Galerie
              </button>
            )}
          </div>
        )}

        {/* Metadata fields */}
        <div className="mt-4 space-y-3">
          <div>
            <label htmlFor="televersement-libelle" className="text-xs text-muted-foreground">Libellé (optionnel)</label>
            <input id="televersement-libelle" value={libelle} onChange={e => setLibelle(e.target.value)} className="input-base text-sm mt-1" placeholder={placeholder} />
          </div>
          {!sansDate && (
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label htmlFor="televersement-valide-depuis" className="text-xs text-muted-foreground">Valide depuis</label>
                <input id="televersement-valide-depuis" type="date" value={valideDepuis} onChange={e => setValideDepuis(e.target.value)} className="input-base text-sm mt-1" />
              </div>
              {!sansExpiration && (
                <div>
                  <label htmlFor="televersement-valide-jusqua" className="text-xs text-muted-foreground">Valide jusqu'au</label>
                  <input id="televersement-valide-jusqua" type="date" value={valideJusqua} onChange={e => setValideJusqua(e.target.value)} className="input-base text-sm mt-1" />
                </div>
              )}
            </div>
          )}
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
