import { useRef, useState } from 'react';
import { Button } from '@/components/ui/button';
import { DialogResponsive, DialogResponsiveBody, DialogResponsiveContent, DialogResponsiveDescription, DialogResponsiveFooter, DialogResponsiveHeader, DialogResponsiveTitle } from '@/components/ui/DialogResponsive';
import { formatParis } from '@/lib/date-heure-paris';
import { copieBulletinTelechargeable, ouvrirCopieBulletin, retirerCopieBulletin, signalerCopieBulletin, type CopieBulletin, type MotifSignalementCopie } from '@/lib/copiesBulletins';

interface Props {
  copies: CopieBulletin[];
  etablissement?: boolean;
  onRemplacer?: (copie: CopieBulletin) => void;
  onChangement: () => void;
  copieCible?: string | null;
}
const libellesStatut = { PUBLIEE: 'Copie disponible', REMPLACEE: 'Version remplacée', RETIREE: 'Copie retirée' };
const motifs = { DESTINATAIRE: 'Ce document ne me concerne pas', CONTENU: 'Le contenu contient une erreur', AUTRE: 'Autre erreur' };

export function CopiesBulletinsListe({ copies, etablissement = false, onRemplacer, onChangement, copieCible }: Props) {
  const [action, setAction] = useState<{ copie: CopieBulletin; type: 'signaler' | 'retirer' } | null>(null);
  const [motif, setMotif] = useState<MotifSignalementCopie>('CONTENU');
  const [busy, setBusy] = useState<string | null>(null);
  const enCours = useRef(false);
  const [erreur, setErreur] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [employeur, setEmployeur] = useState('tous');
  const employeurs = [...new Map(copies.map(c => [c.etablissement_id, c.etablissement_nom])).entries()];
  const liste = [...copies].filter(c => employeur === 'tous' || c.etablissement_id === employeur)
    .sort((a, b) => b.periode_debut.localeCompare(a.periode_debut) || b.version - a.version);

  async function ouvrir(copie: CopieBulletin) {
    if (enCours.current) return;
    enCours.current = true; setBusy(copie.id); setErreur(null); setMessage(null);
    try { await ouvrirCopieBulletin(copie); }
    catch (e) { setErreur(e instanceof Error ? e.message : 'Impossible d’ouvrir ce PDF. Réessayez.'); }
    finally { enCours.current = false; setBusy(null); }
  }
  async function confirmer() {
    if (!action || enCours.current) return;
    enCours.current = true; setBusy(action.copie.id); setErreur(null); setMessage(null);
    try {
      if (action.type === 'retirer') await retirerCopieBulletin(action.copie.id);
      else await signalerCopieBulletin(action.copie.id, motif);
      setMessage(action.type === 'retirer' || motif === 'DESTINATAIRE'
        ? 'La copie a été retirée. Son PDF n’est plus accessible dans Jolene.'
        : 'Le signalement est enregistré. L’établissement peut le consulter.');
      setAction(null); onChangement();
    } catch (e) { setErreur(e instanceof Error ? e.message : 'L’opération n’a pas été confirmée. Réessayez.'); }
    finally { enCours.current = false; setBusy(null); }
  }

  return <div className="space-y-3">
    {erreur && !action && <p role="alert" className="text-sm text-destructive">{erreur}</p>}
    {message && <p role="status" className="text-sm text-foreground">{message}</p>}
    {copieCible && !copies.some(c => c.id === copieCible) && <p role="status" className="text-sm text-muted-foreground">La copie demandée n’est pas disponible pour ce compte. Les documents accessibles sont affichés ci-dessous.</p>}
    {!etablissement && employeurs.length > 1 && <label className="block text-sm">Employeur
      <select className="mt-1 block min-h-11 w-full rounded-lg border bg-background p-2 text-base" value={employeur} onChange={e => setEmployeur(e.target.value)}>
        <option value="tous">Tous les employeurs</option>
        {employeurs.map(([id, nom]) => <option key={id} value={id}>{nom}</option>)}
      </select>
    </label>}
    {liste.length === 0 && <p className="rounded-xl border border-dashed p-5 text-sm text-muted-foreground">Aucune copie de bulletin officiel disponible. Les simulations sont présentées séparément.</p>}
    {liste.map(copie => <article key={copie.id} id={`copie-${copie.id}`} aria-label={`Copie du bulletin, version ${copie.version}`} className={`rounded-xl border p-4 ${copieCible === copie.id ? 'border-primary bg-primary/5' : 'border-border'}`}>
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <h3 className="font-semibold">{etablissement ? `${copie.soignant_prenom} ${copie.soignant_nom}` : copie.etablissement_nom}</h3>
          <p className="mt-1 text-sm">Du {formatParis(copie.periode_debut, 'dd/MM/yyyy')} au {formatParis(copie.periode_fin, 'dd/MM/yyyy')}</p>
        </div>
        <span className="rounded-full bg-muted px-2 py-1 text-xs">{libellesStatut[copie.statut]}</span>
      </div>
      <p className="mt-2 text-xs text-muted-foreground">Version {copie.version} · publiée le {formatParis(copie.publie_le, 'dd/MM/yyyy à HH:mm')} · {copie.mission_ids.length} mission{copie.mission_ids.length > 1 ? 's' : ''} liée{copie.mission_ids.length > 1 ? 's' : ''}</p>
      {copie.motif_remplacement && <p className="mt-1 text-xs text-muted-foreground">Motif de remplacement : {copie.motif_remplacement === 'CONTENU' ? 'correction du contenu' : 'autre correction'}.</p>}
      {copie.signalee && <p className="mt-2 text-sm text-warning">Une erreur a été signalée sur cette version.</p>}
      {copie.statut === 'REMPLACEE' && <p className="mt-2 text-sm text-muted-foreground">Cette ancienne version est conservée. Consultez la version la plus récente.</p>}
      {copie.statut === 'RETIREE' && <p className="mt-2 text-sm text-muted-foreground">Le PDF de cette version n’est plus accessible.</p>}
      <div className="mt-3 flex flex-wrap gap-2">
        {copieBulletinTelechargeable(copie) && <Button variant="outline" disabled={busy !== null} onClick={() => { void ouvrir(copie); }}>{busy === copie.id && !action ? 'Ouverture…' : 'Ouvrir / télécharger le PDF original'}</Button>}
        {etablissement && copie.statut === 'PUBLIEE' && <Button variant="outline" disabled={busy !== null} onClick={() => onRemplacer?.(copie)}>Remplacer cette version</Button>}
        {copieBulletinTelechargeable(copie) && <Button variant="ghost" disabled={busy !== null} onClick={() => { setErreur(null); setMotif('CONTENU'); setAction({ copie, type: etablissement ? 'retirer' : 'signaler' }); }}>{etablissement ? 'Retirer l’accès au PDF' : 'Signaler une erreur'}</Button>}
      </div>
    </article>)}
    <DialogResponsive open={action !== null} onOpenChange={open => { if (!open && !enCours.current) setAction(null); }}>
      <DialogResponsiveContent>
        <DialogResponsiveHeader>
          <DialogResponsiveTitle>{action?.type === 'retirer' ? 'Retirer cette copie' : 'Signaler une erreur'}</DialogResponsiveTitle>
          <DialogResponsiveDescription>{action?.type === 'retirer' ? 'L’accès au PDF sera supprimé pour l’établissement et le destinataire. L’historique du dépôt sera conservé.' : 'Le signalement concerne uniquement cette version du document.'}</DialogResponsiveDescription>
        </DialogResponsiveHeader>
        <DialogResponsiveBody>
          {action?.type === 'signaler' && <fieldset className="space-y-2"><legend className="mb-2 text-sm font-medium">Quelle erreur souhaitez-vous signaler ?</legend>
            {(Object.keys(motifs) as MotifSignalementCopie[]).map(code => <label key={code} className="flex min-h-11 items-center gap-3 text-sm"><input type="radio" name="motif-copie" value={code} checked={motif === code} disabled={busy !== null} onChange={() => setMotif(code)} />{motifs[code]}</label>)}
          </fieldset>}
          {action?.type === 'signaler' && motif === 'DESTINATAIRE' && <p className="mt-3 text-sm">La copie sera immédiatement retirée et son PDF ne sera plus accessible dans Jolene.</p>}
          {erreur && <p role="alert" className="mt-3 text-sm text-destructive">{erreur}</p>}
        </DialogResponsiveBody>
        <DialogResponsiveFooter><Button variant="outline" disabled={busy !== null} onClick={() => setAction(null)}>Annuler</Button><Button disabled={busy !== null} onClick={() => { void confirmer(); }}>{busy ? 'Enregistrement…' : action?.type === 'retirer' ? 'Confirmer le retrait' : 'Envoyer le signalement'}</Button></DialogResponsiveFooter>
      </DialogResponsiveContent>
    </DialogResponsive>
  </div>;
}
