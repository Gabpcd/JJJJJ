import { useState, useRef, useCallback } from 'react';
import { X, Upload, Camera } from 'lucide-react';
import { TYPES_DOCUMENTS } from '@/lib/documents';

interface ModalTeleversementProps {
  typeDocument: string;
  onConfirmer: (fichier: File, libelle: string, valideDepuis: string, valideJusqua: string) => Promise<void>;
  onFermer: () => void;
  aExpiration?: boolean;
}

export function ModalTeleversement({ typeDocument, onConfirmer, onFermer, aExpiration }: ModalTeleversementProps) {
  const [fichier, setFichier] = useState<File | null>(null);
  const [libelle, setLibelle] = useState('');
  const [valideDepuis, setValideDepuis] = useState(new Date().toISOString().split('T')[0]);
  const [valideJusqua, setValideJusqua] = useState('');
  const [envoi, setEnvoi] = useState(false);
  const [dragActive, setDragActive] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const cameraRef = useRef<HTMLInputElement>(null);
  const isMobile = typeof window !== 'undefined' && 'ontouchstart' in window;

  const handleFile = (f: File) => {
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
    <div className="fixed inset-0 z-[200] flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-foreground/50 backdrop-blur-sm" onClick={onFermer} />
      <div className="relative bg-card rounded-2xl shadow-xl p-6 mx-4 max-w-md w-full max-h-[90vh] overflow-y-auto">
        <button onClick={onFermer} className="absolute top-4 right-4 text-muted-foreground hover:text-foreground">
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
          <input ref={inputRef} type="file" accept=".pdf,.jpg,.jpeg,.png" className="hidden" onChange={e => e.target.files?.[0] && handleFile(e.target.files[0])} />
          {fichier ? (
            <div>
              <p className="text-sm font-medium text-foreground">📎 {fichier.name}</p>
              <p className="text-xs text-muted-foreground mt-1">{(fichier.size / 1024).toFixed(0)} Ko</p>
            </div>
          ) : (
            <>
              <Upload className="h-8 w-8 text-muted-foreground/40 mx-auto mb-2" />
              <p className="text-sm text-muted-foreground">Glissez votre fichier ici ou cliquez</p>
              <p className="text-xs text-muted-foreground/60 mt-1">PDF, JPG, PNG · 10 Mo max</p>
            </>
          )}
        </div>

        {/* Camera scanner - mobile only */}
        {isMobile && (
          <div className="mt-3">
            <input ref={cameraRef} type="file" accept="image/*" capture="environment" className="hidden" onChange={e => e.target.files?.[0] && handleFile(e.target.files[0])} />
            <button
              onClick={() => cameraRef.current?.click()}
              className="w-full flex items-center justify-center gap-2 px-4 py-3 bg-primary/5 border-2 border-dashed border-primary/30 rounded-xl text-primary font-semibold hover:bg-primary/10 transition"
            >
              <Camera className="h-5 w-5" /> Scanner avec la caméra
            </button>
          </div>
        )}

        {/* Metadata fields */}
        <div className="mt-4 space-y-3">
          <div>
            <label className="text-xs text-muted-foreground">Libellé (optionnel)</label>
            <input value={libelle} onChange={e => setLibelle(e.target.value)} className="input-base text-sm mt-1" placeholder="Ex: CNI recto-verso" />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="text-xs text-muted-foreground">Valide depuis</label>
              <input type="date" value={valideDepuis} onChange={e => setValideDepuis(e.target.value)} className="input-base text-sm mt-1" />
            </div>
            {aExpiration !== false && (
              <div>
                <label className="text-xs text-muted-foreground">Valide jusqu'au</label>
                <input type="date" value={valideJusqua} onChange={e => setValideJusqua(e.target.value)} className="input-base text-sm mt-1" />
              </div>
            )}
          </div>
        </div>

        <div className="flex gap-3 mt-6">
          <button onClick={onFermer} className="btn-secondary text-sm flex-1 py-2.5">Annuler</button>
          <button onClick={handleSubmit} disabled={!fichier || envoi} className="btn-primary text-sm flex-1 py-2.5 disabled:opacity-50">
            {envoi ? 'Envoi…' : 'Téléverser'}
          </button>
        </div>
      </div>
    </div>
  );
}
