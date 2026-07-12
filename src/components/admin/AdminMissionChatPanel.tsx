import { useEffect, useMemo, useState } from 'react';
import { MessageSquare } from 'lucide-react';
import { ChatMission } from '@/components/ChatMission';
import { Badge } from '@/components/ui/badge';

interface MissionChatItem {
  id: string;
  intitule: string;
  statut?: string | null;
  etablissements?: { nom?: string | null } | null;
  soignants?: { prenom?: string | null; nom?: string | null } | null;
}

interface AdminMissionChatPanelProps {
  missions: MissionChatItem[];
  emptyLabel?: string;
}

const STATUTS_CHAT = new Set(['ASSIGNEE', 'EN_COURS', 'TERMINEE', 'ABSENCE', 'LITIGE']);

export function AdminMissionChatPanel({
  missions,
  emptyLabel = 'Aucune mission liée pour ouvrir une messagerie.',
}: AdminMissionChatPanelProps) {
  const chatMissions = useMemo(
    () => missions.filter((mission) => !mission.statut || STATUTS_CHAT.has(mission.statut)),
    [missions]
  );

  const [selectedMissionId, setSelectedMissionId] = useState('');

  useEffect(() => {
    if (chatMissions.length === 0) {
      setSelectedMissionId('');
      return;
    }

    if (!chatMissions.some((mission) => mission.id === selectedMissionId)) {
      setSelectedMissionId(chatMissions[0].id);
    }
  }, [chatMissions, selectedMissionId]);

  const selectedMission = chatMissions.find((mission) => mission.id === selectedMissionId) ?? chatMissions[0];

  if (chatMissions.length === 0 || !selectedMission) {
    return (
      <div className="rounded-lg border border-dashed border-border bg-muted/30 p-6 text-sm text-muted-foreground">
        {emptyLabel}
      </div>
    );
  }

  const counterpartLabel = selectedMission.soignants
    ? `${selectedMission.soignants.prenom || ''} ${selectedMission.soignants.nom || ''}`.trim()
    : selectedMission.etablissements?.nom || null;

  return (
    <div className="space-y-4">
      <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
        <div className="space-y-1">
          <div className="flex items-center gap-2 text-sm font-medium text-foreground">
            <MessageSquare className="h-4 w-4 text-primary" />
            Messagerie liée à une mission
          </div>
          <p className="text-xs text-muted-foreground">
            Le chat admin s’appuie sur une mission commune entre les parties.
          </p>
        </div>

        <div className="flex flex-col gap-2 md:min-w-[320px]">
          <select
            aria-label="Mission associée à la conversation"
            value={selectedMission.id}
            onChange={(e) => setSelectedMissionId(e.target.value)}
            className="h-10 rounded-md border border-input bg-background px-3 text-sm text-foreground"
          >
            {chatMissions.map((mission) => (
              <option key={mission.id} value={mission.id}>
                {mission.intitule}
              </option>
            ))}
          </select>
          <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
            {selectedMission.statut && <Badge variant="outline">{selectedMission.statut}</Badge>}
            {counterpartLabel && <span>Interlocuteur lié : {counterpartLabel}</span>}
          </div>
        </div>
      </div>

      <ChatMission missionId={selectedMission.id} role="ETABLISSEMENT" prenomUtilisateur="Admin" isAdmin />
    </div>
  );
}
