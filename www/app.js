// MowBite Updater's page: each part with what runs, whether there's something new, its version, updating it now and by
// itself, when, the free space, the log and what can go to make room. all through cgi-bin/updater
'use strict';

const API = 'cgi-bin/updater';

// --- words: english, german when the browser is ---
const DE = {
  'Only with the mower idle in the dock. If a new version doesn\'t start, it goes back to the one before. Afterwards old images and the build cache are cleared away.':
    'Nur wenn der Mäher im Leerlauf im Dock steht. Startet eine neue Version nicht, geht er zurück auf die vorige. Danach werden alte Images und der Build-Cache weggeräumt.',
  'in the dock': 'im Dock',
  'idle, not in the dock': 'im Leerlauf, nicht im Dock',
  'OpenMower doesn\'t answer': 'OpenMower antwortet nicht',
  'no MQTT': 'kein MQTT',
  'Update available': 'Update verfügbar',
  'Switch to the version picked': 'Wechsel auf gewählte Version',
  'Up to date': 'Aktuell',
  'Not known yet': 'Noch unbekannt',
  'Built here': 'Hier gebaut',
  "Left out (didn't start)": 'Ausgelassen (startete nicht)',
  'With the OS': 'Mit dem OS',
  'Runs: {what}': 'Läuft: {what}',
  'built {d}': 'gebaut {d}',
  'commit {c}': 'Commit {c}',
  'state unknown': 'Stand unbekannt',
  'Version': 'Version',
  'Edge (newest)': 'Edge (neueste)',
  'Release': 'Release',
  'Beta': 'Beta',
  'Stable': 'Stabil',
  'Newest version': 'Neuester Stand',
  'Local copy': 'Lokale Kopie',
  'Update': 'Aktualisieren',
  'Automatically at night': 'Automatisch nachts',
  'Last time: {what}': 'Zuletzt: {what}',
  'Next in line, after the one updating now.': 'Ist als Nächstes dran.',
  'Comes with OpenMowerOS 3 itself: openmower update-os.': 'Kommt bei OpenMowerOS 3 mit dem System selbst: openmower update-os.',
  "With this version the MowBite Planner doesn't work: it needs two changes that are only in edge so far (OM_PLANNER=external and keeping the planner's settings per area).":
    'Mit dieser Version funktioniert der MowBite-Planer nicht: Er braucht zwei Änderungen, die bisher nur in Edge sind (OM_PLANNER=external und das Behalten der Planer-Einstellungen pro Fläche).',
  "Edge changes often, an update at night can bring a new fault. Only when there's room for the old and the new image at once.":
    'Edge ändert sich oft, ein Update in der Nacht kann einen neuen Fehler mitbringen. Nur wenn Platz für das alte und das neue Image zugleich ist.',
  'This is a version built on its own, not one from its registry. "Update" swaps it for the one from there.':
    'Das ist eine eigens gebaute Version, keine aus der Registry. „Aktualisieren“ ersetzt sie durch die von dort.',
  'Stable is the newest release without "beta". It can be older than the beta that runs now, going there leaves out what came since.':
    'Stabil ist das neueste Release ohne „beta“. Es kann älter sein als die Beta, die gerade läuft; der Wechsel lässt weg, was seitdem dazukam.',
  'Built from a local copy, it is left as it is.': 'Aus einer lokalen Kopie gebaut, er bleibt, wie er ist.',
  'Updates also with the mower out of the dock.': 'Wird auch aktualisiert, wenn der Mäher nicht im Dock ist.',
  'Something wrong since the last update?': 'Seit dem letzten Update stimmt etwas nicht?',
  'Back to the version before': 'Zurück zur vorigen Version',
  'Really go back?': 'Wirklich zurück?',
  'When it updates by itself': 'Wann automatisch aktualisiert wird',
  'At': 'Um',
  'every night': 'jede Nacht',
  'Days': 'Tage',
  "If the mower isn't idle in the dock then, it tries again every 10 minutes for 3 hours. The time is the mower's.":
    'Steht der Mäher dann nicht im Leerlauf im Dock, versucht er es 3 Stunden lang alle 10 Minuten wieder. Die Uhrzeit ist die des Mähers.',
  'Check for updates': 'Auf Updates prüfen',
  'Update all': 'Alle aktualisieren',
  'asked…': 'angefragt…',
  'Last checked {t}.': 'Zuletzt geprüft {t}.',
  '{gb} GB free on the mower.': '{gb} GB frei auf dem Mäher.',
  'No answer from the updater for a moment.': 'Der Updater antwortet gerade nicht.',
  'Not saved, the updater did not answer.': 'Nicht gespeichert, der Updater hat nicht geantwortet.',
  'The updater did not answer.': 'Der Updater hat nicht geantwortet.',
  'Log': 'Protokoll',
  'newest at the top': 'neueste oben',
  'Copy': 'Kopieren',
  'copied': 'kopiert',
  "The last run waited: the mower wasn't idle in the dock.": 'Der letzte Lauf hat gewartet: Der Mäher stand nicht im Leerlauf im Dock.',
  'The last run was stopped halfway (the mower or the updater restarted), what had not started yet was put back.':
    'Der letzte Lauf wurde mittendrin unterbrochen (Mäher oder Updater neu gestartet), was noch nicht lief, wurde zurückgesetzt.',
  'Updating right now…': 'Aktualisiert gerade…',
  'Updating {name} ({n} of {of})…': 'Aktualisiert {name} ({n} von {of})…',
  'Getting ready': 'Wird vorbereitet',
  'Downloading': 'Herunterladen',
  'Unpacking': 'Entpacken',
  'Building': 'Bauen',
  'Restarting': 'Neustart',
  'Waiting until OpenMower is idle again': 'Warten, bis OpenMower wieder im Leerlauf ist',
  'Waiting until it answers': 'Warten auf Antwort',
  'Going back to the version before': 'Zurück auf die vorige Version',
  'Looking for updates': 'Sucht nach Updates',
  'Looking what can go': 'Sieht nach, was weg kann',
  'Deleting': 'Löscht',
  'Mower right now: {what}': 'Mäher gerade: {what}',
  'mowing': 'mäht',
  'driving to the dock': 'fährt zum Dock',
  'leaving the dock': 'fährt aus dem Dock',
  'recording an area': 'nimmt eine Fläche auf',
  '{n} of {of} layers': '{n} von {of} Ebenen',
  'step {n} of {of}': 'Schritt {n} von {of}',
  'was up to date': 'war aktuell',
  'updated {when}': 'aktualisiert {when}',
  'back to the version before {when}': 'zurück auf die vorige Version {when}',
  'runs an image built here, updated only when asked': 'läuft mit einem hier gebauten Image, wird nur auf Anfrage aktualisiert',
  'not enough room on the mower: needs about {need} MB and some to spare, {free} MB free':
    'nicht genug Platz auf dem Mäher: braucht etwa {need} MB und etwas Reserve, {free} MB frei',
  "this version didn't start before, it waits for the next one": 'diese Version ist schon einmal nicht gestartet, er wartet auf die nächste',
  'stable {v} is older than what runs, it stays until a newer stable is out': 'Stabil {v} ist älter als die laufende Version, sie bleibt, bis es eine neuere stabile gibt',
  "the new version didn't start, it went back to the one before": 'die neue Version ist nicht gestartet, er ist auf die vorige zurückgegangen',
  "not confirmed yet: the new version didn't answer as it should while the mower wasn't idle, nothing was restarted. The next run looks again":
    'noch nicht bestätigt: Die neue Version hat nicht wie erwartet geantwortet, während der Mäher nicht im Leerlauf war, deshalb wurde nichts neu gestartet. Der nächste Lauf sieht noch einmal nach',
  "not built: the image it's built on isn't on the mower": 'nicht gebaut: Das Image, auf dem er aufbaut, ist nicht auf dem Mäher',
  "not done: the mower wasn't idle in the dock": 'nicht gemacht: Der Mäher stand nicht im Leerlauf im Dock',
  'there is no version before to go back to': 'es gibt keine vorige Version zum Zurückgehen',
  'failed ({why}), see the log': 'fehlgeschlagen ({why}), siehe Protokoll',
  'Make room': 'Platz schaffen',
  '{gb} GB free': '{gb} GB frei',
  "What's on the mower that nothing needs: images no container uses and the build cache. Shown is the room each really frees. Nothing goes by itself.":
    'Was auf dem Mäher liegt und nicht gebraucht wird: Images, die kein Container benutzt, und der Build-Cache. Angezeigt ist der Platz, der jeweils wirklich frei wird. Nichts wird von selbst gelöscht.',
  'Build cache': 'Build-Cache',
  'The next build (the planner) then takes longer and needs the internet.': 'Der nächste Bau (Planer) dauert dann länger und braucht Internet.',
  'Nothing to delete right now.': 'Gerade gibt es nichts zu löschen.',
  'Look again': 'Neu ansehen',
  'Delete': 'Löschen',
  'Clear': 'Leeren',
  'Really delete?': 'Wirklich löschen?',
  'Delete all ({size})': 'Alles löschen ({size})',
  'an image without a name': 'ein Image ohne Namen',
  'the version before an update, kept to go back to': 'der Stand vor einem Update, zum Zurückgehen aufgehoben',
  'kept by the planner session to go back to': 'Rückweg der Planer-Session',
  'an older version kept to go back to': 'ein älterer Stand, zum Zurückgehen aufgehoben',
  'left over, nothing uses it': 'übrig geblieben, nichts benutzt es',
  'not used by any container': 'von keinem Container benutzt',
  'The updater does not answer.': 'Der Updater antwortet nicht.',
  'It updates itself too, after the automatic updates at night.': 'Er aktualisiert sich auch selbst, nach den automatischen Updates in der Nacht.',
  'Restarting the updater, the page comes back by itself': 'Der Updater startet neu, die Seite kommt von selbst wieder',
  'Out of reach for the updater': 'Für den Updater nicht erreichbar',
  'Add an app': 'App hinzufügen',
  'Add': 'Hinzufügen',
  'Pick an app': 'App auswählen',
  'Any other app of your stacks, the updater then looks after it like the others: only with the mower idle in the dock, and back to the version before when the new one doesn\'t run for half a minute.':
    'Jede andere App deiner Stacks, der Updater kümmert sich dann wie um die anderen: nur mit dem Mäher im Leerlauf im Dock, und zurück auf die vorige Version, wenn die neue keine halbe Minute läuft.',
  'Every app of your stacks is in already.': 'Alle Apps deiner Stacks sind schon dabei.',
  'Take out': 'Herausnehmen',
  'Really take out?': 'Wirklich herausnehmen?',
  'Picked by you.': 'Von dir hinzugefügt.',
  'This page is shown inside another one, open it on its own to change anything:': 'Diese Seite ist in eine andere eingebettet, zum Ändern bitte direkt öffnen:',
  '"{name}" is in {dir}. The updater only sees {reach}. Move it there, or add this line to the updater\'s "volumes:":':
    '„{name}“ liegt in {dir}. Der Updater sieht nur {reach}. Dorthin verschieben oder diese Zeile bei den „volumes:“ des Updaters einfügen:',
  '"{name}" runs without a compose file, the updater can\'t update it.':
    '„{name}“ läuft ohne compose-Datei, das kann der Updater nicht aktualisieren.',
  'The updater doesn\'t see its own folder {dir}: it forgets its settings and can\'t update itself. Add this line to its "volumes:":':
    'Der Updater sieht seinen eigenen Ordner {dir} nicht: Er vergisst seine Einstellungen und kann sich nicht selbst aktualisieren. Diese Zeile bei seinen „volumes:“ einfügen:',
  'Mon': 'Mo', 'Tue': 'Di', 'Wed': 'Mi', 'Thu': 'Do', 'Fri': 'Fr', 'Sat': 'Sa', 'Sun': 'So',
};
// (MowBite passes its language on when it embeds the page)
const QUERY = new URLSearchParams(location.search);
const german = QUERY.get('lang') ? QUERY.get('lang') === 'de' : (navigator.language || '').toLowerCase().startsWith('de');
const embedded = window.self !== window.top;
// embedded by MowBite (the app, its page on this mower, or one on this computer) it can change things, embedded by any
// other page only show them: a page somewhere else can't make one click here on something
function parentOk() {
  if (!embedded) return true;
  let from = '';
  try {
    from = location.ancestorOrigins && location.ancestorOrigins.length ? location.ancestorOrigins[0] : new URL(document.referrer).origin;
  } catch {
    return false;
  }
  try {
    const u = new URL(from);
    return u.protocol === 'capacitor:' || u.hostname === 'localhost' || u.hostname === '127.0.0.1' || u.hostname === location.hostname;
  } catch {
    return false;
  }
}
const locked = !parentOk();
if (locked) document.documentElement.classList.add('locked');
document.documentElement.lang = german ? 'de' : 'en';
function tr(text, vars) {
  let t = (german && DE[text]) || text;
  for (const k in vars || {}) t = t.split('{' + k + '}').join(vars[k]);
  return t;
}
const fmt = (n, d) => n.toLocaleString(german ? 'de-DE' : 'en-GB', {minimumFractionDigits: d, maximumFractionDigits: d});

// --- what the updater says ---
let st = null;
// what was asked on this page, and when: shown at once, until the updater shows it's on it
let asked = false;
let askedFor = '';
let askedAt = 0;
// (its run seen since: from then on its bars say it)
let askedRan = false;
let lost = false;
let failed = null;
let logOpen = false;
let sure = null;
let now = Date.now() / 1000;
// its start the page was loaded with: another one (its update) loads the page again, it may have changed
let started = null;

const running = () => !!st && st.status.result === 'running';
// it restarts on its new version: since when, for a few minutes at most
function restarting() {
  const [state, t] = S('updater').split(' ');
  return state === 'restarting' && /^\d+$/.test(t || '') && now - Number(t) < 300 ? Number(t) : null;
}
// a request the updater took and works on before its bar shows (taken: "<since> now:<part> self back:<part> ..."): what
// and since when. a look for updates alone keeps nothing from being asked meanwhile, it stops for it
function taken() {
  const [since, ...what] = S('taken').split(' ');
  return {since: /^\d+$/.test(since || '') ? Number(since) : null, what: what.filter((w) => w && w !== 'check')};
}
const busy = () => locked || asked || (!!st && (st.requested || taken().what.length > 0 || running() || !!restarting()));
// since when this was asked (on this page or taken by the updater), null when it wasn't: "now:<part>", "now:all",
// "back:<part>", "self", "room", "free", "check"
function askedSince(what) {
  const word = askedFor.replace(/^now$/, 'now:all').replace('=', ':').replace(/^free:.*/, 'free');
  if (asked && word === what) return askedAt / 1000;
  const t = taken();
  if (t.what.some((w) => (w.startsWith('free:') ? 'free' : w) === what)) return t.since;
  if (what === 'check' && S('taken').split(' ').includes('check')) return t.since;
  return null;
}
const looking = () => (/^\d+$/.test(S('looking')) ? Number(S('looking')) : askedSince('check'));

async function load() {
  try {
    const res = await fetch(API, {cache: 'no-store', signal: AbortSignal.timeout(8000)});
    if (!res.ok) throw new Error();
    st = await res.json();
    lost = false;
    if (started && st.status.started && st.status.started !== started && !document.querySelector('#app :focus')) return void location.reload();
    started = st.status.started || started;
    if (asked && running()) askedRan = true;
    // (a moment after asking: an answer from before it may not know of it yet)
    if (Date.now() - askedAt > 4000 && !st.requested && !taken().what.length && !running()) asked = false;
  } catch {
    lost = true;
  }
  render();
}
// (as json, which only its own page and programs may send)
async function post(query, body) {
  if (locked) throw new Error();
  const res = await fetch(API + '?' + query, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: body || '', signal: AbortSignal.timeout(8000)});
  if (!res.ok || (await res.text()).trim() !== 'ok') throw new Error();
}
function ask(query, body) {
  asked = true;
  askedFor = query;
  askedAt = Date.now();
  askedRan = false;
  failed = null;
  render();
  // (what it says then, at once: it takes a request within a second or two)
  post(query, body).then(() => setTimeout(load, 1500), () => {
    asked = false;
    failed = tr('The updater did not answer.');
    render();
  });
}
// only what changed: a value it shows but nobody set (OpenMower's channel from its .env) stays unset
function setConf(patch) {
  Object.assign(st.conf, patch);
  failed = null;
  const lines = Object.keys(patch).map((k) => k + ' ' + patch[k]);
  render();
  post('conf', lines.join('\n') + '\n').catch(() => {
    failed = tr('Not saved, the updater did not answer.');
    render();
  });
}

function loop() {
  load().finally(() => setTimeout(loop, busy() || looking() ? 2000 : 5000));
}
// the seconds on a bar
setInterval(() => {
  now = Date.now() / 1000;
  if (running() || restarting() || asked || S('taken') || looking()) render();
}, 1000);

// --- the parts, in words ---
const PARTS = () => (st && st.parts) || [];
const S = (k) => (st && st.status[k]) || '';
const date = (d) => (/^\d{4}-\d\d-\d\d$/.test(d || '') ? new Date(d + 'T12:00:00').toLocaleDateString(german ? 'de-DE' : 'en-GB') : null);
const when = (t) => (t ? new Date(Number(t) * 1000).toLocaleString(german ? 'de-DE' : 'en-GB', {dateStyle: 'short', timeStyle: 'short'}) : '?');
const size = (b) => (b >= 1e9 ? fmt(b / 1e9, 1) + ' GB' : b >= 1e6 ? Math.round(b / 1e6) + ' MB' : Math.max(0, Math.round(b / 1e3)) + ' kB');

function runningText(p) {
  const [what, day] = S(p.id + '_running').split(' ');
  const built = date(day);
  if (p.kind === 'os') return tr('Comes with OpenMowerOS 3 itself: openmower update-os.');
  if (p.kind === 'build' || p.kind === 'local') {
    const commit = what && what !== '?' ? what.slice(0, 7) : null;
    return [commit ? tr('commit {c}', {c: commit}) : tr('state unknown'), built && tr('built {d}', {d: built})].filter(Boolean).join(' · ');
  }
  if (p.kind === 'openmower') return [what, built && tr('built {d}', {d: built})].filter(Boolean).join(' · ');
  return [what, built].filter(Boolean).join(' · ');
}
const BADGE = {
  yes: 'Update available',
  switch: 'Switch to the version picked',
  no: 'Up to date',
  failed: "Left out (didn't start)",
  unknown: 'Not known yet',
  local: 'Built here',
  os: 'With the OS',
};
function result(p) {
  const [state, ...rest] = S(p.id).split(' ');
  switch (state) {
    case 'current':
      return tr('was up to date');
    case 'updated':
      return tr('updated {when}', {when: when(rest[0])}) + (rest[1] ? ' (' + rest[1] + ')' : '');
    case 'back':
      return tr('back to the version before {when}', {when: when(rest[0])}) + (rest[1] ? ' (' + rest[1] + ')' : '');
    case 'local':
      // (a build from a copy says so already)
      return p.kind === 'local' ? null : tr('runs an image built here, updated only when asked');
    case 'nospace':
      return tr('not enough room on the mower: needs about {need} MB and some to spare, {free} MB free', {need: rest[0] || '?', free: rest[1] || '?'});
    case 'skipped_failed':
      return tr("this version didn't start before, it waits for the next one");
    case 'stable_older':
      return tr('stable {v} is older than what runs, it stays until a newer stable is out', {v: rest[0] || '?'});
    case 'rolled_back':
      return tr("the new version didn't start, it went back to the one before");
    case 'unconfirmed':
      return tr("not confirmed yet: the new version didn't answer as it should while the mower wasn't idle, nothing was restarted. The next run looks again");
    case 'error':
      if (rest[0] === 'base_missing') return tr("not built: the image it's built on isn't on the mower");
      if (rest[0] === 'not_docked') return tr("not done: the mower wasn't idle in the dock");
      if (rest[0] === 'no_back') return tr('there is no version before to go back to');
      return tr('failed ({why}), see the log', {why: rest.join(' ') || '?'});
    default:
      return null;
  }
}

// what it does right now, for the bar
const STEPS = ['prepare', 'download', 'extract', 'build', 'restart', 'wait', 'back'];
function progressNow() {
  if (!running()) return null;
  const [part, step, pct, since, done, of] = S('progress').split(' ');
  if (!STEPS.includes(step)) return null;
  const n = (x) => (/^\d+$/.test(x || '') ? Number(x) : undefined);
  return {part, step, pct: n(pct) === undefined ? null : Math.min(100, n(pct)), since: n(since) || 0, done: n(done), of: n(of)};
}
const runParts = () => (running() ? S('run_parts').split(' ').filter(Boolean) : []);
function stepLabel(p) {
  return tr(
    {
      prepare: 'Getting ready',
      download: 'Downloading',
      extract: 'Unpacking',
      build: 'Building',
      restart: 'Restarting',
      wait: p.part === 'openmower' ? 'Waiting until OpenMower is idle again' : 'Waiting until it answers',
      back: 'Going back to the version before',
      look: 'Looking for updates',
      room: 'Looking what can go',
      free: 'Deleting',
    }[p.step],
  );
}
function stepDetail(p) {
  if (p.step === 'extract' && p.of) return tr('{n} of {of} layers', {n: p.done || 0, of: p.of});
  if (p.step === 'build' && p.of) return tr('step {n} of {of}', {n: Math.min(p.of, (p.done || 0) + 1), of: p.of});
  if (p.pct !== null && p.step === 'download') return p.pct + ' %';
  // (asked for before this page knew when)
  if (!p.since) return '';
  const secs = Math.max(0, Math.round(now - p.since));
  return Math.floor(secs / 60) + ':' + String(secs % 60).padStart(2, '0');
}
function runText() {
  const r = S('result');
  if (r === 'waiting') return tr("The last run waited: the mower wasn't idle in the dock.");
  if (r === 'interrupted') return tr('The last run was stopped halfway (the mower or the updater restarted), what had not started yet was put back.');
  if (r === 'running') {
    const p = progressNow();
    const parts = runParts();
    const part = p && (p.part === 'updater' ? {name: 'MowBite Updater'} : PARTS().find((x) => x.id === p.part));
    if (!part || !parts.includes(p.part)) return tr('Updating right now…');
    return tr('Updating {name} ({n} of {of})…', {name: part.name, n: parts.indexOf(p.part) + 1, of: parts.length});
  }
  return null;
}
// OpenMower's states besides idle, in words
const STATES = {MOWING: 'mowing', DOCKING: 'driving to the dock', UNDOCKING: 'leaving the dock', AREA_RECORDING: 'recording an area'};
function mowerText() {
  const m = S('mower');
  if (!st) return '';
  if (m === '1') return tr('in the dock');
  if (m === '0 IDLE') return tr('idle, not in the dock');
  if (m === '0 unknown') return tr("OpenMower doesn't answer");
  if (m.startsWith('0 ')) return STATES[m.slice(2)] ? tr(STATES[m.slice(2)]) : m.slice(2).toLowerCase().replace(/_/g, ' ');
  return tr('no MQTT');
}

// --- building the page ---
function h(tag, attrs, ...kids) {
  const e = document.createElement(tag);
  let value;
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === undefined || v === null || v === false) continue;
    if (k === 'class') e.className = v;
    else if (k === 'value') value = v;
    else if (k === 'checked') e.checked = true;
    else if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
    else e.setAttribute(k, v === true ? '' : v);
  }
  for (const kid of kids.flat(Infinity)) if (kid !== null && kid !== undefined && kid !== false) e.append(kid.nodeType ? kid : String(kid));
  if (value !== undefined) e.value = value;
  return e;
}
const dim = (text) => h('p', {class: 'dim'}, text);
// to the clipboard, also on plain http where the browser has no clipboard api
function copyText(text) {
  if (navigator.clipboard && window.isSecureContext) return void navigator.clipboard.writeText(text).catch(() => {});
  const area = h('textarea', {style: 'position:fixed;opacity:0'});
  area.value = text;
  document.body.append(area);
  area.select();
  try {
    document.execCommand('copy');
  } catch {}
  area.remove();
}
// a delete or a step back takes two taps: the first asks, for a few seconds
function twoTaps(key, label, question, go) {
  return h('button', {
    class: 'control' + (sure === key ? ' danger' : ''),
    disabled: busy(),
    onclick: () => {
      if (sure !== key) {
        sure = key;
        setTimeout(() => {
          if (sure === key) {
            sure = null;
            render();
          }
        }, 4000);
        render();
        return;
      }
      sure = null;
      go();
    },
  }, sure === key ? question : label);
}

// a part asked for that isn't on its bar yet: from the tap on, so something moves at once. in a run before its first
// step only the first one (the others are in line), the time since it was asked when known
function waiting(id) {
  const prog = progressNow();
  const parts = runParts();
  if (parts.includes(id)) return !prog && parts.indexOf(id) === 0 ? {step: 'prepare', since: askedSince('now:' + id) || askedSince('now:all')} : null;
  const back = askedSince('back:' + id);
  if (back !== null) return {step: 'back', since: back};
  const t = askedSince(id === 'updater' ? 'self' : 'now:' + id);
  return t !== null ? {step: 'prepare', since: t} : null;
}
// its getting ready counted from the tap, not from when the updater got to it
function fromTap(p) {
  if (p.step !== 'prepare') return p;
  const t = askedSince(p.part === 'updater' ? 'self' : 'now:' + p.part) || askedSince('now:all');
  return t && t < p.since ? {...p, since: t} : p;
}

function bar(p) {
  const label = stepLabel(p);
  return h('div', {class: 'progress'},
    h('div', {class: 'progressHead'}, h('span', null, label), h('span', {class: 'dim'}, stepDetail(p))),
    h('div', {class: 'track', role: 'progressbar', 'aria-label': label, 'aria-valuemin': 0, 'aria-valuemax': 100, 'aria-valuenow': p.pct === null ? undefined : p.pct},
      p.pct === null ? h('div', {class: 'moving'}) : h('div', {class: 'fill', style: 'width:' + p.pct + '%'})),
  );
}

function partCard(p) {
  const id = p.id;
  const avail = S(id + '_available').split(' ')[0] || (p.kind === 'os' ? 'os' : '');
  const isNew = avail === 'yes' || avail === 'switch';
  const fixed = p.kind === 'local' || p.kind === 'os';
  const auto = st.conf[id + '_auto'] === 1;
  const prog = progressNow();
  const mine = prog && prog.part === id ? prog : null;
  const parts = runParts();
  const queued = !mine && parts.includes(id) && parts.indexOf(id) > (prog ? parts.indexOf(prog.part) : 0);
  const wait = !mine && !queued && waiting(id);
  const plannerHere = PARTS().some((x) => x.id === 'planner');
  const stable = S(id + '_stable');

  let pick = null;
  if (p.kind === 'openmower') {
    const own = [st.conf.openmower, S('openmower_env')].filter((t) => t && t !== 'edge' && t !== 'latest');
    pick = h('select', {class: 'control', 'aria-label': tr('Version'), value: st.conf.openmower, onchange: (e) => (e.target.blur(), setConf({openmower: e.target.value}))},
      ['edge', 'latest', ...new Set(own)].map((t) => h('option', {value: t}, t === 'edge' ? tr('Edge (newest)') : t === 'latest' ? tr('Release') : t)));
  } else if (p.kind === 'image' && stable) {
    pick = h('select', {class: 'control', 'aria-label': tr('Version'), value: st.conf[id], onchange: (e) => (e.target.blur(), setConf({[id]: e.target.value}))},
      h('option', {value: 'beta'}, tr('Beta')),
      (stable === 'yes' || st.conf[id] === 'stable') && h('option', {value: 'stable'}, tr('Stable')));
  } else if (p.kind !== 'os') {
    const label = p.kind === 'local' ? tr('Local copy') : p.kind === 'build' ? tr('Newest version') : (S(id + '_available').split(' ')[1] || '').split(':').pop() || '–';
    pick = h('select', {class: 'control', 'aria-label': tr('Version'), disabled: true}, h('option', null, label));
  }

  const res = result(p);
  return h('div', {class: 'card'},
    h('div', {class: 'head'},
      h('span', {class: 'name'}, p.name || p.container),
      avail && BADGE[avail] && h('span', {class: 'badge' + (isNew ? ' new' : '')}, tr(BADGE[avail]))),
    dim(tr('Runs: {what}', {what: runningText(p)})),
    mine && bar(fromTap(mine)),
    wait && bar({part: id, step: wait.step, pct: null, since: wait.since}),
    queued && dim(tr('Next in line, after the one updating now.')),
    pick && h('div', {class: 'row'}, pick,
      h('button', {class: 'control' + (isNew ? ' primary' : ''), disabled: busy() || fixed, onclick: () => ask('now=' + id)}, tr('Update'))),
    !fixed && h('label', {class: 'check'},
      h('input', {type: 'checkbox', checked: auto, onchange: (e) => setConf({[id + '_auto']: e.target.checked ? 1 : 0})}),
      tr('Automatically at night')),
    p.kind === 'image' && avail === 'local' && dim(tr('This is a version built on its own, not one from its registry. "Update" swaps it for the one from there.')),
    p.kind === 'image' && st.conf[id] === 'stable' && (S(id + '_stable_older')
      ? dim(tr('stable {v} is older than what runs, it stays until a newer stable is out', {v: S(id + '_stable_older')}))
      : dim(tr('Stable is the newest release without "beta". It can be older than the beta that runs now, going there leaves out what came since.'))),
    p.kind === 'openmower' && st.conf.openmower !== 'edge' && plannerHere &&
      h('div', {class: 'warn'}, tr("With this version the MowBite Planner doesn't work: it needs two changes that are only in edge so far (OM_PLANNER=external and keeping the planner's settings per area).")),
    p.kind === 'openmower' && auto && dim(tr("Edge changes often, an update at night can bring a new fault. Only when there's room for the old and the new image at once.")),
    p.kind === 'local' && dim(tr('Built from a local copy, it is left as it is.')),
    p.gate === 'none' && dim(tr('Updates also with the mower out of the dock.')),
    res && dim(tr('Last time: {what}', {what: res})),
    p.kind === 'image' && S(id + '_back') === 'yes' &&
      h('div', {class: 'row'}, dim(tr('Something wrong since the last update?')),
        twoTaps('back:' + id, tr('Back to the version before'), tr('Really go back?'), () => ask('back=' + id))),
    S(id + '_picked') === 'yes' &&
      h('div', {class: 'row'}, dim(tr('Picked by you.')),
        twoTaps('out:' + id, tr('Take out'), tr('Really take out?'), () => pick(picked().filter((c) => c !== p.container)))),
  );
}

// the apps picked on this page (besides the known and labelled ones): changed, then looked at again at once
const picked = () => String(st.conf.picked || 'none').split(',').filter((c) => c && c !== 'none');
function pick(list) {
  setConf({picked: list.length ? list.join(',') : 'none'});
  ask('check');
}
let choice = '';
function addCard() {
  const cand = S('candidates').split(' ').filter(Boolean);
  if (!cand.includes(choice)) choice = cand[0] || '';
  return h('div', {class: 'card'},
    h('span', {class: 'name'}, tr('Add an app')),
    dim(tr('Any other app of your stacks, the updater then looks after it like the others: only with the mower idle in the dock, and back to the version before when the new one doesn\'t run for half a minute.')),
    cand.length
      ? h('div', {class: 'row'},
        h('select', {class: 'control', 'aria-label': tr('Pick an app'), value: choice, onchange: (e) => (choice = e.target.value, e.target.blur())},
          cand.map((c) => h('option', {value: c}, c))),
        h('button', {class: 'control', disabled: busy() || !choice, onclick: () => pick([...picked(), choice])}, tr('Add')))
      : dim(tr('Every app of your stacks is in already.')),
  );
}

// itself: the commit it runs, whether there's a newer one and updating it, the bar while it downloads and restarts
function selfCard() {
  if (!S('updater_running')) return null;
  const [rev, day] = S('updater_running').split(' ');
  const avail = S('updater_available').split(' ')[0];
  const isNew = avail === 'yes';
  const prog = progressNow();
  const mine = prog && prog.part === 'updater' ? prog : null;
  const since = restarting();
  const wait = !mine && !since && waiting('updater');
  const tag = (S('updater_available').split(' ')[1] || '').split(':').pop() || '–';
  const res = result({id: 'updater', kind: 'image'});
  return h('div', {class: 'card'},
    h('div', {class: 'head'},
      h('span', {class: 'name'}, 'MowBite Updater'),
      avail && BADGE[avail] && h('span', {class: 'badge' + (isNew ? ' new' : '')}, tr(BADGE[avail]))),
    dim(tr('Runs: {what}', {what: [rev && rev !== '?' ? tr('commit {c}', {c: rev}) : tr('state unknown'), date(day)].filter(Boolean).join(' · ')})),
    mine && bar(fromTap(mine)),
    wait && bar({part: 'updater', step: wait.step, pct: null, since: wait.since}),
    since && bar({part: 'updater', step: 'restart', pct: null, since}),
    since && dim(tr('Restarting the updater, the page comes back by itself')),
    h('div', {class: 'row'},
      h('select', {class: 'control', 'aria-label': tr('Version'), disabled: true}, h('option', null, tag)),
      h('button', {class: 'control' + (isNew ? ' primary' : ''), disabled: busy(), onclick: () => ask('self')}, tr('Update'))),
    avail === 'local' && dim(tr('This is a version built on its own, not one from its registry. "Update" swaps it for the one from there.')),
    PARTS().some((p) => st.conf[p.id + '_auto'] === 1) && dim(tr('It updates itself too, after the automatic updates at night.')),
    res && dim(tr('Last time: {what}', {what: res})),
  );
}

// what it can't reach and why: a container it would look after whose stack is in a folder it doesn't have (with the
// line that gives it to it), one not from a compose file, or its own compose file
function awayCard() {
  const far = S('unreachable').split(' ').filter(Boolean).map((x) => {
    const at = x.lastIndexOf('@');
    return {name: x.slice(0, at), dir: x.slice(at + 1)};
  });
  const self = S('updater_away');
  if (!far.length && !self) return null;
  const reach = S('reach').trim().split(' ').filter(Boolean).join(', ') || '/opt/stacks';
  const line = (dir) => h('pre', {class: 'log'}, '      - ' + dir + ':' + dir);
  return h('div', {class: 'card'},
    h('span', {class: 'name'}, tr('Out of reach for the updater')),
    self && self !== '-' && [dim(tr('The updater doesn\'t see its own folder {dir}: it forgets its settings and can\'t update itself. Add this line to its "volumes:":', {dir: self})), line(self)],
    far.map((f) => f.dir === '-'
      ? dim(tr('"{name}" runs without a compose file, the updater can\'t update it.', {name: f.name}))
      : [dim(tr('"{name}" is in {dir}. The updater only sees {reach}. Move it there, or add this line to the updater\'s "volumes:":', {name: f.name, dir: f.dir, reach})), line(f.dir)]),
  );
}

function scheduleCard() {
  const days = st.conf.days === 'daily' ? [] : String(st.conf.days).split(',').map(Number);
  const toggle = (d) => {
    const next = days.includes(d) ? days.filter((x) => x !== d) : [...days, d].sort();
    setConf({days: next.length && next.length < 7 ? next.join(',') : 'daily'});
  };
  return h('div', {class: 'card'},
    h('span', {class: 'name'}, tr('When it updates by itself')),
    h('div', {class: 'row'},
      h('input', {class: 'control', type: 'time', 'aria-label': tr('At'), value: st.conf.at, onchange: (e) => e.target.value && (e.target.blur(), setConf({at: e.target.value}))}),
      h('label', {class: 'check'},
        h('input', {type: 'checkbox', checked: st.conf.days === 'daily', onchange: (e) => setConf({days: e.target.checked ? 'daily' : '7'})}),
        tr('every night'))),
    st.conf.days !== 'daily' && h('div', {class: 'days', role: 'group', 'aria-label': tr('Days')},
      ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((d, i) =>
        h('button', {class: 'control' + (days.includes(i + 1) ? ' primary' : ''), 'aria-pressed': String(days.includes(i + 1)), onclick: () => toggle(i + 1)}, tr(d)))),
    dim(tr("If the mower isn't idle in the dock then, it tries again every 10 minutes for 3 hours. The time is the mower's.")),
  );
}

function actionsCard() {
  const free = /^\d+$/.test(S('disk_free')) ? Number(S('disk_free')) : null;
  const run = runText();
  const look = looking();
  const all = running() || askedRan ? null : askedSince('now:all');
  const line = [
    // (still in line: it finishes what it does first)
    run || (st.requested ? tr('asked…') : null),
    lost && tr('No answer from the updater for a moment.'),
    S('checked') && tr('Last checked {t}.', {t: when(S('checked'))}),
    free !== null && tr('{gb} GB free on the mower.', {gb: fmt(free / 1024, 1)}),
  ].filter(Boolean).join(' ');
  const log = [...(st.log || [])].reverse().join('\n');
  let copied = false;
  const copy = h('button', {class: 'control', onclick: () => {
    copyText(log);
    copied = true;
    copy.textContent = tr('copied');
    setTimeout(() => (copy.textContent = tr('Copy')), 1500);
  }}, copied ? tr('copied') : tr('Copy'));
  const details = h('details', {open: logOpen, ontoggle: (e) => (logOpen = e.target.open)},
    h('summary', {class: 'dim'}, tr('Log')),
    h('div', {class: 'row'}, dim(tr('newest at the top')), copy),
    h('pre', {class: 'log'}, log));
  return h('div', {class: 'card'},
    h('div', {class: 'row'},
      h('button', {class: 'control', disabled: busy(), onclick: () => ask('check')}, tr('Check for updates')),
      h('button', {class: 'control', disabled: busy(), onclick: () => ask('now')}, tr('Update all'))),
    all !== null && bar({part: '', step: 'prepare', pct: null, since: all}),
    look !== null && bar({part: '', step: 'look', pct: null, since: look}),
    line && dim(line),
    failed && h('div', {class: 'warn'}, failed),
    log && details,
  );
}

const ROOM_NOTE = {
  rollback: 'the version before an update, kept to go back to',
  planner: 'kept by the planner session to go back to',
  old: 'an older version kept to go back to',
  dangling: 'left over, nothing uses it',
  unused: 'not used by any container',
};
function roomCard() {
  const items = (st.room && st.room.items) || [];
  const cache = (st.room && st.room.cache) || 0;
  const free = /^\d+$/.test(S('disk_free')) ? Number(S('disk_free')) : null;
  const total = items.reduce((n, i) => n + i.bytes, 0);
  return h('div', {class: 'card'},
    h('div', {class: 'head'}, h('span', {class: 'name'}, tr('Make room')), free !== null && h('span', {class: 'badge'}, tr('{gb} GB free', {gb: fmt(free / 1024, 1)}))),
    dim(tr("What's on the mower that nothing needs: images no container uses and the build cache. Shown is the room each really frees. Nothing goes by itself.")),
    items.map((i) => h('div', {class: 'item'},
      h('span', {class: 'itemName'}, i.refs === '-' ? tr('an image without a name') : i.refs.split(',').join(', ')),
      dim(tr(ROOM_NOTE[i.kind] || ROOM_NOTE.unused)),
      h('div', {class: 'row'}, dim(size(i.bytes)), twoTaps('img:' + i.id, tr('Delete'), tr('Really delete?'), () => ask('free=img:' + i.id))))),
    cache > 0 && h('div', {class: 'item'},
      h('span', {class: 'itemName'}, tr('Build cache')),
      dim(tr('The next build (the planner) then takes longer and needs the internet.')),
      h('div', {class: 'row'}, dim(size(cache)), twoTaps('cache', tr('Clear'), tr('Really delete?'), () => ask('free=cache')))),
    !items.length && !cache && dim(tr('Nothing to delete right now.')),
    askedSince('room') !== null && bar({part: '', step: 'room', pct: null, since: askedSince('room')}),
    askedSince('free') !== null && bar({part: '', step: 'free', pct: null, since: askedSince('free')}),
    h('div', {class: 'row'},
      h('button', {class: 'control', disabled: busy(), onclick: () => ask('room')}, tr('Look again')),
      items.length > 1 ? twoTaps('all', tr('Delete all ({size})', {size: size(total)}), tr('Really delete?'), () => ask('free=all')) : h('span')),
  );
}

function render() {
  const app = document.getElementById('app');
  // not while something on the page is being typed or picked
  const active = document.activeElement;
  if (active && app.contains(active) && (active.tagName === 'INPUT' || active.tagName === 'SELECT') && active.type !== 'checkbox') return;
  document.getElementById('mower').textContent = mowerText();
  if (!st) {
    app.replaceChildren(dim(lost ? tr('The updater does not answer.') : '…'));
    return;
  }
  const pre = app.querySelector('pre.log');
  const scroll = pre ? pre.scrollTop : 0;
  const anyAuto = PARTS().some((p) => st.conf[p.id + '_auto'] === 1);
  // (what isn't there this time, false or null, isn't shown)
  app.replaceChildren(...[
    locked && h('div', {class: 'warn'}, tr('This page is shown inside another one, open it on its own to change anything:'), ' ',
      h('a', {href: location.origin + '/', target: '_blank', rel: 'noreferrer'}, location.origin)),
    dim(tr("Only with the mower idle in the dock. If a new version doesn't start, it goes back to the one before. Afterwards old images and the build cache are cleared away.")),
    // (embedded its head with the mower's state isn't there)
    document.documentElement.classList.contains('embed') && dim(tr('Mower right now: {what}', {what: mowerText()})),
    awayCard(),
    ...PARTS().map(partCard),
    selfCard(),
    addCard(),
    anyAuto && scheduleCard(),
    actionsCard(),
    roomCard(),
  ].filter(Boolean));
  const log = app.querySelector('pre.log');
  if (log) log.scrollTop = scroll;
}

// embedded: its height to MowBite, which gives the frame that height (no scrolling box in a box)
if (embedded && window.ResizeObserver) {
  new ResizeObserver(() => window.parent.postMessage({mowbiteUpdater: 'height', height: Math.ceil(document.body.getBoundingClientRect().height)}, '*')).observe(document.body);
}

loop();
