// Мост «Telegram Mini App → iOS-приложение».
// Игра написана для Telegram и обращается к window.Telegram.WebApp. В приложении Telegram нет,
// поэтому здесь тот же объект, но всё уходит в iOS: вибрация, окна, ссылки, кнопка «Назад», тема.
// Вход — токеном приложения (заголовок Authorization), который сервер проверяет так же, как подпись Telegram.
(() => {
  const C = window.__GOS_CFG || {};
  const post = (m) => { try { window.webkit.messageHandlers.gos.postMessage(m); } catch (e) {} };

  // ---- запросы к своему серверу идут с токеном приложения ----
  const _fetch = window.fetch.bind(window);
  window.fetch = (input, init) => {
    try {
      const url = new URL(typeof input === 'string' ? input : (input && input.url) || String(input), location.href);
      if (url.origin === location.origin && C.token) {
        init = Object.assign({}, init || {});
        const h = new Headers(init.headers || (input instanceof Request ? input.headers : undefined));
        h.set('Authorization', 'Bearer ' + C.token);
        h.delete('x-init-data');
        init.headers = h;
      }
    } catch (e) {}
    return _fetch(input, init);
  };

  // ---- ответы из iOS (окна подтверждения и т. п.) ----
  let seq = 0; const waits = {};
  window.__gosCb = (id, v) => { const f = waits[id]; delete waits[id]; if (f) try { f(v); } catch (e) {} };
  const ask = (m, cb) => { const id = ++seq; waits[id] = cb || (() => {}); m.id = id; post(m); };

  // ---- события ----
  const ev = {};
  const emit = (n, ...a) => (ev[n] || []).slice().forEach(f => { try { f(...a); } catch (e) {} });

  // ---- тема как в Telegram для iOS ----
  const THEMES = {
    light: { bg_color: '#ffffff', secondary_bg_color: '#efeff4', text_color: '#000000', hint_color: '#8e8e93', link_color: '#007aff', button_color: '#007aff', button_text_color: '#ffffff',
      section_bg_color: '#ffffff', header_bg_color: '#f8f8f8', bottom_bar_bg_color: '#f2f2f2', accent_text_color: '#007aff', section_header_text_color: '#6d6d72', subtitle_text_color: '#8e8e93',
      destructive_text_color: '#ff3b30', section_separator_color: '#c8c7cc' },
    dark: { bg_color: '#000000', secondary_bg_color: '#1c1c1d', text_color: '#ffffff', hint_color: '#98989e', link_color: '#3e88f7', button_color: '#3e88f7', button_text_color: '#ffffff',
      section_bg_color: '#2c2c2e', header_bg_color: '#1a1a1a', bottom_bar_bg_color: '#1d1d1d', accent_text_color: '#3e88f7', section_header_text_color: '#8d8e93', subtitle_text_color: '#98989e',
      destructive_text_color: '#eb5545', section_separator_color: '#38383a' },
  };
  let dark = !!C.dark;

  // ---- кнопка «Назад»: её рисует iOS, когда игра просит показать кнопку Telegram ----
  const backH = [];
  const BackButton = {
    isVisible: false,
    show() { this.isVisible = true; syncBack(); return this; },
    hide() { this.isVisible = false; syncBack(); return this; },
    onClick(f) { if (typeof f === 'function') backH.push(f); return this; },
    offClick(f) { const i = backH.indexOf(f); if (i >= 0) backH.splice(i, 1); return this; },
  };
  let lastBack = null;
  function syncBack() {
    let v = BackButton.isVisible;
    // у внутренних страниц игра рисует свою круглую кнопку «назад» — вторую не показываем
    if (document.body && document.body.classList.contains('sub-h')) v = false;
    // корень вкладки (например, «Номера»): «назад» увёл бы на главную, а она — соседняя вкладка
    try { if (C.route && C.route !== 'home' && typeof S !== 'undefined' && S.stack && S.stack.length <= 2 && S.stack[S.stack.length - 1] === C.route) v = false; } catch (e) {}
    if (v !== lastBack) { lastBack = v; post({ t: 'back', v }); }
  }
  window.__gosBack = () => {
    try { if (document.querySelector('.sheet:not(.closing)') && typeof closeSheets === 'function') { closeSheets(); return; } } catch (e) {}
    backH.slice().forEach(f => { try { f(); } catch (e) {} });
  };

  const noop = function () {};
  const dummyBtn = () => ({ isVisible: false, isActive: true, text: '', show() { return this; }, hide() { return this; }, onClick() { return this; }, offClick() { return this; },
    setText() { return this; }, setParams() { return this; }, enable() { return this; }, disable() { return this; }, showProgress() { return this; }, hideProgress() { return this; } });
  const csKey = (k) => 'cs_' + k;
  const ls = { get: (k) => { try { return localStorage.getItem(csKey(k)); } catch (e) { return null; } }, set: (k, v) => { try { localStorage.setItem(csKey(k), String(v)); } catch (e) {} }, del: (k) => { try { localStorage.removeItem(csKey(k)); } catch (e) {} } };
  const later = (f) => setTimeout(f, 0);
  const VER = '7.7';
  const verGE = (a, b) => { const x = String(a).split('.').map(Number), y = String(b).split('.').map(Number); for (let i = 0; i < 3; i++) { const d = (x[i] || 0) - (y[i] || 0); if (d) return d > 0; } return true; };
  const open = (url) => { if (url) post({ t: 'open', url: String(url) }); };

  const WebApp = {
    initData: 'inapp',
    initDataUnsafe: { user: C.user || {}, start_param: 'inapp', auth_date: Math.floor(Date.now() / 1000) },
    version: VER, platform: 'ios', colorScheme: dark ? 'dark' : 'light', themeParams: dark ? THEMES.dark : THEMES.light,
    isExpanded: true, isFullscreen: false, isActive: true, isClosingConfirmationEnabled: false, isVerticalSwipesEnabled: false,
    headerColor: '#efeff4', backgroundColor: '#efeff4', bottomBarColor: '#efeff4',
    get viewportHeight() { return window.innerHeight; }, get viewportStableHeight() { return window.innerHeight; },
    safeAreaInset: { top: 0, bottom: 0, left: 0, right: 0 }, contentSafeAreaInset: { top: 0, bottom: 0, left: 0, right: 0 },
    BackButton, MainButton: dummyBtn(), SecondaryButton: dummyBtn(), SettingsButton: dummyBtn(),
    HapticFeedback: {
      impactOccurred(s) { post({ t: 'haptic', k: 'impact', s: s || 'light' }); return this; },
      notificationOccurred(s) { post({ t: 'haptic', k: 'notify', s: s || 'success' }); return this; },
      selectionChanged() { post({ t: 'haptic', k: 'select' }); return this; },
    },
    CloudStorage: {
      setItem(k, v, cb) { ls.set(k, v); if (cb) later(() => cb(null, true)); return this; },
      getItem(k, cb) { const v = ls.get(k); if (cb) later(() => cb(null, v == null ? '' : v)); return this; },
      getItems(ks, cb) { const o = {}; (ks || []).forEach(k => { const v = ls.get(k); o[k] = v == null ? '' : v; }); if (cb) later(() => cb(null, o)); return this; },
      removeItem(k, cb) { ls.del(k); if (cb) later(() => cb(null, true)); return this; },
      removeItems(ks, cb) { (ks || []).forEach(ls.del); if (cb) later(() => cb(null, true)); return this; },
      getKeys(cb) { const out = []; try { for (let i = 0; i < localStorage.length; i++) { const k = localStorage.key(i); if (k && k.startsWith('cs_')) out.push(k.slice(3)); } } catch (e) {} if (cb) later(() => cb(null, out)); return this; },
    },
    isVersionAtLeast: (v) => verGE(VER, v),
    ready: noop, expand: noop, requestFullscreen: noop, exitFullscreen: noop, disableVerticalSwipes: noop, enableVerticalSwipes: noop,
    setHeaderColor: noop, setBackgroundColor: noop, setBottomBarColor: noop, enableClosingConfirmation: noop, disableClosingConfirmation: noop,
    lockOrientation: noop, unlockOrientation: noop, sendData: noop,
    onEvent(n, f) { (ev[n] = ev[n] || []).push(f); }, offEvent(n, f) { const a = ev[n] || []; const i = a.indexOf(f); if (i >= 0) a.splice(i, 1); },
    openLink(url) { open(url); }, openTelegramLink(url) { open(url); },
    openInvoice(url, cb) { open(url); if (cb) later(() => cb('pending')); },
    downloadFile(p) { open(p && p.url); },
    switchInlineQuery(q) { open('https://t.me/share/url?url=' + encodeURIComponent('https://t.me/' + (C.bot || 'GosnomerGame')) + '&text=' + encodeURIComponent('@' + (C.bot || 'GosnomerGame') + ' ' + (q || ''))); },
    showAlert(message, cb) { ask({ t: 'alert', message: String(message || '') }, () => cb && cb()); },
    showConfirm(message, cb) { ask({ t: 'confirm', message: String(message || '') }, (v) => cb && cb(!!v)); },
    showPopup(p, cb) { p = p || {}; ask({ t: 'popup', title: p.title || '', message: p.message || '', buttons: (p.buttons || [{ type: 'close' }]).map(b => ({ id: b.id || '', type: b.type || 'default', text: b.text || '' })) }, (id) => cb && cb(id)); },
    close() { post({ t: 'close' }); },
    // shareMessage, shareToStory, эмодзи-статус, сканер QR и биометрия работают только внутри Telegram —
    // их нет, и игра сама показывает запасной вариант
  };
  window.Telegram = { WebApp, Utils: {}, WebView: { initParams: {}, isIframe: false, onEvent: noop, offEvent: noop, postEvent: noop, receiveEvent: noop, callEventCallbacks: noop } };

  function applyTheme() {
    const t = dark ? THEMES.dark : THEMES.light, st = document.documentElement && document.documentElement.style;
    WebApp.themeParams = t; WebApp.colorScheme = dark ? 'dark' : 'light';
    if (!st) return;
    for (const k in t) st.setProperty('--tg-theme-' + k.replace(/_/g, '-'), t[k]);
    st.setProperty('--tg-color-scheme', WebApp.colorScheme);
    ['--tg-safe-area-inset-top', '--tg-safe-area-inset-bottom', '--tg-safe-area-inset-left', '--tg-safe-area-inset-right',
      '--tg-content-safe-area-inset-top', '--tg-content-safe-area-inset-bottom'].forEach(v => st.setProperty(v, '0px'));
    st.setProperty('--tg-viewport-height', window.innerHeight + 'px'); st.setProperty('--tg-viewport-stable-height', window.innerHeight + 'px');
  }
  applyTheme();
  window.__gosTheme = (d) => { dark = !!d; applyTheme(); emit('themeChanged'); };
  window.addEventListener('resize', () => { applyTheme(); emit('viewportChanged', { isStateStable: true }); });

  // ---- открыть нужную вкладку игры (Номера, Рынок, Профиль, Меню) и сообщить iOS, что страница готова ----
  const hide = document.createElement('style');
  const addHide = () => { const r = document.head || document.documentElement; if (r) r.appendChild(hide); else setTimeout(addHide, 0); };
  if (C.route && C.route !== 'home') { hide.textContent = 'body{visibility:hidden}'; addHide(); }
  const t0 = Date.now();
  const routeTimer = setInterval(() => {
    let ok = false;
    try { ok = typeof S !== 'undefined' && S.me && typeof tabGo === 'function' && document.getElementById('view') && !/Загрузка…/.test(document.getElementById('view').textContent || '') || false; } catch (e) {}
    if (ok || Date.now() - t0 > 8000) {
      clearInterval(routeTimer);
      try { if (ok && C.route && C.route !== 'home') tabGo(C.route); } catch (e) {}
      // «назад» на корне вкладки ничего не делает: главная игры — это соседняя вкладка «Играть»
      try { if (ok && typeof back === 'function') { const _back = back; window.back = function () { try { if (C.route && C.route !== 'home' && S.stack.length <= 2 && S.stack[S.stack.length - 1] === C.route) return; } catch (e) {} return _back.apply(this, arguments); }; } } catch (e) {}
      setTimeout(() => { hide.remove(); post({ t: 'ready' }); syncBack(); }, 60);
    }
  }, 60);

  if (!document.documentElement) { const w = () => { if (document.documentElement) applyTheme(); else setTimeout(w, 0); }; w(); }
  document.addEventListener('DOMContentLoaded', () => {
    applyTheme();
    try { new MutationObserver(syncBack).observe(document.body, { attributes: true, attributeFilter: ['class'] }); } catch (e) {}
    try { new MutationObserver(syncBack).observe(document.getElementById('view'), { childList: true }); } catch (e) {}
  });
})();
