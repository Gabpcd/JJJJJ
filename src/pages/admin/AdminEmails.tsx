import React, { useState, useEffect } from 'react';
import { Mail, Eye, Send, Loader2, CheckCircle, XCircle } from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { usePageTitle } from '@/hooks/usePageTitle';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { EmptyState } from '@/components/ui/EmptyState';
import { TableOuCartes, type ColonneTableau } from '@/components/ui/TableOuCartes';
import { supabase, SUPABASE_URL } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';

// [DEV] Dummy data for email template previews — not sent to real users
const DONNEES_FICTIVES: Record<string, Record<string, string>> = {
  BIENVENUE_SOIGNANT: { prenom: '[DEV] Marie', lien_profil: 'https://jolene.app/soignant/profil' },
  BIENVENUE_ETABLISSEMENT: { nom_etablissement: '[DEV] EHPAD Les Oliviers', lien_profil: 'https://jolene.app/etablissement/profil' },
  MISSION_ACCEPTEE_SOIGNANT: { prenom: '[DEV] Marie', mission: '[DEV] Remplacement IDE — Jour', etablissement: '[DEV] EHPAD Les Oliviers', date: '15 mars 2026', heure: '07h00 – 19h00' },
  MISSION_ACCEPTEE_ETABLISSEMENT: { nom_etablissement: '[DEV] EHPAD Les Oliviers', mission: '[DEV] Remplacement IDE — Jour', soignant: '[DEV] Marie Dupont', date: '15 mars 2026' },
  MISSION_ANNULEE_SOIGNANT: { prenom: '[DEV] Marie', mission: '[DEV] Remplacement AS — Nuit', motif: 'Annulation par l\'établissement' },
  MISSION_ANNULEE_ETABLISSEMENT: { nom_etablissement: '[DEV] EHPAD Les Oliviers', mission: '[DEV] Remplacement AS — Nuit', soignant: '[DEV] Marie Dupont' },
  CONTRAT_SIGNE: { prenom: '[DEV] Marie', numero_contrat: '[DEV] CTR-2026-0042', mission: '[DEV] Remplacement IDE — Jour' },
  RAPPEL_POINTAGE: { prenom: '[DEV] Marie', mission: '[DEV] Remplacement IDE — Jour', heure_debut: '07h00', etablissement: '[DEV] EHPAD Les Oliviers' },
  FACTURE_EMISE: { nom_etablissement: '[DEV] EHPAD Les Oliviers', numero_facture: '[DEV] FA-2026-0018', montant_ttc: '1 250,00 €' },
  PAIEMENT_RECU: { nom_etablissement: '[DEV] EHPAD Les Oliviers', numero_facture: '[DEV] FA-2026-0018', montant: '1 250,00 €' },
  DOCUMENT_EXPIRE: { prenom: '[DEV] Marie', type_document: 'Attestation vaccinale', date_expiration: '20 avril 2026' },
  EVALUATION_RECUE: { prenom: '[DEV] Marie', note: '5/5', commentaire: 'Excellente professionnelle, ponctuelle et compétente.', mission: '[DEV] Remplacement IDE — Jour' },
  RAPPEL_DPAE: { nom_etablissement: '[DEV] EHPAD Les Oliviers', soignant: '[DEV] Marie Dupont', numero_contrat: '[DEV] CTR-2026-0042' },
  LITIGE_OUVERT: { prenom: '[DEV] Marie', mission: '[DEV] Remplacement IDE — Jour', motif: 'Heures contestées', reference: '[DEV] LIT-2026-007' },
};

const TEMPLATES = Object.keys(DONNEES_FICTIVES);

// Libellés français affichés à côté des identifiants techniques de templates
const LIBELLES_TEMPLATES: Record<string, string> = {
  BIENVENUE_SOIGNANT: 'Bienvenue soignant',
  BIENVENUE_ETABLISSEMENT: 'Bienvenue établissement',
  MISSION_ACCEPTEE_SOIGNANT: 'Mission acceptée (soignant)',
  MISSION_ACCEPTEE_ETABLISSEMENT: 'Mission acceptée (établissement)',
  MISSION_ANNULEE_SOIGNANT: 'Mission annulée (soignant)',
  MISSION_ANNULEE_ETABLISSEMENT: 'Mission annulée (établissement)',
  CONTRAT_SIGNE: 'Contrat signé',
  RAPPEL_POINTAGE: 'Rappel de pointage',
  FACTURE_EMISE: 'Facture émise',
  PAIEMENT_RECU: 'Paiement reçu',
  DOCUMENT_EXPIRE: 'Document expiré',
  EVALUATION_RECUE: 'Évaluation reçue',
  RAPPEL_DPAE: 'Rappel DPAE',
  LITIGE_OUVERT: 'Litige ouvert',
};

const libelleTemplate = (type: string) => LIBELLES_TEMPLATES[type] || type;

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
      <div class="header"><span class="logo">🩷 Jolene</span></div>
      <div class="body">
        <span class="badge">${type.replace(/_/g, ' ')}</span>
        <h1 style="margin-top:16px">Prévisualisation du template</h1>
        <p>Voici les variables injectées dans ce template :</p>
        <table class="vars">${vars}</table>
        <p style="color:#94a3b8;font-size:12px;margin-top:24px">Ceci est un aperçu de développement. L'email réel utilise le template serveur complet.</p>
      </div>
      <div class="footer">© 2026 Jolene — support@jolene.app 🩷</div>
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
    const supabaseUrl = SUPABASE_URL;
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

        {/* Templates */}
        {(() => {
          const colonnes: ColonneTableau<string>[] = [
            { cle: 'template', titre: 'Template' },
            { cle: 'preview', titre: 'Prévisualiser', align: 'center' },
            { cle: 'test', titre: 'Envoyer un test', align: 'center' },
          ];
          return (
            <TableOuCartes
              colonnes={colonnes}
              donnees={TEMPLATES as unknown as string[]}
              getId={(t) => t}
              renduCellule={(t, col) => {
                switch (col.cle) {
                  case 'template':
                    return (
                      <div>
                        <p className="text-sm font-medium text-foreground">{libelleTemplate(t)}</p>
                        <p className="font-mono text-xs text-muted-foreground">{t}</p>
                      </div>
                    );
                  case 'preview':
                    return (
                      <BoutonY2K
                        variant={previewType === t ? 'primary' : 'secondary'}
                        size="sm"
                        onClick={(e) => { e.stopPropagation(); setPreviewType(previewType === t ? null : t); }}
                        className="gap-1.5"
                        aria-label={previewType === t ? `Masquer l'aperçu de ${t}` : `Prévisualiser ${t}`}
                        iconeGauche={<Eye className="h-4 w-4" />}
                      >
                        {previewType === t ? 'Masquer' : 'Prévisualiser'}
                      </BoutonY2K>
                    );
                  case 'test':
                    return (
                      <BoutonY2K
                        variant="secondary"
                        size="sm"
                        onClick={(e) => { e.stopPropagation(); envoyerTest(t); }}
                        disabled={sending !== null}
                        loading={sending === t}
                        className="gap-1.5"
                        aria-label={`Envoyer un email test pour ${t}`}
                        iconeGauche={sending === t ? undefined : <Send className="h-4 w-4" />}
                      >
                        Envoyer
                      </BoutonY2K>
                    );
                  default:
                    return null;
                }
              }}
              renduCarte={(t) => (
                <div className="space-y-3">
                  <div>
                    <p className="text-sm font-medium text-foreground">{libelleTemplate(t)}</p>
                    <p className="font-mono text-xs text-muted-foreground break-all">{t}</p>
                  </div>
                  <div className="grid grid-cols-2 gap-2">
                    <BoutonY2K
                      variant={previewType === t ? 'primary' : 'secondary'}
                      size="sm"
                      onClick={(e) => { e.stopPropagation(); setPreviewType(previewType === t ? null : t); }}
                      className="gap-1.5 min-h-[44px]"
                      iconeGauche={<Eye className="h-4 w-4" />}
                    >
                      {previewType === t ? 'Masquer' : 'Aperçu'}
                    </BoutonY2K>
                    <BoutonY2K
                      variant="secondary"
                      size="sm"
                      onClick={(e) => { e.stopPropagation(); envoyerTest(t); }}
                      disabled={sending !== null}
                      loading={sending === t}
                      className="gap-1.5 min-h-[44px]"
                      iconeGauche={sending === t ? undefined : <Send className="h-4 w-4" />}
                    >
                      Test
                    </BoutonY2K>
                  </div>
                </div>
              )}
            />
          );
        })()}

        {/* Preview iframe */}
        {previewType && (
          <div className="space-y-2">
            <h2 className="text-lg font-semibold text-foreground">
              Aperçu : {libelleTemplate(previewType)} <span className="font-mono text-sm text-primary">({previewType})</span>
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
          {histLoading ? (
            <div className="text-center py-8 text-muted-foreground">
              <Loader2 className="h-4 w-4 animate-spin inline mr-2" /> Chargement…
            </div>
          ) : (() => {
            const colonnes: ColonneTableau<any>[] = [
              { cle: 'date', titre: 'Date' },
              { cle: 'type', titre: 'Type' },
              { cle: 'destinataire', titre: 'Destinataire' },
              { cle: 'statut', titre: 'Statut', align: 'center' },
            ];
            const statutBadge = (e: any) =>
              e.statut === 'ENVOYE' ? (
                <BadgeY2K variant="success" icone={<CheckCircle className="h-3 w-3" />}>Envoyé</BadgeY2K>
              ) : (
                <BadgeY2K variant="error" icone={<XCircle className="h-3 w-3" />}>Erreur</BadgeY2K>
              );
            return (
              <TableOuCartes
                colonnes={colonnes}
                donnees={historique}
                getId={(e: any) => e.id}
                etatVide={<EmptyState titre="Aucun email envoyé" description="L'historique des emails transactionnels apparaîtra ici." />}
                renduCellule={(e: any, col) => {
                  switch (col.cle) {
                    case 'date':
                      return <span className="text-sm">{formatDate(e.cree_le)}</span>;
                    case 'type':
                      return (
                        <div>
                          <p className="text-sm">{libelleTemplate(e.type)}</p>
                          {LIBELLES_TEMPLATES[e.type] && <p className="font-mono text-[10px] text-muted-foreground">{e.type}</p>}
                        </div>
                      );
                    case 'destinataire':
                      return <span className="text-sm">{e.destinataire_email}</span>;
                    case 'statut':
                      return statutBadge(e);
                    default:
                      return null;
                  }
                }}
                renduCarte={(e: any) => (
                  <div className="space-y-2">
                    <div className="flex items-start justify-between gap-2">
                      <div className="min-w-0">
                        <p className="text-sm text-foreground">{libelleTemplate(e.type)}</p>
                        {LIBELLES_TEMPLATES[e.type] && <p className="font-mono text-[10px] text-muted-foreground break-all">{e.type}</p>}
                      </div>
                      {statutBadge(e)}
                    </div>
                    <div className="text-xs text-muted-foreground space-y-0.5">
                      <p>📧 {e.destinataire_email}</p>
                      <p>📅 {formatDate(e.cree_le)}</p>
                    </div>
                  </div>
                )}
              />
            );
          })()}
        </div>
      </div>
    </LayoutAdmin>
  );
}
