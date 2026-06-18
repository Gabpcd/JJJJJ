import React, { useState, useEffect, useRef } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';
import { supabase } from '@/integrations/supabase/client';
import { capturerErreurSentry } from '@/lib/sentry';
import { FileText, Upload, CheckCircle, Clock, Download, ExternalLink, Loader2, RefreshCw, AlertTriangle, X } from 'lucide-react';
import {
  CardY2K,
  CardY2KHeader,
  CardY2KTitle,
  CardY2KContent,
} from '@/components/y2k/CardY2K';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { Textarea } from '@/components/ui/textarea';
import { toast } from 'sonner';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface ContratInfo {
  contrat_valide: boolean;
  contrat_url: string | null;
  contrat_uploade_le: string | null;
  nom: string;
  siret: string;
  taux_commission_negocie: number;
}

export default function ContratPlateforme() {
  usePageTitle('Contrat plateforme');
  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <ContratPlateformeContent />
    </LayoutApp>
  );
}

export function ContratPlateformeContent() {
  const { user, etablissementId } = useEtablissementScope();
  const [contrat, setContrat] = useState<ContratInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const [uploading, setUploading] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);

  // Task 11 — résiliation
  const [showResilierModal, setShowResilierModal] = useState(false);
  const [resilierMotif, setResilierMotif] = useState('');
  const [resilierLoading, setResilierLoading] = useState(false);

  const charger = async () => {
    if (!user || !etablissementId) return;
    try {
      const { data, error } = await supabase.rpc('fn_mon_contrat_plateforme' as any);
      if (error) throw error;
      if (data) setContrat(data as any);
    } catch (err) {
      capturerErreurSentry(err, 'ContratPlateforme', 'charger');
      toast.error('Impossible de charger les informations du contrat.');
    }
    setLoading(false);
  };

  useEffect(() => { charger(); }, [user, etablissementId]);

  const handleUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file || !user || !etablissementId) return;

    if (file.type !== 'application/pdf') {
      toast.error('Seuls les fichiers PDF sont acceptés.');
      return;
    }
    if (file.size > 10 * 1024 * 1024) {
      toast.error('Le fichier ne doit pas dépasser 10 Mo.');
      return;
    }

    setUploading(true);
    try {
      const path = `${etablissementId}/contrats-plateforme/contrat_${Date.now()}.pdf`;
      const { error: uploadError } = await supabase.storage
        .from('jolene-documents')
        .upload(path, file, { upsert: true, contentType: 'application/pdf' });
      if (uploadError) throw uploadError;

      const { data: rpcData, error: rpcError } = await supabase.rpc('fn_uploader_contrat_plateforme' as any, {
        p_contrat_url: path,
      });
      if (rpcError) throw rpcError;
      if ((rpcData as any)?.error) throw new Error((rpcData as any).error);

      // Vérification IA réelle du contrat (type + SIRET + identité signataire),
      // fire-and-forget : le résultat est écrit côté établissement + revue admin.
      supabase.functions.invoke('verify-contrat-etablissement', {
        body: { etablissement_id: etablissementId },
      }).catch(() => { /* best-effort, l'admin valide aussi manuellement */ });

      toast.success('Contrat téléversé — vérification automatique en cours.');
      await charger();
    } catch (err) {
      capturerErreurSentry(err, 'ContratPlateforme', 'upload');
      const msg = (err as any)?.message || (err as any)?.error_description || '';
      toast.error(msg ? `Échec du téléversement : ${msg}` : 'Une erreur est survenue lors du téléversement.');
    }
    setUploading(false);
    if (fileRef.current) fileRef.current.value = '';
  };

  const telechargerContrat = async () => {
    if (!contrat?.contrat_url) return;
    try {
      const { data } = await supabase.storage.from('jolene-documents').createSignedUrl(contrat.contrat_url, 300);
      if (data?.signedUrl) window.open(data.signedUrl, '_blank');
      else toast.error('Impossible de générer le lien de téléchargement.');
    } catch {
      toast.error('Impossible de télécharger le contrat.');
    }
  };

  const resilierContrat = async () => {
    if (!resilierMotif.trim()) { toast.error('Motif de résiliation obligatoire.'); return; }
    setResilierLoading(true);
    try {
      const { data, error } = await supabase.rpc('fn_revoquer_contrat_service' as any, {
        p_motif: resilierMotif.trim(),
      });
      if (error || (data as any)?.error) throw new Error((data as any)?.error || error?.message || 'Erreur résiliation.');
      toast.success('Demande de résiliation enregistrée. Effective sous 48h.');
      setShowResilierModal(false);
      setResilierMotif('');
      await charger();
    } catch (err: any) {
      toast.error(err?.message || 'Erreur lors de la résiliation.');
    }
    setResilierLoading(false);
  };

  if (loading) return <ChargementPage />;

  // State 1: No contract uploaded
  if (!contrat?.contrat_url) {
    return (
      <div className="max-w-2xl mx-auto space-y-6">
        <h2 className="text-lg font-bold text-foreground">Contrat plateforme</h2>
        <CardY2K noPadding>
          <CardY2KHeader>
            <div className="flex items-center gap-3">
              <div className="rounded-xl p-2.5 bg-warning/10">
                <FileText className="h-6 w-6 text-warning" />
              </div>
              <CardY2KTitle className="text-lg">Contrat d'utilisation</CardY2KTitle>
            </div>
          </CardY2KHeader>
          <CardY2KContent className="space-y-4">
            <p className="text-sm text-muted-foreground">
              Vous n'avez pas encore téléversé votre contrat d'utilisation de la plateforme Jolene.
              Téléchargez le modèle, signez-le, et uploadez-le ici.
            </p>
            <div className="bg-muted/50 rounded-xl p-4 space-y-3">
              <p className="text-sm font-medium text-foreground">📋 Étapes :</p>
              <ol className="text-sm text-muted-foreground space-y-2 list-decimal list-inside">
                <li>Téléchargez le modèle de contrat</li>
                <li>Imprimez, signez et scannez le document</li>
                <li>Uploadez le PDF signé ci-dessous</li>
              </ol>
            </div>
            <input
              ref={fileRef}
              type="file"
              accept="application/pdf"
              onChange={handleUpload}
              className="hidden"
              aria-label="Téléverser le contrat signé"
            />
            <BoutonY2K
              onClick={() => fileRef.current?.click()}
              disabled={uploading}
              className="w-full gap-2"
            >
              {uploading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Upload className="h-4 w-4" />}
              {uploading ? 'Envoi en cours…' : 'Téléverser le contrat signé (PDF, max 10 Mo)'}
            </BoutonY2K>
          </CardY2KContent>
        </CardY2K>
      </div>
    );
  }

  // State 2: Uploaded but not yet validated
  if (!contrat.contrat_valide) {
    return (
      <div className="max-w-2xl mx-auto space-y-6">
        <h2 className="text-lg font-bold text-foreground">Contrat plateforme</h2>
        <CardY2K noPadding className="border-warning/30">
          <CardY2KHeader>
            <div className="flex items-center gap-3">
              <div className="rounded-xl p-2.5 bg-warning/10">
                <Clock className="h-6 w-6 text-warning" />
              </div>
              <div>
                <CardY2KTitle className="text-lg">En cours de vérification</CardY2KTitle>
                <BadgeY2K variant="warning" className="mt-1">En attente</BadgeY2K>
              </div>
            </div>
          </CardY2KHeader>
          <CardY2KContent className="space-y-4">
            <p className="text-sm text-muted-foreground">
              Votre contrat a été téléversé le{' '}
              <span className="font-medium text-foreground">
                {contrat.contrat_uploade_le
                  ? format(new Date(contrat.contrat_uploade_le), 'dd MMMM yyyy', { locale: fr })
                  : '—'}
              </span>.
              Il est en cours de vérification automatique (IA : conformité, SIRET, signataire). Vous serez notifié dès qu'il sera validé.
            </p>
            <div className="flex gap-2">
              <BoutonY2K variant="secondary" onClick={telechargerContrat} className="gap-2">
                <ExternalLink className="h-4 w-4" /> Voir le contrat téléversé
              </BoutonY2K>
              <input
                ref={fileRef}
                type="file"
                accept="application/pdf"
                onChange={handleUpload}
                className="hidden"
                aria-label="Remplacer le contrat"
              />
              <BoutonY2K variant="secondary" onClick={() => fileRef.current?.click()} disabled={uploading} className="gap-2">
                {uploading ? <Loader2 className="h-4 w-4 animate-spin" /> : <RefreshCw className="h-4 w-4" />}
                {uploading ? 'Envoi…' : 'Remplacer le contrat'}
              </BoutonY2K>
            </div>
          </CardY2KContent>
        </CardY2K>
      </div>
    );
  }

  // State 3: Validated
  return (
    <div className="max-w-2xl mx-auto space-y-6">
      <h2 className="text-lg font-bold text-foreground">Contrat plateforme</h2>
      <CardY2K noPadding className="border-success/30">
        <CardY2KHeader>
          <div className="flex items-center gap-3">
            <div className="rounded-xl p-2.5 bg-success/10">
              <CheckCircle className="h-6 w-6 text-success" />
            </div>
            <div>
              <CardY2KTitle className="text-lg">Contrat actif</CardY2KTitle>
              <BadgeY2K variant="success" className="mt-1">Validé</BadgeY2K>
            </div>
          </div>
        </CardY2KHeader>
        <CardY2KContent className="space-y-4">
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <p className="text-xs text-muted-foreground">Établissement</p>
              <p className="text-sm font-medium text-foreground">{contrat.nom}</p>
            </div>
            <div>
              <p className="text-xs text-muted-foreground">SIRET</p>
              <p className="text-sm font-medium text-foreground">{contrat.siret}</p>
            </div>
            <div>
              <p className="text-xs text-muted-foreground">Taux de commission</p>
              <p className="text-sm font-medium text-foreground">{contrat.taux_commission_negocie}%</p>
            </div>
            <div>
              <p className="text-xs text-muted-foreground">Date de téléversement</p>
              <p className="text-sm font-medium text-foreground">
                {contrat.contrat_uploade_le
                  ? format(new Date(contrat.contrat_uploade_le), 'dd MMMM yyyy', { locale: fr })
                  : '—'}
              </p>
            </div>
          </div>
          <div className="flex gap-2 flex-wrap">
            <BoutonY2K variant="secondary" onClick={telechargerContrat} className="gap-2">
              <Download className="h-4 w-4" /> Télécharger le contrat
            </BoutonY2K>
            <input
              ref={fileRef}
              type="file"
              accept="application/pdf"
              onChange={handleUpload}
              className="hidden"
              aria-label="Remplacer le contrat"
            />
            <BoutonY2K variant="secondary" onClick={() => fileRef.current?.click()} disabled={uploading} className="gap-2">
              {uploading ? <Loader2 className="h-4 w-4 animate-spin" /> : <RefreshCw className="h-4 w-4" />}
              {uploading ? 'Envoi…' : 'Remplacer le contrat'}
            </BoutonY2K>
            <BoutonY2K variant="destructive" onClick={() => { setResilierMotif(''); setShowResilierModal(true); }} className="gap-2">
              <AlertTriangle className="h-4 w-4" /> Résilier mon contrat
            </BoutonY2K>
          </div>
        </CardY2KContent>
      </CardY2K>

      {/* Task 11 — Modal résiliation contrat */}
      {showResilierModal && (
        <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4" onClick={() => setShowResilierModal(false)}>
          <div className="bg-card border border-border rounded-2xl max-w-md w-full p-6 space-y-4" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center justify-between">
              <h2 className="text-lg font-bold text-foreground inline-flex items-center gap-2">
                <AlertTriangle className="h-5 w-5 text-destructive" /> Résilier le contrat
              </h2>
              <button onClick={() => setShowResilierModal(false)} className="p-1 hover:bg-muted rounded-lg" aria-label="Fermer">
                <X className="h-5 w-5" />
              </button>
            </div>
            <div className="rounded-lg bg-destructive/10 border border-destructive/30 p-4 text-sm text-foreground space-y-1">
              <p className="font-semibold">Attention — action irréversible</p>
              <p className="text-muted-foreground text-xs">La résiliation prend effet sous <strong>48 heures</strong>. Les missions en cours restent valides jusqu'à leur terme.</p>
            </div>
            <label className="block">
              <span className="text-xs font-medium text-foreground mb-1 block">Motif de résiliation * (obligatoire)</span>
              <Textarea
                value={resilierMotif}
                onChange={(e) => setResilierMotif(e.target.value)}
                rows={3}
                placeholder="Indiquez la raison de votre résiliation…"
                disabled={resilierLoading}
              />
            </label>
            <div className="flex gap-2">
              <BoutonY2K variant="secondary" onClick={() => setShowResilierModal(false)} disabled={resilierLoading}>Annuler</BoutonY2K>
              <BoutonY2K variant="destructive" onClick={resilierContrat} disabled={resilierLoading || !resilierMotif.trim()} loading={resilierLoading}>
                Confirmer la résiliation
              </BoutonY2K>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
