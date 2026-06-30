/**
 * PageRecherchesSauvegardees — gestion centralisée des filtres sauvegardés.
 *
 * Routes :
 *   /soignant/parametres/recherches-sauvegardees     (audience SOIGNANT)
 *   /etablissement/parametres/recherches-sauvegardees (audience ETAB)
 *
 * Pour chaque filtre : renommer, toggle alerte + fréquence, supprimer,
 * et "Aller à la recherche" qui réapplique les filtres dans la page de
 * recherche correspondante.
 *
 * J2.3.C.2
 */

import React, { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Bell, BellOff, Trash2, Edit2, Search, ChevronRight } from 'lucide-react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import {
  DialogResponsive,
  DialogResponsiveContent,
  DialogResponsiveHeader,
  DialogResponsiveTitle,
  DialogResponsiveDescription,
  DialogResponsiveBody,
  DialogResponsiveFooter,
} from '@/components/ui/DialogResponsive';
import { logger } from '@/lib/logger';
import type { FiltreSauvegarde, FrequenceAlerte } from '@/components/FiltresSauvegardes';
import { usePageTitle } from '@/hooks/usePageTitle';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface Props {
  role: 'SOIGNANT' | 'ADMIN_ETABLISSEMENT';
}

const FREQUENCE_LABELS: Record<FrequenceAlerte, string> = {
  IMMEDIATE: 'Immédiat (vérification horaire)',
  QUOTIDIENNE: 'Quotidien',
  HEBDOMADAIRE: 'Hebdomadaire',
};

export default function PageRecherchesSauvegardees({ role }: Props) {
  usePageTitle('Mes recherches sauvegardées');
  const navigate = useNavigate();
  const { user } = useAuth();
  const audience = role === 'SOIGNANT' ? 'SOIGNANT_RECHERCHE_MISSIONS' : 'ETAB_RECHERCHE_SOIGNANTS';
  const [list, setList] = useState<FiltreSauvegarde[]>([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState<FiltreSauvegarde | null>(null);

  const reload = async () => {
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_lister_mes_filtres_sauvegardes', { p_audience: audience });
    if (error) {
      logger.error('[PageRecherchesSauvegardees] error', error);
      toast.error('Impossible de charger vos recherches');
    } else {
      setList((data as any) || []);
    }
    setLoading(false);
  };

  useEffect(() => { if (user) reload(); }, [user, audience]);

  const handleDelete = async (f: FiltreSauvegarde) => {
    if (!confirm(`Supprimer la recherche « ${f.nom} » ?`)) return;
    const { data, error } = await supabase.rpc('fn_supprimer_filtre_sauvegarde', { p_id: f.id });
    if (error || (data as any)?.error) {
      toast.error((data as any)?.error || 'Erreur suppression');
      return;
    }
    toast.success('Recherche supprimée');
    reload();
  };

  const handleToggleAlerte = async (f: FiltreSauvegarde) => {
    const { data, error } = await supabase.rpc('fn_modifier_filtre_sauvegarde', {
      p_id: f.id, p_alerte_active: !f.alerte_active,
    });
    if (error || (data as any)?.error) {
      toast.error((data as any)?.error || 'Erreur mise à jour');
      return;
    }
    toast.success(!f.alerte_active ? 'Alerte activée' : 'Alerte désactivée');
    reload();
  };

  const handleAllerRecherche = (f: FiltreSauvegarde) => {
    // On stocke les filtres dans sessionStorage pour que la page de recherche
    // les pré-applique au montage. Pattern simple et résilient cross-route.
    try {
      sessionStorage.setItem('jolene.filtres_a_appliquer', JSON.stringify({
        audience: f.audience,
        filtres: f.filtres,
        nom_source: f.nom,
      }));
    } catch (_e) { /* ignore */ }
    if (role === 'SOIGNANT') navigate('/soignant/recherche-missions');
    else navigate('/etablissement/tableau-de-bord'); // Pas de page recherche soignants étab — fallback dashboard
  };

  if (loading) return <LayoutApp role={role}><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role={role}>
      <div className="space-y-4 max-w-3xl">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-xl font-bold flex items-center gap-2">
              <Search className="h-5 w-5" /> Mes recherches sauvegardées
            </h1>
            <p className="text-sm text-gray-600 mt-1">
              {role === 'SOIGNANT'
                ? 'Sauvegardez vos critères de recherche missions et activez des alertes email.'
                : 'Sauvegardez vos critères de recherche soignants et activez des alertes email.'}
            </p>
          </div>
        </div>

        {list.length === 0 ? (
          <div className="card-base p-8 text-center">
            <Search className="h-10 w-10 mx-auto text-gray-300 mb-3" />
            <p className="text-gray-500 mb-4">Aucune recherche sauvegardée pour l'instant.</p>
            <BoutonY2K onClick={() => {
              if (role === 'SOIGNANT') navigate('/soignant/recherche-missions');
              else navigate('/etablissement/tableau-de-bord');
            }}>
              Créer une recherche
            </BoutonY2K>
          </div>
        ) : (
          <ul className="space-y-2">
            {list.map((f) => (
              <li key={f.id} className="border rounded-lg p-4 bg-white space-y-2 hover:bg-gray-50">
                <div className="flex items-start justify-between gap-3">
                  <div className="flex-1 min-w-0">
                    <h3 className="font-medium truncate">{f.nom}</h3>
                    <div className="text-xs text-gray-500 mt-1 flex flex-wrap gap-3">
                      <span>
                        {f.alerte_active
                          ? <>🔔 Alertes {FREQUENCE_LABELS[f.frequence_alerte].toLowerCase()}</>
                          : <>🔕 Alertes désactivées</>}
                      </span>
                      <span>•</span>
                      <span>Dernier check : {format(new Date(f.dernier_check_le), 'dd MMM HH:mm', { locale: fr })}</span>
                      {f.nb_resultats_dernier_check > 0 && (
                        <>
                          <span>•</span>
                          <span className="text-blue-600 font-medium">{f.nb_resultats_dernier_check} résultat{f.nb_resultats_dernier_check > 1 ? 's' : ''}</span>
                        </>
                      )}
                    </div>
                  </div>
                  <div className="flex items-center gap-1 shrink-0">
                    <BoutonY2K size="sm" variant="ghost" onClick={() => handleToggleAlerte(f)}
                      title={f.alerte_active ? 'Désactiver alertes' : 'Activer alertes'}>
                      {f.alerte_active
                        ? <Bell className="h-4 w-4 text-blue-600" />
                        : <BellOff className="h-4 w-4 text-gray-400" />}
                    </BoutonY2K>
                    <BoutonY2K size="sm" variant="ghost" onClick={() => setEditing(f)} title="Modifier">
                      <Edit2 className="h-4 w-4" />
                    </BoutonY2K>
                    <BoutonY2K size="sm" variant="ghost" onClick={() => handleDelete(f)} title="Supprimer">
                      <Trash2 className="h-4 w-4 text-red-500" />
                    </BoutonY2K>
                  </div>
                </div>
                <BoutonY2K size="sm" variant="secondary" className="w-full" onClick={() => handleAllerRecherche(f)} iconeDroite={<ChevronRight className="h-4 w-4" />}>
                  Aller à la recherche
                </BoutonY2K>
              </li>
            ))}
          </ul>
        )}

        <div className="card-base p-4 bg-blue-50 text-sm text-blue-900">
          <strong>Comment fonctionnent les alertes ?</strong><br />
          Les alertes sont envoyées par email selon la fréquence choisie :
          <ul className="list-disc pl-5 mt-2 space-y-1">
            <li><strong>Immédiat</strong> — vérification toutes les heures, latence max 1h.</li>
            <li><strong>Quotidien</strong> — résumé chaque matin (8h Paris).</li>
            <li><strong>Hebdomadaire</strong> — résumé chaque lundi matin.</li>
          </ul>
          <p className="mt-2">
            Vous pouvez désactiver toutes les alertes email globalement dans <a className="underline"
              href={role === 'SOIGNANT' ? '/soignant/parametres/notifications' : '/etablissement/parametres/notifications'}>
              Paramètres → Notifications
            </a>.
          </p>
        </div>
      </div>

      {/* Modal Modifier */}
      <ModalEditPage
        filtre={editing}
        onOpenChange={(o) => { if (!o) setEditing(null); }}
        onSaved={() => { reload(); setEditing(null); }}
      />
    </LayoutApp>
  );
}

function ModalEditPage({
  filtre, onOpenChange, onSaved,
}: {
  filtre: FiltreSauvegarde | null;
  onOpenChange: (o: boolean) => void;
  onSaved: () => void;
}) {
  const [nom, setNom] = useState('');
  const [alerteActive, setAlerteActive] = useState(false);
  const [frequence, setFrequence] = useState<FrequenceAlerte>('QUOTIDIENNE');
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (filtre) {
      setNom(filtre.nom);
      setAlerteActive(filtre.alerte_active);
      setFrequence(filtre.frequence_alerte);
    }
  }, [filtre]);

  if (!filtre) return null;

  const submit = async () => {
    if (nom.trim().length === 0) { toast.error('Nom requis'); return; }
    setSubmitting(true);
    const { data, error } = await supabase.rpc('fn_modifier_filtre_sauvegarde', {
      p_id: filtre.id, p_nom: nom.trim(),
      p_alerte_active: alerteActive, p_frequence_alerte: frequence,
    });
    setSubmitting(false);
    if (error || (data as any)?.error) {
      toast.error((data as any)?.error || 'Erreur mise à jour');
      return;
    }
    toast.success('Recherche mise à jour');
    onSaved();
  };

  return (
    <DialogResponsive open={!!filtre} onOpenChange={onOpenChange}>
      <DialogResponsiveContent>
        <DialogResponsiveHeader>
          <DialogResponsiveTitle>Modifier la recherche</DialogResponsiveTitle>
          <DialogResponsiveDescription>
            Renommer + changer les préférences d'alertes. Pour modifier les
            critères de recherche, supprimez celle-ci et créez-en une nouvelle
            depuis la page de recherche.
          </DialogResponsiveDescription>
        </DialogResponsiveHeader>
        <DialogResponsiveBody className="space-y-4">
          <div>
            <Label htmlFor="nom-edit">Nom</Label>
            <Input id="nom-edit" maxLength={100} value={nom} onChange={(e) => setNom(e.target.value)} />
          </div>
          <div className="flex items-center justify-between">
            <Label htmlFor="alerte-edit">Alertes email</Label>
            <Switch id="alerte-edit" checked={alerteActive} onCheckedChange={setAlerteActive} />
          </div>
          {alerteActive && (
            <div>
              <Label htmlFor="freq-edit">Fréquence</Label>
              <Select value={frequence} onValueChange={(v) => setFrequence(v as FrequenceAlerte)}>
                <SelectTrigger id="freq-edit"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {(Object.keys(FREQUENCE_LABELS) as FrequenceAlerte[]).map((k) => (
                    <SelectItem key={k} value={k}>{FREQUENCE_LABELS[k]}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}
        </DialogResponsiveBody>
        <DialogResponsiveFooter>
          <BoutonY2K variant="secondary" onClick={() => onOpenChange(false)} disabled={submitting}>Annuler</BoutonY2K>
          <BoutonY2K onClick={submit} disabled={submitting}>
            {submitting ? 'Enregistrement…' : 'Enregistrer'}
          </BoutonY2K>
        </DialogResponsiveFooter>
      </DialogResponsiveContent>
    </DialogResponsive>
  );
}
