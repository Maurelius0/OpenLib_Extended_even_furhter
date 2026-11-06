// Deterministic lifecycle fault injection, not an Android compositor emulator.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

function reader(script) {
  const events = new Map(), frames = [], calls = [];
  const viewport = {
    clientWidth: 364, clientHeight: 752, scrollLeft: 0,
    style: {transform: ''},
    getBoundingClientRect: () => ({left: 24, right: 388, top: 12, bottom: 764}),
  };
  const book = {
    scrollWidth: 4000,
    closest: () => null,
    querySelectorAll: () => [],
  };
  const listen = (name, callback) => {
    if (!events.has(name)) events.set(name, []);
    events.get(name).push(callback);
  };
  const document = {
    hidden: false,
    documentElement: {dataset: {}},
    getElementById: id => id === 'viewport' ? viewport : book,
    createTreeWalker: () => ({nextNode: () => false}),
    addEventListener: listen,
  };
  const window = {
    readerChapter: 2,
    flutter_inappwebview: {callHandler: (...args) => calls.push(args)},
    addEventListener: listen,
  };
  vm.runInNewContext(script, {
    document, window, NodeFilter: {SHOW_TEXT: 4},
    getComputedStyle: () => ({fontSize: '20px'}),
    requestAnimationFrame: callback => frames.push(callback),
    setTimeout, clearTimeout,
  });
  return {
    viewport, document, window, calls,
    emit: name => (events.get(name) || []).forEach(callback => callback()),
    frame: () => frames.splice(0).forEach(callback => callback()),
    pending: () => frames.length,
  };
}

const scriptPath = process.argv[2] || path.join(__dirname,
  '../lib/ui/components/epub_pagination.js');
const script = fs.readFileSync(scriptPath, 'utf8');

// Model the native layer returning with its scroll position lost. The same
// live page must become visible without a tap, reload, or reading activity.
{
  const r = reader(script);
  r.window.readerGoPage(3);
  const expected = r.viewport.scrollLeft;
  r.document.hidden = true;
  r.emit('visibilitychange');
  r.viewport.scrollLeft = 0;
  r.calls.length = 0;
  r.document.hidden = false;
  r.emit('visibilitychange');
  r.emit('focus');
  r.emit('pageshow');
  r.frame(); r.frame();
  assert.equal(r.viewport.scrollLeft, expected, 'unlock must restore live page');
  assert.equal(r.viewport.style.transform, '', 'temporary compositing style must be removed');
  assert.equal(r.calls.length, 0, 'resume must not turn pages, open controls or record reading');
  r.window.readerTurn(1);
  assert.equal(r.calls.at(-1)[1].page, 4, 'normal navigation survives resume');
  console.log('PASS unlock restores live page without input or reading activity');
}

{
  const r = reader(script);
  r.window.readerGoPage(2);
  r.calls.length = 0;
  r.document.hidden = true;
  r.viewport.clientWidth = 0;
  r.viewport.clientHeight = 0;
  r.window.readerRestore(0, false);
  r.frame();
  assert.equal(r.calls.length, 0, 'hidden layout must not overwrite reading position');
  r.document.hidden = false;
  r.viewport.clientWidth = 364;
  r.viewport.clientHeight = 752;
  r.viewport.scrollLeft = 0;
  r.emit('focus');
  r.frame(); r.frame();
  assert.equal(r.viewport.scrollLeft, 0, 'restore requested while hidden runs once visible');
  assert.equal(r.calls.at(-1)[1].reading, false);
  console.log('PASS hidden layout cannot save position; deferred loading restores on unlock');
}

{
  const r = reader(script);
  r.window.readerGoPage(2);
  r.viewport.style.transform = 'translateX(0px)';
  for (let i = 0; i < 20; i++) {
    r.emit('focus'); r.emit('pageshow');
  }
  assert.equal(r.pending(), 1, 'focus events must coalesce');
  r.document.hidden = true;
  r.frame();
  assert.equal(r.pending(), 0, 'relocking cancels pending refresh');
  r.document.hidden = false;
  r.emit('visibilitychange');
  r.frame(); r.frame();
  assert.equal(r.viewport.style.transform, 'translateX(0px)');
  assert.equal(r.pending(), 0, 'no continuous redraw loop');
  console.log('PASS repeated focus, rapid relock, style preservation and no redraw loop');
}
