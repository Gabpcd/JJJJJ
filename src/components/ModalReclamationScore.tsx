import React, { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { Loader2, Upload, X } from 'lucide-react';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Textarea } from '@/components/ui/textarea';

const MOTIFS = [
  { value: 'ARRET_MALADIE', label: 'Arrêt maladie' },
  { value: 'ACCIDENT', label: 'Accident' },
  { value: 'URGENCE_FAMILIALE', label: 'Urgence familiale' },
  { value: 'ERREUR_ETABLISSEMENT', label: 'Erreur de l\'établissement' },
  { value: 'AUTRE', label: 'Autre' },
];

interface Props {
  onClose: () => void;
  onSuccess: () => void;
}

export function ModalReclamationScore({ onClose, onSuccess }: Props) {
  const { user } = useAuth();
  const [missions, setMissions] = useState<any[]>([]);
  const [missionId, setMissionId] = useState('');
  const [motif, setMotif] = useState('');
  const [details, setDetails] = useState('');
  const [fichier, setFichier] = useState<File | null>(null);
  const [saving, setSaving] = useState(false);
  const [erreur, setErreur] = useState('');

  useEffect(() => {
    if (!user) return;
    // Load missions where score may have dropped (terminated missions)
    supabase.from('missions')
      .select('id, intitule, debut_le')
      .eq('soignant_assigne_id', user.id)
      .in('statut', ['TERMINEE', 'ANNULEE_PAR_ETABLISSEMENT', 'ANNULEE_PAR_SOIGNANT', 'ABSENCE'])
      .order('debut_le', { ascending: false })
      .limit(20)
      .then(({ data }) => {
        if (data) setMissions(data as any);
      });
  }, [user]);

  const handleSubmit = async () => {
    if (!motif) { setErreur('Sélectionnez un motif.'); return; }
    if (!details.trim()) { setErreur('Ajoutez des détails.'); return; }

    setSaving(true);
    setErreur('');

    let justificatifCle: string | null = null;
    let justificatifNom: string | null = null;

    // Upload justificatif if present
    if (fichier) {
      const ext = fichier.name.split('.').pop();
      const path = `${user!.id}/reclamations/${Date.now()}.${ext}`;
      const { error: upErr } = await supabase.storage.from('jolene-documents').upload(path, fichier);
      if (upErr) {
        setErreur('Erreur lors de l\'upload du justificatif. Veuillez réessayer.');
        setSaving(false);
        return;
      }
      justificatifCle = path;
      justificatifNom = fichier.name;
    }

    const { error } = await supabase.from('reclamations_scoring').insert({
      soignant_id: user!.id,
      mission_id: missionId || null,
      motif,
      details: details.trim(),
      justificatif_s3_cle: justificatifCle,
      justificatif_nom_fichier: justificatifNom,
    } as any);

    if (error) {
      setErreur('Erreur lors de l\'envoi de la réclamation. Veuillez réessayer.');
    } else {
      onSuccess();
    }
    setSaving(false);
  };

  return (
    <div className="fixed inset-0 z-[9999] flex items-center justify-center">
      <div className="absolute inset-0 bg-foreground/50 backdrop-blur-sm" onClick={onClose} />
      <div className="relative bg-card rounded-2xl shadow-xl p-6 mx-4 max-w-lg w-full space-y-4 max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between">
          <h3 className="text-lg font-bold text-foreground">⚖️ Contester une pénalité</h3>
          <button onClick={onClose} className="p-1 hover:bg-muted rounded-lg"><X className="h-5 w-5" /></button>
        </div>

        <div>
          <label className="text-sm font-medium text-foreground mb-1.5 block">Mission concernée (optionnel)</label>
          <Select value={missionId} onValueChange={setMissionId}>
            <SelectTrigger><SelectValue placeholder="Sélectionner une mission" /></SelectTrigger>
            <SelectContent>
              {missions.map(m => (
                <SelectItem key={m.id} value={m.id}>
                  {m.intitule} — {new Date(m.debut_le).toLocaleDateString('fr-FR')}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>

        <div>
          <label className="text-sm font-medium text-foreground mb-1.5 block">Motif de contestation</label>
          <Select value={motif} onValueChange={setMotif}>
            <SelectTrigger><SelectValue placeholder="Sélectionner un motif" /></SelectTrigger>
            <SelectContent>
              {MOTIFS.map(m => (
                <SelectItem key={m.value} value={m.value}>{m.label}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>

        <div>
          <label className="text-sm font-medium text-foreground mb-1.5 block">Détails</label>
          <Textarea
            value={details}
            onChange={e => setDetails(e.target.value)}
            placeholder="Expliquez les circonstances..."
            className="min-h-[100px]"
          />
        </div>

        <div>
          <label className="text-sm font-medium text-foreground mb-1.5 block">Justificatif (PDF, image)</label>
          {fichier ? (
            <div className="flex items-center gap-2 p-2 bg-muted rounded-lg">
              <span className="text-sm text-foreground flex-1 truncate">{fichier.name}</span>
              <button onClick={() => setFichier(null)} className="text-destructive"><X className="h-4 w-4" /></button>
            </div>
          ) : (
            <label className="flex items-center justify-center gap-2 p-4 border-2 border-dashed border-border rounded-xl cursor-pointer hover:bg-muted/50 transition">
              <Upload className="h-4 w-4 text-muted-foreground" />
              <span className="text-sm text-muted-foreground">Choisir un fichier</span>
              <input type="file" accept=".pdf,.jpg,.jpeg,.png" className="hidden" onChange={e => setFichier(e.target.files?.[0] || null)} />
            </label>
          )}
        </div>

        {erreur && <p className="text-sm text-destructive">{erreur}</p>}

        <div className="flex gap-3 pt-2">
          <button onClick={onClose} className="flex-1 btn-secondary text-sm py-2.5">Annuler</button>
          <button
            onClick={handleSubmit}
            disabled={saving}
            className="flex-1 btn-primary text-sm py-2.5 disabled:opacity-50 flex items-center justify-center gap-2"
          >
            {saving ? <><Loader2 className="h-4 w-4 animate-spin" /> Envoi…</> : '📩 Soumettre la réclamation'}
          </button>
        </div>
      </div>
    </div>
  );
}
