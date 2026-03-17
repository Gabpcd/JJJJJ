import { useState } from 'react';
import { Plus, Upload, Loader2, X } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';

interface ImportHeuresExternesProps {
  onDone: () => void;
}

const TYPES_EMPLOYEUR = ['Hôpital public', 'Clinique privée', 'EHPAD', 'Agence de staffing', 'Autre'];
const TYPES_PREUVE = ['BULLETIN_PAIE', 'ATTESTATION_EMPLOYEUR', 'CERTIFICAT_TRAVAIL'];

export default function ImportHeuresExternes({ onDone }: ImportHeuresExternesProps) {
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [open, setOpen] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [form, setForm] = useState({
    employeur: '', typeEmployeur: 'Hôpital public',
    dateDebut: '', dateFin: '', heures: '',
    typePreuve: 'BULLETIN_PAIE',
  });
  const [fichier, setFichier] = useState<File | null>(null);

  const maj = (k: string, v: string) => setForm(prev => ({ ...prev, [k]: v }));

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user || !fichier) return;
    setSubmitting(true);

    try {
      // 1. Upload document
      const ext = fichier.name.split('.').pop();
      const s3Cle = `heures_externes/${user.id}/${Date.now()}.${ext}`;
      const { error: upErr } = await supabase.storage.from('jolene-documents').upload(s3Cle, fichier);
      if (upErr) throw upErr;

      // 2. Create document entry
      const { data: doc, error: docErr } = await supabase.from('documents_soignants').insert({
        soignant_id: user.id,
        type_document: form.typePreuve as any,
        nom_fichier: fichier.name,
        s3_cle: s3Cle,
        s3_bucket: 'soin-direct-documents',
        taille_octets: fichier.size,
        type_mime: fichier.type,
        statut_verification: 'EN_ATTENTE',
      } as any).select('id').single();
      if (docErr) throw docErr;

      // 3. Insert heures_externes
      const { error: heErr } = await supabase.from('heures_externes').insert({
        soignant_id: user.id,
        employeur_nom: form.employeur,
        employeur_type: form.typeEmployeur,
        date_debut: form.dateDebut,
        date_fin: form.dateFin,
        heures_declarees: parseFloat(form.heures),
        document_id: doc!.id,
        type_preuve: form.typePreuve,
        statut: 'EN_ATTENTE',
      });
      if (heErr) throw heErr;

      // 4. Audit
      await supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user.id, p_type_acteur: 'SOIGNANT',
        p_action: 'HEURES_EXTERNES_DECLAREES',
        p_type_ressource: 'soignant', p_id_ressource: user.id,
        p_cle_s3: s3Cle,
        p_details: { employeur: form.employeur, heures: parseFloat(form.heures), periode: `${form.dateDebut} - ${form.dateFin}` },
        p_ip: null, p_navigateur: navigator.userAgent,
      });

      afficherNotification({ type: 'succes', message: 'Heures déclarées ! Elles seront vérifiées par notre équipe.' });
      setOpen(false);
      setForm({ employeur: '', typeEmployeur: 'Hôpital public', dateDebut: '', dateFin: '', heures: '', typePreuve: 'BULLETIN_PAIE' });
      setFichier(null);
      onDone();
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: err.message || 'Erreur lors de la soumission' });
    } finally {
      setSubmitting(false);
    }
  };

  if (!open) {
    return (
      <button onClick={() => setOpen(true)} className="btn-secondary text-sm flex items-center gap-2">
        <Plus className="h-4 w-4" /> Déclarer des heures externes
      </button>
    );
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-foreground/30 p-4">
      <div className="bg-card rounded-2xl shadow-2xl max-w-lg w-full max-h-[90vh] overflow-y-auto p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-base font-bold text-foreground">Déclarer des heures externes</h3>
          <button onClick={() => setOpen(false)} className="text-muted-foreground hover:text-foreground"><X className="h-5 w-5" /></button>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="text-sm font-medium text-foreground mb-1 block">Employeur *</label>
            <input value={form.employeur} onChange={e => maj('employeur', e.target.value)} className="input-base" required />
          </div>
          <div>
            <label className="text-sm font-medium text-foreground mb-1 block">Type</label>
            <select value={form.typeEmployeur} onChange={e => maj('typeEmployeur', e.target.value)} className="input-base">
              {TYPES_EMPLOYEUR.map(t => <option key={t} value={t}>{t}</option>)}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div><label className="text-sm font-medium text-foreground mb-1 block">Du *</label><input type="date" value={form.dateDebut} onChange={e => maj('dateDebut', e.target.value)} className="input-base" required /></div>
            <div><label className="text-sm font-medium text-foreground mb-1 block">Au *</label><input type="date" value={form.dateFin} onChange={e => maj('dateFin', e.target.value)} className="input-base" required /></div>
          </div>
          <div>
            <label className="text-sm font-medium text-foreground mb-1 block">Heures déclarées *</label>
            <input type="number" min="1" step="0.5" value={form.heures} onChange={e => maj('heures', e.target.value)} className="input-base" required />
          </div>
          <div>
            <label className="text-sm font-medium text-foreground mb-1 block">Type de justificatif</label>
            <select value={form.typePreuve} onChange={e => maj('typePreuve', e.target.value)} className="input-base">
              <option value="BULLETIN_PAIE">Bulletin de paie</option>
              <option value="ATTESTATION_EMPLOYEUR">Attestation employeur</option>
              <option value="CERTIFICAT_TRAVAIL">Certificat de travail</option>
            </select>
          </div>
          <div>
            <label className="text-sm font-medium text-foreground mb-1 block">Document justificatif *</label>
            <label className="flex items-center gap-2 cursor-pointer border-2 border-dashed border-border rounded-lg p-3 hover:bg-accent/30 transition-colors">
              <Upload className="h-4 w-4 text-muted-foreground" />
              <span className="text-sm text-muted-foreground">{fichier ? fichier.name : 'Téléverser le document'}</span>
              <input type="file" accept=".pdf,.jpg,.jpeg,.png" onChange={e => setFichier(e.target.files?.[0] || null)} className="hidden" required />
            </label>
          </div>

          <div className="bg-warning/10 border border-warning/30 rounded-lg p-3">
            <p className="text-xs text-warning">⚠️ Ces heures seront vérifiées par notre équipe. Statut : En attente de validation</p>
          </div>

          <button type="submit" disabled={submitting || !form.employeur || !form.heures || !fichier} className="btn-primary w-full disabled:opacity-50">
            {submitting ? <Loader2 className="h-4 w-4 animate-spin mx-auto" /> : 'Soumettre'}
          </button>
        </form>
      </div>
    </div>
  );
}
