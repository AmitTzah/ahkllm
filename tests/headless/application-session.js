'use strict';
const fs=require('node:fs');
const path=require('node:path');
const seed=require('./seed');
const launcher=require('./launch');
const {launchApplicationPackage}=require('./application-launcher');
const {showChat,runProbe}=require('./scenarios/helpers');

async function openPreparedApplication(cdp,dataDir,dbPath,id) {
  await showChat();
  const profile={id:'text-example',name:'Text example',command:[launcher.AHK,path.join(launcher.REPO_ROOT,'tests/fixtures/external-application.ahk')],timeout_seconds:5};
  fs.writeFileSync(path.join(dataDir,'applications.json'),JSON.stringify({'text-example':profile}));
  const packagePath=path.join(dataDir,'text-application-package.json');
  fs.writeFileSync(packagePath,JSON.stringify({protocol:'ahkllm.external-applications',version:1,request_id:'text-'+id,application_id:'text-example',title:'Text protocol connection',instructions:'Use the advertised application functions.',initial_input:'EXACT TEXT PREPARED CONTEXT Ω',state:{checkpoint:0},await_first_message:true}));
  const launched=await launchApplicationPackage(packagePath,dataDir,runProbe('chat-info').hwnd);
  if (launched.status!==0) throw new Error(launched.stderr+launched.stdout);
  const threadId=seed.query(dbPath,'SELECT thread_id FROM application_sessions WHERE request_id=?',['text-'+id])[0].thread_id;
  await cdp.waitFor('window.activeThreadId === '+JSON.stringify(threadId)+' && window._applicationState?.awaitingFirstMessage',10000,100,'prepared application opened');
  return threadId;
}
module.exports={openPreparedApplication};
