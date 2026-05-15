import { useEffect, useState } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { FileCheck, FileText, Search, CheckCircle, AlertCircle } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';

const fmt = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(Number(v) || 0);

export default function AdminMandatsFacturation() {
  usePageTitle('Mandats de facturation');
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [stats, setStats] = useState<any>(null);
  const [soignants, setSoignants] = useState<any[]>([]);
  const [recherche, setRecherche] = useState('');
  const [filtre, setFiltre] = useState<'TOUS' | 'SIGNE' | 'NON_SIGNE'>('TOUS');

  useEffect(() => {
    Promise.all([
      supabase.rpc('fn_admin_mandats_stats' as any),
      supabase.from('soignants')
        .select('id, prenom, nom, email, profession, mandat_facturation_signe, mandat_facturation_signe_le, mandat_facturation_version, cree_le')
        .is('supprime_le', null)
        .order('cree_le', { ascending: false }),
    ]).then(([sRes, uRes]) => {
      if (sRes.data) setStats(sRes.data);
      if (uRes.data) setSoignants(uRes.data);
      setLoading(false);
    })
      .catch((err) => {
        setLoading(false);
        toast.error(err?.message || 'Erreur chargement mandats');
      });
  }, []);

  const filteredSoignants = soignants.filter((s) => {
    if (filtre === 'SIGNE' && !s.mandat_facturation_signe) return false;
    if (filtre === 'NON_SIGNE' && s.mandat_facturation_signe) return false;
    if (recherche) {
      const q = recherche.toLowerCase();
      return `${s.prenom} ${s.nom} ${s.email}`.toLowerCase().includes(q);
    }
    return true;
  });

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  const tauxSignature = stats?.total_soignants > 0
    ? Math.round((stats.mandat_signe / stats.total_soignants) * 100)
    : 0;

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin pageName="Mandats de facturation" />
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-bold text-foreground flex items-center gap-2">
            <FileCheck className="h-6 w-6 text-primary" /> Mandats de facturation
          </h1>
          <p className="text-sm text-muted-foreground mt-1">
            Suivi des signatures du mandat de facturation (Article 289 I-2 CGI) et des factures d'honoraires émises.
          </p>
        </div>

        {/* KPIs — tous cliquables */}
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
          <Card className="cursor-pointer hover:border-primary/50 transition-colors" onClick={() => { setFiltre('TOUS'); window.scrollTo({ top: 400, behavior: 'smooth' }); }}>
            <CardContent className="pt-4 pb-3">
              <p className="text-xs text-muted-foreground uppercase">Soignants total</p>
              <p className="text-2xl font-bold text-foreground">{stats?.total_soignants ?? 0}</p>
            </CardContent>
          </Card>
          <Card className="border-success/30 bg-success/5 cursor-pointer hover:border-success/50 transition-colors" onClick={() => { setFiltre('SIGNE'); window.scrollTo({ top: 400, behavior: 'smooth' }); }}>
            <CardContent className="pt-4 pb-3">
              <p className="text-xs text-muted-foreground uppercase">Mandat signé</p>
              <p className="text-2xl font-bold text-success">{stats?.mandat_signe ?? 0}</p>
              <p className="text-xs text-success mt-0.5">{tauxSignature}% du total</p>
            </CardContent>
          </Card>
          <Card className="border-warning/30 bg-warning/5 cursor-pointer hover:border-warning/50 transition-colors" onClick={() => { setFiltre('NON_SIGNE'); window.scrollTo({ top: 400, behavior: 'smooth' }); }}>
            <CardContent className="pt-4 pb-3">
              <p className="text-xs text-muted-foreground uppercase">Non signé</p>
              <p className="text-2xl font-bold text-warning">{stats?.mandat_non_signe ?? 0}</p>
            </CardContent>
          </Card>
          <Card className="cursor-pointer hover:border-primary/50 transition-colors" onClick={() => navigate('/admin/facturation')}>
            <CardContent className="pt-4 pb-3">
              <p className="text-xs text-muted-foreground uppercase">Factures honoraires émises</p>
              <p className="text-2xl font-bold text-foreground">{stats?.total_factures_honoraires ?? 0}</p>
              <p className="text-xs text-muted-foreground mt-0.5">
                {fmt(Number(stats?.montant_factures_honoraires_total || 0))}
              </p>
            </CardContent>
          </Card>
        </div>

        {/* Filtres */}
        <div className="flex flex-col sm:flex-row gap-3">
          <div className="relative flex-1 max-w-md">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder="Rechercher un soignant…"
              value={recherche}
              onChange={(e) => setRecherche(e.target.value)}
              className="pl-10"
            />
          </div>
          <div className="flex gap-2">
            {(['TOUS', 'SIGNE', 'NON_SIGNE'] as const).map((f) => (
              <button
                key={f}
                onClick={() => setFiltre(f)}
                className={`px-3 py-1.5 text-xs font-medium rounded-lg border transition-colors ${
                  filtre === f ? 'border-primary bg-primary/10 text-primary' : 'border-border text-muted-foreground hover:border-primary/30'
                }`}
              >
                {f === 'TOUS' ? 'Tous' : f === 'SIGNE' ? 'Signé' : 'Non signé'}
              </button>
            ))}
          </div>
        </div>

        {/* Tableau */}
        <Card>
          <CardContent className="p-0">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-border text-left text-xs text-muted-foreground">
                    <th className="p-3 font-medium">Soignant</th>
                    <th className="p-3 font-medium">Profession</th>
                    <th className="p-3 font-medium">Mandat</th>
                    <th className="p-3 font-medium">Signé le</th>
                    <th className="p-3 font-medium">Version</th>
                    <th className="p-3 font-medium">Inscrit le</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredSoignants.length === 0 ? (
                    <tr>
                      <td colSpan={6} className="p-6 text-center text-muted-foreground">
                        Aucun soignant trouvé
                      </td>
                    </tr>
                  ) : (
                    filteredSoignants.map((s) => (
                      <tr key={s.id} className="border-b border-border/50 hover:bg-muted/30">
                        <td className="p-3">
                          <button
                            onClick={() => navigate(`/admin/utilisateurs/${s.id}`)}
                            className="text-primary hover:underline font-medium text-left"
                          >
                            {s.prenom} {s.nom}
                          </button>
                          <p className="text-xs text-muted-foreground">{s.email}</p>
                        </td>
                        <td className="p-3">
                          <BadgeY2K variant="info" size="sm">{s.profession}</BadgeY2K>
                        </td>
                        <td className="p-3">
                          {s.mandat_facturation_signe ? (
                            <span className="inline-flex items-center gap-1 text-xs font-medium text-success">
                              <CheckCircle className="h-3.5 w-3.5" /> Signé
                            </span>
                          ) : (
                            <span className="inline-flex items-center gap-1 text-xs font-medium text-warning">
                              <AlertCircle className="h-3.5 w-3.5" /> Non signé
                            </span>
                          )}
                        </td>
                        <td className="p-3 text-xs text-muted-foreground">
                          {s.mandat_facturation_signe_le ? format(new Date(s.mandat_facturation_signe_le), 'dd/MM/yyyy HH:mm', { locale: fr }) : '—'}
                        </td>
                        <td className="p-3 text-xs text-muted-foreground">
                          {s.mandat_facturation_version || '—'}
                        </td>
                        <td className="p-3 text-xs text-muted-foreground">
                          {s.cree_le ? format(new Date(s.cree_le), 'dd/MM/yyyy', { locale: fr }) : '—'}
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </CardContent>
        </Card>
      </div>
    </LayoutAdmin>
  );
}
