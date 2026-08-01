// reasoning-levels.js — shared frontend helpers for reasoning/thinking levels.
// Single source of truth for level labels and least→most ordering used by the
// settings UIs (e.g. the assistant reasoning dropdown). Keeps the label/order
// maps out of individual settings sections so they aren't duplicated.
window.ReasoningLevels = (function() {
  var LABELS = { none: 'None (Disabled)', minimal: 'Minimal', low: 'Low', medium: 'Medium', high: 'High', xhigh: 'Extra High', max: 'Max' };
  var ORDER = { none: 0, minimal: 1, low: 2, medium: 3, high: 4, xhigh: 5, max: 6 };
  var FALLBACK = ['none', 'minimal', 'low', 'medium', 'high'];

  function label(level) { return LABELS[level] || level; }

  // Sort reasoning levels least → most thinking.
  function sortLevels(levels) {
    return (levels || []).slice().sort(function(a, b) {
      var oa = (ORDER[a] !== undefined) ? ORDER[a] : 99;
      var ob = (ORDER[b] !== undefined) ? ORDER[b] : 99;
      return oa - ob;
    });
  }

  // Levels a model supports (from its thinkingLevelMap), or a safe fallback.
  function levelsForModel(models, baseModel) {
    if (models && baseModel && models[baseModel] && models[baseModel].thinkingLevelMap) {
      return Object.keys(models[baseModel].thinkingLevelMap);
    }
    return FALLBACK.slice();
  }

  // Build <option> HTML for a reasoning dropdown: "Model Default" + the
  // model's supported levels, sorted least → most thinking.
  function buildOptionsHtml(models, baseModel) {
    return buildOptionsHtmlForValues(levelsForModel(models, baseModel));
  }

  // Build <option> HTML from an explicit list of level values (already
  // model-scoped by the caller), labeled and sorted least → most thinking.
  function buildOptionsHtmlForValues(values) {
    var html = '<option value="">Model Default</option>';
    sortLevels(values || []).forEach(function(level) {
      html += '<option value="' + level + '">' + label(level) + '</option>';
    });
    return html;
  }

  return {
    label: label,
    sortLevels: sortLevels,
    levelsForModel: levelsForModel,
    buildOptionsHtml: buildOptionsHtml,
    buildOptionsHtmlForValues: buildOptionsHtmlForValues
  };
})();
