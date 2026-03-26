import { useState, useEffect, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { ProgressionJalons3200h } from '@/components/ProgressionJalons3200h';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { CheckCircle, Upload, FileText, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';

export default function Parcours3200h() {
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const navigate = useNavigate();
  const [soignant, setSoignant] = useState<any>(null);
  const [suivi, setSuivi] = useState<any>(null);
  const [missions, setMissions] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [uploading, setUploading] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!user) return;
    Promise.all([
      supabase.from('soignants').select('heures_cumulees, eligible_conversion_3200h, type_exercice, statut_liberal, siret_liberal').eq('id', user.id).single(),
      supabase.from('suivi_conversion_3200h').select('id, soignant_id, heures_actuelles, jalon_800h_atteint, jalon_1600h_atteint, jalon_2400h_atteint, jalon_3200h_atteint').eq('soignant_id', user.id).maybeSingle(),
      supabase.from('missions').select('debut_le, duree_heures').eq('soignant_assigne_id', user.id).eq('statut', 'TERMINEE').order('debut_le', { ascending: true }),
    ]).then(([{ data: sg }, { data: sv }, { data: ms }]) => {
      setSoignant(sg);
      setSuivi(sv);
      setMissions((ms as any[]) || []);
      setLoading(false);
      supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user.id, p_type_acteur: 'SOIGNANT',
        p_action: 'DONNEES_PERSO_CONSULTATION',
        p_type_ressource: 'soignant', p_id_ressource: user.id,
        p_cle_s3: null, p_details: { page: 'parcours_3200h' },
        p_ip: null, p_navigateur: navigator.userAgent,
      });
    });
  }, [user]);

  if (loading || !soignant) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  const heuresDepuisMissions = missions.reduce((acc, m) => acc + (m.duree_heures || 0), 0);
  const heures = Math.max(suivi?.heures_actuelles || 0, soignant.heures_cumulees || 0, heuresDepuisMissions);
  const isLiberal = soignant.type_exercice === 'LIBERAL' || soignant.statut_liberal === 'ACTIF';

  // Upload attestation 3200h
  const handleUpload3200h = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file || !user) return;
    if (file.size > 10 * 1024 * 1024) {
      afficherNotification({ type: 'erreur', message: 'Fichier trop volumineux. Maximum : 10 Mo.' });
      return;
    }
    setUploading(true);
    const path = `${user.id}/attestation_3200h/${Date.now()}_${file.name.replace(/[^a-zA-Z0-9._-]/g, '_')}`;
    const { error: upErr } = await supabase.storage.from('jolene-documents').upload(path, file);
    if (upErr) {
      afficherNotification({ type: 'erreur', message: 'Erreur lors du téléversement.' });
      setUploading(false);
      return;
    }
    const { error: docErr } = await supabase.from('documents_soignants').insert({
      soignant_id: user.id,
      type_document: 'ATTESTATION_EMPLOYEUR' as any,
      nom_fichier: file.name,
      s3_cle: path,
      s3_bucket: 'jolene-documents',
      type_mime: file.type,
      taille_octets: file.size,
      libelle: 'Attestation 3200h — heures externes',
    });
    if (docErr) {
      afficherNotification({ type: 'erreur', message: 'Erreur lors de l\'enregistrement.' });
    } else {
      afficherNotification({ type: 'succes', message: '📄 Attestation téléversée ! Elle sera vérifiée par un administrateur.' });
    }
    setUploading(false);
  };

  // CAS A : Déjà libéral
  if (isLiberal) {
    return (
      <LayoutApp role="SOIGNANT">
        <div className="mb-6">
          <h1 className="text-xl font-bold text-foreground">🎯 Parcours 3 200h</h1>
          <p className="text-sm text-muted-foreground mt-1">Votre chemin vers l'installation en libéral</p>
        </div>
        <div className="card-base text-center py-8">
          <CheckCircle className="h-12 w-12 text-success mx-auto mb-4" />
          <h2 className="text-lg font-bold text-foreground">Vous exercez déjà en libéral ✅</h2>
          <p className="text-sm text-muted-foreground mt-2">Félicitations ! Vous êtes installé(e) en libéral.</p>
          {soignant.siret_liberal && (
            <p className="text-sm text-muted-foreground mt-2">SIRET : <span className="font-mono font-bold text-foreground">{soignant.siret_liberal}</span></p>
          )}
          <div className="mt-6 flex gap-3 justify-center flex-wrap">
            <Button variant="outline" onClick={() => navigate('/soignant/documents')}>
              <FileText className="h-4 w-4 mr-2" /> Mes documents libéraux
            </Button>
            <Button onClick={() => navigate('/soignant/missions')}>
              Voir les missions →
            </Button>
          </div>
        </div>
      </LayoutApp>
    );
  }

  return (
    <LayoutApp role="SOIGNANT">
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground">🎯 Parcours 3 200h</h1>
        <p className="text-sm text-muted-foreground mt-1">Votre chemin vers l'installation en libéral</p>
      </div>

      {/* CAS B : Upload attestation "J'ai déjà mes 3200h" */}
      {heures < 3200 && (
        <div className="card-base mb-6 border-2 border-dashed border-primary/30">
          <h3 className="text-sm font-bold text-foreground mb-2">📄 J'ai déjà mes 3 200h hors plateforme</h3>
          <p className="text-xs text-muted-foreground mb-3">
            Téléversez une attestation employeur ou un bulletin de salaire prouvant vos heures. Un administrateur vérifiera votre dossier.
          </p>
          <input ref={fileRef} type="file" accept="application/pdf,image/*" className="hidden" onChange={handleUpload3200h} />
          <Button variant="outline" size="sm" disabled={uploading} onClick={() => fileRef.current?.click()} className="gap-1.5">
            {uploading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Upload className="h-4 w-4" />}
            {uploading ? 'Envoi…' : 'Téléverser mon attestation'}
          </Button>
        </div>
      )}

      {/* CAS C : Barre de progression */}
      <ProgressionJalons3200h heures={heures} suivi={suivi} missions={missions} />
    </LayoutApp>
  );
}
