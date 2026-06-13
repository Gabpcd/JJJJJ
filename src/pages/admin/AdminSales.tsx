import { useState, useEffect, useMemo, useCallback } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { PROFESSIONS, getLabelProfession } from '@/lib/constantes';
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
const SUJET_PROSPECTION_DEFAUT = 'Renfort soignant sous 48h pour {{nom}} — sans engagement';
const CORPS_PROSPECTION_DEFAUT = `Bonjour,

Je suis Gabrielle, fondatrice de Jolene (jolene.app), la plateforme qui met en relation les établissements de santé avec des soignants vérifiés — diplômes, RPPS et assurances contrôlés.

Concrètement pour {{nom}} :
• Publiez un besoin en 2 minutes, recevez des candidatures de soignants notés et vérifiés
• Contrats et déclarations générés automatiquement
• 15 % de commission tout compris, sans abonnement ni engagement

Auriez-vous 10 minutes cette semaine pour en parler ? Vous pouvez répondre directement à cet email.

Bien cordialement,
Gabrielle — Fondatrice de Jolene
jolene.app`;

interface TemplateProspection { sujet: string; contenu: string }

function remplirTemplate(txt: string, p: { nom?: string | null; ville?: string | null }): string {
  return (txt || '')
    .split('{{nom}}').join(p.nom || 'votre établissement')
    .split('{{ville}}').join(p.ville || '');
}

/** Ouvre le client mail avec destinataire + sujet + corps pré-remplis (1 clic, zéro copier-coller). */
function ouvrirMailto(email: string, tpl: TemplateProspection, p: { nom?: string | null; ville?: string | null }) {
  const sujet = encodeURIComponent(remplirTemplate(tpl.sujet, p));
  const corps = encodeURIComponent(remplirTemplate(tpl.contenu, p));
  window.location.href = `mailto:${email}?subject=${sujet}&body=${corps}`;
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

export default function AdminSales() {
  usePageTitle('Recruter des soignants et des établissements');
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<'groupes' | 'soignants' | 'etablissements' | 'prospection' | 'prospection_soignants' | 'etab_jolene' | 'templates' | 'posts'>('groupes');

  const [groupes, setGroupes] = useState<any[]>([]);
  const [contacts, setContacts] = useState<any[]>([]);
  const [templates, setTemplates] = useState<any[]>([]);

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
    setLoading(true);
    const [g, c, t] = await Promise.all([
      supabase.from('sales_groupes' as any).select('*').order('favori', { ascending: false }).order('plateforme').order('profession'),
      supabase.from('sales_contacts' as any).select('*').order('favori', { ascending: false }).order('cree_le', { ascending: false }),
      supabase.from('sales_templates' as any).select('*').order('cible'),
    ]);
    setGroupes((g.data as any[]) || []);
    setContacts((c.data as any[]) || []);
    setTemplates((t.data as any[]) || []);
    setLoading(false);
  }, []);

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

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  return (
    <LayoutAdmin>
      <div className="space-y-5">
        <div>
          <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
            <Megaphone className="h-5 w-5 text-primary" /> Recruter des soignants et des établissements
          </h1>
          <p className="text-sm text-muted-foreground">
            Groupes de recrutement (WhatsApp, Facebook, LinkedIn…), contacts sourcés & publication assistée.
          </p>
        </div>

        {/* Tabs */}
        <div className="flex gap-2 flex-wrap">
          <BoutonY2K variant={tab === 'groupes' ? 'primary' : 'secondary'} size="sm" onClick={() => setTab('groupes')} iconeGauche={<Megaphone className="h-4 w-4" />}>Groupes ({groupes.length})</BoutonY2K>
          <BoutonY2K variant={tab === 'soignants' ? 'primary' : 'secondary'} size="sm" onClick={() => setTab('soignants')} iconeGauche={<Users className="h-4 w-4" />}>Soignants ({soignants.length})</BoutonY2K>
          <BoutonY2K variant={tab === 'etablissements' ? 'primary' : 'secondary'} size="sm" onClick={() => setTab('etablissements')} iconeGauche={<Building2 className="h-4 w-4" />}>Étab. sourcés ({etablissements.length})</BoutonY2K>
          <BoutonY2K variant={tab === 'prospection' ? 'primary' : 'secondary'} size="sm" onClick={() => setTab('prospection')} iconeGauche={<Search className="h-4 w-4" />}>Prospection étab.</BoutonY2K>
          <BoutonY2K variant={tab === 'prospection_soignants' ? 'primary' : 'secondary'} size="sm" onClick={() => setTab('prospection_soignants')} iconeGauche={<Users className="h-4 w-4" />}>Prospection soignants</BoutonY2K>
          <BoutonY2K variant={tab === 'etab_jolene' ? 'primary' : 'secondary'} size="sm" onClick={() => setTab('etab_jolene')} iconeGauche={<Building2 className="h-4 w-4" />}>Étab. Jolene</BoutonY2K>
          <BoutonY2K variant={tab === 'templates' ? 'primary' : 'secondary'} size="sm" onClick={() => setTab('templates')} iconeGauche={<FileText className="h-4 w-4" />}>Modèles ({templates.length})</BoutonY2K>
          <BoutonY2K variant={tab === 'posts' ? 'primary' : 'secondary'} size="sm" onClick={() => setTab('posts')} iconeGauche={<Send className="h-4 w-4" />}>Posts de la semaine</BoutonY2K>
        </div>

        {/* ── GROUPES ── */}
        {tab === 'groupes' && (
          <div className="space-y-4">
            <div className="flex flex-col sm:flex-row gap-2 items-stretch sm:items-end">
              <div className="flex-1">
                <Label className="text-xs">Recherche</Label>
                <div className="relative">
                  <Search className="absolute left-2 top-2.5 h-4 w-4 text-muted-foreground" />
                  <Input value={recherche} onChange={e => setRecherche(e.target.value)} placeholder="Nom, région, note…" className="pl-8 h-9" />
                </div>
              </div>
              <div>
                <Label className="text-xs">Plateforme</Label>
                <select value={fPlateforme} onChange={e => setFPlateforme(e.target.value)} className="input-base h-9 w-full">
                  <option value="">Toutes</option>
                  {PLATEFORMES.map(p => <option key={p.v} value={p.v}>{p.label}</option>)}
                </select>
              </div>
              <div>
                <Label className="text-xs">Profession</Label>
                <select value={fProfession} onChange={e => setFProfession(e.target.value)} className="input-base h-9 w-full">
                  <option value="">Toutes</option>
                  <option value="TOUTES">Toutes professions</option>
                  {PROFESSIONS.map(p => <option key={p.valeur} value={p.valeur}>{p.label}</option>)}
                </select>
              </div>
              <BoutonY2K size="sm" variant={fFavorisGroupes ? 'primary' : 'secondary'} onClick={() => setFFavorisGroupes(!fFavorisGroupes)} iconeGauche={<Star className="h-4 w-4" />}>Favoris</BoutonY2K>
              <BoutonY2K size="sm" onClick={() => setEditGroupe({ plateforme: 'FACEBOOK', profession: 'TOUTES', audience: 'MIXTE', statut: 'A_VERIFIER' })} iconeGauche={<Plus className="h-4 w-4" />}>Ajouter</BoutonY2K>
              <BoutonY2K size="sm" variant="ghost" onClick={() => setImportCible('GROUPES')} iconeGauche={<FileText className="h-4 w-4" />}>Importer CSV</BoutonY2K>
            </div>

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
                        <button onClick={() => toggleFavoriGroupe(g)} title={g.favori ? 'Retirer des favoris' : 'Ajouter aux favoris'}
                          className="p-1.5 rounded-lg hover:bg-muted transition-colors">
                          <Star className={`h-5 w-5 ${g.favori ? 'fill-yellow-400 text-yellow-400' : 'text-muted-foreground'}`} />
                        </button>
                        {g.url ? (
                          <BoutonY2K size="sm" onClick={() => window.open(g.url, '_blank', 'noopener')} iconeGauche={<ExternalLink className="h-4 w-4" />}>Ouvrir</BoutonY2K>
                        ) : (
                          <BadgeY2K variant="warning">Lien à renseigner</BadgeY2K>
                        )}
                        <BoutonY2K size="sm" variant="ghost" onClick={() => setEditGroupe({ ...g })}>Éditer</BoutonY2K>
                        <BoutonY2K size="sm" variant="ghost" onClick={() => supprimerGroupe(g.id)} iconeGauche={<Trash2 className="h-4 w-4" />} />
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
            onToggleArchives={() => setVoirArchives(!voirArchives)}
            onAdd={() => setEditContact({ type: tab === 'soignants' ? 'SOIGNANT' : 'ETABLISSEMENT', statut: 'PROSPECT' })}
            onImport={() => setImportCible('CONTACTS')}
            onEdit={c => setEditContact({ ...c })}
            onStatut={majStatutContact}
            onFavori={toggleFavoriContact}
            onArchive={archiverContact}
          />
        )}

        {/* ── PROSPECTION (base nationale) ── */}
        {tab === 'prospection' && (<><EnvoiMasseBar cible="ETABLISSEMENT" /><ProspectionEtab onAjouter={charger} /></>)}

        {/* ── PROSPECTION SOIGNANTS (Annuaire Santé CNAM, libéraux + tél cabinet) ── */}
        {tab === 'prospection_soignants' && (<><EnvoiMasseBar cible="SOIGNANT" /><ProspectionSoignants onAjouter={charger} /></>)}

        {/* ── ÉTABLISSEMENTS JOLENE (inscrits) ── */}
        {tab === 'etab_jolene' && <EtablissementsJolene />}

        {/* ── TEMPLATES ── */}
        {tab === 'templates' && (
          <div className="space-y-3">
            <p className="text-xs text-muted-foreground">
              Publication assistée : copiez le message et ouvrez le groupe pour le coller (l'auto-post natif est interdit par WhatsApp/Facebook).
            </p>
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
/* ── Sous-composant liste contacts ── */
function ListeContacts({ type, contacts, voirArchives, onToggleArchives, onAdd, onImport, onEdit, onStatut, onFavori, onArchive }: {
  type: 'SOIGNANT' | 'ETABLISSEMENT';
  contacts: any[];
  voirArchives: boolean;
  onToggleArchives: () => void;
  onAdd: () => void;
  onImport: () => void;
  onEdit: (c: any) => void;
  onStatut: (id: string, s: string) => void;
  onFavori: (c: any) => void;
  onArchive: (c: any, archive: boolean) => void;
}) {
  const tpl = useTemplateProspection();
  return (
    <div className="space-y-3">
      <div className="flex justify-end gap-2">
        <BoutonY2K size="sm" variant={voirArchives ? 'primary' : 'secondary'} onClick={onToggleArchives} iconeGauche={<Archive className="h-4 w-4" />}>
          {voirArchives ? 'Masquer les archivés' : 'Voir les archivés'}
        </BoutonY2K>
        <BoutonY2K size="sm" variant="ghost" onClick={onImport} iconeGauche={<FileText className="h-4 w-4" />}>Importer CSV</BoutonY2K>
        <BoutonY2K size="sm" onClick={onAdd} iconeGauche={<Plus className="h-4 w-4" />}>
          Ajouter {type === 'SOIGNANT' ? 'un soignant' : 'un établissement'}
        </BoutonY2K>
      </div>
      {contacts.length === 0 ? (
        <CardY2K hoverLift={false}><CardY2KContent><p className="text-sm text-muted-foreground text-center py-6">Aucun contact sourcé pour l'instant.</p></CardY2KContent></CardY2K>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          {contacts.map(c => (
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
                        {c.ville ? ` · ${c.ville}` : ''}
                      </p>
                    </div>
                  </div>
                  <div className="flex items-center gap-1.5">
                    {c.archive && <BadgeY2K variant="warning">Archivé</BadgeY2K>}
                    <BadgeY2K variant={badgeStatutContact(c.statut)}>{LABELS_STATUT_CONTACT[c.statut] || c.statut}</BadgeY2K>
                  </div>
                </div>
                {/* Contacter */}
                <div className="flex gap-2 mt-3 flex-wrap">
                  {c.telephone && (
                    <>
                      <BoutonY2K size="sm" onClick={() => { window.location.href = `tel:${c.telephone}`; }} iconeGauche={<Phone className="h-4 w-4" />}>Appeler</BoutonY2K>
                      <BoutonY2K size="sm" variant="secondary" onClick={() => window.open(lienWhatsApp(c.telephone), '_blank', 'noopener')} iconeGauche={<MessageCircle className="h-4 w-4" />}>WhatsApp</BoutonY2K>
                    </>
                  )}
                  {c.email && (
                    <BoutonY2K size="sm" variant="secondary"
                      onClick={() => type === 'ETABLISSEMENT' ? ouvrirMailto(c.email, tpl, c) : (window.location.href = `mailto:${c.email}`)}
                      iconeGauche={<Mail className="h-4 w-4" />}>Email</BoutonY2K>
                  )}
                </div>
                {/* Pipeline + édition */}
                <div className="flex gap-2 mt-2 items-center flex-wrap">
                  <select value={c.statut} onChange={e => onStatut(c.id, e.target.value)} className="input-base h-8 text-xs">
                    {STATUTS_CONTACT.map(s => <option key={s} value={s}>{LABELS_STATUT_CONTACT[s] || s}</option>)}
                  </select>
                  <BoutonY2K size="sm" variant="ghost" onClick={() => onEdit(c)}>Éditer</BoutonY2K>
                  {c.archive ? (
                    <BoutonY2K size="sm" variant="ghost" onClick={() => onArchive(c, false)} iconeGauche={<RotateCcw className="h-4 w-4" />}>Restaurer</BoutonY2K>
                  ) : (
                    <BoutonY2K size="sm" variant="ghost" onClick={() => onArchive(c, true)} iconeGauche={<Archive className="h-4 w-4" />}>Retirer</BoutonY2K>
                  )}
                </div>
                {c.notes && <p className="text-[11px] text-muted-foreground mt-2">{c.notes}</p>}
              </CardY2KContent>
            </CardY2K>
          ))}
        </div>
      )}
    </div>
  );
}

/* ── Panneau de formulaire ── */
function FormPanel({ titre, children, onClose, onSave }: { titre: string; children: React.ReactNode; onClose: () => void; onSave: () => void }) {
  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-foreground/40 p-0 sm:p-4" onClick={onClose}>
      <div className="bg-card w-full sm:max-w-lg rounded-t-2xl sm:rounded-2xl p-5 max-h-[90vh] overflow-y-auto space-y-3" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between">
          <h2 className="font-bold text-foreground">{titre}</h2>
          <button onClick={onClose} className="text-muted-foreground hover:text-foreground"><X className="h-5 w-5" /></button>
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
  return <div><Label className="text-xs">{label}</Label>{children}</div>;
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
        <Input value={recherche} onChange={e => setRecherche(e.target.value)} placeholder="Nom ou ville…" className="pl-8 h-9" />
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
                      {e.type}{e.ville ? ` · ${e.ville}` : ''}{e.code_postal ? ` (${e.code_postal})` : ''}
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
  { v: 'PHARMACIE', label: "Pharmacies d'officine" },
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
  const [favoris, setFavoris] = useState(false);
  const [page, setPage] = useState(1);
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(false);
  const [emailEdit, setEmailEdit] = useState<{ finess: string; valeur: string; prospect?: any } | null>(null);
  const [outreach, setOutreach] = useState<any | null>(null);
  const tpl = useTemplateProspection();

  const rechercher = useCallback(async (p = 1) => {
    setLoading(true);
    const { data: res, error } = await supabase.rpc('fn_admin_chercher_prospects' as any, {
      p_type: type || null,
      p_departement: departement.trim() || null,
      p_q: q.trim() || null,
      p_favoris: favoris,
      p_page: p,
    });
    setLoading(false);
    if (error) { toast.error(error.message); return; }
    setData(res);
    setPage(p);
  }, [type, departement, q, favoris]);

  useEffect(() => { rechercher(1); }, [type, departement, favoris]); // recherche live (q via bouton/Enter)

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
    const prospect = emailEdit.prospect;
    setEmailEdit(null);
    rechercher(page);
    // Enchaîne directement sur l'envoi : email saisi → modal d'envoi pré-remplie.
    if (valeur && prospect) {
      toast.success('Email enregistré — envoi prêt.');
      setOutreach({ ...prospect, email: valeur });
    } else {
      toast.success('Email enregistré.');
    }
  };

  const ajouterAuPipeline = async (pr: any) => {
    const { error } = await supabase.from('sales_contacts' as any).upsert({
      type: 'ETABLISSEMENT', nom: pr.nom, ville: pr.ville || null,
      telephone: pr.telephone || null, email: pr.email || null, finess: pr.finess,
      statut: 'PROSPECT', notes: `Prospection FINESS ${pr.finess}${pr.siret ? ` · SIRET ${pr.siret}` : ''}`,
    } as any, { onConflict: 'finess' });
    if (error) { toast.error(error.message); return; }
    toast.success('Ajouté aux établissements sourcés.');
    onAjouter();
  };

  const total = data?.total ?? 0;

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
              <select value={type} onChange={e => setType(e.target.value)} className="input-base h-9 w-full">
                {TYPES_PROSPECTION.map(c => <option key={c.v} value={c.v}>{c.label}</option>)}
              </select>
            </div>
            <div>
              <Label className="text-xs">Département (optionnel)</Label>
              <Input value={departement} onChange={e => setDepartement(e.target.value)} placeholder="National" className="h-9 w-28" />
            </div>
            <div className="flex-1 min-w-[160px]">
              <Label className="text-xs">Nom ou ville</Label>
              <Input value={q} onChange={e => setQ(e.target.value)} onKeyDown={e => { if (e.key === 'Enter') rechercher(1); }} placeholder="Korian, Marseille…" className="h-9" />
            </div>
            <BoutonY2K size="sm" variant={favoris ? 'primary' : 'secondary'} onClick={() => setFavoris(!favoris)} iconeGauche={<Star className="h-4 w-4" />}>Favoris</BoutonY2K>
            <BoutonY2K size="sm" onClick={() => rechercher(1)} disabled={loading} iconeGauche={<Search className="h-4 w-4" />}>
              {loading ? 'Recherche…' : 'Rechercher'}
            </BoutonY2K>
          </div>
        </CardY2KContent>
      </CardY2K>

      {data && (
        <>
          <p className="text-xs text-muted-foreground">
            {total.toLocaleString('fr-FR')} établissement(s) — page {data.page}/{Math.max(data.total_pages, 1)}
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

                  <div className="flex gap-2 mt-3 flex-wrap">
                    {pr.telephone ? (
                      <BoutonY2K size="sm" onClick={() => { window.location.href = `tel:${pr.telephone}`; }} iconeGauche={<Phone className="h-4 w-4" />}>
                        Appeler
                      </BoutonY2K>
                    ) : (
                      <BadgeY2K variant="warning">Tél. non renseigné</BadgeY2K>
                    )}
                    {pr.email ? (
                      <>
                        <BoutonY2K size="sm" onClick={() => setOutreach(pr)} iconeGauche={<Send className="h-4 w-4" />}>Envoyer l'email</BoutonY2K>
                        <BoutonY2K size="sm" variant="secondary" onClick={() => ouvrirMailto(pr.email, tpl, pr)} iconeGauche={<Mail className="h-4 w-4" />}>Ma boîte mail</BoutonY2K>
                      </>
                    ) : (
                      <BoutonY2K size="sm" variant="ghost" onClick={() => setEmailEdit({ finess: pr.finess, valeur: '', prospect: pr })} iconeGauche={<Pencil className="h-4 w-4" />}>+ Email</BoutonY2K>
                    )}
                    <BoutonY2K size="sm" variant="ghost" onClick={() => ajouterAuPipeline(pr)} iconeGauche={<Plus className="h-4 w-4" />}>Pipeline</BoutonY2K>
                  </div>
                  {pr.telephone && <p className="text-[11px] text-muted-foreground mt-1.5">{pr.telephone}{pr.email ? ` · ${pr.email}` : ''}</p>}
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
            L'enrichissement Annuaire Santé remplit automatiquement les emails trouvables (en fond, en continu).
            Pour ceux qu'il ne trouve pas, demandez-le à l'appel — une fois saisi, l'envoi se fait en 1 clic.
          </p>
          <Champ label="Adresse email">
            <Input type="email" value={emailEdit.valeur} onChange={e => setEmailEdit({ ...emailEdit, valeur: e.target.value })} placeholder="ex : direction@nom-etablissement.fr" />
          </Champ>
        </FormPanel>
      )}

      {/* Envoi email via Jolene */}
      {outreach && <OutreachModal prospect={outreach} template={tpl} onClose={() => { setOutreach(null); rechercher(page); onAjouter(); }} />}
    </div>
  );
}

/* ── Envoi EN MASSE du template aux prospects avec email jamais contactés ──
   Les bases officielles (FINESS, CNAM) fournissent les téléphones mais aucun
   email : le flux = appel → email saisi sur la carte → ce bouton envoie le
   template à tous ceux qui en ont un, sans repasser un par un. Garde
   anti-doublon : email_envoye_le. 100 max par clic (limite Resend). */
function EnvoiMasseBar({ cible }: { cible: 'ETABLISSEMENT' | 'SOIGNANT' }) {
  const [aEnvoyer, setAEnvoyer] = useState<number | null>(null);
  const [template, setTemplate] = useState<{ sujet: string; contenu: string } | null>(null);
  const [envoi, setEnvoi] = useState(false);
  const [enrichissement, setEnrichissement] = useState(false);

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
      toast.success(`🔎 ${d.traites} fiche(s) passée(s) à l'Annuaire Santé : ${d.emails} email(s) + ${d.telephones} téléphone(s) trouvés${d.ambigus ? ` · ${d.ambigus} homonyme(s) ignoré(s) par sécurité` : ''}${d.restants ? ` — ${d.restants.toLocaleString('fr-FR')} restantes, recliquez pour continuer` : ''}`);
      chargerEtat();
    } finally {
      setEnrichissement(false);
    }
  };

  const table = cible === 'ETABLISSEMENT' ? 'prospects_etablissements' : 'prospects_soignants';

  const chargerEtat = async () => {
    const [{ count }, { data: tpl }] = await Promise.all([
      supabase.from(table as any).select('email', { count: 'exact', head: true })
        .not('email', 'is', null).neq('email', '').is('email_envoye_le', null),
      cible === 'ETABLISSEMENT'
        ? supabase.from('sales_templates' as any).select('sujet, contenu').eq('nom', TEMPLATE_PROSPECTION_NOM).maybeSingle()
        : supabase.from('sales_templates' as any).select('sujet, contenu').eq('cible', 'SOIGNANT').limit(1).maybeSingle(),
    ]);
    setAEnvoyer(count ?? 0);
    setTemplate((tpl as any) || null);
  };

  useEffect(() => { chargerEtat(); /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [cible]);

  const envoyerTous = async () => {
    if (!template) return;
    if (!window.confirm(`Envoyer le template officiel aux ${Math.min(aEnvoyer ?? 0, 100)} prospect(s) avec email jamais contactés ? (max 100 par clic — recliquez pour la tranche suivante)`)) return;
    setEnvoi(true);
    try {
      const { data, error } = await supabase.functions.invoke('sales-outreach-batch', {
        body: { cible, sujet: template.sujet, corps: template.contenu },
      });
      if (error || (data as any)?.error) { toast.error((data as any)?.error || 'Envoi en masse impossible.'); return; }
      const d = data as any;
      toast.success(`✉️ ${d.envoyes} email(s) envoyé(s)${d.echecs ? `, ${d.echecs} échec(s)` : ''}${d.restants ? ` — ${d.restants} restant(s), recliquez pour continuer` : ' — tous les prospects avec email sont contactés ✓'}`);
      chargerEtat();
    } finally {
      setEnvoi(false);
    }
  };

  if (aEnvoyer === null) return null;
  return (
    <div className="rounded-xl border border-primary/30 bg-primary/5 p-3 mb-4 flex flex-col sm:flex-row sm:items-center gap-2">
      <p className="text-xs text-muted-foreground flex-1">
        ✉️ <strong className="text-foreground">{aEnvoyer}</strong> prospect(s) <strong>avec un email collecté</strong>, jamais contacté(s) — prêts pour l'envoi groupé.
        {' '}<span className="text-muted-foreground/80">(Ce compteur ne montre QUE ceux qui ont déjà un email, pas le total de la base. L'enrichissement Annuaire Santé tourne automatiquement en fond et le fera monter.)</span>
        {aEnvoyer === 0 && ' Pour l’instant aucun email collecté : l’enrichissement auto les remplit progressivement, ou saisissez-les via « + Email » sur chaque carte.'}
        {!template && ' ⚠️ Aucun template trouvé (onglet Modèles).'}
      </p>
      <BoutonY2K
        size="sm"
        variant="secondary"
        onClick={enrichir}
        disabled={enrichissement}
        loading={enrichissement}
        className="whitespace-nowrap"
      >
        🔎 Enrichir (Annuaire Santé)
      </BoutonY2K>
      <BoutonY2K
        size="sm"
        onClick={envoyerTous}
        disabled={envoi || aEnvoyer === 0 || !template}
        loading={envoi}
        iconeGauche={envoi ? undefined : <Send className="h-4 w-4" />}
        className="whitespace-nowrap"
      >
        Envoyer le template à tous
      </BoutonY2K>
    </div>
  );
}

/* ── Modal d'envoi email 1-clic via Jolene (Resend) ──
   Pré-remplie avec le template officiel (onglet Templates) — modifiable avant envoi. */
function OutreachModal({ prospect, template, onClose }: { prospect: any; template: TemplateProspection; onClose: () => void }) {
  const [sujet, setSujet] = useState(remplirTemplate(template.sujet, prospect));
  const [corps, setCorps] = useState(remplirTemplate(template.contenu, prospect));
  const [envoi, setEnvoi] = useState(false);

  const envoyer = async () => {
    setEnvoi(true);
    const { data, error } = await supabase.functions.invoke('sales-outreach', {
      body: { email: prospect.email, sujet, corps, finess: prospect.finess },
    });
    setEnvoi(false);
    if (error || (data as any)?.error) { toast.error((data as any)?.error || 'Envoi impossible.'); return; }
    toast.success(`Email envoyé à ${prospect.email} — prospect passé en CONTACTÉ.`);
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-foreground/40 p-0 sm:p-4" onClick={onClose}>
      <div className="bg-card w-full sm:max-w-lg rounded-t-2xl sm:rounded-2xl p-5 max-h-[90vh] overflow-y-auto space-y-3" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between">
          <h2 className="font-bold text-foreground">Email à {prospect.nom}</h2>
          <button onClick={onClose} className="text-muted-foreground hover:text-foreground"><X className="h-5 w-5" /></button>
        </div>
        <p className="text-xs text-muted-foreground">À : {prospect.email} · De : Gabrielle de Jolene (réponses → votre boîte perso)</p>
        <Champ label="Sujet"><Input value={sujet} onChange={e => setSujet(e.target.value)} /></Champ>
        <Champ label="Message"><Textarea value={corps} onChange={e => setCorps(e.target.value)} rows={9} /></Champ>
        <div className="flex gap-2 pt-1">
          <BoutonY2K onClick={envoyer} disabled={envoi} iconeGauche={<Send className="h-4 w-4" />} className="flex-1">
            {envoi ? 'Envoi…' : 'Envoyer'}
          </BoutonY2K>
          <BoutonY2K variant="secondary" onClick={onClose}>Annuler</BoutonY2K>
        </div>
      </div>
    </div>
  );
}

/* ── Modal d'import CSV en masse (groupes ou contacts) ── */
function ImportCsvModal({ cible, onClose, onImport }: {
  cible: 'GROUPES' | 'CONTACTS';
  onClose: () => void;
  onImport: (texte: string) => Promise<void>;
}) {
  const [texte, setTexte] = useState('');
  const [encours, setEncours] = useState(false);
  const format = cible === 'GROUPES'
    ? 'nom;url;profession;region'
    : 'nom;telephone;email;ville;profession';

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-foreground/40 p-0 sm:p-4" onClick={onClose}>
      <div className="bg-card w-full sm:max-w-lg rounded-t-2xl sm:rounded-2xl p-5 max-h-[90vh] overflow-y-auto space-y-3" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between">
          <h2 className="font-bold text-foreground">Importer en masse ({cible === 'GROUPES' ? 'groupes' : 'contacts'})</h2>
          <button onClick={onClose} className="text-muted-foreground hover:text-foreground"><X className="h-5 w-5" /></button>
        </div>
        <p className="text-xs text-muted-foreground">
          Une ligne par entrée, colonnes séparées par <code>;</code> — format : <code>{format}</code>.
          Collez directement depuis Excel/Numbers (export CSV point-virgule).
        </p>
        <Textarea value={texte} onChange={e => setTexte(e.target.value)} rows={10}
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
    return `🩺 ${s.nb} mission${s.nb > 1 ? 's' : ''} ${label} disponible${s.nb > 1 ? 's' : ''} cette semaine${villes}${taux}.\n\nÉtablissements vérifiés, paiement garanti, inscription gratuite.\n👉 https://jolene.app/soignant/recherche-missions?${utm}\n\n#emploi #soignant #${(s.profession || '').toLowerCase()}`;
  };
  const totalMissions = stats.reduce((acc, s) => acc + Number(s.nb || 0), 0);
  const postGlobal = `🩺 ${totalMissions} mission${totalMissions > 1 ? 's' : ''} médicales et paramédicales ouvertes cette semaine sur Jolene.\n\nInfirmiers, aides-soignants, kinés, pharmaciens… des établissements vérifiés recrutent près de chez vous. Paiement garanti, 0 frais pour les soignants.\n👉 https://jolene.app?${utm}\n\n#emploi #santé #soignants`;

  if (chargement) return <ChargementPage />;

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
            <Input value={lienAvis} onChange={e => setLienAvis(e.target.value)} placeholder="https://g.page/r/…/review" className="h-9" />
            <BoutonY2K size="sm" onClick={sauverLienAvis} iconeGauche={<Save className="h-4 w-4" />}>
              {lienAvisSauve ? 'Enregistré ✓' : 'Enregistrer'}
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
                <BadgeY2K variant="premium">{totalMissions} missions</BadgeY2K>
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

/* ── Prospection soignants (base Annuaire Santé CNAM : libéraux conventionnés
   avec téléphone de cabinet — IDE, dentistes, kinés, médecins généralistes,
   pharmaciens titulaires, sages-femmes, orthophonistes, podologues) ── */
const PROFESSIONS_PROSPECTION_SOIGNANTS = [
  { v: '', label: 'Toutes les professions' },
  { v: 'IDE', label: 'Infirmiers (IDEL)' },
  { v: 'DENTISTE', label: 'Chirurgiens-dentistes' },
  { v: 'KINE', label: 'Kinésithérapeutes' },
  { v: 'MEDECIN', label: 'Médecins généralistes' },
  { v: 'PHARMACIEN', label: 'Pharmaciens (officines)' },
  { v: 'SAGE_FEMME', label: 'Sages-femmes' },
  { v: 'ORTHOPHONISTE', label: 'Orthophonistes' },
  { v: 'PEDICURE_PODOLOGUE', label: 'Pédicures-podologues' },
];
const SUJET_PROSPECTION_SOIGNANT = 'Des missions près de chez vous — inscription gratuite';
const CORPS_PROSPECTION_SOIGNANT = `Bonjour,

Je suis Gabrielle, fondatrice de Jolene (jolene.app). Des établissements de santé près de chez vous cherchent des renforts ponctuels — vous choisissez vos missions, vos dates et votre taux.

• Inscription gratuite en 2 minutes, zéro commission pour les soignants
• Contrats et démarches gérés automatiquement
• Paiement garanti et rapide

Découvrez les missions ouvertes : https://jolene.app/inscription/soignant?utm_source=prospection&utm_medium=email

Bien cordialement,
Gabrielle — Fondatrice de Jolene`;

function ProspectionSoignants({ onAjouter }: { onAjouter: () => void }) {
  const [profession, setProfessionP] = useState('');
  const [departement, setDepartement] = useState('');
  const [q, setQ] = useState('');
  const [favoris, setFavoris] = useState(false);
  const [page, setPage] = useState(1);
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(false);
  const [emailEdit, setEmailEdit] = useState<{ cle: string; valeur: string; prospect?: any } | null>(null);

  const rechercher = useCallback(async (p = 1) => {
    setLoading(true);
    const { data: res, error } = await supabase.rpc('fn_admin_chercher_prospects_soignants' as any, {
      p_profession: profession || null,
      p_departement: departement.trim() || null,
      p_q: q.trim() || null,
      p_favoris: favoris,
      p_page: p,
    });
    setLoading(false);
    if (error) { toast.error(error.message); return; }
    setData(res);
    setPage(p);
  }, [profession, departement, q, favoris]);

  useEffect(() => { rechercher(1); }, [profession, departement, favoris]); // q via Enter/bouton

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
    const prospect = emailEdit.prospect;
    setEmailEdit(null);
    rechercher(page);
    // Enchaîne directement sur l'envoi : email saisi → brouillon pré-rempli dans la boîte mail.
    if (valeur && prospect) {
      toast.success('Email enregistré — message prêt dans votre boîte mail.');
      mailtoSoignant({ ...prospect, email: valeur });
    } else {
      toast.success('Email enregistré.');
    }
  };

  const ajouterAuPipeline = async (pr: any) => {
    const { error } = await supabase.from('sales_contacts' as any).insert({
      type: 'SOIGNANT', nom: `${pr.prenom || ''} ${pr.nom}`.trim(), ville: pr.ville || null,
      telephone: pr.telephone || null, email: pr.email || null, profession: pr.profession,
      statut: 'PROSPECT', notes: `Prospection Annuaire Santé CNAM${pr.enseigne ? ` · ${pr.enseigne}` : ''}`,
    } as any);
    if (error) { toast.error(error.message); return; }
    toast.success('Ajouté aux soignants sourcés.');
    onAjouter();
  };

  const mailtoSoignant = (pr: any) => {
    const sujet = encodeURIComponent(SUJET_PROSPECTION_SOIGNANT);
    const corps = encodeURIComponent(CORPS_PROSPECTION_SOIGNANT);
    window.location.href = `mailto:${pr.email}?subject=${sujet}&body=${corps}`;
  };

  const total = data?.total ?? 0;

  return (
    <div className="space-y-4">
      <CardY2K hoverLift={false}>
        <CardY2KContent>
          <p className="text-[11px] text-muted-foreground mb-2">
            Base officielle Annuaire Santé (CNAM) : professionnels <strong>libéraux</strong> conventionnés
            avec téléphone de cabinet. Recherche <strong>nationale</strong> — département optionnel.
            (Les salariés n'apparaissent dans aucune base publique : pour eux, groupes + SEO + parrainage.)
          </p>
          <div className="flex flex-col sm:flex-row gap-2 sm:items-end flex-wrap">
            <div className="flex-1 min-w-[170px]">
              <Label className="text-xs">Profession</Label>
              <select value={profession} onChange={e => setProfessionP(e.target.value)} className="input-base h-9 w-full">
                {PROFESSIONS_PROSPECTION_SOIGNANTS.map(c => <option key={c.v} value={c.v}>{c.label}</option>)}
              </select>
            </div>
            <div>
              <Label className="text-xs">Département (optionnel)</Label>
              <Input value={departement} onChange={e => setDepartement(e.target.value)} placeholder="National" className="h-9 w-28" />
            </div>
            <div className="flex-1 min-w-[160px]">
              <Label className="text-xs">Nom, ville ou cabinet</Label>
              <Input value={q} onChange={e => setQ(e.target.value)} onKeyDown={e => { if (e.key === 'Enter') rechercher(1); }} placeholder="Dupont, Lorient…" className="h-9" />
            </div>
            <BoutonY2K size="sm" variant={favoris ? 'primary' : 'secondary'} onClick={() => setFavoris(!favoris)} iconeGauche={<Star className="h-4 w-4" />}>Favoris</BoutonY2K>
            <BoutonY2K size="sm" onClick={() => rechercher(1)} disabled={loading} iconeGauche={<Search className="h-4 w-4" />}>
              {loading ? 'Recherche…' : 'Rechercher'}
            </BoutonY2K>
          </div>
        </CardY2KContent>
      </CardY2K>

      {data && (
        <>
          <p className="text-xs text-muted-foreground">
            {total.toLocaleString('fr-FR')} soignant(s) — page {data.page}/{Math.max(data.total_pages, 1)}
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
                  <div className="flex gap-2 mt-3 flex-wrap">
                    {pr.telephone ? (
                      <BoutonY2K size="sm" onClick={() => { window.location.href = `tel:${pr.telephone}`; }} iconeGauche={<Phone className="h-4 w-4" />}>
                        Appeler
                      </BoutonY2K>
                    ) : (
                      <BadgeY2K variant="warning">Tél. non renseigné</BadgeY2K>
                    )}
                    {pr.email ? (
                      <BoutonY2K size="sm" variant="secondary" onClick={() => mailtoSoignant(pr)} iconeGauche={<Mail className="h-4 w-4" />}>Email</BoutonY2K>
                    ) : (
                      <BoutonY2K size="sm" variant="ghost" onClick={() => setEmailEdit({ cle: pr.cle, valeur: '', prospect: pr })} iconeGauche={<Pencil className="h-4 w-4" />}>+ Email</BoutonY2K>
                    )}
                    <BoutonY2K size="sm" variant="ghost" onClick={() => ajouterAuPipeline(pr)} iconeGauche={<Plus className="h-4 w-4" />}>Pipeline</BoutonY2K>
                  </div>
                  {pr.telephone && <p className="text-[11px] text-muted-foreground mt-1.5">{pr.telephone}{pr.email ? ` · ${pr.email}` : ''}</p>}
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
            L'enrichissement Annuaire Santé remplit en fond les emails trouvables (faible taux pour les
            soignants : homonymes ignorés par sécurité). Sinon, demandez-le à l'appel — puis tout devient 1-clic.
          </p>
          <Champ label="Adresse email">
            <Input type="email" value={emailEdit.valeur} onChange={e => setEmailEdit({ ...emailEdit, valeur: e.target.value })} placeholder="ex : prenom.nom@gmail.com" />
          </Champ>
        </FormPanel>
      )}
    </div>
  );
}
