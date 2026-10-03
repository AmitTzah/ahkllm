/* Preview omissions are display-only. Exact archived bodies are fetched on demand. */
var ApiLogPreview = (function () {
  'use strict';
  function shorten(value) {
    if (typeof value === 'string' && value.length > 4000) {
      return value.slice(0, 1000) + '\n[' + (value.length - 2000) + ' characters omitted from preview]\n' + value.slice(-1000);
    }
    if (Array.isArray(value)) return value.map(shorten);
    if (value && typeof value === 'object') {
      var result = {};
      Object.keys(value).forEach(function (key) { Object.defineProperty(result, key, {value:shorten(value[key]), enumerable:true}); });
      return result;
    }
    return value;
  }
  function format(body) {
    if (typeof body === 'string') {
      try { return JSON.stringify(shorten(JSON.parse(body)), null, 2); }
      catch (_) { return shorten(body); }
    }
    return JSON.stringify(shorten(body), null, 2);
  }
  function fullBody(entry, field) {
    var archive = entry[field + '_archive'];
    return archive ? window.chrome.webview.hostObjects.Logs.GetBody(archive) : Promise.resolve(entry[field]);
  }
  return {format:format, fullBody:fullBody};
})();
