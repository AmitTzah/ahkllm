// Update account-owned rows without rebuilding unrelated, possibly edited rows.
(function() {
  function isPlanModel(id, metadata) {
    return /^(chatgpt|codex)\//.test(id || '') || /^(chatgpt|codex)$/.test((metadata || {}).provider || '');
  }

  function replaceRows(tableId, catalog, createRow) {
    var tbody = document.getElementById(tableId);
    if (!tbody) return;
    tbody.querySelectorAll('tr').forEach(function(row) {
      var id = (row.querySelector('[data-field="id"]') || {}).value || '';
      var provider = (row.querySelector('[data-field="provider"]') || {}).value || '';
      if (isPlanModel(id, { provider: provider })) row.remove();
    });
    Object.keys(catalog).forEach(function(id) {
      var placeholder = tbody.querySelector('td[colspan]');
      if (placeholder) placeholder.parentElement.remove();
      tbody.appendChild(createRow(id, catalog[id]));
    });
  }

  window.ChatGptModelCatalogUi = { isPlanModel: isPlanModel, replaceRows: replaceRows };
})();
