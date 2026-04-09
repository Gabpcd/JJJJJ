import React, { useState, useEffect } from 'react';
import { Copy, CheckCircle, MessageCircle, Mail, Linkedin, Share2, Gift, Trophy, Users, Shield, Zap } from 'lucide-react';
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
}

export default function PageParrainage() {
  const { user } = useAuth();
  const [codeParrainage, setCodeParrainage] = useState('');
  const [filleuls, setFilleuls] = useState<Filleul[]>([]);
  const [copied, setCopied] = useState<'lien' | 'code' | null>(null);
  const [loading, setLoading] = useState(true);
  const [badgeAmbassadeur, setBadgeAmbassadeur] = useState(false);
  const [prioriteMissionsUrgentes, setPrioriteMissionsUrgentes] = useState(false);

  const lienRef = `https://jolene-app.lovable.app?ref=${codeParrainage}`;

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
      .single();

    if (soignant) {
      setCodeParrainage(soignant.code_parrainage || '');
      setBadgeAmbassadeur(!!(soignant as any).badge_ambassadeur);
      setPrioriteMissionsUrgentes(!!(soignant as any).priorite_missions_urgentes);
    }

    const { data: parrainages } = await supabase
      .from('parrainages')
      .select('filleul_id, cree_le, statut')
      .eq('parrain_id', user.id)
      .order('cree_le', { ascending: false });

    if (parrainages && parrainages.length > 0) {
      const filleulIds = parrainages.map(p => p.filleul_id);
      const { data: soignants } = await supabase
        .from('soignants')
        .select('id, prenom, cree_le, premiere_mission_le')
        .in('id', filleulIds);

      const filleulsList: Filleul[] = parrainages.map(p => {
        const s = soignants?.find(s => s.id === p.filleul_id);
        return {
          id: p.filleul_id,
          prenom: s?.prenom || 'Soignant',
          cree_le: p.cree_le || '',
          premiere_mission_le: s?.premiere_mission_le || null,
          statut: p.statut || 'INSCRIT',
        };
      });
      setFilleuls(filleulsList);
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
      <SEOHead title="Parrainage — Jolene" description="Invitez vos collègues soignants et obtenez le badge Ambassadeur sur Jolene." />
      <div className="max-w-3xl mx-auto px-4 py-8 space-y-8">
        <div>
          <h1 className="text-2xl font-bold text-foreground flex items-center gap-2">
            <Gift className="h-6 w-6 text-primary" /> Parrainage
          </h1>
          <p className="text-muted-foreground mt-1">Recommandez Jolene à vos collègues et débloquez des avantages exclusifs.</p>
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
              <p className="text-xs text-muted-foreground mt-2">Parrainez 3 collègues qui terminent leur 1ère mission pour obtenir le badge.</p>
            </div>
          )}

          <div className="flex items-start gap-2 p-3 rounded-xl bg-primary/5 border border-primary/20">
            <Zap className="h-4 w-4 text-primary mt-0.5 flex-shrink-0" />
            <div className="text-sm text-foreground">
              <p className="font-semibold">Avantage : Accès prioritaire aux missions urgentes</p>
              <p className="text-xs text-muted-foreground mt-0.5">Les missions urgentes vous sont visibles <strong>15 minutes avant</strong> les autres soignants.</p>
            </div>
          </div>
        </div>

        {/* Code & Lien */}
        <div className="rounded-2xl border border-primary/20 bg-gradient-to-br from-primary/5 to-primary/10 p-6 space-y-5">
          <div className="text-center">
            <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-1">Votre code parrainage</p>
            <div className="flex items-center justify-center gap-3">
              <span className="text-xl sm:text-3xl font-extrabold text-primary tracking-widest">{codeParrainage || '...'}</span>
              <button
                onClick={() => copier('code', codeParrainage)}
                className="h-9 w-9 rounded-lg bg-primary/10 hover:bg-primary/20 flex items-center justify-center transition-colors"
              >
                {copied === 'code' ? <CheckCircle className="h-4 w-4 text-primary" /> : <Copy className="h-4 w-4 text-primary" />}
              </button>
            </div>
          </div>

          <div className="flex flex-col sm:flex-row gap-5 items-center">
            <div className="shrink-0 bg-background p-3 rounded-xl">
              <QRCodeSVG value={lienRef} size={140} level="M" bgColor="transparent" fgColor="currentColor" className="text-foreground" aria-label="QR code de votre lien de parrainage" role="img" />
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
            <li>Partagez votre code ou lien avec vos collègues soignants</li>
            <li>Ils s'inscrivent et terminent leur première mission sur Jolene</li>
            <li>Après <strong>3 filleuls validés</strong>, vous obtenez le badge <span className="text-primary font-semibold">Ambassadeur</span></li>
            <li>Le badge vous donne accès aux missions urgentes <strong>15 min avant tout le monde</strong></li>
          </ol>
          <div className="mt-3 p-2 rounded-lg bg-muted text-xs text-muted-foreground">
            ℹ️ Le parrainage Jolene est un système de recommandation sans rétribution financière, conforme à la réglementation.
          </div>
        </div>

        {/* Tableau filleuls */}
        <div>
          <h3 className="font-semibold text-foreground mb-3 flex items-center gap-2">
            <Users className="h-4 w-4 text-primary" /> Mes filleuls
          </h3>
          {filleuls.length === 0 ? (
            <div className="rounded-xl border border-dashed border-border bg-muted/30 p-8 text-center">
              <p className="text-muted-foreground text-sm">Aucun filleul pour le moment. Partagez votre lien !</p>
            </div>
          ) : (
            <div className="rounded-xl border border-border overflow-hidden">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Prénom</TableHead>
                    <TableHead>Inscription</TableHead>
                    <TableHead>Statut</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {filleuls.map((f) => (
                    <TableRow key={f.id}>
                      <TableCell className="font-medium">{f.prenom}</TableCell>
                      <TableCell className="text-muted-foreground text-xs">
                        {f.cree_le ? new Date(f.cree_le).toLocaleDateString('fr-FR') : '—'}
                      </TableCell>
                      <TableCell>
                        {f.premiere_mission_le || f.statut === 'VALIDE' ? (
                          <span className="inline-flex items-center gap-1 text-xs font-semibold text-primary bg-primary/10 rounded-full px-2 py-0.5">
                            <CheckCircle className="h-3 w-3" /> 1ère mission faite
                          </span>
                        ) : (
                          <span className="text-xs font-medium text-muted-foreground bg-muted rounded-full px-2 py-0.5">Inscrit</span>
                        )}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </div>
      </div>
    </LayoutApp>
  );
}
