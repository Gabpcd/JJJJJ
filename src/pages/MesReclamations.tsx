import { useState, useEffect, useCallback } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { MessageCircle, Plus, Clock, CheckCircle, AlertCircle, Loader2, Send } from 'lucide-react';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Input } from '@/components/ui/input';
import {
  DialogResponsive,
  DialogResponsiveContent,
  DialogResponsiveHeader,
  DialogResponsiveTitle,
  DialogResponsiveBody,
  DialogResponsiveFooter,
} from '@/components/ui/DialogResponsive';

const CATEGORIES = [
  { value: 'MISSION', label: 'Mission (annulation, litige, problème)' },
  { value: 'PAIEMENT', label: 'Paiement (retard, montant incorrect)' },
  { value: 'COMPORTEMENT', label: 'Comportement (soignant ou établissement)' },
  { value: 'TECHNIQUE', label: 'Problème technique (bug, accès)' },
  { value: 'AUTRE', label: 'Autre' },
];

const STATUT_CONFIG: Record<string, { label: string; color: string; icon: typeof Clock }> = {
  EN_ATTENTE: { label: 'En attente', color: 'text-warning', icon: Clock },
  EN_COURS: { label: 'En cours de traitement', color: 'text-primary', icon: AlertCircle },
  RESOLUE: { label: 'Résolue', color: 'text-success', icon: CheckCircle },
  FERMEE: { label: 'Fermée', color: 'text-muted-foreground', icon: CheckCircle },
};

interface Reclamation {
  id: string;
  categorie: string;
  sujet: string;
  details: string;
  statut: string;
  reponse_admin: string | null;
  cree_le: string;
  traite_le: string | null;
}

export default function MesReclamations({ role }: { role: 'SOIGNANT' | 'ADMIN_ETABLISSEMENT' }) {
  usePageTitle('Mes réclamations');
  return (
    <LayoutApp role={role}>
      <ReclamationsContent role={role} />
    </LayoutApp>
  );
}

/**
 * Contenu "Réclamations" sans LayoutApp — réutilisable dans les Tabs
 * de LitigesEtablissement (fusion B.1).
 */
export function ReclamationsContent({ role: _role }: { role: 'SOIGNANT' | 'ADMIN_ETABLISSEMENT' }) {
  const { user } = useAuth();
  const [loading, setLoading] = useState(true);
  const [reclamations, setReclamations] = useState<Reclamation[]>([]);
  const [showForm, setShowForm] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  // Form state
  const [categorie, setCategorie] = useState('MISSION');
  const [sujet, setSujet] = useState('');
  const [details, setDetails] = useState('');

  const charger = useCallback(async () => {
    if (!user) return;
    setLoading(true);
    const { data } = await supabase
      .from('reclamations' as any)
      .select('id, categorie, sujet, details, statut, reponse_admin, cree_le, traite_le')
      .eq('utilisateur_id', user.id)
      .order('cree_le', { ascending: false });
    setReclamations((data as any[]) || []);
    setLoading(false);
  }, [user]);

  useEffect(() => { charger(); }, [charger]);

  const soumettre = async () => {
    if (!sujet.trim() || !details.trim()) {
      toast.error('Veuillez remplir le sujet et les détails');
      return;
    }
    setSubmitting(true);
    const { data, error } = await supabase.rpc('fn_soumettre_reclamation' as any, {
      p_categorie: categorie,
      p_sujet: sujet.trim(),
      p_details: details.trim(),
    });
    if (error || (data as any)?.error) {
      toast.error((data as any)?.error || 'Erreur lors de la soumission');
    } else {
      toast.success('Réclamation envoyée — nous reviendrons vers vous rapidement');
      setShowForm(false);
      setSujet('');
      setDetails('');
      setCategorie('MISSION');
      charger();
    }
    setSubmitting(false);
  };

  if (loading) return <ChargementPage />;

  return (
    <>
      <div className="max-w-3xl mx-auto space-y-5">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="h-10 w-10 rounded-xl bg-primary/10 flex items-center justify-center">
              <MessageCircle className="h-5 w-5 text-primary" />
            </div>
            <div>
              <h1 className="text-xl font-bold text-foreground">Mes réclamations</h1>
              <p className="text-sm text-muted-foreground">Signalez un problème ou suivez vos demandes</p>
            </div>
          </div>
          <BoutonY2K onClick={() => setShowForm(true)} className="gap-2">
            <Plus className="h-4 w-4" /> Nouvelle réclamation
          </BoutonY2K>
        </div>

        {reclamations.length === 0 ? (
          <div className="card-base p-8 text-center">
            <MessageCircle className="h-10 w-10 text-muted-foreground mx-auto mb-3" />
            <p className="text-sm text-muted-foreground mb-4">Aucune réclamation pour le moment.</p>
            <BoutonY2K onClick={() => setShowForm(true)} variant="secondary" className="gap-2">
              <Plus className="h-4 w-4" /> Signaler un problème
            </BoutonY2K>
          </div>
        ) : (
          <div className="space-y-3">
            {reclamations.map((r) => {
              const statut = STATUT_CONFIG[r.statut] || STATUT_CONFIG.EN_ATTENTE;
              const StatutIcon = statut.icon;
              const catLabel = CATEGORIES.find(c => c.value === r.categorie)?.label || r.categorie;
              return (
                <div key={r.id} className="card-base p-4 space-y-2">
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex-1 min-w-0">
                      <p className="font-semibold text-foreground truncate" title={r.sujet}>{r.sujet}</p>
                      <p className="text-xs text-muted-foreground">{catLabel} · {format(new Date(r.cree_le), "d MMM yyyy 'à' HH:mm", { locale: fr })}</p>
                    </div>
                    <div className={`flex items-center gap-1 text-xs font-medium ${statut.color} whitespace-nowrap`}>
                      <StatutIcon className="h-3.5 w-3.5" />
                      {statut.label}
                    </div>
                  </div>
                  <p className="text-sm text-muted-foreground line-clamp-2">{r.details}</p>
                  {r.reponse_admin && (
                    <div className="mt-2 p-3 rounded-lg bg-primary/5 border border-primary/20">
                      <p className="text-xs font-medium text-primary mb-1">Réponse Jolene :</p>
                      <p className="text-sm text-foreground">{r.reponse_admin}</p>
                      {r.traite_le && (
                        <p className="text-[10px] text-muted-foreground mt-1">
                          {format(new Date(r.traite_le), "d MMM yyyy 'à' HH:mm", { locale: fr })}
                        </p>
                      )}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>

      {/* ── Modal nouvelle réclamation ── */}
      <DialogResponsive open={showForm} onOpenChange={setShowForm}>
        <DialogResponsiveContent>
          <DialogResponsiveHeader>
            <DialogResponsiveTitle>Nouvelle réclamation</DialogResponsiveTitle>
          </DialogResponsiveHeader>
          <DialogResponsiveBody className="space-y-4">
            <div>
              <label className="text-sm font-medium text-foreground">Catégorie</label>
              <select
                value={categorie}
                onChange={(e) => setCategorie(e.target.value)}
                className="input-base w-full mt-1"
              >
                {CATEGORIES.map(c => (
                  <option key={c.value} value={c.value}>{c.label}</option>
                ))}
              </select>
            </div>
            <div>
              <label className="text-sm font-medium text-foreground">Sujet</label>
              <Input
                value={sujet}
                onChange={(e) => setSujet(e.target.value)}
                placeholder="Décrivez brièvement le problème"
                className="mt-1"
              />
            </div>
            <div>
              <label className="text-sm font-medium text-foreground">Détails</label>
              <textarea
                value={details}
                onChange={(e) => setDetails(e.target.value)}
                placeholder="Expliquez la situation en détail : dates, montants, personnes concernées..."
                rows={5}
                className="input-base w-full mt-1 resize-none"
              />
            </div>
          </DialogResponsiveBody>
          <DialogResponsiveFooter>
            <BoutonY2K variant="secondary" onClick={() => setShowForm(false)}>Annuler</BoutonY2K>
            <BoutonY2K onClick={soumettre} disabled={submitting || !sujet.trim() || !details.trim()} className="gap-2">
              {submitting ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
              Envoyer
            </BoutonY2K>
          </DialogResponsiveFooter>
        </DialogResponsiveContent>
      </DialogResponsive>
    </>
  );
}
