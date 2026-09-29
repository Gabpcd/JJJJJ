import { useCallback, useEffect, useRef, useState } from 'react';
import { Button } from '@/components/ui/button';
import { ApercuPdfCopie } from '@/components/ApercuPdfCopie';
import { DialogResponsive, DialogResponsiveBody, DialogResponsiveContent, DialogResponsiveDescription, DialogResponsiveFooter, DialogResponsiveHeader, DialogResponsiveTitle } from '@/components/ui/DialogResponsive';
import { chargerMissionsCopies, CopieRetireeErreur, empreintePdfCopie, idempotenceCopie, nouvelleIdempotenceCopie, publierCopieBulletin, type CopieBulletin, type DepotCopieBulletin, type MissionCopieBulletin, type MotifRemplacementCopie } from '@/lib/copiesBulletins';
import { cleJourParis, formatParis } from '@/lib/date-heure-paris';

interface Props {
  etablissementId: string;
  userId: string;
  remplacement: CopieBulletin | null;
  onFermer: () => void;
  onPublie: (id: string) => void;
}
const champ = 'mt-1 min-h-11 w-full rounded-lg border border-input bg-background p-2 text-base';

export function CopiesBulletinsDepot({ etablissementId, userId, remplacement, onFermer, onPublie }: Props) {
  const aujourdHui = cleJourParis(new Date());
  const [debut, setDebut] = useState(remplacement?.periode_debut ?? `${aujourdHui.slice(0, 7)}-01`);
  const [fin, setFin] = useState(remplacement?.periode_fin ?? aujourdHui);
  const [missions, setMissions] = useState<MissionCopieBulletin[]>([]);
  const [destinataire, setDestinataire] = useState(remplacement?.soignant_id ?? '');
  const [missionIds, setMissionIds] = useState<string[]>(remplacement?.mission_ids ?? []);
  const [chargementMissions, setChargementMissions] = useState(!remplacement);
  const [erreurMissions, setErreurMissions] = useState<string | null>(null);
  const [revision, setRevision] = useState(0);
  const [pdf, setPdf] = useState<{ file: File; url: string; sha256: string } | null>(null);
  const [lectureFichier, setLectureFichier] = useState(false);
  const lectureCourante = useRef(0);
  const [motif, setMotif] = useState<MotifRemplacementCopie>('CONTENU');
  const [etape, setEtape] = useState<'saisie' | 'confirmation'>('saisie');
  const [confirme, setConfirme] = useState(false);
  const [apercuPret, setApercuPret] = useState(false);
  const actualiserApercu = useCallback((pret: boolean) => { setApercuPret(pret); if (!pret) setConfirme(false); }, []);
  const [erreur, setErreur] = useState<string | null>(null);
  const erreurElement = useRef<HTMLParagraphElement>(null);
  const [intentionRetiree, setIntentionRetiree] = useState<{ empreinte: string; id: string } | null>(null);
  const [information, setInformation] = useState<string | null>(null);
  const [progression, setProgression] = useState<string | null>(null);
  const verrou = useRef(false);
  const intention = useRef<{ empreinte: string; id: string } | null>(null);
  const busy = progression !== null;
  const periodeValide = Boolean(debut && fin && debut <= fin);
  const destinataires = [...new Map(missions.map(m => [m.soignant_id, { id: m.soignant_id, nom: m.soignant_nom, prenom: m.soignant_prenom }])).values()];
  const profil = destinataires.find(d => d.id === destinataire);
  const nom = remplacement ? `${remplacement.soignant_prenom} ${remplacement.soignant_nom}` : profil ? `${profil.prenom} ${profil.nom}` : '';
  const missionsDestinataire = missions.filter(m => m.soignant_id === destinataire);
  const peutPrevisualiser = periodeValide && Boolean(destinataire && pdf && missionIds.length) && !chargementMissions && !erreurMissions && !lectureFichier;

  function donneesDepot(): DepotCopieBulletin {
    return { etablissementId, soignantId: destinataire, periodeDebut: debut, periodeFin: fin,
      missionIds: [...missionIds].sort(), remplaceId: remplacement?.id ?? null, motifRemplacement: remplacement ? motif : null };
  }

  useEffect(() => {
    if (remplacement) return;
    let actif = true;
    setMissions([]); setMissionIds([]); setDestinataire(''); setErreurMissions(null);
    if (!periodeValide) { setChargementMissions(false); return; }
    setChargementMissions(true);
    void chargerMissionsCopies(etablissementId, debut, fin).then(data => { if (actif) setMissions(data); })
      .catch(e => { if (actif) setErreurMissions(e instanceof Error ? e.message : 'Impossible de charger les missions. Réessayez.'); })
      .finally(() => { if (actif) setChargementMissions(false); });
    return () => { actif = false; };
  }, [etablissementId, debut, fin, periodeValide, remplacement, revision]);
  useEffect(() => () => { if (pdf) URL.revokeObjectURL(pdf.url); }, [pdf]);
  useEffect(() => () => { lectureCourante.current += 1; }, []);
  useEffect(() => {
    if (erreur) erreurElement.current?.scrollIntoView({ block: 'nearest', inline: 'nearest', behavior: 'auto' });
  }, [erreur]);

  async function choisirFichier(file: File | undefined) {
    const lecture = ++lectureCourante.current;
    setPdf(null); setErreur(null); setConfirme(false); setApercuPret(false);
    if (!file) { setLectureFichier(false); return; }
    setLectureFichier(true);
    try {
      const sha256 = await empreintePdfCopie(file);
      if (lectureCourante.current === lecture) setPdf({ file, sha256, url: URL.createObjectURL(file) });
    } catch (e) { if (lectureCourante.current === lecture) setErreur(e instanceof Error ? e.message : 'Ce fichier ne peut pas être lu.'); }
    finally { if (lectureCourante.current === lecture) setLectureFichier(false); }
  }

  async function publier() {
    if (verrou.current || intentionRetiree || !confirme || !apercuPret || !peutPrevisualiser || !pdf) return;
    verrou.current = true; setErreur(null); setInformation(null); setProgression('Préparation du dépôt…');
    const depot = donneesDepot();
    try {
      const empreinte = JSON.stringify({ depot, sha256: pdf.sha256 });
      if (intention.current?.empreinte !== empreinte) intention.current = { empreinte, id: await idempotenceCopie(userId, depot, pdf.sha256) };
      const id = await publierCopieBulletin(depot, pdf.file, pdf.sha256, intention.current.id, setProgression);
      onPublie(id);
    } catch (e) {
      if (e instanceof CopieRetireeErreur) { setIntentionRetiree(intention.current); setConfirme(false); }
      setErreur(e instanceof Error ? e.message : 'La publication n’a pas été confirmée. Réessayez.');
    }
    finally { verrou.current = false; setProgression(null); }
  }

  async function preparerNouveauDepot() {
    if (verrou.current || !intentionRetiree || !pdf) return;
    const depot = donneesDepot();
    const empreinte = JSON.stringify({ depot, sha256: pdf.sha256 });
    if (empreinte !== intentionRetiree.empreinte) return;
    verrou.current = true; setConfirme(false); setProgression('Préparation du nouveau dépôt…');
    try {
      const id = await nouvelleIdempotenceCopie(userId, depot, pdf.sha256, intentionRetiree.id);
      intention.current = { empreinte, id };
      setIntentionRetiree(null); setErreur(null);
      setInformation('Un nouveau dépôt est préparé. Vérifiez à nouveau le PDF et le destinataire, puis confirmez.');
    } catch { setErreur('Le nouveau dépôt n’a pas pu être préparé. Réessayez cette préparation.'); }
    finally { verrou.current = false; setProgression(null); }
  }

  return <DialogResponsive open onOpenChange={open => { if (!open && !verrou.current) onFermer(); }}>
    <DialogResponsiveContent maxWidth="2xl" onInteractOutside={event => { if (busy) event.preventDefault(); }} onEscapeKeyDown={event => { if (busy) event.preventDefault(); }}>
      <DialogResponsiveHeader>
        <DialogResponsiveTitle>{etape === 'confirmation' ? 'Aperçu et confirmation' : remplacement ? 'Remplacer la copie du bulletin' : 'Déposer une copie officielle'}</DialogResponsiveTitle>
        <DialogResponsiveDescription>Copie PDF du bulletin déjà remis par le service paie de l’employeur. Le dépôt ne déclare aucun salaire payé.</DialogResponsiveDescription>
      </DialogResponsiveHeader>
      <DialogResponsiveBody>
        {etape === 'saisie' ? <fieldset disabled={busy} className="space-y-4">
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <label className="text-sm font-medium">Début de période<input className={champ} type="date" value={debut} disabled={Boolean(remplacement)} onChange={e => { setDebut(e.target.value); setConfirme(false); }} /></label>
            <label className="text-sm font-medium">Fin de période<input className={champ} type="date" value={fin} disabled={Boolean(remplacement)} onChange={e => { setFin(e.target.value); setConfirme(false); }} /></label>
          </div>
          {!periodeValide && <p role="alert" className="text-sm text-destructive">La fin de période doit être postérieure ou égale au début.</p>}
          {remplacement ? <div className="rounded-xl bg-muted p-3 text-sm"><p className="font-medium">Destinataire : {nom}</p><p>{missionIds.length} mission{missionIds.length > 1 ? 's' : ''} liée{missionIds.length > 1 ? 's' : ''}. Le destinataire, la période et les missions sont conservés pour cette nouvelle version.</p></div>
            : <>
              {chargementMissions && <p role="status" className="text-sm">Chargement des destinataires et missions…</p>}
              {erreurMissions && <div role="alert"><p className="text-sm text-destructive">{erreurMissions}</p><Button variant="outline" onClick={() => setRevision(v => v + 1)}>Réessayer le chargement</Button></div>}
              <label className="block text-sm font-medium">Destinataire<select className={champ} disabled={chargementMissions || Boolean(erreurMissions)} value={destinataire} onChange={e => { setDestinataire(e.target.value); setMissionIds([]); setConfirme(false); }}>
                <option value="">Sélectionner le salarié</option>{destinataires.map(d => <option key={d.id} value={d.id}>{d.prenom} {d.nom}</option>)}
              </select></label>
              {!chargementMissions && !erreurMissions && periodeValide && missions.length === 0 && <p className="text-sm text-muted-foreground">Aucune mission salariée attribuée n’est disponible pour cette période. Vérifiez les dates.</p>}
              {destinataire && <fieldset className="space-y-2"><legend className="mb-2 text-sm font-medium">Missions concernées</legend>{missionsDestinataire.map(m => <label key={m.id} className="flex min-h-11 items-start gap-3 rounded-lg border p-3 text-sm"><input type="checkbox" className="mt-1" checked={missionIds.includes(m.id)} onChange={e => { setMissionIds(ids => e.target.checked ? [...ids, m.id] : ids.filter(id => id !== m.id)); setConfirme(false); }} /><span>{m.intitule}<span className="block text-xs text-muted-foreground">{formatParis(m.debut_le, 'dd/MM/yyyy')} – {formatParis(m.fin_le, 'dd/MM/yyyy')}</span></span></label>)}<p className="text-xs text-muted-foreground">Sélectionnez au moins une mission du même employeur et du même salarié. Le document peut aussi couvrir des éléments de paie extérieurs à Jolene.</p></fieldset>}
            </>}
          {remplacement && <label className="block text-sm font-medium">Motif du remplacement<select className={champ} value={motif} onChange={e => setMotif(e.target.value as MotifRemplacementCopie)}><option value="CONTENU">Correction du contenu</option><option value="AUTRE">Autre correction</option></select></label>}
          <label className="block text-sm font-medium">PDF officiel (10 Mo maximum)<input className={`${champ} text-sm`} type="file" accept="application/pdf,.pdf" onChange={e => { void choisirFichier(e.target.files?.[0]); }} /></label>
          {pdf && <p className="break-all text-xs text-muted-foreground">Fichier sélectionné : {pdf.file.name}</p>}
          <p className="text-xs text-muted-foreground">Choisissez le fichier établi par votre service paie, jamais une simulation générée dans Jolene. Le serveur vérifiera le PDF avant publication.</p>
          {lectureFichier && <p role="status" className="text-sm">Vérification du fichier…</p>}
        </fieldset> : <div className="space-y-4">
          <div className="rounded-xl border border-primary/20 bg-primary/5 p-4 text-sm"><p className="font-semibold">Destinataire : {nom}</p><p>Période : du {formatParis(debut, 'dd/MM/yyyy')} au {formatParis(fin, 'dd/MM/yyyy')}</p><p>{missionIds.length} mission{missionIds.length > 1 ? 's' : ''} sélectionnée{missionIds.length > 1 ? 's' : ''}{remplacement ? ` · remplace la version ${remplacement.version}` : ''}</p></div>
          {pdf && <><ApercuPdfCopie key={pdf.url} file={pdf.file} onPretChange={actualiserApercu} /><a className="inline-flex min-h-11 items-center text-sm text-primary underline" href={pdf.url} target="_blank" rel="noopener noreferrer">Ouvrir aussi le PDF dans un nouvel onglet</a></>}
          <label className="flex items-start gap-3 rounded-xl border p-3 text-sm"><input type="checkbox" className="mt-1" checked={confirme} disabled={busy || !apercuPret || Boolean(intentionRetiree)} onChange={e => setConfirme(e.target.checked)} /><span>Je confirme le destinataire et que cette copie du bulletin officiel a déjà été remise par le service paie de l’employeur.</span></label>
        </div>}
        {erreur && <p ref={erreurElement} role="alert" className="mt-4 scroll-my-1 text-sm text-destructive">{erreur}</p>}
        {information && <p role="status" className="mt-4 text-sm">{information}</p>}
        {progression && <p role="status" className="mt-4 text-sm">{progression}</p>}
      </DialogResponsiveBody>
      <DialogResponsiveFooter>
        <Button variant="outline" disabled={busy} onClick={() => { if (etape === 'confirmation') { setEtape('saisie'); setConfirme(false); setErreur(null); setIntentionRetiree(null); setInformation(null); } else onFermer(); }}>{etape === 'confirmation' ? 'Modifier le dépôt' : 'Annuler'}</Button>
        {etape === 'saisie' ? <Button disabled={!peutPrevisualiser} onClick={() => { setEtape('confirmation'); setErreur(null); }}>Aperçu et confirmation</Button>
          : intentionRetiree ? <Button disabled={busy} onClick={() => { void preparerNouveauDepot(); }}>Préparer un nouveau dépôt</Button>
            : <Button disabled={!confirme || !apercuPret || busy || !peutPrevisualiser} onClick={() => { void publier(); }}>{busy ? 'Publication en cours…' : 'Confirmer la publication'}</Button>}
      </DialogResponsiveFooter>
    </DialogResponsiveContent>
  </DialogResponsive>;
}
