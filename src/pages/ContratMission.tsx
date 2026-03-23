import React, { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { CheckAnimation } from '@/components/CheckAnimation';
import { useParams, useNavigate } from 'react-router-dom';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { useAuth } from '@/contexts/AuthContext';
import { useRole } from '@/hooks/useRole';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { FileText, Printer, CheckCircle, Clock, Shield, ExternalLink } from 'lucide-react';
import { BandeauRappelDPAE } from '@/components/BandeauRappelDPAE';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { Checkbox } from '@/components/ui/checkbox';
import { UserRole } from '@/lib/types';
import SignatureCanvas from '@/components/SignatureCanvas';
import { sanitizeHTML } from '@/lib/sanitize';
import { ModalConfirmation } from '@/components/ModalConfirmation';
import { logger } from '@/lib/logger';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';

export default function ContratMission() {
  usePageTitle('Contrat');
  const { id } = useParams();
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const navigate = useNavigate();
  const [contrat, setContrat] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [accepte, setAccepte] = useState(false);
  const [signing, setSigning] = useState(false);
  const [signatureData, setSignatureData] = useState<string | null>(null);
  const [showConfirmSign, setShowConfirmSign] = useState(false);
  const [showCheckAnim, setShowCheckAnim] = useState(false);
  const [modeSignature, setModeSignature] = useState<'CANVAS' | 'YOUSIGN'>('CANVAS');
  const [yousignLoading, setYousignLoading] = useState(false);
  const [yousignUrl, setYousignUrl] = useState<string | null>(null);

  const { role: serverRole } = useRole();
  const role: UserRole = serverRole === 'INCONNU' ? 'SOIGNANT' : serverRole;

  useEffect(() => {
    if (!id) return;
    const load = async () => {
      const { data } = await supabase
        .from('contrats_mission')
        .select('id, mission_id, numero_contrat, type_contrat, statut, contenu_html, soignant_id, etablissement_id, signature_soignant, signature_soignant_le, signature_etablissement, signature_etablissement_le, signature_image_soignant, signature_image_etablissement, dpae_effectuee, dpae_effectuee_le, mode_signature')
        .eq('id', id)
        .single();
      setContrat(data);
      setLoading(false);
    };
    load();
  }, [id]);

  const handleYousignCreate = async () => {
    if (!contrat || !user) return;
    setYousignLoading(true);
    try {
      const { data: sessionData } = await supabase.auth.getSession();
      const token = sessionData?.session?.access_token;
      if (!token) throw new Error('Non authentifié');

      const res = await fetch(
        `https://${import.meta.env.VITE_SUPABASE_PROJECT_ID}.supabase.co/functions/v1/yousign-create`,
        {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${token}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ contrat_id: contrat.id }),
        }
      );

      const data = await res.json();

      if (data.fallback) {
        afficherNotification({ type: 'info', message: data.message || 'Yousign non disponible — utilisez la signature manuscrite.' });
        setModeSignature('CANVAS');
        return;
      }

      if (!res.ok) throw new Error(data.error || 'Erreur Yousign');

      const isSoignant = contrat.soignant_id === user.id;
      const url = isSoignant ? data.soignant_signing_url : data.etablissement_signing_url;
      setYousignUrl(url);

      // Reload contract to get updated mode_signature
      const { data: updated } = await supabase
        .from('contrats_mission')
        .select('id, mission_id, numero_contrat, type_contrat, statut, contenu_html, soignant_id, etablissement_id, signature_soignant, signature_soignant_le, signature_etablissement, signature_etablissement_le, signature_image_soignant, signature_image_etablissement, dpae_effectuee, dpae_effectuee_le, mode_signature')
        .eq('id', contrat.id)
        .single();
      if (updated) setContrat(updated);

      afficherNotification({ type: 'succes', message: 'Procédure Yousign initialisée ! Cliquez sur le bouton pour signer.' });
    } catch (err: any) {
      logger.error('Yousign create error', err);
      afficherNotification({ type: 'erreur', message: err.message || 'Erreur lors de l\'initialisation Yousign' });
      setModeSignature('CANVAS');
    } finally {
      setYousignLoading(false);
    }
  };

  const handleFallbackCanvas = async () => {
    setModeSignature('CANVAS');
    // Reset mode_signature in DB if needed (admin-only update, so just change UI)
  };

  const handleSigner = async () => {
    if (!contrat || !user || !accepte || !signatureData) return;
    setSigning(true);
    try {
      const isSoignant = contrat.soignant_id === user.id;

      if (isSoignant) {
        // Soignant signe via RPC sécurisée
        const { data: rpcResult, error: rpcError } = await supabase.rpc('fn_signer_contrat_soignant' as any, {
          p_contrat_id: contrat.id,
          p_signature_image: signatureData,
        });
        if (rpcError) throw rpcError;
        if (rpcResult?.error) throw new Error(rpcResult.error);
      } else {
        // Établissement signe via RPC sécurisée
        const { data: rpcResult, error: rpcError } = await supabase.rpc('fn_signer_contrat_etablissement' as any, {
          p_contrat_id: contrat.id,
          p_signature_image: signatureData,
        });
        if (rpcError) throw rpcError;
        if (rpcResult?.error) throw new Error(rpcResult.error);
      }

      await supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user.id,
        p_type_acteur: isSoignant ? 'SOIGNANT' : 'ADMIN_ETABLISSEMENT',
        p_action: 'CONTRAT_SIGNE',
        p_type_ressource: 'contrat',
        p_id_ressource: contrat.id,
        p_cle_s3: null,
        p_details: { numero: contrat.numero_contrat, type: contrat.type_contrat, role_signataire: isSoignant ? 'soignant' : 'etablissement' },
        p_ip: null,
        p_navigateur: navigator.userAgent,
      });

      afficherNotification({ type: 'succes', message: 'Contrat signé avec succès !' });
      setShowCheckAnim(true);
      const { data: updated } = await supabase.from('contrats_mission').select('id, mission_id, numero_contrat, type_contrat, statut, contenu_html, soignant_id, etablissement_id, signature_soignant, signature_soignant_le, signature_etablissement, signature_etablissement_le, signature_image_soignant, signature_image_etablissement').eq('id', contrat.id).single();
      setContrat(updated);

      // Check if both parties have now signed → send CONTRAT_SIGNE emails
      if (updated) {
        const bothSigned = updated.signature_soignant && updated.signature_etablissement;
        if (bothSigned) {
          // Fetch mission name for email
          const { data: missionData } = await supabase.from('missions').select('intitule, soignant_assigne_id, etablissement_id').eq('id', contrat.mission_id).single();
          const missionName = missionData?.intitule || 'Mission';

          // Email to current user
          supabase.functions.invoke('send-email', {
            body: {
              type: 'CONTRAT_SIGNE',
              data: { prenom: user.prenom || '', mission: missionName, contrat_id: contrat.id },
              destinataire_id: user.id,
            },
          }).catch(() => {});

          // Email to the other party via edge function (service handles authorization)
          // We fetch the other party's email from the etablissement table
          if (missionData?.etablissement_id && isSoignant) {
            {
              supabase.functions.invoke('send-email', {
                body: {
                  type: 'CONTRAT_SIGNE',
                  data: { mission: missionName, contrat_id: contrat.id },
                  destinataire_id: missionData.etablissement_id,
                },
              }).catch(() => {});
            }
          }
        }
      }
    } catch (err) {
      afficherNotification({ type: 'erreur', message: 'Erreur lors de la signature' });
    } finally {
      setSigning(false);
    }
  };

  if (loading) return <LayoutApp role={role}><ChargementPage /></LayoutApp>;
  if (!contrat) return <LayoutApp role={role}><p className="text-center text-muted-foreground py-12">Contrat introuvable</p></LayoutApp>;

  const isSoignant = contrat.soignant_id === user?.id;
  const dejaSigneParMoi = isSoignant ? contrat.signature_soignant : contrat.signature_etablissement;

  return (
    <LayoutApp role={role}>
      <CheckAnimation active={showCheckAnim} />
      <button onClick={() => navigate(-1)} className="flex items-center gap-1 text-sm text-primary mb-4 hover:underline">
        ← Retour
      </button>
      <div className="max-w-3xl mx-auto">
        {contrat.statut === 'ANNULE' && (
          <div className="bg-destructive/10 border border-destructive/30 rounded-xl p-4 mb-4 text-center">
            <p className="text-sm font-semibold text-destructive">❌ Ce contrat a été annulé suite à l'annulation de la mission.</p>
          </div>
        )}
        {contrat.statut === 'EXPIRE' && (
          <div className="bg-warning/10 border border-warning/30 rounded-xl p-4 mb-4 text-center">
            <p className="text-sm font-semibold text-warning">⏰ Contrat expiré — non signé dans les 72h. La mission a été annulée.</p>
          </div>
        )}
        <div className="flex items-center gap-3 mb-4">
          <FileText className="h-6 w-6 text-primary" />
          <div>
            <h1 className="text-xl font-bold text-foreground">Contrat {contrat.numero_contrat}</h1>
            <p className="text-sm text-muted-foreground flex items-center gap-2">
              Statut : {contrat.statut === 'SIGNE_COMPLET'
                ? (contrat.mode_signature === 'YOUSIGN' ? '🔒 Signé via Yousign (eIDAS) ✅' : '✅ Signé')
                : contrat.statut === 'ANNULE' ? '❌ Annulé'
                : '⏳ En attente de signatures'}
              {contrat.mode_signature === 'YOUSIGN' && contrat.statut !== 'SIGNE_COMPLET' && (
                <span className="text-[10px] font-bold bg-primary text-primary-foreground px-1.5 py-0.5 rounded">eIDAS</span>
              )}
            </p>
          </div>
        </div>

        {/* Contract HTML render */}
        <div className="card-base mb-4 max-h-[60vh] overflow-y-auto contrat-print">
          {contrat.contenu_html ? (
            <div dangerouslySetInnerHTML={{ __html: sanitizeHTML(contrat.contenu_html) }} className="prose prose-sm max-w-none text-foreground" />
          ) : (
            <p className="text-center text-muted-foreground py-8">Le contenu du contrat n'est pas encore disponible.</p>
          )}
        </div>

        {/* Signatures section */}
        <div className="card-base mb-4 space-y-4">
          <h3 className="font-bold text-foreground">Signatures</h3>

          {/* Etablissement signature */}
          <div className="space-y-2">
            <div className="flex items-center gap-3">
              {contrat.signature_etablissement ? (
                <CheckCircle className="h-5 w-5 text-success" />
              ) : (
                <Clock className="h-5 w-5 text-warning" />
              )}
              <span className="text-sm text-foreground">
                Établissement : {contrat.signature_etablissement
                  ? `✅ Signé le ${format(new Date(contrat.signature_etablissement_le), "dd/MM/yyyy 'à' HH:mm", { locale: fr })}`
                  : '⏳ En attente'}
              </span>
            </div>
            {contrat.signature_image_etablissement && (
              <img src={contrat.signature_image_etablissement} alt="Signature établissement" className="h-16 border border-border rounded bg-background ml-8" />
            )}
          </div>

          {/* Soignant signature */}
          <div className="space-y-2">
            <div className="flex items-center gap-3">
              {contrat.signature_soignant ? (
                <CheckCircle className="h-5 w-5 text-success" />
              ) : (
                <Clock className="h-5 w-5 text-warning" />
              )}
              <span className="text-sm text-foreground">
                Soignant(e) : {contrat.signature_soignant
                  ? `✅ Signé le ${format(new Date(contrat.signature_soignant_le), "dd/MM/yyyy 'à' HH:mm", { locale: fr })}`
                  : '⏳ En attente'}
              </span>
            </div>
            {contrat.signature_image_soignant && (
              <img src={contrat.signature_image_soignant} alt="Signature soignant" className="h-16 border border-border rounded bg-background ml-8" />
            )}
          </div>
        </div>

        {/* Signing section */}
        {!dejaSigneParMoi && contrat.statut !== 'SIGNE_COMPLET' && contrat.statut !== 'ANNULE' && contrat.statut !== 'EXPIRE' && (
          <div className="card-base space-y-4">
            <h3 className="font-bold text-foreground">Votre signature</h3>

            {/* Yousign active — show status */}
            {contrat.mode_signature === 'YOUSIGN' ? (
              <div className="rounded-xl border border-primary/30 bg-primary/5 p-4 space-y-3">
                <div className="flex items-center gap-2">
                  <Shield className="h-5 w-5 text-primary" />
                  <span className="font-semibold text-foreground">🔒 Signature Yousign en cours</span>
                </div>
                <p className="text-sm text-muted-foreground">
                  La procédure de signature électronique eIDAS est en cours. Vous recevrez un email de Yousign pour signer le contrat.
                </p>
                {yousignUrl && (
                  <a
                    href={yousignUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="btn-primary inline-flex items-center gap-2"
                  >
                    Signer avec Yousign <ExternalLink className="h-4 w-4" />
                  </a>
                )}
                <p className="text-xs text-muted-foreground">
                  Vous pouvez aussi utiliser la <button type="button" onClick={() => handleFallbackCanvas()} className="underline text-primary">signature manuscrite</button> si vous préférez.
                </p>
              </div>
            ) : (
              <>
                {/* Mode selector */}
                <div className="space-y-3">
                  <p className="text-sm font-medium text-foreground">Choisissez votre mode de signature :</p>
                  <RadioGroup value={modeSignature} onValueChange={(v) => setModeSignature(v as 'CANVAS' | 'YOUSIGN')}>
                    <label className="flex items-center gap-3 p-3 rounded-lg border border-border cursor-pointer hover:bg-accent/50 transition-colors">
                      <RadioGroupItem value="CANVAS" />
                      <div>
                        <span className="text-sm font-medium text-foreground">✍️ Signature manuscrite (canvas)</span>
                        <p className="text-xs text-muted-foreground">Signez directement sur votre écran</p>
                      </div>
                    </label>
                    <label className="flex items-center gap-3 p-3 rounded-lg border border-primary/40 bg-primary/5 cursor-pointer hover:bg-primary/10 transition-colors">
                      <RadioGroupItem value="YOUSIGN" />
                      <div className="flex-1">
                        <div className="flex items-center gap-2">
                          <span className="text-sm font-medium text-foreground">🔒 Signature électronique Yousign</span>
                          <span className="text-[10px] font-bold bg-primary text-primary-foreground px-1.5 py-0.5 rounded">eIDAS</span>
                          <span className="text-[10px] text-muted-foreground italic">(recommandée)</span>
                        </div>
                        <p className="text-xs text-muted-foreground">Signature à valeur juridique renforcée, conforme au règlement européen eIDAS.</p>
                      </div>
                    </label>
                  </RadioGroup>
                </div>

                {modeSignature === 'YOUSIGN' ? (
                  <div className="space-y-3">
                    <button
                      onClick={handleYousignCreate}
                      disabled={yousignLoading}
                      className="btn-primary w-full flex items-center justify-center gap-2 disabled:opacity-50"
                    >
                      <Shield className="h-4 w-4" />
                      {yousignLoading ? 'Initialisation Yousign...' : '🔒 Lancer la signature Yousign'}
                    </button>
                  </div>
                ) : (
                  <>
                    <SignatureCanvas onSave={(data) => setSignatureData(data)} />

                    {signatureData && (
                      <div className="flex items-center gap-2 text-xs text-green-700">
                        <CheckCircle className="h-3.5 w-3.5" /> Signature validée
                      </div>
                    )}

                    <label className="flex items-start gap-3 cursor-pointer">
                      <Checkbox checked={accepte} onCheckedChange={(v) => setAccepte(!!v)} />
                      <span className="text-sm text-foreground">Je reconnais avoir lu et accepté les termes de ce contrat.</span>
                    </label>

                    <div className="flex gap-3">
                      <button
                        onClick={() => setShowConfirmSign(true)}
                        disabled={!accepte || signing || !signatureData}
                        className="btn-primary flex-1 disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
                      >
                        <FileText className="h-4 w-4" /> {signing ? 'Signature...' : '✍️ Signer définitivement'}
                      </button>
                      <button onClick={() => window.print()} className="btn-secondary flex items-center gap-2">
                        <Printer className="h-4 w-4" /> Imprimer
                      </button>
                    </div>

                    <ModalConfirmation
                      ouvert={showConfirmSign}
                      onFermer={() => setShowConfirmSign(false)}
                      onConfirmer={handleSigner}
                      titre="Confirmer la signature"
                      message="Cette action est irréversible. En signant ce contrat, vous vous engagez légalement. Souhaitez-vous continuer ?"
                      labelConfirmer="✍️ Signer"
                      variante="primaire"
                    />
                  </>
                )}
              </>
            )}
          </div>
        )}

        {dejaSigneParMoi && (
          <div className="space-y-4">
            <div className="rounded-xl bg-green-50 dark:bg-green-950/20 border border-green-200 dark:border-green-800 p-4 text-center">
              <p className="text-sm font-semibold text-green-700 dark:text-green-400">✅ Vous avez déjà signé ce contrat</p>
            </div>
            {/* A1: Rappel DUE — after establishment signature */}
            {!isSoignant && (contrat.statut === 'SIGNE_ETABLISSEMENT' || contrat.statut === 'SIGNE_COMPLET') && (
              <BandeauRappelDUE contratId={contrat.id} dueEffectuee={contrat.due_effectuee} dueEffectueeLe={contrat.due_effectuee_le} />
            )}
          </div>
        )}

        <p className="text-[10px] text-muted-foreground/60 italic text-center mt-4">
          Art. L.1242-12 du Code du travail — Ce contrat est obligatoire pour toute mission.
          Signature électronique simple. Signature qualifiée eIDAS prochainement disponible.
        </p>
      </div>
    </LayoutApp>
  );
}
