import React, { useState, useEffect } from 'react';
import { Copy, CheckCircle, MessageCircle, Mail, Linkedin, Share2, Gift, Trophy, Users } from 'lucide-react';
import { QRCodeSVG } from 'qrcode.react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { LayoutApp } from '@/components/LayoutApp';
import { SEOHead } from '@/components/SEOHead';
import { getLabelProfession } from '@/lib/constantes';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';

interface Filleul {
  id: string;
  prenom: string;
  cree_le: string;
  premiere_mission_le: string | null;
  statut: string;
}

interface ClassementParrain {
  rang: number;
  label: string;
  count: number;
  isMoi: boolean;
}

export default function PageParrainage() {
  const { user } = useAuth();
  const [codeParrainage, setCodeParrainage] = useState('');
  const [filleuls, setFilleuls] = useState<Filleul[]>([]);
  const [bonusTotal, setBonusTotal] = useState(0);
  const [copied, setCopied] = useState<'lien' | 'code' | null>(null);
  const [classement, setClassement] = useState<ClassementParrain[]>([]);
  const [loading, setLoading] = useState(true);

  const lienRef = `https://jolene-app.lovable.app?ref=${codeParrainage}`;

  useEffect(() => {
    if (!user) return;
    loadData();
  }, [user]);

  const loadData = async () => {
    if (!user) return;
    setLoading(true);

    // Get code parrainage
    const { data: soignant } = await supabase
      .from('soignants')
      .select('code_parrainage')
      .eq('id', user.id)
      .single();

    if (soignant?.code_parrainage) {
      setCodeParrainage(soignant.code_parrainage);
    }

    // Get filleuls
    const { data: parrainages } = await supabase
      .from('parrainages')
      .select('filleul_id, cree_le, statut, bonus_heures_parrain')
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

      const totalBonus = parrainages.reduce((acc, p) => acc + (p.bonus_heures_parrain || 0), 0);
      setBonusTotal(totalBonus);
    }

    // Build leaderboard (top 5 parrains)
    const { data: topParrains } = await supabase
      .from('parrainages')
      .select('parrain_id')
      .order('cree_le', { ascending: false });

    if (topParrains) {
      const counts: Record<string, number> = {};
      topParrains.forEach(p => { counts[p.parrain_id] = (counts[p.parrain_id] || 0) + 1; });
      const sorted = Object.entries(counts).sort((a, b) => b[1] - a[1]).slice(0, 5);
      setClassement(sorted.map(([id, count], i) => ({
        rang: i + 1,
        label: id === user?.id ? 'Vous' : `Parrain #${i + 1}`,
        count,
        isMoi: id === user?.id,
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
    `Rejoignez Jolene, la plateforme de staffing médical ! Inscrivez-vous avec mon lien et obtenez +50h bonus : ${lienRef}`
  );

  const filleulsInscrits = filleuls.length;
  const filleulsMission = filleuls.filter(f => f.statut === 'VALIDE' || f.premiere_mission_le).length;

  return (
    <LayoutApp role="SOIGNANT">
      <SEOHead title="Parrainage — Jolene" description="Invitez vos collègues soignants et gagnez des bonus ensemble sur Jolene." />
      <div className="max-w-3xl mx-auto px-4 py-8 space-y-8">
        <div>
          <h1 className="text-2xl font-bold text-foreground flex items-center gap-2">
            <Gift className="h-6 w-6 text-primary" /> Parrainage
          </h1>
          <p className="text-muted-foreground mt-1">Invitez vos collègues et gagnez des bonus ensemble.</p>
        </div>

        {/* Code & Lien */}
        <div className="rounded-2xl border border-primary/20 bg-gradient-to-br from-primary/5 to-primary/10 p-6 space-y-5">
          {/* Code en gros */}
          <div className="text-center">
            <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-1">Votre code parrainage</p>
            <div className="flex items-center justify-center gap-3">
              <span className="text-3xl font-extrabold text-primary tracking-widest">{codeParrainage || '...'}</span>
              <button
                onClick={() => copier('code', codeParrainage)}
                className="h-9 w-9 rounded-lg bg-primary/10 hover:bg-primary/20 flex items-center justify-center transition-colors"
              >
                {copied === 'code' ? <CheckCircle className="h-4 w-4 text-primary" /> : <Copy className="h-4 w-4 text-primary" />}
              </button>
            </div>
          </div>

          {/* Lien + QR */}
          <div className="flex flex-col sm:flex-row gap-5 items-center">
            <div className="shrink-0 bg-background p-3 rounded-xl">
              <QRCodeSVG value={lienRef} size={140} level="M" bgColor="transparent" fgColor="currentColor" className="text-foreground" />
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

          {/* Boutons partage */}
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
            <p className="text-3xl font-extrabold text-primary">{filleulsInscrits}</p>
            <p className="text-xs text-muted-foreground mt-1">filleul{filleulsInscrits > 1 ? 's' : ''} inscrit{filleulsInscrits > 1 ? 's' : ''}</p>
          </div>
          <div className="rounded-xl border border-border bg-card p-5 text-center">
            <p className="text-3xl font-extrabold text-primary">{bonusTotal}h</p>
            <p className="text-xs text-muted-foreground mt-1">de bonus accumulé</p>
          </div>
        </div>

        {/* Explication */}
        <div className="rounded-xl border border-border bg-card p-5">
          <h3 className="font-semibold text-foreground mb-2 flex items-center gap-2">
            <Gift className="h-4 w-4 text-primary" /> Comment ça marche ?
          </h3>
          <p className="text-sm text-muted-foreground leading-relaxed">
            Pour chaque soignant qui s'inscrit avec votre code et termine sa 1ère mission : <span className="font-semibold text-foreground">vous gagnez 50h bonus</span> et votre filleul aussi. Les bonus sont automatiquement crédités sur vos compteurs respectifs.
          </p>
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

        {/* Classement */}
        {classement.length > 0 && (
          <div>
            <h3 className="font-semibold text-foreground mb-3 flex items-center gap-2">
              <Trophy className="h-4 w-4 text-primary" /> Classement parrains
            </h3>
            <div className="rounded-xl border border-border overflow-hidden">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead className="w-12">#</TableHead>
                    <TableHead>Parrain</TableHead>
                    <TableHead className="text-right">Filleuls</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {classement.map((c) => (
                    <TableRow key={c.rang} className={c.isMoi ? 'bg-primary/5' : ''}>
                      <TableCell className="font-bold text-primary">
                        {c.rang === 1 ? '🥇' : c.rang === 2 ? '🥈' : c.rang === 3 ? '🥉' : c.rang}
                      </TableCell>
                      <TableCell className={c.isMoi ? 'font-bold text-primary' : ''}>{c.label}</TableCell>
                      <TableCell className="text-right font-semibold">{c.count}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          </div>
        )}
      </div>
    </LayoutApp>
  );
}
