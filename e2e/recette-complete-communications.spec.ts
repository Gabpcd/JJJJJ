import {test,expect} from '@playwright/test';
import {communicationsSimulees,conversationId,conversationArchiveeId} from './helpers/recette-complete-communications';
import {now,preuveMission,type RoleRecette} from './helpers/recette-complete-mission';

for(const role of ['SOIGNANT','ADMIN_ETABLISSEMENT'] as RoleRecette[]) {
  const prefix=role==='SOIGNANT'?'soignant':'etablissement';
  test(`${role} : notifications indisponibles, reprise et mutations fiables`,async({context,page},info)=>{
    const state=await communicationsSimulees(context,role);page.setDefaultTimeout(12_000);
    await page.clock.setFixedTime(new Date(now));state.failures.add('notifications');
    try {
      await page.goto(`/${prefix}/notifications`);
      await expect(page.getByRole('alert').filter({hasText:'Impossible de charger vos notifications.'})).toBeVisible();
      await expect(page.getByText('Tout est lu !',{exact:true})).toBeHidden();
      await preuveMission(page,info,`${prefix}-notifications-erreur`);
      state.failures.clear();await page.getByRole('button',{name:'Réessayer',exact:true}).click();
      const notification=page.getByRole('button',{name:/Notification fictive de recette/});
      await expect(notification).toBeVisible();
      state.failures.add('notifications:PATCH');await notification.click();
      await expect(page.getByText('Impossible de marquer cette notification comme lue.',{exact:true})).toBeVisible();
      expect(state.notifications[0].lue).toBe(false);
      state.failures.clear();await notification.click();await expect.poll(()=>state.notifications[0].lue).toBe(true);
      state.failures.add('notifications:DELETE');await page.getByRole('button',{name:'Supprimer les lues',exact:true}).click();
      await expect(page.getByText('Impossible de supprimer les notifications.',{exact:true})).toBeVisible();
      await expect(notification).toBeVisible();
      state.failures.clear();await page.getByRole('button',{name:'Supprimer les lues',exact:true}).click();
      await expect(page.getByText('Tout est lu !',{exact:true})).toBeVisible();
      await preuveMission(page,info,`${prefix}-notifications-reprise`);
      expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);
    } finally {await info.attach('journal-communications',{body:JSON.stringify({...state,failures:[...state.failures]},null,2),contentType:'application/json'});}
  });
  test(`${role} : liste des conversations et identités en erreur puis reprise`,async({context,page},info)=>{
    const state=await communicationsSimulees(context,role);page.setDefaultTimeout(12_000);
    await page.clock.setFixedTime(new Date(now));state.failures.add('fn_lister_conversations_messagerie');
    try {
      await page.goto(`/${prefix}/messagerie`);
      const erreur=page.getByRole('alert').filter({hasText:'Impossible de charger vos conversations.'});
      await expect(erreur).toBeVisible();await expect(page.getByText('Aucune conversation',{exact:true})).toBeHidden();
      await preuveMission(page,info,`${prefix}-conversations-erreur`);
      state.failures.clear();state.failures.add('fn_interlocuteurs_conversations');
      await page.getByRole('button',{name:'Réessayer les conversations',exact:true}).click();
      await expect(erreur).toBeVisible();
      state.failures.clear();await page.getByRole('button',{name:'Réessayer les conversations',exact:true}).click();
      await expect(page.getByRole('button',{name:/Dernier échange simulé/})).toContainText(role==='SOIGNANT'?'Clinique Simulation':'Camille Recette');
      await preuveMission(page,info,`${prefix}-conversations-reprise`);
      expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);
    } finally {await info.attach('journal-communications',{body:JSON.stringify({...state,failures:[...state.failures]},null,2),contentType:'application/json'});}
  });
  test(`${role} : historique des messages en erreur puis reprise`,async({context,page},info)=>{
    const state=await communicationsSimulees(context,role);page.setDefaultTimeout(12_000);
    await page.clock.setFixedTime(new Date(now));state.failures.add('messages_chat');
    try {
      await page.goto(`/${prefix}/messagerie?conv=${conversationId}`);
      await expect(page.getByRole('alert').filter({hasText:'Impossible de charger les messages.'})).toBeVisible();
      await expect(page.getByText('Aucun message. Envoyez le premier !',{exact:true})).toBeHidden();
      await preuveMission(page,info,`${prefix}-messages-erreur`);
      state.failures.clear();await page.getByRole('button',{name:'Réessayer les messages',exact:true}).click();
      await expect(page.getByText('Message de recette récupéré après la panne.',{exact:true})).toBeVisible();
      await expect(page).toHaveURL(new RegExp(`conv=${conversationId}`));
      await preuveMission(page,info,`${prefix}-messages-reprise`);
      expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);
    } finally {await info.attach('journal-communications',{body:JSON.stringify({...state,failures:[...state.failures]},null,2),contentType:'application/json'});}
  });
  test(`${role} : conversation peuplée, recherche, retour et archives en lecture seule`,async({context,page},info)=>{
    const state=await communicationsSimulees(context,role);page.setDefaultTimeout(12_000);
    await page.clock.setFixedTime(new Date(now));
    try {
      await page.goto(`/${prefix}/messagerie`);
      const recherche=page.getByRole('textbox',{name:'Rechercher une conversation',exact:true});
      await expect(page.getByRole('button',{name:/Dernier échange simulé/})).toBeVisible();
      await recherche.fill('aucun-correspondant');
      await expect(page.getByText('Aucune conversation ne correspond à votre recherche.',{exact:true})).toBeVisible();
      await recherche.fill('fictive');
      await page.getByRole('button',{name:/Dernier échange simulé/}).click();
      await expect(page.getByText('Message de recette récupéré après la panne.',{exact:true})).toBeVisible();
      await expect(page.getByRole('textbox',{name:'Saisir un message',exact:true})).toBeVisible();
      const envoyer=page.getByRole('button',{name:'Envoyer le message',exact:true});
      await expect(envoyer).toBeDisabled();
      // Un bouton peut être « visible » pour Playwright mais coupé par overflow-hidden.
      expect(await envoyer.evaluate(element=>{
        const rect=element.getBoundingClientRect();
        if(rect.left<0||rect.right>document.documentElement.clientWidth)return false;
        let parent=element.parentElement;
        while(parent){
          const style=getComputedStyle(parent),bounds=parent.getBoundingClientRect();
          if(['hidden','clip','auto','scroll'].includes(style.overflowX)&&(rect.left<bounds.left-1||rect.right>bounds.right+1))return false;
          parent=parent.parentElement;
        }
        return true;
      })).toBe(true);
      await preuveMission(page,info,`${prefix}-conversation-ouverte`);
      if(await page.getByRole('button',{name:'Retour aux conversations',exact:true}).isVisible())
        await page.getByRole('button',{name:'Retour aux conversations',exact:true}).click();
      else await page.goBack();
      await expect(page).not.toHaveURL(/\?conv=/);
      await recherche.clear();
      await page.getByRole('tab',{name:/Archivées/}).click();
      await page.getByRole('button',{name:/Échange archivé simulé/}).click();
      await expect(page).toHaveURL(new RegExp(`conv=${conversationArchiveeId}`));
      await expect(page.getByText('Conversation archivée — lecture seule.',{exact:true})).toBeVisible();
      await expect(page.getByRole('textbox',{name:'Saisir un message',exact:true})).toBeHidden();
      await preuveMission(page,info,`${prefix}-conversation-archivee`);
      expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);
    } finally {await info.attach('journal-communications',{body:JSON.stringify({...state,failures:[...state.failures]},null,2),contentType:'application/json'});}
  });
}
