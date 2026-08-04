import { cloneElement, isValidElement, useCallback, useEffect, useId, useMemo, useRef, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementAdmin, ChargementSectionAdmin } from '@/components/admin/ChargementAdmin';
import { AdminCrmAutomation } from '@/components/admin/AdminCrmAutomation';
import { AdminFilterBar } from '@/components/admin/AdminFilterBar';
import { AdminSourcingCockpit } from '@/components/admin/AdminSourcingCockpit';
import { AdminGrowthWorkspaceNav, type AdminGrowthWorkspaceStep } from '@/components/admin/AdminGrowthWorkspaceNav';
import { AdminPageHeader } from '@/components/admin/AdminPageHeader';
import { supabase } from '@/integrations/supabase/client';
import { PROFESSIONS, getLabelProfession, getLabelTypeEtablissement } from '@/lib/constantes';
import { CardY2K, CardY2KContent } from '@/components/y2k/CardY2K';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { toast } from 'sonner';
import {
  Megaphone, Plus, ExternalLink, Phone, Mail, MessageCircle, Copy, Save, X, Trash2,
  Users, Building2, FileText, Search, Star, Archive, RotateCcw, Send, Pencil,
} from 'lucide-react';

/* ── Constantes UI ── */
const PLATEFORMES = [
  { v: 'WHATSAPP', label: 'WhatsApp' },
  { v: 'FACEBOOK', label: 'Facebook' },
  { v: 'INSTAGRAM', label: 'Instagram' },
  { v: 'TIKTOK', label: 'TikTok' },
  { v: 'LINKEDIN', label: 'LinkedIn' },
  { v: 'TELEGRAM', label: 'Telegram' },
  { v: 'SNAPCHAT', label: 'Snapchat' },
  { v: 'JOBBOARD', label: 'Job board' },
  { v: 'AUTRE', label: 'Autre' },
];
const AUDIENCES = [
  { v: 'SOIGNANTS', label: 'Soignants' },
  { v: 'ETABLISSEMENTS', label: 'Établissements' },
  { v: 'MIXTE', label: 'Mixte' },
];
const STATUTS_GROUPE = ['ACTIF', 'A_VERIFIER', 'INACTIF'];
const STATUTS_CONTACT = ['PROSPECT', 'CONTACTE', 'RELANCE', 'INSCRIT', 'PERDU'];
const CONTACTS_PAGE_SIZE = 100;
const SALES_CONTACTS_SELECT = [
  'id', 'type', 'nom', 'profession', 'telephone', 'email', 'ville', 'departement',
  'type_etab', 'groupe_id', 'statut', 'notes', 'maj_le', 'cree_le', 'favori',
  'archive', 'reponse', 'a_rappeler', 'ne_plus_contacter',
].join(',');

type TypeContact = 'SOIGNANT' | 'ETABLISSEMENT';
type SalesTab = 'sourcing' | 'crm' | 'groupes' | 'soignants' | 'etablissements' | 'prospection' | 'prospection_soignants' | 'etab_jolene' | 'templates' | 'posts' | 'backlinks';

const SALES_TABS = new Set<SalesTab>([
  'sourcing', 'crm', 'groupes', 'soignants', 'etablissements', 'prospection',
  'prospection_soignants', 'etab_jolene', 'templates', 'posts', 'backlinks',
]);

function estSalesTab(value: string | null): value is SalesTab {
  return value !== null && SALES_TABS.has(value as SalesTab);
}

function etapePourTab(tab: SalesTab): AdminGrowthWorkspaceStep {
  if (['crm', 'soignants', 'etablissements', 'etab_jolene'].includes(tab)) return 'actions';
  if (['groupes', 'templates', 'posts', 'backlinks'].includes(tab)) return 'ressources';
  return 'cibles';
}

interface PaginationContacts {
  page: number;
  total: number | null;
}
/** Libellés français des statuts contact (les valeurs envoyées en base restent inchangées). */
const LABELS_STATUT_CONTACT: Record<string, string> = {
  PROSPECT: 'Prospect',
  CONTACTE: 'Contacté',
  RELANCE: 'Relancé',
  INSCRIT: 'Inscrit',
  PERDU: 'Perdu',
};

function badgeStatutGroupe(s: string): 'success' | 'warning' | 'error' {
  return s === 'ACTIF' ? 'success' : s === 'INACTIF' ? 'error' : 'warning';
}
function badgeStatutContact(s: string): 'success' | 'warning' | 'error' | 'info' {
  if (s === 'INSCRIT') return 'success';
  if (s === 'PERDU') return 'error';
  if (s === 'CONTACTE' || s === 'RELANCE') return 'info';
  return 'warning';
}

interface CompteursBaseProspection {
  total: number;
  avec_email: number;
  avec_email_non_contacte: number;
  avec_telephone: number;
  contactables: number;
  nouveaux_30j: number;
  maj_le: string;
}

interface StatsProspectionAdmin {
  soignants: CompteursBaseProspection;
  etablissements: CompteursBaseProspection;
  crm_soignants: number;
  crm_etablissements: number;
  exact: boolean;
  genere_le: string;
}

function estNombreCompteur(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0;
}

function afficherCompteur(value: unknown): string {
  return estNombreCompteur(value) ? value.toLocaleString('fr-FR') : '—';
}

function normaliserStatsProspection(value: unknown): StatsProspectionAdmin | null {
  if (!value || typeof value !== 'object') return null;
  const stats = value as Partial<StatsProspectionAdmin>;
  if (
    stats.exact !== true
    || !estNombreCompteur(stats.crm_soignants)
    || !estNombreCompteur(stats.crm_etablissements)
    || !estNombreCompteur(stats.soignants?.total)
    || !estNombreCompteur(stats.soignants?.avec_email_non_contacte)
    || !estNombreCompteur(stats.etablissements?.total)
    || !estNombreCompteur(stats.etablissements?.avec_email_non_contacte)
  ) return null;
  return stats as StatsProspectionAdmin;
}

function messageErreurProspection(error?: { message?: string | null } | null): string {
  const message = error?.message?.toLowerCase() || '';
  if (message.includes('statement timeout') || message.includes('canceling statement') || message.includes('timeout')) {
    return 'La recherche a pris trop de temps. Les résultats déjà affichés sont conservés ; ajoutez un filtre ou relancez dans un instant.';
  }
  return 'La recherche est momentanément indisponible. Les résultats déjà affichés sont conservés ; vous pouvez réessayer.';
}

/** Lien WhatsApp wa.me depuis un numéro FR (0X… → 33X…). */
function lienWhatsApp(tel: string): string {
  const digits = (tel || '').replace(/\D/g, '');
  let intl = digits;
  if (digits.startsWith('0')) intl = '33' + digits.slice(1);
  else if (digits.startsWith('33')) intl = digits;
  return `https://wa.me/${intl}`;
}

/* ── Template de prospection email (éditable dans l'onglet Templates) ──
   Utilisé partout : mailto pré-rempli (sujet + corps) ET envoi direct Resend. */
const TEMPLATE_PROSPECTION_NOM = 'Email prospection établissement';
const SUJET_PROSPECTION_DEFAUT = 'Des renforts soignants vérifiés pour {{nom}}';
const CORPS_PROSPECTION_DEFAUT = `Bonjour,

Je suis Gabrielle, la fondatrice de Jolene. J'ai créé une plateforme pour aider les établissements comme {{nom}} à trouver des renforts soignants fiables, sans la lourdeur ni les marges des agences d'intérim.

Chaque soignant est vérifié par nos soins : diplôme, RPPS et assurance contrôlés avant la moindre mission.

Concrètement, pour vous :
• Vous publiez un besoin en 2 minutes et recevez des candidatures de soignants notés
• Les contrats et déclarations sont générés automatiquement
• 15 % de commission HT (18 % TTC avec TVA à 20 %), sans abonnement ni engagement

Si cela peut vous être utile, je serais ravie d'échanger quelques minutes — répondez simplement à cet email, je vous réponds personnellement.

Voir comment ça marche : https://jolene.app

Bien à vous,
Gabrielle Picard
Fondatrice de Jolene
gabrielle@jolene.app`;

interface TemplateProspection { sujet: string; contenu: string }

function remplirTemplate(txt: string, p: { nom?: string | null; ville?: string | null }): string {
  return (txt || '')
    .split('{{nom}}').join(p.nom || 'votre établissement')
    .split('{{ville}}').join(p.ville || '');
}

/** Ouvre Gmail web (mail.google.com) avec destinataire + sujet + corps pré-remplis,
 *  dans un nouvel onglet — envoie depuis le compte Google connecté (gabrielle@jolene.app),
 *  pas l'app Mail du Mac. Meilleure délivrabilité que Resend pour la prospection à froid. */
function composerGmail(email: string, sujet: string, corps: string) {
  const url = `https://mail.google.com/mail/?view=cm&fs=1&to=${encodeURIComponent(email)}&su=${encodeURIComponent(sujet)}&body=${encodeURIComponent(corps)}`;
  window.open(url, '_blank', 'noopener');
}
/** Ouvre Gmail pré-rempli avec le template (1 clic, zéro copier-coller). */
function ouvrirMailto(email: string, tpl: TemplateProspection, p: { nom?: string | null; ville?: string | null; prenom?: string | null }) {
  const nomAffiche = p.prenom ? `${p.prenom} ${p.nom || ''}`.trim() : (p.nom || undefined);
  composerGmail(email, remplirTemplate(tpl.sujet, { ...p, nom: nomAffiche }), remplirTemplate(tpl.contenu, { ...p, nom: nomAffiche }));
}

/** Charge le template de prospection depuis sales_templates (fallback : constantes). */
function useTemplateProspection(): TemplateProspection {
  const [tpl, setTpl] = useState<TemplateProspection>({ sujet: SUJET_PROSPECTION_DEFAUT, contenu: CORPS_PROSPECTION_DEFAUT });
  useEffect(() => {
    supabase.from('sales_templates' as any).select('sujet, contenu').eq('nom', TEMPLATE_PROSPECTION_NOM).maybeSingle()
      .then(({ data }) => {
        const d = data as any;
        if (d?.contenu) setTpl({ sujet: d.sujet || SUJET_PROSPECTION_DEFAUT, contenu: d.contenu });
      });
  }, []);
  return tpl;
}

/** Charge le template de prospection SOIGNANT (cible=SOIGNANT) — fallback constantes. */
function useTemplateProspectionSoignant(): TemplateProspection {
  const [tpl, setTpl] = useState<TemplateProspection>({ sujet: SUJET_PROSPECTION_SOIGNANT, contenu: CORPS_PROSPECTION_SOIGNANT });
  useEffect(() => {
    supabase.from('sales_templates' as any).select('sujet, contenu').eq('cible', 'SOIGNANT').limit(1).maybeSingle()
      .then(({ data }) => {
        const d = data as any;
        if (d?.contenu) setTpl({ sujet: d.sujet || SUJET_PROSPECTION_SOIGNANT, contenu: d.contenu });
      });
  }, []);
  return tpl;
}

export default function AdminSales() {
  usePageTitle('Prospects et actions commerciales');
  const [searchParams] = useSearchParams();
  const tabParam = searchParams.get('tab');
  const tab: SalesTab = estSalesTab(tabParam) ? tabParam : 'sourcing';
  const [loading, setLoading] = useState(true);

  const [groupes, setGroupes] = useState<any[]>([]);
  const [contacts, setContacts] = useState<any[]>([]);
  const [paginationContacts, setPaginationContacts] = useState<Record<TypeContact, PaginationContacts>>({
    SOIGNANT: { page: 1, total: null },
    ETABLISSEMENT: { page: 1, total: null },
  });
  const [templates, setTemplates] = useState<any[]>([]);
  const [statsProspection, setStatsProspection] = useState<StatsProspectionAdmin | null>(null);
  const [erreurCompteurs, setErreurCompteurs] = useState<string | null>(null);
  const chargementIdRef = useRef(0);
  const erreurCompteursSignaleeRef = useRef(false);

  // filtres annuaire
  const [fPlateforme, setFPlateforme] = useState('');
  const [fProfession, setFProfession] = useState('');
  const [recherche, setRecherche] = useState('');

  // formulaires
  const [editGroupe, setEditGroupe] = useState<any | null>(null);
  const [editContact, setEditContact] = useState<any | null>(null);
  const [editTemplate, setEditTemplate] = useState<any | null>(null);

  const [fFavorisGroupes, setFFavorisGroupes] = useState(false);
  const [voirArchives, setVoirArchives] = useState(false);
  const [importCible, setImportCible] = useState<'GROUPES' | 'CONTACTS' | null>(null);

  const importerCsv = async (texte: string) => {
    const lignes = texte.split('\n').map(l => l.trim()).filter(Boolean);
    let inseres = 0, ignores = 0;
    if (importCible === 'GROUPES') {
      const urlsExistantes = new Set(groupes.map(g => (g.url || '').replace(/\/$/, '')));
      const rows = [];
      for (const l of lignes) {
        const [nom, url, profession, region] = l.split(';').map(x => (x || '').trim());
        if (!nom) { ignores++; continue; }
        if (url && urlsExistantes.has(url.replace(/\/$/, ''))) { ignores++; continue; }
        rows.push({ nom, url: url || null, profession: profession || 'TOUTES', region: region || null,
          plateforme: url?.includes('facebook') ? 'FACEBOOK' : url?.includes('instagram') ? 'INSTAGRAM' : url?.includes('tiktok') ? 'TIKTOK' : url?.includes('linkedin') ? 'LINKEDIN' : 'AUTRE',
          audience: 'MIXTE', statut: 'A_VERIFIER' });
      }
      if (rows.length) {
        const { error } = await supabase.from('sales_groupes' as any).insert(rows as any);
        if (error) { toast.error(error.message); return; }
        inseres = rows.length;
      }
    } else {
      const rows = [];
      for (const l of lignes) {
        const [nom, telephone, email, ville, profession] = l.split(';').map(x => (x || '').trim());
        if (!nom) { ignores++; continue; }
        rows.push({ type: tab === 'soignants' ? 'SOIGNANT' : 'ETABLISSEMENT', nom,
          telephone: telephone || null, email: email || null, ville: ville || null,
          profession: profession || null, statut: 'PROSPECT' });
      }
      if (rows.length) {
        const { error } = await supabase.from('sales_contacts' as any).insert(rows as any);
        if (error) { toast.error(error.message); return; }
        inseres = rows.length;
      }
    }
    toast.success(`${inseres} ligne(s) importée(s)${ignores ? `, ${ignores} ignorée(s)` : ''}.`);
    setImportCible(null);
    charger();
  };

  const charger = useCallback(async () => {
    const chargementId = ++chargementIdRef.current;
    setLoading(true);
    const requeteContacts = (type: TypeContact, page: number) => {
      const from = (page - 1) * CONTACTS_PAGE_SIZE;
      let requete = supabase.from('sales_contacts' as any)
        .select(SALES_CONTACTS_SELECT, { count: 'exact' })
        .eq('type', type);
      if (!voirArchives) requete = requete.eq('archive', false);
      return requete
        .order('favori', { ascending: false })
        .order('cree_le', { ascending: false })
        .order('id', { ascending: true })
        .range(from, from + CONTACTS_PAGE_SIZE - 1);
    };

    const [g, contactsSoignants, contactsEtablissements, t, stats] = await Promise.all([
      supabase.from('sales_groupes' as any).select('*').order('favori', { ascending: false }).order('plateforme').order('profession'),
      requeteContacts('SOIGNANT', paginationContacts.SOIGNANT.page),
      requeteContacts('ETABLISSEMENT', paginationContacts.ETABLISSEMENT.page),
      supabase.from('sales_templates' as any).select('*').order('cible'),
      supabase.rpc('fn_admin_prospection_stats' as any),
    ]);
    if (chargementId !== chargementIdRef.current) return;

    // En cas d'échec, conserver les dernières données valides plutôt que
    // d'afficher un faux zéro issu d'un tableau/count nul.
    if (!g.error && Array.isArray(g.data)) setGroupes(g.data as any[]);
    setContacts((contactsActuels) => [
      ...(!contactsSoignants.error && Array.isArray(contactsSoignants.data)
        ? contactsSoignants.data as any[]
        : contactsActuels.filter((contact) => contact.type === 'SOIGNANT')),
      ...(!contactsEtablissements.error && Array.isArray(contactsEtablissements.data)
        ? contactsEtablissements.data as any[]
        : contactsActuels.filter((contact) => contact.type === 'ETABLISSEMENT')),
    ]);
    setPaginationContacts((paginationActuelle) => ({
      SOIGNANT: {
        ...paginationActuelle.SOIGNANT,
        total: contactsSoignants.error ? paginationActuelle.SOIGNANT.total : contactsSoignants.count,
      },
      ETABLISSEMENT: {
        ...paginationActuelle.ETABLISSEMENT,
        total: contactsEtablissements.error ? paginationActuelle.ETABLISSEMENT.total : contactsEtablissements.count,
      },
    }));
    if (!t.error && Array.isArray(t.data)) setTemplates(t.data as any[]);

    const statsValides = !stats.error ? normaliserStatsProspection(stats.data) : null;
    if (statsValides) {
      setStatsProspection(statsValides);
      setErreurCompteurs(null);
      erreurCompteursSignaleeRef.current = false;
    } else {
      const message = 'Les compteurs des bases officielles sont momentanément indisponibles. Les dernières valeurs connues sont conservées.';
      setErreurCompteurs(message);
      if (!erreurCompteursSignaleeRef.current) toast.error(message);
      erreurCompteursSignaleeRef.current = true;
    }
    setLoading(false);
  }, [paginationContacts.ETABLISSEMENT.page, paginationContacts.SOIGNANT.page, voirArchives]);

  useEffect(() => { charger(); }, [charger]);

  /* ── Groupes filtrés ── */
  const groupesFiltres = useMemo(() => {
    return groupes.filter(g =>
      (!fPlateforme || g.plateforme === fPlateforme) &&
      (!fProfession || g.profession === fProfession) &&
      (!fFavorisGroupes || g.favori) &&
      (!recherche || `${g.nom} ${g.region || ''} ${g.notes || ''}`.toLowerCase().includes(recherche.toLowerCase())),
    );
  }, [groupes, fPlateforme, fProfession, fFavorisGroupes, recherche]);

  const soignants = useMemo(
    () => contacts.filter(c => c.type === 'SOIGNANT' && (voirArchives || !c.archive)),
    [contacts, voirArchives],
  );
  const etablissements = useMemo(
    () => contacts.filter(c => c.type === 'ETABLISSEMENT' && (voirArchives || !c.archive)),
    [contacts, voirArchives],
  );

  const toggleFavoriGroupe = async (g: any) => {
    const { error } = await supabase.from('sales_groupes' as any).update({ favori: !g.favori } as any).eq('id', g.id);
    if (error) { toast.error(error.message); return; }
    charger();
  };

  const toggleFavoriContact = async (c: any) => {
    const { error } = await supabase.from('sales_contacts' as any).update({ favori: !c.favori } as any).eq('id', c.id);
    if (error) { toast.error(error.message); return; }
    charger();
  };

  const archiverContact = async (c: any, archive: boolean) => {
    const { error } = await supabase.from('sales_contacts' as any).update({ archive, maj_le: new Date().toISOString() } as any).eq('id', c.id);
    if (error) { toast.error(error.message); return; }
    toast.success(archive ? 'Retiré (archivé — restaurable).' : 'Restauré.');
    charger();
  };

  /* ── Actions ── */
  const copier = async (texte: string) => {
    try { await navigator.clipboard.writeText(texte); toast.success('Message copié — collez-le dans le groupe.'); }
    catch { toast.error('Copie impossible.'); }
  };

  const sauverGroupe = async () => {
    if (!editGroupe?.nom?.trim()) { toast.error('Le nom du groupe est requis.'); return; }
    const payload = {
      nom: editGroupe.nom.trim(), plateforme: editGroupe.plateforme || 'WHATSAPP',
      profession: editGroupe.profession || 'TOUTES', region: editGroupe.region || null,
      url: editGroupe.url || null, membres: editGroupe.membres ? Number(editGroupe.membres) : null,
      audience: editGroupe.audience || 'MIXTE', statut: editGroupe.statut || 'A_VERIFIER',
      notes: editGroupe.notes || null, maj_le: new Date().toISOString(),
    };
    const { error } = editGroupe.id
      ? await supabase.from('sales_groupes' as any).update(payload as any).eq('id', editGroupe.id)
      : await supabase.from('sales_groupes' as any).insert(payload as any);
    if (error) { toast.error(error.message); return; }
    toast.success('Groupe enregistré.');
    setEditGroupe(null); charger();
  };

  const supprimerGroupe = async (id: string) => {
    const { error } = await supabase.from('sales_groupes' as any).delete().eq('id', id);
    if (error) { toast.error(error.message); return; }
    toast.success('Groupe supprimé.'); charger();
  };

  const sauverContact = async () => {
    if (!editContact?.nom?.trim()) { toast.error('Le nom est requis.'); return; }
    const payload = {
      type: editContact.type || 'SOIGNANT', nom: editContact.nom.trim(),
      profession: editContact.profession || null, telephone: editContact.telephone || null,
      email: editContact.email || null, ville: editContact.ville || null,
      groupe_id: editContact.groupe_id || null, statut: editContact.statut || 'PROSPECT',
      notes: editContact.notes || null, maj_le: new Date().toISOString(),
    };
    const { error } = editContact.id
      ? await supabase.from('sales_contacts' as any).update(payload as any).eq('id', editContact.id)
      : await supabase.from('sales_contacts' as any).insert(payload as any);
    if (error) { toast.error(error.message); return; }
    toast.success('Contact enregistré.');
    setEditContact(null); charger();
  };

  const sauverTemplate = async () => {
    if (!editTemplate?.contenu?.trim()) { toast.error('Le message est requis.'); return; }
    const { error } = await supabase.from('sales_templates' as any)
      .update({ sujet: editTemplate.sujet?.trim() || null, contenu: editTemplate.contenu } as any)
      .eq('id', editTemplate.id);
    if (error) { toast.error(error.message); return; }
    toast.success('Modèle enregistré — utilisé par tous les boutons email.');
    setEditTemplate(null); charger();
  };

  const majStatutContact = async (id: string, statut: string) => {
    const { error } = await supabase.from('sales_contacts' as any).update({ statut, maj_le: new Date().toISOString() } as any).eq('id', id);
    if (error) { toast.error(error.message); return; }
    charger();
  };

  // Une réponse positive correspond à l'état CRM canonique « intéressé » :
  // réponse POSITIVE + rappel manuel. INSCRIT reste une action explicite distincte.
  const majReponseContact = async (c: any, reponse: string | null) => {
    const maintenant = new Date();
    const patch: any = { reponse, maj_le: maintenant.toISOString(), a_rappeler: false };
    if (reponse === 'POSITIVE') {
      // Une correction depuis PERDU/RELANCE redevient un contact intéressé.
      // Seule l'inscription déjà confirmée reste au statut INSCRIT.
      if (c.statut !== 'INSCRIT') patch.statut = 'CONTACTE';
      patch.a_rappeler = true;
      patch.ne_plus_contacter = false;
      patch.sequence_active = false;
      patch.prochaine_action_le = null;
      patch.dernier_contact_le = maintenant.toISOString();
      patch.derniere_action_type = 'INTERESSE';
    } else if (reponse === 'NEGATIVE') {
      patch.statut = 'PERDU';
      patch.ne_plus_contacter = true;
      patch.sequence_active = false;
      patch.prochaine_action_le = null;
      patch.dernier_contact_le = maintenant.toISOString();
      patch.derniere_action_type = 'PAS_INTERESSE';
    }
    const { error } = await supabase.from('sales_contacts' as any).update(patch).eq('id', c.id);
    if (error) { toast.error(error.message); return; }
    toast.success(reponse === 'POSITIVE' ? 'Marqué intéressé' : reponse === 'NEGATIVE' ? 'Marqué pas intéressé.' : 'Réponse mise à jour.');
    charger();
  };

  // « À rappeler » : appelé sans réponse → file de rappel (anti-oubli).
  const toggleARappeler = async (c: any) => {
    const { error } = await supabase.from('sales_contacts' as any)
      .update({ a_rappeler: !c.a_rappeler, dernier_contact_le: new Date().toISOString(), maj_le: new Date().toISOString() } as any)
      .eq('id', c.id);
    if (error) { toast.error(error.message); return; }
    charger();
  };

  const changerPageContacts = (type: TypeContact, page: number) => {
    setPaginationContacts((paginationActuelle) => ({
      ...paginationActuelle,
      [type]: { ...paginationActuelle[type], page: Math.max(1, page) },
    }));
  };

  const basculerArchivesContacts = () => {
    setVoirArchives((archivesVisibles) => !archivesVisibles);
    setPaginationContacts((paginationActuelle) => ({
      SOIGNANT: { ...paginationActuelle.SOIGNANT, page: 1 },
      ETABLISSEMENT: { ...paginationActuelle.ETABLISSEMENT, page: 1 },
    }));
  };

  const etapeActive = etapePourTab(tab);
  const ongletsContexte: Array<{ id: SalesTab; label: string }> = etapeActive === 'cibles'
    ? [
      { id: 'sourcing', label: 'Cibles prioritaires' },
      { id: 'prospection', label: `Annuaire établissements · ${afficherCompteur(statsProspection?.etablissements?.total)}` },
      { id: 'prospection_soignants', label: `Annuaire soignants · ${afficherCompteur(statsProspection?.soignants?.total)}` },
    ]
    : etapeActive === 'actions'
      ? [
        { id: 'crm', label: 'Actions du jour' },
        { id: 'etablissements', label: `Suivi établissements · ${afficherCompteur(statsProspection?.crm_etablissements)}` },
        { id: 'soignants', label: `Suivi soignants · ${afficherCompteur(statsProspection?.crm_soignants)}` },
        { id: 'etab_jolene', label: 'Clients Jolene' },
      ]
      : [
        { id: 'groupes', label: `Groupes · ${groupes.length}` },
        { id: 'templates', label: `Modèles · ${templates.length}` },
        { id: 'posts', label: 'Publications' },
        { id: 'backlinks', label: 'Référencement' },
      ];

  if (loading) return <LayoutAdmin><ChargementAdmin titre="Chargement de l’espace commercial" /></LayoutAdmin>;

  return (
    <LayoutAdmin>
      <div className="space-y-6">
        <AdminPageHeader
          title="Prospects et actions commerciales"
          description="Un parcours unique pour qualifier une cible, préparer une action humaine et conserver son historique."
          icon={<Megaphone className="h-6 w-6" />}
        />

        <AdminGrowthWorkspaceNav active={etapeActive} />

        <section className="border-t border-border pt-4" aria-labelledby="admin-sales-context-nav-title">
          <div className="flex flex-col gap-1">
            <h2 id="admin-sales-context-nav-title" className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
              Vues de l’étape
            </h2>
            <p className="text-sm text-muted-foreground">
              {etapeActive === 'cibles' && 'Sélectionnez les personnes et établissements à ajouter à votre liste de travail.'}
              {etapeActive === 'actions' && 'Traitez les rappels et mettez à jour le suivi après chaque action humaine.'}
              {etapeActive === 'ressources' && 'Préparez les relais, modèles et contenus utilisés pour développer Jolene.'}
            </p>
          </div>
          <nav aria-labelledby="admin-sales-context-nav-title" className="mt-2 overflow-x-auto">
            <ul className="flex min-w-max gap-1 border-b border-border">
              {ongletsContexte.map((onglet) => {
                const estActif = onglet.id === tab;
                return (
                  <li key={onglet.id}>
                    <Link
                      to={`/admin/fondateur/sales?tab=${onglet.id}`}
                      aria-current={estActif ? 'page' : undefined}
                      className={`inline-flex min-h-[44px] items-center justify-center border-b-2 px-3 py-2 text-center text-sm font-medium whitespace-nowrap transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-inset ${
                        estActif
                          ? 'border-primary bg-muted/40 text-primary'
                          : 'border-transparent text-muted-foreground hover:border-border hover:bg-muted/30 hover:text-foreground'
                      }`}
                    >
                      {onglet.label}
                    </Link>
                  </li>
                );
              })}
            </ul>
          </nav>
        </section>

        {erreurCompteurs && (
          <p role="alert" className="text-xs text-amber-700 dark:text-amber-300 rounded-lg border border-amber-300/60 bg-amber-50/70 dark:bg-amber-950/20 px-3 py-2">
            {erreurCompteurs}
          </p>
        )}

        {/* ── SOURCING : découverte et qualification, sans aucun envoi ── */}
        {tab === 'sourcing' && <AdminSourcingCockpit onContactsChanged={charger} />}

        {/* ── CRM AUTOMATISÉ : file, séquences, attribution et historique ── */}
        {tab === 'crm' && <AdminCrmAutomation onContactsChanged={charger} />}

        {/* ── GROUPES ── */}
        {tab === 'groupes' && (
          <div className="space-y-4">
            <AdminFilterBar
              ariaLabel="Filtres des groupes de recrutement"
              advancedLabel="Plateforme, profession et favoris"
              advancedActiveCount={(fPlateforme ? 1 : 0) + (fProfession ? 1 : 0) + (fFavorisGroupes ? 1 : 0)}
              onResetAdvanced={() => {
                setFPlateforme('');
                setFProfession('');
                setFFavorisGroupes(false);
              }}
              actions={(
                <BoutonY2K size="sm" onClick={() => setEditGroupe({ plateforme: 'FACEBOOK', profession: 'TOUTES', audience: 'MIXTE', statut: 'A_VERIFIER' })} iconeGauche={<Plus className="h-4 w-4" />}>
                  Ajouter
                </BoutonY2K>
              )}
              advanced={(
                <>
                  <div>
                    <Label htmlFor="admin-sales-plateforme" className="text-xs">Plateforme</Label>
                    <select id="admin-sales-plateforme" value={fPlateforme} onChange={e => setFPlateforme(e.target.value)} className="input-base h-9 w-full">
                      <option value="">Toutes</option>
                      {PLATEFORMES.map(p => <option key={p.v} value={p.v}>{p.label}</option>)}
                    </select>
                  </div>
                  <div>
                    <Label htmlFor="admin-sales-profession" className="text-xs">Profession</Label>
                    <select id="admin-sales-profession" value={fProfession} onChange={e => setFProfession(e.target.value)} className="input-base h-9 w-full">
                      <option value="">Toutes</option>
                      <option value="TOUTES">Toutes professions</option>
                      {PROFESSIONS.map(p => <option key={p.valeur} value={p.valeur}>{p.label}</option>)}
                    </select>
                  </div>
                  <BoutonY2K size="sm" variant={fFavorisGroupes ? 'primary' : 'secondary'} onClick={() => setFFavorisGroupes(!fFavorisGroupes)} iconeGauche={<Star className="h-4 w-4" />}>
                    Favoris
                  </BoutonY2K>
                  <BoutonY2K size="sm" variant="ghost" onClick={() => setImportCible('GROUPES')} iconeGauche={<FileText className="h-4 w-4" />}>
                    Importer CSV
                  </BoutonY2K>
                </>
              )}
            >
              <div className="w-full sm:min-w-72 sm:flex-1">
                <Label htmlFor="admin-sales-recherche-groupes" className="text-xs">Recherche</Label>
                <div className="relative">
                  <Search className="absolute left-2 top-2.5 h-4 w-4 text-muted-foreground" />
                  <Input id="admin-sales-recherche-groupes" value={recherche} onChange={e => setRecherche(e.target.value)} placeholder="Nom, région, note…" className="pl-8 h-9" />
                </div>
              </div>
            </AdminFilterBar>

            {groupesFiltres.length === 0 ? (
              <CardY2K hoverLift={false}><CardY2KContent><p className="text-sm text-muted-foreground text-center py-6">Aucun groupe. Ajoutez vos vrais liens — ils deviennent cliquables.</p></CardY2KContent></CardY2K>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                {groupesFiltres.map(g => (
                  <CardY2K key={g.id} hoverLift={false}>
                    <CardY2KContent>
                      <div className="flex items-start justify-between gap-2">
                        <div className="min-w-0">
                          <div className="flex items-center gap-2 flex-wrap">
                            {g.url ? (
                              <a href={g.url} target="_blank" rel="noopener noreferrer"
                                className="font-semibold text-primary hover:underline truncate inline-flex items-center gap-1">
                                {g.nom}<ExternalLink className="h-3.5 w-3.5 shrink-0" />
                              </a>
                            ) : (
                              <span className="font-semibold text-foreground truncate">{g.nom}</span>
                            )}
                            <BadgeY2K variant={badgeStatutGroupe(g.statut)}>{g.statut === 'A_VERIFIER' ? 'À vérifier' : g.statut === 'ACTIF' ? 'Actif' : 'Inactif'}</BadgeY2K>
                          </div>
                          <p className="text-xs text-muted-foreground mt-0.5">
                            {PLATEFORMES.find(p => p.v === g.plateforme)?.label} · {g.profession === 'TOUTES' ? 'Toutes prof.' : getLabelProfession(g.profession)}
                            {g.region ? ` · ${g.region}` : ''}{g.membres ? ` · ${g.membres} membres` : ''}
                          </p>
                          {g.url && (
                            <a href={g.url} target="_blank" rel="noopener noreferrer"
                              className="text-[11px] text-primary/80 hover:underline break-all line-clamp-1 mt-0.5 block">
                              {g.url.replace(/^https?:\/\//, '')}
                            </a>
                          )}
                          {g.notes && <p className="text-[11px] text-muted-foreground mt-1 line-clamp-2">{g.notes}</p>}
                        </div>
                      </div>
                      <div className="flex gap-2 mt-3 flex-wrap items-center">
                        <button
                          onClick={() => toggleFavoriGroupe(g)}
                          title={g.favori ? 'Retirer des favoris' : 'Ajouter aux favoris'}
                          aria-label={`${g.favori ? 'Retirer des favoris' : 'Ajouter aux favoris'} : ${g.nom}`}
                          aria-pressed={Boolean(g.favori)}
                          className="p-1.5 rounded-lg hover:bg-muted transition-colors">
                          <Star aria-hidden="true" className={`h-5 w-5 ${g.favori ? 'fill-yellow-400 text-yellow-400' : 'text-muted-foreground'}`} />
                        </button>
                        {g.url ? (
                          <BoutonY2K size="sm" onClick={() => window.open(g.url, '_blank', 'noopener')} iconeGauche={<ExternalLink className="h-4 w-4" />}>Ouvrir</BoutonY2K>
                        ) : (
                          <BadgeY2K variant="warning">Lien à renseigner</BadgeY2K>
                        )}
                        <BoutonY2K size="sm" variant="ghost" onClick={() => setEditGroupe({ ...g })}>Éditer</BoutonY2K>
                        <BoutonY2K
                          size="sm"
                          variant="ghost"
                          onClick={() => supprimerGroupe(g.id)}
                          aria-label={`Supprimer le groupe ${g.nom}`}
                          iconeGauche={<Trash2 className="h-4 w-4" aria-hidden="true" />}
                        />
                      </div>
                    </CardY2KContent>
                  </CardY2K>
                ))}
              </div>
            )}
          </div>
        )}

        {/* ── CONTACTS (soignants / établissements) ── */}
        {(tab === 'soignants' || tab === 'etablissements') && (
          <ListeContacts
            type={tab === 'soignants' ? 'SOIGNANT' : 'ETABLISSEMENT'}
            contacts={tab === 'soignants' ? soignants : etablissements}
            voirArchives={voirArchives}
            pagination={paginationContacts[tab === 'soignants' ? 'SOIGNANT' : 'ETABLISSEMENT']}
            onPageChange={(page) => changerPageContacts(tab === 'soignants' ? 'SOIGNANT' : 'ETABLISSEMENT', page)}
            onToggleArchives={basculerArchivesContacts}
            onAdd={() => setEditContact({ type: tab === 'soignants' ? 'SOIGNANT' : 'ETABLISSEMENT', statut: 'PROSPECT' })}
            onImport={() => setImportCible('CONTACTS')}
            onEdit={c => setEditContact({ ...c })}
            onStatut={majStatutContact}
            onReponse={majReponseContact}
            onARappeler={toggleARappeler}
            onFavori={toggleFavoriContact}
            onArchive={archiverContact}
          />
        )}

        {/* ── PROSPECTION (base nationale) ── */}
        {tab === 'prospection' && <ProspectionEtab onAjouter={charger} />}

        {/* ── PROSPECTION SOIGNANTS (Annuaire Santé / RPPS) ── */}
        {tab === 'prospection_soignants' && <ProspectionSoignants onAjouter={charger} />}

        {/* ── ÉTABLISSEMENTS JOLENE (inscrits) ── */}
        {tab === 'etab_jolene' && <EtablissementsJolene />}

        {/* ── TEMPLATES ── */}
        {tab === 'templates' && (
          <div className="space-y-3">
            <p className="text-xs text-muted-foreground">
              Publication assistée : copiez le message et ouvrez le groupe pour le coller (l'auto-post natif est interdit par WhatsApp/Facebook).
            </p>
            <details className="rounded-xl border border-border bg-card p-3">
              <summary className="cursor-pointer text-sm font-semibold text-foreground">
                Campagnes groupées après lancement
              </summary>
              <p className="mb-3 mt-2 text-xs text-muted-foreground">
                Ces commandes restent verrouillées tant que les automatisations marketing ne sont pas activées.
              </p>
              <EnvoiMasseBar cible="ETABLISSEMENT" />
              <EnvoiMasseBar cible="SOIGNANT" />
            </details>
            {templates.map(t => (
              <CardY2K key={t.id} hoverLift={false}>
                <CardY2KContent>
                  <div className="flex items-center justify-between gap-2 mb-2">
                    <span className="font-semibold text-foreground">{t.nom}</span>
                    <BadgeY2K variant="info">{t.cible === 'GROUPE' ? 'Post groupe' : t.cible === 'SOIGNANT' ? 'Message privé soignant' : 'Message privé établissement'}</BadgeY2K>
                  </div>
                  {t.sujet && (
                    <p className="text-xs text-foreground mb-1.5"><span className="text-muted-foreground">Sujet :</span> <strong>{t.sujet}</strong></p>
                  )}
                  <pre className="text-xs text-muted-foreground whitespace-pre-wrap font-sans bg-muted/40 rounded-lg p-3">{t.contenu}</pre>
                  <div className="flex gap-2 mt-2">
                    <BoutonY2K size="sm" onClick={() => copier(t.contenu)} iconeGauche={<Copy className="h-4 w-4" />}>Copier le message</BoutonY2K>
                    <BoutonY2K size="sm" variant="secondary" onClick={() => setEditTemplate({ ...t })} iconeGauche={<Pencil className="h-4 w-4" />}>Modifier</BoutonY2K>
                  </div>
                </CardY2KContent>
              </CardY2K>
            ))}
          </div>
        )}

        {/* ── POSTS DE LA SEMAINE (générés depuis les missions réelles) ── */}
        {tab === 'posts' && <PostsGenerateur />}

        {/* ── BACKLINKS / ANNUAIRES ── */}
        {tab === 'backlinks' && <BacklinksAnnuaires />}
      </div>

      {/* ── Import CSV ── */}
      {importCible && (
        <ImportCsvModal
          cible={importCible}
          onClose={() => setImportCible(null)}
          onImport={importerCsv}
        />
      )}

      {/* ── Formulaire groupe ── */}
      {editGroupe && (
        <FormPanel titre={editGroupe.id ? 'Modifier le groupe' : 'Nouveau groupe'} onClose={() => setEditGroupe(null)} onSave={sauverGroupe}>
          <Champ label="Nom du groupe *"><Input value={editGroupe.nom || ''} onChange={e => setEditGroupe({ ...editGroupe, nom: e.target.value })} /></Champ>
          <div className="grid grid-cols-2 gap-3">
            <Champ label="Plateforme">
              <select value={editGroupe.plateforme} onChange={e => setEditGroupe({ ...editGroupe, plateforme: e.target.value })} className="input-base h-9 w-full">
                {PLATEFORMES.map(p => <option key={p.v} value={p.v}>{p.label}</option>)}
              </select>
            </Champ>
            <Champ label="Audience">
              <select value={editGroupe.audience} onChange={e => setEditGroupe({ ...editGroupe, audience: e.target.value })} className="input-base h-9 w-full">
                {AUDIENCES.map(a => <option key={a.v} value={a.v}>{a.label}</option>)}
              </select>
            </Champ>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <Champ label="Profession">
              <select value={editGroupe.profession} onChange={e => setEditGroupe({ ...editGroupe, profession: e.target.value })} className="input-base h-9 w-full">
                <option value="TOUTES">Toutes professions</option>
                {PROFESSIONS.map(p => <option key={p.valeur} value={p.valeur}>{p.label}</option>)}
              </select>
            </Champ>
            <Champ label="Statut">
              <select value={editGroupe.statut} onChange={e => setEditGroupe({ ...editGroupe, statut: e.target.value })} className="input-base h-9 w-full">
                {STATUTS_GROUPE.map(s => <option key={s} value={s}>{s === 'A_VERIFIER' ? 'À vérifier' : s === 'ACTIF' ? 'Actif' : 'Inactif'}</option>)}
              </select>
            </Champ>
          </div>
          <Champ label="URL (lien réel du groupe)"><Input value={editGroupe.url || ''} onChange={e => setEditGroupe({ ...editGroupe, url: e.target.value })} placeholder="https://chat.whatsapp.com/… ou https://facebook.com/groups/…" /></Champ>
          <div className="grid grid-cols-2 gap-3">
            <Champ label="Région"><Input value={editGroupe.region || ''} onChange={e => setEditGroupe({ ...editGroupe, region: e.target.value })} placeholder="Île-de-France, National…" /></Champ>
            <Champ label="Membres"><Input type="number" value={editGroupe.membres || ''} onChange={e => setEditGroupe({ ...editGroupe, membres: e.target.value })} /></Champ>
          </div>
          <Champ label="Notes"><Textarea value={editGroupe.notes || ''} onChange={e => setEditGroupe({ ...editGroupe, notes: e.target.value })} rows={2} /></Champ>
        </FormPanel>
      )}

      {/* ── Formulaire contact ── */}
      {editContact && (
        <FormPanel titre={editContact.id ? 'Modifier le contact' : 'Nouveau contact'} onClose={() => setEditContact(null)} onSave={sauverContact}>
          <Champ label="Nom *"><Input value={editContact.nom || ''} onChange={e => setEditContact({ ...editContact, nom: e.target.value })} /></Champ>
          <div className="grid grid-cols-2 gap-3">
            {editContact.type === 'SOIGNANT' && (
              <Champ label="Profession">
                <select value={editContact.profession || ''} onChange={e => setEditContact({ ...editContact, profession: e.target.value })} className="input-base h-9 w-full">
                  <option value="">—</option>
                  {PROFESSIONS.map(p => <option key={p.valeur} value={p.valeur}>{p.label}</option>)}
                </select>
              </Champ>
            )}
            <Champ label="Ville"><Input value={editContact.ville || ''} onChange={e => setEditContact({ ...editContact, ville: e.target.value })} /></Champ>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <Champ label="Téléphone"><Input value={editContact.telephone || ''} onChange={e => setEditContact({ ...editContact, telephone: e.target.value })} placeholder="06…" /></Champ>
            <Champ label="Email"><Input type="email" value={editContact.email || ''} onChange={e => setEditContact({ ...editContact, email: e.target.value })} /></Champ>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <Champ label="Groupe source">
              <select value={editContact.groupe_id || ''} onChange={e => setEditContact({ ...editContact, groupe_id: e.target.value || null })} className="input-base h-9 w-full">
                <option value="">—</option>
                {groupes.map(g => <option key={g.id} value={g.id}>{g.nom}</option>)}
              </select>
            </Champ>
            <Champ label="Statut">
              <select value={editContact.statut} onChange={e => setEditContact({ ...editContact, statut: e.target.value })} className="input-base h-9 w-full">
                {STATUTS_CONTACT.map(s => <option key={s} value={s}>{LABELS_STATUT_CONTACT[s] || s}</option>)}
              </select>
            </Champ>
          </div>
          <Champ label="Notes"><Textarea value={editContact.notes || ''} onChange={e => setEditContact({ ...editContact, notes: e.target.value })} rows={2} /></Champ>
        </FormPanel>
      )}

      {/* ── Formulaire template ── */}
      {editTemplate && (
        <FormPanel titre={`Modifier « ${editTemplate.nom} »`} onClose={() => setEditTemplate(null)} onSave={sauverTemplate}>
          <p className="text-xs text-muted-foreground mb-2">
            Placeholders disponibles : <code>{'{{nom}}'}</code> (nom de l'établissement) et <code>{'{{ville}}'}</code> —
            remplacés automatiquement à l'envoi, que l'email parte de Jolene ou de votre boîte mail.
          </p>
          <Champ label="Sujet de l'email">
            <Input value={editTemplate.sujet || ''} onChange={e => setEditTemplate({ ...editTemplate, sujet: e.target.value })} />
          </Champ>
          <Champ label="Message">
            <Textarea value={editTemplate.contenu || ''} onChange={e => setEditTemplate({ ...editTemplate, contenu: e.target.value })} rows={12} />
          </Champ>
        </FormPanel>
      )}
    </LayoutAdmin>
  );
}
/* ── Réponses au contact (suivi sourcing) ── */
const REPONSES_FILTRE = [
  { v: '', label: 'Toutes réponses' },
  { v: 'EN_ATTENTE', label: 'En attente' },
  { v: 'POSITIVE', label: 'Intéressé(e)' },
  { v: 'NEGATIVE', label: 'Pas intéressé(e)' },
];
function badgeReponse(r: string): 'success' | 'error' | 'warning' { return r === 'POSITIVE' ? 'success' : r === 'NEGATIVE' ? 'error' : 'warning'; }
function labelReponse(r: string): string { return r === 'POSITIVE' ? 'Intéressé(e)' : r === 'NEGATIVE' ? 'Pas intéressé(e)' : 'Réponse en attente'; }

/* ── Sous-composant liste contacts sourcés (CRM) ── */
function ListeContacts({ type, contacts, voirArchives, pagination, onPageChange, onToggleArchives, onAdd, onImport, onEdit, onStatut, onReponse, onARappeler, onFavori, onArchive }: {
  type: 'SOIGNANT' | 'ETABLISSEMENT';
  contacts: any[];
  voirArchives: boolean;
  pagination: PaginationContacts;
  onPageChange: (page: number) => void;
  onToggleArchives: () => void;
  onAdd: () => void;
  onImport: () => void;
  onEdit: (c: any) => void;
  onStatut: (id: string, s: string) => void;
  onReponse: (c: any, reponse: string | null) => void;
  onARappeler: (c: any) => void;
  onFavori: (c: any) => void;
  onArchive: (c: any, archive: boolean) => void;
}) {
  const tpl = useTemplateProspection();
  const tplSoignant = useTemplateProspectionSoignant();
  const [fStatut, setFStatut] = useState('');
  const [fReponse, setFReponse] = useState('');
  const [fARappeler, setFARappeler] = useState(false);
  const [fProfType, setFProfType] = useState('');
  const [fDept, setFDept] = useState('');
  const [tri, setTri] = useState('recent');

  const nbRappels = useMemo(() => contacts.filter(c => c.a_rappeler).length, [contacts]);
  const totalPages = pagination.total === null
    ? null
    : Math.max(1, Math.ceil(pagination.total / CONTACTS_PAGE_SIZE));

  const liste = useMemo(() => {
    const l = contacts.filter(c =>
      (!fStatut || c.statut === fStatut) &&
      (!fReponse || c.reponse === fReponse) &&
      (!fARappeler || c.a_rappeler) &&
      (!fProfType || (type === 'SOIGNANT' ? c.profession === fProfType : c.type_etab === fProfType)) &&
      (!fDept || (c.departement || '').toUpperCase() === fDept.trim().toUpperCase()),
    );
    return [...l].sort((a, b) => {
      if (tri === 'nom') return (a.nom || '').localeCompare(b.nom || '');
      if (tri === 'statut') return (a.statut || '').localeCompare(b.statut || '');
      return new Date(b.maj_le || b.cree_le || 0).getTime() - new Date(a.maj_le || a.cree_le || 0).getTime();
    });
  }, [contacts, fStatut, fReponse, fARappeler, fProfType, fDept, tri, type]);

  return (
    <div className="space-y-3">
      {/* Barre d'actions */}
      <div className="flex justify-end gap-2 flex-wrap">
        <BoutonY2K size="sm" variant={fARappeler ? 'primary' : 'secondary'} onClick={() => setFARappeler(!fARappeler)} iconeGauche={<RotateCcw className="h-4 w-4" />}>
          À rappeler{nbRappels ? ` (${nbRappels})` : ''}
        </BoutonY2K>
        <BoutonY2K size="sm" variant={voirArchives ? 'primary' : 'secondary'} onClick={onToggleArchives} iconeGauche={<Archive className="h-4 w-4" />}>
          {voirArchives ? 'Masquer les archivés' : 'Voir les archivés'}
        </BoutonY2K>
        <BoutonY2K size="sm" variant="ghost" onClick={onImport} iconeGauche={<FileText className="h-4 w-4" />}>Importer CSV</BoutonY2K>
        <BoutonY2K size="sm" onClick={onAdd} iconeGauche={<Plus className="h-4 w-4" />}>
          Ajouter {type === 'SOIGNANT' ? 'un soignant' : 'un établissement'}
        </BoutonY2K>
      </div>

      {/* Filtres / tri */}
      <div className="flex gap-2 flex-wrap items-end">
        <div>
          <Label className="text-xs">Statut</Label>
          <select aria-label="Filtrer les contacts par statut" value={fStatut} onChange={e => setFStatut(e.target.value)} className="input-base h-8 text-xs">
            <option value="">Tous</option>
            {STATUTS_CONTACT.map(s => <option key={s} value={s}>{LABELS_STATUT_CONTACT[s] || s}</option>)}
          </select>
        </div>
        <div>
          <Label className="text-xs">Réponse</Label>
          <select aria-label="Filtrer les contacts par réponse" value={fReponse} onChange={e => setFReponse(e.target.value)} className="input-base h-8 text-xs">
            {REPONSES_FILTRE.map(r => <option key={r.v} value={r.v}>{r.label}</option>)}
          </select>
        </div>
        <div>
          <Label className="text-xs">{type === 'SOIGNANT' ? 'Profession' : "Type d'étab."}</Label>
          <select aria-label={type === 'SOIGNANT' ? 'Filtrer les contacts par profession' : 'Filtrer les contacts par type d’établissement'} value={fProfType} onChange={e => setFProfType(e.target.value)} className="input-base h-8 text-xs">
            <option value="">{type === 'SOIGNANT' ? 'Toutes' : 'Tous'}</option>
            {type === 'SOIGNANT'
              ? PROFESSIONS.map(p => <option key={p.valeur} value={p.valeur}>{p.label}</option>)
              : TYPES_PROSPECTION.filter(t => t.v).map(t => <option key={t.v} value={t.v}>{t.label}</option>)}
          </select>
        </div>
        <div>
          <Label className="text-xs">Dépt.</Label>
          <Input aria-label="Filtrer les contacts par département" value={fDept} onChange={e => setFDept(e.target.value)} placeholder="ex : 75" className="h-8 w-20 text-xs" />
        </div>
        <div>
          <Label className="text-xs">Tri</Label>
          <select aria-label="Trier les contacts" value={tri} onChange={e => setTri(e.target.value)} className="input-base h-8 text-xs">
            <option value="recent">Plus récent</option>
            <option value="nom">Nom (A→Z)</option>
            <option value="statut">Statut</option>
          </select>
        </div>
      </div>

      <p className="text-xs text-muted-foreground">
        {liste.length} contact(s) affiché(s) sur cette page
        {pagination.total !== null ? ` · ${pagination.total.toLocaleString('fr-FR')} au total` : ''}
        {fARappeler ? ' · file « à rappeler »' : ''}
        {(fStatut || fReponse || fARappeler || fProfType || fDept) ? ' · filtres appliqués à la page courante' : ''}
      </p>

      {liste.length === 0 ? (
        <CardY2K hoverLift={false}><CardY2KContent><p className="text-sm text-muted-foreground text-center py-6">Aucun contact pour ces filtres.</p></CardY2KContent></CardY2K>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          {liste.map(c => (
            <CardY2K key={c.id} hoverLift={false} className={c.archive ? 'opacity-60' : ''}>
              <CardY2KContent>
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0 flex items-start gap-1.5">
                    <button onClick={() => onFavori(c)} title="Favori" className="mt-0.5 shrink-0">
                      <Star className={`h-4 w-4 ${c.favori ? 'fill-yellow-400 text-yellow-400' : 'text-muted-foreground'}`} />
                    </button>
                    <div className="min-w-0">
                      <span className="font-semibold text-foreground">{c.nom}</span>
                      <p className="text-xs text-muted-foreground mt-0.5">
                        {c.profession ? getLabelProfession(c.profession) : type === 'ETABLISSEMENT' ? 'Établissement' : ''}
                        {c.ville ? ` · ${c.ville}` : ''}{c.departement ? ` (${c.departement})` : ''}
                      </p>
                    </div>
                  </div>
                  <div className="flex items-center gap-1.5 flex-wrap justify-end">
                    {c.ne_plus_contacter && <BadgeY2K variant="error">Ne plus contacter</BadgeY2K>}
                    {c.a_rappeler && <BadgeY2K variant="warning">À rappeler</BadgeY2K>}
                    {c.reponse && <BadgeY2K variant={badgeReponse(c.reponse)}>{labelReponse(c.reponse)}</BadgeY2K>}
                    {c.archive && <BadgeY2K variant="warning">Archivé</BadgeY2K>}
                    <BadgeY2K variant={badgeStatutContact(c.statut)}>{LABELS_STATUT_CONTACT[c.statut] || c.statut}</BadgeY2K>
                  </div>
                </div>
                {/* Contacter */}
                {c.ne_plus_contacter ? (
                  <p role="status" className="mt-3 rounded-lg border border-destructive/30 bg-destructive/5 px-3 py-2 text-xs text-destructive">
                    Contact bloqué. Marquez la fiche comme intéressée uniquement si la personne a explicitement changé d’avis.
                  </p>
                ) : (
                  <div className="flex gap-2 mt-3 flex-wrap">
                    {c.telephone && (
                    <>
                      <BoutonY2K size="sm" onClick={() => { window.location.href = `tel:${c.telephone}`; }} iconeGauche={<Phone className="h-4 w-4" />}>Appeler</BoutonY2K>
                      <BoutonY2K size="sm" variant="secondary" onClick={() => window.open(lienWhatsApp(c.telephone), '_blank', 'noopener')} iconeGauche={<MessageCircle className="h-4 w-4" />}>WhatsApp</BoutonY2K>
                    </>
                    )}
                    {c.email && (
                    <BoutonY2K size="sm" variant="secondary"
                      onClick={() => ouvrirMailto(c.email, type === 'ETABLISSEMENT' ? tpl : tplSoignant, c)}
                      iconeGauche={<Mail className="h-4 w-4" />}>Gmail</BoutonY2K>
                    )}
                  </div>
                )}
                {(c.telephone || c.email) && (
                  <p className="text-[11px] mt-1.5 flex flex-wrap gap-x-2">
                    {c.ne_plus_contacter ? (
                      <>{c.telephone || ''}{c.telephone && c.email ? ' · ' : ''}{c.email || ''}</>
                    ) : (
                      <>
                        {c.telephone && <a href={`tel:${c.telephone}`} className="text-primary font-medium hover:underline">{c.telephone}</a>}
                        {c.email && <a href={`mailto:${c.email}`} className="text-primary font-medium hover:underline break-all">{c.email}</a>}
                      </>
                    )}
                  </p>
                )}
                {/* Suivi : réponse + à rappeler */}
                <div className="flex gap-1.5 mt-2 flex-wrap items-center">
                  <BoutonY2K size="sm" variant={c.reponse === 'POSITIVE' ? 'primary' : 'secondary'} onClick={() => onReponse(c, 'POSITIVE')}>Intéressé(e)</BoutonY2K>
                  <BoutonY2K size="sm" variant="ghost" onClick={() => onReponse(c, 'NEGATIVE')}>Ne plus contacter</BoutonY2K>
                  <BoutonY2K size="sm" variant={c.a_rappeler ? 'primary' : 'ghost'} disabled={c.ne_plus_contacter} onClick={() => onARappeler(c)} iconeGauche={<RotateCcw className="h-4 w-4" />}>
                    {c.a_rappeler ? 'Rappel programmé' : 'À rappeler'}
                  </BoutonY2K>
                </div>
                {/* Pipeline + édition */}
                <div className="flex gap-2 mt-2 items-center flex-wrap">
                  <select aria-label={`Statut du contact ${c.nom}`} value={c.statut} onChange={e => onStatut(c.id, e.target.value)} className="input-base h-8 text-xs">
                    {STATUTS_CONTACT.map(s => <option key={s} value={s}>{LABELS_STATUT_CONTACT[s] || s}</option>)}
                  </select>
                  <BoutonY2K size="sm" variant="ghost" onClick={() => onEdit(c)}>Éditer / note</BoutonY2K>
                  {c.archive ? (
                    <BoutonY2K size="sm" variant="ghost" onClick={() => onArchive(c, false)} iconeGauche={<RotateCcw className="h-4 w-4" />}>Restaurer</BoutonY2K>
                  ) : (
                    <BoutonY2K size="sm" variant="ghost" onClick={() => onArchive(c, true)} iconeGauche={<Archive className="h-4 w-4" />}>Retirer</BoutonY2K>
                  )}
                </div>
                {c.notes && <p className="text-[11px] text-muted-foreground mt-2 whitespace-pre-wrap">{c.notes}</p>}
              </CardY2KContent>
            </CardY2K>
          ))}
        </div>
      )}

      {totalPages !== null && totalPages > 1 && (
        <nav aria-label={`Pagination du CRM ${type === 'SOIGNANT' ? 'soignants' : 'établissements'}`} className="flex justify-center gap-2 pt-2">
          <BoutonY2K size="sm" variant="secondary" disabled={pagination.page <= 1} onClick={() => onPageChange(pagination.page - 1)}>← Précédent</BoutonY2K>
          <span className="text-xs text-muted-foreground self-center">Page {pagination.page}/{totalPages}</span>
          <BoutonY2K size="sm" variant="secondary" disabled={pagination.page >= totalPages} onClick={() => onPageChange(pagination.page + 1)}>Suivant →</BoutonY2K>
        </nav>
      )}
    </div>
  );
}

/* ── Panneau de formulaire ── */
function FormPanel({ titre, children, onClose, onSave }: { titre: string; children: React.ReactNode; onClose: () => void; onSave: () => void }) {
  const titleId = useId();

  useEffect(() => {
    const fermerAvecEchap = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose();
    };
    document.addEventListener('keydown', fermerAvecEchap);
    return () => document.removeEventListener('keydown', fermerAvecEchap);
  }, [onClose]);

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-foreground/40 p-0 sm:p-4" onClick={onClose}>
      <div className="bg-card w-full sm:max-w-lg rounded-t-2xl sm:rounded-2xl p-5 max-h-[90vh] overflow-y-auto space-y-3" role="dialog" aria-modal="true" aria-labelledby={titleId} onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between">
          <h2 id={titleId} className="font-bold text-foreground">{titre}</h2>
          <button aria-label={`Fermer : ${titre}`} onClick={onClose} className="text-muted-foreground hover:text-foreground"><X className="h-5 w-5" aria-hidden="true" /></button>
        </div>
        {children}
        <div className="flex gap-2 pt-2">
          <BoutonY2K onClick={onSave} iconeGauche={<Save className="h-4 w-4" />} className="flex-1">Enregistrer</BoutonY2K>
          <BoutonY2K variant="secondary" onClick={onClose}>Annuler</BoutonY2K>
        </div>
      </div>
    </div>
  );
}

function Champ({ label, children }: { label: string; children: React.ReactNode }) {
  const generatedId = useId();
  const controlId = isValidElement<{ id?: string }>(children) && children.props.id ? children.props.id : generatedId;
  const control = isValidElement<{ id?: string }>(children)
    ? cloneElement(children, { id: controlId })
    : children;
  return <div><Label htmlFor={controlId} className="text-xs">{label}</Label>{control}</div>;
}

/* ── Établissements déjà inscrits sur Jolene ── */
function EtablissementsJolene() {
  const [etabs, setEtabs] = useState<any[]>([]);
  const [recherche, setRecherche] = useState('');
  const [loading, setLoading] = useState(true);

  const charger = useCallback(async () => {
    setLoading(true);
    const { data } = await supabase.rpc('fn_admin_lister_etablissements' as any, { p_recherche: recherche || null });
    setEtabs((data as any[]) || []);
    setLoading(false);
  }, [recherche]);

  useEffect(() => { const t = setTimeout(charger, 300); return () => clearTimeout(t); }, [charger]);

  return (
    <div className="space-y-3">
      <div className="relative max-w-sm">
        <Search className="absolute left-2 top-2.5 h-4 w-4 text-muted-foreground" />
        <Input aria-label="Rechercher un établissement Jolene" value={recherche} onChange={e => setRecherche(e.target.value)} placeholder="Nom ou ville…" className="pl-8 h-9" />
      </div>
      {loading ? (
        <p className="text-sm text-muted-foreground py-4">Chargement…</p>
      ) : etabs.length === 0 ? (
        <CardY2K hoverLift={false}><CardY2KContent><p className="text-sm text-muted-foreground text-center py-6">Aucun établissement inscrit pour l'instant.</p></CardY2KContent></CardY2K>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          {etabs.map(e => (
            <CardY2K key={e.id} hoverLift={false}>
              <CardY2KContent>
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <span className="font-semibold text-foreground">{e.nom}</span>
                    <p className="text-xs text-muted-foreground mt-0.5">
                      {getLabelTypeEtablissement(e.type)}{e.ville ? ` · ${e.ville}` : ''}{e.code_postal ? ` (${e.code_postal})` : ''}
                    </p>
                  </div>
                  <BadgeY2K variant={e.peut_publier ? 'success' : 'warning'}>{e.statut_verification || (e.peut_publier ? 'Vérifié' : 'En attente')}</BadgeY2K>
                </div>
                <div className="flex gap-2 mt-3 flex-wrap">
                  {e.telephone && (
                    <BoutonY2K size="sm" onClick={() => { window.location.href = `tel:${e.telephone}`; }} iconeGauche={<Phone className="h-4 w-4" />}>Appeler</BoutonY2K>
                  )}
                  {e.email && (
                    <BoutonY2K size="sm" variant="secondary" onClick={() => { window.location.href = `mailto:${e.email}`; }} iconeGauche={<Mail className="h-4 w-4" />}>Email</BoutonY2K>
                  )}
                  {!e.telephone && !e.email && <BadgeY2K variant="warning">Coordonnées non renseignées</BadgeY2K>}
                </div>
              </CardY2KContent>
            </CardY2K>
          ))}
        </div>
      )}
    </div>
  );
}

/* ── Prospection nationale (base FINESS interne, ~270k établissements avec téléphone) ── */
const TYPES_PROSPECTION = [
  { v: '', label: 'Tous les types' },
  { v: 'EHPAD', label: 'EHPAD / personnes âgées' },
  { v: 'HOPITAL', label: 'Hôpitaux / cliniques' },
  { v: 'DOMICILE', label: 'SSIAD / soins à domicile' },
  { v: 'HANDICAP', label: 'Handicap / médico-social' },
  { v: 'CENTRE_SANTE', label: 'Centres / maisons de santé' },
  { v: 'LABO', label: "Laboratoires d'analyses" },
  { v: 'DIALYSE', label: 'Centres de dialyse' },
  { v: 'ECOLE_SANTE', label: 'Écoles de santé (IFSI, IFAS…) — prospection étudiants' },
];

function ProspectionEtab({ onAjouter }: { onAjouter: () => void }) {
  const [type, setType] = useState('');
  const [departement, setDepartement] = useState('');
  const [q, setQ] = useState('');
  const qRef = useRef('');
  const [favoris, setFavoris] = useState(false);
  const [avecEmail, setAvecEmail] = useState(false);
  const [avecTel, setAvecTel] = useState(false);
  const [page, setPage] = useState(1);
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(false);
  const [erreurRecherche, setErreurRecherche] = useState<string | null>(null);
  const rechercheIdRef = useRef(0);
  const [emailEdit, setEmailEdit] = useState<{ finess: string; valeur: string } | null>(null);

  const rechercher = useCallback(async (p = 1) => {
    const rechercheId = ++rechercheIdRef.current;
    setLoading(true);
    const { data: res, error } = await supabase.rpc('fn_admin_chercher_prospects' as any, {
      p_type: type || null,
      p_departement: departement.trim() || null,
      p_q: qRef.current.trim() || null,
      p_favoris: favoris,
      p_page: p,
      p_avec_email: avecEmail,
      p_avec_tel: avecTel,
    });
    if (rechercheId !== rechercheIdRef.current) return;
    setLoading(false);
    if (error) {
      const message = messageErreurProspection(error);
      setErreurRecherche(message);
      toast.error(message);
      return;
    }
    setErreurRecherche(null);
    setData(res);
    setPage(p);
  }, [type, departement, favoris, avecEmail, avecTel]);

  useEffect(() => { void rechercher(1); }, [rechercher]); // recherche live (q via bouton/Enter)

  const toggleFavori = async (pr: any) => {
    const { error } = await supabase.from('prospects_etablissements' as any)
      .update({ favori: !pr.favori } as any).eq('finess', pr.finess);
    if (error) { toast.error(error.message); return; }
    rechercher(page);
  };

  const sauverEmail = async () => {
    if (!emailEdit) return;
    const valeur = emailEdit.valeur.trim();
    const { error } = await supabase.from('prospects_etablissements' as any)
      .update({ email: valeur || null } as any).eq('finess', emailEdit.finess);
    if (error) { toast.error(error.message); return; }
    setEmailEdit(null);
    rechercher(page);
    toast.success('Email enregistré. Aucun message envoyé.');
  };

  const ajouterProspectAuCrm = async (pr: any): Promise<string | null> => {
    const { data: resultat, error } = await supabase.rpc('fn_admin_sourcing_ajouter_crm' as any, {
      p_cible: 'ETABLISSEMENT',
      p_prospect_id: pr.finess,
      p_score: null,
    });
    if (error) { toast.error(error.message); return null; }
    const contactId = (resultat as { contact_id?: string } | null)?.contact_id;
    if (!contactId) { toast.error('Le contact CRM créé est introuvable.'); return null; }
    return contactId;
  };

  const ajouterAuPipeline = async (pr: any) => {
    const contactId = await ajouterProspectAuCrm(pr);
    if (!contactId) return;
    toast.success('Ajouté aux prospects. Aucun message envoyé.');
    onAjouter();
  };

  const total = estNombreCompteur(data?.total) ? data.total : null;

  return (
    <div className="space-y-4">
      <CardY2K hoverLift={false}>
        <CardY2KContent>
          <p className="text-[11px] text-muted-foreground mb-2">
            Base officielle FINESS importée (tous les établissements de santé de France, téléphone inclus).
            Recherche <strong>nationale</strong> — le département est optionnel.
          </p>
          <div className="flex flex-col sm:flex-row gap-2 sm:items-end flex-wrap">
            <div className="flex-1 min-w-[160px]">
              <Label className="text-xs">Type d'établissement</Label>
              <select aria-label="Type d’établissement à prospecter" value={type} onChange={e => setType(e.target.value)} className="input-base h-9 w-full">
                {TYPES_PROSPECTION.map(c => <option key={c.v} value={c.v}>{c.label}</option>)}
              </select>
            </div>
            <div>
              <Label className="text-xs">Département (optionnel)</Label>
              <Input aria-label="Département des établissements à prospecter" value={departement} onChange={e => setDepartement(e.target.value)} placeholder="National" className="h-9 w-28" />
            </div>
            <div className="flex-1 min-w-[160px]">
              <Label className="text-xs">Nom ou ville</Label>
              <Input aria-label="Nom ou ville de l’établissement à prospecter" value={q} onChange={e => { qRef.current = e.target.value; setQ(e.target.value); }} onKeyDown={e => { if (e.key === 'Enter') rechercher(1); }} placeholder="Korian, Marseille…" className="h-9" />
            </div>
            <BoutonY2K size="sm" variant={avecEmail ? 'primary' : 'secondary'} onClick={() => setAvecEmail(!avecEmail)} iconeGauche={<Mail className="h-4 w-4" />}>Avec email</BoutonY2K>
            <BoutonY2K size="sm" variant={avecTel ? 'primary' : 'secondary'} onClick={() => setAvecTel(!avecTel)} iconeGauche={<Phone className="h-4 w-4" />}>Avec tél.</BoutonY2K>
            <BoutonY2K size="sm" variant={favoris ? 'primary' : 'secondary'} onClick={() => setFavoris(!favoris)} iconeGauche={<Star className="h-4 w-4" />}>Favoris</BoutonY2K>
            <BoutonY2K size="sm" onClick={() => rechercher(1)} disabled={loading} iconeGauche={<Search className="h-4 w-4" />}>
              {loading ? 'Recherche…' : 'Rechercher'}
            </BoutonY2K>
          </div>
        </CardY2KContent>
      </CardY2K>

      {erreurRecherche && (
        <p role="alert" className="text-xs text-amber-700 dark:text-amber-300 rounded-lg border border-amber-300/60 bg-amber-50/70 dark:bg-amber-950/20 px-3 py-2">
          {erreurRecherche}
        </p>
      )}

      {data && (
        <>
          <p className="text-xs text-muted-foreground">
            {total === null ? 'Total momentanément indisponible' : `${total.toLocaleString('fr-FR')} établissement(s)`} — page {data.page}/{Math.max(data.total_pages, 1)}
            {total === 0 && ' · Si la base semble vide, l\'import FINESS est peut-être encore en cours (quelques minutes).'}
          </p>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            {(data.resultats || []).map((pr: any) => (
              <CardY2K key={pr.finess} hoverLift={false}>
                <CardY2KContent>
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0 flex items-start gap-1.5">
                      <button onClick={() => toggleFavori(pr)} title="Favori" className="mt-0.5 shrink-0">
                        <Star className={`h-4 w-4 ${pr.favori ? 'fill-yellow-400 text-yellow-400' : 'text-muted-foreground'}`} />
                      </button>
                      <div className="min-w-0">
                        <span className="font-semibold text-foreground">{pr.nom}</span>
                        <p className="text-xs text-muted-foreground mt-0.5">
                          {pr.categorie_lib || pr.type_jolene}
                          {pr.ville ? ` · ${pr.ville}` : ''}{pr.code_postal ? ` (${pr.code_postal})` : ''}
                        </p>
                      </div>
                    </div>
                  </div>

                  <div className="flex gap-2 mt-3 flex-wrap items-center">
                    <BoutonY2K size="sm" onClick={() => ajouterAuPipeline(pr)} iconeGauche={<Plus className="h-4 w-4" />}>Ajouter aux prospects</BoutonY2K>
                    {!pr.email && (
                      <BoutonY2K size="sm" variant="ghost" onClick={() => setEmailEdit({ finess: pr.finess, valeur: '' })} iconeGauche={<Pencil className="h-4 w-4" />}>Renseigner l’email</BoutonY2K>
                    )}
                    <span className="text-[11px] text-muted-foreground">Qualification interne uniquement</span>
                  </div>
                  {(pr.telephone || pr.email) && (
                    <p className="text-[11px] mt-1.5 flex flex-wrap gap-x-2">
                      {pr.telephone && <span>{pr.telephone}</span>}
                      {pr.email && <span className="break-all">{pr.email}</span>}
                    </p>
                  )}
                </CardY2KContent>
              </CardY2K>
            ))}
          </div>
          {data.total_pages > 1 && (
            <div className="flex justify-center gap-2 pt-2">
              <BoutonY2K size="sm" variant="secondary" disabled={page <= 1 || loading} onClick={() => rechercher(page - 1)}>← Précédent</BoutonY2K>
              <span className="text-xs text-muted-foreground self-center">{page}/{data.total_pages}</span>
              <BoutonY2K size="sm" variant="secondary" disabled={page >= data.total_pages || loading} onClick={() => rechercher(page + 1)}>Suivant →</BoutonY2K>
            </div>
          )}
        </>
      )}

      {/* Saisie email d'un prospect (la base FINESS officielle ne contient pas
          les emails — on le récupère à l'appel puis tout devient 1-clic) */}
      {emailEdit && (
        <FormPanel titre="Email de l'établissement" onClose={() => setEmailEdit(null)} onSave={sauverEmail}>
          <p className="text-xs text-muted-foreground mb-2">
            Complétez uniquement une adresse publique vérifiée. L’enregistrement ne déclenche aucun message.
          </p>
          <Champ label="Adresse email">
            <Input type="email" value={emailEdit.valeur} onChange={e => setEmailEdit({ ...emailEdit, valeur: e.target.value })} placeholder="ex : direction@nom-etablissement.fr" />
          </Champ>
        </FormPanel>
      )}

    </div>
  );
}

/* ── Envoi EN MASSE du template aux prospects avec email jamais contactés ──
   Les bases officielles (FINESS, Annuaire Santé / RPPS) publient des coordonnées
   de façon inégale : le flux = appel → email saisi sur la carte → ce bouton envoie le
   template à tous ceux qui en ont un, sans repasser un par un. Garde
   anti-doublon : email_envoye_le. 100 max par clic (limite Resend). */
function EnvoiMasseBar({ cible }: { cible: 'ETABLISSEMENT' | 'SOIGNANT' }) {
  const [aEnvoyer, setAEnvoyer] = useState<number | null>(null);
  const [template, setTemplate] = useState<{ sujet: string; contenu: string } | null>(null);
  const [envoi, setEnvoi] = useState(false);
  const [enrichissement, setEnrichissement] = useState(false);
  const [erreurEtat, setErreurEtat] = useState<string | null>(null);
  const [marketingActif, setMarketingActif] = useState<boolean | null>(null);
  const chargementIdRef = useRef(0);

  const chargerEtat = useCallback(async () => {
    const chargementId = ++chargementIdRef.current;
    const [statsResult, templateResult, marketingResult] = await Promise.all([
      supabase.rpc('fn_admin_prospection_stats' as any),
      cible === 'ETABLISSEMENT'
        ? supabase.from('sales_templates' as any).select('sujet, contenu').eq('nom', TEMPLATE_PROSPECTION_NOM).maybeSingle()
        : supabase.from('sales_templates' as any).select('sujet, contenu').eq('cible', 'SOIGNANT').limit(1).maybeSingle(),
      supabase.from('growth_config' as any).select('valeur').eq('cle', 'automatisations_marketing_actives').maybeSingle(),
    ]);
    if (chargementId !== chargementIdRef.current) return;

    const stats = !statsResult.error ? normaliserStatsProspection(statsResult.data) : null;
    const compteur = cible === 'ETABLISSEMENT'
      ? stats?.etablissements?.avec_email_non_contacte
      : stats?.soignants?.avec_email_non_contacte;

    if (estNombreCompteur(compteur)) {
      setAEnvoyer(compteur);
      setErreurEtat(null);
    } else {
      // Ne jamais convertir un timeout ou un count nul en « 0 prospect ».
      // Une valeur précédente reste visible jusqu'à la prochaine réponse valide.
      setErreurEtat('Le compteur exact est momentanément indisponible. La dernière valeur connue est conservée.');
    }

    if (!templateResult.error) setTemplate((templateResult.data as any) || null);
    setMarketingActif(!marketingResult.error && (marketingResult.data as any)?.valeur === 'true');
  }, [cible]);

  useEffect(() => {
    void chargerEtat();
    return () => { chargementIdRef.current += 1; };
  }, [chargerEtat]);

  // Enrichissement Annuaire Santé (FHIR ANS) : remplit email/telephone depuis
  // le registre officiel — étabs par FINESS (exact), soignants par nom+prénom
  // (match non ambigu uniquement). 40 fiches par clic, relançable.
  const enrichir = async () => {
    setEnrichissement(true);
    try {
      const { data, error } = await supabase.functions.invoke('enrich-prospects-annuaire', {
        body: { cible },
      });
      if (error || (data as any)?.error) { toast.error((data as any)?.error || 'Enrichissement impossible.'); return; }
      const d = data as any;
      toast.success(`${d.traites} fiche(s) passée(s) à l'Annuaire Santé : ${d.emails} email(s) + ${d.telephones} téléphone(s) trouvés${d.ambigus ? ` · ${d.ambigus} homonyme(s) ignoré(s) par sécurité` : ''}${d.reste_a_traiter ? ' — d’autres fiches restent à traiter, recliquez pour continuer' : ''}`);
      void chargerEtat();
    } finally {
      setEnrichissement(false);
    }
  };

  const envoyerTous = async () => {
    if (!marketingActif) {
      toast.error('Envoi groupé désactivé avant le lancement.');
      return;
    }
    if (!template || !estNombreCompteur(aEnvoyer) || aEnvoyer === 0) return;
    if (!window.confirm(`Envoyer le template officiel aux ${Math.min(aEnvoyer, 100)} prospect(s) avec email jamais contactés ? (max 100 par clic — recliquez pour la tranche suivante)`)) return;
    setEnvoi(true);
    try {
      const { data, error } = await supabase.functions.invoke('sales-outreach-batch', {
        body: { cible, sujet: template.sujet, corps: template.contenu },
      });
      if (error || (data as any)?.error) { toast.error((data as any)?.error || 'Envoi en masse impossible.'); return; }
      const d = data as any;
      toast.success(`${d.envoyes} email(s) envoyé(s)${d.echecs ? `, ${d.echecs} échec(s)` : ''}${d.restants ? ` — ${d.restants} restant(s), recliquez pour continuer` : ' — tous les prospects avec email sont contactés'}`);
      void chargerEtat();
    } finally {
      setEnvoi(false);
    }
  };

  return (
    <div className="rounded-xl border border-primary/30 bg-primary/5 p-3 mb-4 flex flex-col sm:flex-row sm:items-center gap-2">
      <p className="text-sm text-muted-foreground flex-1" aria-live="polite">
        <strong className="text-foreground">Emails prêts : {afficherCompteur(aEnvoyer)}</strong>. Ce nombre compte uniquement les fiches avec une adresse email, jamais le total de l’annuaire.
        {aEnvoyer === 0 && ' L’enrichissement peut compléter progressivement les coordonnées publiques.'}
        {marketingActif === false && ' Les envois groupés sont verrouillés avant le lancement.'}
        {erreurEtat && <> <span role="alert" className="text-amber-700 dark:text-amber-300">{erreurEtat}</span></>}
        {!template && ' Aucun template trouvé (onglet Modèles).'}
      </p>
      {erreurEtat && (
        <BoutonY2K size="sm" variant="ghost" onClick={() => void chargerEtat()} className="whitespace-nowrap">
          Réessayer
        </BoutonY2K>
      )}
      <BoutonY2K
        size="sm"
        variant="secondary"
        onClick={enrichir}
        disabled={enrichissement}
        loading={enrichissement}
        className="whitespace-nowrap"
      >
        Enrichir (Annuaire Santé)
      </BoutonY2K>
      <BoutonY2K
        size="sm"
        onClick={envoyerTous}
        disabled={!marketingActif || envoi || aEnvoyer === null || aEnvoyer === 0 || !template}
        loading={envoi}
        iconeGauche={envoi ? undefined : <Send className="h-4 w-4" />}
        className="whitespace-nowrap"
      >
        {marketingActif ? 'Envoyer le template à tous' : 'Envoi groupé désactivé'}
      </BoutonY2K>
    </div>
  );
}

/* ── Modal d'import CSV en masse (groupes ou contacts) ── */
function ImportCsvModal({ cible, onClose, onImport }: {
  cible: 'GROUPES' | 'CONTACTS';
  onClose: () => void;
  onImport: (texte: string) => Promise<void>;
}) {
  const titleId = useId();
  const [texte, setTexte] = useState('');
  const [encours, setEncours] = useState(false);
  const format = cible === 'GROUPES'
    ? 'nom;url;profession;region'
    : 'nom;telephone;email;ville;profession';

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-foreground/40 p-0 sm:p-4" onClick={onClose}>
      <div className="bg-card w-full sm:max-w-lg rounded-t-2xl sm:rounded-2xl p-5 max-h-[90vh] overflow-y-auto space-y-3" role="dialog" aria-modal="true" aria-labelledby={titleId} onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between">
          <h2 id={titleId} className="font-bold text-foreground">Importer en masse ({cible === 'GROUPES' ? 'groupes' : 'contacts'})</h2>
          <button aria-label="Fermer l’import CSV" onClick={onClose} className="text-muted-foreground hover:text-foreground"><X className="h-5 w-5" aria-hidden="true" /></button>
        </div>
        <p className="text-xs text-muted-foreground">
          Une ligne par entrée, colonnes séparées par <code>;</code> — format : <code>{format}</code>.
          Collez directement depuis Excel/Numbers (export CSV point-virgule).
        </p>
        <Textarea aria-label={`Données CSV à importer pour ${cible === 'GROUPES' ? 'les groupes' : 'les contacts'}`} value={texte} onChange={e => setTexte(e.target.value)} rows={10}
          placeholder={cible === 'GROUPES'
            ? "IDEL Bretagne;https://facebook.com/groups/xxx;IDE;Bretagne"
            : "EHPAD Les Lilas;0145678900;contact@leslilas.fr;Paris;"} />
        <div className="flex gap-2">
          <BoutonY2K disabled={encours || !texte.trim()} className="flex-1"
            onClick={async () => { setEncours(true); await onImport(texte); setEncours(false); }}>
            {encours ? 'Import…' : 'Importer'}
          </BoutonY2K>
          <BoutonY2K variant="secondary" onClick={onClose}>Annuler</BoutonY2K>
        </div>
      </div>
    </div>
  );
}

/* ── Posts de la semaine : textes prêts-à-coller générés depuis les missions réelles ── */
function PostsGenerateur() {
  const [stats, setStats] = useState<any[]>([]);
  const [chargement, setChargement] = useState(true);
  const [lienAvis, setLienAvis] = useState('');
  const [lienAvisSauve, setLienAvisSauve] = useState(false);

  useEffect(() => {
    (async () => {
      const [r, cfg] = await Promise.all([
        supabase.rpc('fn_admin_generer_posts' as any),
        supabase.from('growth_config' as any).select('valeur').eq('cle', 'lien_avis_google').maybeSingle(),
      ]);
      if (r.error) toast.error(r.error.message);
      setStats((r.data as any[]) || []);
      setLienAvis(((cfg.data as any)?.valeur || '') as string);
      setChargement(false);
    })();
  }, []);

  const copier = (txt: string) => {
    navigator.clipboard.writeText(txt);
    toast.success('Post copié — collez-le dans le groupe.');
  };

  const sauverLienAvis = async () => {
    const { error } = await supabase.from('growth_config' as any)
      .update({ valeur: lienAvis.trim(), maj_le: new Date().toISOString() } as any)
      .eq('cle', 'lien_avis_google');
    if (error) { toast.error(error.message); return; }
    setLienAvisSauve(true);
    toast.success('Lien avis Google enregistré — il sera inclus dans les emails post-mission.');
    setTimeout(() => setLienAvisSauve(false), 2000);
  };

  const utm = 'utm_source=social&utm_medium=organic&utm_campaign=post-hebdo';
  const buildPost = (s: any) => {
    const label = getLabelProfession(s.profession) || s.profession;
    const taux = s.taux_max ? ` jusqu'à ${Number(s.taux_max).toFixed(0)} €/h` : '';
    const villes = s.villes ? ` (${s.villes})` : '';
    return `${s.nb} mission${s.nb > 1 ? 's' : ''} ${label} disponible${s.nb > 1 ? 's' : ''} cette semaine${villes}${taux}.\n\nÉtablissements vérifiés, contrat et modalités de paiement affichés, inscription gratuite.\nhttps://jolene.app/soignant/recherche-missions?${utm}\n\n#emploi #soignant #${(s.profession || '').toLowerCase()}`;
  };
  const totalMissions = stats.reduce((acc, s) => acc + Number(s.nb || 0), 0);
  const postGlobal = `${totalMissions} mission${totalMissions > 1 ? 's' : ''} médicales et paramédicales ouvertes cette semaine sur Jolene.\n\nInfirmiers, aides-soignants, kinés et autres professionnels de santé : des établissements vérifiés recrutent près de chez vous. Contrat et modalités de paiement affichés, 0 frais pour les soignants.\nhttps://jolene.app?${utm}\n\n#emploi #santé #soignants`;

  if (chargement) return <ChargementSectionAdmin label="Chargement des posts…" />;

  return (
    <div className="space-y-4">
      <p className="text-xs text-muted-foreground">
        Textes générés depuis les missions réellement ouvertes — copiez-les dans vos groupes Facebook/WhatsApp/LinkedIn
        (onglet Groupes). Les liens incluent un suivi automatique : l'impact est visible dans Acquisition.
      </p>

      {/* Config lien avis Google (utilisé par l'email post-mission automatique) */}
      <CardY2K hoverLift={false}>
        <CardY2KContent>
          <p className="font-semibold text-foreground text-sm mb-1">Lien avis Google</p>
          <p className="text-xs text-muted-foreground mb-2">
            Collez ici le lien "Demander des avis" de votre fiche Google Business. Tant qu'il est vide, l'email
            automatique post-mission n'envoie que le nudge parrainage.
          </p>
          <div className="flex gap-2">
          <Input aria-label="Lien Google pour recueillir des avis" value={lienAvis} onChange={e => setLienAvis(e.target.value)} placeholder="https://g.page/r/…/review" className="h-9" />
            <BoutonY2K size="sm" onClick={sauverLienAvis} iconeGauche={<Save className="h-4 w-4" />}>
              {lienAvisSauve ? 'Enregistré' : 'Enregistrer'}
            </BoutonY2K>
          </div>
        </CardY2KContent>
      </CardY2K>

      {totalMissions === 0 ? (
        <CardY2K hoverLift={false}>
          <CardY2KContent>
            <p className="text-sm text-muted-foreground text-center py-6">
              Aucune mission ouverte en ce moment — les posts se généreront automatiquement dès qu'un établissement publie.
            </p>
          </CardY2KContent>
        </CardY2K>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          <CardY2K hoverLift={false}>
            <CardY2KContent>
              <div className="flex items-center justify-between gap-2 mb-2">
                <span className="font-semibold text-foreground">Post global (toutes professions)</span>
                <BadgeY2K variant="premium">{totalMissions} mission{totalMissions > 1 ? 's' : ''}</BadgeY2K>
              </div>
              <pre className="text-xs text-muted-foreground whitespace-pre-wrap font-sans bg-muted/40 rounded-lg p-3">{postGlobal}</pre>
              <BoutonY2K size="sm" className="mt-2" onClick={() => copier(postGlobal)} iconeGauche={<Copy className="h-4 w-4" />}>Copier</BoutonY2K>
            </CardY2KContent>
          </CardY2K>
          {stats.map(s => (
            <CardY2K key={s.profession} hoverLift={false}>
              <CardY2KContent>
                <div className="flex items-center justify-between gap-2 mb-2">
                  <span className="font-semibold text-foreground">{getLabelProfession(s.profession) || s.profession}</span>
                  <BadgeY2K variant="info">{s.nb} mission{Number(s.nb) > 1 ? 's' : ''}</BadgeY2K>
                </div>
                <pre className="text-xs text-muted-foreground whitespace-pre-wrap font-sans bg-muted/40 rounded-lg p-3">{buildPost(s)}</pre>
                <BoutonY2K size="sm" className="mt-2" onClick={() => copier(buildPost(s))} iconeGauche={<Copy className="h-4 w-4" />}>Copier</BoutonY2K>
              </CardY2KContent>
            </CardY2K>
          ))}
        </div>
      )}
    </div>
  );
}

/* ── Prospection soignants (base officielle Annuaire Santé / RPPS). ── */
const PROFESSIONS_PROSPECTION_SOIGNANTS = [
  { v: '', label: 'Toutes les professions' },
  { v: 'IDE', label: 'Infirmiers (IDE)' },
  { v: 'DENTISTE', label: 'Chirurgiens-dentistes' },
  { v: 'KINE', label: 'Kinésithérapeutes' },
  { v: 'MEDECIN', label: 'Médecins généralistes' },
  { v: 'SAGE_FEMME', label: 'Sages-femmes' },
  { v: 'ORTHOPHONISTE', label: 'Orthophonistes' },
  { v: 'PEDICURE_PODOLOGUE', label: 'Pédicures-podologues' },
];
const SUJET_PROSPECTION_SOIGNANT = 'Des missions de soignant près de chez vous';
const CORPS_PROSPECTION_SOIGNANT = `Bonjour,

Je suis Gabrielle, la fondatrice de Jolene. Des établissements de santé près de chez vous cherchent des renforts ponctuels — et sur Jolene, c'est vous qui choisissez vos missions, vos dates et votre taux.

• Inscription gratuite en 2 minutes, zéro commission pour les soignants
• Contrats et démarches administratives gérés automatiquement
• Contrat et modalités de paiement affichés avant candidature

Découvrez les missions ouvertes : https://jolene.app/inscription/soignant

Bien à vous,
Gabrielle Picard
Fondatrice de Jolene
gabrielle@jolene.app`;

function ProspectionSoignants({ onAjouter }: { onAjouter: () => void }) {
  const [profession, setProfessionP] = useState('');
  const [departement, setDepartement] = useState('');
  const [q, setQ] = useState('');
  const qRef = useRef('');
  const [favoris, setFavoris] = useState(false);
  const [avecEmail, setAvecEmail] = useState(false);
  const [avecTel, setAvecTel] = useState(false);
  const [page, setPage] = useState(1);
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(false);
  const [erreurRecherche, setErreurRecherche] = useState<string | null>(null);
  const rechercheIdRef = useRef(0);
  const [emailEdit, setEmailEdit] = useState<{ cle: string; valeur: string } | null>(null);
  const [etudiants, setEtudiants] = useState(false);

  const rechercher = useCallback(async (p = 1) => {
    const rechercheId = ++rechercheIdRef.current;
    setLoading(true);
    const { data: res, error } = await supabase.rpc('fn_admin_chercher_prospects_soignants' as any, {
      p_profession: profession || null,
      p_departement: departement.trim() || null,
      p_q: qRef.current.trim() || null,
      p_favoris: favoris,
      p_page: p,
      p_avec_email: avecEmail,
      p_avec_tel: avecTel,
      p_etudiants: etudiants,
    });
    if (rechercheId !== rechercheIdRef.current) return;
    setLoading(false);
    if (error) {
      const message = messageErreurProspection(error);
      setErreurRecherche(message);
      toast.error(message);
      return;
    }
    setErreurRecherche(null);
    setData(res);
    setPage(p);
  }, [profession, departement, favoris, avecEmail, avecTel, etudiants]);

  useEffect(() => { void rechercher(1); }, [rechercher]); // q via Enter/bouton

  const toggleFavori = async (pr: any) => {
    const { error } = await supabase.from('prospects_soignants' as any)
      .update({ favori: !pr.favori } as any).eq('cle', pr.cle);
    if (error) { toast.error(error.message); return; }
    rechercher(page);
  };

  const sauverEmail = async () => {
    if (!emailEdit) return;
    const valeur = emailEdit.valeur.trim();
    const { error } = await supabase.from('prospects_soignants' as any)
      .update({ email: valeur || null } as any).eq('cle', emailEdit.cle);
    if (error) { toast.error(error.message); return; }
    setEmailEdit(null);
    rechercher(page);
    toast.success('Email enregistré. Aucun message envoyé.');
  };

  const ajouterProspectAuCrm = async (pr: any): Promise<string | null> => {
    const { data: resultat, error } = await supabase.rpc('fn_admin_sourcing_ajouter_crm' as any, {
      p_cible: 'SOIGNANT',
      p_prospect_id: pr.cle,
      p_score: null,
    });
    if (error) { toast.error(error.message); return null; }
    const contactId = (resultat as { contact_id?: string } | null)?.contact_id;
    if (!contactId) { toast.error('Le contact CRM créé est introuvable.'); return null; }
    return contactId;
  };

  const ajouterAuPipeline = async (pr: any) => {
    const contactId = await ajouterProspectAuCrm(pr);
    if (!contactId) return;
    toast.success('Ajouté aux prospects. Aucun message envoyé.');
    onAjouter();
  };

  const total = estNombreCompteur(data?.total) ? data.total : null;

  return (
    <div className="space-y-4">
      <CardY2K hoverLift={false}>
        <CardY2KContent>
          <p className="text-[11px] text-muted-foreground mb-2">
            Base officielle Annuaire Santé / RPPS : professionnels <strong>salariés, libéraux et étudiants</strong>,
            avec rattachement à une structure lorsqu'il est publié. Recherche <strong>nationale</strong> — département optionnel.
            Les coordonnées de contact ne sont pas renseignées pour tous les professionnels.
          </p>
          <div className="flex flex-col sm:flex-row gap-2 sm:items-end flex-wrap">
            <div className="flex-1 min-w-[170px]">
              <Label className="text-xs">Profession</Label>
              <select aria-label="Profession des soignants à prospecter" value={profession} onChange={e => setProfessionP(e.target.value)} className="input-base h-9 w-full">
                {PROFESSIONS_PROSPECTION_SOIGNANTS.map(c => <option key={c.v} value={c.v}>{c.label}</option>)}
              </select>
            </div>
            <div>
              <Label className="text-xs">Département (optionnel)</Label>
              <Input aria-label="Département des soignants à prospecter" value={departement} onChange={e => setDepartement(e.target.value)} placeholder="National" className="h-9 w-28" />
            </div>
            <div className="flex-1 min-w-[160px]">
              <Label className="text-xs">Nom, ville ou cabinet</Label>
              <Input aria-label="Nom, ville ou cabinet du soignant à prospecter" value={q} onChange={e => { qRef.current = e.target.value; setQ(e.target.value); }} onKeyDown={e => { if (e.key === 'Enter') rechercher(1); }} placeholder="Dupont, Lorient…" className="h-9" />
            </div>
            <BoutonY2K size="sm" variant={avecEmail ? 'primary' : 'secondary'} onClick={() => setAvecEmail(!avecEmail)} iconeGauche={<Mail className="h-4 w-4" />}>Avec email</BoutonY2K>
            <BoutonY2K size="sm" variant={avecTel ? 'primary' : 'secondary'} onClick={() => setAvecTel(!avecTel)} iconeGauche={<Phone className="h-4 w-4" />}>Avec tél.</BoutonY2K>
            <BoutonY2K size="sm" variant={favoris ? 'primary' : 'secondary'} onClick={() => setFavoris(!favoris)} iconeGauche={<Star className="h-4 w-4" />}>Favoris</BoutonY2K>
            <BoutonY2K size="sm" variant={etudiants ? 'primary' : 'secondary'} onClick={() => setEtudiants(!etudiants)}>Étudiants</BoutonY2K>
            <BoutonY2K size="sm" onClick={() => rechercher(1)} disabled={loading} iconeGauche={<Search className="h-4 w-4" />}>
              {loading ? 'Recherche…' : 'Rechercher'}
            </BoutonY2K>
          </div>
        </CardY2KContent>
      </CardY2K>

      {erreurRecherche && (
        <p role="alert" className="text-xs text-amber-700 dark:text-amber-300 rounded-lg border border-amber-300/60 bg-amber-50/70 dark:bg-amber-950/20 px-3 py-2">
          {erreurRecherche}
        </p>
      )}

      {data && (
        <>
          <p className="text-xs text-muted-foreground">
            {total === null ? 'Total momentanément indisponible' : `${total.toLocaleString('fr-FR')} soignant(s)`} — page {data.page}/{Math.max(data.total_pages, 1)}
            {total === 0 && " · Si la base semble vide, l'import Annuaire Santé est peut-être encore en cours (10-15 min)."}
          </p>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            {(data.resultats || []).map((pr: any) => (
              <CardY2K key={pr.cle} hoverLift={false}>
                <CardY2KContent>
                  <div className="flex items-start gap-1.5">
                    <button onClick={() => toggleFavori(pr)} title="Favori" className="mt-0.5 shrink-0">
                      <Star className={`h-4 w-4 ${pr.favori ? 'fill-yellow-400 text-yellow-400' : 'text-muted-foreground'}`} />
                    </button>
                    <div className="min-w-0">
                      <span className="font-semibold text-foreground">{pr.prenom} {pr.nom}</span>
                      <p className="text-xs text-muted-foreground mt-0.5">
                        {PROFESSIONS_PROSPECTION_SOIGNANTS.find(c => c.v === pr.profession)?.label || pr.profession}
                        {pr.ville ? ` · ${pr.ville}` : ''}{pr.code_postal ? ` (${pr.code_postal})` : ''}
                        {pr.enseigne ? ` · ${pr.enseigne}` : ''}
                      </p>
                    </div>
                  </div>
                  <div className="flex gap-2 mt-3 flex-wrap items-center">
                    <BoutonY2K size="sm" onClick={() => ajouterAuPipeline(pr)} iconeGauche={<Plus className="h-4 w-4" />}>Ajouter aux prospects</BoutonY2K>
                    {!pr.email && (
                      <BoutonY2K size="sm" variant="ghost" onClick={() => setEmailEdit({ cle: pr.cle, valeur: '' })} iconeGauche={<Pencil className="h-4 w-4" />}>Renseigner l’email</BoutonY2K>
                    )}
                    <span className="text-[11px] text-muted-foreground">Qualification interne uniquement</span>
                  </div>
                  {(pr.telephone || pr.email) && (
                    <p className="text-[11px] mt-1.5 flex flex-wrap gap-x-2">
                      {pr.telephone && <span>{pr.telephone}</span>}
                      {pr.email && <span className="break-all">{pr.email}</span>}
                    </p>
                  )}
                </CardY2KContent>
              </CardY2K>
            ))}
          </div>
          {data.total_pages > 1 && (
            <div className="flex justify-center gap-2 pt-2">
              <BoutonY2K size="sm" variant="secondary" disabled={page <= 1 || loading} onClick={() => rechercher(page - 1)}>← Précédent</BoutonY2K>
              <span className="text-xs text-muted-foreground self-center">{page}/{data.total_pages}</span>
              <BoutonY2K size="sm" variant="secondary" disabled={page >= data.total_pages || loading} onClick={() => rechercher(page + 1)}>Suivant →</BoutonY2K>
            </div>
          )}
        </>
      )}

      {emailEdit && (
        <FormPanel titre="Email du soignant" onClose={() => setEmailEdit(null)} onSave={sauverEmail}>
          <p className="text-xs text-muted-foreground mb-2">
            Complétez uniquement une adresse publique vérifiée. L’enregistrement ne déclenche aucun message.
          </p>
          <Champ label="Adresse email">
            <Input type="email" value={emailEdit.valeur} onChange={e => setEmailEdit({ ...emailEdit, valeur: e.target.value })} placeholder="ex : prenom.nom@gmail.com" />
          </Champ>
        </FormPanel>
      )}

    </div>
  );
}

/* ── Backlinks / Annuaires : liste suivie pour soumettre Jolene Santé ── */
const CATEGORIES_ANNUAIRE = [
  { v: '', label: 'Toutes catégories' },
  { v: 'SAAS', label: 'Logiciels / SaaS' },
  { v: 'STARTUP', label: 'Startups' },
  { v: 'B2B', label: 'B2B / entreprises' },
  { v: 'EMPLOI', label: 'Emploi / recrutement' },
  { v: 'SANTE', label: 'Santé' },
  { v: 'GENERAL', label: 'Généraliste' },
];
const STATUTS_ANNUAIRE = ['A_SOUMETTRE', 'SOUMIS', 'PUBLIE', 'REFUSE'];
const LABELS_STATUT_ANNUAIRE: Record<string, string> = { A_SOUMETTRE: 'À soumettre', SOUMIS: 'Soumis', PUBLIE: 'Publié', REFUSE: 'Refusé' };
function badgeStatutAnnuaire(s: string): 'success' | 'warning' | 'error' | 'info' {
  if (s === 'PUBLIE') return 'success';
  if (s === 'REFUSE') return 'error';
  if (s === 'SOUMIS') return 'info';
  return 'warning';
}
function badgeAutorite(a: string): 'success' | 'warning' | 'info' {
  return a === 'ELEVEE' ? 'success' : a === 'FAIBLE' ? 'warning' : 'info';
}

function BacklinksAnnuaires() {
  const [annuaires, setAnnuaires] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [fStatut, setFStatut] = useState('');
  const [fCategorie, setFCategorie] = useState('');
  const [edit, setEdit] = useState<any | null>(null);

  const charger = useCallback(async () => {
    setLoading(true);
    const { data } = await supabase.from('sales_annuaires' as any).select('*')
      .order('favori', { ascending: false }).order('autorite').order('nom');
    setAnnuaires((data as any[]) || []);
    setLoading(false);
  }, []);
  useEffect(() => { charger(); }, [charger]);

  const maj = async (id: string, patch: any) => {
    const { error } = await supabase.from('sales_annuaires' as any).update({ ...patch, maj_le: new Date().toISOString() } as any).eq('id', id);
    if (error) { toast.error(error.message); return; }
    charger();
  };
  const copier = async (txt: string) => {
    try { await navigator.clipboard.writeText(txt); toast.success('Texte copié — collez-le dans l\'annuaire.'); }
    catch { toast.error('Copie impossible.'); }
  };

  const liste = useMemo(() => annuaires.filter(a =>
    (!fStatut || a.statut === fStatut) && (!fCategorie || a.categorie === fCategorie),
  ), [annuaires, fStatut, fCategorie]);
  const stats = useMemo(() => ({
    aSoumettre: annuaires.filter(a => a.statut === 'A_SOUMETTRE').length,
    publies: annuaires.filter(a => a.statut === 'PUBLIE').length,
  }), [annuaires]);

  if (loading) return <ChargementSectionAdmin label="Chargement des annuaires…" />;
  return (
    <div className="space-y-4">
      <CardY2K hoverLift={false}><CardY2KContent>
        <p className="text-xs text-muted-foreground">
          Annuaires où soumettre Jolene Santé pour obtenir des <strong>backlinks</strong> (liens entrants = confiance Google).
          Le texte est déjà rédigé : <strong>« Copier le texte »</strong>, ouvrez l'annuaire, collez, puis passez la fiche en « Soumis ».
          {' '}<strong className="text-foreground">{stats.aSoumettre}</strong> à soumettre · <strong className="text-foreground">{stats.publies}</strong> publié(s).
        </p>
      </CardY2KContent></CardY2K>

      <div className="flex gap-2 flex-wrap items-end">
        <div>
          <Label className="text-xs">Statut</Label>
          <select aria-label="Filtrer les annuaires par statut" value={fStatut} onChange={e => setFStatut(e.target.value)} className="input-base h-8 text-xs">
            <option value="">Tous</option>
            {STATUTS_ANNUAIRE.map(s => <option key={s} value={s}>{LABELS_STATUT_ANNUAIRE[s]}</option>)}
          </select>
        </div>
        <div>
          <Label className="text-xs">Catégorie</Label>
          <select aria-label="Filtrer les annuaires par catégorie" value={fCategorie} onChange={e => setFCategorie(e.target.value)} className="input-base h-8 text-xs">
            {CATEGORIES_ANNUAIRE.map(c => <option key={c.v} value={c.v}>{c.label}</option>)}
          </select>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
        {liste.map(a => (
          <CardY2K key={a.id} hoverLift={false}>
            <CardY2KContent>
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0 flex items-start gap-1.5">
                  <button
                    onClick={() => maj(a.id, { favori: !a.favori })}
                    className="mt-0.5 shrink-0"
                    aria-label={`${a.favori ? 'Retirer des favoris' : 'Ajouter aux favoris'} : ${a.nom}`}
                    aria-pressed={Boolean(a.favori)}
                  >
                    <Star aria-hidden="true" className={`h-4 w-4 ${a.favori ? 'fill-yellow-400 text-yellow-400' : 'text-muted-foreground'}`} />
                  </button>
                  <div className="min-w-0">
                    <a href={a.url} target="_blank" rel="noopener noreferrer" className="font-semibold text-primary hover:underline inline-flex items-center gap-1">{a.nom}<ExternalLink className="h-3.5 w-3.5 shrink-0" /></a>
                    <p className="text-[11px] text-muted-foreground mt-0.5">{CATEGORIES_ANNUAIRE.find(c => c.v === a.categorie)?.label || a.categorie}</p>
                  </div>
                </div>
                <div className="flex items-center gap-1.5 flex-wrap justify-end">
                  <BadgeY2K variant={badgeAutorite(a.autorite)}>{a.autorite === 'ELEVEE' ? 'Autorité élevée' : a.autorite === 'FAIBLE' ? 'Autorité faible' : 'Autorité moyenne'}</BadgeY2K>
                  {a.gratuit && <BadgeY2K variant="info">Gratuit</BadgeY2K>}
                  <BadgeY2K variant={badgeStatutAnnuaire(a.statut)}>{LABELS_STATUT_ANNUAIRE[a.statut]}</BadgeY2K>
                </div>
              </div>
              {a.comment_soumettre && <p className="text-[11px] text-muted-foreground mt-2">Soumission : {a.comment_soumettre}</p>}
              {a.texte_a_soumettre && <pre className="text-[11px] text-muted-foreground whitespace-pre-wrap font-sans bg-muted/40 rounded-lg p-2.5 mt-2">{a.texte_a_soumettre}</pre>}
              <div className="flex gap-2 mt-2 flex-wrap items-center">
                <BoutonY2K size="sm" onClick={() => copier(a.texte_a_soumettre || '')} iconeGauche={<Copy className="h-4 w-4" />}>Copier le texte</BoutonY2K>
                <BoutonY2K size="sm" variant="secondary" onClick={() => window.open(a.url, '_blank', 'noopener')} iconeGauche={<ExternalLink className="h-4 w-4" />}>Ouvrir l'annuaire</BoutonY2K>
                <select aria-label={`Statut de l’annuaire ${a.nom}`} value={a.statut} onChange={e => maj(a.id, { statut: e.target.value })} className="input-base h-8 text-xs">
                  {STATUTS_ANNUAIRE.map(s => <option key={s} value={s}>{LABELS_STATUT_ANNUAIRE[s]}</option>)}
                </select>
                <BoutonY2K size="sm" variant="ghost" onClick={() => setEdit({ ...a })} iconeGauche={<Pencil className="h-4 w-4" />}>Note / lien</BoutonY2K>
              </div>
              {a.lien_obtenu && <p className="text-[11px] mt-1.5"><a href={a.lien_obtenu} target="_blank" rel="noopener noreferrer" className="text-primary hover:underline break-all">{a.lien_obtenu}</a></p>}
              {a.notes && <p className="text-[11px] text-muted-foreground mt-1">{a.notes}</p>}
            </CardY2KContent>
          </CardY2K>
        ))}
      </div>

      {edit && (
        <FormPanel titre={`Fiche — ${edit.nom}`} onClose={() => setEdit(null)} onSave={async () => { await maj(edit.id, { lien_obtenu: edit.lien_obtenu || null, notes: edit.notes || null }); setEdit(null); }}>
          <Champ label="Lien obtenu (URL du backlink une fois publié)"><Input value={edit.lien_obtenu || ''} onChange={e => setEdit({ ...edit, lien_obtenu: e.target.value })} placeholder="https://…" /></Champ>
          <Champ label="Notes"><Textarea value={edit.notes || ''} onChange={e => setEdit({ ...edit, notes: e.target.value })} rows={3} /></Champ>
        </FormPanel>
      )}
    </div>
  );
}
