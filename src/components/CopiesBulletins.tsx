import { useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { useEtabPermissions } from '@/hooks/useEtabPermissions';
import { Button } from '@/components/ui/button';
import { CopiesBulletinsListe } from '@/components/CopiesBulletinsListe';
import { CopiesBulletinsDepot } from '@/components/CopiesBulletinsDepot';
import { listerCopiesBulletins, type CopieBulletin } from '@/lib/copiesBulletins';

export function CopiesBulletinsEtablissement({ etablissementId }: { etablissementId: string }) {
  const { user } = useAuth();
  if (!user || !etablissementId) return null;
  return <CopiesBulletinsAvecPermission key={`${user.id}:${etablissementId}`} userId={user.id} etablissementId={etablissementId} />;
}
function CopiesBulletinsAvecPermission({ userId, etablissementId }: { userId: string; etablissementId: string }) {
  const { loading, error, permissions, recharger } = useEtabPermissions(etablissementId);
  if (loading) return <section className="card-base"><h2 className="font-semibold">Copies des bulletins officiels</h2><p role="status" className="mt-2 text-sm">Vérification des accès…</p></section>;
  if (error) return <section className="card-base"><h2 className="font-semibold">Copies des bulletins officiels</h2><p role="alert" className="my-2 text-sm text-destructive">Vos droits d’accès n’ont pas pu être vérifiés.</p><Button variant="outline" onClick={() => { void recharger(); }}>Réessayer les accès</Button></section>;
  if (!permissions.paiement) return <section className="card-base"><h2 className="font-semibold">Copies des bulletins officiels</h2><p className="mt-2 text-sm text-muted-foreground">La consultation et le dépôt des copies sont réservés aux membres disposant du droit de paiement pour cet établissement.</p></section>;
  return <CopiesBulletinsContenu userId={userId} etablissementId={etablissementId} />;
}
export function CopiesBulletinsSoignant() {
  const { user } = useAuth();
  return user ? <CopiesBulletinsContenu key={user.id} userId={user.id} /> : null;
}
function CopiesBulletinsContenu({ userId, etablissementId }: { userId: string; etablissementId?: string }) {
  const [search] = useSearchParams();
  const [copies, setCopies] = useState<CopieBulletin[]>([]);
  const [loading, setLoading] = useState(true);
  const [erreur, setErreur] = useState<string | null>(null);
  const [revision, setRevision] = useState(0);
  const [depot, setDepot] = useState<{ remplacement: CopieBulletin | null } | null>(null);
  const [publie, setPublie] = useState<string | null>(null);
  useEffect(() => {
    let actif = true;
    setLoading(true); setErreur(null); setCopies([]);
    void listerCopiesBulletins(etablissementId ?? null).then(data => { if (actif) setCopies(data); })
      .catch(e => { if (actif) setErreur(e instanceof Error ? e.message : 'Impossible de charger les copies. Réessayez.'); })
      .finally(() => { if (actif) setLoading(false); });
    return () => { actif = false; };
  }, [etablissementId, userId, revision]);
  return <section className="card-base space-y-4" aria-label="Copies des bulletins officiels">
    <div className="flex flex-wrap items-center justify-between gap-3"><h2 className="font-semibold">Copies des bulletins officiels</h2>{etablissementId && <Button onClick={() => { setPublie(null); setDepot({ remplacement: null }); }}>Déposer une copie officielle</Button>}</div>
    <p className="text-sm text-muted-foreground">Retrouvez les PDF déposés par l’employeur, déjà remis par son service paie. Une copie disponible ne confirme pas le paiement du salaire.</p>
    {publie && <p role="status" className="text-sm text-success">La copie a été publiée. Le destinataire peut la consulter dans ses documents de paie.</p>}
    {loading && <p role="status" className="text-sm">Chargement des copies…</p>}
    {erreur && <div role="alert"><p className="text-sm text-destructive">{erreur}</p><Button className="mt-2" variant="outline" onClick={() => setRevision(v => v + 1)}>Réessayer les copies</Button></div>}
    {!loading && !erreur && <CopiesBulletinsListe copies={copies} etablissement={Boolean(etablissementId)} copieCible={publie ?? search.get('copie')} onRemplacer={copie => setDepot({ remplacement: copie })} onChangement={() => setRevision(v => v + 1)} />}
    {depot && etablissementId && <CopiesBulletinsDepot key={depot.remplacement?.id ?? 'nouvelle'} userId={userId} etablissementId={etablissementId} remplacement={depot.remplacement} onFermer={() => setDepot(null)} onPublie={id => { setDepot(null); setPublie(id); setRevision(v => v + 1); }} />}
  </section>;
}
