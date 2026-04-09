import React, { useState, useEffect } from 'react';
import { useParams, useNavigate, Link } from 'react-router-dom';
import { ChevronRight, ArrowLeft, Mail, Phone, MapPin, Calendar, Shield, Star, Award, FileText, Clock, Ban, RefreshCw, Trash2, KeyRound, UserCog, AlertTriangle, MessageCircle, Send } from 'lucide-react';
import { supabase as supabaseClient } from '@/integrations/supabase/client';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Separator } from '@/components/ui/separator';
import { toast } from 'sonner';
import { logger } from '@/lib/logger';
import { usePageTitle } from '@/hooks/usePageTitle';
import { TYPES_DOCUMENTS, STATUTS_VERIFICATION } from '@/lib/documents';
import { ModalConfirmation } from '@/components/ModalConfirmation';
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
  const [modalSupprimer, setModalSupprimer] = useState(false);
  const [documentsMissing, setDocumentsMissing] = useState<string[]>([]);
  const [documentsExpires, setDocumentsExpires] = useState<string[]>([]);
  const [dernierRappel, setDernierRappel] = useState<string | null>(null);
  const [envoiRappel, setEnvoiRappel] = useState(false);

  usePageTitle('Détail utilisateur');

  useEffect(() => {
    if (!id) return;
    charger();
  }, [id]);

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
        const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
        const publishableKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
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

    const { error } = await supabase
      .from(table as any)
      .update({ supprime_le: isSuspended ? null : new Date().toISOString() } as any)
      .eq('id', id!);

    if (error) { toast.error('Erreur lors de la mise à jour du compte.'); return; }
    toast.success(isSuspended ? 'Compte réactivé' : 'Compte suspendu');
    charger();
  };

  const supprimerCompte = async () => {
    toast.error('La suppression définitive nécessite une action manuelle dans le dashboard Supabase pour des raisons de sécurité.');
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

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  if (!soignant && !etablissement) {
    return (
      <LayoutAdmin>
        <div className="text-center py-20">
          <p className="text-muted-foreground">Utilisateur introuvable.</p>
          <Button variant="outline" className="mt-4" onClick={() => navigate('/admin/utilisateurs')}>
            <ArrowLeft className="h-4 w-4 mr-1" /> Retour
          </Button>
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
        <Button variant="ghost" size="icon" onClick={() => navigate('/admin/utilisateurs')}>
          <ArrowLeft className="h-5 w-5" />
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
            <Badge variant="outline" className="text-xs">{type === 'soignant' ? 'Soignant' : 'Établissement'}</Badge>
            {isSuspended ? (
              <Badge variant="destructive" className="text-xs">Suspendu</Badge>
            ) : (
              <Badge className="bg-success text-success-foreground text-xs">Actif</Badge>
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
          <Button size="sm" variant="outline" onClick={envoyerRappelDocuments} disabled={envoiRappel}>
            <Send className="h-3.5 w-3.5 mr-1" />
            {envoiRappel ? 'Envoi…' : 'Envoyer un rappel'}
          </Button>
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
          <Card>
            <CardHeader><CardTitle className="text-lg">Informations personnelles</CardTitle></CardHeader>
            <CardContent>
              {type === 'soignant' ? (
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <InfoRow icon={Mail} label="Email" value={soignant.email} />
                  <InfoRow icon={Phone} label="Téléphone" value={soignant.telephone || '—'} />
                  <InfoRow icon={Calendar} label="Date de naissance" value={soignant.date_naissance ? new Date(soignant.date_naissance).toLocaleDateString('fr-FR') : '—'} />
                  <InfoRow icon={Shield} label="Profession" value={soignant.profession} />
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
                  <InfoRow icon={Shield} label="Type" value={etablissement.type} />
                  <InfoRow icon={MapPin} label="Adresse" value={`${etablissement.adresse_rue}, ${etablissement.adresse_code_postal} ${etablissement.adresse_ville}`} />
                  <InfoRow icon={Clock} label="Inscrit le" value={new Date(etablissement.cree_le).toLocaleDateString('fr-FR')} />
                  <InfoRow icon={FileText} label="Formule" value={etablissement.formule_abonnement || '—'} />
                  <InfoRow icon={FileText} label="Taux commission" value={`${etablissement.taux_commission_negocie}%`} />
                  <InfoRow icon={FileText} label="Délai paiement" value={`${etablissement.delai_paiement_jours} jours`} />
                </div>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        {/* ── 2. Documents ── */}
        {type === 'soignant' && (
          <TabsContent value="documents">
            <Card>
              <CardHeader><CardTitle className="text-lg">Documents ({documents.length})</CardTitle></CardHeader>
              <CardContent>
                {documents.length === 0 ? (
                  <p className="text-sm text-muted-foreground">Aucun document téléversé.</p>
                ) : (
                  <div className="rounded-lg border overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Type</TableHead>
                          <TableHead>Fichier</TableHead>
                          <TableHead>Statut</TableHead>
                          <TableHead>Validité</TableHead>
                          <TableHead>Téléversé le</TableHead>
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
                            </TableRow>
                          );
                        })}
                      </TableBody>
                    </Table>
                  </div>
                )}
              </CardContent>
            </Card>
          </TabsContent>
        )}

        {/* ── 3. Missions ── */}
        <TabsContent value="missions">
          <Card>
            <CardHeader><CardTitle className="text-lg">Historique des missions ({missions.length})</CardTitle></CardHeader>
            <CardContent>
              {missions.length === 0 ? (
                <p className="text-sm text-muted-foreground">Aucune mission.</p>
              ) : (
                <div className="rounded-lg border overflow-x-auto">
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
                            <Badge variant="outline" className="text-[10px]">{m.statut}</Badge>
                          </TableCell>
                          {type === 'soignant' && <TableCell className="text-xs font-mono">{m.net_a_payer ? `${Number(m.net_a_payer).toFixed(2)} €` : '—'}</TableCell>}
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        {/* ── 4. Score & Badges ── */}
        {type === 'soignant' && (
          <TabsContent value="score">
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <Card>
                <CardContent className="pt-6 text-center">
                  <div className="text-2xl sm:text-4xl font-bold text-primary">{soignant.score_fiabilite != null && soignant.total_missions_terminees > 0 ? soignant.score_fiabilite : '—'}</div>
                  <p className="text-sm text-muted-foreground mt-1">{soignant.score_fiabilite != null && soignant.total_missions_terminees > 0 ? 'Score de fiabilité / 100' : 'Pas encore d\'évaluation'}</p>
                </CardContent>
              </Card>
              <Card>
                <CardContent className="pt-6 text-center">
                  <div className="text-2xl sm:text-4xl font-bold text-foreground">{soignant.total_missions_terminees}</div>
                  <p className="text-sm text-muted-foreground mt-1">Missions terminées</p>
                </CardContent>
              </Card>
              <Card>
                <CardContent className="pt-6 text-center">
                  <div className="text-2xl sm:text-4xl font-bold text-foreground">{soignant.heures_cumulees}h</div>
                  <p className="text-sm text-muted-foreground mt-1">Heures cumulées</p>
                </CardContent>
              </Card>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4">
              <Card>
                <CardHeader><CardTitle className="text-sm">Vérifications</CardTitle></CardHeader>
                <CardContent className="space-y-2">
                  <VerifRow label="Identité vérifiée" ok={soignant.identite_verifiee} />
                  <VerifRow label="Diplôme vérifié" ok={soignant.diplome_verifie} />
                  <VerifRow label="RPPS vérifié" ok={soignant.rpps_verifie} />
                  <VerifRow label="Tous documents valides" ok={soignant.tous_documents_valides} />
                </CardContent>
              </Card>
              <Card>
                <CardHeader><CardTitle className="text-sm">Statistiques</CardTitle></CardHeader>
                <CardContent className="space-y-2">
                  <StatRow label="Missions annulées" value={soignant.total_missions_annulees} />
                  <StatRow label="Retards pointage" value={soignant.total_retards_pointage} />
                  <StatRow label="Absences" value={soignant.total_absences} />
                  <StatRow label="Éligible 3200h" value={soignant.eligible_conversion_3200h ? 'Oui' : 'Non'} />
                  <StatRow label="Prévoyance inscrit" value={soignant.prevoyance_inscrit ? 'Oui' : 'Non'} />
                </CardContent>
              </Card>
            </div>
          </TabsContent>
        )}

        {/* ── 5. Profil complet ── */}
        <TabsContent value="profil">
          {type === 'soignant' && soignant ? (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <Card>
                <CardHeader><CardTitle className="text-sm">Identité</CardTitle></CardHeader>
                <CardContent className="space-y-2">
                  <ProfileRow label="Prénom" value={soignant.prenom} />
                  <ProfileRow label="Nom" value={soignant.nom} />
                  <ProfileRow label="Email" value={soignant.email} />
                  <ProfileRow label="Téléphone" value={soignant.telephone || '—'} />
                  <ProfileRow label="Date de naissance" value={soignant.date_naissance ? new Date(soignant.date_naissance).toLocaleDateString('fr-FR') : '—'} />
                </CardContent>
              </Card>
              <Card>
                <CardHeader><CardTitle className="text-sm">Professionnel</CardTitle></CardHeader>
                <CardContent className="space-y-2">
                  <ProfileRow label="Profession" value={soignant.profession} />
                  <ProfileRow label="Type de contrat" value={soignant.type_contrat || '—'} />
                  <ProfileRow label="RPPS" value={soignant.numero_rpps || '—'} />
                  <ProfileRow label="ADELI" value={soignant.numero_adeli || '—'} />
                  <ProfileRow label="Rayon déplacement" value={`${soignant.rayon_deplacement_km || 30} km`} />
                </CardContent>
              </Card>
              <Card>
                <CardHeader><CardTitle className="text-sm">Vérifications & Conformité</CardTitle></CardHeader>
                <CardContent className="space-y-2">
                  <VerifRow label="Identité vérifiée" ok={soignant.identite_verifiee} />
                  <VerifRow label="Diplôme vérifié" ok={soignant.diplome_verifie} />
                  <VerifRow label="RPPS vérifié" ok={soignant.rpps_verifie} />
                  <VerifRow label="Tous documents valides" ok={soignant.tous_documents_valides} />
                  <ProfileRow label="Statut vérification ARIA" value={soignant.statut_verification_aria || '—'} />
                </CardContent>
              </Card>
              <Card>
                <CardHeader><CardTitle className="text-sm">Statistiques</CardTitle></CardHeader>
                <CardContent className="space-y-2">
                  <ProfileRow label="Score fiabilité" value={soignant.score_fiabilite != null && soignant.total_missions_terminees > 0 ? `${soignant.score_fiabilite}/100` : 'Pas encore d\'évaluation'} />
                  <ProfileRow label="Missions terminées" value={soignant.total_missions_terminees ?? 0} />
                  <ProfileRow label="Missions annulées" value={soignant.total_missions_annulees ?? 0} />
                  <ProfileRow label="Heures cumulées" value={`${soignant.heures_cumulees ?? 0}h`} />
                  <ProfileRow label="Retards pointage" value={soignant.total_retards_pointage ?? 0} />
                  <ProfileRow label="Absences" value={soignant.total_absences ?? 0} />
                </CardContent>
              </Card>
              <Card>
                <CardHeader><CardTitle className="text-sm">Prévoyance & Libéral</CardTitle></CardHeader>
                <CardContent className="space-y-2">
                  <VerifRow label="Prévoyance inscrit" ok={soignant.prevoyance_inscrit} />
                  <ProfileRow label="Fournisseur prévoyance" value={soignant.prevoyance_fournisseur || '—'} />
                  <VerifRow label="Éligible 3200h" ok={soignant.eligible_conversion_3200h} />
                </CardContent>
              </Card>
              <Card>
                <CardHeader><CardTitle className="text-sm">Localisation & Dates</CardTitle></CardHeader>
                <CardContent className="space-y-2">
                  <ProfileRow label="Latitude" value={soignant.adresse_lat ?? '—'} />
                  <ProfileRow label="Longitude" value={soignant.adresse_lng ?? '—'} />
                  <ProfileRow label="Inscrit le" value={new Date(soignant.cree_le).toLocaleDateString('fr-FR')} />
                  <ProfileRow label="Dernière modification" value={soignant.modifie_le ? new Date(soignant.modifie_le).toLocaleDateString('fr-FR') : '—'} />
                </CardContent>
              </Card>
            </div>
          ) : etablissement ? (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <Card>
                <CardHeader><CardTitle className="text-sm">Identité</CardTitle></CardHeader>
                <CardContent className="space-y-2">
                  <ProfileRow label="Nom" value={etablissement.nom} />
                  <ProfileRow label="SIRET" value={etablissement.siret} />
                  <ProfileRow label="FINESS" value={etablissement.finess || '—'} />
                  <ProfileRow label="Type" value={etablissement.type} />
                  <ProfileRow label="Email contact" value={etablissement.email_contact} />
                  <ProfileRow label="Téléphone" value={etablissement.telephone_contact || '—'} />
                </CardContent>
              </Card>
              <Card>
                <CardHeader><CardTitle className="text-sm">Adresse</CardTitle></CardHeader>
                <CardContent className="space-y-2">
                  <ProfileRow label="Rue" value={etablissement.adresse_rue} />
                  <ProfileRow label="Ville" value={`${etablissement.adresse_code_postal} ${etablissement.adresse_ville}`} />
                  <ProfileRow label="Département" value={etablissement.adresse_departement || '—'} />
                  <ProfileRow label="Coordonnées" value={etablissement.adresse_lat ? `${etablissement.adresse_lat}, ${etablissement.adresse_lng}` : '—'} />
                </CardContent>
              </Card>
              <Card>
                <CardHeader><CardTitle className="text-sm">Commercial</CardTitle></CardHeader>
                <CardContent className="space-y-2">
                  <ProfileRow label="Formule" value={etablissement.formule_abonnement || '—'} />
                  <ProfileRow label="Taux commission" value={`${etablissement.taux_commission_negocie}%`} />
                  <ProfileRow label="Mode facturation" value={etablissement.mode_facturation || '—'} />
                  <ProfileRow label="Mode paiement" value={etablissement.mode_paiement_commission || '—'} />
                  <ProfileRow label="Délai paiement" value={`${etablissement.delai_paiement_jours} jours`} />
                </CardContent>
              </Card>
              <Card>
                <CardHeader><CardTitle className="text-sm">Configuration</CardTitle></CardHeader>
                <CardContent className="space-y-2">
                  <ProfileRow label="Convention collective" value={etablissement.convention_collective || '—'} />
                  <VerifRow label="Chorus Pro actif" ok={etablissement.chorus_pro_actif} />
                  <VerifRow label="Rist plafond actif" ok={etablissement.rist_plafond_actif} />
                  <ProfileRow label="Majoration nuit" value={`${etablissement.taux_majoration_nuit_pourcent}%`} />
                  <ProfileRow label="Majoration dimanche" value={`${etablissement.taux_majoration_dimanche_pourcent}%`} />
                  <ProfileRow label="Majoration férié" value={`${etablissement.taux_majoration_ferie_pourcent}%`} />
                </CardContent>
              </Card>
            </div>
          ) : null}
        </TabsContent>

        {/* ── 6. Actions admin ── */}
        <TabsContent value="actions">
          <Card>
            <CardHeader><CardTitle className="text-lg">Actions administrateur</CardTitle></CardHeader>
            <CardContent className="space-y-4">
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
                <ActionCard
                  icon={Trash2}
                  label="Supprimer le compte"
                  description="Suppression définitive et irréversible."
                  variant="destructive"
                  onClick={() => setModalSupprimer(true)}
                />
              </div>
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>

      <ModalConfirmation
        ouvert={modalSuspendre}
        onFermer={() => setModalSuspendre(false)}
        onConfirmer={suspendre}
        titre={isSuspended ? 'Réactiver le compte' : 'Suspendre le compte'}
        message={isSuspended
          ? `Voulez-vous réactiver le compte de ${nom} ?`
          : `Voulez-vous suspendre le compte de ${nom} ? L'utilisateur ne pourra plus accéder à la plateforme.`
        }
        labelConfirmer={isSuspended ? 'Réactiver' : 'Suspendre'}
        variante={isSuspended ? 'primaire' : 'danger'}
      />

      <ModalConfirmation
        ouvert={modalSupprimer}
        onFermer={() => setModalSupprimer(false)}
        onConfirmer={supprimerCompte}
        titre="Supprimer définitivement"
        message={`Attention : la suppression définitive de ${nom} est irréversible. Cette action nécessite une intervention manuelle dans Supabase.`}
        labelConfirmer="Supprimer"
        variante="danger"
      />
    </LayoutAdmin>
  );
}

/* ── Small helper components ── */

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
        <Badge className="bg-success text-success-foreground text-[10px]">✓ Oui</Badge>
      ) : (
        <Badge variant="outline" className="text-[10px]">✗ Non</Badge>
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
      <Button size="sm" variant={variant} onClick={onClick} className="mt-auto self-start">
        {label}
      </Button>
    </div>
  );
}
