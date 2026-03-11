import { useState, useEffect, useMemo } from 'react';
import { useSearchParams, useNavigate } from 'react-router-dom';
import { Printer, ArrowLeft } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { PROFESSIONS } from '@/lib/constantes';
import { ENTREPRISE } from '@/constantes/entreprise';
import { ChargementPage } from '@/components/ChargementPage';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

function getLabelProfession(code: string) {
  return PROFESSIONS.find(p => p.valeur === code)?.label || code;
}

export default function AttestationHeures() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const debut = searchParams.get('debut') || '';
  const fin = searchParams.get('fin') || '';

  const [soignant, setSoignant] = useState<any>(null);
  const [missions, setMissions] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!user || !debut || !fin) return;
    const load = async () => {
      const [{ data: sg }, { data: ms }] = await Promise.all([
        supabase.from('soignants').select('prenom, nom, profession, numero_rpps, numero_adeli').eq('id', user.id).single(),
        supabase.from('missions')
          .select('intitule, service, debut_le, fin_le, duree_heures, taux_horaire_base, net_a_payer, statut, etablissements(nom, adresse_ville, finess)')
          .eq('soignant_assigne_id', user.id)
          .eq('statut', 'TERMINEE')
          .gte('debut_le', debut)
          .lte('debut_le', fin)
          .order('debut_le', { ascending: true }),
      ]);
      setSoignant(sg);
      setMissions((ms as any[]) || []);

      // Audit HDS
      await supabase.rpc('fn_ecrire_audit', {
        p_acteur_id: user.id,
        p_type_acteur: 'SOIGNANT',
        p_action: 'DONNEES_PERSO_EXPORT',
        p_type_ressource: 'soignant',
        p_id_ressource: user.id,
        p_cle_s3: null,
        p_details: {
          type: 'attestation_heures',
          periode: { debut, fin },
          nb_missions: (ms as any[])?.length || 0,
          total_heures: (ms as any[])?.reduce((s: number, m: any) => s + (m.duree_heures || 0), 0) || 0,
        },
        p_ip: null,
        p_navigateur: navigator.userAgent,
      });

      setLoading(false);
    };
    load();
  }, [user, debut, fin]);

  const stats = useMemo(() => {
    const totalHeures = missions.reduce((s, m) => s + (m.duree_heures || 0), 0);
    const etabs = new Set(missions.map(m => m.etablissements?.nom).filter(Boolean));
    return { totalHeures, nbEtabs: etabs.size };
  }, [missions]);

  const identifiant = `ATT-${user?.id?.substring(0, 8) || 'XXXX'}-${Date.now()}`;

  if (loading) return <div className="flex items-center justify-center min-h-screen"><ChargementPage /></div>;

  return (
    <div className="min-h-screen bg-white">
      {/* Toolbar — hidden on print */}
      <div className="no-print sticky top-0 z-50 bg-white border-b border-gray-200 px-4 py-3 flex items-center gap-3">
        <button onClick={() => navigate('/soignant/mes-gains')} className="flex items-center gap-1 text-sm text-primary font-medium hover:underline">
          <ArrowLeft className="h-4 w-4" /> Retour à mes gains
        </button>
        <div className="flex-1" />
        <button onClick={() => window.print()} className="flex items-center gap-2 bg-primary text-primary-foreground rounded-xl px-5 py-2.5 font-semibold text-sm hover:opacity-90 transition-opacity">
          <Printer className="h-4 w-4" /> Imprimer / Enregistrer en PDF
        </button>
      </div>

      {/* Attestation content */}
      <div className="attestation max-w-3xl mx-auto p-8 md:p-12">
        {/* Header */}
        <div className="text-center mb-8">
          <p className="text-2xl font-bold mb-1">❤️ Soin Direct</p>
          <h1 className="text-xl font-bold uppercase tracking-wide">Attestation d'heures travaillées</h1>
        </div>

        <hr className="border-gray-300 mb-6" />

        {/* Soignant */}
        <div className="mb-6">
          <h2 className="font-bold text-sm uppercase tracking-wide mb-2">Soignant</h2>
          <table className="text-sm">
            <tbody>
              <tr><td className="pr-4 text-gray-600 py-0.5">Nom :</td><td className="font-medium">{soignant?.prenom} {soignant?.nom}</td></tr>
              <tr><td className="pr-4 text-gray-600 py-0.5">Profession :</td><td>{getLabelProfession(soignant?.profession)}</td></tr>
              {soignant?.numero_rpps && <tr><td className="pr-4 text-gray-600 py-0.5">N° RPPS :</td><td>{soignant.numero_rpps}</td></tr>}
              {soignant?.numero_adeli && <tr><td className="pr-4 text-gray-600 py-0.5">N° ADELI :</td><td>{soignant.numero_adeli}</td></tr>}
            </tbody>
          </table>
        </div>

        {/* Période */}
        <div className="mb-6">
          <h2 className="font-bold text-sm uppercase tracking-wide mb-2">Période</h2>
          <p className="text-sm">Du {format(new Date(debut), 'dd/MM/yyyy')} au {format(new Date(fin), 'dd/MM/yyyy')}</p>
        </div>

        <hr className="border-gray-300 mb-6" />

        {/* Détail des missions */}
        <div className="mb-6">
          <h2 className="font-bold text-sm uppercase tracking-wide mb-3">Détail des missions</h2>
          <table className="w-full border-collapse text-sm">
            <thead>
              <tr className="bg-gray-100">
                <th className="border border-gray-300 px-2 py-1.5 text-left font-semibold">Date</th>
                <th className="border border-gray-300 px-2 py-1.5 text-left font-semibold">Établissement</th>
                <th className="border border-gray-300 px-2 py-1.5 text-left font-semibold">FINESS</th>
                <th className="border border-gray-300 px-2 py-1.5 text-left font-semibold">Service</th>
                <th className="border border-gray-300 px-2 py-1.5 text-right font-semibold">Durée</th>
              </tr>
            </thead>
            <tbody>
              {missions.map((m, i) => (
                <tr key={i} className={i % 2 === 0 ? '' : 'bg-gray-50'}>
                  <td className="border border-gray-300 px-2 py-1">{format(new Date(m.debut_le), 'dd/MM/yyyy')}</td>
                  <td className="border border-gray-300 px-2 py-1">{m.etablissements?.nom || '—'}</td>
                  <td className="border border-gray-300 px-2 py-1">{m.etablissements?.finess || '—'}</td>
                  <td className="border border-gray-300 px-2 py-1">{m.service || '—'}</td>
                  <td className="border border-gray-300 px-2 py-1 text-right">{m.duree_heures || 0}h</td>
                </tr>
              ))}
              <tr className="font-bold bg-gray-100">
                <td className="border border-gray-300 px-2 py-1.5" colSpan={4}>TOTAL</td>
                <td className="border border-gray-300 px-2 py-1.5 text-right">{stats.totalHeures}h</td>
              </tr>
            </tbody>
          </table>
        </div>

        <hr className="border-gray-300 mb-6" />

        {/* Synthèse */}
        <div className="mb-6">
          <h2 className="font-bold text-sm uppercase tracking-wide mb-2">Synthèse</h2>
          <ul className="text-sm space-y-1">
            <li>Nombre de missions terminées : <strong>{missions.length}</strong></li>
            <li>Total d'heures travaillées : <strong>{stats.totalHeures}h</strong></li>
            <li>Établissements fréquentés : <strong>{stats.nbEtabs}</strong></li>
          </ul>
        </div>

        <hr className="border-gray-300 mb-6" />

        {/* Footer légal */}
        <div className="text-xs text-gray-500 space-y-2">
          <p>Ce document est généré automatiquement par la plateforme Soin Direct SAS. Il peut être présenté à l'Ordre professionnel, à la CPAM ou à tout organisme compétent.</p>
          <p>Généré le : {format(new Date(), 'dd/MM/yyyy')}</p>
          <p>Identifiant : {identifiant}</p>
          <p className="font-medium">Soin Direct SAS — www.soindirect.fr</p>
          <p>Conforme RGPD · HDS · Code du Travail</p>
          <p className="italic mt-3">⚠️ Les montants financiers ne figurent pas sur cette attestation. Pour les justificatifs de rémunération, consultez vos bulletins de paie.</p>
        </div>
      </div>
    </div>
  );
}
