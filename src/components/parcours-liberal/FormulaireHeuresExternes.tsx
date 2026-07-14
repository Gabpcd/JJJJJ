import { useRef, useState } from 'react';
import { Upload, X } from 'lucide-react';
import { toast } from 'sonner';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { verifierFichierDocument } from '@/lib/documentUpload';

interface ResultatVerif {
  verdict: 'EN_ATTENTE' | 'VALIDE' | 'REJETE';
  heures_extraites?: number | null;
  coherence?: boolean | null;
}

interface Props {
  onSubmit: (payload: {
    etablissement_nom: string;
    etablissement_type?: string;
    date_debut: string;
    date_fin: string;
    heures_declarees: number;
    attestation_file?: File;
  }) => Promise<ResultatVerif | null | void>;
  onCancel: () => void;
  isLoading?: boolean;
}

const TYPES_ETABLISSEMENT = [
  { value: '', label: '— Type (optionnel) —' },
  { value: 'HOPITAL_PUBLIC', label: 'Hôpital public' },
  { value: 'CLINIQUE_PRIVEE', label: 'Clinique privée' },
  { value: 'EHPAD', label: 'EHPAD' },
  { value: 'SSIAD', label: 'SSIAD' },
  { value: 'HAD', label: 'HAD' },
  { value: 'CENTRE_SANTE', label: 'Centre de santé' },
  { value: 'AUTRE', label: 'Autre' },
];

const MAX_SIZE = 10 * 1024 * 1024;
export function FormulaireHeuresExternes({ onSubmit, onCancel, isLoading }: Props) {
  const fileRef = useRef<HTMLInputElement>(null);
  const [etabNom, setEtabNom] = useState('');
  const [etabType, setEtabType] = useState('');
  const [dateDebut, setDateDebut] = useState('');
  const [dateFin, setDateFin] = useState('');
  const [heures, setHeures] = useState('');
  const [file, setFile] = useState<File | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const handleFile = async (f: File | null): Promise<boolean> => {
    if (!f) {
      setFile(null);
      return false;
    }
    const validation = await verifierFichierDocument(f, {
      maxBytes: MAX_SIZE,
      allowedMimes: ['application/pdf', 'image/jpeg', 'image/png'],
    });
    if (validation.ok === false) {
      setFile(null);
      toast.error(validation.message);
      return false;
    }
    setFile(f);
    return true;
  };

  const valid = () => {
    if (!etabNom.trim()) return 'Nom de l\'établissement requis.';
    if (!dateDebut || !dateFin) return 'Dates requises.';
    if (new Date(dateFin) < new Date(dateDebut)) return 'La date de fin doit être après la date de début.';
    const h = Number(heures);
    if (!Number.isFinite(h) || h < 1 || h > 10000) return 'Heures entre 1 et 10 000.';
    if (!file) return 'Attestation requise.';
    return null;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const err = valid();
    if (err) { toast.error(err); return; }

    setSubmitting(true);
    try {
      const res = await onSubmit({
        etablissement_nom: etabNom.trim(),
        etablissement_type: etabType || undefined,
        date_debut: dateDebut,
        date_fin: dateFin,
        heures_declarees: Number(heures),
        attestation_file: file!,
      });
      // L'analyse automatique ne comptabilise jamais les heures : hors rejet
      // concluant, la déclaration attend toujours une validation humaine.
      if (res && res.verdict === 'REJETE') {
        toast.error('❌ Le document fourni ne semble pas être une attestation d\'heures. Vérifie le fichier.');
      } else {
        toast.success('Heures ajoutées. Analyse automatique terminée ou en cours ; validation humaine requise avant comptabilisation.');
      }
      setEtabNom(''); setEtabType(''); setDateDebut(''); setDateFin(''); setHeures(''); setFile(null);
      if (fileRef.current) fileRef.current.value = '';
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : 'Erreur lors de l\'ajout.');
    } finally {
      setSubmitting(false);
    }
  };

  const busy = submitting || isLoading;

  return (
    <form onSubmit={handleSubmit} className="card-base space-y-3">
      <div>
        <label className="text-sm font-medium text-foreground mb-1 block">Nom de l'établissement *</label>
        <input type="text" value={etabNom} onChange={(e) => setEtabNom(e.target.value)} className="input-base" placeholder="CHU de Lyon" required />
      </div>

      <div>
        <label className="text-sm font-medium text-foreground mb-1 block">Type d'établissement</label>
        <select value={etabType} onChange={(e) => setEtabType(e.target.value)} className="input-base">
          {TYPES_ETABLISSEMENT.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
        </select>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <div>
          <label className="text-sm font-medium text-foreground mb-1 block">Date de début *</label>
          <input type="date" value={dateDebut} onChange={(e) => setDateDebut(e.target.value)} className="input-base" required />
        </div>
        <div>
          <label className="text-sm font-medium text-foreground mb-1 block">Date de fin *</label>
          <input type="date" value={dateFin} onChange={(e) => setDateFin(e.target.value)} className="input-base" min={dateDebut || undefined} required />
        </div>
      </div>

      <div>
        <label className="text-sm font-medium text-foreground mb-1 block">Nombre d'heures déclarées *</label>
        <input type="number" value={heures} onChange={(e) => setHeures(e.target.value)} min={1} max={10000} step={1} className="input-base" placeholder="1600" required />
        <p className="text-xs text-muted-foreground mt-1">Une année à temps plein ≈ 1 600h.</p>
      </div>

      <div>
        <label className="text-sm font-medium text-foreground mb-1 block">Attestation *</label>
        <div className="flex items-center gap-2 flex-wrap">
          <input ref={fileRef} type="file" accept="application/pdf,image/jpeg,image/png" onChange={async e => {
            const selected = e.target.files?.[0] ?? null;
            if (!(await handleFile(selected))) e.target.value = '';
          }} className="hidden" id="attestation-file" />
          <BoutonY2K type="button" variant="secondary" onClick={() => fileRef.current?.click()} disabled={busy} className="gap-2" iconeGauche={<Upload className="h-4 w-4" />}>
            {file ? 'Changer le fichier' : 'Choisir un fichier'}
          </BoutonY2K>
          {file && (
            <span className="flex items-center gap-1.5 text-xs text-muted-foreground">
              <span className="truncate max-w-[200px]">{file.name}</span>
              <button type="button" onClick={() => { setFile(null); if (fileRef.current) fileRef.current.value = ''; }} className="hover:text-destructive" aria-label="Retirer">
                <X className="h-3.5 w-3.5" />
              </button>
            </span>
          )}
        </div>
        <p className="text-xs text-muted-foreground mt-1">PDF, JPEG ou PNG — 10 Mo max. L'attestation doit mentionner l'établissement, la période et le nombre d'heures.</p>
      </div>

      <div className="flex gap-2 pt-2">
        <BoutonY2K type="submit" disabled={busy} loading={busy} className="flex-1 gap-2">
          Ajouter ces heures
        </BoutonY2K>
        <BoutonY2K type="button" variant="secondary" onClick={onCancel} disabled={busy} className="flex-1">
          Annuler
        </BoutonY2K>
      </div>
    </form>
  );
}
