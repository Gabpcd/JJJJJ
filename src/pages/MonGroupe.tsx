import { usePageTitle } from '@/hooks/usePageTitle';
import React, { useState, useEffect } from 'react';
import { Building2, Mail } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { getLabelTypeEtablissement } from '@/lib/constantes';
import { toast } from 'sonner';

export default function MonGroupe() {
  usePageTitle('Mon Groupe');
  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <MonGroupeContent />
    </LayoutApp>
  );
}

export function MonGroupeContent() {
  const { user } = useAuth();
  const [etab, setEtab] = useState<any>(null);
  const [groupe, setGroupe] = useState<any>(null);
  const [etablissements, setEtablissements] = useState<any[]>([]);
  const [filtreDepartement, setFiltreDepartement] = useState('');
  const [filtreType, setFiltreType] = useState('');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!user) return;
    const load = async () => {
      const { data: e, error: errE } = await supabase
        .from('etablissements')
        .select('groupe_sante_id, groupes_sante(id, nom, siren, raison_sociale_facturation, remise_groupe_pourcent, formule_abonnement)')
        .eq('id', user.id)
        .single();
      if (errE) { toast.error('Impossible de charger les informations du groupe.'); setLoading(false); return; }

      setEtab(e);

      if (e?.groupe_sante_id) {
        setGroupe((e as any).groupes_sante);
        const { data: etabs, error: errEtabs } = await supabase
          .from('etablissements')
          .select('id, nom, adresse_ville, adresse_departement, type, finess')
          .eq('groupe_sante_id', e.groupe_sante_id)
          .is('supprime_le', null)
          .order('adresse_departement', { ascending: true });
        if (errEtabs) toast.error('Erreur lors du chargement des établissements du groupe.');
        setEtablissements(etabs || []);
      }
      setLoading(false);
    };
    load();
  }, [user]);

  if (loading) return <ChargementPage />;

  if (!etab?.groupe_sante_id || !groupe) {
    return (
      <div className="flex flex-col items-center justify-center py-16 text-center">
        <Building2 className="h-16 w-16 text-primary/30 mb-4" />
        <h2 className="text-lg font-bold text-foreground mb-2">Établissement indépendant</h2>
        <p className="text-sm text-muted-foreground max-w-md mb-4">
          Votre établissement n'appartient à aucun groupe de santé.
          Contactez-nous pour rattacher votre établissement à un groupe existant.
        </p>
        <BoutonY2K onClick={() => window.location.href = 'mailto:contact@jolene.app?subject=Rejoindre un groupe de santé'} iconeGauche={<Mail className="h-4 w-4" />}>
          Contacter Jolene
        </BoutonY2K>
      </div>
    );
  }

  const departements = [...new Set(etablissements.map(e => e.adresse_departement).filter(Boolean))].sort();
  const types = [...new Set(etablissements.map(e => e.type).filter(Boolean))].sort();

  const etabsFiltres = etablissements.filter(e => {
    if (filtreDepartement && e.adresse_departement !== filtreDepartement) return false;
    if (filtreType && e.type !== filtreType) return false;
    return true;
  });

  return (
    <>
      <div className="card-base bg-gradient-to-r from-primary/5 to-info/5 mb-6">
        <h1 className="text-2xl font-bold text-foreground">{groupe.nom}</h1>
        <div className="flex items-center gap-3 mt-2 flex-wrap text-sm text-muted-foreground">
          {groupe.siren && <span>SIREN : {groupe.siren}</span>}
          {groupe.formule_abonnement && (
            <span className="badge-base bg-primary/10 text-primary">{groupe.formule_abonnement}</span>
          )}
          {groupe.remise_groupe_pourcent > 0 && (
            <span className="badge-base bg-success/10 text-success">Tarif négocié : -{groupe.remise_groupe_pourcent}%</span>
          )}
        </div>
      </div>

      <div className="flex gap-2 flex-wrap mb-4">
        <select value={filtreDepartement} onChange={(e) => setFiltreDepartement(e.target.value)} className="input-base text-sm flex-1 min-w-0 sm:min-w-[150px]">
          <option value="">Tous les départements</option>
          {departements.map(d => <option key={d} value={d}>{d}</option>)}
        </select>
        <select value={filtreType} onChange={(e) => setFiltreType(e.target.value)} className="input-base text-sm flex-1 min-w-0 sm:min-w-[150px]">
          <option value="">Tous les types</option>
          {types.map(t => <option key={t} value={t}>{getLabelTypeEtablissement(t)}</option>)}
        </select>
      </div>

      <h2 className="text-lg font-bold text-foreground mb-3">Établissements du groupe ({etabsFiltres.length})</h2>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {etabsFiltres.map(e => (
          <div key={e.id} className="card-base">
            <div className="flex items-start justify-between">
              <div>
                <h3 className="font-semibold text-foreground">{e.nom}</h3>
                <p className="text-sm text-muted-foreground">{e.adresse_ville}{e.adresse_departement ? ` (${e.adresse_departement})` : ''}</p>
                <p className="text-xs text-muted-foreground mt-1">{getLabelTypeEtablissement(e.type)}{e.finess ? ` · FINESS: ${e.finess}` : ''}</p>
              </div>
              {e.id === user?.id && (
                <span className="badge-base bg-primary/10 text-primary text-[10px]">📍 Vous êtes ici</span>
              )}
            </div>
          </div>
        ))}
      </div>
    </>
  );
}
