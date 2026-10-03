// Generic local applications; saved independently through the connection controls.
(function () {
  'use strict';
  var sectionName = 'applications';
  var S = window.SettingsShared;
  var connections = [];
  var editingId = '';
  var saving = false;
  var previousFocus = null;

  function status(message, error) {
    var modal = document.getElementById('applicationEditor');
    var element = document.getElementById(modal.classList.contains('open') ? 'applicationEditorStatus' : 'applicationSettingsStatus');
    if (element) {
      element.textContent = message || '';
      element.style.color = error ? '#b42318' : '';
    }
  }

  function request(action, payload) {
    return window.Ipc.request(action, payload || {}).catch(function (error) {
      status(error.message || 'The application connection could not be updated.', true);
      throw error;
    });
  }

  function load() {
    wire();
    request('requestApplicationConnections').catch(function () {});
  }

  function save() { return {}; }

  function fill(profile) {
    previousFocus = document.activeElement;
    editingId = profile ? profile.id : '';
    S.setVal('applicationId', editingId);
    S.setVal('applicationName', profile ? profile.name : '');
    S.setVal('applicationProgram', profile ? profile.command[0] : '');
    S.setVal('applicationArguments', profile ? profile.command.slice(1).join('\n') : '');
    S.setVal('applicationWorkingDirectory', profile ? profile.working_directory : '');
    S.setVal('applicationTimeout', profile ? profile.timeout_seconds : 60);
    document.getElementById('applicationId').disabled = !!editingId;
    document.getElementById('applicationAdvanced').open = !!(profile && (profile.command.length > 1 || profile.working_directory || profile.timeout_seconds !== 60));
    document.getElementById('applicationEditor').classList.add('open');
    document.getElementById('applicationEditorTitle').textContent = editingId ? 'Edit connection' : 'Add application';
    status('');
    document.getElementById('applicationName').focus();
  }

  function closeEditor() {
    if (saving) return;
    document.getElementById('applicationEditor').classList.remove('open');
    hideHelp();
    var target = previousFocus && previousFocus.isConnected && previousFocus.offsetParent !== null ? previousFocus : document.getElementById(connections.length ? 'addApplicationConnection' : 'addApplicationEmpty');
    if (target && typeof target.focus === 'function') target.focus();
  }

  function readProfile() {
    var id = S.getVal('applicationId').trim();
    var name = S.getVal('applicationName').trim();
    var program = S.getVal('applicationProgram').trim();
    var timeout = Number(S.getVal('applicationTimeout'));
    if (!/^[a-z0-9][a-z0-9._-]{0,79}$/.test(id)) throw new Error('Use a connection ID containing lowercase letters, numbers, dots, underscores, or hyphens.');
    if (!name || !program) throw new Error('Enter an application name and program.');
    if (!Number.isInteger(timeout) || timeout < 1 || timeout > 300) throw new Error('Timeout must be a whole number from 1 to 300 seconds.');
    if (!editingId && connections.some(function (item) { return item.id === id; })) throw new Error('That connection ID already exists. Edit its connection instead.');
    return {id: id, name: name, command: [program].concat(S.getVal('applicationArguments').split(/\r?\n/).filter(function (line) { return line !== ''; })), working_directory: S.getVal('applicationWorkingDirectory').trim(), timeout_seconds: timeout};
  }

  function saveConnection() {
    if (saving) return Promise.resolve();
    var profile;
    try { profile = readProfile(); }
    catch (error) { status(error.message, true); return Promise.resolve(); }
    saving = true;
    var button = document.getElementById('saveApplicationConnection');
    button.disabled = true;
    return request('saveApplicationConnection', {profile: profile}).then(function () {
      saving = false;
      closeEditor();
      status('Connection saved.');
    }).catch(function () {}).finally(function () { saving = false; button.disabled = false; });
  }

  function disconnect(profile) {
    if (!window.confirm('Disconnect ' + profile.name + '? Existing chats will remain readable. Reconnect this application to resume its tools.')) return;
    request('disconnectApplicationConnection', {id: profile.id}).then(function () {
      if (editingId === profile.id) closeEditor();
      status('Application disconnected. Chats were kept.');
    }).catch(function () {});
  }

  function receive(data) {
    connections = data && data.connections || [];
    var list = document.getElementById('applicationConnections');
    if (!list) return;
    list.replaceChildren();
    document.getElementById('applicationConnectionsEmpty').style.display = connections.length ? 'none' : '';
    document.getElementById('addApplicationConnection').style.display = connections.length ? '' : 'none';
    document.getElementById('applicationConnectionsCount').textContent = connections.length + (connections.length === 1 ? ' application connected' : ' applications connected');
    connections.forEach(function (profile) {
      var card = document.createElement('div');
      card.className = 'application-connection-card';
      var icon = document.createElement('div'); icon.className = 'application-connection-icon'; icon.textContent = profile.name.slice(0, 2).toUpperCase(); icon.setAttribute('aria-hidden', 'true');
      var info = document.createElement('div'); info.className = 'application-connection-info';
      var name = document.createElement('strong'); name.className = 'application-connection-name'; name.textContent = profile.name;
      var details = document.createElement('div');
      details.className = 'application-connection-details';
      details.textContent = profile.id + ' · ' + profile.chat_count + (profile.chat_count === 1 ? ' chat' : ' chats');
      var program = document.createElement('div'); program.className = 'application-connection-program'; program.textContent = profile.command[0]; program.title = profile.command[0];
      var edit = document.createElement('button'); edit.className = 'btn-sm'; edit.textContent = 'Edit'; edit.onclick = function () { fill(profile); };
      var remove = document.createElement('button'); remove.className = 'btn-sm danger'; remove.textContent = 'Disconnect'; remove.onclick = function () { disconnect(profile); };
      var actions = document.createElement('div'); actions.className = 'application-connection-actions'; actions.append(edit, remove);
      info.append(name, details, program); card.append(icon, info, actions); list.appendChild(card);
    });
  }

  function wire() {
    var add = document.getElementById('addApplicationConnection');
    if (!add || add.dataset.wired) return;
    add.dataset.wired = 'true';
    add.onclick = function () { fill(null); };
    document.getElementById('addApplicationEmpty').onclick = add.onclick;
    document.getElementById('applicationConnectionForm').onsubmit = function (event) { event.preventDefault(); saveConnection(); };
    document.getElementById('cancelApplicationConnection').onclick = closeEditor;
    document.getElementById('closeApplicationConnection').onclick = closeEditor;
    document.getElementById('browseApplicationProgram').onclick = function () { request('browseApplicationProgram').catch(function () {}); };
    document.getElementById('showApplicationGuide').onclick = function () {
      document.getElementById('applicationGuide').classList.add('open');
      document.getElementById('closeApplicationGuide').focus();
    };
    document.getElementById('closeApplicationGuide').onclick = closeGuide;
    document.getElementById('applicationGuideDone').onclick = closeGuide;
    wireModal('applicationGuide', closeGuide);
    wireModal('applicationEditor', closeEditor);
    var modal = document.getElementById('applicationEditor');
    modal.querySelectorAll('.application-help').forEach(function (button) {
      button.addEventListener('mouseenter', function () { showHelp(button); });
      button.addEventListener('focus', function () { showHelp(button); });
      button.addEventListener('mouseleave', hideHelp);
      button.addEventListener('blur', hideHelp);
    });
    modal.addEventListener('scroll', hideHelp, true);
  }

  function closeGuide() {
    document.getElementById('applicationGuide').classList.remove('open');
    document.getElementById('showApplicationGuide').focus();
  }

  function wireModal(id, close) {
    var modal = document.getElementById(id);
    modal.onclick = function (event) { if (event.target === modal) close(); };
    modal.addEventListener('keydown', function (event) {
      if (event.key === 'Escape') { event.preventDefault(); close(); }
      if (event.key !== 'Tab') return;
      var targets = Array.from(modal.querySelectorAll('button:not(:disabled), input:not(:disabled), textarea, summary, [tabindex="0"]')).filter(function (element) { return element.offsetParent !== null; });
      if (!targets.length) return;
      var first = targets[0], last = targets[targets.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    });
  }

  function hideHelp() {
    var tooltip = document.getElementById('applicationHelpTooltip');
    if (tooltip) tooltip.style.display = 'none';
  }

  function showHelp(button) {
    var tooltip = document.getElementById('applicationHelpTooltip');
    tooltip.textContent = button.dataset.tip;
    tooltip.style.display = 'block';
    var anchor = button.getBoundingClientRect(), box = tooltip.getBoundingClientRect();
    tooltip.style.left = Math.max(12, Math.min(anchor.left, window.innerWidth - box.width - 12)) + 'px';
    tooltip.style.top = (anchor.top - box.height - 8 >= 12 ? anchor.top - box.height - 8 : Math.min(anchor.bottom + 8, window.innerHeight - box.height - 12)) + 'px';
    button.setAttribute('aria-describedby', 'applicationHelpTooltip');
  }

  window.SettingsApplications = {receive: receive, readProfile: readProfile, saveConnection: saveConnection, closeEditor: closeEditor, programSelected: function (data) { S.setVal('applicationProgram', data.path); }};
  S.registerSection(sectionName, {load: load, save: save});
})();
