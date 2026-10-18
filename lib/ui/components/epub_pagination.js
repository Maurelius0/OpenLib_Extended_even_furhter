(() => {
  let changingFont = false;
  const viewport = document.getElementById('viewport');
  const book = document.getElementById('book');
  let page = 0, count = 1, offset = 0, startX = 0, startY = 0;
  const nodes = () => {
    const walker = document.createTreeWalker(book, NodeFilter.SHOW_TEXT);
    const result = []; while (walker.nextNode()) { if (!walker.currentNode.parentElement?.closest('style,script')) result.push(walker.currentNode); }
    return result;
  };
  const step = () => viewport.clientWidth + 48;
  const layout = () => [viewport.clientWidth, viewport.clientHeight,
    getComputedStyle(book).fontSize, document.documentElement.dataset.readerFont || 'default'].join(':');
  // Keep publisher styles intact for reset, including inline !important rules.
  const originalFamilies = new WeakMap();
  function applyFont(root) {
    const family = window.readerFontFamily;
    function apply(element) {
      if (element.closest('svg,math,pre,code')) return;
      if (family) {
        if (!originalFamilies.has(element)) originalFamilies.set(element,
          [element.style.getPropertyValue('font-family'), element.style.getPropertyPriority('font-family')]);
        element.style.setProperty('font-family', '"' + family + '", serif', 'important');
      } else if (originalFamilies.has(element)) {
        const [value, priority] = originalFamilies.get(element);
        if (value) element.style.setProperty('font-family', value, priority);
        else element.style.removeProperty('font-family');
        originalFamilies.delete(element);
      }
    }
    apply(root); root.querySelectorAll('*').forEach(apply);
  }
  applyFont(book);
  const pagesFor = element => Math.max(1, Math.ceil((element.scrollWidth + 48) / step()));
  const sectionMarkers = (window.readerSections || []).map((label, index) => ({
    title: label.title, index,
    target: label.anchor ? (document.getElementById(label.anchor) ||
      Array.from(book.querySelectorAll('[name]')).find(e => e.getAttribute('name') === label.anchor)) : null,
    fileLevel: !label.anchor
  })).filter(marker => marker.fileLevel || marker.target);
  let markerLayout = '', markerPages = [];
  function partTitle() {
    const key = layout();
    if (key !== markerLayout) {
      const bounds = viewport.getBoundingClientRect(), scroll = viewport.scrollLeft;
      markerPages = sectionMarkers.map(marker => {
        const rect = marker.target?.getBoundingClientRect();
        return {title: marker.title, index: marker.index,
          page: rect ? Math.max(0, Math.floor((rect.left - bounds.left + scroll + 1) / step())) : 0,
          top: rect ? rect.top : -Infinity};
      }).sort((a, b) => a.page - b.page || a.top - b.top || a.index - b.index);
      markerLayout = key;
    }
    let title = ''; // Unlabelled pages before the first heading stay untitled.
    for (const marker of markerPages) {
      if (marker.page > page) break;
      title = marker.title;
    }
    return title;
  }
  function anchor() {
    let total = 0;
    for (const node of nodes()) {
      const bounds = viewport.getBoundingClientRect();
      const range = document.createRange();
      range.selectNodeContents(node);
      if (!Array.from(range.getClientRects()).some(rect => rect.width &&
          rect.left >= bounds.left - 1 && rect.left < bounds.right &&
          rect.top >= bounds.top - 1 && rect.top < bounds.bottom)) {
        total += node.length; continue;
      }
      let low = 0, high = node.length;
      while (low < high) {
        const mid = Math.floor((low + high) / 2);
        range.setStart(node, mid); range.setEnd(node, mid + 1);
        const rect = range.getBoundingClientRect();
        if (rect.left < bounds.left - 1) low = mid + 1; else high = mid;
      }
      return total + low;
    }
    return offset;
  }
  function report(reading = false) {
    offset = anchor();
    window.flutter_inappwebview?.callHandler('reader', {page, count, offset, reading: reading === true, chapter: window.readerChapter, partTitle: partTitle(), layout: layout()});
  }
  function position(target) {
    viewport.scrollLeft = 0;
    count = pagesFor(book);
    let total = 0;
    page = 0;
    for (const node of nodes()) {
      if (total + node.length > target) {
        const range = document.createRange();
        range.setStart(node, Math.max(0, target - total));
        range.setEnd(node, Math.min(node.length, target - total + 1));
        page = Math.floor((range.getBoundingClientRect().left -
          viewport.getBoundingClientRect().left + 1) / step());
        break;
      }
      total += node.length;
    }
    page = Math.max(0, Math.min(count - 1, page));
    viewport.scrollLeft = page * step();
    requestAnimationFrame(report);
  }
  window.readerGoPage = target => {
    count = pagesFor(book);
    page = Math.max(0, Math.min(count - 1, Math.round(target)));
    viewport.scrollLeft = page * step(); report(true);
  };
  window.readerPreviewPage = target => {
    count = pagesFor(book);
    page = Math.max(0, Math.min(count - 1, Math.round(target)));
    viewport.scrollLeft = page * step();
    window.flutter_inappwebview?.callHandler('reader', {page, count, offset, preview: true,
      reading: false, chapter: window.readerChapter, partTitle: partTitle(), layout: layout()});
  };
  window.readerMeasure = async body => {
    const key = layout();
    const probe = document.createElement('main');
    probe.className = 'reader-section';
    Object.assign(probe.style, {position: 'fixed', left: '-100000px', top: '0',
      width: viewport.clientWidth + 'px', height: viewport.clientHeight + 'px',
      visibility: 'hidden', pointerEvents: 'none'});
    probe.innerHTML = body;
    applyFont(probe);
    document.body.appendChild(probe);
    try {
      await Promise.all(Array.from(probe.querySelectorAll('img')).map(i => i.decode().catch(() => {})));
      await document.fonts.ready;
      await new Promise(resolve => requestAnimationFrame(resolve));
      return {count: pagesFor(probe), layout: key, valid: key === layout()};
    } finally { probe.remove(); }
  };
  window.readerTurn = delta => {
    if (changingFont) return;
    if (page + delta < 0 || page + delta >= count) {
      window.flutter_inappwebview?.callHandler('boundary', delta);
      return;
    }
    page += delta; viewport.scrollLeft = page * step(); report(true);
  };
  window.readerSetFont = async (css, id, family) => {
    changingFont = true;
    try {
    const saved = offset;
    const style = document.getElementById('reader-font-face') ||
      document.head.appendChild(Object.assign(document.createElement('style'), {id: 'reader-font-face'}));
    style.textContent = css;
    document.documentElement.dataset.readerFont = id;
    window.readerFontFamily = family;
    applyFont(book);
    if (family) await document.fonts.load('20px "' + family + '"');
    await document.fonts.ready;
    position(saved);
    await new Promise(resolve => requestAnimationFrame(resolve));
    return true;
    } finally { changingFont = false; }
  };
  window.readerSettings = (size, dark) => {
    const saved = offset;
    document.documentElement.style.setProperty('--size', size + 'px');
    document.documentElement.classList.toggle('dark', dark);
    requestAnimationFrame(() => position(saved));
  };
  window.readerRestore = (target, last, reading = false) => {
    position(target);
    if (last) { page = count - 1; viewport.scrollLeft = page * step(); }
    requestAnimationFrame(() => report(reading));
  };
  window.readerAnchor = id => {
    const target = Array.from(book.querySelectorAll('[id],[name]')).find(e => e.id === id || e.getAttribute('name') === id);
    if (!target) return;
    viewport.scrollLeft = 0;
    count = pagesFor(book);
    page = Math.max(0, Math.min(count - 1, Math.floor((target.getBoundingClientRect().left - viewport.getBoundingClientRect().left + 1) / step())));
    viewport.scrollLeft = page * step();
    report(true);
  };
  let pressTimer, pressedGraphic, suppressUntil = 0;
  const graphic = target => target.closest?.('svg') || target.closest?.('img');
  const cancelPress = () => { clearTimeout(pressTimer); pressedGraphic = null; };
  function graphicTitle(element) {
    const byIds = attribute => (element.getAttribute(attribute) || '').split(/\s+/)
      .map(id => document.getElementById(id)?.textContent || '').join(' ');
    const candidates = [element.getAttribute('title'),
      element.tagName.toLowerCase() === 'svg' ? element.querySelector('title')?.textContent : '',
      element.closest('figure')?.querySelector('figcaption')?.textContent,
      byIds('aria-labelledby'), element.getAttribute('aria-label'),
      byIds('aria-describedby'), element.getAttribute('alt')];
    for (const candidate of candidates) {
      const text = (candidate || '').replace(/\s+/g, ' ').trim();
      if (!text || /^(?:(?:image|img|picture|photo|graphic)(?:[ _-]*\d+)?|illustration|cover)[.!:]?$/i.test(text) ||
          /\.(?:png|jpe?g|gif|svg|webp|avif)$/i.test(text)) continue;
      return text.length > 1000 ? text.slice(0, 999) + '…' : text;
    }
    return '';
  }
  function openGraphic(element) {
    if (!element) return;
    let source;
    if (element.tagName.toLowerCase() === 'svg') {
      const copy = element.cloneNode(true);
      copy.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
      source = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(new XMLSerializer().serializeToString(copy));
    } else source = element.getAttribute('src');
    if (!source?.startsWith('data:image/')) return;
    suppressUntil = Date.now() + 800;
    window.flutter_inappwebview?.callHandler('image', source, graphicTitle(element));
  }
  document.addEventListener('contextmenu', event => {
    event.preventDefault();
    if (Date.now() < suppressUntil) return;
    cancelPress(); openGraphic(graphic(event.target));
  });
  document.addEventListener('click', event => {
    event.preventDefault();
    if (changingFont || Date.now() < suppressUntil || window.getSelection()?.toString()) return;
    const link = event.target.closest?.('[data-reader-target]');
    if (link) { window.flutter_inappwebview?.callHandler('link', link.getAttribute('data-reader-target')); return; }
    const fraction = event.clientX / innerWidth;
    if (fraction < .3) window.readerTurn(-1);
    else if (fraction > .7) window.readerTurn(1);
    else window.flutter_inappwebview?.callHandler('controls');
  });
  document.addEventListener('keydown', event => {
    const link = event.target.closest?.('[data-reader-target]');
    if (link && event.key === 'Enter') { event.preventDefault(); window.flutter_inappwebview?.callHandler('link', link.getAttribute('data-reader-target')); }
  });
  document.addEventListener('touchstart', event => {
    cancelPress();
    startX = event.changedTouches[0].clientX; startY = event.changedTouches[0].clientY;
    if (event.touches.length !== 1) return;
    pressedGraphic = graphic(event.target);
    if (pressedGraphic) pressTimer = setTimeout(() => { openGraphic(pressedGraphic); cancelPress(); }, 500);
  }, {passive: true});
  document.addEventListener('touchmove', event => {
    if (Math.abs(event.changedTouches[0].clientX - startX) > 10 || Math.abs(event.changedTouches[0].clientY - startY) > 10) cancelPress();
  }, {passive: true});
  document.addEventListener('touchcancel', cancelPress, {passive: true});
  document.addEventListener('touchend', event => {
    cancelPress();
    if (Date.now() < suppressUntil) { event.preventDefault(); return; }
    const dx = event.changedTouches[0].clientX - startX;
    const dy = event.changedTouches[0].clientY - startY;
    if (Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy)) {
      event.preventDefault(); suppressUntil = Date.now() + 300; window.readerTurn(dx < 0 ? 1 : -1);
    }
  }, {passive: false});
  let timer;
  window.addEventListener('resize', () => {
    clearTimeout(timer); timer = setTimeout(() => position(offset), 100);
  });
})();
