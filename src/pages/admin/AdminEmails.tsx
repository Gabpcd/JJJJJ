import React, { useState, useEffect } from 'react';
import { Mail, Eye, Send, Loader2, CheckCircle, XCircle } from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { usePageTitle } from '@/hooks/usePageTitle';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';

const DONNEES_FICTIVES: Record<string, Record<string, string>> = {
  BIENVENUE_SOIGNANT: { prenom: 'Marie', lien_profil: 'https://app.jolene.app/soignant/profil' },
  BIENVENUE_ETABLISSEMENT: { nom_etablissement: 'EHPAD Les Oliviers', lien_profil: 'https://app.jolene.app/etablissement/profil' },
  MISSION_ACCEPTEE_SOIGNANT: { prenom: 'Marie', mission: 'Remplacement IDE — Jour', etablissement: 'EHPAD Les Oliviers', date: '15 mars 2026', heure: '07h00 – 19h00' },
  MISSION_ACCEPTEE_ETABLISSEMENT: { nom_etablissement: 'EHPAD Les Oliviers', mission: 'Remplacement IDE — Jour', soignant: 'Marie Dupont', date: '15 mars 2026' },
  MISSION_ANNULEE_SOIGNANT: { prenom: 'Marie', mission: 'Remplacement AS — Nuit', motif: 'Annulation par l\'établissement' },
  MISSION_ANNULEE_ETABLISSEMENT: { nom_etablissement: 'EHPAD Les Oliviers', mission: 'Remplacement AS — Nuit', soignant: 'Marie Dupont' },
  CONTRAT_SIGNE: { prenom: 'Marie', numero_contrat: 'CTR-2026-0042', mission: 'Remplacement IDE — Jour' },
  RAPPEL_POINTAGE: { prenom: 'Marie', mission: 'Remplacement IDE — Jour', heure_debut: '07h00', etablissement: 'EHPAD Les Oliviers' },
  FACTURE_EMISE: { nom_etablissement: 'EHPAD Les Oliviers', numero_facture: 'FA-2026-0018', montant_ttc: '1 250,00 €' },
  PAIEMENT_RECU: { nom_etablissement: 'EHPAD Les Oliviers', numero_facture: 'FA-2026-0018', montant: '1 250,00 €' },
  DOCUMENT_EXPIRE: { prenom: 'Marie', type_document: 'Attestation vaccinale', date_expiration: '20 avril 2026' },
  EVALUATION_RECUE: { prenom: 'Marie', note: '5/5', commentaire: 'Excellente professionnelle, ponctuelle et compétente.', mission: 'Remplacement IDE — Jour' },
  RAPPEL_DPAE: { nom_etablissement: 'EHPAD Les Oliviers', soignant: 'Marie Dupont', numero_contrat: 'CTR-2026-0042' },
  LITIGE_OUVERT: { prenom: 'Marie', mission: 'Remplacement IDE — Jour', motif: 'Heures contestées', reference: 'LIT-2026-007' },
};

const TEMPLATES = Object.keys(DONNEES_FICTIVES);

function genererHtmlPreview(type: string, data: Record<string, string>): string {
  const vars = Object.entries(data).map(([k, v]) => `<tr><td style="padding:6px 14px;color:#64748b;font-size:13px">${k}</td><td style="padding:6px 14px;font-size:13px;color:#333">${v}</td></tr>`).join('');
  return `<!DOCTYPE html><html><head><meta charset="utf-8"/><style>
    body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;margin:0;padding:32px;background:#faf7fc;color:#1a1a2e}
    .card{max-width:600px;margin:0 auto;background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(224,69,144,.12)}
    .header{background:linear-gradient(135deg,#E04590 0%,#9333EA 50%,#3B82F6 100%);padding:28px;text-align:center}
    .logo{color:#fff;font-size:22px;font-weight:800;letter-spacing:-0.5px}
    .body{padding:32px}
    h1{font-size:18px;margin:0 0 16px;color:#1a1a2e}
    p{font-size:14px;line-height:1.6;color:#555;margin:0 0 12px}
    .vars{width:100%;border-collapse:collapse;margin:16px 0;background:linear-gradient(135deg,rgba(224,69,144,.04),rgba(147,51,234,.06));border-radius:12px;overflow:hidden}
    .vars td{border-bottom:1px solid rgba(224,69,144,.1);padding:6px 14px}
    .footer{text-align:center;padding:16px;font-size:12px;color:#94a3b8;border-top:1px solid #f0e6f6}
    .badge{display:inline-block;background:linear-gradient(135deg,#E04590,#9333EA);color:#fff;padding:5px 14px;border-radius:99px;font-size:12px;font-weight:700}
  </style></head><body>
    <div class="card">
      <div class="header"><span class="logo">❤️ Jolene</span></div>
      <div class="body">
        <span class="badge">${type.replace(/_/g, ' ')}</span>
        <h1 style="margin-top:16px">Prévisualisation du template</h1>
        <p>Voici les variables injectées dans ce template :</p>
        <table class="vars">${vars}</table>
        <p style="color:#94a3b8;font-size:12px;margin-top:24px">Ceci est un aperçu de développement. L'email réel utilise le template serveur complet.</p>
      </div>
      <div class="footer">© 2026 Jolene — contact@jolene.app ❤️</div>
    </div>
  </body></html>`;
}

export default function AdminEmails() {
  usePageTitle('Emails');
  const { user } = useAuth();
  const [previewType, setPreviewType] = useState<string | null>(null);
  const [sending, setSending] = useState<string | null>(null);
  const [historique, setHistorique] = useState<any[]>([]);
  const [histLoading, setHistLoading] = useState(true);

  useEffect(() => {
    chargerHistorique();
  }, []);

  const chargerHistorique = async () => {
    setHistLoading(true);
    const { data } = await supabase
      .from('emails_envoyes')
      .select('id, type, sujet, destinataire_email, destinataire_id, statut, erreur, provider_id, cree_le')
      .order('cree_le', { ascending: false })
      .limit(20);
    setHistorique(data || []);
    setHistLoading(false);
  };

  const envoyerTest = async (type: string) => {
    if (!user) return;
    setSending(type);
    const { data: { session } } = await supabase.auth.getSession();
    const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
    const res = await fetch(`${supabaseUrl}/functions/v1/send-email`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${session?.access_token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ type, destinataire_id: user.id, data: DONNEES_FICTIVES[type] }),
    });
    const error = res.ok ? null : { message: `HTTP ${res.status}` };
    setSending(null);
    if (error) {
      toast.error('Une erreur est survenue. Veuillez réessayer.');
    } else {
      toast.success('Email test envoyé à votre adresse');
      chargerHistorique();
    }
  };

  const formatDate = (d: string) =>
    new Date(d).toLocaleDateString('fr-FR', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' });

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin pageName="Emails" />
      <div className="space-y-8">
        <div>
          <h1 className="text-2xl font-bold text-foreground flex items-center gap-2">
            <Mail className="h-6 w-6 text-primary" /> Templates emails
          </h1>
          <p className="text-muted-foreground mt-1">Prévisualisez et testez les 14 templates transactionnels.</p>
        </div>

        {/* Templates table */}
        <div className="rounded-lg border border-border overflow-hidden">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="w-[50%]">Template</TableHead>
                <TableHead className="text-center">Prévisualiser</TableHead>
                <TableHead className="text-center">Envoyer un test</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {TEMPLATES.map((t) => (
                <TableRow key={t} className={previewType === t ? 'bg-muted/50' : ''}>
                  <TableCell className="font-mono text-sm">{t}</TableCell>
                  <TableCell className="text-center">
                    <Button
                      variant={previewType === t ? 'default' : 'outline'}
                      size="sm"
                      onClick={() => setPreviewType(previewType === t ? null : t)}
                      className="gap-1.5"
                    >
                      <Eye className="h-4 w-4" />
                      {previewType === t ? 'Masquer' : 'Prévisualiser'}
                    </Button>
                  </TableCell>
                  <TableCell className="text-center">
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => envoyerTest(t)}
                      disabled={sending !== null}
                      className="gap-1.5"
                    >
                      {sending === t ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
                      Envoyer
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>

        {/* Preview iframe */}
        {previewType && (
          <div className="space-y-2">
            <h2 className="text-lg font-semibold text-foreground">
              Aperçu : <span className="font-mono text-primary">{previewType}</span>
            </h2>
            <div className="rounded-lg border border-border overflow-hidden bg-muted">
              <iframe
                title={`Aperçu ${previewType}`}
                srcDoc={genererHtmlPreview(previewType, DONNEES_FICTIVES[previewType])}
                className="w-full border-0"
                style={{ height: '500px' }}
                sandbox="allow-same-origin"
              />
            </div>
          </div>
        )}

        {/* Historique */}
        <div className="space-y-3">
          <h2 className="text-lg font-semibold text-foreground">Derniers emails envoyés</h2>
          <div className="rounded-lg border border-border overflow-hidden">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Date</TableHead>
                  <TableHead>Type</TableHead>
                  <TableHead>Destinataire</TableHead>
                  <TableHead className="text-center">Statut</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {histLoading ? (
                  <TableRow>
                    <TableCell colSpan={4} className="text-center py-8 text-muted-foreground">
                      <Loader2 className="h-4 w-4 animate-spin inline mr-2" /> Chargement…
                    </TableCell>
                  </TableRow>
                ) : historique.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={4} className="text-center py-8 text-muted-foreground">
                      Aucun email envoyé.
                    </TableCell>
                  </TableRow>
                ) : (
                  historique.map((e) => (
                    <TableRow key={e.id}>
                      <TableCell className="text-sm">{formatDate(e.cree_le)}</TableCell>
                      <TableCell className="font-mono text-xs">{e.type}</TableCell>
                      <TableCell className="text-sm">{e.destinataire_email}</TableCell>
                      <TableCell className="text-center">
                        {e.statut === 'ENVOYE' ? (
                          <Badge className="bg-emerald-500/10 text-emerald-600 border-emerald-500/20 gap-1">
                            <CheckCircle className="h-3 w-3" /> Envoyé
                          </Badge>
                        ) : (
                          <Badge variant="destructive" className="gap-1">
                            <XCircle className="h-3 w-3" /> Erreur
                          </Badge>
                        )}
                      </TableCell>
                    </TableRow>
                  ))
                )}
              </TableBody>
            </Table>
          </div>
        </div>
      </div>
    </LayoutAdmin>
  );
}
