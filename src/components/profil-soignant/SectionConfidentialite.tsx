import { useState } from 'react';
import { telechargerOuPartager } from '@/lib/telechargement';
import { useNavigate } from 'react-router-dom';
import { Download, Trash2, Shield, UserX } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { useRole } from '@/hooks/useRole';
import { capturerErreurSentry } from '@/lib/sentry';
import { extraireMessageErreur } from '@/lib/erreurs';

interface Props {
  userId: string;
}

interface DeleteAccountResponse {
  success?: boolean;
  error?: string;
}

export function SectionConfidentialite({ userId }: Props) {
  const { afficherNotification } = useNotification();
  const { role } = useRole();
  const navigate = useNavigate();
  const [exportLoading, setExportLoading] = useState(false);
  const [showDeleteModal, setShowDeleteModal] = useState(false);
  const [deleteConfirmText, setDeleteConfirmText] = useState('');
  const [deleteLoading, setDeleteLoading] = useState(false);

  const handleExportRGPD = async (fmt: 'json' | 'csv') => {
    setExportLoading(true);
    try {
      const { data, error } = await supabase.rpc('fn_rgpd_exporter_rate_limited' as any);
      if (error) throw error;
      // La RPC renvoie {error} en cas de rate-limit (2 exports/24h) ou d'échec :
      // afficher le message au lieu d'exporter un fichier contenant l'erreur.
      if (data && typeof data === 'object' && (data as any).error) {
        afficherNotification({ type: 'erreur', message: (data as any).error });
        setExportLoading(false);
        return;
      }
      await supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: userId, p_type_acteur: role || 'SOIGNANT',
        p_action: 'RGPD_EXPORT_DONNEES',
        p_type_ressource: 'soignant', p_id_ressource: userId,
        p_cle_s3: null, p_details: { format: fmt },
        p_ip: null, p_navigateur: navigator.userAgent,
      });

      let contenu: string;
      let mime: string;
      let filename: string;
      if (fmt === 'csv') {
        const rows: string[][] = [];
        const flatten = (obj: any, prefix = '') => {
          for (const [k, v] of Object.entries(obj || {})) {
            const key = prefix ? `${prefix}.${k}` : k;
            if (Array.isArray(v)) rows.push([key, JSON.stringify(v)]);
            else if (typeof v === 'object' && v !== null) flatten(v, key);
            else rows.push([key, String(v ?? '')]);
          }
        };
        flatten(data);
        contenu = 'Champ,Valeur\n' + rows.map((r) => r.map((c) => `"${String(c).replace(/"/g, '""')}"`).join(',')).join('\n');
        mime = 'text/csv';
        filename = `mes-donnees-jolene-${new Date().toISOString().slice(0, 10)}.csv`;
      } else {
        contenu = JSON.stringify(data, null, 2);
        mime = 'application/json';
        filename = `mes-donnees-jolene-${new Date().toISOString().slice(0, 10)}.json`;
      }
      await telechargerOuPartager(contenu, filename, mime);
      afficherNotification({ type: 'succes', message: `Données exportées en ${fmt.toUpperCase()}.` });
    } catch (err: any) {
      capturerErreurSentry(err, 'SectionConfidentialite', 'export_rgpd');
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(err) });
    }
    setExportLoading(false);
  };

  const handleSupprimerCompte = async () => {
    setDeleteLoading(true);
    try {
      const { data, error } = await supabase.functions.invoke<DeleteAccountResponse>('delete-account', { body: {} });
      if (error) throw error;
      if (data?.error || data?.success !== true) {
        afficherNotification({ type: 'erreur', message: data?.error || 'Suppression impossible.' });
        setDeleteLoading(false);
        return;
      }
      afficherNotification({ type: 'succes', message: 'Compte supprimé. Redirection...' });
      // La fonction a deja revoque les sessions et supprime logiquement le
      // compte Auth. Cet appel efface la copie locale, meme si le JWT est deja
      // invalide cote serveur.
      await supabase.auth.signOut({ scope: 'local' });
      navigate('/');
    } catch (err: unknown) {
      capturerErreurSentry(err, 'SectionConfidentialite', 'supprimer_compte');
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(err) });
    }
    setDeleteLoading(false);
    setShowDeleteModal(false);
  };

  return (
    <div className="space-y-4">
      <div className="card-base">
        <h2 className="text-base font-semibold text-foreground mb-2 flex items-center gap-2">
          <Shield className="h-4 w-4 text-primary" /> Mes données (RGPD)
        </h2>
        <p className="text-xs text-muted-foreground mb-4">
          Télécharge l'intégralité de tes données personnelles dans le format de ton choix.
        </p>
        <div className="flex flex-wrap gap-3">
          <button
            onClick={() => handleExportRGPD('json')}
            disabled={exportLoading}
            className="btn-secondary text-sm py-2 px-3 flex items-center gap-2 disabled:opacity-50"
          >
            <Download className="h-4 w-4" />
            {exportLoading ? 'Export…' : 'Exporter JSON'}
          </button>
          <button
            onClick={() => handleExportRGPD('csv')}
            disabled={exportLoading}
            className="btn-secondary text-sm py-2 px-3 flex items-center gap-2 disabled:opacity-50"
          >
            <Download className="h-4 w-4" />
            {exportLoading ? 'Export…' : 'Exporter CSV'}
          </button>
        </div>
      </div>

      <div className="card-base">
        <h2 className="text-base font-semibold text-foreground mb-2 flex items-center gap-2">
          <UserX className="h-4 w-4 text-muted-foreground" /> Exclusions établissements
        </h2>
        <p className="text-xs text-muted-foreground mb-3">
          Liste des établissements t'ayant exclu de leurs missions.
        </p>
        <button
          onClick={() => navigate('/soignant/exclusions')}
          className="btn-secondary text-sm py-2 px-3"
        >
          Voir mes exclusions →
        </button>
      </div>

      <div id="suppression-compte" className="card-base scroll-mt-24 border-destructive/30">
        <h2 className="text-base font-semibold text-destructive mb-2">
          Suppression de compte
        </h2>
        <p className="text-xs text-muted-foreground mb-3">
          La suppression de ton compte est irréversible. Tes données seront anonymisées conformément au RGPD.
        </p>
        <button
          onClick={() => setShowDeleteModal(true)}
          className="flex items-center gap-2 text-sm text-destructive hover:text-destructive/80 transition"
        >
          <Trash2 className="h-4 w-4" /> Supprimer mon compte
        </button>
      </div>

      {showDeleteModal && (
        <div className="fixed inset-0 z-[9999] flex items-center justify-center">
          <div className="absolute inset-0 bg-foreground/50 backdrop-blur-sm" onClick={() => setShowDeleteModal(false)} />
          <div className="relative bg-card rounded-2xl shadow-xl p-6 mx-4 max-w-md w-full">
            <h3 className="text-lg font-bold text-destructive mb-2">🗑️ Supprimer mon compte</h3>
            <p className="text-sm text-muted-foreground mb-4">
              Cette action est irréversible. Tes données seront anonymisées conformément au RGPD. Tape <strong>SUPPRIMER</strong> pour confirmer.
            </p>
            <input
              value={deleteConfirmText}
              onChange={(e) => setDeleteConfirmText(e.target.value)}
              placeholder="Tape SUPPRIMER"
              className="input-base mb-4"
            />
            <div className="flex gap-3 justify-end">
              <button
                onClick={() => { setShowDeleteModal(false); setDeleteConfirmText(''); }}
                className="btn-secondary text-sm px-4 py-2"
              >
                Annuler
              </button>
              <button
                onClick={handleSupprimerCompte}
                disabled={deleteConfirmText !== 'SUPPRIMER' || deleteLoading}
                className="btn-danger text-sm px-4 py-2 disabled:opacity-50"
              >
                {deleteLoading ? 'Suppression…' : 'Supprimer définitivement'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
