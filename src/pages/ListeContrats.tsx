import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EtatVide } from '@/components/EtatVide';
import { BadgeStatut } from '@/components/BadgeStatut';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { FileText } from 'lucide-react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { UserRole } from '@/lib/types';

const FILTRES_STATUT = ['Tous', 'EN_ATTENTE_SIGNATURES', 'SIGNE_COMPLET', 'ANNULE'] as const;

export default function ListeContrats({ role }: { role: UserRole }) {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [contrats, setContrats] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [filtre, setFiltre] = useState('Tous');

  useEffect(() => {
    if (!user) return;
    const load = async () => {
      const col = role === 'SOIGNANT' ? 'soignant_id' : 'etablissement_id';
      const { data } = await supabase
        .from('contrats_mission')
        .select('*')
        .eq(col, user.id)
        .order('cree_le', { ascending: false });
      setContrats(data || []);
      setLoading(false);
    };
    load();
  }, [user, role]);

  const filtered = filtre === 'Tous' ? contrats : contrats.filter(c => c.statut === filtre);

  if (loading) return <LayoutApp role={role}><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role={role}>
      <h1 className="text-xl font-bold text-foreground mb-4">{role === 'SOIGNANT' ? 'Mes contrats' : 'Contrats'}</h1>

      <div className="flex gap-2 mb-4 flex-wrap">
        {FILTRES_STATUT.map(f => (
          <button key={f} onClick={() => setFiltre(f)} className={`badge-base transition-colors ${filtre === f ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground hover:bg-accent'}`}>
            {f === 'Tous' ? 'Tous' : f === 'EN_ATTENTE_SIGNATURES' ? 'En attente' : f === 'SIGNE_COMPLET' ? 'Signés' : 'Annulés'}
          </button>
        ))}
      </div>

      {filtered.length === 0 ? (
        <EtatVide icone={FileText} titre="Aucun contrat" sousTitre="Les contrats seront générés automatiquement lors de l'acceptation des missions." />
      ) : (
        <div className="space-y-3">
          {filtered.map((c: any) => (
            <div key={c.id} onClick={() => navigate(`/contrat/${c.id}`)} className="card-base hover:shadow-md cursor-pointer transition-all">
              <div className="flex items-center justify-between mb-2">
                <div className="flex items-center gap-2">
                  <FileText className="h-4 w-4 text-primary" />
                  <span className="text-sm font-semibold text-foreground">{c.numero_contrat}</span>
                </div>
                <span className={`badge-base text-[10px] ${c.statut === 'SIGNE_COMPLET' ? 'bg-success/10 text-success' : c.statut === 'ANNULE' ? 'bg-destructive/10 text-destructive' : 'bg-warning/10 text-warning'}`}>
                  {c.statut === 'SIGNE_COMPLET' ? '✅ Signé' : c.statut === 'ANNULE' ? '❌ Annulé' : '⏳ En attente'}
                </span>
              </div>
              <p className="text-xs text-muted-foreground">Type : {c.type_contrat}</p>
              <p className="text-xs text-muted-foreground">Créé le {format(new Date(c.cree_le), 'dd/MM/yyyy', { locale: fr })}</p>
              {!c.signature_soignant && role === 'SOIGNANT' && c.statut !== 'ANNULE' && (
                <p className="text-xs text-primary font-medium mt-1">✍️ Signer →</p>
              )}
              {!c.signature_etablissement && role === 'ETABLISSEMENT' && c.statut !== 'ANNULE' && (
                <p className="text-xs text-primary font-medium mt-1">✍️ Signer →</p>
              )}
            </div>
          ))}
        </div>
      )}
    </LayoutApp>
  );
}
