import { useState, useEffect, useMemo } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementAdmin } from '@/components/admin/ChargementAdmin';
import { supabase } from '@/integrations/supabase/client';
import { CardY2K, CardY2KHeader, CardY2KTitle, CardY2KContent } from '@/components/y2k/CardY2K';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Plus, Save, X, FileText, ExternalLink, Trash2, Calculator } from 'lucide-react';
import { toast } from 'sonner';
import { SimulateurLevee } from '@/components/admin/SimulateurLevee';

const fmt = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 }).format(v);

type Statut = 'A_CONTACTER' | 'CONTACTE' | 'INTRO_FAITE' | 'PITCH' | 'DUE_DILIGENCE' | 'TERM_SHEET' | 'SIGNE' | 'DECLINE';

const STATUTS: { value: Statut; label: string; variant: 'info' | 'warning' | 'success' | 'error' | 'premium' }[] = [
  { value: 'A_CONTACTER', label: 'À contacter', variant: 'info' },
  { value: 'CONTACTE', label: 'Contacté', variant: 'info' },
  { value: 'INTRO_FAITE', label: 'Intro faite', variant: 'warning' },
  { value: 'PITCH', label: 'Pitch', variant: 'warning' },
  { value: 'DUE_DILIGENCE', label: 'Due diligence', variant: 'premium' },
  { value: 'TERM_SHEET', label: 'Term sheet', variant: 'premium' },
  { value: 'SIGNE', label: 'Signé', variant: 'success' },
  { value: 'DECLINE', label: 'Décliné', variant: 'error' },
];

function statutInfo(s: string) {
  return STATUTS.find(st => st.value === s) || STATUTS[0];
}

const CATEGORIES_DOC: { value: string; label: string }[] = [
  { value: 'NOTE', label: 'Note' },
  { value: 'BUSINESS_PLAN', label: 'Business plan' },
  { value: 'DECK', label: 'Deck' },
  { value: 'FINANCIER', label: 'Financier' },
  { value: 'LEGAL', label: 'Juridique' },
  { value: 'AUTRE', label: 'Autre' },
];

function categorieLabel(c: string) {
  return CATEGORIES_DOC.find(cat => cat.value === c)?.label || c;
}

interface Investisseur {
  id: string;
  nom: string;
  type: string;
  contact_nom: string | null;
  contact_email: string | null;
  statut: Statut;
  montant_vise: number | null;
  notes: string | null;
  derniere_interaction: string | null;
}

interface Document {
  id: string;
  titre: string;
  categorie: string;
  contenu: string | null;
  url_externe: string | null;
  cree_le: string;
}

function emptyInvestisseur(): Partial<Investisseur> {
  return { nom: '', type: 'VC', contact_nom: '', contact_email: '', statut: 'A_CONTACTER', montant_vise: null, notes: '' };
}

function emptyDoc(): Partial<Document> {
  return { titre: '', categorie: 'NOTE', contenu: '', url_externe: '' };
}

export default function AdminLevee() {
  usePageTitle('Levée de fonds');
  const [loading, setLoading] = useState(true);
  const [investisseurs, setInvestisseurs] = useState<Investisseur[]>([]);
  const [documents, setDocuments] = useState<Document[]>([]);
  const [showForm, setShowForm] = useState(false);
  const [editItem, setEditItem] = useState<Partial<Investisseur> | null>(null);
  const [showDocForm, setShowDocForm] = useState(false);
  const [editDoc, setEditDoc] = useState<Partial<Document> | null>(null);
  const [saving, setSaving] = useState(false);
  const [tab, setTab] = useState<'simulateur' | 'pipeline' | 'documents'>('simulateur');

  const charger = async () => {
    setLoading(true);
    const [resInv, resDocs] = await Promise.all([
      supabase.from('investisseurs_pipeline' as any).select('*').order('cree_le', { ascending: false }),
      supabase.from('fondateur_documents' as any).select('*').order('cree_le', { ascending: false }),
    ]);
    setInvestisseurs((resInv.data as any[]) || []);
    setDocuments((resDocs.data as any[]) || []);
    setLoading(false);
  };

  useEffect(() => { charger(); }, []);

  useEffect(() => {
    if (!showForm && !showDocForm) return;
    const fermerAvecEchap = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return;
      setShowForm(false);
      setEditItem(null);
      setShowDocForm(false);
      setEditDoc(null);
    };
    document.addEventListener('keydown', fermerAvecEchap);
    return () => document.removeEventListener('keydown', fermerAvecEchap);
  }, [showForm, showDocForm]);

  const stats = useMemo(() => {
    return {
      total: investisseurs.length,
      signes: investisseurs.filter(i => i.statut === 'SIGNE').length,
      montantSigne: investisseurs.filter(i => i.statut === 'SIGNE').reduce((s, i) => s + (Number(i.montant_vise) || 0), 0),
      parStatut: STATUTS.map(st => ({ ...st, count: investisseurs.filter(i => i.statut === st.value).length })),
    };
  }, [investisseurs]);

  const sauvegarderInvestisseur = async () => {
    if (!editItem?.nom?.trim()) { toast.error('Nom requis.'); return; }
    setSaving(true);
    const payload = {
      nom: editItem.nom!.trim(),
      type: editItem.type || 'VC',
      contact_nom: editItem.contact_nom || null,
      contact_email: editItem.contact_email || null,
      statut: editItem.statut || 'A_CONTACTER',
      montant_vise: Number(editItem.montant_vise) || null,
      notes: editItem.notes || null,
      derniere_interaction: new Date().toISOString(),
      maj_le: new Date().toISOString(),
    };
    let err;
    if (editItem.id) {
      ({ error: err } = await supabase.from('investisseurs_pipeline' as any).update(payload as any).eq('id', editItem.id));
    } else {
      ({ error: err } = await supabase.from('investisseurs_pipeline' as any).insert(payload as any));
    }
    setSaving(false);
    if (err) { toast.error("Impossible d'enregistrer l'investisseur. Veuillez réessayer."); return; }
    toast.success(editItem.id ? 'Investisseur mis à jour.' : 'Investisseur ajouté.');
    setShowForm(false); setEditItem(null); charger();
  };

  const supprimerInvestisseur = async (id: string) => {
    const { error } = await supabase.from('investisseurs_pipeline' as any).delete().eq('id', id);
    if (error) { toast.error('Impossible de supprimer cet investisseur. Veuillez réessayer.'); return; }
    toast.success('Supprimé.'); charger();
  };

  const sauvegarderDoc = async () => {
    if (!editDoc?.titre?.trim()) { toast.error('Titre requis.'); return; }
    setSaving(true);
    const payload = {
      titre: editDoc.titre!.trim(),
      categorie: editDoc.categorie || 'NOTE',
      contenu: editDoc.contenu || null,
      url_externe: editDoc.url_externe || null,
      maj_le: new Date().toISOString(),
    };
    let err;
    if (editDoc.id) {
      ({ error: err } = await supabase.from('fondateur_documents' as any).update(payload as any).eq('id', editDoc.id));
    } else {
      ({ error: err } = await supabase.from('fondateur_documents' as any).insert(payload as any));
    }
    setSaving(false);
    if (err) { toast.error("Impossible d'enregistrer le document. Veuillez réessayer."); return; }
    toast.success(editDoc.id ? 'Document mis à jour.' : 'Document ajouté.');
    setShowDocForm(false); setEditDoc(null); charger();
  };

  const supprimerDoc = async (id: string) => {
    const { error } = await supabase.from('fondateur_documents' as any).delete().eq('id', id);
    if (error) { toast.error('Impossible de supprimer ce document. Veuillez réessayer.'); return; }
    toast.success('Supprimé.'); charger();
  };

  if (loading) return <LayoutAdmin><ChargementAdmin titre="Levée de fonds & Documents" /></LayoutAdmin>;

  return (
    <LayoutAdmin>
      <div className="space-y-6">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div>
            <h1 className="text-xl font-bold text-foreground">Levée de fonds & Documents</h1>
            <p className="text-sm text-muted-foreground">Simulateur temps réel · Pipeline investisseurs · Documents</p>
          </div>
        </div>

        {/* Tabs */}
        <div className="flex gap-2 flex-wrap">
          <BoutonY2K variant={tab === 'simulateur' ? 'primary' : 'secondary'} size="sm" onClick={() => setTab('simulateur')} iconeGauche={<Calculator className="h-4 w-4" />}>
            Simulateur
          </BoutonY2K>
          <BoutonY2K variant={tab === 'pipeline' ? 'primary' : 'secondary'} size="sm" onClick={() => setTab('pipeline')}>
            Pipeline ({stats.total})
          </BoutonY2K>
          <BoutonY2K variant={tab === 'documents' ? 'primary' : 'secondary'} size="sm" onClick={() => setTab('documents')}>
            Documents ({documents.length})
          </BoutonY2K>
        </div>

        {tab === 'simulateur' && <SimulateurLevee />}

        {tab === 'pipeline' && (
          <>
            {/* Stats pipeline */}
            <div className="flex flex-wrap gap-2">
              {stats.parStatut.filter(s => s.count > 0).map(s => (
                <BadgeY2K key={s.value} variant={s.variant}>{s.label} ({s.count})</BadgeY2K>
              ))}
            </div>
            {stats.montantSigne > 0 && (
              <CardY2K hoverLift={false} className="bg-gradient-hero text-white">
                <div className="p-4 text-center">
                  <p className="text-sm opacity-80">Montant levé (signé)</p>
                  <p className="text-2xl font-bold">{fmt(stats.montantSigne)}</p>
                </div>
              </CardY2K>
            )}

            <BoutonY2K onClick={() => { setEditItem(emptyInvestisseur()); setShowForm(true); }} iconeGauche={<Plus className="h-4 w-4" />}>
              Ajouter un investisseur
            </BoutonY2K>

            <div className="space-y-3">
              {investisseurs.map(inv => {
                const si = statutInfo(inv.statut);
                return (
                  <CardY2K key={inv.id} hoverLift={false}>
                    <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 p-4">
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 flex-wrap">
                          <p className="font-semibold text-foreground">{inv.nom}</p>
                          <BadgeY2K variant={si.variant}>{si.label}</BadgeY2K>
                          <BadgeY2K variant="info">{inv.type}</BadgeY2K>
                        </div>
                        {inv.contact_nom && <p className="text-sm text-muted-foreground">{inv.contact_nom}{inv.contact_email ? ` · ${inv.contact_email}` : ''}</p>}
                        {inv.montant_vise && <p className="text-xs text-muted-foreground">Montant visé : {fmt(inv.montant_vise)}</p>}
                        {inv.notes && <p className="text-xs text-muted-foreground mt-1 line-clamp-2">{inv.notes}</p>}
                      </div>
                      <div className="flex gap-2 shrink-0">
                        <BoutonY2K variant="secondary" size="sm" onClick={() => { setEditItem({ ...inv }); setShowForm(true); }}>Modifier</BoutonY2K>
                        <BoutonY2K variant="destructive" size="sm" onClick={() => supprimerInvestisseur(inv.id)} iconeGauche={<Trash2 className="h-3 w-3" />}>
                          Suppr.
                        </BoutonY2K>
                      </div>
                    </div>
                  </CardY2K>
                );
              })}
              {investisseurs.length === 0 && <p className="text-sm text-muted-foreground text-center py-8">Aucun investisseur dans le pipeline.</p>}
            </div>
          </>
        )}

        {tab === 'documents' && (
          <>
            <BoutonY2K onClick={() => { setEditDoc(emptyDoc()); setShowDocForm(true); }} iconeGauche={<Plus className="h-4 w-4" />}>
              Ajouter un document
            </BoutonY2K>
            <div className="space-y-3">
              {documents.map(doc => (
                <CardY2K key={doc.id} hoverLift={false}>
                  <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 p-4">
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <FileText className="h-4 w-4 text-primary" />
                        <p className="font-semibold text-foreground">{doc.titre}</p>
                        <BadgeY2K variant="info">{categorieLabel(doc.categorie)}</BadgeY2K>
                      </div>
                      {doc.url_externe && (
                        <a href={doc.url_externe} target="_blank" rel="noopener noreferrer" className="text-xs text-primary inline-flex items-center gap-1 mt-1">
                          <ExternalLink className="h-3 w-3" /> Lien externe
                        </a>
                      )}
                      {doc.contenu && <p className="text-xs text-muted-foreground mt-1 line-clamp-3">{doc.contenu}</p>}
                      <p className="text-[10px] text-muted-foreground mt-1">{new Date(doc.cree_le).toLocaleDateString('fr-FR')}</p>
                    </div>
                    <div className="flex gap-2 shrink-0">
                      <BoutonY2K variant="secondary" size="sm" onClick={() => { setEditDoc({ ...doc }); setShowDocForm(true); }}>Modifier</BoutonY2K>
                      <BoutonY2K variant="destructive" size="sm" onClick={() => supprimerDoc(doc.id)} iconeGauche={<Trash2 className="h-3 w-3" />}>Suppr.</BoutonY2K>
                    </div>
                  </div>
                </CardY2K>
              ))}
              {documents.length === 0 && <p className="text-sm text-muted-foreground text-center py-8">Aucun document. Ajoutez vos business plans, decks, notes stratégiques.</p>}
            </div>
          </>
        )}

        {/* Modal investisseur */}
        {showForm && editItem && (
          <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-foreground/40">
            <CardY2K className="max-w-lg w-full max-h-[90vh] overflow-y-auto" role="dialog" aria-modal="true" aria-labelledby="admin-levee-investisseur-title">
              <CardY2KHeader>
                <div className="flex items-center justify-between w-full">
                  <CardY2KTitle id="admin-levee-investisseur-title" className="text-sm">{editItem.id ? 'Modifier' : 'Ajouter'} un investisseur</CardY2KTitle>
                  <button aria-label="Fermer le formulaire investisseur" onClick={() => { setShowForm(false); setEditItem(null); }} className="text-muted-foreground hover:text-foreground"><X className="h-5 w-5" aria-hidden="true" /></button>
                </div>
              </CardY2KHeader>
              <CardY2KContent className="space-y-4">
                <div>
                  <Label htmlFor="admin-levee-investisseur-nom">Nom du fonds / investisseur</Label>
                  <Input id="admin-levee-investisseur-nom" value={editItem.nom || ''} onChange={e => setEditItem({ ...editItem, nom: e.target.value })} />
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <Label htmlFor="admin-levee-investisseur-type">Type</Label>
                    <select id="admin-levee-investisseur-type" value={editItem.type || 'VC'} onChange={e => setEditItem({ ...editItem, type: e.target.value })} className="input-base w-full">
                      {['VC', 'BA', 'Family Office', 'Corporate', 'Public', 'Autre'].map(t => <option key={t} value={t}>{t}</option>)}
                    </select>
                  </div>
                  <div>
                    <Label htmlFor="admin-levee-investisseur-statut">Statut</Label>
                    <select id="admin-levee-investisseur-statut" value={editItem.statut || 'A_CONTACTER'} onChange={e => setEditItem({ ...editItem, statut: e.target.value as Statut })} className="input-base w-full">
                      {STATUTS.map(s => <option key={s.value} value={s.value}>{s.label}</option>)}
                    </select>
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <Label htmlFor="admin-levee-contact-nom">Contact</Label>
                    <Input id="admin-levee-contact-nom" value={editItem.contact_nom || ''} onChange={e => setEditItem({ ...editItem, contact_nom: e.target.value })} placeholder="Nom du contact" />
                  </div>
                  <div>
                    <Label htmlFor="admin-levee-contact-email">Email contact</Label>
                    <Input id="admin-levee-contact-email" type="email" value={editItem.contact_email || ''} onChange={e => setEditItem({ ...editItem, contact_email: e.target.value })} />
                  </div>
                </div>
                <div>
                  <Label htmlFor="admin-levee-montant">Montant visé (€)</Label>
                  <Input id="admin-levee-montant" type="number" value={editItem.montant_vise || ''} onChange={e => setEditItem({ ...editItem, montant_vise: Number(e.target.value) || null })} />
                </div>
                <div>
                  <Label htmlFor="admin-levee-investisseur-notes">Notes</Label>
                  <textarea id="admin-levee-investisseur-notes" value={editItem.notes || ''} onChange={e => setEditItem({ ...editItem, notes: e.target.value })} className="input-base w-full min-h-[80px]" />
                </div>
                <div className="flex justify-end gap-2 pt-2">
                  <BoutonY2K variant="secondary" onClick={() => { setShowForm(false); setEditItem(null); }}>Annuler</BoutonY2K>
                  <BoutonY2K onClick={sauvegarderInvestisseur} disabled={saving} iconeGauche={<Save className="h-4 w-4" />}>
                    {saving ? 'Enregistrement…' : 'Enregistrer'}
                  </BoutonY2K>
                </div>
              </CardY2KContent>
            </CardY2K>
          </div>
        )}

        {/* Modal document */}
        {showDocForm && editDoc && (
          <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-foreground/40">
            <CardY2K className="max-w-lg w-full max-h-[90vh] overflow-y-auto" role="dialog" aria-modal="true" aria-labelledby="admin-levee-document-title">
              <CardY2KHeader>
                <div className="flex items-center justify-between w-full">
                  <CardY2KTitle id="admin-levee-document-title" className="text-sm">{editDoc.id ? 'Modifier' : 'Ajouter'} un document</CardY2KTitle>
                  <button aria-label="Fermer le formulaire document" onClick={() => { setShowDocForm(false); setEditDoc(null); }} className="text-muted-foreground hover:text-foreground"><X className="h-5 w-5" aria-hidden="true" /></button>
                </div>
              </CardY2KHeader>
              <CardY2KContent className="space-y-4">
                <div>
                  <Label htmlFor="admin-levee-document-titre">Titre</Label>
                  <Input id="admin-levee-document-titre" value={editDoc.titre || ''} onChange={e => setEditDoc({ ...editDoc, titre: e.target.value })} />
                </div>
                <div>
                  <Label htmlFor="admin-levee-document-categorie">Catégorie</Label>
                  <select id="admin-levee-document-categorie" value={editDoc.categorie || 'NOTE'} onChange={e => setEditDoc({ ...editDoc, categorie: e.target.value })} className="input-base w-full">
                    {CATEGORIES_DOC.map(c => <option key={c.value} value={c.value}>{c.label}</option>)}
                  </select>
                </div>
                <div>
                  <Label htmlFor="admin-levee-document-url">URL externe (Google Drive, Notion…)</Label>
                  <Input id="admin-levee-document-url" value={editDoc.url_externe || ''} onChange={e => setEditDoc({ ...editDoc, url_externe: e.target.value })} placeholder="https://..." />
                </div>
                <div>
                  <Label htmlFor="admin-levee-document-contenu">Notes / contenu</Label>
                  <textarea id="admin-levee-document-contenu" value={editDoc.contenu || ''} onChange={e => setEditDoc({ ...editDoc, contenu: e.target.value })} className="input-base w-full min-h-[120px]" />
                </div>
                <div className="flex justify-end gap-2 pt-2">
                  <BoutonY2K variant="secondary" onClick={() => { setShowDocForm(false); setEditDoc(null); }}>Annuler</BoutonY2K>
                  <BoutonY2K onClick={sauvegarderDoc} disabled={saving} iconeGauche={<Save className="h-4 w-4" />}>
                    {saving ? 'Enregistrement…' : 'Enregistrer'}
                  </BoutonY2K>
                </div>
              </CardY2KContent>
            </CardY2K>
          </div>
        )}
      </div>
    </LayoutAdmin>
  );
}
