import React, { useState, useEffect } from 'react';
import { Copy, CheckCircle, MessageCircle, Mail, Linkedin, Share2, Gift, Users, Shield, Landmark } from 'lucide-react';
import { QRCodeSVG } from 'qrcode.react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { LayoutApp } from '@/components/LayoutApp';
import { SEOHead } from '@/components/SEOHead';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';

interface Filleul {
  id: string;
  prenom: string;
  cree_le: string;
  premiere_mission_le: string | null;
  statut: string;
  // 7f — progression vers la prime (fn_obtenir_mes_parrainages v2)
  prime_versee_le?: string | null;
  gmv_cumule_filleul?: number;
  reste_gmv_avant_prime?: number;
  seuil_gmv?: number;
}

export default function PageParrainage() {
  const { user } = useAuth();
  const [codeParrainage, setCodeParrainage] = useState('');
  const [filleuls, setFilleuls] = useState<Filleul[]>([]);
  const [copied, setCopied] = useState<'lien' | 'code' | null>(null);
  const [loading, setLoading] = useState(true);
  const [badgeAmbassadeur, setBadgeAmbassadeur] = useState(false);
  const [prioriteMissionsUrgentes, setPrioriteMissionsUrgentes] = useState(false);

  const lienRef = `https://jolene.app/inscription/soignant?ref=${codeParrainage}`;

  useEffect(() => {
    if (!user) return;
    loadData();
  }, [user]);

  const loadData = async () => {
    if (!user) return;
    setLoading(true);

    const { data: soignant } = await supabase
      .from('soignants')
      .select('code_parrainage, badge_ambassadeur, priorite_missions_urgentes')
      .eq('id', user.id)
      .maybeSingle();

    if (soignant) {
      setCodeParrainage(soignant.code_parrainage || '');
      setBadgeAmbassadeur(!!(soignant as any).badge_ambassadeur);
      setPrioriteMissionsUrgentes(!!(soignant as any).priorite_missions_urgentes);
    }

    const { data: rpcData } = await supabase.rpc('fn_obtenir_mes_parrainages' as any);
    const result = rpcData as any;
    if (result && !result.error && Array.isArray(result.filleuls)) {
      setFilleuls(result.filleuls.map((f: any) => ({
        id: f.filleul_id,
        prenom: f.prenom || 'Soignant',
        cree_le: f.cree_le || '',
        premiere_mission_le: f.premiere_mission_le || null,
        statut: f.statut || 'INSCRIT',
      })));
    }

    setLoading(false);
  };

  const copier = (type: 'lien' | 'code', text: string) => {
    navigator.clipboard.writeText(text);
    setCopied(type);
    setTimeout(() => setCopied(null), 2000);
  };

  const messagePartage = encodeURIComponent(
    `Rejoignez Jolene, la plateforme de staffing médical ! Inscrivez-vous avec mon lien : ${lienRef}`
  );

  const filleulsInscrits = filleuls.length;
  const filleulsValides = filleuls.filter(f => f.statut === 'VALIDE' || f.premiere_mission_le).length;
  const progressAmbassadeur = Math.min(filleulsValides, 3);

  return (
    <LayoutApp role="SOIGNANT">
      <SEOHead title="Parrainage — Jolene" description="Invite tes collègues soignants et obtiens le badge Ambassadeur sur Jolene." />
      <div className="max-w-3xl mx-auto px-4 py-8 space-y-8">
        <div>
          <h1 className="text-2xl font-bold text-foreground flex items-center gap-2">
            <Gift className="h-6 w-6 text-primary" /> Parrainage
          </h1>
          <p className="text-muted-foreground mt-1">Recommande Jolene à tes collègues et débloque des avantages exclusifs.</p>
        </div>

        {/* Badge Ambassadeur */}
        <div className={`rounded-2xl border-2 p-6 ${badgeAmbassadeur ? 'border-primary bg-primary/5' : 'border-border bg-card'}`}>
          <div className="flex items-center gap-3 mb-4">
            <div className={`h-12 w-12 rounded-full flex items-center justify-center ${badgeAmbassadeur ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground'}`}>
              <Shield className="h-6 w-6" />
            </div>
            <div>
              <h2 className="text-lg font-bold text-foreground">Badge Ambassadeur</h2>
              {badgeAmbassadeur ? (
                <p className="text-sm text-primary font-semibold">✅ Débloqué !</p>
              ) : (
                <p className="text-sm text-muted-foreground">{progressAmbassadeur}/3 filleuls validés</p>
              )}
            </div>
          </div>

          {!badgeAmbassadeur && (
            <div className="mb-4">
              <div className="h-3 bg-muted rounded-full overflow-hidden">
                <div className="h-full bg-primary rounded-full transition-all" style={{ width: `${(progressAmbassadeur / 3) * 100}%` }} />
              </div>
              <p className="text-xs text-muted-foreground mt-2">Parraine 3 collègues qui terminent leur 1ère mission pour obtenir le badge.</p>
            </div>
          )}

          <div className="flex items-start gap-2 p-3 rounded-xl bg-primary/5 border border-primary/20 mb-2">
            <Landmark className="h-4 w-4 text-primary mt-0.5 flex-shrink-0" />
            <div className="text-sm text-foreground">
              {/* 7f (§5) : 25 € chacun à 500 € de missions ENCAISSÉES du filleul
                  — jamais « mission terminée » (règle d'or, prime autofinancée). */}
              <p className="font-semibold">Prime de 25€ pour toi + 25€ pour ton filleul</p>
              <p className="text-xs text-muted-foreground mt-0.5">Versée par virement quand ton filleul atteint 500€ de missions encaissées (1 à 2 missions en général). Renseigne ton IBAN dans <strong>Profil → Paiements</strong>.</p>
            </div>
          </div>
          <div className="flex items-start gap-2 p-3 rounded-xl bg-primary/5 border border-primary/20">
            <Shield className="h-4 w-4 text-primary mt-0.5 flex-shrink-0" />
            <div className="text-sm text-foreground">
              <p className="font-semibold">Badge Ambassadeur visible</p>
              <p className="text-xs text-muted-foreground mt-0.5">Une fois débloqué, le badge Ambassadeur apparaît sur ton profil côté établissements (annuaire, recherches, candidatures).</p>
            </div>
          </div>
        </div>

        {/* Code & Lien */}
        <div className="rounded-2xl border border-primary/20 bg-gradient-to-br from-primary/5 to-primary/10 p-6 space-y-5">
          <div className="text-center">
            <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-1">Ton code parrainage</p>
            <div className="flex items-center justify-center gap-3">
              <span className="text-xl sm:text-3xl font-extrabold text-primary tracking-widest">{codeParrainage || '...'}</span>
              <button
                onClick={() => copier('code', codeParrainage)}
                className="h-9 w-9 rounded-lg bg-primary/10 hover:bg-primary/20 flex items-center justify-center transition-colors"
                title="Copier le code"
                aria-label="Copier le code parrainage"
              >
                {copied === 'code' ? <CheckCircle className="h-4 w-4 text-primary" /> : <Copy className="h-4 w-4 text-primary" />}
              </button>
            </div>
          </div>

          <div className="flex flex-col sm:flex-row gap-5 items-center">
            <div className="shrink-0 bg-background p-3 rounded-xl">
              <QRCodeSVG value={lienRef} size={140} level="M" bgColor="#FFFFFF" fgColor="#1A1A2E" className="rounded bg-white p-1" aria-label="QR code de ton lien de parrainage" role="img" />
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
            <a href={`https://wa.me/?text=${messagePartage}`} target="_blank" rel="noopener noreferrer"
               className="inline-flex items-center gap-1.5 px-4 py-2 rounded-lg text-xs font-semibold bg-[#25D366]/10 text-[#25D366] hover:bg-[#25D366]/20 transition-colors">
              <MessageCircle className="h-3.5 w-3.5" /> WhatsApp
            </a>
            <a href={`sms:?body=${messagePartage}`}
               className="inline-flex items-center gap-1.5 px-4 py-2 rounded-lg text-xs font-semibold bg-muted text-foreground hover:bg-muted/80 transition-colors">
              <Share2 className="h-3.5 w-3.5" /> SMS
            </a>
            <a href={`mailto:?subject=Rejoignez Jolene&body=${messagePartage}`}
               className="inline-flex items-center gap-1.5 px-4 py-2 rounded-lg text-xs font-semibold bg-muted text-foreground hover:bg-muted/80 transition-colors">
              <Mail className="h-3.5 w-3.5" /> Email
            </a>
            <a href={`https://www.linkedin.com/sharing/share-offsite/?url=${encodeURIComponent(lienRef)}`} target="_blank" rel="noopener noreferrer"
               className="inline-flex items-center gap-1.5 px-4 py-2 rounded-lg text-xs font-semibold bg-[#0A66C2]/10 text-[#0A66C2] hover:bg-[#0A66C2]/20 transition-colors">
              <Linkedin className="h-3.5 w-3.5" /> LinkedIn
            </a>
          </div>
        </div>

        {/* Compteur */}
        <div className="grid grid-cols-2 gap-4">
          <div className="rounded-xl border border-border bg-card p-5 text-center">
            <p className="text-xl sm:text-3xl font-extrabold text-primary">{filleulsInscrits}</p>
            <p className="text-xs text-muted-foreground mt-1">filleul{filleulsInscrits > 1 ? 's' : ''} inscrit{filleulsInscrits > 1 ? 's' : ''}</p>
          </div>
          <div className="rounded-xl border border-border bg-card p-5 text-center">
            <p className="text-xl sm:text-3xl font-extrabold text-primary">{filleulsValides}</p>
            <p className="text-xs text-muted-foreground mt-1">mission{filleulsValides > 1 ? 's' : ''} terminée{filleulsValides > 1 ? 's' : ''}</p>
          </div>
        </div>

        {/* Explication */}
        <div className="rounded-xl border border-border bg-card p-5">
          <h3 className="font-semibold text-foreground mb-2 flex items-center gap-2">
            <Gift className="h-4 w-4 text-primary" /> Comment ça marche ?
          </h3>
          <ol className="text-sm text-muted-foreground leading-relaxed space-y-2 list-decimal list-inside">
            <li>Partage ton code ou lien avec tes collègues soignants</li>
            <li>Ton filleul applique ton code à l'inscription</li>
            <li>Quand il atteint <strong>500€ de missions encaissées</strong> : <strong>25€ versés</strong> pour toi + <strong>25€ pour lui</strong> (par virement sur ton IBAN)</li>
            <li>Après <strong>3 filleuls validés</strong>, tu obtiens le badge <span className="text-primary font-semibold">Ambassadeur</span></li>
          </ol>
        </div>

        {/* Tableau filleuls */}
        <div>
          <h3 className="font-semibold text-foreground mb-3 flex items-center gap-2">
            <Users className="h-4 w-4 text-primary" /> Mes filleuls
          </h3>
          {filleuls.length === 0 ? (
            <div className="rounded-xl border border-dashed border-border bg-muted/30 p-8 text-center">
              <p className="text-muted-foreground text-sm">Aucun filleul pour le moment. Partage ton lien !</p>
            </div>
          ) : (
            <div className="rounded-xl border border-border overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Prénom</TableHead>
                    <TableHead>Inscription</TableHead>
                    <TableHead>Statut</TableHead>
                    <TableHead>Vers la prime</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {filleuls.map((f) => {
                    const aFaitMission = !!f.premiere_mission_le || f.statut === 'VALIDE';
                    const enAttente = !aFaitMission && f.statut === 'EN_ATTENTE';
                    // 7f (§5) : visibilité du progrès — « plus que X € de missions
                    // avant vos primes » (gmv exposé par fn_obtenir_mes_parrainages v2).
                    const primeVersee = f.statut === 'PRIME_VERSEE' || !!f.prime_versee_le;
                    const resteGmv = Number(f.reste_gmv_avant_prime ?? NaN);
                    const seuilGmv = Number(f.seuil_gmv ?? 500);
                    const gmv = Number(f.gmv_cumule_filleul ?? 0);
                    return (
                      <TableRow key={f.id}>
                        <TableCell className="font-medium">{f.prenom}</TableCell>
                        <TableCell className="text-muted-foreground text-xs whitespace-nowrap">
                          {f.cree_le ? new Date(f.cree_le).toLocaleDateString('fr-FR') : '—'}
                        </TableCell>
                        <TableCell>
                          {aFaitMission ? (
                            <span className="inline-flex items-center gap-1 text-xs font-semibold text-primary bg-primary/10 rounded-full px-2 py-0.5 whitespace-nowrap">
                              <CheckCircle className="h-3 w-3" /> 1ère mission faite
                            </span>
                          ) : enAttente ? (
                            <span className="inline-flex items-center gap-1 text-xs font-semibold text-warning bg-warning/10 rounded-full px-2 py-0.5 whitespace-nowrap">
                              ⏳ En attente
                            </span>
                          ) : (
                            <span className="text-xs font-medium text-muted-foreground bg-muted rounded-full px-2 py-0.5 whitespace-nowrap">Inscrit</span>
                          )}
                        </TableCell>
                        <TableCell className="min-w-[150px]">
                          {primeVersee ? (
                            <span className="text-xs font-semibold text-success whitespace-nowrap">💰 Primes versées</span>
                          ) : aFaitMission && Number.isFinite(resteGmv) ? (
                            <div>
                              <div className="h-1.5 rounded-full bg-muted overflow-hidden mb-1" aria-hidden="true">
                                <div
                                  className="h-full rounded-full bg-primary transition-all"
                                  style={{ width: `${Math.min(100, Math.round((gmv / seuilGmv) * 100))}%` }}
                                />
                              </div>
                              <p className="text-[11px] text-muted-foreground whitespace-nowrap">
                                {resteGmv > 0
                                  ? `Plus que ${Math.ceil(resteGmv)} € de missions avant vos primes`
                                  : 'Seuil atteint — primes en cours de versement'}
                              </p>
                            </div>
                          ) : (
                            <span className="text-[11px] text-muted-foreground">—</span>
                          )}
                        </TableCell>
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
            </div>
          )}
        </div>
      </div>
    </LayoutApp>
  );
}
