import React, { useState, useEffect } from 'react';
import { Copy, CheckCircle, MessageCircle, Mail, Linkedin, Share2, Gift, Trophy, Building2, Award, AlertCircle, Loader2, Info } from 'lucide-react';
import { QRCodeSVG } from 'qrcode.react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { LayoutApp } from '@/components/LayoutApp';
import { SEOHead } from '@/components/SEOHead';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { toast } from 'sonner';
import {
  PARRAINAGE_ETAB_CAP,
  PARRAINAGE_ETAB_SEUIL_AMBASSADEUR,
} from '@/lib/constantes';

interface Filleul {
  parrainage_id: string;
  filleul_etab_id: string;
  filleul_nom: string;
  filleul_ville: string | null;
  statut: 'PENDING' | 'VALIDATED' | 'EXPIRED';
  cree_le: string;
  valide_le: string | null;
  credit_montant_eur: number | null;
}

interface CreditEtab {
  id: string;
  montant_eur: number;
  motif: string;
  applique_le: string | null;
  facture_id: string | null;
  cree_le: string;
}

interface CreditsState {
  total_disponible_eur: number;
  total_applique_eur: number;
  credits: CreditEtab[];
}

const CAP_PARRAINAGES = PARRAINAGE_ETAB_CAP;
const SEUIL_AMBASSADEUR = PARRAINAGE_ETAB_SEUIL_AMBASSADEUR;

export default function PageParrainageEtab() {
  usePageTitle('Parrainage — Établissement');
  const { user } = useAuth();
  const { etablissementId } = useEtablissementScope();
  const [code, setCode] = useState('');
  const [filleuls, setFilleuls] = useState<Filleul[]>([]);
  const [credits, setCredits] = useState<CreditsState | null>(null);
  const [copied, setCopied] = useState<'lien' | 'code' | null>(null);
  const [loading, setLoading] = useState(true);
  // Application code reçu (filleul)
  const [codeRecu, setCodeRecu] = useState(() => {
    try {
      const stored = sessionStorage.getItem('jolene.parrainage_etab_code');
      return stored ?? '';
    } catch { return ''; }
  });
  const [appliying, setAppliying] = useState(false);
  const [parrainApplique, setParrainApplique] = useState<string | null>(null);

  const lienRef = `https://jolene.app/inscription/etablissement?ref=${code}`;
  const filleulsValides = filleuls.filter(f => f.statut === 'VALIDATED').length;
  const badgeAmbassadeur = filleulsValides >= SEUIL_AMBASSADEUR;
  const capAtteint = filleulsValides >= CAP_PARRAINAGES;

  const charger = async () => {
    if (!etablissementId) return;
    setLoading(true);

    const [etabRes, filleulsRes, creditsRes] = await Promise.all([
      supabase.from('etablissements').select('code_parrainage').eq('id', etablissementId).maybeSingle(),
      supabase.rpc('fn_mes_filleuls_etab' as any),
      supabase.rpc('fn_mes_credits_etab' as any),
    ]);

    if (etabRes.error) toast.error('Erreur chargement code parrainage');
    if (filleulsRes.error) toast.error('Erreur chargement filleuls');
    if (creditsRes.error) toast.error('Erreur chargement crédits');

    if (etabRes.data?.code_parrainage) setCode(etabRes.data.code_parrainage);
    if (Array.isArray(filleulsRes.data)) setFilleuls(filleulsRes.data as Filleul[]);
    if (creditsRes.data && !(creditsRes.data as any)?.error) setCredits(creditsRes.data as CreditsState);
    setLoading(false);
  };

  useEffect(() => { charger(); }, [etablissementId]);

  const appliquerCode = async () => {
    const code = codeRecu.trim().toUpperCase();
    if (!code) return;
    // Format codes Jolene : ETB-XXXXXX ou JO-XXXXXX (préfixe + 4-10 alphanumériques)
    if (!/^[A-Z]{2,3}-?[A-Z0-9]{4,10}$/i.test(code)) {
      toast.error('Format de code invalide (ex. ETB-XXXXXX)');
      return;
    }
    setAppliying(true);
    const { data, error } = await supabase.rpc('fn_appliquer_parrainage_etab' as any, { p_code: code });
    setAppliying(false);
    if (error) { toast.error(error.message); return; }
    const r = data as any;
    if (r?.success) {
      toast.success(r.message ?? 'Code appliqué');
      setParrainApplique(r.parrain_nom);
      try { sessionStorage.removeItem('jolene.parrainage_etab_code'); } catch { /* noop */ }
      setCodeRecu('');
      charger();
    } else {
      toast.error(r?.error ?? 'Erreur');
    }
  };

  // Détecter si déjà filleul (a déjà appliqué un code)
  const [dejaFilleul, setDejaFilleul] = useState(false);
  useEffect(() => {
    if (!etablissementId) return;
    supabase.from('parrainages_etablissements' as any).select('id').eq('filleul_etab_id', etablissementId).maybeSingle()
      .then(({ data }: any) => setDejaFilleul(!!data));
  }, [etablissementId, parrainApplique]);

  const copier = (type: 'lien' | 'code', text: string) => {
    navigator.clipboard.writeText(text);
    setCopied(type);
    setTimeout(() => setCopied(null), 2000);
  };

  const messagePartage = encodeURIComponent(
    `Recommandation Jolene : la plateforme de staffing médical conforme et transparente. Inscrivez votre établissement avec mon code parrainage et nous gagnons tous les deux : ${lienRef}`
  );

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <SEOHead title="Parrainage Établissement — Jolene" description="Parrainez d'autres établissements : des crédits commission par paliers (50€ à 500€ de missions, puis 150€ à 2 000€), pour vous et votre filleul." />
      <div className="max-w-3xl mx-auto px-4 py-8 space-y-8">
        <div>
          <h1 className="text-2xl font-bold text-foreground flex items-center gap-2">
            <Gift className="h-6 w-6 text-primary" /> Parrainage entre établissements
          </h1>
          <p className="text-muted-foreground mt-1">
            Recommandez Jolene à un confrère et gagnez des crédits commission par paliers : <strong className="text-primary">50€ chacun</strong> dès 500€ de missions réalisées par votre filleul, puis <strong className="text-primary">150€ chacun</strong> à 2 000€. Crédits déduits de vos factures commission.
          </p>
        </div>

        {loading ? (
          <div className="card-base text-center py-10">
            <Loader2 className="h-6 w-6 animate-spin text-muted-foreground mx-auto" />
          </div>
        ) : (
          <>
            {/* Bloc "Appliquer un code reçu" — visible uniquement si pas encore filleul */}
            {!dejaFilleul && (
              <div className="card-base border-l-4 border-l-primary bg-primary/5">
                <h2 className="font-semibold text-foreground mb-2">Avez-vous reçu un code parrainage ?</h2>
                <p className="text-xs text-muted-foreground mb-3">
                  Un autre établissement vous a recommandé Jolene ? Saisissez son code (format <code className="bg-muted px-1 rounded">ETB-XXXXXX</code>). Au fil de vos missions, vous et votre parrain recevrez chacun 50€ de crédit dès 500€ de missions réalisées, puis 150€ à 2 000€.
                </p>
                <label htmlFor="code-parrainage-recu" className="sr-only">Code parrainage reçu</label>
                <div className="flex flex-col gap-2 sm:flex-row">
                  <input
                    id="code-parrainage-recu"
                    type="text"
                    value={codeRecu}
                    onChange={(e) => setCodeRecu(e.target.value.toUpperCase())}
                    placeholder="ETB-XXXXXX"
                    className="min-w-0 flex-1 px-3 py-2 text-base sm:text-sm rounded-lg border border-border bg-background font-mono"
                  />
                  <button
                    type="button"
                    onClick={appliquerCode}
                    disabled={appliying || !codeRecu.trim()}
                    className="btn-primary w-full text-sm inline-flex items-center justify-center gap-1.5 sm:w-auto"
                  >
                    {appliying ? <Loader2 className="h-4 w-4 animate-spin" /> : null}
                    Appliquer
                  </button>
                </div>
              </div>
            )}

            {/* Compteurs */}
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
              <div className="rounded-2xl border border-border bg-card p-5 text-center">
                <p className="text-3xl font-extrabold text-primary">{filleuls.length}</p>
                <p className="text-xs text-muted-foreground mt-1">filleul{filleuls.length > 1 ? 's' : ''} inscrit{filleuls.length > 1 ? 's' : ''}</p>
              </div>
              <div className="rounded-2xl border border-border bg-card p-5 text-center">
                <p className="text-3xl font-extrabold text-success">{filleulsValides}<span className="text-sm text-muted-foreground"> / {CAP_PARRAINAGES}</span></p>
                <p className="text-xs text-muted-foreground mt-1">parrainages validés</p>
              </div>
              <div className="rounded-2xl border border-border bg-card p-5 text-center">
                <p className="text-3xl font-extrabold text-foreground">
                  {credits ? `${Number(credits.total_disponible_eur).toFixed(0)} €` : '—'}
                </p>
                <p className="text-xs text-muted-foreground mt-1">crédits disponibles</p>
              </div>
            </div>

            {/* Badge Ambassadeur (3 filleuls validés) */}
            {badgeAmbassadeur && (
              <div className="rounded-2xl border-2 border-amber-400 bg-amber-50/50 dark:bg-amber-950/10 p-6 flex items-center gap-4">
                <div className="h-14 w-14 rounded-full bg-amber-100 text-amber-700 flex items-center justify-center">
                  <Trophy className="h-8 w-8" />
                </div>
                <div>
                  <h2 className="text-lg font-bold text-foreground">Ambassadeur</h2>
                  <p className="text-sm text-muted-foreground">Vous avez parrainé {filleulsValides} établissements validés ! Merci pour votre confiance.</p>
                </div>
              </div>
            )}

            {capAtteint && (
              <div className="rounded-xl border border-warning bg-warning/5 p-4 flex items-start gap-2">
                <AlertCircle className="h-4 w-4 text-warning shrink-0 mt-0.5" />
                <p className="text-xs text-foreground">
                  Vous avez atteint le cap de <strong>{CAP_PARRAINAGES} parrainages validés</strong>. Les nouvelles applications de votre code ne déclencheront plus de crédit.
                </p>
              </div>
            )}

            {/* Code & Lien */}
            <div className="rounded-2xl border border-primary/20 bg-gradient-to-br from-primary/5 to-primary/10 p-6 space-y-5">
              <div className="text-center">
                <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-1">Votre code parrainage établissement</p>
                <div className="flex items-center justify-center gap-3">
                  <span className="text-xl sm:text-3xl font-extrabold text-primary tracking-widest">{code || '...'}</span>
                  <button
                    onClick={() => copier('code', code)}
                    className="h-9 w-9 rounded-lg bg-primary/10 hover:bg-primary/20 flex items-center justify-center transition-colors"
                    title="Copier le code"
                    aria-label="Copier le code de parrainage"
                  >
                    {copied === 'code' ? <CheckCircle aria-hidden="true" className="h-4 w-4 text-primary" /> : <Copy aria-hidden="true" className="h-4 w-4 text-primary" />}
                  </button>
                </div>
              </div>

              <div className="flex flex-col sm:flex-row gap-5 items-center">
                <div className="shrink-0 bg-background p-3 rounded-xl">
                  <QRCodeSVG value={lienRef} size={140} level="M" bgColor="#FFFFFF" fgColor="#1A1A2E" className="rounded bg-white p-1" aria-label="QR code lien parrainage" role="img" />
                </div>
                <div className="flex-1 space-y-3 w-full">
                  <div className="bg-background rounded-lg px-3 py-2.5 text-xs font-mono text-muted-foreground break-all border border-border">
                    {lienRef}
                  </div>
                  <button
                    onClick={() => copier('lien', lienRef)}
                    className="w-full h-10 rounded-lg bg-primary text-primary-foreground font-semibold text-sm flex items-center justify-center gap-2 hover:bg-primary/90 transition-colors"
                  >
                    {copied === 'lien' ? <><CheckCircle className="h-4 w-4" /> Copié !</> : <><Copy className="h-4 w-4" /> Copier le lien</>}
                  </button>
                </div>
              </div>

              <div className="flex flex-wrap gap-2 justify-center">
                <a href={`https://www.linkedin.com/sharing/share-offsite/?url=${encodeURIComponent(lienRef)}`} target="_blank" rel="noopener noreferrer"
                   className="inline-flex items-center gap-1.5 px-4 py-2 rounded-lg text-xs font-semibold bg-[#0A66C2]/10 text-[#0A66C2] hover:bg-[#0A66C2]/20 transition-colors">
                  <Linkedin className="h-3.5 w-3.5" /> LinkedIn
                </a>
                <a href={`mailto:?subject=Recommandation Jolene&body=${messagePartage}`}
                   className="inline-flex items-center gap-1.5 px-4 py-2 rounded-lg text-xs font-semibold bg-muted text-foreground hover:bg-muted/80 transition-colors">
                  <Mail className="h-3.5 w-3.5" /> Email
                </a>
                <a href={`https://wa.me/?text=${messagePartage}`} target="_blank" rel="noopener noreferrer"
                   className="inline-flex items-center gap-1.5 px-4 py-2 rounded-lg text-xs font-semibold bg-[#25D366]/10 text-[#25D366] hover:bg-[#25D366]/20 transition-colors">
                  <MessageCircle className="h-3.5 w-3.5" /> WhatsApp
                </a>
              </div>
            </div>

            {/* Comment ça marche */}
            <div className="rounded-xl border border-border bg-card p-5">
              <h3 className="font-semibold text-foreground mb-2 flex items-center gap-2">
                <Award className="h-4 w-4 text-primary" /> Comment ça marche ?
              </h3>
              <ol className="text-sm text-muted-foreground leading-relaxed space-y-2 list-decimal list-inside">
                <li>Partagez votre code ou lien avec un autre établissement de santé</li>
                <li>Il s'inscrit, signe son contrat de service Jolene et applique votre code</li>
                <li>Il publie ses missions et les réalise ; les crédits se déclenchent au fil de sa GMV encaissée</li>
                <li><strong className="text-primary">Palier 1 — 50€ de crédit</strong> pour vous <strong className="text-primary">+ 50€ pour votre filleul</strong> dès <strong>500€ de missions réalisées</strong></li>
                <li><strong className="text-primary">Palier 2 — 150€ de crédit</strong> chacun à <strong>2 000€ de missions</strong>, déduits de vos factures commission</li>
                <li>Après <strong>{SEUIL_AMBASSADEUR} filleuls validés</strong>, vous obtenez le badge <span className="text-primary font-semibold">Ambassadeur</span></li>
              </ol>
              <div className="mt-3 p-2 rounded-lg bg-muted text-xs text-muted-foreground">
                <Info className="inline-block h-3.5 w-3.5 mr-1 align-text-bottom" aria-hidden="true" />Limite : {CAP_PARRAINAGES} parrainages validés maximum par établissement. Un même SIRET ne peut bénéficier que d'un seul parrainage validé.
              </div>
            </div>

            {/* Filleuls */}
            <div>
              <h3 className="font-semibold text-foreground mb-3 flex items-center gap-2">
                <Building2 className="h-4 w-4 text-primary" /> Mes filleuls établissements
              </h3>
              {filleuls.length === 0 ? (
                <div className="rounded-xl border border-dashed border-border bg-muted/30 p-8 text-center">
                  <p className="text-muted-foreground text-sm">Aucun filleul pour le moment. Partagez votre lien à vos confrères !</p>
                </div>
              ) : (
                <div className="rounded-xl border border-border overflow-hidden overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Établissement</TableHead>
                        <TableHead>Inscription</TableHead>
                        <TableHead>Statut</TableHead>
                        <TableHead className="text-right">Crédit</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {filleuls.map((f) => (
                        <TableRow key={f.parrainage_id}>
                          <TableCell className="font-medium">{f.filleul_nom}{f.filleul_ville && <span className="text-muted-foreground text-xs ml-2">· {f.filleul_ville}</span>}</TableCell>
                          <TableCell className="text-muted-foreground text-xs">
                            {f.cree_le ? new Date(f.cree_le).toLocaleDateString('fr-FR') : '—'}
                          </TableCell>
                          <TableCell>
                            {f.statut === 'VALIDATED' ? (
                              <span className="inline-flex items-center gap-1 text-xs font-semibold text-success bg-success/10 rounded-full px-2 py-0.5">
                                <CheckCircle className="h-3 w-3" /> Validé
                              </span>
                            ) : f.statut === 'EXPIRED' ? (
                              <span className="text-xs font-medium text-muted-foreground bg-muted rounded-full px-2 py-0.5">Expiré</span>
                            ) : (
                              <span className="text-xs font-medium text-warning bg-warning/10 rounded-full px-2 py-0.5">En attente</span>
                            )}
                          </TableCell>
                          <TableCell className="text-right text-sm font-semibold">
                            {f.credit_montant_eur ? `${Number(f.credit_montant_eur).toFixed(0)} €` : '—'}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
              )}
            </div>

            {/* Crédits */}
            {credits && credits.credits.length > 0 && (
              <div>
                <h3 className="font-semibold text-foreground mb-3">Mes crédits</h3>
                <div className="rounded-xl border border-border overflow-hidden overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Date</TableHead>
                        <TableHead>Motif</TableHead>
                        <TableHead className="text-right">Montant</TableHead>
                        <TableHead>Statut</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {credits.credits.map((c) => (
                        <TableRow key={c.id}>
                          <TableCell className="text-xs text-muted-foreground">{new Date(c.cree_le).toLocaleDateString('fr-FR')}</TableCell>
                          <TableCell className="text-sm">{c.motif === 'PARRAINAGE' ? 'Parrainage' : c.motif}</TableCell>
                          <TableCell className="text-right text-sm font-semibold text-foreground">{Number(c.montant_eur).toFixed(0)} €</TableCell>
                          <TableCell>
                            {c.applique_le ? (
                              <span className="text-xs text-success">Appliqué le {new Date(c.applique_le).toLocaleDateString('fr-FR')}</span>
                            ) : (
                              <span className="text-xs text-warning">À appliquer</span>
                            )}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
              </div>
            )}
          </>
        )}
      </div>
    </LayoutApp>
  );
}
