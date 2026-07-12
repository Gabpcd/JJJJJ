import React, { useState, useEffect } from 'react';
import { useParams, useNavigate, Link } from 'react-router-dom';
import { ChevronRight, ArrowLeft, Mail, Phone, MapPin, Calendar, Shield, Star, Award, FileText, Clock, Ban, RefreshCw, Trash2, KeyRound, UserCog, AlertTriangle, MessageCircle, Send } from 'lucide-react';
import { supabase as supabaseClient, SUPABASE_PUBLISHABLE_KEY, SUPABASE_URL } from '@/integrations/supabase/client';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementAdmin } from '@/components/admin/ChargementAdmin';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import {
  CardY2K,
  CardY2KHeader,
  CardY2KTitle,
  CardY2KContent,
} from '@/components/y2k/CardY2K';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Separator } from '@/components/ui/separator';
import { toast } from 'sonner';
import { logger } from '@/lib/logger';
import { usePageTitle } from '@/hooks/usePageTitle';
import { TYPES_DOCUMENTS, STATUTS_VERIFICATION } from '@/lib/documents';
import { BADGES_STATUT, getLabelProfession, getLabelTypeEtablissement } from '@/lib/constantes';
import { formatEuroAdmin } from '@/lib/adminPresentation';
import { ModalConfirmation } from '@/components/ModalConfirmation';
import { Textarea } from '@/components/ui/textarea';
import { AdminMissionChatPanel } from '@/components/admin/AdminMissionChatPanel';

export default function AdminDetailUtilisateur() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [type, setType] = useState<'soignant' | 'etablissement' | null>(null);
  const [soignant, setSoignant] = useState<any>(null);
  const [etablissement, setEtablissement] = useState<any>(null);
  const [documents, setDocuments] = useState<any[]>([]);
  const [missions, setMissions] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [modalSuspendre, setModalSuspendre] = useState(false);
  const [motifSuspension, setMotifSuspension] = useState(''); // Lot 21 : motif obligatoire (journalisé)
  const [modalSupprimer, setModalSupprimer] = useState(false);
  const [modalLeverSuspension, setModalLeverSuspension] = useState(false);
  const [raisonLeverSuspension, setRaisonLeverSuspension] = useState('');
  const [modalForceRib, setModalForceRib] = useState(false);
  const [raisonForceRib, setRaisonForceRib] = useState('');
  const [documentsMissing, setDocumentsMissing] = useState<string[]>([]);
  const [documentsExpires, setDocumentsExpires] = useState<string[]>([]);
  const [dernierRappel, setDernierRappel] = useState<string | null>(null);
  const [envoiRappel, setEnvoiRappel] = useState(false);

  usePageTitle('Détail utilisateur');

  useEffect(() => {
    if (!id) return;
    charger();
  }, [id]);

  /* Validation manuelle : l'admin téléverse un document reçu en privé au nom
     du soignant (storage admin policy + RPC fn_admin_ajouter_document_soignant)
     puis il est validé immédiatement — tous_documents_valides est recalculé. */
  const [uploadDocType, setUploadDocType] = useState('CNI');
  const [uploadEnCours, setUploadEnCours] = useState(false);
  const [validationEnCours, setValidationEnCours] = useState<string | null>(null);

  const uploaderPourSoignant = async (fichier: File) => {
    if (!id) return;
    setUploadEnCours(true);
    try {
      const nomSanitise = fichier.name.normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^\w.-]+/g, '-');
      const cle = `${id}/documents/${uploadDocType}/${Date.now()}-${nomSanitise}`;
      const { error: upErr } = await supabase.storage.from('jolene-documents')
        .upload(cle, fichier, { contentType: fichier.type || undefined, upsert: false });
      if (upErr) { toast.error(`Téléversement impossible : ${upErr.message}`); return; }
      const { data, error } = await supabase.rpc('fn_admin_ajouter_document_soignant' as any, {
        p_soignant_id: id,
        p_type_document: uploadDocType,
        p_cle: cle,
        p_nom_fichier: fichier.name,
        p_type_mime: fichier.type || null,
        p_taille_octets: fichier.size,
        p_valider: true,
      });
      if (error || (data as any)?.error) {
        await supabase.storage.from('jolene-documents').remove([cle]);
        toast.error((data as any)?.error || 'Enregistrement impossible.');
        return;
      }
      toast.success(`Document ${TYPES_DOCUMENTS[uploadDocType] || uploadDocType} ajouté et validé`);
      charger();
    } finally {
      setUploadEnCours(false);
    }
  };

  const validerDocument = async (docId: string) => {
    setValidationEnCours(docId);
    try {
      const { data, error } = await supabase.rpc('fn_admin_moderer_document' as any, {
        p_document_id: docId, p_action: 'VALIDER',
      });
      if (error || (data as any)?.error) { toast.error((data as any)?.error || 'Validation impossible.'); return; }
      toast.success('Document validé');
      charger();
    } finally {
      setValidationEnCours(null);
    }
  };

  const charger = async () => {
    setLoading(true);

    const { data: s } = await supabase
      .from('soignants')
      .select('*')
      .eq('id', id!)
      .maybeSingle();

    if (s) {
      setSoignant(s);
      setType('soignant');

      // RGPD — tracer la consultation d'un soignant par un admin (Art. 32 + droit d'accès)
      const { data: { user: currentUser } } = await supabase.auth.getUser();
      if (currentUser) {
        supabase.rpc('fn_ecrire_audit_safe', {
          p_acteur_id: currentUser.id,
          p_type_acteur: 'ADMIN_PLATEFORME',
          p_action: 'ADMIN_CONSULTATION_SOIGNANT',
          p_type_ressource: 'soignant',
          p_id_ressource: id!,
          p_cle_s3: null,
          p_details: { contexte: 'page_detail_utilisateur', profession: s.profession },
          p_ip: null,
          p_navigateur: navigator.userAgent,
        }).then(() => {});
      }

      const [docRes, missRes, reqRes] = await Promise.all([
        supabase.from('documents_soignants').select('*').eq('soignant_id', id!).is('supprime_le', null).order('televerse_le', { ascending: false }),
        supabase.from('missions').select('id, intitule, statut, debut_le, fin_le, taux_horaire_base, duree_heures, net_a_payer, etablissement_id, etablissements(nom)').eq('soignant_assigne_id', id!).order('debut_le', { ascending: false }).limit(100),
        supabase.from('documents_requis_par_profession').select('type_document, est_critique').eq('profession', s.profession),
      ]);
      if (docRes.data) setDocuments(docRes.data);
      if (missRes.data) setMissions(missRes.data);

      // Determine missing/expired documents
      if (reqRes.data && docRes.data) {
        const existingTypes = new Set(docRes.data.filter(d => d.statut_verification !== 'REJETE').map(d => d.type_document));
        const missing = reqRes.data.filter(r => !existingTypes.has(r.type_document)).map(r => TYPES_DOCUMENTS[r.type_document] || r.type_document);
        setDocumentsMissing(missing);
        
        const now = new Date();
        const expired = docRes.data.filter(d => d.valide_jusqua && new Date(d.valide_jusqua) < now).map(d => TYPES_DOCUMENTS[d.type_document] || d.type_document);
        setDocumentsExpires(expired);
      }

      // Check last reminder sent
      const { data: lastEmail } = await supabase
        .from('emails_envoyes')
        .select('cree_le')
        .eq('destinataire_id', id!)
        .eq('type', 'RAPPEL_DOCUMENTS')
        .order('cree_le', { ascending: false })
        .limit(1)
        .maybeSingle();
      
      setDernierRappel(lastEmail?.cree_le || null);
    } else {
      const { data: e } = await supabase
        .from('etablissements')
        .select('*')
        .eq('id', id!)
        .maybeSingle();

      if (e) {
        setEtablissement(e);
        setType('etablissement');

        // RGPD — tracer la consultation d'un établissement par un admin
        const { data: { user: currentUser } } = await supabase.auth.getUser();
        if (currentUser) {
          supabase.rpc('fn_ecrire_audit_safe', {
            p_acteur_id: currentUser.id,
            p_type_acteur: 'ADMIN_PLATEFORME',
            p_action: 'ADMIN_CONSULTATION_ETABLISSEMENT',
            p_type_ressource: 'etablissement',
            p_id_ressource: id!,
            p_cle_s3: null,
            p_details: { contexte: 'page_detail_utilisateur', nom: e.nom },
            p_ip: null,
            p_navigateur: navigator.userAgent,
          }).then(() => {});
        }

        const { data: missData } = await supabase
          .from('missions')
          .select('id, intitule, statut, debut_le, fin_le, taux_horaire_base, duree_heures, soignant_assigne_id, soignants(prenom, nom)')
          .eq('etablissement_id', id!)
          .order('debut_le', { ascending: false })
          .limit(100);
        if (missData) setMissions(missData);
      }
    }

    setLoading(false);
  };

  const envoyerRappelDocuments = async () => {
    if (!soignant || !id) return;
    setEnvoiRappel(true);

    const allMissing = [...documentsMissing, ...documentsExpires];
    const payload = {
      type: 'RAPPEL_DOCUMENTS',
      destinataire_id: id,
      data: {
        prenom: soignant.prenom,
        documents_manquants: allMissing,
      },
    };

    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session?.access_token) {
        toast.error('Session expirée. Veuillez vous reconnecter.');
        setEnvoiRappel(false);
        return;
      }

      try {
        const supabaseUrl = SUPABASE_URL;
        const publishableKey = SUPABASE_PUBLISHABLE_KEY;
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 10000);
        const res = await fetch(`${supabaseUrl}/functions/v1/send-email`, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${session.access_token}`,
            'Content-Type': 'application/json',
            apikey: publishableKey,
          },
          body: JSON.stringify(payload),
          signal: controller.signal,
        });
        clearTimeout(timeoutId);

        const data = await res.json().catch(() => null);
        if (!res.ok) {
          throw new Error(data?.error || `HTTP ${res.status}`);
        }
      } catch (fetchError: any) {
        const { error } = await supabase.functions.invoke('send-email', {
          body: payload,
        });
        if (error) throw error;
        if (fetchError?.message && fetchError.message !== 'Failed to fetch') {
          logger.warn('send-email fetch fallback used:', fetchError.message);
        }
      }

      toast.success(`Rappel envoyé à ${soignant.prenom}`);
      setDernierRappel(new Date().toISOString());
    } catch (err: any) {
      logger.error('send-email exception:', err);
      toast.error("Erreur lors de l'envoi du rappel. Veuillez réessayer.");
    }
    setEnvoiRappel(false);
  };

  const suspendre = async () => {
    const table = type === 'soignant' ? 'soignants' : 'etablissements';
    const entity = type === 'soignant' ? soignant : etablissement;
    const isSuspended = !!entity?.supprime_le;

    // Lot 21 : suspendre exige un motif (journalisé). Réactiver : pas de motif.
    if (!isSuspended && !motifSuspension.trim()) {
      toast.error('Motif obligatoire pour suspendre le compte.');
      return;
    }

    const { data, error } = await supabase.rpc('fn_admin_suspendre_utilisateur' as any, {
      p_table: table,
      p_id: id!,
      p_suspendre: !isSuspended,
      p_motif: !isSuspended ? motifSuspension.trim() : null,
    });

    if (error || (data as any)?.error) {
      toast.error((data as any)?.error || 'Erreur lors de la mise à jour du compte.');
      return;
    }
    toast.success(isSuspended ? 'Compte réactivé' : 'Compte suspendu');
    setModalSuspendre(false);
    setMotifSuspension('');
    charger();
  };

  const supprimerCompte = async () => {
    toast.error('Pour des raisons de sécurité, la suppression définitive ne peut pas être effectuée depuis cette interface. Elle requiert une intervention technique.');
  };

  const reinitialiserMdp = async () => {
    const email = type === 'soignant' ? soignant?.email : etablissement?.email_contact;
    if (!email) { toast.error('Aucun email trouvé'); return; }
    const { error } = await supabase.auth.resetPasswordForEmail(email);
    if (error) { toast.error('Erreur lors de l\'envoi. Vérifiez l\'email.'); return; }
    toast.success(`Email de réinitialisation envoyé à ${email}`);
  };

  const promouvoirAdmin = async () => {
    toast.info('Fonctionnalité de promotion admin — utilisez la fonction set-user-claims via le dashboard Supabase.');
  };

  const leverSuspension = async () => {
    if (!raisonLeverSuspension.trim()) { toast.error('Raison obligatoire.'); return; }
    const { data, error } = await supabase.rpc('fn_admin_lever_suspension' as any, {
      p_soignant_id: id!,
      p_raison: raisonLeverSuspension.trim(),
    });
    if (error || (data as any)?.error) { toast.error((data as any)?.error || error?.message || 'Erreur.'); return; }
    toast.success('Suspension levée');
    setModalLeverSuspension(false);
    setRaisonLeverSuspension('');
    charger();
  };

  const forcerReuploadRib = async () => {
    if (!raisonForceRib.trim()) { toast.error('Raison obligatoire.'); return; }
    const { data, error } = await supabase.rpc('fn_admin_forcer_reupload_rib' as any, {
      p_etablissement_id: id!,
      p_raison: raisonForceRib.trim(),
    });
    if (error || (data as any)?.error) { toast.error((data as any)?.error || error?.message || 'Erreur.'); return; }
    toast.success('Re-upload RIB forcé — l\'établissement sera notifié');
    setModalForceRib(false);
    setRaisonForceRib('');
  };

  if (loading) return <LayoutAdmin><ChargementAdmin titre="Détail utilisateur" /></LayoutAdmin>;

  if (!soignant && !etablissement) {
    return (
      <LayoutAdmin>
        <div className="text-center py-20">
          <h1 className="text-2xl font-bold text-foreground">Utilisateur introuvable</h1>
          <p className="mt-2 text-muted-foreground">Ce compte n’existe pas ou n’est plus accessible.</p>
          <BoutonY2K variant="secondary" className="mt-4" onClick={() => navigate('/admin/utilisateurs')} iconeGauche={<ArrowLeft className="h-4 w-4" />}>
            Retour
          </BoutonY2K>
        </div>
      </LayoutAdmin>
    );
  }

  const entity = soignant || etablissement;
  const isSuspended = !!entity?.supprime_le;
  const nom = type === 'soignant' ? `${soignant.prenom} ${soignant.nom}` : etablissement.nom;
  const hasDocIssues = type === 'soignant' && (documentsMissing.length > 0 || documentsExpires.length > 0);

  return (
    <LayoutAdmin>
      {/* Breadcrumb */}
      <nav className="flex items-center gap-1.5 text-sm text-muted-foreground mb-4" aria-label="Fil d'Ariane">
        <Link to="/admin" className="hover:text-foreground transition-colors">Admin</Link>
        <ChevronRight className="h-3.5 w-3.5" />
        <Link to="/admin/utilisateurs" className="hover:text-foreground transition-colors">Utilisateurs</Link>
        <ChevronRight className="h-3.5 w-3.5" />
        <span className="text-foreground font-medium">{nom}</span>
      </nav>

      <div className="flex items-center gap-3 mb-6">
        <Button aria-label="Retour à la liste des utilisateurs" variant="ghost" size="icon" onClick={() => navigate('/admin/utilisateurs')}>
          <ArrowLeft className="h-5 w-5" aria-hidden="true" />
        </Button>
        <div className="flex-1">
          <div className="flex items-center gap-2">
            <h1 className="text-2xl font-bold text-foreground">{nom}</h1>
            <button
              type="button"
              onClick={async () => {
                const { data, error } = await supabaseClient.rpc('fn_obtenir_conversation', { p_autre_id: id!, p_mission_id: null });
                logger.debug('fn_obtenir_conversation (admin):', { data, error });
                if (data) navigate(`/admin/messagerie?conv=${data}`);
                else {
                  logger.error('fn_obtenir_conversation error:', error);
                  toast.error("Impossible d'ouvrir la conversation.");
                }
              }}
              className="h-8 w-8 rounded-full bg-primary text-primary-foreground flex items-center justify-center hover:bg-primary/90 transition-colors shrink-0"
              title="Contacter"
            >
              <MessageCircle className="h-4 w-4" />
            </button>
          </div>
          <div className="flex items-center gap-2 mt-1">
            <BadgeY2K variant="info">{type === 'soignant' ? 'Soignant' : 'Établissement'}</BadgeY2K>
            {isSuspended ? (
              <BadgeY2K variant="error">Suspendu</BadgeY2K>
            ) : (
              <BadgeY2K variant="success">Actif</BadgeY2K>
            )}
          </div>
        </div>
      </div>

      {/* Documents alert banner */}
      {hasDocIssues && (
        <div className="mb-4 rounded-lg border border-warning/50 bg-warning/10 p-4 flex flex-col sm:flex-row items-start sm:items-center gap-3">
          <AlertTriangle className="h-5 w-5 text-warning shrink-0" />
          <div className="flex-1">
            <p className="text-sm font-medium text-foreground">
              {documentsMissing.length > 0 && `Documents manquants : ${documentsMissing.join(', ')}`}
              {documentsMissing.length > 0 && documentsExpires.length > 0 && ' · '}
              {documentsExpires.length > 0 && `Documents expirés : ${documentsExpires.join(', ')}`}
            </p>
            {dernierRappel && (
              <p className="text-xs text-muted-foreground mt-1">
                Dernier rappel envoyé le {new Date(dernierRappel).toLocaleDateString('fr-FR', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' })}
              </p>
            )}
          </div>
          <BoutonY2K size="sm" variant="secondary" onClick={envoyerRappelDocuments} disabled={envoiRappel} loading={envoiRappel} iconeGauche={envoiRappel ? undefined : <Send className="h-3.5 w-3.5" />}>
            {envoiRappel ? 'Envoi…' : 'Envoyer un rappel'}
          </BoutonY2K>
        </div>
      )}

      <Tabs defaultValue="infos" className="space-y-4">
        <TabsList className="flex-wrap">
          <TabsTrigger value="infos">Informations</TabsTrigger>
          {type === 'soignant' && <TabsTrigger value="documents">Documents</TabsTrigger>}
          <TabsTrigger value="missions">Missions</TabsTrigger>
          {type === 'soignant' && <TabsTrigger value="score">Score & Badges</TabsTrigger>}
          <TabsTrigger value="profil">Profil complet</TabsTrigger>
          <TabsTrigger value="actions">Actions admin</TabsTrigger>
        </TabsList>

        {/* ── 1. Informations personnelles ── */}
        <TabsContent value="infos">
          <CardY2K noPadding>
            <CardY2KHeader><CardY2KTitle className="text-lg">Informations personnelles</CardY2KTitle></CardY2KHeader>
            <CardY2KContent>
              {type === 'soignant' ? (
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <InfoRow icon={Mail} label="Email" value={soignant.email} />
                  <InfoRow icon={Phone} label="Téléphone" value={soignant.telephone || '—'} />
                  <InfoRow icon={Calendar} label="Date de naissance" value={soignant.date_naissance ? new Date(soignant.date_naissance).toLocaleDateString('fr-FR') : '—'} />
                  <InfoRow icon={Shield} label="Profession" value={soignant.profession ? getLabelProfession(soignant.profession) : '—'} />
                  <InfoRow icon={FileText} label="RPPS" value={soignant.numero_rpps || '—'} />
                  <InfoRow icon={FileText} label="ADELI" value={soignant.numero_adeli || '—'} />
                  <InfoRow icon={MapPin} label="Coordonnées GPS" value={soignant.adresse_lat ? `${soignant.adresse_lat}, ${soignant.adresse_lng}` : '—'} />
                  <InfoRow icon={MapPin} label="Rayon déplacement" value={`${soignant.rayon_deplacement_km} km`} />
                  <InfoRow icon={Clock} label="Inscrit le" value={new Date(soignant.cree_le).toLocaleDateString('fr-FR')} />
                  <InfoRow icon={Clock} label="Dernière activité" value={soignant.derniere_activite_le ? new Date(soignant.derniere_activite_le).toLocaleDateString('fr-FR') : '—'} />
                </div>
              ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <InfoRow icon={Mail} label="Email contact" value={etablissement.email_contact} />
                  <InfoRow icon={Phone} label="Téléphone" value={etablissement.telephone_contact || '—'} />
                  <InfoRow icon={FileText} label="SIRET" value={etablissement.siret} />
                  <InfoRow icon={FileText} label="FINESS" value={etablissement.finess || '—'} />
                  <InfoRow icon={Shield} label="Type" value={getLabelTypeEtablissement(etablissement.type)} />
                  <InfoRow icon={MapPin} label="Adresse" value={`${etablissement.adresse_rue}, ${etablissement.adresse_code_postal} ${etablissement.adresse_ville}`} />
                  <InfoRow icon={Clock} label="Inscrit le" value={new Date(etablissement.cree_le).toLocaleDateString('fr-FR')} />
                  <InfoRow icon={FileText} label="Formule" value={etablissement.formule_abonnement || '—'} />
                  <InfoRow icon={FileText} label="Taux commission" value={`${etablissement.taux_commission_negocie}%`} />
                  <InfoRow icon={FileText} label="Délai paiement" value={`${etablissement.delai_paiement_jours} jour${etablissement.delai_paiement_jours > 1 ? 's' : ''}`} />
                </div>
              )}
            </CardY2KContent>
          </CardY2K>
        </TabsContent>

        {/* ── 2. Documents ── */}
        {type === 'soignant' && (
          <TabsContent value="documents">
            <CardY2K noPadding>
              <CardY2KHeader><CardY2KTitle className="text-lg">Documents ({documents.length})</CardY2KTitle></CardY2KHeader>
              <CardY2KContent>
                {/* Upload admin : documents reçus en privé, validés à l'ajout */}
                <div className="rounded-xl border border-primary/30 bg-primary/5 p-3 mb-4 flex flex-col sm:flex-row sm:items-center gap-2">
                  <p className="text-xs text-muted-foreground flex-1">
                    Le soignant vous a envoyé un document en privé ? Ajoutez-le ici : il sera validé immédiatement.
                  </p>
                  <select
                    aria-label="Type du document à ajouter"
                    value={uploadDocType}
                    onChange={(e) => setUploadDocType(e.target.value)}
                    className="input-base text-xs h-9 sm:w-44"
                  >
                    {Object.entries(TYPES_DOCUMENTS).map(([val, label]) => (
                      <option key={val} value={val}>{label}</option>
                    ))}
                  </select>
                  <label className={`inline-flex items-center justify-center gap-1.5 rounded-xl px-3 h-9 text-xs font-semibold cursor-pointer bg-primary text-primary-foreground hover:bg-primary/90 ${uploadEnCours ? 'opacity-50 pointer-events-none' : ''}`}>
                    {uploadEnCours ? 'Envoi…' : 'Choisir le fichier'}
                    <input
                      type="file"
                      accept="image/*,.pdf"
                      className="hidden"
                      disabled={uploadEnCours}
                      onChange={(e) => {
                        const f = e.target.files?.[0];
                        if (f) uploaderPourSoignant(f);
                        e.target.value = '';
                      }}
                    />
                  </label>
                </div>
                {documents.length === 0 ? (
                  <p className="text-sm text-muted-foreground">Aucun document téléversé.</p>
                ) : (
                  <>
                    {/* Desktop : table */}
                    <div className="hidden md:block rounded-lg border overflow-x-auto">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Type</TableHead>
                            <TableHead>Fichier</TableHead>
                            <TableHead>Statut</TableHead>
                            <TableHead>Validité</TableHead>
                            <TableHead>Téléversé le</TableHead>
                            <TableHead></TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {documents.map((doc) => {
                            const statutInfo = STATUTS_VERIFICATION[doc.statut_verification] || { label: doc.statut_verification, couleur: 'bg-muted text-muted-foreground' };
                            return (
                              <TableRow key={doc.id}>
                                <TableCell className="font-medium">{TYPES_DOCUMENTS[doc.type_document] || doc.type_document}</TableCell>
                                <TableCell className="text-xs text-muted-foreground max-w-[200px] truncate">{doc.nom_fichier}</TableCell>
                                <TableCell>
                                  <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-medium ${statutInfo.couleur}`}>
                                    {statutInfo.label}
                                  </span>
                                </TableCell>
                                <TableCell className="text-xs">
                                  {doc.valide_jusqua ? new Date(doc.valide_jusqua).toLocaleDateString('fr-FR') : '—'}
                                </TableCell>
                                <TableCell className="text-xs">
                                  {doc.televerse_le ? new Date(doc.televerse_le).toLocaleDateString('fr-FR') : '—'}
                                </TableCell>
                                <TableCell>
                                  {doc.statut_verification !== 'VERIFIE' && (
                                    <BoutonY2K
                                      size="sm"
                                      variant="secondary"
                                      onClick={() => validerDocument(doc.id)}
                                      disabled={validationEnCours === doc.id}
                                      loading={validationEnCours === doc.id}
                                    >
                                      Valider
                                    </BoutonY2K>
                                  )}
                                </TableCell>
                              </TableRow>
                            );
                          })}
                        </TableBody>
                      </Table>
                    </div>

                    {/* Mobile : cards */}
                    <div className="md:hidden space-y-3">
                      {documents.map((doc) => {
                        const statutInfo = STATUTS_VERIFICATION[doc.statut_verification] || { label: doc.statut_verification, couleur: 'bg-muted text-muted-foreground' };
                        return (
                          <div key={doc.id} className="rounded-xl border border-border bg-card p-3 space-y-2">
                            <div className="flex items-start justify-between gap-2">
                              <p className="text-sm font-semibold text-foreground">{TYPES_DOCUMENTS[doc.type_document] || doc.type_document}</p>
                              <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-medium shrink-0 ${statutInfo.couleur}`}>
                                {statutInfo.label}
                              </span>
                            </div>
                            <p className="text-xs text-muted-foreground break-words">{doc.nom_fichier}</p>
                            <div className="flex items-center justify-between text-[11px] text-muted-foreground border-t border-border/40 pt-2">
                              <span>Téléversé : {doc.televerse_le ? new Date(doc.televerse_le).toLocaleDateString('fr-FR') : '—'}</span>
                              <span>Validité : {doc.valide_jusqua ? new Date(doc.valide_jusqua).toLocaleDateString('fr-FR') : '—'}</span>
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  </>
                )}
              </CardY2KContent>
            </CardY2K>
          </TabsContent>
        )}

        {/* ── 3. Missions ── */}
        <TabsContent value="missions">
          <CardY2K noPadding>
            <CardY2KHeader><CardY2KTitle className="text-lg">Historique des missions ({missions.length})</CardY2KTitle></CardY2KHeader>
            <CardY2KContent>
              {missions.length === 0 ? (
                <p className="text-sm text-muted-foreground">Aucune mission.</p>
              ) : (
                <>
                  {/* Desktop : table */}
                  <div className="hidden md:block rounded-lg border overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Intitulé</TableHead>
                          {type === 'soignant' && <TableHead>Établissement</TableHead>}
                          {type === 'etablissement' && <TableHead>Soignant</TableHead>}
                          <TableHead>Début</TableHead>
                          <TableHead>Durée</TableHead>
                          <TableHead>Statut</TableHead>
                          {type === 'soignant' && <TableHead>Net</TableHead>}
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {missions.map((m: any) => (
                          <TableRow key={m.id}>
                            <TableCell className="font-medium">{m.intitule}</TableCell>
                            {type === 'soignant' && <TableCell className="text-xs">{(m.etablissements as any)?.nom || '—'}</TableCell>}
                            {type === 'etablissement' && <TableCell className="text-xs">{(m.soignants as any) ? `${(m.soignants as any).prenom} ${(m.soignants as any).nom}` : '—'}</TableCell>}
                            <TableCell className="text-xs">{new Date(m.debut_le).toLocaleDateString('fr-FR')}</TableCell>
                            <TableCell className="text-xs">{m.duree_heures ? `${m.duree_heures}h` : '—'}</TableCell>
                            <TableCell>
                              <BadgeY2K variant="info" size="sm">{BADGES_STATUT[m.statut]?.label || m.statut}</BadgeY2K>
                            </TableCell>
                            {type === 'soignant' && <TableCell className="text-xs font-mono">{m.net_a_payer ? formatEuroAdmin(m.net_a_payer) : '—'}</TableCell>}
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </div>

                  {/* Mobile : cards */}
                  <div className="md:hidden space-y-3">
                    {missions.map((m: any) => {
                      const statutLabel = BADGES_STATUT[m.statut]?.label || m.statut;
                      const contrepartie = type === 'soignant'
                        ? ((m.etablissements as any)?.nom || '—')
                        : ((m.soignants as any) ? `${(m.soignants as any).prenom} ${(m.soignants as any).nom}` : '—');
                      return (
                        <div key={m.id} className="rounded-xl border border-border bg-card p-3 space-y-2">
                          <div className="flex items-start justify-between gap-2">
                            <p className="text-sm font-semibold truncate">{m.intitule}</p>
                            <BadgeY2K variant="info" size="sm" className="shrink-0">{statutLabel}</BadgeY2K>
                          </div>
                          <div className="grid grid-cols-1 gap-1 text-xs">
                            <div className="flex items-start justify-between gap-2">
                              <span className="text-muted-foreground shrink-0">{type === 'soignant' ? 'Établissement' : 'Soignant'}</span>
                              <span className="text-foreground text-right truncate">{contrepartie}</span>
                            </div>
                            <div className="flex items-start justify-between gap-2">
                              <span className="text-muted-foreground shrink-0">Début</span>
                              <span className="text-foreground">{new Date(m.debut_le).toLocaleDateString('fr-FR')}</span>
                            </div>
                            <div className="flex items-start justify-between gap-2">
                              <span className="text-muted-foreground shrink-0">Durée</span>
                              <span className="text-foreground">{m.duree_heures ? `${m.duree_heures}h` : '—'}</span>
                            </div>
                            {type === 'soignant' && (
                              <div className="flex items-start justify-between gap-2">
                                <span className="text-muted-foreground shrink-0">Net</span>
                                <span className="text-foreground font-mono">{m.net_a_payer ? formatEuroAdmin(m.net_a_payer) : '—'}</span>
                              </div>
                            )}
                          </div>
                        </div>
                      );
                    })}
                  </div>
                </>
              )}
            </CardY2KContent>
          </CardY2K>
        </TabsContent>

        {/* ── 4. Score & Badges ── */}
        {type === 'soignant' && (
          <TabsContent value="score">
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <CardY2K noPadding>
                <CardY2KContent className="pt-6 text-center">
                  <div className="text-2xl sm:text-4xl font-bold text-primary">{soignant.score_fiabilite != null && soignant.total_missions_terminees > 0 ? soignant.score_fiabilite : '—'}</div>
                  <p className="text-sm text-muted-foreground mt-1">{soignant.score_fiabilite != null && soignant.total_missions_terminees > 0 ? 'Score de fiabilité / 100' : 'Pas encore d\'évaluation'}</p>
                </CardY2KContent>
              </CardY2K>
              <CardY2K noPadding>
                <CardY2KContent className="pt-6 text-center">
                  <div className="text-2xl sm:text-4xl font-bold text-foreground">{soignant.total_missions_terminees}</div>
                  <p className="text-sm text-muted-foreground mt-1">Missions terminées</p>
                </CardY2KContent>
              </CardY2K>
              <CardY2K noPadding>
                <CardY2KContent className="pt-6 text-center">
                  <div className="text-2xl sm:text-4xl font-bold text-foreground">{soignant.heures_cumulees}h</div>
                  <p className="text-sm text-muted-foreground mt-1">Heures cumulées</p>
                </CardY2KContent>
              </CardY2K>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4">
              <CardY2K noPadding>
                <CardY2KHeader><CardY2KTitle className="text-sm">Vérifications</CardY2KTitle></CardY2KHeader>
                <CardY2KContent className="space-y-2">
                  <VerifRow label="Identité vérifiée" ok={soignant.identite_verifiee} />
                  <VerifRow label="Diplôme vérifié" ok={soignant.diplome_verifie} />
                  <VerifRow label="RPPS vérifié" ok={soignant.rpps_verifie} />
                  <VerifRow label="Tous documents valides" ok={soignant.tous_documents_valides} />
                </CardY2KContent>
              </CardY2K>
              <CardY2K noPadding>
                <CardY2KHeader><CardY2KTitle className="text-sm">Statistiques</CardY2KTitle></CardY2KHeader>
                <CardY2KContent className="space-y-2">
                  <StatRow label="Missions annulées" value={soignant.total_missions_annulees} />
                  <StatRow label="Retards pointage" value={soignant.total_retards_pointage} />
                  <StatRow label="Absences" value={soignant.total_absences} />
                  <StatRow label="Éligible 3200h" value={soignant.eligible_conversion_3200h ? 'Oui' : 'Non'} />
                  <StatRow label="Prévoyance inscrit" value={soignant.prevoyance_inscrit ? 'Oui' : 'Non'} />
                </CardY2KContent>
              </CardY2K>
            </div>
          </TabsContent>
        )}

        {/* ── 5. Profil complet ── */}
        <TabsContent value="profil">
          {type === 'soignant' && soignant ? (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <CardY2K noPadding>
                <CardY2KHeader><CardY2KTitle className="text-sm">Identité</CardY2KTitle></CardY2KHeader>
                <CardY2KContent className="space-y-2">
                  <ProfileRow label="Prénom" value={soignant.prenom} />
                  <ProfileRow label="Nom" value={soignant.nom} />
                  <ProfileRow label="Email" value={soignant.email} />
                  <ProfileRow label="Téléphone" value={soignant.telephone || '—'} />
                  <ProfileRow label="Date de naissance" value={soignant.date_naissance ? new Date(soignant.date_naissance).toLocaleDateString('fr-FR') : '—'} />
                </CardY2KContent>
              </CardY2K>
              <CardY2K noPadding>
                <CardY2KHeader><CardY2KTitle className="text-sm">Professionnel</CardY2KTitle></CardY2KHeader>
                <CardY2KContent className="space-y-2">
                  <ProfileRow label="Profession" value={soignant.profession ? getLabelProfession(soignant.profession) : '—'} />
                  <ProfileRow label="Type de contrat" value={soignant.type_contrat || '—'} />
                  <ProfileRow label="RPPS" value={soignant.numero_rpps || '—'} />
                  <ProfileRow label="ADELI" value={soignant.numero_adeli || '—'} />
                  <ProfileRow label="Rayon déplacement" value={soignant.rayon_deplacement_km != null ? `${soignant.rayon_deplacement_km} km` : '—'} />
                </CardY2KContent>
              </CardY2K>
              <CardY2K noPadding>
                <CardY2KHeader><CardY2KTitle className="text-sm">Vérifications & Conformité</CardY2KTitle></CardY2KHeader>
                <CardY2KContent className="space-y-2">
                  <VerifRow label="Identité vérifiée" ok={soignant.identite_verifiee} />
                  <VerifRow label="Diplôme vérifié" ok={soignant.diplome_verifie} />
                  <VerifRow label="RPPS vérifié" ok={soignant.rpps_verifie} />
                  <VerifRow label="Tous documents valides" ok={soignant.tous_documents_valides} />
                  <ProfileRow label="Statut vérification ARIA" value={soignant.statut_verification_aria ? (STATUTS_VERIFICATION[soignant.statut_verification_aria]?.label || soignant.statut_verification_aria) : '—'} />
                </CardY2KContent>
              </CardY2K>
              <CardY2K noPadding>
                <CardY2KHeader><CardY2KTitle className="text-sm">Statistiques</CardY2KTitle></CardY2KHeader>
                <CardY2KContent className="space-y-2">
                  <ProfileRow label="Score fiabilité" value={soignant.score_fiabilite != null && soignant.total_missions_terminees > 0 ? `${soignant.score_fiabilite}/100` : 'Pas encore d\'évaluation'} />
                  <ProfileRow label="Missions terminées" value={soignant.total_missions_terminees ?? 0} />
                  <ProfileRow label="Missions annulées" value={soignant.total_missions_annulees ?? 0} />
                  <ProfileRow label="Heures cumulées" value={`${soignant.heures_cumulees ?? 0}h`} />
                  <ProfileRow label="Retards pointage" value={soignant.total_retards_pointage ?? 0} />
                  <ProfileRow label="Absences" value={soignant.total_absences ?? 0} />
                </CardY2KContent>
              </CardY2K>
              <CardY2K noPadding>
                <CardY2KHeader><CardY2KTitle className="text-sm">Prévoyance & Libéral</CardY2KTitle></CardY2KHeader>
                <CardY2KContent className="space-y-2">
                  <VerifRow label="Prévoyance inscrit" ok={soignant.prevoyance_inscrit} />
                  <ProfileRow label="Fournisseur prévoyance" value={soignant.prevoyance_fournisseur || '—'} />
                  <VerifRow label="Éligible 3200h" ok={soignant.eligible_conversion_3200h} />
                </CardY2KContent>
              </CardY2K>
              <CardY2K noPadding>
                <CardY2KHeader><CardY2KTitle className="text-sm">Localisation & Dates</CardY2KTitle></CardY2KHeader>
                <CardY2KContent className="space-y-2">
                  <ProfileRow label="Latitude" value={soignant.adresse_lat ?? '—'} />
                  <ProfileRow label="Longitude" value={soignant.adresse_lng ?? '—'} />
                  <ProfileRow label="Inscrit le" value={new Date(soignant.cree_le).toLocaleDateString('fr-FR')} />
                  <ProfileRow label="Dernière modification" value={soignant.modifie_le ? new Date(soignant.modifie_le).toLocaleDateString('fr-FR') : '—'} />
                </CardY2KContent>
              </CardY2K>
            </div>
          ) : etablissement ? (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <CardY2K noPadding>
                <CardY2KHeader><CardY2KTitle className="text-sm">Identité</CardY2KTitle></CardY2KHeader>
                <CardY2KContent className="space-y-2">
                  <ProfileRow label="Nom" value={etablissement.nom} />
                  <ProfileRow label="SIRET" value={etablissement.siret} />
                  <ProfileRow label="FINESS" value={etablissement.finess || '—'} />
                  <ProfileRow label="Type" value={getLabelTypeEtablissement(etablissement.type)} />
                  <ProfileRow label="Email contact" value={etablissement.email_contact} />
                  <ProfileRow label="Téléphone" value={etablissement.telephone_contact || '—'} />
                </CardY2KContent>
              </CardY2K>
              <CardY2K noPadding>
                <CardY2KHeader><CardY2KTitle className="text-sm">Adresse</CardY2KTitle></CardY2KHeader>
                <CardY2KContent className="space-y-2">
                  <ProfileRow label="Rue" value={etablissement.adresse_rue} />
                  <ProfileRow label="Ville" value={`${etablissement.adresse_code_postal} ${etablissement.adresse_ville}`} />
                  <ProfileRow label="Département" value={etablissement.adresse_departement || '—'} />
                  <ProfileRow label="Coordonnées" value={etablissement.adresse_lat ? `${etablissement.adresse_lat}, ${etablissement.adresse_lng}` : '—'} />
                </CardY2KContent>
              </CardY2K>
              <CardY2K noPadding>
                <CardY2KHeader><CardY2KTitle className="text-sm">Commercial</CardY2KTitle></CardY2KHeader>
                <CardY2KContent className="space-y-2">
                  <ProfileRow label="Formule" value={etablissement.formule_abonnement || '—'} />
                  <ProfileRow label="Taux commission" value={`${etablissement.taux_commission_negocie}%`} />
                  <ProfileRow label="Mode facturation" value={etablissement.mode_facturation || '—'} />
                  <ProfileRow label="Mode paiement" value={etablissement.mode_paiement_commission || '—'} />
                  <ProfileRow label="Délai paiement" value={`${etablissement.delai_paiement_jours} jour${etablissement.delai_paiement_jours > 1 ? 's' : ''}`} />
                </CardY2KContent>
              </CardY2K>
              <CardY2K noPadding>
                <CardY2KHeader><CardY2KTitle className="text-sm">Configuration</CardY2KTitle></CardY2KHeader>
                <CardY2KContent className="space-y-2">
                  <ProfileRow label="Convention collective" value={etablissement.convention_collective || '—'} />
                  <VerifRow label="Chorus Pro actif" ok={etablissement.chorus_pro_actif} />
                  <VerifRow label="Rist plafond actif" ok={etablissement.rist_plafond_actif} />
                  <ProfileRow label="Majoration nuit" value={`${etablissement.taux_majoration_nuit_pourcent}%`} />
                  <ProfileRow label="Majoration dimanche" value={`${etablissement.taux_majoration_dimanche_pourcent}%`} />
                  <ProfileRow label="Majoration férié" value={`${etablissement.taux_majoration_ferie_pourcent}%`} />
                </CardY2KContent>
              </CardY2K>
            </div>
          ) : null}
        </TabsContent>

        {/* ── 6. Actions admin ── */}
        <TabsContent value="actions">
          <CardY2K noPadding>
            <CardY2KHeader><CardY2KTitle className="text-lg">Actions administrateur</CardY2KTitle></CardY2KHeader>
            <CardY2KContent className="space-y-4">
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <ActionCard
                  icon={isSuspended ? RefreshCw : Ban}
                  label={isSuspended ? 'Réactiver le compte' : 'Suspendre le compte'}
                  description={isSuspended ? 'Rétablit l\'accès de l\'utilisateur à la plateforme.' : 'Bloque temporairement l\'accès de l\'utilisateur.'}
                  variant={isSuspended ? 'outline' : 'destructive'}
                  onClick={() => setModalSuspendre(true)}
                />
                <ActionCard
                  icon={KeyRound}
                  label="Réinitialiser le mot de passe"
                  description="Envoie un email de réinitialisation à l'utilisateur."
                  variant="outline"
                  onClick={reinitialiserMdp}
                />
                {type === 'soignant' && (
                  <ActionCard
                    icon={UserCog}
                    label="Promouvoir admin"
                    description="Donne les droits d'administration plateforme."
                    variant="outline"
                    onClick={promouvoirAdmin}
                  />
                )}
                {type === 'soignant' && isSuspended && (
                  <ActionCard
                    icon={RefreshCw}
                    label="Lever la suspension"
                    description="Lève la suspension du soignant avec motif audit."
                    variant="outline"
                    onClick={() => { setRaisonLeverSuspension(''); setModalLeverSuspension(true); }}
                  />
                )}
                {type === 'etablissement' && (
                  <ActionCard
                    icon={RefreshCw}
                    label="Forcer re-upload RIB"
                    description="Invalide le RIB actuel et demande un nouveau téléversement."
                    variant="outline"
                    onClick={() => { setRaisonForceRib(''); setModalForceRib(true); }}
                  />
                )}
                <ActionCard
                  icon={Trash2}
                  label="Supprimer le compte"
                  description="Suppression définitive et irréversible."
                  variant="destructive"
                  onClick={() => setModalSupprimer(true)}
                />
              </div>
            </CardY2KContent>
          </CardY2K>
        </TabsContent>
      </Tabs>

      {isSuspended ? (
        <ModalConfirmation
          ouvert={modalSuspendre}
          onFermer={() => setModalSuspendre(false)}
          onConfirmer={suspendre}
          titre="Réactiver le compte"
          message={`Voulez-vous réactiver le compte de ${nom} ?`}
          labelConfirmer="Réactiver"
          variante="primaire"
        />
      ) : (
        <ModalActionAvecRaison
          ouvert={modalSuspendre}
          onFermer={() => { setModalSuspendre(false); setMotifSuspension(''); }}
          onConfirmer={suspendre}
          titre="Suspendre le compte"
          message={`Voulez-vous suspendre le compte de ${nom} ? L'utilisateur ne pourra plus accéder à la plateforme. Le motif est obligatoire et journalisé dans l'audit.`}
          raison={motifSuspension}
          onChangeRaison={setMotifSuspension}
          placeholder="Motif de la suspension (obligatoire)"
          labelConfirmer="Suspendre le compte"
        />
      )}

      <ModalConfirmation
        ouvert={modalSupprimer}
        onFermer={() => setModalSupprimer(false)}
        onConfirmer={supprimerCompte}
        titre="Supprimer définitivement"
        message={`Attention : la suppression définitive de ${nom} est irréversible. Pour des raisons de sécurité, elle requiert une intervention technique en dehors de cette interface.`}
        labelConfirmer="Supprimer"
        variante="danger"
      />

      <ModalActionAvecRaison
        ouvert={modalLeverSuspension}
        onFermer={() => setModalLeverSuspension(false)}
        onConfirmer={leverSuspension}
        titre="Lever la suspension"
        message={`Voulez-vous lever la suspension de ${nom} ? Merci d'indiquer la raison de cette décision : elle sera conservée dans le journal d'audit.`}
        raison={raisonLeverSuspension}
        onChangeRaison={setRaisonLeverSuspension}
        placeholder="Raison de la levée de suspension (obligatoire)"
        labelConfirmer="Lever la suspension"
      />

      <ModalActionAvecRaison
        ouvert={modalForceRib}
        onFermer={() => setModalForceRib(false)}
        onConfirmer={forcerReuploadRib}
        titre="Demander un nouveau RIB"
        message={`Le RIB actuel de ${nom} sera invalidé et un nouveau téléversement sera demandé à l'établissement. Merci d'indiquer la raison de cette action.`}
        raison={raisonForceRib}
        onChangeRaison={setRaisonForceRib}
        placeholder="Raison de la demande (obligatoire)"
        labelConfirmer="Confirmer"
      />
    </LayoutAdmin>
  );
}

/* ── Small helper components ── */

function ModalActionAvecRaison({ ouvert, onFermer, onConfirmer, titre, message, raison, onChangeRaison, placeholder, labelConfirmer }: {
  ouvert: boolean;
  onFermer: () => void;
  onConfirmer: () => void;
  titre: string;
  message: string;
  raison: string;
  onChangeRaison: (valeur: string) => void;
  placeholder: string;
  labelConfirmer: string;
}) {
  const titleId = React.useId();
  const descId = React.useId();

  if (!ouvert) return null;

  return (
    <div
      className="fixed inset-0 z-[9999] flex items-center justify-center"
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
      aria-describedby={descId}
    >
      <div className="fixed inset-0 bg-foreground/50 backdrop-blur-sm" onClick={onFermer} aria-hidden="true" />
      <div className="fixed top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 bg-card rounded-2xl shadow-xl p-6 mx-4 max-w-md w-[calc(100%-2rem)]">
        <h3 id={titleId} className="text-lg font-bold text-foreground mb-2">{titre}</h3>
        <p id={descId} className="text-sm text-muted-foreground mb-4">{message}</p>
        <Textarea
          aria-label={placeholder}
          value={raison}
          onChange={(e) => onChangeRaison(e.target.value)}
          placeholder={placeholder}
          rows={3}
          className="mb-4"
        />
        <div className="flex gap-3 justify-end">
          <button onClick={onFermer} className="btn-secondary text-sm px-4 py-2" type="button">
            Annuler
          </button>
          <button onClick={onConfirmer} className="btn-primary text-sm px-4 py-2" type="button">
            {labelConfirmer}
          </button>
        </div>
      </div>
    </div>
  );
}

function ProfileRow({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="flex items-center justify-between text-sm">
      <span className="text-muted-foreground">{label}</span>
      <span className="font-medium text-foreground text-right max-w-[60%] truncate">{value}</span>
    </div>
  );
}

function InfoRow({ icon: Icon, label, value }: { icon: any; label: string; value: string }) {
  return (
    <div className="flex items-start gap-3">
      <Icon className="h-4 w-4 text-muted-foreground mt-0.5 shrink-0" />
      <div>
        <p className="text-xs text-muted-foreground">{label}</p>
        <p className="text-sm font-medium text-foreground">{value}</p>
      </div>
    </div>
  );
}

function VerifRow({ label, ok }: { label: string; ok: boolean }) {
  return (
    <div className="flex items-center justify-between text-sm">
      <span className="text-muted-foreground">{label}</span>
      {ok ? (
        <BadgeY2K variant="success" size="sm">Oui</BadgeY2K>
      ) : (
        <BadgeY2K variant="info" size="sm">Non</BadgeY2K>
      )}
    </div>
  );
}

function StatRow({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="flex items-center justify-between text-sm">
      <span className="text-muted-foreground">{label}</span>
      <span className="font-medium text-foreground">{value}</span>
    </div>
  );
}

function ActionCard({ icon: Icon, label, description, variant, onClick }: {
  icon: any;
  label: string;
  description: string;
  variant: 'outline' | 'destructive';
  onClick: () => void;
}) {
  return (
    <div className="border rounded-lg p-4 flex flex-col gap-2">
      <div className="flex items-center gap-2">
        <Icon className={`h-4 w-4 ${variant === 'destructive' ? 'text-destructive' : 'text-muted-foreground'}`} />
        <span className="text-sm font-medium text-foreground">{label}</span>
      </div>
      <p className="text-xs text-muted-foreground">{description}</p>
      <BoutonY2K size="sm" variant={variant === 'destructive' ? 'destructive' : 'secondary'} onClick={onClick} className="mt-auto self-start">
        {label}
      </BoutonY2K>
    </div>
  );
}
