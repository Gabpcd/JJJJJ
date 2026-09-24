import type {BrowserContext} from '@playwright/test';
import {creerMissionSimulee,ids,now,type RoleRecette} from './recette-complete-mission';

export const conversationId='71000000-0000-4000-8000-000000000007';
export const conversationArchiveeId='71000000-0000-4000-8000-000000000009';
export async function communicationsSimulees(context:BrowserContext,role:RoleRecette) {
  const simulation=creerMissionSimulee();await simulation.installer(context,role);
  const uid=role==='SOIGNANT'?ids.soignant:ids.etablissement;
  const autre=role==='SOIGNANT'?ids.etablissement:ids.soignant;
  const state={...simulation.state,failures:new Set<string>(),callsCommunications:[] as string[],
    notifications:[{id:'notif-simulation',destinataire_id:uid,titre:'Notification fictive de recette',
      corps:'Contenu simulé, aucun envoi réel.',type:'SYSTEME',lue:false,lien:null,cree_le:now}],
  };
  await context.route('**/rest/v1/**',async route=>{
    const request=route.request(),url=new URL(request.url()),name=url.pathname.split('/').pop()!;
    if(!['notifications','fn_lister_conversations_messagerie','fn_interlocuteurs_conversations','messages_chat'].includes(name)) return route.fallback();
    state.callsCommunications.push(`${name}:${request.method()}`);
    if(state.failures.has(name)||state.failures.has(`${name}:${request.method()}`)) return route.fulfill({status:503,json:{message:'Interruption simulée des communications'}});
    if(name==='notifications') {
      if(request.method()==='PATCH') {state.notifications.forEach(n=>n.lue=true);return route.fulfill({status:200,json:null});}
      if(request.method()==='DELETE') {state.notifications=state.notifications.filter(n=>!n.lue);return route.fulfill({status:200,json:null});}
      if(['GET','HEAD'].includes(request.method())) return route.fulfill({status:200,json:state.notifications,
        headers:{'content-range':`0-${Math.max(state.notifications.length-1,0)}/${state.notifications.length}`}});
    }
    if(name==='fn_lister_conversations_messagerie'&&request.method()==='POST') return route.fulfill({status:200,json:[conversationId,conversationArchiveeId].map(id=>({
      id,participant_1_id:ids.soignant,participant_2_id:ids.etablissement,
      soignant_id:ids.soignant,etablissement_id:ids.etablissement,mission_id:ids.mission,
      autre_id:autre,dernier_message_le:now,cree_le:now,ordre_le:now,archived_at:id===conversationArchiveeId?now:null,
      dernier_contenu:id===conversationArchiveeId?'Échange archivé simulé':'Dernier échange simulé',non_lus:1,mission_intitule:'Mission fictive',
    }))});
    if(name==='fn_interlocuteurs_conversations'&&request.method()==='POST') return route.fulfill({status:200,json:[conversationId,conversationArchiveeId].flatMap(id=>[
      {conversation_id:id,participant_id:ids.soignant,prenom:'Camille',nom:'Recette',avatar_url:null,est_jolene:false},
      {conversation_id:id,participant_id:ids.etablissement,prenom:'Clinique',nom:'Simulation',avatar_url:null,est_jolene:false},
    ])});
    if(name==='messages_chat'&&request.method()==='GET') return route.fulfill({status:200,json:[{
      id:'message-simulation',conversation_id:url.searchParams.get('conversation_id')?.replace('eq.',''),auteur_id:autre,contenu:'Message de recette récupéré après la panne.',
      est_admin:false,lu:false,cree_le:now,
    }]});
    return route.fallback();
  });
  return state;
}
