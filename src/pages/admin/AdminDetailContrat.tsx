import { useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { ArrowLeft, FileText, Shield, Clock, Copy, ExternalLink } from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { usePageTitle } from '@/hooks/usePageTitle';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { CardY2K } from '@/components/y2k/CardY2K';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface DetailContrat {
  id: string;
  numero_contrat: string | null;
  mission_id: string;
  mission_intitule: string;
  mission_debut_le: string;
  mission_fin_le: string;
  soignant_id: string | null;
  soignant_nom: string | null;
  soignant_email: string | null;
  soignant_rpps: string | null;
  etablissement_id: string;
  etablissement_nom: string;
  etablissement_siret: string | null;
  type_contrat: string;
  statut: string;
  mode_signature: string | null;
  hash_document: string | null;
  signature_soignant: boolean;
  signature_soignant_le: string | null;
  signature_ip_soignant: string | null;
  signature_navigateur_soignant: string | null;
  signature_etablissement: boolean;
  signature_etablissement_le: string | null;
  signature_ip_etablissement: string | null;
  signature_navigateur_etablissement: string | null;
  dpae_effectuee: boolean;
  dpae_effectuee_le: string | null;
  dpae_numero: string | null;
  storage_path: string | null;
  pdf_cle_s3: string | null;
  cree_le: string;
}

interface SignatureRecord {
  id: string;
  signataire_role: string;
  signe_a: string;
  ip_signature: string | null;
  user_agent: string | null;
  hash_document: string | null;
  otp_valide_a: string | null;
  statut_signature: string;
}

interface AuditRecord {
  id: string;
  acteur_id: string | null;
  type_acteur: string;
  action: string;
  details: any;
  cree_le: string;
}

export default function AdminDetailContrat() {
  usePageTitle('Admin · Détail contrat');
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [contrat, setContrat] = useState<DetailContrat | null>(null);
  const [signatures, setSignatures] = useState<SignatureRecord[]>([]);
  const [auditTrail, setAuditTrail] = useState<AuditRecord[]>([]);
  const [pdfUrl, setPdfUrl] = useState<string | null>(null);

  useEffect(() => {
    if (!id) return;
    let cancelled = false;
    async function load() {
      const { data, error } = await supabase.rpc('fn_admin_detail_contrat' as any, { p_contrat_id: id });
      if (cancelled) return;
      if (error) {
        afficherNotification({ type: 'erreur', message: error.message });
        setLoading(false);
        return;
      }
      const result = data as any;
      if (!result?.success) {
        afficherNotification({ type: 'erreur', message: result?.error || 'Erreur.' });
        setLoading(false);
        return;
      }
      setContrat(result.contrat as DetailContrat);
      setSignatures(result.signatures as SignatureRecord[]);
      setAuditTrail(result.audit_trail as AuditRecord[]);

      const path = (result.contrat as DetailContrat).storage_path || (result.contrat as DetailContrat).pdf_cle_s3;
      if (path) {
        const { data: signed } = await supabase.storage.from('contrats-signes').createSignedUrl(path, 300);
        if (!cancelled && signed?.signedUrl) setPdfUrl(signed.signedUrl);
      }
      setLoading(false);
    }
    load();
    return () => { cancelled = true; };
  }, [id, afficherNotification]);

  function copierHash() {
    if (!contrat?.hash_document) return;
    navigator.clipboard.writeText(contrat.hash_document).then(() => {
      afficherNotification({ type: 'succes', message: 'Hash copié.' });
    });
  }

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;
  if (!contrat) return (
    <LayoutAdmin>
      <p className="text-sm text-muted-foreground">Contrat introuvable.</p>
    </LayoutAdmin>
  );

  return (
    <LayoutAdmin>
      <button onClick={() => navigate('/admin/contrats')} className="flex items-center gap-1 text-sm text-primary hover:underline mb-2">
        <ArrowLeft className="h-4 w-4" /> Retour
      </button>

      <div className="mb-6">
        <h1 className="text-2xl font-bold text-foreground inline-flex items-center gap-2">
          <FileText className="h-6 w-6 text-primary" /> {contrat.numero_contrat || 'Contrat'}
        </h1>
        <p className="text-sm text-muted-foreground mt-1">{contrat.mission_intitule}</p>
      </div>

      {/* Parties */}
      <section className="grid grid-cols-1 md:grid-cols-2 gap-3 mb-6">
        <CardY2K hoverLift={false}>
          <h2 className="text-sm font-bold text-foreground mb-2">Soignant</h2>
          <p className="text-sm">{contrat.soignant_nom}</p>
          <p className="text-xs text-muted-foreground">{contrat.soignant_email}</p>
          {contrat.soignant_rpps && <p className="text-xs text-muted-foreground">RPPS : <span className="font-mono">{contrat.soignant_rpps}</span></p>}
          <button onClick={() => navigate(`/admin/utilisateurs/${contrat.soignant_id}`)} className="text-xs text-primary hover:underline mt-2 inline-flex items-center gap-1">
            Profil <ExternalLink className="h-3 w-3" />
          </button>
        </CardY2K>
        <CardY2K hoverLift={false}>
          <h2 className="text-sm font-bold text-foreground mb-2">Établissement</h2>
          <p className="text-sm">{contrat.etablissement_nom}</p>
          {contrat.etablissement_siret && <p className="text-xs text-muted-foreground font-mono">SIRET : {contrat.etablissement_siret}</p>}
        </CardY2K>
      </section>

      {/* Hash + statut + DPAE */}
      <CardY2K hoverLift={false} className="mb-6 space-y-3">
        <div className="flex items-center gap-2 mb-2">
          <Shield className="h-5 w-5 text-primary" />
          <h2 className="text-sm font-bold text-foreground">Intégrité document</h2>
        </div>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-xs">
          <div>
            <p className="text-muted-foreground">Statut</p>
            <p className="font-semibold text-foreground">{contrat.statut}</p>
          </div>
          <div>
            <p className="text-muted-foreground">Type contrat</p>
            <p className="font-semibold text-foreground">{contrat.type_contrat}</p>
          </div>
          <div>
            <p className="text-muted-foreground">Mode signature</p>
            <p className="font-semibold text-foreground">{contrat.mode_signature || '—'}</p>
          </div>
          <div>
            <p className="text-muted-foreground">Créé le</p>
            <p className="font-semibold text-foreground">{format(new Date(contrat.cree_le), 'dd MMM yyyy HH:mm', { locale: fr })}</p>
          </div>
        </div>
        {contrat.hash_document && (
          <div className="rounded-lg bg-muted/40 border border-border p-3">
            <p className="text-[11px] text-muted-foreground mb-1">Hash SHA-256 du document</p>
            <div className="flex items-center gap-2">
              <code className="text-xs font-mono break-all text-foreground flex-1">{contrat.hash_document}</code>
              <BoutonY2K variant="secondary" size="sm" onClick={copierHash} iconeGauche={<Copy className="h-3 w-3" />} className="shrink-0">
                Copier
              </BoutonY2K>
            </div>
          </div>
        )}
      </CardY2K>

      {/* Signatures détaillées */}
      <CardY2K hoverLift={false} className="mb-6">
        <h2 className="text-sm font-bold text-foreground mb-3">Signatures</h2>
        <div className="space-y-2">
          <div className="rounded-lg border border-border p-3 text-xs">
            <p className="font-semibold text-foreground mb-1">Soignant — {contrat.signature_soignant ? 'signé' : 'en attente'}</p>
            {contrat.signature_soignant_le && (
              <>
                <p className="text-muted-foreground">Signé le {format(new Date(contrat.signature_soignant_le), 'dd MMM yyyy HH:mm:ss', { locale: fr })}</p>
                {contrat.signature_ip_soignant && <p className="text-muted-foreground">IP : <span className="font-mono">{contrat.signature_ip_soignant}</span></p>}
                {contrat.signature_navigateur_soignant && <p className="text-muted-foreground text-[11px] truncate">UA : {contrat.signature_navigateur_soignant}</p>}
              </>
            )}
          </div>
          <div className="rounded-lg border border-border p-3 text-xs">
            <p className="font-semibold text-foreground mb-1">Établissement — {contrat.signature_etablissement ? 'signé' : 'en attente'}</p>
            {contrat.signature_etablissement_le && (
              <>
                <p className="text-muted-foreground">Signé le {format(new Date(contrat.signature_etablissement_le), 'dd MMM yyyy HH:mm:ss', { locale: fr })}</p>
                {contrat.signature_ip_etablissement && <p className="text-muted-foreground">IP : <span className="font-mono">{contrat.signature_ip_etablissement}</span></p>}
              </>
            )}
          </div>
        </div>

        {signatures.length > 0 && (
          <details className="mt-3">
            <summary className="text-xs cursor-pointer text-muted-foreground hover:text-foreground">
              {signatures.length} signature{signatures.length > 1 ? 's' : ''} dans signatures_contrats (OTP / PSC)
            </summary>
            <ul className="mt-2 space-y-2">
              {signatures.map((s) => (
                <li key={s.id} className="rounded-lg bg-muted/30 border border-border p-2 text-[11px]">
                  <p className="font-semibold text-foreground">{s.signataire_role} · {s.statut_signature}</p>
                  <p className="text-muted-foreground">Signé le {format(new Date(s.signe_a), 'dd MMM HH:mm:ss', { locale: fr })}</p>
                  {s.ip_signature && <p className="text-muted-foreground">IP : <span className="font-mono">{s.ip_signature}</span></p>}
                  {s.otp_valide_a && <p className="text-muted-foreground">OTP validé : {format(new Date(s.otp_valide_a), 'dd MMM HH:mm', { locale: fr })}</p>}
                  {s.hash_document && <p className="text-muted-foreground font-mono break-all">Hash : {s.hash_document.slice(0, 20)}…</p>}
                </li>
              ))}
            </ul>
          </details>
        )}
      </CardY2K>

      {/* DPAE */}
      {(contrat.type_contrat === 'CDD' || contrat.type_contrat === 'SALARIE') && (
        <CardY2K hoverLift={false} className="mb-6">
          <h2 className="text-sm font-bold text-foreground mb-2">DPAE</h2>
          {contrat.dpae_effectuee && contrat.dpae_numero ? (
            <div className="text-xs space-y-1">
              <p>DPAE validée le {format(new Date(contrat.dpae_effectuee_le!), 'dd MMM yyyy', { locale: fr })}</p>
              <p className="font-mono text-foreground">N° URSSAF : {contrat.dpae_numero}</p>
            </div>
          ) : (
            <p className="text-xs text-warning">⏳ DPAE non encore transmise / numéro non saisi.</p>
          )}
        </CardY2K>
      )}

      {/* PDF embarqué */}
      {pdfUrl && (
        <CardY2K hoverLift={false} className="mb-6">
          <h2 className="text-sm font-bold text-foreground mb-3">PDF contrat</h2>
          <iframe src={pdfUrl} className="w-full h-[600px] border border-border rounded-lg" title="Contrat PDF" />
        </CardY2K>
      )}

      {/* Audit trail */}
      <CardY2K hoverLift={false}>
        <div className="flex items-center gap-2 mb-3">
          <Clock className="h-5 w-5 text-primary" />
          <h2 className="text-sm font-bold text-foreground">Historique des actions ({auditTrail.length})</h2>
        </div>
        {auditTrail.length === 0 ? (
          <p className="text-xs text-muted-foreground italic">Aucune action enregistrée.</p>
        ) : (
          <ul className="space-y-1.5 max-h-96 overflow-y-auto">
            {auditTrail.map((a) => (
              <li key={a.id} className="border-l-2 border-border pl-3 py-1">
                <p className="text-xs">
                  <strong className="text-foreground">{a.action}</strong>
                  <span className="text-muted-foreground"> · {a.type_acteur}</span>
                  <span className="text-muted-foreground"> · {format(new Date(a.cree_le), 'dd MMM HH:mm:ss', { locale: fr })}</span>
                </p>
                {a.details && Object.keys(a.details).length > 0 && (
                  <p className="text-[10px] text-muted-foreground truncate">
                    {Object.entries(a.details as Record<string, unknown>)
                      .map(([cle, valeur]) => `${cle.replace(/_/g, ' ')} : ${valeur !== null && typeof valeur === 'object' ? JSON.stringify(valeur) : String(valeur)}`)
                      .join(' · ')
                      .slice(0, 200)}
                  </p>
                )}
              </li>
            ))}
          </ul>
        )}
      </CardY2K>

      <div className="mt-4 flex justify-end">
        <BoutonY2K
          variant="secondary"
          size="sm"
          onClick={() => navigate(`/contrat/${contrat.id}/certificat`)}
          iconeGauche={<ExternalLink className="h-4 w-4" />}
        >
          Voir certificat signature
        </BoutonY2K>
      </div>
    </LayoutAdmin>
  );
}
