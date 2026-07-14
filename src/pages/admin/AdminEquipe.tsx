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
import { UserPlus, Trash2, Save, Calculator, CheckCircle2, ShieldAlert, X } from 'lucide-react';
import { toast } from 'sonner';
import {
  ADMIN_ACCESS_DESCRIPTIONS,
  ADMIN_ACCESS_GROUPS,
  aTousLesAccesAdmin,
} from '@/lib/adminAccess';

const fmt = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 }).format(v);

const COEFF_CHARGES_PATRONALES = 1.45;

interface Membre {
  id: string;
  nom: string;
  prenom: string;
  email: string;
  poste: string;
  salaire_brut_mensuel: number;
  date_embauche: string | null;
  acces_groupes: string[];
  actif: boolean;
  user_id: string | null;
}

interface FormMembre extends Partial<Membre> {
  password?: string;
}

function emptyMembre(): FormMembre {
  return {
    nom: '',
    prenom: '',
    email: '',
    poste: '',
    salaire_brut_mensuel: 0,
    date_embauche: null,
    acces_groupes: [...ADMIN_ACCESS_GROUPS],
    actif: true,
    password: '',
  };
}

export default function AdminEquipe() {
  usePageTitle('Équipe');
  const [loading, setLoading] = useState(true);
  const [membres, setMembres] = useState<Membre[]>([]);
  const [showForm, setShowForm] = useState(false);
  const [editMembre, setEditMembre] = useState<FormMembre | null>(null);
  const [saving, setSaving] = useState(false);

  const charger = async () => {
    setLoading(true);
    const { data } = await supabase.from('equipe_admin' as any).select('*').order('date_embauche', { ascending: true });
    setMembres((data as any[]) || []);
    setLoading(false);
  };

  useEffect(() => { charger(); }, []);

  useEffect(() => {
    if (!showForm) return;
    const fermerAvecEchap = (event: KeyboardEvent) => {
      if (event.key !== 'Escape' || saving) return;
      setShowForm(false);
      setEditMembre(null);
    };
    document.addEventListener('keydown', fermerAvecEchap);
    return () => document.removeEventListener('keydown', fermerAvecEchap);
  }, [showForm, saving]);

  const coutTotal = useMemo(() => {
    const brut = membres.filter(m => m.actif).reduce((s, m) => s + (Number(m.salaire_brut_mensuel) || 0), 0);
    return { brut, charges: brut * COEFF_CHARGES_PATRONALES, annuel: brut * COEFF_CHARGES_PATRONALES * 12 };
  }, [membres]);

  const ouvrirFormulaire = (m?: Membre) => {
    setEditMembre(m ? { ...m, password: '' } : emptyMembre());
    setShowForm(true);
  };

  const sauvegarder = async () => {
    if (!editMembre) return;
    if (!editMembre.nom?.trim() || !editMembre.prenom?.trim() || !editMembre.email?.trim()) {
      toast.error('Nom, prénom et email sont obligatoires.');
      return;
    }
    setSaving(true);

    let err;
    if (editMembre.id) {
      // Mise à jour d'un membre existant
      const payload = {
        nom: editMembre.nom!.trim(),
        prenom: editMembre.prenom!.trim(),
        email: editMembre.email!.trim(),
        poste: editMembre.poste || 'Opérations',
        salaire_brut_mensuel: Number(editMembre.salaire_brut_mensuel) || 0,
        date_embauche: editMembre.date_embauche || null,
        // Au lancement, l'accès partiel est désactivé : une mise à jour
        // explicite attribue les huit périmètres canoniques.
        acces_groupes: [...ADMIN_ACCESS_GROUPS],
        actif: editMembre.actif ?? true,
        maj_le: new Date().toISOString(),
      };
      ({ error: err } = await supabase.from('equipe_admin' as any).update(payload as any).eq('id', editMembre.id));
    } else {
      // Création : compte auth + equipe_admin via RPC serveur (transaction atomique)
      if (!editMembre.password || editMembre.password.length < 8) {
        toast.error('Mot de passe requis (8 caractères minimum).');
        setSaving(false);
        return;
      }
      const { error: rpcErr } = await supabase.rpc('fn_admin_creer_compte_employe' as any, {
        p_email: editMembre.email!.trim(),
        p_password: editMembre.password,
        p_prenom: editMembre.prenom!.trim(),
        p_nom: editMembre.nom!.trim(),
        p_poste: editMembre.poste || 'Opérations',
        p_salaire_brut: Number(editMembre.salaire_brut_mensuel) || 0,
        p_acces_groupes: [...ADMIN_ACCESS_GROUPS],
      });
      err = rpcErr;
    }
    setSaving(false);
    if (err) {
      console.error('Erreur sauvegarde membre équipe :', err);
      toast.error("Une erreur est survenue lors de l'enregistrement. Veuillez réessayer.");
      return;
    }
    toast.success(editMembre.id ? 'Membre mis à jour.' : 'Compte et accès créés.');
    setShowForm(false);
    setEditMembre(null);
    charger();
  };

  const desactiver = async (id: string) => {
    const { error } = await supabase.from('equipe_admin' as any).update({ actif: false, maj_le: new Date().toISOString() } as any).eq('id', id);
    if (error) {
      console.error('Erreur désactivation membre équipe :', error);
      toast.error('Une erreur est survenue lors de la désactivation. Veuillez réessayer.');
      return;
    }
    toast.success('Membre désactivé.');
    charger();
  };

  if (loading) return <LayoutAdmin><ChargementAdmin titre="Gestion de l’équipe" /></LayoutAdmin>;

  return (
    <LayoutAdmin>
      <div className="space-y-6">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div>
            <h1 className="text-xl font-bold text-foreground">Gestion de l'équipe</h1>
            <p className="text-sm text-muted-foreground">{membres.filter(m => m.actif).length} membre{membres.filter(m => m.actif).length > 1 ? 's' : ''} actif{membres.filter(m => m.actif).length > 1 ? 's' : ''}</p>
          </div>
          <BoutonY2K onClick={() => ouvrirFormulaire()} iconeGauche={<UserPlus className="h-4 w-4" />}>
            Ajouter un membre
          </BoutonY2K>
        </div>

        {/* Simulateur coût équipe */}
        <CardY2K hoverLift={false}>
          <CardY2KHeader>
            <CardY2KTitle className="text-sm flex items-center gap-2">
              <Calculator className="h-4 w-4" /> Coût total de l'équipe
            </CardY2KTitle>
          </CardY2KHeader>
          <CardY2KContent>
            <div className="grid grid-cols-3 gap-4">
              <div className="rounded-lg border p-3">
                <p className="text-xs text-muted-foreground">Salaires bruts /mois</p>
                <p className="text-lg font-bold text-foreground">{fmt(coutTotal.brut)}</p>
              </div>
              <div className="rounded-lg border p-3">
                <p className="text-xs text-muted-foreground">Coût total /mois</p>
                <p className="text-lg font-bold text-foreground">{fmt(coutTotal.charges)}</p>
                <p className="text-[10px] text-muted-foreground">×{COEFF_CHARGES_PATRONALES} charges patronales</p>
              </div>
              <div className="rounded-lg border p-3">
                <p className="text-xs text-muted-foreground">Coût annuel</p>
                <p className="text-lg font-bold text-foreground">{fmt(coutTotal.annuel)}</p>
              </div>
            </div>
          </CardY2KContent>
        </CardY2K>

        {/* Liste des membres */}
        <div className="space-y-3">
          {membres.map(m => (
            <CardY2K key={m.id} hoverLift={false} className={!m.actif ? 'opacity-50' : ''}>
              <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 p-4">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <p className="font-semibold text-foreground">{m.prenom} {m.nom}</p>
                    <BadgeY2K variant={m.actif ? 'success' : 'error'}>{m.actif ? 'Actif' : 'Désactivé'}</BadgeY2K>
                    {m.actif && !aTousLesAccesAdmin(m.acces_groupes) && (
                      <BadgeY2K variant="error">Bloqué au lancement</BadgeY2K>
                    )}
                  </div>
                  <p className="text-sm text-muted-foreground">{m.poste} · {m.email}</p>
                  {m.salaire_brut_mensuel > 0 && (
                    <p className="text-xs text-muted-foreground">
                      {fmt(m.salaire_brut_mensuel)} brut/mois → {fmt(m.salaire_brut_mensuel * COEFF_CHARGES_PATRONALES)} coût total
                    </p>
                  )}
                  <div className="flex flex-wrap gap-1 mt-1">
                    {(m.acces_groupes || []).map(g => (
                      <BadgeY2K key={g} variant="info" className="text-[10px]">{g}</BadgeY2K>
                    ))}
                  </div>
                </div>
                <div className="flex gap-2 shrink-0">
                  <BoutonY2K variant="secondary" size="sm" onClick={() => ouvrirFormulaire(m)}>Modifier</BoutonY2K>
                  {m.actif && !m.user_id?.startsWith('09e82688') && (
                    <BoutonY2K variant="destructive" size="sm" onClick={() => desactiver(m.id)} iconeGauche={<Trash2 className="h-3 w-3" />}>
                      Désactiver
                    </BoutonY2K>
                  )}
                </div>
              </div>
            </CardY2K>
          ))}
        </div>

        {/* Formulaire modal inline */}
        {showForm && editMembre && (
          <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-foreground/40">
            <CardY2K className="max-w-lg w-full max-h-[90vh] overflow-y-auto" role="dialog" aria-modal="true" aria-labelledby="admin-equipe-dialog-title">
              <CardY2KHeader>
                <div className="flex items-center justify-between w-full">
                  <CardY2KTitle id="admin-equipe-dialog-title" className="text-sm">{editMembre.id ? 'Modifier' : 'Ajouter'} un membre</CardY2KTitle>
                  <button aria-label="Fermer le formulaire du membre" onClick={() => { setShowForm(false); setEditMembre(null); }} className="text-muted-foreground hover:text-foreground">
                    <X className="h-5 w-5" aria-hidden="true" />
                  </button>
                </div>
              </CardY2KHeader>
              <CardY2KContent className="space-y-4">
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <Label htmlFor="admin-equipe-prenom">Prénom</Label>
                    <Input id="admin-equipe-prenom" value={editMembre.prenom || ''} onChange={e => setEditMembre({ ...editMembre, prenom: e.target.value })} />
                  </div>
                  <div>
                    <Label htmlFor="admin-equipe-nom">Nom</Label>
                    <Input id="admin-equipe-nom" value={editMembre.nom || ''} onChange={e => setEditMembre({ ...editMembre, nom: e.target.value })} />
                  </div>
                </div>
                <div>
                  <Label htmlFor="admin-equipe-email">Email</Label>
                  <Input id="admin-equipe-email" type="email" value={editMembre.email || ''} onChange={e => setEditMembre({ ...editMembre, email: e.target.value })} />
                </div>
                {!editMembre.id && (
                  <div>
                    <Label htmlFor="admin-equipe-password">Mot de passe (8 caractères min.)</Label>
                    <Input id="admin-equipe-password" type="password" value={editMembre.password || ''} onChange={e => setEditMembre({ ...editMembre, password: e.target.value })} placeholder="••••••••" autoComplete="new-password" />
                    <p className="text-[10px] text-muted-foreground mt-1">Crée un compte admin avec ce mot de passe. L'employé pourra le changer ensuite.</p>
                  </div>
                )}
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <Label htmlFor="admin-equipe-poste">Poste</Label>
                    <Input id="admin-equipe-poste" value={editMembre.poste || ''} onChange={e => setEditMembre({ ...editMembre, poste: e.target.value })} />
                  </div>
                  <div>
                    <Label htmlFor="admin-equipe-salaire">Salaire brut /mois (€)</Label>
                    <Input id="admin-equipe-salaire" type="number" value={editMembre.salaire_brut_mensuel || ''} onChange={e => setEditMembre({ ...editMembre, salaire_brut_mensuel: Number(e.target.value) })} />
                  </div>
                </div>
                <div>
                  <Label htmlFor="admin-equipe-date-embauche">Date d'embauche</Label>
                  <Input id="admin-equipe-date-embauche" type="date" value={editMembre.date_embauche || ''} onChange={e => setEditMembre({ ...editMembre, date_embauche: e.target.value })} />
                </div>
                <div>
                  <Label>Périmètres d'accès</Label>
                  <div className="mt-2 flex gap-2 rounded-lg border border-amber-500/30 bg-amber-500/10 p-3 text-xs text-foreground" role="status">
                    <ShieldAlert className="mt-0.5 h-4 w-4 shrink-0 text-amber-700 dark:text-amber-300" aria-hidden="true" />
                    <p>
                      L'accès partiel est temporairement désactivé pour le lancement. Chaque compte administrateur reçoit les huit périmètres. Les comptes historiques incomplets restent bloqués tant qu'ils ne sont pas explicitement enregistrés avec cet accès complet.
                    </p>
                  </div>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 mt-2">
                    {ADMIN_ACCESS_DESCRIPTIONS.map(({ cle, description }) => (
                      <div key={cle} className="flex items-start gap-2 text-sm">
                        <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-success" aria-hidden="true" />
                        <span>
                          {cle}
                          <span className="block text-xs text-muted-foreground">{description}</span>
                        </span>
                      </div>
                    ))}
                  </div>
                </div>
                <div className="flex justify-end gap-2 pt-2">
                  <BoutonY2K variant="secondary" onClick={() => { setShowForm(false); setEditMembre(null); }}>Annuler</BoutonY2K>
                  <BoutonY2K onClick={sauvegarder} disabled={saving} iconeGauche={<Save className="h-4 w-4" />}>
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
