import { useEffect, useState } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { CardY2K, CardY2KContent } from '@/components/y2k/CardY2K';
import { Input } from '@/components/ui/input';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { FileDeTravail } from '@/components/admin/FileDeTravail';
import { getLabelProfession } from '@/lib/constantes';
import { FileCheck, Search, CheckCircle, AlertCircle, BellRing } from 'lucide-react';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
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
  const [relanceEnCours, setRelanceEnCours] = useState<string | null>(null);
  const [relanceGroupee, setRelanceGroupee] = useState(false);

  // Relance mandat : notification in-app + email (template ADMIN_BROADCAST).
  const relancer = async (s: any): Promise<boolean> => {
    const corps = `Bonjour ${s.prenom},\n\nVotre mandat de facturation n'est pas encore signé. Il permet à Jolene de générer automatiquement vos factures d'honoraires et vous donne accès au paiement rapide (24-48h).\n\nSignez-le en 2 minutes depuis votre espace : Mon profil → Mandat de facturation.\n\nL'équipe Jolene`;
    const [notifRes, emailRes] = await Promise.all([
      supabase.rpc('fn_creer_notification', {
        p_destinataire_id: s.id,
        p_type_destinataire: 'SOIGNANT',
        p_type: 'RAPPEL_DOCUMENTS',
        p_titre: 'Signez votre mandat de facturation',
        p_corps: 'Votre mandat de facturation attend votre signature — il débloque la facturation automatique et le paiement rapide.',
        p_lien: '/soignant/mandat-facturation',
        p_type_ressource: null,
        p_id_ressource: null,
      } as any),
      supabase.functions.invoke('send-email', {
        body: {
          type: 'ADMIN_BROADCAST',
          destinataire_id: s.id,
          data: { subject: 'Votre mandat de facturation attend votre signature', body: corps },
        },
      }),
    ]);
    return !notifRes.error && !emailRes.error;
  };

  const relancerUn = async (s: any) => {
    setRelanceEnCours(s.id);
    try {
      const ok = await relancer(s);
      if (ok) toast.success(`${s.prenom} ${s.nom} relancé(e) — notification + email envoyés.`);
      else toast.error('Relance partielle ou échouée — réessayez.');
    } finally {
      setRelanceEnCours(null);
    }
  };

  const relancerTous = async (liste: any[]) => {
    if (!window.confirm(`Relancer les ${liste.length} soignant${liste.length > 1 ? 's' : ''} sans mandat signé ? Chacun recevra une notification + un email.`)) return;
    setRelanceGroupee(true);
    let ok = 0; let ko = 0;
    try {
      for (const s of liste) {
        // Envois séquentiels : évite le rate-limit Resend et garde l'UI réactive
        const succes = await relancer(s);
        if (succes) ok++; else ko++;
      }
      toast.success(`Relance groupée terminée : ${ok} envoyée(s)${ko > 0 ? `, ${ko} échec(s)` : ''}.`);
    } finally {
      setRelanceGroupee(false);
    }
  };

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

  const matchRecherche = (s: any) => {
    if (!recherche) return true;
    const q = recherche.toLowerCase();
    return `${s.prenom} ${s.nom} ${s.email}`.toLowerCase().includes(q);
  };

  const filteredSoignants = soignants.filter((s) => {
    if (filtre === 'SIGNE' && !s.mandat_facturation_signe) return false;
    if (filtre === 'NON_SIGNE' && s.mandat_facturation_signe) return false;
    return matchRecherche(s);
  });

  // File de travail (vue « Tous ») : les mandats non signés demandent une
  // relance admin → en tête, plus anciens inscrits d'abord. Les signés
  // partent dans l'historique replié.
  const nonSignes = soignants
    .filter((s) => !s.mandat_facturation_signe && matchRecherche(s))
    .sort((a, b) => new Date(a.cree_le || 0).getTime() - new Date(b.cree_le || 0).getTime());
  const signes = soignants.filter((s) => s.mandat_facturation_signe && matchRecherche(s));

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  const tauxSignature = stats?.total_soignants > 0
    ? Math.round((stats.mandat_signe / stats.total_soignants) * 100)
    : 0;

  const renderListe = (liste: any[]) => (
    <CardY2K noPadding>
      <CardY2KContent className="p-0">
        {liste.length === 0 ? (
          <p className="p-6 text-center text-muted-foreground">Aucun soignant trouvé</p>
        ) : (
          <>
            {/* Desktop table */}
            <div className="hidden md:block overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-border text-left text-xs text-muted-foreground">
                    <th className="p-3 font-medium">Soignant</th>
                    <th className="p-3 font-medium">Profession</th>
                    <th className="p-3 font-medium">Mandat</th>
                    <th className="p-3 font-medium">Signé le</th>
                    <th className="p-3 font-medium">Version</th>
                    <th className="p-3 font-medium">Inscrit le</th>
                    <th className="p-3 font-medium"></th>
                  </tr>
                </thead>
                <tbody>
                  {liste.map((s) => (
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
                        <BadgeY2K variant="info" size="sm">{getLabelProfession(s.profession)}</BadgeY2K>
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
                      <td className="p-3">
                        {!s.mandat_facturation_signe && (
                          <BoutonY2K
                            size="sm"
                            variant="secondary"
                            onClick={() => relancerUn(s)}
                            disabled={relanceEnCours === s.id || relanceGroupee}
                            loading={relanceEnCours === s.id}
                            iconeGauche={relanceEnCours === s.id ? undefined : <BellRing className="h-3.5 w-3.5" />}
                          >
                            Relancer
                          </BoutonY2K>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {/* Mobile cards */}
            <div className="md:hidden space-y-3 p-3">
              {liste.map((s) => (
                <div key={s.id} className="card-base space-y-2">
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0">
                      <button
                        onClick={() => navigate(`/admin/utilisateurs/${s.id}`)}
                        className="text-primary hover:underline font-semibold text-sm text-left"
                      >
                        {s.prenom} {s.nom}
                      </button>
                      <p className="text-xs text-muted-foreground truncate">{s.email}</p>
                    </div>
                    {s.mandat_facturation_signe ? (
                      <span className="inline-flex items-center gap-1 text-xs font-medium text-success shrink-0">
                        <CheckCircle className="h-3.5 w-3.5" /> Signé
                      </span>
                    ) : (
                      <span className="inline-flex items-center gap-1 text-xs font-medium text-warning shrink-0">
                        <AlertCircle className="h-3.5 w-3.5" /> Non signé
                      </span>
                    )}
                  </div>
                  <div className="flex items-center gap-2">
                    <BadgeY2K variant="info" size="sm">{getLabelProfession(s.profession)}</BadgeY2K>
                  </div>
                  <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs pt-1 border-t border-border/50">
                    <div>
                      <p className="text-muted-foreground">Signé le</p>
                      <p className="text-foreground">
                        {s.mandat_facturation_signe_le ? format(new Date(s.mandat_facturation_signe_le), 'dd/MM/yyyy HH:mm', { locale: fr }) : '—'}
                      </p>
                    </div>
                    <div>
                      <p className="text-muted-foreground">Version</p>
                      <p className="text-foreground">{s.mandat_facturation_version || '—'}</p>
                    </div>
                    <div>
                      <p className="text-muted-foreground">Inscrit le</p>
                      <p className="text-foreground">
                        {s.cree_le ? format(new Date(s.cree_le), 'dd/MM/yyyy', { locale: fr }) : '—'}
                      </p>
                    </div>
                  </div>
                  {!s.mandat_facturation_signe && (
                    <BoutonY2K
                      size="sm"
                      variant="secondary"
                      className="w-full"
                      onClick={() => relancerUn(s)}
                      disabled={relanceEnCours === s.id || relanceGroupee}
                      loading={relanceEnCours === s.id}
                      iconeGauche={relanceEnCours === s.id ? undefined : <BellRing className="h-3.5 w-3.5" />}
                    >
                      Relancer
                    </BoutonY2K>
                  )}
                </div>
              ))}
            </div>
          </>
        )}
      </CardY2KContent>
    </CardY2K>
  );

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
          <CardY2K noPadding className="cursor-pointer hover:border-primary/50 transition-colors" onClick={() => { setFiltre('TOUS'); window.scrollTo({ top: 400, behavior: 'smooth' }); }}>
            <CardY2KContent className="pt-4 pb-3">
              <p className="text-xs text-muted-foreground uppercase">Soignants total</p>
              <p className="text-2xl font-bold text-foreground">{stats?.total_soignants ?? 0}</p>
            </CardY2KContent>
          </CardY2K>
          <CardY2K noPadding className="border-success/30 bg-success/5 cursor-pointer hover:border-success/50 transition-colors" onClick={() => { setFiltre('SIGNE'); window.scrollTo({ top: 400, behavior: 'smooth' }); }}>
            <CardY2KContent className="pt-4 pb-3">
              <p className="text-xs text-muted-foreground uppercase">Mandat signé</p>
              <p className="text-2xl font-bold text-success">{stats?.mandat_signe ?? 0}</p>
              <p className="text-xs text-success mt-0.5">{tauxSignature}% du total</p>
            </CardY2KContent>
          </CardY2K>
          <CardY2K noPadding className="border-warning/30 bg-warning/5 cursor-pointer hover:border-warning/50 transition-colors" onClick={() => { setFiltre('NON_SIGNE'); window.scrollTo({ top: 400, behavior: 'smooth' }); }}>
            <CardY2KContent className="pt-4 pb-3">
              <p className="text-xs text-muted-foreground uppercase">Non signé</p>
              <p className="text-2xl font-bold text-warning">{stats?.mandat_non_signe ?? 0}</p>
            </CardY2KContent>
          </CardY2K>
          <CardY2K noPadding className="cursor-pointer hover:border-primary/50 transition-colors" onClick={() => navigate('/admin/facturation')}>
            <CardY2KContent className="pt-4 pb-3">
              <p className="text-xs text-muted-foreground uppercase">Factures honoraires émises</p>
              <p className="text-2xl font-bold text-foreground">{stats?.total_factures_honoraires ?? 0}</p>
              <p className="text-xs text-muted-foreground mt-0.5">
                {fmt(Number(stats?.montant_factures_honoraires_total || 0))}
              </p>
            </CardY2KContent>
          </CardY2K>
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
          {nonSignes.length > 0 && (
            <BoutonY2K
              variant="primary"
              size="sm"
              onClick={() => relancerTous(nonSignes)}
              disabled={relanceGroupee}
              loading={relanceGroupee}
              iconeGauche={relanceGroupee ? undefined : <BellRing className="h-4 w-4" />}
              className="whitespace-nowrap"
            >
              Relancer les {nonSignes.length} non signés
            </BoutonY2K>
          )}
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

        {/* File de travail (vue « Tous ») ou liste plate filtrée */}
        {filtre === 'TOUS' ? (
          <FileDeTravail
            nbATraiter={nonSignes.length}
            aTraiter={renderListe(nonSignes)}
            nbHistorique={signes.length}
            historique={renderListe(signes)}
            labelATraiter="À traiter (mandats non signés)"
            labelHistorique="Historique (mandats signés)"
            titreVide={recherche ? 'Aucun soignant trouvé' : 'Tous les mandats sont signés'}
            descriptionVide={recherche
              ? 'Aucun mandat non signé ne correspond à votre recherche.'
              : 'Tous les soignants inscrits ont signé leur mandat de facturation.'}
            iconeVide={<FileCheck />}
          />
        ) : (
          renderListe(filteredSoignants)
        )}
      </div>
    </LayoutAdmin>
  );
}
