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

export default function AdminSales() {
  usePageTitle('Sales / Sourcing');
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<'groupes' | 'soignants' | 'etablissements' | 'prospection' | 'etab_jolene' | 'templates'>('groupes');

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

  const [fFavorisGroupes, setFFavorisGroupes] = useState(false);
  const [voirArchives, setVoirArchives] = useState(false);

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

  const majStatutContact = async (id: string, statut: string) => {
    const { error } = await supabase.from('sales_contacts' as any).update({ statut, maj_le: new Date().toISOString() } as any).eq('id', id);
    if (error) { toast.error(error.message); return; }
    charger();
  };

  const supprimerContact = async (id: string) => {
    const { error } = await supabase.from('sales_contacts' as any).delete().eq('id', id);
    if (error) { toast.error(error.message); return; }
    charger();
  };

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  return (
    <LayoutAdmin>
      <div className="space-y-5">
        <div>
          <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
            <Megaphone className="h-5 w-5 text-primary" /> Sales / Sourcing
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
          <BoutonY2K variant={tab === 'prospection' ? 'primary' : 'secondary'} size="sm" onClick={() => setTab('prospection')} iconeGauche={<Search className="h-4 w-4" />}>Prospection</BoutonY2K>
          <BoutonY2K variant={tab === 'etab_jolene' ? 'primary' : 'secondary'} size="sm" onClick={() => setTab('etab_jolene')} iconeGauche={<Building2 className="h-4 w-4" />}>Étab. Jolene</BoutonY2K>
          <BoutonY2K variant={tab === 'templates' ? 'primary' : 'secondary'} size="sm" onClick={() => setTab('templates')} iconeGauche={<FileText className="h-4 w-4" />}>Templates ({templates.length})</BoutonY2K>
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
            onEdit={c => setEditContact({ ...c })}
            onStatut={majStatutContact}
            onFavori={toggleFavoriContact}
            onArchive={archiverContact}
          />
        )}

        {/* ── PROSPECTION (base nationale) ── */}
        {tab === 'prospection' && <ProspectionEtab onAjouter={charger} />}

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
                    <BadgeY2K variant="info">{t.cible === 'GROUPE' ? 'Post groupe' : t.cible === 'SOIGNANT' ? 'DM soignant' : 'DM établissement'}</BadgeY2K>
                  </div>
                  <pre className="text-xs text-muted-foreground whitespace-pre-wrap font-sans bg-muted/40 rounded-lg p-3">{t.contenu}</pre>
                  <BoutonY2K size="sm" className="mt-2" onClick={() => copier(t.contenu)} iconeGauche={<Copy className="h-4 w-4" />}>Copier le message</BoutonY2K>
                </CardY2KContent>
              </CardY2K>
            ))}
          </div>
        )}
      </div>

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
                {STATUTS_CONTACT.map(s => <option key={s} value={s}>{s}</option>)}
              </select>
            </Champ>
          </div>
          <Champ label="Notes"><Textarea value={editContact.notes || ''} onChange={e => setEditContact({ ...editContact, notes: e.target.value })} rows={2} /></Champ>
        </FormPanel>
      )}
    </LayoutAdmin>
  );
}
/* ── Sous-composant liste contacts ── */
function ListeContacts({ type, contacts, voirArchives, onToggleArchives, onAdd, onEdit, onStatut, onFavori, onArchive }: {
  type: 'SOIGNANT' | 'ETABLISSEMENT';
  contacts: any[];
  voirArchives: boolean;
  onToggleArchives: () => void;
  onAdd: () => void;
  onEdit: (c: any) => void;
  onStatut: (id: string, s: string) => void;
  onFavori: (c: any) => void;
  onArchive: (c: any, archive: boolean) => void;
}) {
  return (
    <div className="space-y-3">
      <div className="flex justify-end gap-2">
        <BoutonY2K size="sm" variant={voirArchives ? 'primary' : 'secondary'} onClick={onToggleArchives} iconeGauche={<Archive className="h-4 w-4" />}>
          {voirArchives ? 'Masquer les archivés' : 'Voir les archivés'}
        </BoutonY2K>
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
                    <BadgeY2K variant={badgeStatutContact(c.statut)}>{c.statut}</BadgeY2K>
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
                    <BoutonY2K size="sm" variant="secondary" onClick={() => { window.location.href = `mailto:${c.email}`; }} iconeGauche={<Mail className="h-4 w-4" />}>Email</BoutonY2K>
                  )}
                </div>
                {/* Pipeline + édition */}
                <div className="flex gap-2 mt-2 items-center flex-wrap">
                  <select value={c.statut} onChange={e => onStatut(c.id, e.target.value)} className="input-base h-8 text-xs">
                    {STATUTS_CONTACT.map(s => <option key={s} value={s}>{s}</option>)}
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
];

function ProspectionEtab({ onAjouter }: { onAjouter: () => void }) {
  const [type, setType] = useState('');
  const [departement, setDepartement] = useState('');
  const [q, setQ] = useState('');
  const [favoris, setFavoris] = useState(false);
  const [page, setPage] = useState(1);
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(false);
  const [emailEdit, setEmailEdit] = useState<{ finess: string; valeur: string } | null>(null);
  const [outreach, setOutreach] = useState<any | null>(null);

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
    const { error } = await supabase.from('prospects_etablissements' as any)
      .update({ email: emailEdit.valeur || null } as any).eq('finess', emailEdit.finess);
    if (error) { toast.error(error.message); return; }
    toast.success('Email enregistré.');
    setEmailEdit(null);
    rechercher(page);
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
                        <BoutonY2K size="sm" variant="secondary" onClick={() => { window.location.href = `mailto:${pr.email}`; }} iconeGauche={<Mail className="h-4 w-4" />}>Email</BoutonY2K>
                        <BoutonY2K size="sm" variant="secondary" onClick={() => setOutreach(pr)} iconeGauche={<Send className="h-4 w-4" />}>Via Jolene</BoutonY2K>
                      </>
                    ) : (
                      <BoutonY2K size="sm" variant="ghost" onClick={() => setEmailEdit({ finess: pr.finess, valeur: '' })} iconeGauche={<Pencil className="h-4 w-4" />}>+ Email</BoutonY2K>
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

      {/* Saisie email d'un prospect */}
      {emailEdit && (
        <FormPanel titre="Email de l'établissement" onClose={() => setEmailEdit(null)} onSave={sauverEmail}>
          <Champ label="Adresse email">
            <Input type="email" value={emailEdit.valeur} onChange={e => setEmailEdit({ ...emailEdit, valeur: e.target.value })} placeholder="contact@etablissement.fr" />
          </Champ>
        </FormPanel>
      )}

      {/* Envoi email via Jolene */}
      {outreach && <OutreachModal prospect={outreach} onClose={() => { setOutreach(null); rechercher(page); onAjouter(); }} />}
    </div>
  );
}

/* ── Modal d'envoi email 1-clic via Jolene (Resend) ── */
function OutreachModal({ prospect, onClose }: { prospect: any; onClose: () => void }) {
  const [sujet, setSujet] = useState(`Renfort soignant pour ${prospect.nom}`);
  const [corps, setCorps] = useState(
    `Bonjour,\n\nJe suis Gabrielle, fondatrice de Jolene (jolene.app). Nous mettons en relation les établissements de santé avec des soignants vérifiés, disponibles rapidement — contrats et DPAE gérés par la plateforme.\n\nSeriez-vous disponible pour un échange de 10 minutes cette semaine ?\n\nBien cordialement,\nGabrielle — Jolene`
  );
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
        <p className="text-xs text-muted-foreground">À : {prospect.email} · De : Gabrielle de Jolene (réponses → ta boîte perso)</p>
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
