// ── Bar content HTML ─────────────────────────────────────────
function barHTML(pomColor, pomStroke, pomIcon, pomTime, privacy, privColor, aiLabel) {
  return `
  <div class="topbar-left">
    <div class="bar-group" style="padding:3px 7px; cursor:pointer;">
      <span style="font-size:13px; font-weight:800; color:var(--accent); letter-spacing:-0.5px;">K</span>
    </div>
    <span class="active-win">Firefox — koompi.com</span>
  </div>

  <div class="topbar-center">
    <div class="bar-group">
      <div class="pomodoro-widget" style="opacity:1;">
        <div class="pomo-ring">
          <svg viewBox="0 0 22 22">
            <circle cx="11" cy="11" r="9" fill="none" stroke="${pomColor}33" stroke-width="2"/>
            <circle cx="11" cy="11" r="9" fill="none" stroke="${pomColor}" stroke-width="2"
              stroke-dasharray="42" stroke-dashoffset="${pomStroke}"
              stroke-linecap="round" transform="rotate(-90 11 11)"/>
            <text x="11" y="14" text-anchor="middle" font-size="7" font-family="'Font Awesome 6 Free'" font-weight="900" fill="${pomColor}">${pomIcon}</text>
          </svg>
        </div>
        <span style="font-size:11px;font-weight:600;font-family:'JetBrains Mono',monospace;color:${pomColor};">${pomTime}</span>
      </div>
    </div>
    <div class="bar-group">
      <div class="ws-pills">
        <div class="ws-pill active"><div class="ws-dot" style="background:white;"></div></div>
        <div class="ws-pill used"><div class="ws-dot"></div></div>
        <div class="ws-pill used"><div class="ws-dot"></div></div>
        <div class="ws-pill unused"><div class="ws-dot"></div></div>
        <div class="ws-pill unused"><div class="ws-dot"></div></div>
      </div>
    </div>
  </div>

  <div class="topbar-right">
    <div class="media-pill">
      <div class="media-art"></div>
      <span class="media-title">Get Lucky</span>
      <div class="media-controls">
        <div class="media-btn">⏮</div>
        <div class="media-btn">⏸</div>
        <div class="media-btn">⏭</div>
      </div>
    </div>
    <div class="util-btns">
      <div class="util-btn" title="Screenshot">
        <svg width="13" height="13" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5">
          <rect x="1" y="3" width="14" height="10" rx="2"/><circle cx="8" cy="8" r="2.5"/>
          <path d="M5 3l1-2h4l1 2"/>
        </svg>
      </div>
      <div class="util-btn" title="Color picker">
        <svg width="13" height="13" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5">
          <path d="M10 2l4 4-7 7H3v-4L10 2z"/>
          <circle cx="3.5" cy="12.5" r="1.5" fill="currentColor" stroke="none"/>
        </svg>
      </div>
      <div class="util-btn" title="Screen recorder">
        <svg width="13" height="13" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5">
          <circle cx="8" cy="8" r="6"/><circle cx="8" cy="8" r="3" fill="currentColor" stroke="none"/>
        </svg>
      </div>
    </div>
    <div class="tray-icons">
      <div class="tray-app-icon" style="background:#5865F2;color:white;" title="Discord">D</div>
      <div class="tray-app-icon" style="background:#229ED9;color:white;" title="Telegram">T</div>
    </div>
    <div class="bar-group" style="cursor:pointer; gap:6px; padding:3px 7px;">
      <svg width="13" height="13" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" style="color:var(--t-muted)">
        <path d="M8 12a1 1 0 100 2 1 1 0 000-2z"/>
        <path d="M5.5 9.5a3.5 3.5 0 015 0"/>
        <path d="M3 7a6.5 6.5 0 0110 0"/>
      </svg>
      <svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" style="color:var(--t-muted)">
        <path d="M8 1l2 4-4 3 4 3-2 4V1z"/>
      </svg>
    </div>
    <div class="battery-bar"><div class="battery-fill"></div></div>
    <div class="privacy-pill" style="background:${privColor}22;border-color:${privColor}44;color:${privColor};">
      <div class="priv-dot" style="background:${privColor};animation:pulse-dot 2s infinite;"></div>${privacy}
    </div>
    <div class="ai-pill">${aiLabel}</div>
    <div class="topbar-clock">08:42</div>
  </div>`;
}

// ── Panel bar content (Win11 bottom dock layout) ─────────────
function panelBar() {
  return `
  <div class="panel-zone-left">
    <div class="win-widgets-btn" title="KOOMPI Widgets">
      <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
        <rect x="1"  y="1"  width="6" height="6" rx="1.5" opacity="0.9"/>
        <rect x="9"  y="1"  width="6" height="6" rx="1.5" opacity="0.6"/>
        <rect x="1"  y="9"  width="6" height="6" rx="1.5" opacity="0.6"/>
        <rect x="9"  y="9"  width="6" height="6" rx="1.5" opacity="0.35"/>
      </svg>
    </div>
  </div>

  <div class="win-center">
    <div class="win-start-btn" title="KOOMPI Start">K</div>
    <div class="win-search-bar" title="Search KOOMPI">
      <svg width="11" height="11" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" style="color:var(--t-muted);flex-shrink:0">
        <circle cx="7" cy="7" r="4.5"/><path d="M10.5 10.5l3 3"/>
      </svg>
      <span class="win-search-text">Search...</span>
    </div>
    <div class="win-taskview-btn" title="Task View / Workspaces">
      <svg width="13" height="13" viewBox="0 0 16 16" fill="currentColor" style="color:var(--t-muted)">
        <rect x="1" y="1" width="6" height="6" rx="1" opacity="0.85"/>
        <rect x="9" y="1" width="6" height="6" rx="1" opacity="0.85"/>
        <rect x="1" y="9" width="6" height="6" rx="1" opacity="0.85"/>
        <rect x="9" y="9" width="6" height="6" rx="1" opacity="0.4"/>
      </svg>
    </div>
    <div class="win-divider-v"></div>
    <div class="win-apps">
      <div class="win-app active"   title="Firefox"><i class="fa-brands fa-firefox-browser"></i></div>
      <div class="win-app running"  title="VS Code"><i class="fa-solid fa-laptop-code"></i></div>
      <div class="win-app"          title="Files"><i class="fa-solid fa-folder"></i></div>
      <div class="win-app"          title="Terminal"><i class="fa-solid fa-terminal"></i></div>
      <div class="win-app"          title="KOOMPI AI">✦</div>
      <div class="win-app"          title="Settings"><i class="fa-solid fa-gear"></i></div>
    </div>
  </div>

  <div class="panel-zone-right">
    <div class="win-tray-expand" title="Show hidden icons">^</div>
    <div class="win-tray-row">
      <div class="win-tray-icon" title="Network">
        <svg width="13" height="13" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5">
          <path d="M8 12a1 1 0 100 2 1 1 0 000-2z"/>
          <path d="M5.5 9.5a3.5 3.5 0 015 0"/>
          <path d="M3 7a6.5 6.5 0 0110 0"/>
        </svg>
      </div>
      <div class="win-tray-icon" title="Volume">
        <svg width="13" height="13" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5">
          <path d="M3 6v4h3l4 3V3L6 6H3z"/>
          <path d="M11 5.5a3 3 0 010 5"/>
        </svg>
      </div>
      <div class="win-tray-icon" title="Battery">
        <div class="battery-bar"><div class="battery-fill"></div></div>
      </div>
    </div>
    <div class="win-divider-v" style="margin:0 6px;"></div>
    <div class="privacy-pill"><div class="priv-dot"></div>LOCAL</div>
    <div class="ai-pill">✦ AI</div>
    <div class="win-divider-v" style="margin:0 6px;"></div>
    <div class="panel-clock-2line">
      <span class="p-time">08:42</span>
      <span class="p-date">Sun, Jun 8</span>
    </div>
    <div class="win-notif-btn" title="Notifications (3 unread)">
      <svg width="13" height="13" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5">
        <path d="M8 2a5 5 0 00-5 5v3l-1 1h12l-1-1V7a5 5 0 00-5-5z"/>
        <path d="M6.5 13a1.5 1.5 0 003 0"/>
      </svg>
      <div class="win-notif-badge"></div>
    </div>
  </div>`;
}

// ── Style switcher ───────────────────────────────────────────
const styleDescs = {
  hug:     'Hug (default) — bar flush to screen edge. Concave fillet "ears" at bottom corners match the display bezel radius. Glass spans full width. Most immersive.',
  taskbar: 'Taskbar (Windows 11) — bottom-anchored full-width bar. Widgets button · centered Start + Search + Task View + pinned apps with line indicators · system tray · KOOMPI Privacy + AI pills · 2-line clock · notification bell. Mica translucency.',
  dock:    'Dock (macOS) — thin 24px menu bar at top with active-app menus + Hug corner fillets · large 44px floating dock pill at bottom center with hover magnification · running-app dot indicators.',
};

function setBarStyle(style, btn) {
  ['hug','taskbar','dock'].forEach(function(s) {
    var el = document.getElementById('demo-' + s);
    if (el) el.classList.add('hidden');
  });
  var target = document.getElementById('demo-' + style);
  if (target) target.classList.remove('hidden');
  document.querySelectorAll('.bar-style-tab').forEach(function(b) { b.classList.remove('active'); });
  btn.classList.add('active');
  var desc = document.getElementById('style-desc');
  if (desc) desc.textContent = styleDescs[style];
}
window.setBarStyle = setBarStyle;

// ── Theme toggler ────────────────────────────────────────────
var darkMode = false;
function toggleTheme(btn) {
  darkMode = !darkMode;
  document.querySelectorAll('.bar-demo').forEach(function(d) {
    d.classList.toggle('theme-dark', darkMode);
    d.classList.toggle('theme-light', !darkMode);
  });
  btn.innerHTML = darkMode ? '<i class="fa-solid fa-moon"></i> Dark' : '<i class="fa-solid fa-sun"></i> Light';
  document.querySelectorAll('.desktop-clock').forEach(function(c) {
    c.style.color = darkMode ? 'rgba(255,255,255,0.85)' : 'rgba(26,34,53,0.8)';
  });
  document.querySelectorAll('.desktop-date').forEach(function(c) {
    c.style.color = darkMode ? 'rgba(255,255,255,0.4)' : 'rgba(26,34,53,0.45)';
  });
}
window.toggleTheme = toggleTheme;

// ── Init bar (fill hug + taskbar after sections loaded) ──────
function initBar() {
  var hugEl = document.getElementById('tb-hug');
  if (hugEl) hugEl.innerHTML = barHTML('#EF4444','14','\uf06d','18:33','LOCAL','#10B981','✦ AI');
  var taskbarEl = document.getElementById('tb-taskbar');
  if (taskbarEl) taskbarEl.innerHTML = panelBar();
}
window.initBar = initBar;

// ── Nav scroll tracker ───────────────────────────────────────
// Replaces IntersectionObserver with a rAF-throttled scroll listener.
// Finds the last section whose top edge is at or above 28% of the
// viewport height — stable at all scroll speeds, no jumps.
function initObserver() {
  var sections = Array.from(document.querySelectorAll('.section'));
  var navLinks = document.querySelectorAll('#sidenav a');
  var currentActive = null;
  var ticking = false;
  var clickLock = false; // suppress scroll handler during smooth-scroll

  function findActive() {
    var threshold = window.innerHeight * 0.28;
    var active = sections[0];
    for (var i = 0; i < sections.length; i++) {
      if (sections[i].getBoundingClientRect().top <= threshold) {
        active = sections[i];
      } else {
        break;
      }
    }
    return active;
  }

  function setActive(section) {
    if (!section || section === currentActive) return;
    currentActive = section;
    navLinks.forEach(function(l) { l.classList.remove('active'); });
    var link = document.querySelector('#sidenav a[href="#' + section.id + '"]');
    if (link) {
      link.classList.add('active');
      // Scroll sidebar so the active link stays visible — block:'nearest'
      // means it only moves if the link is already outside the sidebar viewport.
      link.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    }
  }

  function onScroll() {
    if (clickLock || ticking) return;
    ticking = true;
    requestAnimationFrame(function() {
      setActive(findActive());
      ticking = false;
    });
  }

  // On nav click: mark active immediately, lock scroll handler for 900ms
  // so the smooth page scroll doesn't fight the tracker mid-flight.
  navLinks.forEach(function(link) {
    link.addEventListener('click', function() {
      var href = link.getAttribute('href');
      var target = href && document.querySelector(href);
      if (!target) return;
      navLinks.forEach(function(l) { l.classList.remove('active'); });
      link.classList.add('active');
      currentActive = target;
      clickLock = true;
      setTimeout(function() { clickLock = false; }, 900);
    });
  });

  window.addEventListener('scroll', onScroll, { passive: true });
  setActive(findActive()); // initialise on page load
}
window.initObserver = initObserver;

// ── Async section loader ─────────────────────────────────────
var sectionFiles = [
  'sections/00-what-is.html',
  'sections/00a-document-map.html',
  'sections/00b-blueprint.html',
  'sections/84-system-map.html',
  'sections/87-near-future.html',
  'sections/01-design-system.html',
  'sections/02-shell-bar.html',
  'sections/03-launcher.html',
  'sections/04-notifications.html',
  'sections/05-quick-settings.html',
  'sections/06-osd.html',
  'sections/07-overview.html',
  'sections/08-widget-overlay.html',
  'sections/09-cheatsheet.html',
  'sections/15-session.html',
  'sections/34-window-management.html',
  'sections/45-file-manager.html',
  'sections/46-clipboard-manager.html',
  'sections/82-browser.html',
  'sections/86-partner-mobile.html',
  'sections/83-app-suite.html',
  'sections/11-tool-approval.html',
  'sections/12-rag-sources.html',
  'sections/13-memory.html',
  'sections/14-briefing.html',
  'sections/36-ai-failure-correction.html',
  'sections/43-ai-model-manager.html',
  'sections/26-index-status.html',
  'sections/27-privacy-dash.html',
  'sections/28-egress-ledger.html',
  'sections/42-app-permissions.html',
  'sections/85-web3-native.html',
  'sections/35-first-boot.html',
  'sections/29-settings.html',
  'sections/30-factory-reset.html',
  'sections/31-subsystem.html',
  'sections/32-installer.html',
  'sections/33-khmer.html',
  'sections/37-biometrics-auth.html',
  'sections/38-accessibility.html',
  'sections/39-update-management.html',
  'sections/40-network-manager.html',
  'sections/41-backup-restore.html',
  'sections/44-multi-user-profiles.html',
  'sections/47-digital-wellbeing.html',
  'sections/48-multi-device-continuity.html',
  'sections/49-error-recovery.html',
  'sections/50-app-store.html',
  'sections/53-theme-engine.html',
  'sections/54-motion-language.html',
  'sections/55-sound-design.html',
  'sections/51-display-color.html',
  'sections/52-developer-mode.html',
  'sections/56-compositor-visual-physics.html',
  'sections/57-gaming-mode.html',
  'sections/16-ambient-intelligence.html',
  'sections/17-memory-palace.html',
  'sections/19-proactive-os.html',
  'sections/20-appless-computing.html',
  'sections/21-khmer-ai.html',
  'sections/22-data-sovereignty.html',
  'sections/23-cognitive-os.html',
  'sections/24-lifetime-os.html',
  'sections/57a-thinking-os.html',
  'sections/58-memory-architecture.html',
  'sections/59-memory-lifecycle.html',
  'sections/60-agent-memory-impl.html',
  'sections/61-implementation-stack.html',
  'sections/62-death-protocol.html',
  'sections/63-os-that-raises-you.html',
  'sections/64-aging-with-dignity.html',
  'sections/65-cognitive-sovereignty.html',
  'sections/66-past-self.html',
  'sections/67-hardware-succession.html',
  'sections/68-format-archaeology.html',
  'sections/69-continuity-charter.html',
  'sections/70-refugee-mode.html',
  'sections/71-energy-sovereignty.html',
  'sections/72-repair-culture.html',
  'sections/73-ceremonial-forgetting.html',
  'sections/74-model-succession.html',
  'sections/75-household-constitution.html',
  'sections/76-memory-etiquette.html',
  'sections/77-personal-provenance.html',
  'sections/81-exit-door.html',
];

async function loadSections() {
  var main = document.getElementById('main');
  for (var i = 0; i < sectionFiles.length; i++) {
    try {
      var resp = await fetch(sectionFiles[i] + '?v=4');
      var html = await resp.text();
      var tmp = document.createElement('div');
      tmp.innerHTML = html;
      if (tmp.firstElementChild) {
        main.appendChild(tmp.firstElementChild);
      }
    } catch(e) {
      console.warn('Failed to load', sectionFiles[i], e);
    }
  }
  initBar();
  initObserver();
}
window.loadSections = loadSections;

loadSections();
