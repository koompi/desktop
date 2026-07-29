// ══════════════════════════════════════════════════════════════
// DESKTOP SIM — interactivity for the three desktop simulations
// Functions are GLOBALS so inline onclick= attributes (injected via
// innerHTML) can call them. innerHTML-injected <script> never runs,
// so this file is loaded directly from index.html.
// sim = 'hug' | 'taskbar' | 'dock'
// ══════════════════════════════════════════════════════════════

(function () {
  function root(sim) { return document.getElementById('sim-root-' + sim); }
  function q(sim, sel) { var r = root(sim); return r ? r.querySelector(sel) : null; }

  // Close every transient layer in a sim except an optional keeper.
  function closeAll(sim, keep) {
    var r = root(sim);
    if (!r) return;
    r.querySelectorAll('.sim-popup.open, .sim-overview.open, .sim-launcher.open, .sim-left-sidebar.open, .sim-right-sidebar.open')
      .forEach(function (el) { if (el !== keep) el.classList.remove('open'); });
  }

  // ── Sidebars ──────────────────────────────────────────────
  window.simToggleSidebar = function (sim, side, ev) {
    if (ev) ev.stopPropagation();
    var el = q(sim, '.sim-' + side + '-sidebar');
    if (!el) return;
    var willOpen = !el.classList.contains('open');
    closeAll(sim, willOpen ? el : null);
    el.classList.toggle('open', willOpen);
  };

  // ── Popups (anchored cards) ───────────────────────────────
  window.simTogglePopup = function (sim, name, ev) {
    if (ev) ev.stopPropagation();
    var el = q(sim, '.sim-popup[data-popup="' + name + '"]');
    if (!el) return;
    var willOpen = !el.classList.contains('open');
    closeAll(sim, willOpen ? el : null);
    el.classList.toggle('open', willOpen);
  };

  // ── Overview ──────────────────────────────────────────────
  window.simToggleOverview = function (sim, ev) {
    if (ev) ev.stopPropagation();
    var el = q(sim, '.sim-overview');
    if (!el) return;
    var willOpen = !el.classList.contains('open');
    closeAll(sim, willOpen ? el : null);
    el.classList.toggle('open', willOpen);
  };
  window.simOverviewBg = function (el, ev) {
    if (ev.target === el) el.classList.remove('open');
  };

  // ── Launcher ──────────────────────────────────────────────
  window.simToggleLauncher = function (sim, ev) {
    if (ev) ev.stopPropagation();
    var el = q(sim, '.sim-launcher');
    if (!el) return;
    var willOpen = !el.classList.contains('open');
    closeAll(sim, willOpen ? el : null);
    el.classList.toggle('open', willOpen);
  };
  window.simLauncherBg = function (el, ev) {
    if (ev.target === el) el.classList.remove('open');
  };

  // ── OSD (auto-dismiss after 2s) ───────────────────────────
  var osdTimers = {};
  window.simShowOSD = function (sim, kind, ev) {
    if (ev) ev.stopPropagation();
    var r = root(sim);
    if (!r) return;
    r.querySelectorAll('.sim-osd').forEach(function (o) { o.classList.remove('open'); });
    var el = q(sim, '.sim-osd[data-osd="' + kind + '"]');
    if (!el) return;
    el.classList.add('open');
    var key = sim + ':' + kind;
    if (osdTimers[key]) clearTimeout(osdTimers[key]);
    osdTimers[key] = setTimeout(function () { el.classList.remove('open'); }, 2000);
  };

  // ── App window focus (Hug + Dock) ─────────────────────────
  window.simFocusWin = function (sim, winId, title, ev) {
    if (ev) ev.stopPropagation();
    var r = root(sim);
    if (!r) return;
    r.querySelectorAll('.sim-win').forEach(function (w) { w.classList.remove('win-focused'); });
    var w = q(sim, '#' + winId);
    if (w) w.classList.add('win-focused');
    var tl = q(sim, '.active-win');
    if (tl && title) tl.textContent = title;
  };

  // ── Window controls: close / minimize / maximize ──────────
  // Delegated — the ✕ ─ ▢ buttons in every titlebar are live.
  var HUG_FULL = 'left:14px;top:54px;right:14px;bottom:14px;';
  var hugLayouts = {
    'term,code,fox': {
      term: 'left:14px;top:54px;width:calc(40% - 21px);bottom:14px;',
      code: 'left:calc(40% + 7px);top:54px;right:14px;bottom:calc(40% + 7px);',
      fox:  'left:calc(40% + 7px);right:14px;top:calc(60% + 7px);bottom:14px;'
    },
    'term,code': {
      term: 'left:14px;top:54px;width:calc(40% - 21px);bottom:14px;',
      code: 'left:calc(40% + 7px);top:54px;right:14px;bottom:14px;'
    },
    'term,fox': {
      term: 'left:14px;top:54px;width:calc(40% - 21px);bottom:14px;',
      fox:  'left:calc(40% + 7px);top:54px;right:14px;bottom:14px;'
    },
    'code,fox': {
      code: 'left:14px;top:54px;right:14px;bottom:calc(40% + 7px);',
      fox:  'left:14px;top:calc(60% + 7px);right:14px;bottom:14px;'
    },
    'term': { term: HUG_FULL }, 'code': { code: HUG_FULL }, 'fox': { fox: HUG_FULL }
  };

  function hugRetile() {
    var visible = ['term', 'code', 'fox'].filter(function (k) {
      var w = q('hug', '#hug-' + k);
      return w && !w.classList.contains('win-hidden');
    });
    var layout = hugLayouts[visible.join(',')];
    if (!layout) return;
    visible.forEach(function (k) {
      var w = q('hug', '#hug-' + k);
      delete w.dataset.prev; // a retile cancels any maximize
      w.style.cssText = layout[k];
    });
  }

  function updateReopen(sim) {
    var r = root(sim);
    if (!r) return;
    var hidden = r.querySelectorAll('.sim-win.win-hidden').length;
    var chip = r.querySelector('.sim-reopen');
    if (!chip) {
      chip = document.createElement('div');
      chip.className = 'sim-reopen sim-reopen-' + sim;
      chip.textContent = '↺ Reopen windows';
      chip.onclick = function (ev) { ev.stopPropagation(); restoreAll(sim); };
      r.appendChild(chip);
    }
    chip.classList.toggle('show', hidden > 0);
  }

  function hideWin(sim, win, kind) {
    win.classList.remove('win-focused');
    win.classList.add(kind === 'min' ? 'win-minimizing' : 'win-closing');
    setTimeout(function () {
      win.classList.add('win-hidden');
      win.classList.remove('win-minimizing', 'win-closing');
      if (sim === 'hug') hugRetile();
      updateReopen(sim);
    }, 200);
  }

  function restoreAll(sim) {
    var r = root(sim);
    if (!r) return;
    r.querySelectorAll('.sim-win.win-hidden').forEach(function (w) {
      w.classList.remove('win-hidden');
      w.classList.add('win-closing'); // enter from the same curve it left on
      requestAnimationFrame(function () {
        requestAnimationFrame(function () { w.classList.remove('win-closing'); });
      });
    });
    if (sim === 'hug') hugRetile();
    updateReopen(sim);
  }
  window.simRestoreAll = restoreAll;

  var MAX_INSET = {
    hug:     { left: '14px', top: '54px', right: '14px', bottom: '14px' },
    taskbar: { left: '0',    top: '0',    right: '0',    bottom: '48px' },
    dock:    { left: '14px', top: '34px', right: '14px', bottom: '64px' }
  };
  function toggleMax(sim, win) {
    if (win.dataset.prev) {
      win.style.cssText = win.dataset.prev;
      delete win.dataset.prev;
      return;
    }
    win.dataset.prev = win.style.cssText;
    var m = MAX_INSET[sim] || MAX_INSET.hug;
    win.style.left = m.left; win.style.top = m.top;
    win.style.right = m.right; win.style.bottom = m.bottom;
    win.style.width = 'auto'; win.style.height = 'auto';
  }

  // Capture phase: window onclick handlers call stopPropagation(),
  // so bubble-phase delegation would never see these clicks.
  document.addEventListener('click', function (e) {
    var ctrl = e.target.closest ? e.target.closest('.sim-win-ctrl') : null;
    if (ctrl) {
      var win = ctrl.closest('.sim-win');
      var simRoot = ctrl.closest('.desktop-sim');
      if (!win || !simRoot) return;
      e.stopPropagation(); // don't focus a window that's being closed
      var sim = simRoot.id.replace('demo-', '');
      if (ctrl.classList.contains('close')) hideWin(sim, win, 'close');
      else if (ctrl.classList.contains('min')) hideWin(sim, win, 'min');
      else if (ctrl.classList.contains('max')) toggleMax(sim, win);
      return;
    }
    // Taskbar / dock app icons bring minimized windows back
    var app = e.target.closest ? e.target.closest('.win-app, .dock-app') : null;
    if (app) {
      var sr = app.closest('.desktop-sim');
      if (sr) restoreAll(sr.id.replace('demo-', ''));
    }
  }, true);

  // ── Escape closes every open layer in every sim ────────────
  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Escape') return;
    ['hug', 'taskbar', 'dock'].forEach(function (sim) { closeAll(sim, null); });
  });

  // ── Dismiss all panels when clicking the desktop background ──
  // Sidebars, popups, and the bar all call event.stopPropagation(),
  // so this only fires when the bare wallpaper / app-window area is hit.
  window.simDeskClick = function (sim, e) {
    // Skip if the click landed on any interactive layer that didn't stop it
    var el = e && e.target;
    while (el) {
      if (el.matches && el.matches(
        '.sim-left-sidebar,.sim-right-sidebar,.sim-popup-layer,' +
        '.sim-bar-wrap,.sim-overview,.sim-launcher,.sim-osd'
      )) return;
      el = el.parentElement;
    }
    closeAll(sim, null);
  };
})();
