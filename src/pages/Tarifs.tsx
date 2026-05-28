import { usePageTitle } from '@/hooks/usePageTitle';
import React, { useEffect, useState } from 'react';
import { SEOHead } from '@/components/SEOHead';
import { useNavigate } from 'react-router-dom';
import { ArrowLeft } from 'lucide-react';
import { GrilleTarifaire } from '@/components/GrilleTarifaire';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';

export default function Tarifs() {
  usePageTitle('Tarifs');
  const navigate = useNavigate();
  const [paliers, setPaliers] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    supabase
      .from('paliers_commission')
      .select('id, nom, taux_commission, missions_min, missions_max, ordre')
      .eq('est_actif', true)
      .order('ordre', { ascending: true })
      .then(({ data, error }) => {
        if (!error) setPaliers(data ?? []);
        setLoading(false);
      });
  }, []);

  if (loading) return <ChargementPage />;

  return (
    <>
      <SEOHead
        title="Tarifs Jolene | Commission dégressive"
        description="Découvrez la grille tarifaire Jolene : commission dégressive à partir de 15%, facturation transparente, pas de frais cachés."
        url="https://jolene.app/tarifs"
      />
    <div className="min-h-[100dvh] bg-background">
      {/* Header */}
      <header className="border-b border-border bg-card py-4 px-4">
        <div className="max-w-6xl mx-auto flex items-center justify-between">
          <button onClick={() => navigate('/')} className="flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground transition-colors">
            <ArrowLeft className="h-4 w-4" /> Retour
          </button>
          <button onClick={() => navigate('/inscription/etablissement')} className="btn-primary text-sm">
            S'inscrire gratuitement
          </button>
        </div>
      </header>

      {/* Content */}
      <main className="max-w-6xl mx-auto px-4 py-16">
        <div className="text-center mb-12">
          <h1 className="text-3xl md:text-4xl font-black text-foreground mb-3">
            Nos tarifs — Transparence totale
          </h1>
          <p className="text-lg text-muted-foreground max-w-2xl mx-auto">
            Une commission dégressive qui récompense votre fidélité. Plus vous publiez, moins vous payez.
          </p>
        </div>

        <GrilleTarifaire paliers={paliers} />
      </main>

      {/* Footer */}
      <footer className="py-8 text-center text-sm text-muted-foreground border-t border-border bg-card">
        <p>© 2026 Jolene SAS — Conforme RGPD · Code du Travail</p>
      </footer>
    </div>
    </>
  );
}
