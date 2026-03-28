import React, { useState, useEffect, useRef } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { capturerErreurSentry } from '@/lib/sentry';
import { FileText, Upload, CheckCircle, Clock, Download, ExternalLink, Loader2 } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
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
  const { user } = useAuth();
  const [contrat, setContrat] = useState<ContratInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const [uploading, setUploading] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);

  const charger = async () => {
    if (!user) return;
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

  useEffect(() => { charger(); }, [user]);

  const handleUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file || !user) return;

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
      const path = `${user.id}/contrats-plateforme/contrat.pdf`;
      const { error: uploadError } = await supabase.storage
        .from('jolene-documents')
        .upload(path, file, { upsert: true, contentType: 'application/pdf' });
      if (uploadError) throw uploadError;

      const { error: rpcError } = await supabase.rpc('fn_uploader_contrat_plateforme' as any, {
        p_contrat_url: path,
      });
      if (rpcError) throw rpcError;

      // Contract verification is done manually by admin via fn_admin_valider_contrat_etablissement
      // No AI verification for platform contracts (not in documents_soignants table)

      toast.success('Contrat téléversé — en cours de vérification.');
      await charger();
    } catch (err) {
      capturerErreurSentry(err, 'ContratPlateforme', 'upload');
      toast.error('Une erreur est survenue lors du téléversement.');
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

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><ChargementPage /></LayoutApp>;

  // State 1: No contract uploaded
  if (!contrat?.contrat_url) {
    return (
      <LayoutApp role="ADMIN_ETABLISSEMENT">
        <div className="max-w-2xl mx-auto space-y-6">
          <h1 className="text-2xl font-bold text-foreground">Contrat plateforme</h1>
          <Card>
            <CardHeader>
              <div className="flex items-center gap-3">
                <div className="rounded-xl p-2.5 bg-warning/10">
                  <FileText className="h-6 w-6 text-warning" />
                </div>
                <CardTitle className="text-lg">Contrat d'utilisation</CardTitle>
              </div>
            </CardHeader>
            <CardContent className="space-y-4">
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
              <Button
                onClick={() => fileRef.current?.click()}
                disabled={uploading}
                className="w-full gap-2"
              >
                {uploading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Upload className="h-4 w-4" />}
                {uploading ? 'Envoi en cours…' : 'Téléverser le contrat signé (PDF, max 10 Mo)'}
              </Button>
            </CardContent>
          </Card>
        </div>
      </LayoutApp>
    );
  }

  // State 2: Uploaded but not yet validated
  if (!contrat.contrat_valide) {
    return (
      <LayoutApp role="ADMIN_ETABLISSEMENT">
        <div className="max-w-2xl mx-auto space-y-6">
          <h1 className="text-2xl font-bold text-foreground">Contrat plateforme</h1>
          <Card className="border-warning/30">
            <CardHeader>
              <div className="flex items-center gap-3">
                <div className="rounded-xl p-2.5 bg-warning/10">
                  <Clock className="h-6 w-6 text-warning" />
                </div>
                <div>
                  <CardTitle className="text-lg">En cours de vérification</CardTitle>
                  <Badge variant="secondary" className="mt-1 text-xs">En attente</Badge>
                </div>
              </div>
            </CardHeader>
            <CardContent className="space-y-4">
              <p className="text-sm text-muted-foreground">
                Votre contrat a été téléversé le{' '}
                <span className="font-medium text-foreground">
                  {contrat.contrat_uploade_le
                    ? format(new Date(contrat.contrat_uploade_le), 'dd MMMM yyyy', { locale: fr })
                    : '—'}
                </span>.
                Il est en cours de vérification par notre équipe. Vous serez notifié dès qu'il sera validé.
              </p>
              <Button variant="outline" onClick={telechargerContrat} className="gap-2">
                <ExternalLink className="h-4 w-4" /> Voir le contrat téléversé
              </Button>
            </CardContent>
          </Card>
        </div>
      </LayoutApp>
    );
  }

  // State 3: Validated
  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <div className="max-w-2xl mx-auto space-y-6">
        <h1 className="text-2xl font-bold text-foreground">Contrat plateforme</h1>
        <Card className="border-success/30">
          <CardHeader>
            <div className="flex items-center gap-3">
              <div className="rounded-xl p-2.5 bg-success/10">
                <CheckCircle className="h-6 w-6 text-success" />
              </div>
              <div>
                <CardTitle className="text-lg">Contrat actif</CardTitle>
                <Badge className="mt-1 text-xs bg-success text-success-foreground">Validé</Badge>
              </div>
            </div>
          </CardHeader>
          <CardContent className="space-y-4">
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
            <Button variant="outline" onClick={telechargerContrat} className="gap-2">
              <Download className="h-4 w-4" /> Télécharger le contrat
            </Button>
          </CardContent>
        </Card>
      </div>
    </LayoutApp>
  );
}
