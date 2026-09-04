import React, { useCallback, useState, useEffect } from 'react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementAdmin } from '@/components/admin/ChargementAdmin';
import { AdminFilterBar } from '@/components/admin/AdminFilterBar';
import { AdminPageHeader } from '@/components/admin/AdminPageHeader';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { supabase } from '@/integrations/supabase/client';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { CardY2K, CardY2KContent } from '@/components/y2k/CardY2K';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { toast } from 'sonner';
import { FileCheck, MessageSquare, Check, X, Eye, ShieldAlert, EyeOff, GitBranch, Plus } from 'lucide-react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { LitigesFilters } from '@/components/admin/litiges/LitigesFilters';
import { LitigesList, filtrerEtTrier } from '@/components/admin/litiges/LitigesList';
import { LitigePreuvesPanel } from '@/components/admin/litiges/LitigePreuvesPanel';
import { LitigeResolutionModal } from '@/components/admin/litiges/LitigeResolutionModal';
import { AvoirsList } from '@/components/admin/litiges/AvoirsList';
import { LegacyRecategorisation } from '@/components/admin/litiges/LegacyRecategorisation';
import { MediationBanner } from '@/components/admin/litiges/MediationBanner';
import { RefundsQueueWidget } from '@/components/admin/litiges/RefundsQueueWidget';
import { telechargerCsv } from '@/components/admin/litiges/csv';
import { Download, Receipt, RefreshCw, Tag } from 'lucide-react';
import {
  FILTRES_DEFAUT,
  type FiltresLitiges,
  type LitigeEnrichi,
} from '@/components/admin/litiges/types';
import { TYPES_DOCUMENTS } from '@/lib/documents';
import {
  buildDocumentCasSnapshot,
  DocumentModerationCard,
  DocumentValidationDialog,
  type DocumentModerationEntry,
  type DocumentModerationProfile,
  type DocumentValidationPayload,
} from '@/components/admin/DocumentModerationReview';
import { LITIGE_ADMIN_TYPES, type LitigeAdminType } from '@/lib/litigeAdminUi';

const LABELS_PERIMETRE_GEL: Record<string, string> = {
  MISSION_ENTIERE: 'Mission entière (toutes les factures de la mission)',
  FACTURE_UNIQUE: 'Facture unique (uniquement la facture liée)',
  PERIODE_LITIGIEUSE: 'Période litigieuse (factures de la période concernée)',
  AUCUN: 'Aucun gel',
};

const LABELS_TYPE_DOCUMENT: Record<string, string> = {
  ...TYPES_DOCUMENTS,
  CARTE_ORDRE: "Carte de l'Ordre",
  ATTESTATION_CPAM: 'Attestation CPAM',
  NOTE_HONORAIRES: "Note d'honoraires",
  ATTESTATION_3200H: 'Attestation 3200 heures',
  ARRET_MALADIE: 'Arrêt maladie',
};
const libelleTypeDocument = (type: string) => LABELS_TYPE_DOCUMENT[type] ?? type;

const formatDate = (d?: string | null) =>
  d
    ? new Date(d).toLocaleDateString('fr-FR', {
        day: '2-digit',
        month: 'short',
        year: 'numeric',
      })
    : '—';

export default function AdminModeration() {
  usePageTitle('Modération');
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const [litiges, setLitiges] = useState<LitigeEnrichi[]>([]);
  const [evaluations, setEvaluations] = useState<any[]>([]);
  const [documents, setDocuments] = useState<DocumentModerationEntry[]>([]);
  const [documentARejeter, setDocumentARejeter] = useState<DocumentModerationEntry | null>(null);
  const [documentAValider, setDocumentAValider] = useState<DocumentModerationEntry | null>(null);
  const [moderationDocumentLoading, setModerationDocumentLoading] = useState(false);
  const [motifRejetDocument, setMotifRejetDocument] = useState('');
  const [incoherences, setIncoherences] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [erreurChargement, setErreurChargement] = useState<string | null>(null);

  const [filtres, setFiltres] = useState<FiltresLitiges>(FILTRES_DEFAUT);
  const [mediationCount, setMediationCount] = useState<number>(0);
  const [legacyCount, setLegacyCount] = useState<number>(0);

  const [preuvesLitige, setPreuvesLitige] = useState<LitigeEnrichi | null>(null);
  const [preuvesOpen, setPreuvesOpen] = useState(false);

  const [resolutionLitige, setResolutionLitige] = useState<LitigeEnrichi | null>(null);
  const [resolutionOpen, setResolutionOpen] = useState(false);

  const [activeTab, setActiveTab] = useState<string>(
    searchParams.get('onglet') === 'documents' ? 'documents' : 'litiges',
  );

  // Task 5 — masquer notation
  const [masquerNotationId, setMasquerNotationId] = useState<string | null>(null);
  const [masquerRaison, setMasquerRaison] = useState('');
  const [masquerLoading, setMasquerLoading] = useState(false);

  // Task 7 — créer litige (bypass)
  const [showCreerLitige, setShowCreerLitige] = useState(false);
  const [creerLitigeMissionId, setCreerLitigeMissionId] = useState('');
  const [creerLitigeType, setCreerLitigeType] = useState<LitigeAdminType>('DESACCORD_HEURES_POINTAGE');
  const [creerLitigeMotif, setCreerLitigeMotif] = useState('');
  const [creerLitigeRaison, setCreerLitigeRaison] = useState('');
  const [creerLitigeLoading, setCreerLitigeLoading] = useState(false);

  // Task 8 — modifier gel scope
  const [gelScopeLitigeId, setGelScopeLitigeId] = useState<string | null>(null);
  const [gelScopeNouveauScope, setGelScopeNouveauScope] = useState('');
  const [gelScopeRaison, setGelScopeRaison] = useState('');
  const [gelScopeLoading, setGelScopeLoading] = useState(false);

  const charger = useCallback(async () => {
    setLoading(true);
    setErreurChargement(null);

    try {
      const [resLitiges, resEvals, resDocs, resIncoherences] = await Promise.all([
      supabase
        .from('litiges')
        .select(
          'id, motif, reponse, statut, cree_le, soignant_id, etablissement_id, mission_id, initie_par, resolution, resolu_le, type_litige, categorie_litige, est_informatif, montant_tresorerie_bloquee, facture_id, escalade_auto_le',
        )
        .in('statut', ['OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'CONTESTEE'])
        .order('cree_le', { ascending: false }),
      supabase
        .from('evaluations')
        .select('id, note, commentaire, type_evaluateur, mission_id, evaluateur_id, evalue_id, cree_le')
        .eq('visible', false)
        .order('cree_le', { ascending: true })
        .limit(50),
      supabase
        .from('documents_soignants')
        .select('id, nom_fichier, type_document, soignant_id, televerse_le, modifie_le, s3_bucket, s3_cle, s3_version_id, type_mime, taille_octets, statut_verification, motif_rejet, resultat_ia, nom_extrait_ia, prenom_extrait_ia, score_confiance_ia, coherence_nom, valide_depuis, valide_jusqua')
        .in('statut_verification', ['EN_ATTENTE', 'REVUE_MANUELLE_REQUISE', 'API_INDISPONIBLE'])
        .is('supprime_le', null)
        .order('televerse_le', { ascending: true })
        .limit(50),
      supabase.rpc('fn_admin_incoherences_identite' as any),
    ]);

      if (resLitiges.error || resEvals.error || resDocs.error || resIncoherences.error) {
        throw resLitiges.error || resEvals.error || resDocs.error || resIncoherences.error;
      }
      setIncoherences((resIncoherences.data as any[] | null) || []);

    const litigesBruts = (resLitiges.data ?? []) as LitigeEnrichi[];

    if (litigesBruts.length > 0) {
      const soignantIds = [...new Set(litigesBruts.map((l) => l.soignant_id).filter(Boolean))];
      const etablissementIds = [...new Set(litigesBruts.map((l) => l.etablissement_id).filter(Boolean))];
      const missionIds = [...new Set(litigesBruts.map((l) => l.mission_id).filter(Boolean))];

      const [resSoignants, resEtablissements, resMissions] = await Promise.all([
        soignantIds.length
          ? supabase.from('soignants').select('id, prenom, nom, email, telephone, profession').in('id', soignantIds)
          : Promise.resolve({ data: [], error: null } as any),
        etablissementIds.length
          ? supabase.from('etablissements').select('id, nom, email_contact, telephone_contact, type').in('id', etablissementIds)
          : Promise.resolve({ data: [], error: null } as any),
        missionIds.length
          ? supabase.from('missions').select('id, intitule, profession_requise, service, debut_le, fin_le, statut').in('id', missionIds)
          : Promise.resolve({ data: [], error: null } as any),
      ]);

      if (resSoignants.error || resEtablissements.error || resMissions.error) {
        throw resSoignants.error || resEtablissements.error || resMissions.error;
      }

      const soignantsMap = new Map<string, LitigeEnrichi['soignant']>((resSoignants.data ?? []).map((item: any) => [item.id, item]));
      const etablissementsMap = new Map<string, LitigeEnrichi['etablissement']>((resEtablissements.data ?? []).map((item: any) => [item.id, item]));
      const missionsMap = new Map<string, LitigeEnrichi['mission']>((resMissions.data ?? []).map((item: any) => [item.id, item]));

      const litigesEnrichis: LitigeEnrichi[] = litigesBruts.map((l) => ({
        ...l,
        soignant: soignantsMap.get(l.soignant_id) ?? null,
        etablissement: etablissementsMap.get(l.etablissement_id) ?? null,
        mission: missionsMap.get(l.mission_id) ?? null,
      }));

      setLitiges(litigesEnrichis);
    } else {
      setLitiges([]);
    }

    if (resEvals.data && resEvals.data.length > 0) {
      const evalsBruts = resEvals.data as any[];
      const allUserIds = [...new Set([
        ...evalsBruts.map(e => e.evaluateur_id).filter(Boolean),
        ...evalsBruts.map(e => e.evalue_id).filter(Boolean),
      ])];
      const evalMissionIds = [...new Set(evalsBruts.map(e => e.mission_id).filter(Boolean))];

      const [resSg, resEt, resM] = await Promise.all([
        allUserIds.length ? supabase.from('soignants').select('id, prenom, nom').in('id', allUserIds) : Promise.resolve({ data: [], error: null } as any),
        allUserIds.length ? supabase.from('etablissements').select('id, nom').in('id', allUserIds) : Promise.resolve({ data: [], error: null } as any),
        evalMissionIds.length ? supabase.from('missions').select('id, intitule').in('id', evalMissionIds) : Promise.resolve({ data: [], error: null } as any),
      ]);

      if (resSg.error || resEt.error || resM.error) {
        throw resSg.error || resEt.error || resM.error;
      }

      const nameMap: Record<string, string> = {};
      for (const s of (resSg.data ?? [])) nameMap[s.id] = `${s.prenom || ''} ${s.nom || ''}`.trim();
      for (const e of (resEt.data ?? [])) nameMap[e.id] = e.nom;
      const missionMap: Record<string, string> = {};
      for (const m of (resM.data ?? [])) missionMap[m.id] = m.intitule;

      setEvaluations(evalsBruts.map(e => ({
        ...e,
        evaluateur_nom: nameMap[e.evaluateur_id] || '—',
        evalue_nom: nameMap[e.evalue_id] || '—',
        mission_intitule: missionMap[e.mission_id] || '—',
      })));
    } else {
      setEvaluations([]);
    }
    const docsBruts = (resDocs.data ?? []) as Omit<DocumentModerationEntry, 'soignant' | 'exige_expiration'>[];
    if (docsBruts.length > 0) {
      const soignantIds = [...new Set(docsBruts.map((document) => document.soignant_id))];
      const typesDocuments = [...new Set(docsBruts.map((document) => document.type_document))];
      const { data: profils, error: profilsError } = await supabase
        .from('soignants')
        .select('id, prenom, nom, email, profession, date_naissance, numero_rpps, numero_adeli, rpps_verifie, adeli_verifie, modifie_le')
        .in('id', soignantIds)
        .is('supprime_le', null);
      const professions = [...new Set((profils ?? []).map((profil: any) => profil.profession).filter(Boolean))];
      const { data: regles, error: reglesError } = professions.length > 0
        ? await supabase
          .from('documents_requis_par_profession')
          .select('profession, type_document, a_expiration')
          .in('profession', professions)
          .in('type_document', typesDocuments as any[])
        : { data: [], error: null };

      if (profilsError || reglesError) {
        throw profilsError || reglesError;
      }
      const profilsMap = new Map<string, DocumentModerationProfile>(
        ((profils ?? []) as DocumentModerationProfile[]).map((profil) => [profil.id, profil]),
      );
      const expirationMap = new Map<string, boolean>();
      for (const regle of (regles ?? []) as any[]) {
        const cle = `${regle.profession}:${regle.type_document}`;
        expirationMap.set(cle, expirationMap.get(cle) === true || regle.a_expiration === true);
      }
      setDocuments(docsBruts.map((document) => {
        const profil = profilsMap.get(document.soignant_id) ?? null;
        const exigeExpiration = profil?.profession
          ? expirationMap.get(`${profil.profession}:${document.type_document}`) === true
          : false;
        return { ...document, soignant: profil, exige_expiration: exigeExpiration };
      }));
    } else {
      setDocuments([]);
    }

    // Count litiges EN_MEDIATION depuis plus de 7 jours (escalade_auto_le < now - 7d).
    const seuilIso = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
    const { count: medCount, error: errMed } = await supabase
      .from('litiges')
      .select('id', { count: 'exact', head: true })
      .eq('statut', 'EN_MEDIATION')
      .lt('escalade_auto_le', seuilIso);
    if (errMed) throw errMed;
    setMediationCount(medCount ?? 0);
    } catch {
      const message = 'Les données de modération n’ont pas pu être chargées. Vérifiez votre connexion puis réessayez.';
      setErreurChargement(message);
      toast.error(message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void charger();
  }, [charger]);

  const publierEvaluation = async (id: string) => {
    const { data, error } = await supabase.rpc('fn_admin_moderer_evaluation' as any, { p_evaluation_id: id, p_action: 'PUBLIER' });
    if (error || (data as any)?.error) { toast.error('Une erreur est survenue. Veuillez réessayer.'); return; }
    toast.success('Évaluation publiée');
    charger();
  };

  const supprimerEvaluation = async (id: string) => {
    const { data, error } = await supabase.rpc('fn_admin_moderer_evaluation' as any, { p_evaluation_id: id, p_action: 'SUPPRIMER' });
    if (error || (data as any)?.error) { toast.error('Une erreur est survenue. Veuillez réessayer.'); return; }
    toast.success('Évaluation supprimée');
    charger();
  };

  const validerDocument = async (document: DocumentModerationEntry, payload: DocumentValidationPayload) => {
    setModerationDocumentLoading(true);
    const { data, error } = await supabase.rpc('fn_admin_moderer_document' as any, {
      p_document_id: document.id,
      p_action: 'VALIDER',
      p_motif: null,
      p_validation_manuelle: payload.validation,
      p_raison_override: payload.raisonOverride,
    });
    setModerationDocumentLoading(false);
    if (error || (data as any)?.error) {
      toast.error(error?.message || (data as any)?.error || 'La validation a été refusée. Rechargez le document et vérifiez tous les champs.');
      return;
    }
    toast.success((data as any)?.source === 'ADMIN_OVERRIDE_EXCEPTIONNEL'
      ? 'Document validé avec dérogation exceptionnelle tracée'
      : 'Document validé après contrôles');
    setDocumentAValider(null);
    await charger();
  };

  const rejeterDocument = async (document: DocumentModerationEntry, motif: string) => {
    if (motif.trim().length < 10) {
      toast.error('Le motif doit contenir au moins 10 caractères.');
      return;
    }
    setModerationDocumentLoading(true);
    const { data, error } = await supabase.rpc('fn_admin_moderer_document' as any, {
      p_document_id: document.id,
      p_action: 'REJETER',
      p_motif: motif.trim(),
      p_validation_manuelle: buildDocumentCasSnapshot(document),
      p_raison_override: null,
    });
    setModerationDocumentLoading(false);
    if (error || (data as any)?.error) {
      toast.error(error?.message || (data as any)?.error || 'Le rejet a été refusé. Rechargez la file de modération.');
      return;
    }
    toast.success('Document rejeté');
    setDocumentARejeter(null);
    setMotifRejetDocument('');
    charger();
  };

  const voirDocument = async (document: DocumentModerationEntry) => {
    const preview = window.open('about:blank', '_blank');
    if (!preview) {
      toast.error('Autorisez les fenêtres contextuelles pour consulter le document.');
      return;
    }
    preview.opener = null;
    try {
      const { data, error } = await supabase.storage
        .from(document.s3_bucket || 'jolene-documents')
        .createSignedUrl(document.s3_cle, 300);
      if (error || !data?.signedUrl) throw error || new Error('URL signée absente');
      preview.location.replace(data.signedUrl);
    } catch {
      preview.close();
      toast.error('Impossible d’ouvrir ce document.');
    }
  };

  // Task 5 — masquer notation
  const masquerNotation = async () => {
    if (!masquerNotationId) return;
    if (!masquerRaison.trim()) { toast.error('Raison obligatoire pour la traçabilité.'); return; }
    setMasquerLoading(true);
    const { data, error } = await supabase.rpc('fn_admin_masquer_notation' as any, {
      p_notation_id: masquerNotationId,
      p_raison: masquerRaison.trim(),
    });
    setMasquerLoading(false);
    if (error || (data as any)?.error) { toast.error((data as any)?.error || error?.message || 'Erreur.'); return; }
    toast.success('Notation masquée');
    setMasquerNotationId(null);
    setMasquerRaison('');
    charger();
  };

  // Task 7 — créer litige force
  const creerLitigeForce = async () => {
    if (!creerLitigeMissionId.trim()) { toast.error('ID de mission requis.'); return; }
    if (!creerLitigeMotif.trim()) { toast.error('Motif obligatoire.'); return; }
    if (!creerLitigeRaison.trim()) { toast.error('Justification de la dérogation obligatoire.'); return; }
    setCreerLitigeLoading(true);
    const { data, error } = await supabase.rpc('fn_admin_creer_litige_force' as any, {
      p_mission_id: creerLitigeMissionId.trim(),
      p_type_litige: creerLitigeType,
      p_motif: creerLitigeMotif.trim(),
      p_raison_bypass: creerLitigeRaison.trim(),
    });
    setCreerLitigeLoading(false);
    if (error || (data as any)?.error) { toast.error((data as any)?.error || error?.message || 'Erreur.'); return; }
    toast.success('Litige créé');
    setShowCreerLitige(false);
    setCreerLitigeMissionId('');
    setCreerLitigeMotif('');
    setCreerLitigeRaison('');
    charger();
  };

  // Task 8 — modifier gel scope litige
  const modifierGelScope = async () => {
    if (!gelScopeLitigeId) return;
    if (!gelScopeNouveauScope.trim()) { toast.error('Veuillez sélectionner un périmètre de gel.'); return; }
    if (!gelScopeRaison.trim()) { toast.error('Raison obligatoire pour la traçabilité.'); return; }
    setGelScopeLoading(true);
    const { data, error } = await supabase.rpc('fn_admin_modifier_gel_scope_litige' as any, {
      p_litige_id: gelScopeLitigeId,
      p_nouveau_scope: gelScopeNouveauScope.trim(),
      p_raison: gelScopeRaison.trim(),
    });
    setGelScopeLoading(false);
    if (error || (data as any)?.error) { toast.error((data as any)?.error || error?.message || 'Erreur.'); return; }
    toast.success('Périmètre de gel mis à jour');
    setGelScopeLitigeId(null);
    setGelScopeNouveauScope('');
    setGelScopeRaison('');
    charger();
  };

  if (loading) return <LayoutAdmin><ChargementAdmin titre="Modération" /></LayoutAdmin>;

  if (erreurChargement) {
    return (
      <LayoutAdmin>
        <BreadcrumbAdmin pageName="Modération" />
        <div className="space-y-5">
          <AdminPageHeader
            title="Modération"
            description="Litiges, évaluations, documents et contrôles d’identité."
            icon={<ShieldAlert className="h-6 w-6" />}
          />
          <div role="alert" className="rounded-xl border border-destructive/30 bg-destructive/5 p-6 text-center">
            <ShieldAlert className="mx-auto h-8 w-8 text-destructive" />
            <h2 className="mt-3 text-lg font-bold text-foreground">Modération indisponible</h2>
            <p className="mt-1 text-sm text-muted-foreground">{erreurChargement}</p>
            <BoutonY2K
              variant="secondary"
              size="sm"
              className="mt-4 min-h-[44px] gap-2"
              onClick={() => void charger()}
              iconeGauche={<RefreshCw className="h-4 w-4" />}
            >
              Réessayer
            </BoutonY2K>
          </div>
        </div>
      </LayoutAdmin>
    );
  }

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin pageName="Modération" />
      <div className="space-y-5">
        <AdminPageHeader
          title="Modération"
          description="Litiges, évaluations, documents et contrôles d’identité à traiter."
          icon={<ShieldAlert className="h-6 w-6" />}
          actions={<RefundsQueueWidget />}
        />

        <MediationBanner
          count={mediationCount}
          onVoir={() => {
            setFiltres({
              ...FILTRES_DEFAUT,
              statut: 'EN_MEDIATION',
              tri: 'ESCALADE_MEDIATION',
            });
            setActiveTab('litiges');
          }}
        />

        <Tabs value={activeTab} onValueChange={setActiveTab}>
          <div className="overflow-x-auto -mx-4 px-4 md:mx-0 md:px-0">
            <TabsList className="h-auto w-max p-1 md:w-auto">
              <TabsTrigger value="litiges" className="min-h-10 gap-1.5 px-3 text-xs sm:text-sm"><MessageSquare className="h-4 w-4" />Litiges ({litiges.length})</TabsTrigger>
              <TabsTrigger value="avoirs" className="min-h-10 gap-1.5 px-3 text-xs sm:text-sm"><Receipt className="h-4 w-4" />Avoirs</TabsTrigger>
              <TabsTrigger value="legacy" className="min-h-10 gap-1.5 px-3 text-xs sm:text-sm">
                <Tag className="h-4 w-4" />À recatégoriser{legacyCount > 0 ? ` (${legacyCount})` : ''}
              </TabsTrigger>
              <TabsTrigger value="evaluations" className="min-h-10 gap-1.5 px-3 text-xs sm:text-sm"><Eye className="h-4 w-4" />Évaluations ({evaluations.length})</TabsTrigger>
              <TabsTrigger value="documents" className="min-h-10 gap-1.5 px-3 text-xs sm:text-sm"><FileCheck className="h-4 w-4" />Documents ({documents.length})</TabsTrigger>
              <TabsTrigger value="incoherences" className="min-h-10 gap-1.5 px-3 text-xs sm:text-sm"><ShieldAlert className="h-4 w-4" />Identité ({incoherences.length})</TabsTrigger>
            </TabsList>
          </div>

          <TabsContent value="litiges" className="space-y-4" data-testid="tab-litiges">
            <AdminFilterBar
              ariaLabel="Filtres des litiges"
              actions={(
                <>
                  <BoutonY2K
                    size="sm"
                    variant="secondary"
                    onClick={() => { setShowCreerLitige(true); setCreerLitigeMissionId(''); setCreerLitigeMotif(''); setCreerLitigeRaison(''); }}
                    aria-label="Créer un litige par dérogation admin"
                    iconeGauche={<Plus className="h-3.5 w-3.5" />}
                  >
                    Créer un litige par dérogation
                  </BoutonY2K>
                  <BoutonY2K
                    size="sm"
                    variant="secondary"
                    onClick={() => telechargerCsv(filtrerEtTrier(litiges, filtres))}
                    disabled={litiges.length === 0}
                    aria-label="Exporter les litiges filtrés en CSV"
                    data-testid="btn-export-csv"
                    iconeGauche={<Download className="h-3.5 w-3.5" />}
                  >
                    Exporter CSV
                  </BoutonY2K>
                </>
              )}
            >
              <div className="w-full">
                <LitigesFilters filtres={filtres} onChange={setFiltres} />
              </div>
            </AdminFilterBar>

            <LitigesList
              litiges={litiges}
              filtres={filtres}
              onOpenPreuves={(l) => {
                setPreuvesLitige(l);
                setPreuvesOpen(true);
              }}
              onOpenResolution={(l) => {
                setResolutionLitige(l);
                setResolutionOpen(true);
              }}
              onGelScope={(l) => {
                setGelScopeLitigeId(l.id);
                setGelScopeNouveauScope('');
                setGelScopeRaison('');
              }}
            />

            <LitigePreuvesPanel
              litige={preuvesLitige}
              open={preuvesOpen}
              onOpenChange={(o) => {
                setPreuvesOpen(o);
                if (!o) setPreuvesLitige(null);
              }}
            />

            <LitigeResolutionModal
              litige={resolutionLitige}
              open={resolutionOpen}
              onOpenChange={(o) => {
                setResolutionOpen(o);
                if (!o) setResolutionLitige(null);
              }}
              onResolved={() => {
                charger();
              }}
            />
          </TabsContent>

          <TabsContent value="avoirs" className="space-y-4" data-testid="tab-avoirs">
            <AvoirsList onChanged={charger} />
          </TabsContent>

          <TabsContent value="legacy" className="space-y-4" data-testid="tab-legacy">
            <LegacyRecategorisation
              onChanged={charger}
              onCountChange={setLegacyCount}
            />
          </TabsContent>

          <TabsContent value="evaluations">
            <p className="text-xs text-muted-foreground mb-3">
              Les évaluations positives (4-5 étoiles) sans commentaire sont publiées automatiquement. Seules les évaluations nécessitant une vérification apparaissent ici.
            </p>
            {evaluations.length === 0 ? (
              <p className="py-8 text-center text-sm text-muted-foreground">Aucune évaluation en attente de modération.</p>
            ) : (
              <div className="space-y-3">
                {evaluations.map((e) => (
                  <CardY2K noPadding key={e.id}>
                    <CardY2KContent className="pt-4 space-y-3">
                      <div className="flex items-start justify-between gap-3">
                        <div className="space-y-1">
                          <div className="flex items-center gap-2">
                            <BadgeY2K variant={e.note <= 2 ? 'error' : e.note === 3 ? 'warning' : 'info'}>
                              Note {e.note}/5
                            </BadgeY2K>
                            <span className="text-xs text-muted-foreground">{formatDate(e.cree_le)}</span>
                          </div>
                          <p className="text-sm text-foreground">
                            <span className="font-medium">{e.evaluateur_nom}</span>
                            <span className="text-muted-foreground"> ({e.type_evaluateur === 'SOIGNANT' ? 'Soignant' : 'Établissement'}) a évalué </span>
                            <span className="font-medium">{e.evalue_nom}</span>
                          </p>
                          <p className="text-xs text-muted-foreground">Mission : {e.mission_intitule}</p>
                        </div>
                        <div className="flex gap-1.5 shrink-0 flex-wrap">
                          <BoutonY2K size="sm" variant="secondary" onClick={() => publierEvaluation(e.id)} iconeGauche={<Check className="h-3.5 w-3.5" />}>Publier</BoutonY2K>
                          <BoutonY2K size="sm" variant="destructive" onClick={() => supprimerEvaluation(e.id)} iconeGauche={<X className="h-3.5 w-3.5" />}>Supprimer</BoutonY2K>
                          <BoutonY2K size="sm" variant="secondary" onClick={() => { setMasquerNotationId(e.id); setMasquerRaison(''); }} iconeGauche={<EyeOff className="h-3.5 w-3.5" />}>Masquer</BoutonY2K>
                        </div>
                      </div>
                      {e.commentaire && (
                        <div className="rounded-lg bg-muted/50 p-3">
                          <p className="text-sm text-foreground italic">"{e.commentaire}"</p>
                        </div>
                      )}
                      {!e.commentaire && e.note <= 3 && (
                        <p className="text-xs text-warning">Note basse sans commentaire — vérification recommandée</p>
                      )}
                    </CardY2KContent>
                  </CardY2K>
                ))}
              </div>
            )}
          </TabsContent>

          <TabsContent value="documents" className="space-y-4">
            <div className="rounded-xl border border-jolene-mauve-300 bg-jolene-mauve-100/60 p-3 text-sm text-jolene-mauve-800">
              Une validation exige l’ouverture de la preuve, la comparaison avec l’identité et la profession du profil, puis la confirmation des contrôles propres au type de document. Toute modification concurrente bloque la décision.
            </div>
            {documents.length === 0 ? (
              <p className="py-8 text-center text-sm text-muted-foreground">Aucun document en attente</p>
            ) : (
              <div className="space-y-4">
                {documents.map((document) => (
                  <DocumentModerationCard
                    key={document.id}
                    document={document}
                    typeLabel={libelleTypeDocument(document.type_document)}
                    onOpen={voirDocument}
                    onValidate={(entry) => setDocumentAValider(entry)}
                    onReject={(entry) => {
                      setDocumentARejeter(entry);
                      setMotifRejetDocument('');
                    }}
                  />
                ))}
              </div>
            )}
          </TabsContent>

          <TabsContent value="incoherences" className="space-y-4">
            {/* Desktop : table 8 cols */}
            <div className="hidden md:block overflow-x-auto rounded-lg border">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Soignant</TableHead>
                    <TableHead>Nom Profil</TableHead>
                    <TableHead>Nom RPPS</TableHead>
                    <TableHead>Nom CNI</TableHead>
                    <TableHead>Profil ↔ RPPS</TableHead>
                    <TableHead>Profil ↔ CNI</TableHead>
                    <TableHead>RPPS ↔ CNI</TableHead>
                    <TableHead>Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {incoherences.map((inc: any) => {
                    const matchProfilRpps = inc.nom_profil && inc.nom_rpps
                      ? inc.nom_profil.toUpperCase() === inc.nom_rpps.toUpperCase()
                      : null;
                    const matchProfilCni = inc.nom_profil && inc.nom_cni
                      ? inc.nom_profil.toUpperCase() === inc.nom_cni.toUpperCase()
                      : null;
                    const matchRppsCni = inc.nom_rpps && inc.nom_cni
                      ? inc.nom_rpps.toUpperCase() === inc.nom_cni.toUpperCase()
                      : null;
                    return (
                      <TableRow key={inc.soignant_id}>
                        <TableCell className="font-medium">
                          {inc.prenom_profil} {inc.nom_profil}
                        </TableCell>
                        <TableCell>{inc.nom_profil || '—'}</TableCell>
                        <TableCell>{inc.nom_rpps || '—'}</TableCell>
                        <TableCell>{inc.nom_cni || '—'}</TableCell>
                        <TableCell className="text-center">
                          {matchProfilRpps === null ? '—' : matchProfilRpps ? <Check className="h-4 w-4 text-success mx-auto" /> : <X className="h-4 w-4 text-destructive mx-auto" />}
                        </TableCell>
                        <TableCell className="text-center">
                          {matchProfilCni === null ? '—' : matchProfilCni ? <Check className="h-4 w-4 text-success mx-auto" /> : <X className="h-4 w-4 text-destructive mx-auto" />}
                        </TableCell>
                        <TableCell className="text-center">
                          {matchRppsCni === null ? '—' : matchRppsCni ? <Check className="h-4 w-4 text-success mx-auto" /> : <X className="h-4 w-4 text-destructive mx-auto" />}
                        </TableCell>
                        <TableCell>
                          <BoutonY2K size="sm" variant="secondary" onClick={() => navigate(`/admin/utilisateurs/${inc.soignant_id}`)} iconeGauche={<Eye className="h-3.5 w-3.5" />}>
                            Voir
                          </BoutonY2K>
                        </TableCell>
                      </TableRow>
                    );
                  })}
                  {incoherences.length === 0 && <TableRow><TableCell colSpan={8} className="py-8 text-center text-muted-foreground">Aucune incohérence identitaire détectée.</TableCell></TableRow>}
                </TableBody>
              </Table>
            </div>

            {/* Mobile : cards avec 3 matches résumés visuellement */}
            <div className="md:hidden space-y-3">
              {incoherences.length === 0 ? (
                <p className="py-8 text-center text-sm text-muted-foreground">Aucune incohérence identitaire détectée.</p>
              ) : incoherences.map((inc: any) => {
                const matchProfilRpps = inc.nom_profil && inc.nom_rpps
                  ? inc.nom_profil.toUpperCase() === inc.nom_rpps.toUpperCase()
                  : null;
                const matchProfilCni = inc.nom_profil && inc.nom_cni
                  ? inc.nom_profil.toUpperCase() === inc.nom_cni.toUpperCase()
                  : null;
                const matchRppsCni = inc.nom_rpps && inc.nom_cni
                  ? inc.nom_rpps.toUpperCase() === inc.nom_cni.toUpperCase()
                  : null;
                const renderMatch = (m: boolean | null) =>
                  m === null ? <span className="text-muted-foreground">—</span>
                    : m ? <Check className="h-4 w-4 text-success" />
                    : <X className="h-4 w-4 text-destructive" />;
                return (
                  <div key={inc.soignant_id} className="rounded-xl border border-border bg-card p-3 space-y-3">
                    <p className="font-semibold text-sm text-foreground">{inc.prenom_profil} {inc.nom_profil}</p>
                    <div className="grid grid-cols-1 gap-1.5 text-xs">
                      <div className="flex items-start justify-between gap-3">
                        <span className="text-muted-foreground shrink-0">Nom Profil</span>
                        <span className="text-foreground text-right break-words">{inc.nom_profil || '—'}</span>
                      </div>
                      <div className="flex items-start justify-between gap-3">
                        <span className="text-muted-foreground shrink-0">Nom RPPS</span>
                        <span className="text-foreground text-right break-words">{inc.nom_rpps || '—'}</span>
                      </div>
                      <div className="flex items-start justify-between gap-3">
                        <span className="text-muted-foreground shrink-0">Nom CNI</span>
                        <span className="text-foreground text-right break-words">{inc.nom_cni || '—'}</span>
                      </div>
                    </div>
                    <div className="border-t border-border/50 pt-2 grid grid-cols-3 gap-1 text-[10px]">
                      <div className="flex flex-col items-center gap-1">
                        <span className="text-muted-foreground">Profil ↔ RPPS</span>
                        {renderMatch(matchProfilRpps)}
                      </div>
                      <div className="flex flex-col items-center gap-1">
                        <span className="text-muted-foreground">Profil ↔ CNI</span>
                        {renderMatch(matchProfilCni)}
                      </div>
                      <div className="flex flex-col items-center gap-1">
                        <span className="text-muted-foreground">RPPS ↔ CNI</span>
                        {renderMatch(matchRppsCni)}
                      </div>
                    </div>
                    <BoutonY2K size="sm" variant="secondary" className="w-full min-h-[36px]" onClick={() => navigate(`/admin/utilisateurs/${inc.soignant_id}`)} iconeGauche={<Eye className="h-3.5 w-3.5" />}>
                      Voir le détail
                    </BoutonY2K>
                  </div>
                );
              })}
            </div>
          </TabsContent>
        </Tabs>
      </div>

      {documentAValider && (
        <DocumentValidationDialog
          document={documentAValider}
          typeLabel={libelleTypeDocument(documentAValider.type_document)}
          loading={moderationDocumentLoading}
          onCancel={() => !moderationDocumentLoading && setDocumentAValider(null)}
          onConfirm={(payload) => validerDocument(documentAValider, payload)}
        />
      )}

      {documentARejeter && (
        <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4" onClick={() => setDocumentARejeter(null)}>
          <div role="dialog" aria-modal="true" aria-labelledby="titre-rejet-document" className="bg-card border border-border rounded-2xl max-w-md w-full p-6 space-y-4" onClick={(e) => e.stopPropagation()}>
            <h2 id="titre-rejet-document" className="text-lg font-bold text-foreground">Rejeter le document</h2>
            <p className="text-sm text-muted-foreground">Le motif sera visible par le soignant. Décrivez précisément ce qu’il doit corriger.</p>
            <label className="block">
              <span className="text-sm font-medium text-foreground mb-1 block">Motif du rejet *</span>
              <Textarea value={motifRejetDocument} onChange={(e) => setMotifRejetDocument(e.target.value)} rows={4} placeholder="Ex. : le document est illisible sur la page 2…" />
            </label>
            <div className="flex gap-2 justify-end">
              <BoutonY2K variant="secondary" onClick={() => setDocumentARejeter(null)} disabled={moderationDocumentLoading}>Annuler</BoutonY2K>
              <BoutonY2K variant="destructive" loading={moderationDocumentLoading} disabled={motifRejetDocument.trim().length < 10 || moderationDocumentLoading} onClick={() => rejeterDocument(documentARejeter, motifRejetDocument)}>Confirmer le rejet</BoutonY2K>
            </div>
          </div>
        </div>
      )}

      {masquerNotationId && (
        <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4" onClick={() => setMasquerNotationId(null)}>
          <div role="dialog" aria-modal="true" aria-labelledby="titre-masquer-notation" className="bg-card border border-border rounded-2xl max-w-md w-full p-6 space-y-4 max-h-[90dvh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <h2 id="titre-masquer-notation" className="text-lg font-bold text-foreground">Masquer la notation</h2>
            <p className="text-xs text-muted-foreground">Masquer cette évaluation des vues publiques. La raison est tracée à des fins RGPD.</p>
            <label className="block">
              <span className="text-xs font-medium text-foreground mb-1 block">Raison * (journalisée)</span>
              <Textarea value={masquerRaison} onChange={(e) => setMasquerRaison(e.target.value)} rows={3} placeholder="Raison du masquage…" disabled={masquerLoading} />
            </label>
            <div className="flex gap-2">
              <BoutonY2K variant="secondary" onClick={() => setMasquerNotationId(null)} disabled={masquerLoading}>Annuler</BoutonY2K>
              <BoutonY2K variant="destructive" onClick={masquerNotation} disabled={masquerLoading || !masquerRaison.trim()} loading={masquerLoading}>Masquer</BoutonY2K>
            </div>
          </div>
        </div>
      )}

      {/* Création exceptionnelle d’un litige par un administrateur. */}
      {showCreerLitige && (
        <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4" onClick={() => setShowCreerLitige(false)}>
          <div role="dialog" aria-modal="true" aria-labelledby="titre-creer-litige-derogation" className="bg-card border border-border rounded-2xl max-w-md w-full p-6 space-y-4 max-h-[90dvh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <h2 id="titre-creer-litige-derogation" className="text-lg font-bold text-foreground">Créer un litige par dérogation</h2>
            <p className="text-xs text-muted-foreground">Crée exceptionnellement un litige sans passer par le parcours habituel. La justification est journalisée.</p>
            <label className="block">
              <span className="text-xs font-medium text-foreground mb-1 block">ID de mission *</span>
              <Input value={creerLitigeMissionId} onChange={(e) => setCreerLitigeMissionId(e.target.value)} placeholder="Identifiant de la mission" disabled={creerLitigeLoading} />
            </label>
            <label className="block">
              <span className="text-xs font-medium text-foreground mb-1 block">Type de litige *</span>
              <select value={creerLitigeType} onChange={(e) => setCreerLitigeType(e.target.value as LitigeAdminType)} className="input-base" disabled={creerLitigeLoading}>
                {LITIGE_ADMIN_TYPES.map(({ value, label }) => (
                  <option key={value} value={value}>{label}</option>
                ))}
              </select>
            </label>
            <label className="block">
              <span className="text-xs font-medium text-foreground mb-1 block">Motif *</span>
              <Textarea value={creerLitigeMotif} onChange={(e) => setCreerLitigeMotif(e.target.value)} rows={2} placeholder="Motif du litige…" disabled={creerLitigeLoading} />
            </label>
            <label className="block">
              <span className="text-xs font-medium text-foreground mb-1 block">Justification de la dérogation * (journalisée)</span>
              <Textarea value={creerLitigeRaison} onChange={(e) => setCreerLitigeRaison(e.target.value)} rows={2} placeholder="Pourquoi cette dérogation est-elle nécessaire ?" disabled={creerLitigeLoading} />
            </label>
            <div className="flex gap-2">
              <BoutonY2K variant="secondary" onClick={() => setShowCreerLitige(false)} disabled={creerLitigeLoading}>Annuler</BoutonY2K>
              <BoutonY2K onClick={creerLitigeForce} disabled={creerLitigeLoading || !creerLitigeMissionId.trim() || !creerLitigeMotif.trim() || !creerLitigeRaison.trim()} loading={creerLitigeLoading}>Créer le litige</BoutonY2K>
            </div>
          </div>
        </div>
      )}

      {/* Task 8 — Modal modifier gel scope litige */}
      {gelScopeLitigeId && (
        <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4" onClick={() => setGelScopeLitigeId(null)}>
          <div role="dialog" aria-modal="true" aria-labelledby="titre-modifier-perimetre-gel" className="bg-card border border-border rounded-2xl max-w-md w-full p-6 space-y-4 max-h-[90dvh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <h2 id="titre-modifier-perimetre-gel" className="text-lg font-bold text-foreground inline-flex items-center gap-2"><GitBranch className="h-5 w-5" />Modifier le périmètre de gel</h2>
            <p className="text-xs text-muted-foreground">Modifie le périmètre de gel du litige. Action tracée RGPD.</p>
            <label className="block">
              <span className="text-xs font-medium text-foreground mb-1 block">Nouveau périmètre de gel *</span>
              <select value={gelScopeNouveauScope} onChange={(e) => setGelScopeNouveauScope(e.target.value)} className="input-base" disabled={gelScopeLoading}>
                <option value="">— Sélectionner —</option>
                {Object.entries(LABELS_PERIMETRE_GEL).map(([valeur, libelle]) => (
                  <option key={valeur} value={valeur}>{libelle}</option>
                ))}
              </select>
            </label>
            <label className="block">
              <span className="text-xs font-medium text-foreground mb-1 block">Raison * (journalisée)</span>
              <Textarea value={gelScopeRaison} onChange={(e) => setGelScopeRaison(e.target.value)} rows={2} placeholder="Raison de la modification…" disabled={gelScopeLoading} />
            </label>
            <div className="flex gap-2">
              <BoutonY2K variant="secondary" onClick={() => setGelScopeLitigeId(null)} disabled={gelScopeLoading}>Annuler</BoutonY2K>
              <BoutonY2K onClick={modifierGelScope} disabled={gelScopeLoading || !gelScopeNouveauScope.trim() || !gelScopeRaison.trim()} loading={gelScopeLoading}>Mettre à jour</BoutonY2K>
            </div>
          </div>
        </div>
      )}
    </LayoutAdmin>
  );
}
