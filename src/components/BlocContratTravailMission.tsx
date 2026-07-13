import { useEffect, useState } from 'react';
import { FileText, Upload, Download, AlertTriangle, CheckCircle, RefreshCw } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { verifierFichierDocument } from '@/lib/documentUpload';
import { toast } from 'sonner';

interface Props {
  missionId: string;
  typeContratApplique: string | null;
  soignantAssigneId: string | null;
  etablissementId: string;
  debutLe: string | null;
  role: 'ETABLISSEMENT' | 'SOIGNANT';
}

interface ContratTravail {
  id: string;
  pdf_s3_key: string;
  nom_fichier: string | null;
  taille_octets: number | null;
  uploaded_at: string;
  uploaded_by: string;
}

const BUCKET = 'jolene-documents';

export function BlocContratTravailMission({
  missionId,
  typeContratApplique,
  soignantAssigneId,
  etablissementId,
  debutLe,
  role,
}: Props) {
  const { user } = useAuth();
  const [contrat, setContrat] = useState<ContratTravail | null>(null);
  const [loading, setLoading] = useState(true);
  const [uploading, setUploading] = useState(false);
  const [downloading, setDownloading] = useState(false);
  const [file, setFile] = useState<File | null>(null);
  const [showUpload, setShowUpload] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      const { data } = await supabase
        .from('contrats_travail_missions' as any)
        .select('id, pdf_s3_key, nom_fichier, taille_octets, uploaded_at, uploaded_by')
        .eq('mission_id', missionId)
        .maybeSingle();
      if (!cancelled) {
        setContrat((data as any) || null);
        setLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, [missionId]);

  // Conditions affichage
  if (typeContratApplique !== 'SALARIE' || !soignantAssigneId) return null;
  if (loading) return null;

  const upload = async () => {
    if (!file || !user) return;
    const validation = await verifierFichierDocument(file, {
      allowedMimes: ['application/pdf'],
    });
    if (validation.ok === false) {
      toast.error(validation.message);
      return;
    }

    setUploading(true);
    try {
      // Le premier segment doit être l'établissement propriétaire. Une clé
      // unique rend le remplacement compatible avec les preuves immuables.
      const path = `${etablissementId}/contrats-travail/${missionId}/${Date.now()}-${globalThis.crypto.randomUUID()}-contrat.pdf`;
      const { error: upErr } = await supabase.storage
        .from(BUCKET)
        .upload(path, file, { upsert: false, contentType: validation.mime });
      if (upErr) throw upErr;

      // Upsert row contrats_travail_missions + audit via RPC unifiée
      const wasReplace = !!contrat;
      const ancienPath = contrat?.pdf_s3_key ?? null;
      const { data: rpcData, error: rpcErr } = await supabase.rpc('fn_uploader_contrat_travail_mission', {
        p_mission_id: missionId,
        p_pdf_s3_key: path,
        p_nom_fichier: file.name,
        p_taille_octets: file.size,
      });
      const rpcErreur = rpcData && typeof rpcData === 'object' && !Array.isArray(rpcData) && 'error' in rpcData
        ? String((rpcData as { error?: unknown }).error || '')
        : '';
      if (rpcErr || rpcErreur) {
        // Le stockage est immuable : seul le service peut retirer cet objet
        // qui n'a finalement été rattaché à aucune ligne métier.
        await supabase.functions.invoke('verify-contrat-travail', {
          body: { mission_id: missionId, action: 'cleanup_orphan', pdf_s3_key: path },
        });
        if (rpcErr) throw rpcErr;
        throw new Error(rpcErreur);
      }

      if (ancienPath && ancienPath !== path) {
        // Après remplacement, l'ancienne clé n'est plus référencée.
        // Le nettoyage est idempotent et refuse toute clé encore active.
        void supabase.functions.invoke('verify-contrat-travail', {
          body: { mission_id: missionId, action: 'cleanup_orphan', pdf_s3_key: ancienPath },
        });
      }

      // Vérification IA du contrat de travail (type + parties), à l'upload ET au
      // remplacement. Fire-and-forget : résultat écrit côté contrats_travail_missions.
      supabase.functions.invoke('verify-contrat-travail', {
        body: { mission_id: missionId },
      }).catch(() => { /* best-effort */ });

      if (wasReplace) {
        toast.success('Contrat de travail remplacé');
      } else {

        // Notification + email soignant (best-effort)
        try {
          await supabase.from('notifications').insert({
            destinataire_id: soignantAssigneId,
            type_destinataire: 'SOIGNANT',
            type: 'CONTRAT_GENERE',
            titre: 'Contrat de travail déposé',
            corps: 'Votre établissement a déposé votre contrat de travail pour cette mission.',
            type_ressource: 'mission',
            id_ressource: missionId,
            lien: `/soignant/missions/${missionId}`,
          });
        } catch (e) { /* best-effort */ }

        try {
          await supabase.functions.invoke('send-email', {
            body: {
              type: 'CONTRAT_TRAVAIL_DEPOSE',
              destinataire_id: soignantAssigneId,
              data: { mission_id: missionId, lien: `https://jolene.app/soignant/missions/${missionId}` },
            },
          });
        } catch (e) { /* best-effort */ }

        toast.success('Contrat de travail déposé. Le soignant a été notifié.');
      }

      // Refresh
      const { data } = await supabase
        .from('contrats_travail_missions' as any)
        .select('id, pdf_s3_key, nom_fichier, taille_octets, uploaded_at, uploaded_by')
        .eq('mission_id', missionId)
        .maybeSingle();
      setContrat((data as any) || null);
      setFile(null);
      setShowUpload(false);
    } catch (err: any) {
      toast.error(err?.message || 'Erreur upload');
    } finally {
      setUploading(false);
    }
  };

  const download = async () => {
    if (!contrat) return;
    setDownloading(true);
    try {
      // Le soignant n'est pas propriétaire du préfixe Storage de
      // l'établissement. L'Edge Function vérifie la relation mission puis crée
      // une URL courte côté service, sans élargir la politique du bucket.
      const { data, error } = await supabase.functions.invoke('verify-contrat-travail', {
        body: { mission_id: missionId, action: 'signed_url' },
      });
      if (error) throw error;
      if (!data?.signed_url) throw new Error('Lien de téléchargement indisponible');
      window.open(data.signed_url, '_blank', 'noopener,noreferrer');
    } catch (err: any) {
      toast.error(err?.message || 'Erreur téléchargement');
    } finally {
      setDownloading(false);
    }
  };

  // Cas SOIGNANT : pas de contrat uploadé
  if (!contrat && role === 'SOIGNANT') {
    if (!debutLe) return null;
    const debut = new Date(debutLe);
    const now = new Date();
    const msUntilStart = debut.getTime() - now.getTime();
    const oneDayMs = 24 * 60 * 60 * 1000;
    if (msUntilStart > oneDayMs) return null; // Pas d'alerte si > J-1
    return (
      <div className="rounded-xl border-2 border-warning/40 bg-warning/10 p-4 flex items-start gap-3">
        <AlertTriangle className="h-5 w-5 text-warning shrink-0 mt-0.5" />
        <div className="flex-1">
          <p className="font-semibold text-foreground">Contrat de travail manquant</p>
          <p className="text-sm text-muted-foreground mt-1">
            Votre établissement n'a pas encore déposé votre contrat de travail. Vous pouvez le contacter pour le rappeler.
          </p>
        </div>
      </div>
    );
  }

  // Cas SOIGNANT avec contrat uploadé
  if (contrat && role === 'SOIGNANT') {
    return (
      <div className="rounded-xl border border-success/30 bg-success/5 p-4 space-y-2">
        <div className="flex items-center gap-2">
          <CheckCircle className="h-5 w-5 text-success" />
          <p className="font-semibold text-foreground">Mon contrat de travail</p>
        </div>
        <p className="text-xs text-muted-foreground">
          Déposé le {new Date(contrat.uploaded_at).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' })}
          {contrat.taille_octets ? ` · ${(contrat.taille_octets / 1024).toFixed(0)} Ko` : ''}
        </p>
        <BoutonY2K size="sm" variant="secondary" onClick={download} disabled={downloading} loading={downloading} className="gap-2" iconeGauche={downloading ? undefined : <Download className="h-4 w-4" />}>
          Télécharger
        </BoutonY2K>
      </div>
    );
  }

  // Cas ETABLISSEMENT : aucun contrat → prompt upload
  if (!contrat && role === 'ETABLISSEMENT') {
    return (
      <div className="rounded-xl border-2 border-primary/30 bg-primary/5 p-4 space-y-3">
        <div className="flex items-start gap-3">
          <FileText className="h-5 w-5 text-primary shrink-0 mt-0.5" />
          <div className="flex-1">
            <p className="font-semibold text-foreground">Contrat de travail à déposer</p>
            <p className="text-sm text-muted-foreground mt-1">
              Vous êtes employeur du soignant pour cette mission salariée. Déposez le contrat de travail CDD signé par les deux parties au plus tard le premier jour de mission. Format PDF, max 10 Mo.
            </p>
          </div>
        </div>
        <div className="flex flex-col sm:flex-row gap-2">
          <input
            type="file"
            accept=".pdf,application/pdf"
            onChange={async e => {
              const selected = e.target.files?.[0] || null;
              if (!selected) { setFile(null); return; }
              const validation = await verifierFichierDocument(selected, { allowedMimes: ['application/pdf'] });
              if (validation.ok === false) { setFile(null); toast.error(validation.message); e.target.value = ''; return; }
              setFile(selected);
            }}
            className="block w-full text-sm text-foreground file:mr-4 file:py-2 file:px-4 file:rounded-lg file:border-0 file:text-sm file:font-medium file:bg-primary/10 file:text-primary hover:file:bg-primary/20 cursor-pointer"
          />
          <BoutonY2K onClick={upload} disabled={!file || uploading} loading={uploading} className="gap-2 shrink-0" iconeGauche={uploading ? undefined : <Upload className="h-4 w-4" />}>
            Déposer
          </BoutonY2K>
        </div>
        {file && (
          <p className="text-xs text-muted-foreground">
            {file.name} ({(file.size / 1024).toFixed(0)} Ko)
          </p>
        )}
      </div>
    );
  }

  // Cas ETABLISSEMENT avec contrat uploadé
  if (contrat && role === 'ETABLISSEMENT') {
    return (
      <div className="rounded-xl border border-success/30 bg-success/5 p-4 space-y-3">
        <div className="flex items-center gap-2">
          <CheckCircle className="h-5 w-5 text-success" />
          <p className="font-semibold text-foreground">Contrat de travail déposé</p>
        </div>
        <p className="text-xs text-muted-foreground">
          Déposé le {new Date(contrat.uploaded_at).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' })}
          {contrat.taille_octets ? ` · ${(contrat.taille_octets / 1024).toFixed(0)} Ko` : ''}
          {contrat.nom_fichier ? ` · ${contrat.nom_fichier}` : ''}
        </p>
        <div className="flex flex-wrap gap-2">
          <BoutonY2K size="sm" variant="secondary" onClick={download} disabled={downloading} loading={downloading} className="gap-2" iconeGauche={downloading ? undefined : <Download className="h-4 w-4" />}>
            Télécharger
          </BoutonY2K>
          <BoutonY2K size="sm" variant="secondary" onClick={() => setShowUpload(s => !s)} className="gap-2" iconeGauche={<RefreshCw className="h-4 w-4" />}>
            {showUpload ? 'Annuler' : 'Remplacer'}
          </BoutonY2K>
        </div>
        {showUpload && (
          <div className="pt-2 border-t border-border space-y-2">
            <input
              type="file"
              accept=".pdf,application/pdf"
              onChange={async e => {
                const selected = e.target.files?.[0] || null;
                if (!selected) { setFile(null); return; }
                const validation = await verifierFichierDocument(selected, { allowedMimes: ['application/pdf'] });
                if (validation.ok === false) { setFile(null); toast.error(validation.message); e.target.value = ''; return; }
                setFile(selected);
              }}
              className="block w-full text-sm text-foreground file:mr-4 file:py-2 file:px-4 file:rounded-lg file:border-0 file:text-sm file:font-medium file:bg-primary/10 file:text-primary hover:file:bg-primary/20 cursor-pointer"
            />
            <BoutonY2K onClick={upload} disabled={!file || uploading} loading={uploading} size="sm" className="gap-2" iconeGauche={uploading ? undefined : <Upload className="h-4 w-4" />}>
              Remplacer
            </BoutonY2K>
          </div>
        )}
      </div>
    );
  }

  return null;
}
