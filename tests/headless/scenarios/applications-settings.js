'use strict';
const fs = require('node:fs');
const path = require('node:path');
const {DatabaseSync} = require('node:sqlite');
const launcher = require('../launch');
const seed = require('../seed');
const {showChat, openSettings, openSection} = require('./helpers');

module.exports = [{
  id: 368,
  name: 'Applications settings visibly add, edit, persist, and disconnect a generic connection while retaining chats',
  regression: true,
  mode: null,
  settings: {threadTitles: {enabled: false}},
  fixtures: {threads:[{id:'t-app-settings-368',title:'Retained application chat',active_leaf_id:'u-app-settings-368'}],messages:[{id:'u-app-settings-368',thread_id:'t-app-settings-368',role:'user',content:'Retained conversation'}]},
  async body({cdp, dataDir, dbPath}) {
    await showChat();
    await openSettings(cdp);
    await openSection(cdp, 'applications');
    await cdp.waitFor('document.getElementById("applicationConnectionsEmpty").style.display !== "none"', 10000, 100, 'empty Applications tab');
    if (await cdp.eval('document.getElementById("addApplicationConnection").offsetParent !== null')) throw new Error('Empty state has duplicate Add controls');
    await cdp.click('#showApplicationGuide');
    const guide = await cdp.eval('(() => { const modal=document.getElementById("applicationGuide"); const box=modal.querySelector(".modal-box").getBoundingClientRect(); const text=modal.textContent; return modal.classList.contains("open") && box.width<=720 && text.includes("system message") && text.includes("sent separately") && text.includes("does not automatically undo") && text.includes("Run prepared request"); })()');
    if (!guide) throw new Error('Applications guide is missing readable instructions');
    const guideShot=await cdp.send('Page.captureScreenshot',{format:'png'});
    fs.writeFileSync(path.join(launcher.REPO_ROOT,'.tools','applications-guide-smoke.png'),Buffer.from(guideShot.data,'base64'));
    const guideKeyboard = await cdp.eval('(() => { const modal=document.getElementById("applicationGuide"); document.getElementById("applicationGuideDone").focus(); modal.dispatchEvent(new KeyboardEvent("keydown",{key:"Tab",bubbles:true,cancelable:true})); const trapped=document.activeElement.id==="closeApplicationGuide"; modal.dispatchEvent(new KeyboardEvent("keydown",{key:"Escape",bubbles:true,cancelable:true})); return trapped && !modal.classList.contains("open") && document.activeElement.id==="showApplicationGuide"; })()');
    if (!guideKeyboard) throw new Error('Applications guide keyboard navigation failed');
    await cdp.click('#showApplicationGuide');
    await cdp.click('#applicationGuideDone');
    if (await cdp.eval('document.getElementById("applicationGuide").classList.contains("open")')) throw new Error('Got it did not close guide');
    // cdp.click invokes click() without the focus change of a physical pointer click.
    await cdp.eval('document.getElementById("addApplicationEmpty").focus(); true');
    await cdp.click('#addApplicationEmpty');
    await cdp.waitFor('document.getElementById("applicationEditor").classList.contains("open")', 10000, 100, 'connection modal');
    const layout = await cdp.eval('(() => { const box=document.querySelector("#applicationEditor .modal-box").getBoundingClientRect(); const input=document.getElementById("applicationName"); return {width:box.width, viewport:innerWidth, padding:getComputedStyle(input).paddingLeft, tooltipCount:document.querySelectorAll("#applicationEditor .application-help[data-tip]").length, advancedOpen:document.getElementById("applicationAdvanced").open}; })()');
    if (layout.width > 650 || layout.width > layout.viewport - 16 || parseFloat(layout.padding) < 8 || layout.tooltipCount !== 6 || layout.advancedOpen) throw new Error('Connection dialog layout/help inconsistent: '+JSON.stringify(layout));
    // An inactive WebView changes activeElement without emitting native focus events.
    // Exercise the same focus handler explicitly in the isolated background worker.
    await cdp.eval('document.querySelector("#applicationEditor .application-help").focus(); document.querySelector("#applicationEditor .application-help").dispatchEvent(new FocusEvent("focus")); true');
    try {
      await cdp.waitFor('document.getElementById("applicationHelpTooltip")?.textContent.includes("friendly name") && document.getElementById("applicationHelpTooltip").style.display !== "none"', 5000, 100, 'keyboard-focus field help');
    } catch(error) {
      const shot=await cdp.send('Page.captureScreenshot',{format:'png'});
      fs.writeFileSync(path.join(launcher.REPO_ROOT,'.tools','applications-dialog-smoke.png'),Buffer.from(shot.data,'base64'));
      throw new Error(error.message+': '+await cdp.eval('JSON.stringify({active:document.activeElement?.outerHTML,tip:document.getElementById("applicationHelpTooltip")?.outerHTML})'));
    }
    const keyboard = await cdp.eval('(() => { const modal=document.getElementById("applicationEditor"); document.getElementById("saveApplicationConnection").focus(); modal.dispatchEvent(new KeyboardEvent("keydown",{key:"Tab",bubbles:true,cancelable:true})); const trapped=document.activeElement.id==="closeApplicationConnection"; modal.dispatchEvent(new KeyboardEvent("keydown",{key:"Escape",bubbles:true,cancelable:true})); return {trapped,closed:!modal.classList.contains("open"),returned:document.activeElement.id==="addApplicationEmpty",helpHidden:document.getElementById("applicationHelpTooltip").style.display==="none"}; })()');
    if (!Object.values(keyboard).every(Boolean)) throw new Error('Connection dialog keyboard behavior failed: '+JSON.stringify(keyboard));
    await cdp.click('#addApplicationEmpty');
    await cdp.send('Emulation.setDeviceMetricsOverride',{width:480,height:640,deviceScaleFactor:1,mobile:false});
    const narrow = await cdp.eval('(() => { const box=document.querySelector("#applicationEditor .modal-box").getBoundingClientRect(); return box.left>=0 && box.right<=innerWidth && box.height<=innerHeight && getComputedStyle(document.querySelector(".application-field-grid")).gridTemplateColumns.split(" ").length===1; })()');
    if (!narrow) throw new Error('Connection dialog overflowed its narrow viewport');
    await cdp.send('Emulation.clearDeviceMetricsOverride');
    await cdp.eval('document.getElementById("applicationAdvanced").open=true; true');
    await cdp.type('#applicationName', 'Example application');
    await cdp.type('#applicationId', 'ui-example');
    await cdp.type('#applicationProgram', launcher.AHK);
    const adapter = path.join(launcher.REPO_ROOT, 'tests/fixtures/external-application.ahk');
    await cdp.type('#applicationArguments', adapter);
    const capture = await cdp.send('Page.captureScreenshot', {format:'png'});
    fs.writeFileSync(path.join(launcher.REPO_ROOT,'.tools','applications-dialog-smoke.png'), Buffer.from(capture.data,'base64'));
    await cdp.click('#saveApplicationConnection');
    await cdp.waitFor('document.getElementById("applicationConnections").textContent.includes("Example application") && !document.getElementById("applicationEditor").classList.contains("open")', 10000, 100, 'saved application card');
    if (!await cdp.eval('document.getElementById("addApplicationConnection").offsetParent !== null && document.getElementById("addApplicationEmpty").offsetParent === null')) throw new Error('Connected state does not have one visible Add control');
    await cdp.click('#addApplicationConnection');
    await cdp.click('#cancelApplicationConnection');
    const profilesPath = path.join(dataDir, 'applications.json');
    let profiles = JSON.parse(fs.readFileSync(profilesPath, 'utf8'));
    if (profiles['ui-example'].command[1] !== adapter) throw new Error('Settings did not preserve the command argument');
    const db = new DatabaseSync(dbPath);
    try {
      db.prepare('INSERT INTO application_sessions(thread_id,application_id,initial_state,request_id) VALUES(?,?,?,?)').run('t-app-settings-368','ui-example','{"checkpoint":0}','request-368');
    } finally { db.close(); }
    await cdp.eval('window.Ipc.request("requestApplicationConnections", {}); true');
    await cdp.waitFor('document.getElementById("applicationConnections").textContent.includes("1 chat")', 10000, 100, 'application chat count');
    await cdp.eval('Array.from(document.querySelectorAll("#applicationConnections button")).find(b=>b.textContent==="Edit").click(); true');
    const lockedId = await cdp.eval('document.getElementById("applicationId").disabled');
    if (!lockedId) throw new Error('Editing allowed the stable connection ID to change');
    await cdp.eval('document.getElementById("applicationName").value="Renamed application"; document.getElementById("applicationTimeout").value="45"; true');
    await cdp.click('#saveApplicationConnection');
    await cdp.waitFor('document.getElementById("applicationConnections").textContent.includes("Renamed application")', 10000, 100, 'renamed connection persisted');
    profiles = JSON.parse(fs.readFileSync(profilesPath, 'utf8'));
    if (profiles['ui-example'].timeout_seconds !== 45) throw new Error('Edited timeout did not persist');
    await cdp.eval('window.confirm=()=>true; Array.from(document.querySelectorAll("#applicationConnections button")).find(b=>b.textContent==="Disconnect").click(); true');
    await cdp.waitFor('document.getElementById("applicationConnectionsEmpty").style.display !== "none"', 10000, 100, 'connection disconnected');
    profiles = JSON.parse(fs.readFileSync(profilesPath, 'utf8'));
    if (profiles['ui-example']) throw new Error('Disconnected registration remained on disk');
    if (!seed.query(dbPath, "SELECT id FROM messages WHERE thread_id='t-app-settings-368'").length) throw new Error('Disconnect deleted historical messages');
    return 'Settings tab, add/edit persistence, argument boundaries, stable ID, chat count, and disconnect retention verified';
  }
}];
