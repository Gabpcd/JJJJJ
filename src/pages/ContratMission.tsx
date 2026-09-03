import React, { useState, useEffect } from 'react';
import { capturerErreurSentry } from '@/lib/sentry';
import { telechargerOuPartager } from '@/lib/telechargement';
import { usePageTitle } from '@/hooks/usePageTitle';
import { CheckAnimation } from '@/components/CheckAnimation';
import { useParams, useNavigate } from 'react-router-dom';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { useAuth } from '@/contexts/AuthContext';
import { useRole } from '@/hooks/useRole';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { FileText, Printer, CheckCircle, Clock, Shield, Download } from 'lucide-react';
import { BandeauRappelDPAE } from '@/components/BandeauRappelDPAE';
import { Countdown72hSignature } from '@/components/Countdown72hSignature';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { Checkbox } from '@/components/ui/checkbox';
import { UserRole } from '@/lib/types';
import SignatureCanvas from '@/components/SignatureCanvas';
import { SignerContratOtp } from '@/components/SignerContratOtp';
import { CertificatSignature } from '@/components/CertificatSignature';
import { DPAEStatus } from '@/components/DPAEStatus';
import { sanitizeHTML } from '@/lib/sanitize';
import { ModalConfirmation } from '@/components/ModalConfirmation';
import { logger } from '@/lib/logger';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { sha256Hex } from '@/lib/crypto-hash';
import {
  choisirContenuContratAffiche,
  contratNecessiteRenduServeur,
  contientVariablesContratNonRendues,
} from '@/lib/contratMissionUi';

function escapeContractValue(value: unknown): string {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function formatContractDate(value?: string | null): string {
  if (!value) return '—';
  return format(new Date(value), "dd/MM/yyyy 'à' HH:mm", { locale: fr });
}

function formatContractBirthDate(value?: string | null): string {
  if (!value) return 'non renseignée';
  return format(new Date(`${value.slice(0, 10)}T12:00:00`), 'dd/MM/yyyy', { locale: fr });
}

function replaceTemplateVariables(template: string, values: Record<string, string>): string {
  return template.replace(/\{\{\s*([^}]+?)\s*\}\}/g, (_, rawKey) => values[rawKey.trim()] ?? '');
}

function buildFallbackContractHtml({
  contrat,
  mission,
  soignant,
  etablissement,
  templateHtml,
}: {
  contrat: any;
  mission?: any;
  soignant?: any;
  etablissement?: any;
  templateHtml?: string | null;
}) {
  const valeurs: Record<string, string> = {
    numero_contrat: escapeContractValue(contrat?.numero_contrat ?? '—'),
    type_contrat: escapeContractValue(contrat?.type_contrat ?? '—'),
    mission_intitule: escapeContractValue(mission?.intitule ?? 'Mission'),
    mission_service: escapeContractValue(mission?.service ?? '—'),
    mission_debut: escapeContractValue(formatContractDate(mission?.debut_le)),
    mission_fin: escapeContractValue(formatContractDate(mission?.fin_le)),
    mission_duree_heures: escapeContractValue(mission?.duree_heures ?? '—'),
    intitule_mission: escapeContractValue(mission?.intitule ?? 'Mission'),
    profession: escapeContractValue(soignant?.profession ?? '—'),
    debut_le: escapeContractValue(formatContractDate(mission?.debut_le)),
    fin_le: escapeContractValue(formatContractDate(mission?.fin_le)),
    duree_heures: escapeContractValue(mission?.duree_heures ?? '—'),
    taux_horaire: mission?.taux_horaire_base != null ? `${Number(mission.taux_horaire_base).toFixed(2)} €` : '—',
    etablissement_nom: escapeContractValue(etablissement?.nom ?? '—'),
    etablissement_siret: escapeContractValue(etablissement?.siret ?? '—'),
    etablissement_finess: escapeContractValue(etablissement?.finess ?? '—'),
    etablissement_email: escapeContractValue(etablissement?.email_contact ?? '—'),
    etablissement_telephone: escapeContractValue(etablissement?.telephone_contact ?? '—'),
    etablissement_ville: escapeContractValue(etablissement?.adresse_ville ?? '—'),
    etablissement_adresse: escapeContractValue([
      etablissement?.adresse_rue,
      etablissement?.adresse_code_postal,
      etablissement?.adresse_ville,
    ].filter(Boolean).join(', ') || '—'),
    soignant_nom: escapeContractValue(soignant?.nom ?? '—'),
    soignant_prenom: escapeContractValue(soignant?.prenom ?? '—'),
    soignant_profession: escapeContractValue(soignant?.profession ?? '—'),
    soignant_rpps: escapeContractValue(soignant?.numero_rpps ?? '—'),
    soignant_date_naissance: escapeContractValue(formatContractBirthDate(soignant?.date_naissance)),
    soignant_adresse: escapeContractValue([
      soignant?.adresse_rue,
      soignant?.adresse_code_postal,
      soignant?.adresse_ville,
    ].filter(Boolean).join(', ') || 'non renseignée'),
    motif_cdd: escapeContractValue(contrat?.motif_cdd || "remplacement / surcroît temporaire d'activité"),
    convention_collective: escapeContractValue(etablissement?.convention_collective || "CCN applicable à l'établissement"),
    periode_essai_libelle: escapeContractValue(`${Number(contrat?.periode_essai_jours || 1)} ${Number(contrat?.periode_essai_jours || 1) === 1 ? 'jour' : 'jours'}`),
    periode_essai_jours: escapeContractValue(contrat?.periode_essai_jours || 1),
    caisse_retraite: escapeContractValue(etablissement?.caisse_retraite || 'AGIRC-ARRCO'),
    regime_prevoyance: escapeContractValue(etablissement?.regime_prevoyance || "celui de l'employeur"),
    date_signature: escapeContractValue(new Date().toLocaleDateString('fr-FR', { timeZone: 'Europe/Paris' })),
  };

  const templateReconstruit = templateHtml
    ? replaceTemplateVariables(templateHtml, valeurs).replace(/\{\{\s*[^}]+\s*\}\}/g, '')
    : '';

  if (templateReconstruit.trim()) {
    return templateReconstruit;
  }

  return `
    <article>
      <h1>Contrat ${valeurs.numero_contrat}</h1>
      <p><strong>Type :</strong> ${valeurs.type_contrat}</p>
      <p>Version reconstituée automatiquement à partir des données de mission enregistrées.</p>
      <h2>Établissement</h2>
      <p><strong>${valeurs.etablissement_nom}</strong><br/>SIRET : ${valeurs.etablissement_siret}<br/>Adresse : ${valeurs.etablissement_adresse}<br/>Email : ${valeurs.etablissement_email}<br/>Téléphone : ${valeurs.etablissement_telephone}</p>
      <h2>Soignant·e</h2>
      <p><strong>${valeurs.soignant_nom}</strong><br/>Profession : ${valeurs.soignant_profession}<br/>RPPS : ${valeurs.soignant_rpps}</p>
      <h2>Mission concernée</h2>
      <p><strong>${valeurs.mission_intitule}</strong><br/>Service : ${valeurs.mission_service}<br/>Début : ${valeurs.mission_debut}<br/>Fin : ${valeurs.mission_fin}<br/>Durée prévue : ${valeurs.mission_duree_heures} h<br/>Taux horaire : ${valeurs.taux_horaire}</p>
      <h2>Signatures</h2>
      <ul>
        <li>Établissement : ${contrat?.signature_etablissement ? `signé le ${escapeContractValue(formatContractDate(contrat.signature_etablissement_le))}` : 'en attente'}</li>
        <li>Soignant·e : ${contrat?.signature_soignant ? `signé le ${escapeContractValue(formatContractDate(contrat.signature_soignant_le))}` : 'en attente'}</li>
      </ul>
    </article>
  `;
}

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
  // Signature : OTP_SMS (JOLENE_OTP) recommandé ou CANVAS manuscrit.
  const [modeSignature, setModeSignature] = useState<'CANVAS' | 'OTP_SMS'>('OTP_SMS');
  const [smsExterneDesactive, setSmsExterneDesactive] = useState(false);
  const [fallbackHtml, setFallbackHtml] = useState('');
  const [hashContratAffiche, setHashContratAffiche] = useState<string | null>(null);
  const [renduContratEnCours, setRenduContratEnCours] = useState(false);
  const [erreurRenduContrat, setErreurRenduContrat] = useState<string | null>(null);

  const { role: serverRole } = useRole();
  const role: UserRole = serverRole === 'INCONNU'
      ? 'SOIGNANT'
      : serverRole;

  useEffect(() => {
    if (!id) return;
    const load = async () => {
      const { data: dataRaw } = await supabase
        .from('contrats_mission')
        .select('*' as any)
        .eq('id', id)
        .single();
      const data = dataRaw as any;

      if (data) {
        const [missionRes, soignantRes, etabRes, etabCompteRes, templateRes] = await Promise.all([
          supabase
            .from('missions')
            .select('id, intitule, service, debut_le, fin_le, duree_heures, taux_horaire_base')
            .eq('id', data.mission_id)
            .maybeSingle(),
          supabase
            .from('soignants')
            .select('prenom, nom, profession, numero_rpps, est_compte_test, date_naissance, adresse_rue, adresse_code_postal, adresse_ville')
            .eq('id', data.soignant_id)
            .maybeSingle(),
          supabase.rpc('fn_etablissement_pour_mission' as any, { p_etablissement_id: data.etablissement_id }).then(({ data: d, error: e }) => ({
            data: Array.isArray(d) ? d[0] || null : d,
            error: e,
          })),
          supabase
            .from('etablissements')
            .select('id, est_compte_test')
            .eq('id', data.etablissement_id)
            .maybeSingle(),
          supabase
            .from('templates_contrat')
            .select('contenu_html')
            .eq('type_contrat', data.type_contrat)
            .eq('est_actif', true)
            .maybeSingle(),
        ]);

        setFallbackHtml(buildFallbackContractHtml({
          contrat: data,
          mission: missionRes.data,
          soignant: soignantRes.data,
          etablissement: etabRes.data,
          templateHtml: templateRes.data?.contenu_html,
        }));
        const compteTestCourant = (
          data.soignant_id === user?.id
          && soignantRes.data?.est_compte_test === true
        ) || (
          data.etablissement_id === user?.id
          && etabCompteRes.data?.est_compte_test === true
        );
        setSmsExterneDesactive(compteTestCourant);
        if (compteTestCourant) setModeSignature('CANVAS');
      } else {
        setFallbackHtml('');
      }

      setContrat(data);
      setLoading(false);
    };
    load();
  }, [id, user?.id]);

  // Calcul du hash SHA-256 réel du contenu HTML affiché (preuve d'intégrité
  // signée avec l'OTP). Si le contrat a un hash_document figé côté serveur
  // (rendu via generate-contrat-mission-pdf), on l'utilise. Sinon fallback
  // sur un hash calculé localement.
  useEffect(() => {
    const contenuServeurIncomplet = contientVariablesContratNonRendues(contrat?.contenu_html);
    if (contrat?.hash_document && !contenuServeurIncomplet) {
      setHashContratAffiche(contrat.hash_document);
      return;
    }
    const html = choisirContenuContratAffiche(contrat?.contenu_html, fallbackHtml);
    if (!html) {
      setHashContratAffiche(null);
      return;
    }
    let cancelled = false;
    sha256Hex(html).then(h => {
      if (!cancelled) setHashContratAffiche(h);
    }).catch(() => {
      if (!cancelled) setHashContratAffiche(null);
    });
    return () => { cancelled = true; };
  }, [contrat?.contenu_html, contrat?.hash_document, fallbackHtml]);

  // Auto-trigger : si le contrat n'a pas encore été figé en Storage,
  // appelle l'edge function pour le rendre (idempotent côté serveur grâce
  // à upsert: false sur le path timestamped).
  useEffect(() => {
    if (!contrat?.id) return;
    if (contrat.statut === 'ANNULE' || contrat.statut === 'EXPIRE' || contrat.statut === 'REFUSE') return;
    const renduNecessaire = contratNecessiteRenduServeur(contrat.contenu_html, contrat.storage_path);
    if (!renduNecessaire) return;
    let cancelled = false;
    setRenduContratEnCours(true);
    setErreurRenduContrat(null);
    supabase.functions.invoke('generate-contrat-mission-pdf', {
      body: { contrat_id: contrat.id },
    }).then(({ data, error }) => {
      if (cancelled) return;
      if (error || !(data as any)?.success) {
        const motifBrut = typeof (data as any)?.error === 'string'
          ? (data as any).error
          : error?.message;
        const motifServeur = motifBrut ? ` ${String(motifBrut).slice(0, 180)}` : '';
        setErreurRenduContrat(`Le document contractuel final n’a pas pu être préparé.${motifServeur} Réessayez avant de signer.`);
        return;
      }
      // Reload le contrat pour récupérer storage_path + hash
      return supabase.from('contrats_mission')
        .select('*' as any)
        .eq('id', contrat.id)
        .single()
        .then(({ data: updated, error: reloadError }) => {
          if (cancelled) return;
          if (reloadError || !updated || contientVariablesContratNonRendues((updated as any).contenu_html)) {
            setErreurRenduContrat('Le document contractuel final est encore incomplet. Réessayez avant de signer.');
            return;
          }
          setContrat(updated);
        });
    }).catch(() => {
      if (!cancelled) setErreurRenduContrat('Le document contractuel final n’a pas pu être préparé. Réessayez avant de signer.');
    }).finally(() => {
      if (!cancelled) setRenduContratEnCours(false);
    });
    return () => { cancelled = true; };
  }, [contrat?.contenu_html, contrat?.id, contrat?.storage_path, contrat?.statut]);

  const handleDownloadContract = async () => {
    const contractHtml = choisirContenuContratAffiche(contrat?.contenu_html, fallbackHtml);
    if (!contractHtml) {
      afficherNotification({ type: 'erreur', message: 'Aucun contrat téléchargeable pour le moment.' });
      return;
    }

    const documentHtml = `<!doctype html>
      <html lang="fr">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <title>${escapeContractValue(contrat?.numero_contrat ?? 'Contrat')}</title>
          <style>
            body { font-family: Arial, sans-serif; color: #0f172a; line-height: 1.6; padding: 32px; }
            h1, h2, h3 { color: #0f172a; }
            article { max-width: 900px; margin: 0 auto; }
          </style>
        </head>
        <body>${contractHtml}</body>
      </html>`;

    await telechargerOuPartager(documentHtml, `${contrat?.numero_contrat ?? 'contrat'}.html`, 'text/html');
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
          }).catch((err) => { logger.warn('[ContratMission] send-email contrat signé failed', err); });

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
              }).catch((err) => { logger.warn('[ContratMission] send-email other party failed', err); });
            }
          }
        }
      }
    } catch (err) {
      capturerErreurSentry(err, 'ContratMission', 'signature_contrat');
      afficherNotification({ type: 'erreur', message: 'Erreur lors de la signature' });
    } finally {
      setSigning(false);
    }
  };

  if (loading) return <LayoutApp role={role}><ChargementPage /></LayoutApp>;
  if (!contrat) return <LayoutApp role={role}><p className="text-center text-muted-foreground py-12">Contrat introuvable</p></LayoutApp>;

  const isSoignant = contrat.soignant_id === user?.id;
  const dejaSigneParMoi = isSoignant ? contrat.signature_soignant : contrat.signature_etablissement;
  const contractHtml = choisirContenuContratAffiche(contrat.contenu_html, fallbackHtml);
  const contratServeurPret = !!contrat.storage_path
    && !!contrat.hash_document
    && !contientVariablesContratNonRendues(contrat.contenu_html)
    && !renduContratEnCours
    && !erreurRenduContrat;

  return (
    <LayoutApp role={role}>
      <CheckAnimation active={showCheckAnim} />
      <button onClick={() => navigate(-1)} className="app-inline-back flex items-center gap-1 text-sm text-primary mb-4 hover:underline">
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
        {contrat.statut === 'REFUSE' && (
          <div className="bg-destructive/10 border border-destructive/30 rounded-xl p-4 mb-4 text-center">
            <p className="text-sm font-semibold text-destructive">❌ Ce contrat a été refusé par l'une des parties.</p>
          </div>
        )}
        {!dejaSigneParMoi && (contrat.signature_soignant || contrat.signature_etablissement)
         && contrat.statut !== 'SIGNE_COMPLET' && contrat.statut !== 'ANNULE'
         && contrat.statut !== 'EXPIRE' && contrat.statut !== 'REFUSE' && (
          <div className="bg-amber-50 dark:bg-amber-950/30 border border-amber-200 dark:border-amber-800 rounded-xl p-4 mb-4">
            <p className="text-sm font-semibold text-amber-900 dark:text-amber-200">⏳ L'autre partie a déjà signé</p>
            <p className="text-xs text-amber-800 dark:text-amber-300 mt-1">
              Vous pouvez signer maintenant. Le contrat devient complet dès que les deux signatures sont enregistrées, quel que soit leur ordre.
            </p>
          </div>
        )}
        {/* Sprint 6 PR 6 — Fix P1-6 : Countdown 72h signature */}
        {contrat.statut !== 'SIGNE_COMPLET' &&
         contrat.statut !== 'ANNULE' &&
         contrat.statut !== 'EXPIRE' &&
         contrat.statut !== 'REFUSE' &&
         (contrat as any).cree_le && (
          <div className="mb-4">
            <Countdown72hSignature contratCreeLe={(contrat as any).cree_le} />
          </div>
        )}

        <div className="flex items-center gap-3 mb-4">
          <FileText className="h-6 w-6 text-primary" />
          <div>
            <h1 className="text-xl font-bold text-foreground">Contrat {contrat.numero_contrat}</h1>
            <p className="text-sm text-muted-foreground flex items-center gap-2">
              Statut : {contrat.statut === 'SIGNE_COMPLET'
                ? '✅ Signé'
                : contrat.statut === 'ANNULE' ? '❌ Annulé'
                : '⏳ En attente de signatures'}
            </p>
          </div>
        </div>

        <div className="flex flex-wrap gap-3 mb-4">
          <button
            onClick={handleDownloadContract}
            disabled={!contractHtml}
            className="btn-secondary flex items-center gap-2 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            <Download className="h-4 w-4" /> Télécharger le contrat
          </button>
          <button onClick={() => window.print()} className="btn-secondary flex items-center gap-2">
            <Printer className="h-4 w-4" /> Imprimer
          </button>
        </div>

        {/* Contract HTML render */}
        <div className="card-base mb-4 max-h-[60vh] overflow-y-auto contrat-print">
          {contrat.contenu_html_rendu_le && (
            <p className="text-[10px] text-muted-foreground mb-2 italic flex items-center gap-1">
              <Shield className="h-3 w-3" />
              Document officiel figé le {format(new Date(contrat.contenu_html_rendu_le), "dd/MM/yyyy 'à' HH:mm", { locale: fr })}
              {contrat.hash_document && ` — empreinte ${contrat.hash_document.slice(0, 8)}…${contrat.hash_document.slice(-4)}`}
            </p>
          )}
          {!contrat.contenu_html && contractHtml && (
            <p className="text-xs text-muted-foreground mb-4">
              Le document original n'était pas stocké ; cette version a été reconstituée automatiquement à partir des données de la mission.
            </p>
          )}
          {contractHtml ? (
            <div dangerouslySetInnerHTML={{ __html: sanitizeHTML(contractHtml) }} className="prose prose-sm max-w-none text-foreground" />
          ) : (
            <p className="text-center text-muted-foreground py-8">Le contenu du contrat n'est pas encore disponible.</p>
          )}
        </div>

        {/* DPAE : l'employeur peut la préparer dès la création du CDD. */}
        {(role === 'ADMIN_ETABLISSEMENT' || role === 'ADMIN_PLATEFORME' || role === 'ADMIN_GROUPE') &&
         !['ANNULE', 'EXPIRE', 'REFUSE'].includes(contrat.statut) &&
         contrat.type_contrat && ['CDD', 'SALARIE'].includes(contrat.type_contrat) && (
          <div className="mb-4">
            <DPAEStatus
              contratId={contrat.id}
              typeContrat={contrat.type_contrat}
              dpaeNumero={(contrat as any).dpae_numero}
            />
          </div>
        )}

        {/* Certificat de signature (visible parties + admin) une fois signé */}
        {(contrat.signature_soignant || contrat.signature_etablissement) && (
          <div className="mb-4">
            <CertificatSignature
              contratId={contrat.id}
              variant={role === 'ADMIN_PLATEFORME' ? 'detail' : 'resume'}
            />
          </div>
        )}

        {/* Signatures section */}
        <div className="card-base mb-4 space-y-4">
          <h3 className="font-bold text-foreground">Signatures</h3>

          {/* Etablissement signature */}
          <div className="space-y-2">
            <div className="flex items-center gap-3">
              {(contrat.statut === 'SIGNE_COMPLET' || contrat.signature_etablissement) ? (
                <CheckCircle className="h-5 w-5 text-success" />
              ) : (
                <Clock className="h-5 w-5 text-warning" />
              )}
              <span className="text-sm text-foreground">
                Établissement : {(contrat.statut === 'SIGNE_COMPLET' || contrat.signature_etablissement)
                  ? `✅ Signé${contrat.signature_etablissement_le ? ` le ${format(new Date(contrat.signature_etablissement_le), "dd/MM/yyyy 'à' HH:mm", { locale: fr })}` : ''}`
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
              {(contrat.statut === 'SIGNE_COMPLET' || contrat.signature_soignant) ? (
                <CheckCircle className="h-5 w-5 text-success" />
              ) : (
                <Clock className="h-5 w-5 text-warning" />
              )}
              <span className="text-sm text-foreground">
                Soignant(e) : {(contrat.statut === 'SIGNE_COMPLET' || contrat.signature_soignant)
                  ? `✅ Signé${contrat.signature_soignant_le ? ` le ${format(new Date(contrat.signature_soignant_le), "dd/MM/yyyy 'à' HH:mm", { locale: fr })}` : ''}`
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

                {(renduContratEnCours || erreurRenduContrat) && (
                  <div className="rounded-lg border border-warning/40 bg-warning/10 p-3 text-sm" role={erreurRenduContrat ? 'alert' : 'status'}>
                    {erreurRenduContrat || 'Préparation du document contractuel final…'}
                  </div>
                )}

                {/* Mode selector */}
                <div className="space-y-3">
                  <p className="text-sm font-medium text-foreground">Choisissez votre mode de signature :</p>
                  {smsExterneDesactive && (
                    <div className="rounded-lg border border-info/30 bg-info/5 p-3 text-xs text-muted-foreground" role="note">
                      Compte de démonstration : aucun SMS réel n’est envoyé. Utilisez la signature manuscrite ci-dessous.
                    </div>
                  )}
                  <RadioGroup value={modeSignature} onValueChange={(v) => setModeSignature(v as 'CANVAS' | 'OTP_SMS')}>
                    {!smsExterneDesactive && <label className="flex items-center gap-3 p-3 rounded-lg border border-primary/40 bg-primary/5 cursor-pointer hover:bg-primary/10 transition-colors">
                      <RadioGroupItem value="OTP_SMS" className="focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2" />
                      <div className="flex-1">
                        <div className="flex items-center gap-2">
                          <span className="text-sm font-medium text-foreground">📱 Signature électronique OTP SMS</span>
                          <span className="text-[10px] font-bold bg-primary text-primary-foreground px-1.5 py-0.5 rounded">RECOMMANDÉE</span>
                        </div>
                        <p className="text-xs text-muted-foreground">Code SMS à 6 chiffres + horodatage + hash document. Conforme art. 1366-1367 Code civil.</p>
                      </div>
                    </label>}
                    <label className="flex items-center gap-3 p-3 rounded-lg border border-border cursor-pointer hover:bg-accent/50 transition-colors">
                      <RadioGroupItem value="CANVAS" className="focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2" />
                      <div>
                        <span className="text-sm font-medium text-foreground">✍️ Signature manuscrite (canvas)</span>
                        <p className="text-xs text-muted-foreground">Signez directement sur votre écran</p>
                      </div>
                    </label>
                  </RadioGroup>
                </div>

                {modeSignature === 'OTP_SMS' ? (
                  <SignerContratOtp
                    contratId={contrat.id}
                    hashDocument={hashContratAffiche}
                    onSigne={async () => {
                      // Refresh contrat après signature
                      const { data: updated } = await supabase
                        .from('contrats_mission')
                        .select('*' as any)
                        .eq('id', contrat.id)
                        .single();
                      if (updated) setContrat(updated as any);
                    }}
                  />
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
                        disabled={!accepte || signing || !signatureData || !contratServeurPret}
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
          </div>
        )}

        {dejaSigneParMoi && (
          <div className="space-y-4">
            <div className="rounded-xl bg-green-50 dark:bg-green-950/20 border border-green-200 dark:border-green-800 p-4 text-center">
              <p className="text-sm font-semibold text-green-700 dark:text-green-400">✅ Vous avez déjà signé ce contrat</p>
            </div>
            {/* Rappel DPAE — indépendant de l'ordre des signatures. */}
            {!isSoignant && !['ANNULE', 'EXPIRE', 'REFUSE'].includes(contrat.statut) && (
              <BandeauRappelDPAE contratId={contrat.id} dpaeEffectuee={contrat.dpae_effectuee} dpaeEffectueeLe={contrat.dpae_effectuee_le} typeContrat={contrat.type_contrat} />
            )}
          </div>
        )}

        <p className="text-[10px] text-muted-foreground/60 italic text-center mt-4">
          {['CDD', 'SALARIE'].includes(contrat.type_contrat || '')
            ? 'Contrat salarié écrit — art. L.1242-12 du Code du travail. '
            : 'Contrat de prestation entre l’établissement et le professionnel libéral. '}
          Signature électronique simple. Les montants prévisionnels sont régularisés selon les heures validées et les éventuelles corrections contradictoires.
        </p>
      </div>
    </LayoutApp>
  );
}
