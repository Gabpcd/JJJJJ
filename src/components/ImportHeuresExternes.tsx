import { useState } from 'react';
import { Plus, Upload, Loader2, X } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { capturerErreurSentry } from '@/lib/sentry';
import { sanitiserNomFichier, verifierFichierDocument } from '@/lib/documentUpload';

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
    const validation = await verifierFichierDocument(fichier, {
      allowedMimes: ['application/pdf', 'image/jpeg', 'image/png'],
    });
    if (validation.ok === false) {
      afficherNotification({ type: 'erreur', message: validation.message });
      return;
    }
    const heures = Number(form.heures);
    if (!Number.isFinite(heures) || heures < 1 || heures > 10_000) {
      afficherNotification({ type: 'erreur', message: 'Le nombre d’heures doit être compris entre 1 et 10 000.' });
      return;
    }
    if (!form.dateDebut || !form.dateFin || form.dateFin < form.dateDebut) {
      afficherNotification({ type: 'erreur', message: 'La date de fin doit être postérieure ou égale à la date de début.' });
      return;
    }
    setSubmitting(true);

    let documentCreeId: string | null = null;
    let s3Cle: string | null = null;
    try {
      // 1. Upload document
      const sanitizedName = sanitiserNomFichier(fichier.name, validation.mime);
      // Tous les justificatifs d'un soignant restent sous ce préfixe. Il est
      // contrôlé à la fois par Storage, la base et l'Edge Function afin qu'une
      // ligne forgée ne puisse jamais pointer vers le document d'un tiers.
      s3Cle = `${user.id}/documents/${form.typePreuve}/${Date.now()}-${sanitizedName}`;
      const { error: upErr } = await supabase.storage
        .from('jolene-documents')
        .upload(s3Cle, fichier, { contentType: validation.mime, upsert: false });
      if (upErr) throw upErr;

      // Le document, son remplacement éventuel et la déclaration d'heures sont
      // enregistrés dans une transaction unique. Une panne ne peut plus laisser
      // une preuve active orpheline ou une déclaration sans justificatif.
      const { data, error } = await supabase.rpc('fn_declarer_heures_externes_avec_document' as any, {
        p_employeur_nom: form.employeur,
        p_employeur_type: form.typeEmployeur,
        p_date_debut: form.dateDebut,
        p_date_fin: form.dateFin,
        p_heures_declarees: heures,
        p_type_preuve: form.typePreuve,
        p_s3_cle: s3Cle,
        p_nom_fichier: fichier.name,
        p_type_mime: validation.mime,
        p_taille_octets: fichier.size,
      });
      const resultat = data as any;
      if (error || !resultat?.success || !resultat?.document_id) {
        throw error || new Error(resultat?.error_code || 'DECLARATION_INVALIDE');
      }
      documentCreeId = resultat.document_id;

      if (documentCreeId) {
        supabase.functions.invoke('verify-document', {
          body: { document_id: documentCreeId },
        }).catch(() => {});
      }
      afficherNotification({ type: 'succes', message: 'Heures déclarées ! Vérification IA en cours…' });
      setOpen(false);
      setForm({ employeur: '', typeEmployeur: 'Hôpital public', dateDebut: '', dateFin: '', heures: '', typePreuve: 'BULLETIN_PAIE' });
      setFichier(null);
      onDone();
    } catch (err: any) {
      // La RPC est atomique. Si elle a refusé l'écriture, seul le fichier déjà
      // envoyé dans Storage peut rester orphelin : l'Edge Function le supprime
      // après avoir revérifié que son préfixe appartient bien à l'utilisateur.
      if (!documentCreeId && s3Cle) {
        await supabase.functions.invoke('verify-document', {
          body: { action: 'cleanup_orphan', s3_cle: s3Cle },
        });
      }
      capturerErreurSentry(err, 'ImportHeuresExternes', 'soumettre_heures');
      afficherNotification({ type: 'erreur', message: 'Erreur lors de la soumission. Veuillez réessayer.' });
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
            <label htmlFor="heures-externes-employeur" className="text-sm font-medium text-foreground mb-1 block">Employeur *</label>
            <input id="heures-externes-employeur" value={form.employeur} onChange={e => maj('employeur', e.target.value)} className="input-base" required />
          </div>
          <div>
            <label htmlFor="heures-externes-type" className="text-sm font-medium text-foreground mb-1 block">Type</label>
            <select id="heures-externes-type" value={form.typeEmployeur} onChange={e => maj('typeEmployeur', e.target.value)} className="input-base">
              {TYPES_EMPLOYEUR.map(t => <option key={t} value={t}>{t}</option>)}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div><label htmlFor="heures-externes-date-debut" className="text-sm font-medium text-foreground mb-1 block">Du *</label><input id="heures-externes-date-debut" type="date" value={form.dateDebut} onChange={e => maj('dateDebut', e.target.value)} className="input-base" required /></div>
            <div><label htmlFor="heures-externes-date-fin" className="text-sm font-medium text-foreground mb-1 block">Au *</label><input id="heures-externes-date-fin" type="date" value={form.dateFin} onChange={e => maj('dateFin', e.target.value)} className="input-base" required /></div>
          </div>
          <div>
            <label htmlFor="heures-externes-heures" className="text-sm font-medium text-foreground mb-1 block">Heures déclarées *</label>
            <input id="heures-externes-heures" type="number" min="1" step="0.5" value={form.heures} onChange={e => maj('heures', e.target.value)} className="input-base" required />
          </div>
          <div>
            <label htmlFor="heures-externes-type-preuve" className="text-sm font-medium text-foreground mb-1 block">Type de justificatif</label>
            <select id="heures-externes-type-preuve" value={form.typePreuve} onChange={e => maj('typePreuve', e.target.value)} className="input-base">
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
              <input type="file" accept="application/pdf,image/jpeg,image/png" onChange={async e => {
                const selected = e.target.files?.[0] || null;
                if (!selected) { setFichier(null); return; }
                const validation = await verifierFichierDocument(selected, {
                  allowedMimes: ['application/pdf', 'image/jpeg', 'image/png'],
                });
                if (validation.ok === false) {
                  setFichier(null);
                  afficherNotification({ type: 'erreur', message: validation.message });
                  e.target.value = '';
                  return;
                }
                setFichier(selected);
              }} className="hidden" required />
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
