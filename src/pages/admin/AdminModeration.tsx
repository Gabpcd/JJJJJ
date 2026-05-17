import React, { useState, useEffect } from 'react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { supabase } from '@/integrations/supabase/client';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { CardY2K, CardY2KContent } from '@/components/y2k/CardY2K';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { toast } from 'sonner';
import { FileCheck, MessageSquare, Check, X, Eye, ShieldAlert } from 'lucide-react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useNavigate } from 'react-router-dom';
import { LitigesFilters } from '@/components/admin/litiges/LitigesFilters';
import { LitigesList, filtrerEtTrier } from '@/components/admin/litiges/LitigesList';
import { LitigePreuvesPanel } from '@/components/admin/litiges/LitigePreuvesPanel';
import { LitigeResolutionModal } from '@/components/admin/litiges/LitigeResolutionModal';
import { AvoirsList } from '@/components/admin/litiges/AvoirsList';
import { LegacyRecategorisation } from '@/components/admin/litiges/LegacyRecategorisation';
import { MediationBanner } from '@/components/admin/litiges/MediationBanner';
import { RefundsQueueWidget } from '@/components/admin/litiges/RefundsQueueWidget';
import { telechargerCsv } from '@/components/admin/litiges/csv';
import { Download, Receipt, Tag } from 'lucide-react';
import {
  FILTRES_DEFAUT,
  type FiltresLitiges,
  type LitigeEnrichi,
} from '@/components/admin/litiges/types';

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
  const [litiges, setLitiges] = useState<LitigeEnrichi[]>([]);
  const [evaluations, setEvaluations] = useState<any[]>([]);
  const [documents, setDocuments] = useState<any[]>([]);
  const [incoherences, setIncoherences] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  const [filtres, setFiltres] = useState<FiltresLitiges>(FILTRES_DEFAUT);
  const [mediationCount, setMediationCount] = useState<number>(0);
  const [legacyCount, setLegacyCount] = useState<number>(0);

  const [preuvesLitige, setPreuvesLitige] = useState<LitigeEnrichi | null>(null);
  const [preuvesOpen, setPreuvesOpen] = useState(false);

  const [resolutionLitige, setResolutionLitige] = useState<LitigeEnrichi | null>(null);
  const [resolutionOpen, setResolutionOpen] = useState(false);

  const [activeTab, setActiveTab] = useState<string>('litiges');

  const charger = async () => {
    setLoading(true);

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
        .select('id, nom_fichier, type_document, soignant_id, televerse_le')
        .eq('statut_verification', 'EN_ATTENTE')
        .is('supprime_le', null)
        .order('televerse_le', { ascending: true })
        .limit(50),
      supabase.rpc('fn_admin_incoherences_identite' as any),
    ]);

    if (resLitiges.error || resEvals.error || resDocs.error) {
      toast.error('Impossible de charger les données de modération.');
    }
    if (resIncoherences.data) setIncoherences(resIncoherences.data as any[] || []);

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
        allUserIds.length ? supabase.from('soignants').select('id, prenom, nom').in('id', allUserIds) : Promise.resolve({ data: [] } as any),
        allUserIds.length ? supabase.from('etablissements').select('id, nom').in('id', allUserIds) : Promise.resolve({ data: [] } as any),
        evalMissionIds.length ? supabase.from('missions').select('id, intitule').in('id', evalMissionIds) : Promise.resolve({ data: [] } as any),
      ]);

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
    if (resDocs.data) setDocuments(resDocs.data);

    // Count litiges EN_MEDIATION depuis plus de 7 jours (escalade_auto_le < now - 7d).
    const seuilIso = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
    const { count: medCount, error: errMed } = await supabase
      .from('litiges')
      .select('id', { count: 'exact', head: true })
      .eq('statut', 'EN_MEDIATION')
      .lt('escalade_auto_le', seuilIso);
    if (!errMed) setMediationCount(medCount ?? 0);

    setLoading(false);
  };

  useEffect(() => {
    charger();
  }, []);

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

  const validerDocument = async (id: string) => {
    const { data, error } = await supabase.rpc('fn_admin_moderer_document' as any, { p_document_id: id, p_action: 'VALIDER' });
    if (error || (data as any)?.error) { toast.error('Une erreur est survenue. Veuillez réessayer.'); return; }
    toast.success('Document validé');
    charger();
  };

  const rejeterDocument = async (id: string) => {
    const { data, error } = await supabase.rpc('fn_admin_moderer_document' as any, { p_document_id: id, p_action: 'REJETER', p_motif: 'Rejeté par admin' });
    if (error || (data as any)?.error) { toast.error('Une erreur est survenue. Veuillez réessayer.'); return; }
    toast.success('Document rejeté');
    charger();
  };

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin pageName="Modération" />
      <div className="space-y-6">
        <div className="flex items-start justify-between gap-3">
          <h1 className="text-2xl font-bold text-foreground">Modération</h1>
          <RefundsQueueWidget />
        </div>

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
            <TabsList className="w-max md:w-auto">
              <TabsTrigger value="litiges" className="gap-1.5"><MessageSquare className="h-4 w-4" />Litiges ({litiges.length})</TabsTrigger>
              <TabsTrigger value="avoirs" className="gap-1.5"><Receipt className="h-4 w-4" />Avoirs</TabsTrigger>
              <TabsTrigger value="legacy" className="gap-1.5">
                <Tag className="h-4 w-4" />Legacy{legacyCount > 0 ? ` (${legacyCount})` : ''}
              </TabsTrigger>
              <TabsTrigger value="evaluations" className="gap-1.5"><Eye className="h-4 w-4" />Évaluations ({evaluations.length})</TabsTrigger>
              <TabsTrigger value="documents" className="gap-1.5"><FileCheck className="h-4 w-4" />Documents ({documents.length})</TabsTrigger>
              <TabsTrigger value="incoherences" className="gap-1.5"><ShieldAlert className="h-4 w-4" />Identité ({incoherences.length})</TabsTrigger>
            </TabsList>
          </div>

          <TabsContent value="litiges" className="space-y-4" data-testid="tab-litiges">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <LitigesFilters filtres={filtres} onChange={setFiltres} />
            </div>

            <div className="flex items-center justify-end">
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
            </div>

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
              <p className="py-8 text-center text-sm text-muted-foreground">Aucune évaluation en attente de modération 🎉</p>
            ) : (
              <div className="space-y-3">
                {evaluations.map((e) => (
                  <CardY2K noPadding key={e.id}>
                    <CardY2KContent className="pt-4 space-y-3">
                      <div className="flex items-start justify-between gap-3">
                        <div className="space-y-1">
                          <div className="flex items-center gap-2">
                            <BadgeY2K variant={e.note <= 2 ? 'error' : e.note === 3 ? 'warning' : 'info'}>
                              {'★'.repeat(e.note)}{'☆'.repeat(5 - e.note)}
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
                        <div className="flex gap-1.5 shrink-0">
                          <BoutonY2K size="sm" variant="secondary" onClick={() => publierEvaluation(e.id)} iconeGauche={<Check className="h-3.5 w-3.5" />}>Publier</BoutonY2K>
                          <BoutonY2K size="sm" variant="destructive" onClick={() => supprimerEvaluation(e.id)} iconeGauche={<X className="h-3.5 w-3.5" />}>Supprimer</BoutonY2K>
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

          <TabsContent value="documents">
            {/* Desktop : table */}
            <div className="hidden md:block overflow-x-auto rounded-lg border">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Fichier</TableHead>
                    <TableHead>Type</TableHead>
                    <TableHead>Date</TableHead>
                    <TableHead className="text-right">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {documents.map((d) => (
                    <TableRow key={d.id}>
                      <TableCell className="max-w-[200px] truncate font-medium">{d.nom_fichier}</TableCell>
                      <TableCell><BadgeY2K variant="info" size="sm">{d.type_document}</BadgeY2K></TableCell>
                      <TableCell className="text-xs text-muted-foreground">{d.televerse_le ? formatDate(d.televerse_le) : '—'}</TableCell>
                      <TableCell className="space-x-1 text-right">
                        <BoutonY2K size="sm" variant="secondary" onClick={() => validerDocument(d.id)} iconeGauche={<Check className="h-3.5 w-3.5" />}>Valider</BoutonY2K>
                        <BoutonY2K size="sm" variant="destructive" onClick={() => rejeterDocument(d.id)} iconeGauche={<X className="h-3.5 w-3.5" />}>Rejeter</BoutonY2K>
                      </TableCell>
                    </TableRow>
                  ))}
                  {documents.length === 0 && <TableRow><TableCell colSpan={4} className="py-8 text-center text-muted-foreground">Aucun document en attente</TableCell></TableRow>}
                </TableBody>
              </Table>
            </div>

            {/* Mobile : cards */}
            <div className="md:hidden space-y-3">
              {documents.length === 0 ? (
                <p className="py-8 text-center text-sm text-muted-foreground">Aucun document en attente</p>
              ) : documents.map((d) => (
                <div key={d.id} className="rounded-xl border border-border bg-card p-3 space-y-2">
                  <div className="flex items-start justify-between gap-2">
                    <p className="font-medium text-sm break-words flex-1 min-w-0">{d.nom_fichier}</p>
                    <BadgeY2K variant="info" size="sm" className="shrink-0">{d.type_document}</BadgeY2K>
                  </div>
                  <p className="text-[11px] text-muted-foreground">{d.televerse_le ? `Téléversé le ${formatDate(d.televerse_le)}` : 'Date inconnue'}</p>
                  <div className="grid grid-cols-2 gap-2">
                    <BoutonY2K size="sm" variant="secondary" className="min-h-[36px]" onClick={() => validerDocument(d.id)} iconeGauche={<Check className="h-3.5 w-3.5" />}>
                      Valider
                    </BoutonY2K>
                    <BoutonY2K size="sm" variant="destructive" className="min-h-[36px]" onClick={() => rejeterDocument(d.id)} iconeGauche={<X className="h-3.5 w-3.5" />}>
                      Rejeter
                    </BoutonY2K>
                  </div>
                </div>
              ))}
            </div>
          </TabsContent>

          <TabsContent value="incoherences">
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
                  {incoherences.length === 0 && <TableRow><TableCell colSpan={8} className="py-8 text-center text-muted-foreground">Aucune incohérence identitaire détectée 🎉</TableCell></TableRow>}
                </TableBody>
              </Table>
            </div>

            {/* Mobile : cards avec 3 matches résumés visuellement */}
            <div className="md:hidden space-y-3">
              {incoherences.length === 0 ? (
                <p className="py-8 text-center text-sm text-muted-foreground">Aucune incohérence identitaire détectée 🎉</p>
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
    </LayoutAdmin>
  );
}
