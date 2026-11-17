// MowBite Updater's page: on top what there is to do and the mower's state, then each part with what's installed,
// whether there's something new, updating it now and by itself, its channel and the way back, when, and folded away
// what's rare: making room, adding an app, the log. all through cgi-bin/updater
'use strict';

const API = 'cgi-bin/updater';

// --- words: english, german when the browser is ---
const DE = {
  // the top
  'Everything up to date': 'Alles aktuell',
  '1 update available': '1 Update verfügbar',
  '{n} updates available': '{n} Updates verfügbar',
  'Updates available: {names}.': 'Updates verfügbar: {names}.',
  'Not looked for updates yet': 'Noch nicht nach Updates gesucht',
  'Not known whether there are updates': 'Ob es Updates gibt, ist unbekannt',
  'No answer from GitHub and the registries. Does the mower have internet?': 'Keine Antwort von GitHub und den Registries. Hat der Mäher Internet?',
  'Last checked {t}.': 'Zuletzt geprüft {t}.',
  'Last checked {t}. It looks again every 6 hours by itself.': 'Zuletzt geprüft {t}. Er prüft alle 6 Stunden von selbst.',
  'No connection to the updater': 'Keine Verbindung zum Updater',
  'Shown is how things were {t}.': 'Angezeigt ist der Stand von {t}.',
  'The updater restarts on its new version…': 'Der Updater startet mit seiner neuen Version neu…',
  'Updating {name}…': 'Aktualisiert {name}…',
  '{name} goes back to the version before…': '{name} geht auf die vorige Version zurück…',
  'Looking for updates…': 'Sucht nach Updates…',
  'While that runs, the other buttons wait.': 'Solange das läuft, warten die anderen Knöpfe.',
  'Something went wrong with the last update of {name}': 'Beim letzten Update von {name} ging etwas schief',
  "The last update of {name} didn't start": 'Das letzte Update von {name} startete nicht',
  'More on its card below.': 'Mehr auf der Karte unten.',
  'It runs the version before again. More on its card below.': 'Es läuft wieder die vorige Version. Mehr auf der Karte unten.',
  'Mower ready in the dock, updates can run.': 'Mäher bereit im Dock, Updates können laufen.',
  "Mower ready, but not in the dock, or the dock has no power. Updates wait until it's ready in the dock.":
    'Mäher steht bereit, aber nicht im Dock, oder die Ladestation hat keinen Strom. Updates warten, bis er bereit im Dock steht.',
  "OpenMower doesn't answer, updates wait.": 'OpenMower antwortet nicht, Updates warten.',
  "Mower {what}. Updates wait until it's ready in the dock.": 'Mäher {what}. Updates warten, bis er bereit im Dock steht.',
  "The updater can't reach OpenMower (MQTT), updates wait.": 'Der Updater erreicht OpenMower nicht (MQTT), Updates warten.',
  'is mowing': 'mäht gerade',
  'is driving to the dock': 'fährt zum Dock',
  'is leaving the dock': 'fährt aus dem Dock',
  'is recording an area': 'nimmt eine Fläche auf',
  'Automatically: {when} ({names})': 'Automatisch: {when} ({names})',
  'Automatically: off': 'Automatisch: aus',
  'every night at {at}': 'jede Nacht um {at}',
  '{days} at {at}': '{days} um {at}',
  'Check for updates': 'Auf Updates prüfen',
  'Update all ({n})': 'Alle aktualisieren ({n})',
  'Asked…': 'Angefragt…',
  "Nothing updated: the mower wasn't ready in the dock. Tap again when it's there.":
    'Nichts aktualisiert: Der Mäher stand nicht bereit im Dock. Noch einmal tippen, wenn er dort steht.',
  "The last run waited: the mower wasn't ready in the dock. It tries again every 10 minutes for 3 hours.":
    'Der letzte Lauf hat gewartet: Der Mäher stand nicht bereit im Dock. Er versucht es 3 Stunden lang alle 10 Minuten wieder.',
  "The last run waited: the mower wasn't ready in the dock.": 'Der letzte Lauf hat gewartet: Der Mäher stand nicht bereit im Dock.',
  'The last run waited: the schedule starts the mower soon.': 'Der letzte Lauf hat gewartet: Der Zeitplan startet den Mäher bald.',
  'The last run was stopped halfway (the mower or the updater restarted), what had not started yet was put back.':
    'Der letzte Lauf wurde mittendrin unterbrochen (Mäher oder Updater neu gestartet), was noch nicht lief, wurde zurückgesetzt.',
  'The updater did not answer.': 'Der Updater hat nicht geantwortet.',
  'Not saved, the updater did not answer.': 'Nicht gespeichert, der Updater hat nicht geantwortet.',
  "If a new version doesn't start, it goes back to the one before. Afterwards it clears away old versions.":
    'Startet eine neue Version nicht, geht es zurück auf die vorige. Danach räumt er alte Versionen weg.',
  'Loading…': 'Lädt…',
  'The updater does not answer.': 'Der Updater antwortet nicht.',
  'It may be restarting right now. If that lasts longer than 2 minutes: look in Dockge, in the stack "mowbite", whether "mowbite-updater" runs.':
    'Er startet vielleicht gerade neu. Bleibt das länger als 2 Minuten so: in Dockge im Stack „mowbite“ nachsehen, ob „mowbite-updater“ läuft.',
  'This page is shown inside another one, open it on its own to change anything:': 'Diese Seite ist in eine andere eingebettet, zum Ändern bitte direkt öffnen:',
  'today, {t}': 'heute, {t}',
  'yesterday, {t}': 'gestern, {t}',
  // the parts
  'MowBite Planner': 'MowBite-Planer',
  'Runs the mower': 'Steuert den Mäher',
  'The app for the mower': 'Die App für den Mäher',
  'Plans the mowing lanes': 'Plant die Mähbahnen',
  'Keeps everything here up to date': 'Hält alles hier aktuell',
  'Added by you': 'Von dir hinzugefügt',
  'Other apps': 'Weitere Apps',
  'Update available': 'Update verfügbar',
  'Switch to the version picked': 'Wechsel auf gewählte Version',
  'Up to date': 'Aktuell',
  'Not checked yet': 'Noch nicht geprüft',
  'Unknown': 'Unbekannt',
  'Built here': 'Hier gebaut',
  'Skipped': 'Ausgelassen',
  "This version didn't start, it's left out until a newer one comes": 'Diese Version startete nicht, sie wird ausgelassen, bis eine neuere kommt',
  'With the OS': 'Mit dem OS',
  '{v} from {d}': '{v} vom {d}',
  'from {d} ({c})': 'Stand vom {d} ({c})',
  'from {d}': 'Stand vom {d}',
  'commit {c}': 'Commit {c}',
  'state unknown': 'Stand unbekannt',
  'Edge': 'Edge',
  'Release': 'Release',
  'Beta': 'Beta',
  'Stable': 'Stabil',
  'Version': 'Version',
  'Edge (newest)': 'Edge (neueste)',
  'Update': 'Aktualisieren',
  'Switch': 'Wechseln',
  'Try again': 'Erneut versuchen',
  'Replace with the official version': 'Durch offizielle Version ersetzen',
  'Automatically at night ({when})': 'Automatisch nachts ({when})',
  'The version before': 'Die vorige Version',
  'The version before, taking out': 'Die vorige Version, Entfernen',
  'Taking out': 'Entfernen',
  'Data kept': 'Gesicherte Daten',
  "Before each update the updater keeps a copy of this part's data on the mower, the newest two. Putting one back stops it, keeps what it has now first and starts it again, only with the mower ready in the dock.":
    'Vor jedem Update sichert der Updater die Daten dieses Teils auf dem Mäher, die neuesten zwei. Beim Zurückspielen hält er ihn an, sichert vorher den jetzigen Stand und startet ihn wieder, nur mit dem Mäher bereit im Dock.',
  'before the update, {when}: {what}': 'vor dem Update, {when}: {what}',
  'before putting data back, {when}: {what}': 'vor dem Zurückspielen, {when}: {what}',
  'all of its data': 'alle seine Daten',
  'the map (map.json)': 'die Karte (map.json)',
  'Put back': 'Zurückspielen',
  'Really put back?': 'Wirklich zurückspielen?',
  'Putting its data back': 'Spielt seine Daten zurück',
  'its data from {when} put back, what it had before is kept': 'Daten von {when} zurückgespielt, der Stand davor ist gesichert',
  "The new version didn't start and had changed the format of its data: it went back to the one before by itself, with its data from before the update. What it had then is kept.":
    'Die neue Version lief nicht und hatte das Format ihrer Daten geändert: zurück auf die vorige, mit den Daten von vor dem Update. Der Stand danach ist gesichert.',
  "its data couldn't be put back, see the log. The copies stay on the mower.": 'Daten ließen sich nicht zurückspielen, siehe Log. Die Sicherungen bleiben auf dem Mäher.',
  'this copy of its data is gone': 'diese Sicherung gibt es nicht mehr',
  'In line ({n} of {of})': 'Wartet ({n} von {of})',
  'comes with OpenMowerOS itself (openmower update-os)': 'kommt mit OpenMowerOS selbst (openmower update-os)',
  Runs: 'Läuft',
  Channel: 'Kanal',
  '{name} is being updated': '{name} wird aktualisiert',
  '{name} goes back': '{name} geht zurück',
  Ready: 'Vorbereitet',
  Downloaded: 'Heruntergeladen',
  Unpacked: 'Entpackt',
  Built: 'Gebaut',
  Restarted: 'Neu gestartet',
  Waited: 'Gewartet',
  'Back on the version before': 'Zurück auf der vorigen Version',
  'Its data put back': 'Daten zurückgespielt',
  'Checking…': 'Prüfe…',
  'nothing new, it was up to date': 'nichts Neues, er war aktuell',
  "With this version the MowBite Planner doesn't work: it needs two changes that are only in edge so far (OM_PLANNER=external and keeping the planner's settings per area).":
    'Mit dieser Version funktioniert der MowBite-Planer nicht: Er braucht zwei Änderungen, die bisher nur in Edge sind (OM_PLANNER=external und das Behalten der Planer-Einstellungen pro Fläche).',
  "Edge changes often, an update at night can bring a new fault. Only when there's room for the old and the new version at once.":
    'Edge ändert sich oft, ein Update in der Nacht kann einen neuen Fehler mitbringen. Nur wenn Platz für die alte und die neue Version zugleich ist.',
  "This version was built on its own, it isn't the official one.": 'Diese Version wurde selbst gebaut, sie ist nicht die offizielle.',
  'Stable is the newest release without "beta". It can be older than the beta that runs now, going there leaves out what came since.':
    'Stabil ist die neueste Version ohne „beta“. Sie kann älter sein als die Beta, die gerade läuft, dann fehlt, was seitdem dazukam.',
  'Stable is the default: the newest release without "beta". To get new planners first, pick Beta.':
    'Standard ist Stabil: das neueste Release ohne „beta“. Wer neue Planer zuerst will, stellt Beta ein.',
  'Stable is the newest release without "beta", built from its main branch as long as there is none. It can be older than the beta that runs now, going there leaves out what came since.':
    'Stabil ist die neueste Version ohne „beta“, solange es keine gibt, wird aus dem Hauptzweig gebaut. Sie kann älter sein als die Beta, die gerade läuft, dann fehlt, was seitdem dazukam.',
  'Built from a local copy, it is left as it is.': 'Aus einer lokalen Kopie gebaut, er bleibt, wie er ist.',
  'Updates also with the mower out of the dock.': 'Wird auch aktualisiert, wenn der Mäher nicht im Dock ist.',
  'Something wrong since the last update?': 'Seit dem letzten Update stimmt etwas nicht?',
  'Back to the version before': 'Zurück zur vorigen Version',
  'Really go back?': 'Wirklich zurück?',
  'Not to be updated here any more?': 'Nicht mehr mit aktualisieren?',
  'Take out': 'Herausnehmen',
  'Really take out?': 'Wirklich herausnehmen?',
  'It updates itself too, at night before the automatic updates.': 'Er aktualisiert sich auch selbst, nachts vor den automatischen Updates.',
  'Comes first, the page then loads again by itself and the apps follow.': 'Kommt zuerst dran, danach lädt die Seite von selbst neu und die Apps folgen.',
  'Restarting the updater, the page comes back by itself': 'Der Updater startet neu, die Seite kommt von selbst wieder',
  'Open the log': 'Protokoll öffnen',
  // the bars
  'Getting ready': 'Wird vorbereitet',
  'Downloading': 'Herunterladen',
  'Unpacking': 'Entpacken',
  'Building': 'Bauen',
  'Restarting': 'Neustart',
  'Waiting until OpenMower is ready again': 'Warten, bis OpenMower wieder bereit ist',
  'Waiting until it answers': 'Warten auf Antwort',
  'Going back to the version before': 'Zurück auf die vorige Version',
  "The new version didn't run, back to the one before": 'Neue Version lief nicht, zurück auf die vorige',
  'Looking for updates': 'Sucht nach Updates',
  'Looking what can go': 'Sieht nach, was weg kann',
  'Deleting': 'Löscht',
  'Updating right now…': 'Aktualisiert gerade…',
  'Updating {name} ({n} of {of})…': 'Aktualisiert {name} ({n} von {of})…',
  '{n} of {of} layers': '{n} von {of} Ebenen',
  'step {n} of {of}': 'Schritt {n} von {of}',
  // what happened last
  'Last time: {what}': 'Zuletzt: {what}',
  'Last time ({when}): {what}': 'Zuletzt ({when}): {what}',
  'updated': 'aktualisiert',
  'updated to {v}': 'aktualisiert auf {v}',
  'back to the version before': 'zurück auf die vorige Version',
  'back to the version before ({v})': 'zurück auf die vorige Version ({v})',
  'runs a version built here, updated only when asked': 'läuft mit einer hier gebauten Version, wird nur auf Anfrage aktualisiert',
  'not enough room on the mower: needs about {need} MB and some to spare, {free} MB free':
    'nicht genug Platz auf dem Mäher: braucht etwa {need} MB und etwas Reserve, {free} MB frei',
  "this version didn't start before, it waits for the next one": 'diese Version ist schon einmal nicht gestartet, er wartet auf die nächste',
  'stable {v} is older than what runs, it stays until a newer stable is out': 'Stabil {v} ist älter als die laufende Version, sie bleibt, bis es eine neuere stabile gibt',
  "The new version didn't start, it went back to the one before by itself. That version is left out, only the next one is tried again.":
    'Die neue Version ist nicht gestartet, er ist von selbst auf die vorige zurückgegangen. Diese Version lässt er aus, erst die nächste wird wieder versucht.',
  "The new version keeps the motors off, it needs newer firmware: openmower update-firmware. It went back to the one before by itself. After the firmware update, tap Try again.":
    'Die neue Version lässt die Motoren gesperrt, sie braucht neuere Firmware: openmower update-firmware. Er ist von selbst auf die vorige zurückgegangen. Nach dem Firmware-Update auf Erneut versuchen tippen.',
  "This update goes to another version line of OpenMower ({from} → {to}). It can need newer firmware: if the motors stay off after it, the updater goes back by itself and says so.":
    'Dieses Update wechselt die Versionslinie von OpenMower ({from} → {to}). Sie kann neuere Firmware brauchen: Bleiben die Motoren danach gesperrt, geht der Updater von selbst zurück und sagt es.',
  'older': 'älter',
  "not confirmed yet: the new version didn't answer as it should while the mower wasn't ready, nothing was restarted. The next run looks again":
    'noch nicht bestätigt: Die neue Version hat nicht wie erwartet geantwortet, während der Mäher nicht bereit war, deshalb wurde nichts neu gestartet. Der nächste Lauf sieht noch einmal nach',
  'not updated: {name} is stopped right now': 'nicht aktualisiert: {name} ist gerade gestoppt',
  'stopped, it stays stopped as it was': 'gestoppt, er bleibt gestoppt, wie er war',
  "not done: the mower wasn't ready in the dock. Tap again when it's there.": 'nicht gemacht: Der Mäher stand nicht bereit im Dock. Noch einmal tippen, wenn er dort steht.',
  "not done: the mower wasn't ready in the dock": 'nicht gemacht: Der Mäher stand nicht bereit im Dock',
  'not done: the schedule starts the mower {when}, OpenMower is left alone until then':
    'nicht gemacht: Der Zeitplan startet den Mäher {when}, bis dahin bleibt OpenMower, wie es ist',
  "nothing restarted: MowBite's schedule couldn't be held (mqtt)": 'nichts neu gestartet: Der Zeitplan von MowBite ließ sich nicht anhalten (MQTT)',
  "nothing changed: its data couldn't be kept first": 'nichts geändert: Seine Daten ließen sich vorher nicht sichern',
  'there is no version before to go back to': 'es gibt keine vorige Version zum Zurückgehen',
  "The version before didn't start, the one from before runs again.": 'Die vorige Version startete nicht, es läuft wieder die bisherige.',
  'going back failed, {name} may not be running': 'Zurückgehen fehlgeschlagen, {name} läuft womöglich nicht',
  'Download not possible. Does the mower have internet?': 'Download nicht möglich. Hat der Mäher Internet?',
  "GitHub can't be reached. Does the mower have internet?": 'GitHub nicht erreichbar. Hat der Mäher Internet?',
  'building failed': 'Bauen fehlgeschlagen',
  "the compose file couldn't be changed, nothing changed": 'die compose-Datei ließ sich nicht ändern, nichts geändert',
  "built anew, but it couldn't be set up on the new build, the one before stays": 'neu gebaut, ließ sich aber nicht neu anlegen, der vorige Stand bleibt',
  "The updater doesn't run from a compose file and can't update itself.": 'Der Updater läuft nicht aus einer compose-Datei und kann sich nicht selbst aktualisieren.',
  "nothing changed: the version before couldn't be kept": 'nichts geändert: Der vorige Stand ließ sich nicht sichern',
  "OpenMower's .env can't be read or changed, nothing changed": 'OpenMowers .env ließ sich nicht lesen oder ändern, nichts geändert',
  "the update of itself didn't start, the updater stays as it is": 'Selbst-Update nicht gestartet, der Updater bleibt, wie er ist',
  'no stable release found': 'kein stabiles Release gefunden',
  "not built: the OpenMower image it's built on isn't on the mower": 'nicht gebaut: Das OpenMower-Image, auf dem er aufbaut, ist nicht auf dem Mäher',
  'failed ({why})': 'fehlgeschlagen ({why})',
  "its update without a copy isn't finished": 'sein Update ohne Kopie ist nicht fertig',
  "a container couldn't be removed and one removed before couldn't be made again, see the log": 'ein Container ließ sich nicht entfernen, und einer der schon entfernten ließ sich nicht wieder anlegen, siehe Log',
  "{name} isn't on the mower right now: it's built again once the mower is idle in the dock.": '{name} ist gerade nicht auf dem Mäher: Es wird neu gebaut, sobald der Mäher ruhig im Dock steht.',
  'The version before runs again, started by hand. The new one isn\'t on the mower.': 'Die vorige Version läuft wieder, von Hand gestartet. Die neue ist nicht auf dem Mäher.',
  'By hand in a terminal on the mower, the version before:': 'Von Hand in einem Terminal auf dem Mäher, die vorige Version:',
  "a container couldn't be removed: nothing deleted, all runs as before": 'ein Container ließ sich nicht entfernen: nichts gelöscht, alles läuft wie vorher',
  "its update without a copy isn't done yet, that goes on first": 'sein Update ohne Kopie ist noch nicht fertig, das geht zuerst weiter',
  "OpenMower is being replaced: the version before is deleted, the new one doesn't run yet. The mower can't mow until then.":
    'OpenMower wird gerade ersetzt: Die vorige Version ist gelöscht, die neue läuft noch nicht. Bis dahin kann der Mäher nicht mähen.',
  "The new version couldn't be downloaded, there's no room for it even now. The one before came back from its registry.":
    'Die neue Version ließ sich nicht laden, auch jetzt reicht der Platz nicht. Die vorige kam aus ihrer Registry zurück.',
  "The new version couldn't be downloaded, its registry doesn't have it. The one before came back from its registry.":
    'Die neue Version ließ sich nicht laden, ihre Registry hat sie nicht. Die vorige kam aus ihrer Registry zurück.',
  "{name} isn't on the mower right now: it was deleted with OpenMower's version before and building it again failed. Update builds it again.":
    '{name} ist gerade nicht auf dem Mäher: Es wurde mit der vorigen OpenMower-Version gelöscht, und der Neubau ist gescheitert. Aktualisieren baut es neu.',
  // OpenMower without a copy
  "none, OpenMower isn't on the mower right now": 'keine, OpenMower ist gerade nicht auf dem Mäher',
  "Both versions don't fit side by side. This way the version that runs is deleted first, then the new one downloaded ({size}). Until then the mower has no OpenMower and can't mow.":
    'Beide Versionen passen nicht nebeneinander. So wird die laufende Version zuerst gelöscht, dann die neue geladen ({size}). Solange hat der Mäher kein OpenMower und kann nicht mähen.',
  "There's no way back on the mower itself: if the new one doesn't start, the updater downloads the old one again (that takes as long as the update and needs the internet).":
    'Auf dem Mäher selbst gibt es keinen Rückweg: Startet die neue nicht, lädt der Updater die alte noch einmal (dauert so lange wie das Update, braucht Internet).',
  "What's built on OpenMower ({names}) is deleted with it and built again afterwards. If building fails, the mower can only mow again once it's built.":
    'Was auf OpenMower gebaut ist ({names}), wird mit gelöscht und danach neu gebaut. Scheitert der Bau, kann der Mäher erst wieder mähen, wenn es gebaut ist.',
  'Deleted and downloaded or built again: {tags}.': 'Gelöscht und neu geladen oder neu gebaut: {tags}.',
  'Deleted for good: {tags}.': 'Für immer gelöscht: {tags}.',
  'Delete the old version and update': 'Alte Version löschen und aktualisieren',
  'Really delete it first?': 'Wirklich zuerst löschen?',
  "Deleting the old version first isn't possible here: {why}.": 'Die alte Version zuerst zu löschen, geht hier nicht: {why}.',
  "the version that runs can't be downloaded again from its registry (built here, or no answer)":
    'die laufende Version lässt sich nicht wieder aus ihrer Registry laden (hier gebaut oder keine Antwort)',
  "OpenMower's .env names another version than the one that runs": 'OpenMowers .env nennt eine andere Version als die laufende',
  "the size of the new version isn't known": 'die Größe der neuen Version ist unbekannt',
  "it isn't known which images hold the version that runs": 'es ist unbekannt, welche Images die laufende Version halten',
  "even then there isn't room enough (needs about {need}, {has} there)": 'auch dann reicht der Platz nicht (braucht etwa {need}, {has} da)',
  'the container "{name}" uses the version that runs and the updater can\'t build it again': 'der Container „{name}“ nutzt die laufende Version, und der Updater kann ihn nicht neu bauen',
  '{name} is built on OpenMower and the version picked comes under another name': '{name} ist auf OpenMower gebaut, und die gewählte Version kommt unter einem anderen Namen',
  "it isn't known what to build of {name} (GitHub doesn't answer)": 'es ist unbekannt, was von {name} gebaut werden soll (GitHub antwortet nicht)',
  "OpenMower isn't on the mower right now, the mower can't mow.": 'OpenMower ist gerade nicht auf dem Mäher, der Mäher kann nicht mähen.',
  'Next try by itself: {when}.': 'Nächster Versuch von selbst: {when}.',
  'No more tries by itself: tap Try again.': 'Keine Versuche von selbst mehr: auf Erneut versuchen tippen.',
  'By hand in a terminal on the mower, the new version:': 'Von Hand in einem Terminal auf dem Mäher, die neue Version:',
  'or the version before:': 'oder die vorige Version:',
  // MowBite OS in OpenMower's place
  'Switching to MowBite OS…': 'Wechselt zu MowBite OS…',
  'Going back to OpenMower…': 'Geht zurück zu OpenMower…',
  "OpenMower isn't back yet": 'OpenMower ist noch nicht zurück',
  "MowBite OS didn't run, OpenMower runs again": 'MowBite OS lief nicht, OpenMower läuft wieder',
  "More on OpenMower's card below.": 'Mehr auf der Karte von OpenMower unten.',
  "MowBite OS can take OpenMower's place on this mower. OpenMower's data is kept and OpenMower stopped, then MowBite OS is started and checked. If it doesn't run as it should, OpenMower comes back as it was.":
    'MowBite OS kann auf diesem Mäher an die Stelle von OpenMower treten. Die Daten von OpenMower werden gesichert und OpenMower gestoppt, dann wird MowBite OS gestartet und geprüft. Läuft es nicht wie erwartet, kommt OpenMower zurück, wie es war.',
  "MowBite OS takes over OpenMower's map and mower_params.yaml.": 'MowBite OS übernimmt die Karte und die mower_params.yaml von OpenMower.',
  "MowBite OS starts with its own map and settings from the last time it ran, not with OpenMower's current ones.":
    'MowBite OS startet mit seiner eigenen Karte und seinen Einstellungen vom letzten Mal, nicht mit den jetzigen von OpenMower.',
  "There isn't room for both: OpenMower's version is deleted first and downloaded again on the way back (that needs the internet).":
    'Für beide ist kein Platz: Die Version von OpenMower wird zuerst gelöscht und auf dem Rückweg neu geladen (das braucht Internet).',
  'Download: {size}. Only with the mower ready in the dock.': 'Download: {size}. Nur mit dem Mäher bereit im Dock.',
  'Only with the mower ready in the dock.': 'Nur mit dem Mäher bereit im Dock.',
  'Switch to MowBite OS': 'Zu MowBite OS wechseln',
  'Really switch?': 'Wirklich wechseln?',
  "Switching to MowBite OS isn't possible right now: {why}.": 'Der Wechsel zu MowBite OS geht gerade nicht: {why}.',
  "the version of MowBite OS that's set can't be found": 'die eingestellte Version von MowBite OS ist nicht zu finden',
  "there's no answer from where MowBite OS is downloaded (does the mower have internet?)": 'keine Antwort von dort, wo MowBite OS geladen wird (hat der Mäher Internet?)',
  "OpenMower's map and settings aren't in folders on the mower that MowBite OS could take them from":
    'Karte und Einstellungen von OpenMower liegen nicht in Ordnern auf dem Mäher, aus denen MowBite OS sie übernehmen kann',
  'mower_params.yaml has no position for the map (datum_lat and datum_long)': 'die mower_params.yaml hat keine Position für die Karte (datum_lat und datum_long)',
  "this version of MowBite OS can't take over OpenMower's map": 'diese Version von MowBite OS kann die Karte von OpenMower nicht übernehmen',
  'this version of MowBite OS has no setup for this mower': 'diese Version von MowBite OS bringt keine Einrichtung für diesen Mäher mit',
  "OpenMower doesn't run right now": 'OpenMower läuft gerade nicht',
  "OpenMower's update without a copy isn't finished yet": 'das Update von OpenMower ohne Kopie ist noch nicht fertig',
  'something else has to be finished first (an update, data put back or a calibration)': 'erst muss etwas anderes fertig werden (ein Update, zurückgespielte Daten oder eine Kalibrierung)',
  "there's a MowBite OS on the mower already that the updater didn't set up, it leaves that alone":
    'auf dem Mäher ist schon ein MowBite OS, das nicht der Updater eingerichtet hat, das lässt er in Ruhe',
  "there's no room for both, and OpenMower's version couldn't be downloaded again for the way back":
    'für beide ist kein Platz, und die Version von OpenMower ließe sich für den Rückweg nicht neu laden',
  "there isn't room enough even with OpenMower's version deleted (needs about {need}, {has} there)":
    'selbst ohne die Version von OpenMower reicht der Platz nicht (braucht etwa {need}, {has} da)',
  'MowBite OS runs the mower since {when}. OpenMower is stopped, its data stays as it was.': 'MowBite OS steuert den Mäher seit {when}. OpenMower ist gestoppt, seine Daten bleiben, wie sie waren.',
  'On the way back OpenMower gets the map from MowBite OS and is started and checked again. Only with the mower ready in the dock.':
    'Auf dem Rückweg bekommt OpenMower die Karte von MowBite OS und wird wieder gestartet und geprüft. Nur mit dem Mäher bereit im Dock.',
  "OpenMower's version is downloaded again, that needs the internet.": 'Die Version von OpenMower wird neu geladen, das braucht Internet.',
  'Back to OpenMower': 'Zurück zu OpenMower',
  "The way back to OpenMower stopped halfway, OpenMower doesn't run yet.": 'Der Rückweg zu OpenMower blieb auf halber Strecke stehen, OpenMower läuft noch nicht.',
  'Continue the way back': 'Rückweg fortsetzen',
  'Really continue?': 'Wirklich fortsetzen?',
  'Switching to MowBite OS': 'Wechsel zu MowBite OS',
  "If MowBite OS doesn't run as it should, OpenMower comes back as it was.": 'Läuft MowBite OS nicht wie erwartet, kommt OpenMower zurück, wie es war.',
  'The mower can mow again once OpenMower runs.': 'Der Mäher kann wieder mähen, sobald OpenMower läuft.',
  "MowBite OS didn't run as it should: {why}. OpenMower comes back as it was.": 'MowBite OS lief nicht wie erwartet: {why}. OpenMower kommt zurück, wie es war.',
  'The switch was given up: {why}. OpenMower comes back as it was.': 'Der Wechsel wurde abgebrochen: {why}. OpenMower kommt zurück, wie es war.',
  'the schedule starts the mower {when}': 'der Zeitplan startet den Mäher {when}',
  "MowBite's schedule couldn't be held": 'der Zeitplan von MowBite ließ sich nicht anhalten',
  "the mower wasn't ready in the dock": 'der Mäher stand nicht bereit im Dock',
  "something couldn't be stopped": 'etwas ließ sich nicht stoppen',
  "something else still answers on the mower's MQTT port": 'auf dem MQTT-Port des Mähers antwortet noch etwas anderes',
  "OpenMower's version can't be downloaded right now, it would be needed for the way back": 'die Version von OpenMower lässt sich gerade nicht laden, sie wäre für den Rückweg nötig',
  "OpenMower's data couldn't be kept first": 'die Daten von OpenMower ließen sich vorher nicht sichern',
  "MowBite OS couldn't be downloaded": 'MowBite OS ließ sich nicht laden',
  "A safety check in MowBite OS's setup failed, so it won't drive on its own. OpenMower doesn't know this check and will mow again without it.":
    'Eine Sicherheitsprüfung in der Einrichtung von MowBite OS ist fehlgeschlagen, deshalb fährt es nicht selbstständig. OpenMower kennt diese Prüfung nicht und mäht ohne sie wieder.',
  'Bringing OpenMower back': 'Holt OpenMower zurück',
  "Keeping OpenMower's data": 'Sichert die Daten von OpenMower',
  'Downloading MowBite OS': 'Lädt MowBite OS',
  'Stopping OpenMower': 'Stoppt OpenMower',
  "Deleting OpenMower's version": 'Löscht die Version von OpenMower',
  'Starting MowBite OS': 'Startet MowBite OS',
  'Checking that MowBite OS runs': 'Prüft, ob MowBite OS läuft',
  'Taking the map from MowBite OS': 'Holt die Karte aus MowBite OS',
  'Stopping MowBite OS': 'Stoppt MowBite OS',
  'Downloading OpenMower again': 'Lädt OpenMower neu',
  'Handing the map to OpenMower': 'Gibt OpenMower die Karte',
  "Keeping OpenMower's map from before": 'Behält die Karte von OpenMower von vorher',
  'Starting OpenMower': 'Startet OpenMower',
  "OpenMower's data kept": 'Daten von OpenMower gesichert',
  'MowBite OS downloaded': 'MowBite OS geladen',
  'OpenMower stopped': 'OpenMower gestoppt',
  "OpenMower's version deleted": 'Version von OpenMower gelöscht',
  'MowBite OS started': 'MowBite OS gestartet',
  'MowBite OS checked': 'MowBite OS geprüft',
  'Map taken from MowBite OS': 'Karte aus MowBite OS geholt',
  'No map from MowBite OS, OpenMower keeps its own': 'Keine Karte aus MowBite OS, OpenMower behält seine',
  'MowBite OS stopped': 'MowBite OS gestoppt',
  'OpenMower downloaded again': 'OpenMower neu geladen',
  'Map handed to OpenMower': 'Karte an OpenMower übergeben',
  "OpenMower's map from before kept": 'Karte von OpenMower von vorher behalten',
  'OpenMower started': 'OpenMower gestartet',
  "switched to MowBite OS, it took over OpenMower's map and settings": 'zu MowBite OS gewechselt, es hat Karte und Einstellungen von OpenMower übernommen',
  'switched to MowBite OS, with its own data from before': 'zu MowBite OS gewechselt, mit seinen eigenen Daten von vorher',
  "MowBite OS didn't run as it should: {why}. OpenMower runs again as before.": 'MowBite OS lief nicht wie erwartet: {why}. OpenMower läuft wieder wie vorher.',
  "it didn't start": 'es ist nicht gestartet',
  "it didn't get ready in time": 'es wurde nicht rechtzeitig bereit',
  'it stopped itself because of a fault': 'es hat sich wegen eines Fehlers selbst angehalten',
  "it didn't answer as MowBite OS for this mower": 'es hat sich nicht als MowBite OS für diesen Mäher gemeldet',
  "it didn't report the mower's state": 'es hat den Zustand des Mähers nicht gemeldet',
  'the mower stayed in emergency stop': 'der Mäher blieb im Notaus',
  "a part of it couldn't be downloaded": 'ein Teil davon ließ sich nicht laden',
  'its setup for this mower is missing': 'seine Einrichtung für diesen Mäher fehlt',
  "it can't take over OpenMower's map": 'es kann die Karte von OpenMower nicht übernehmen',
  'back on OpenMower, with the map from MowBite OS': 'zurück auf OpenMower, mit der Karte aus MowBite OS',
  "back on OpenMower with the map from MowBite OS, some areas couldn't be taken over": 'zurück auf OpenMower mit der Karte aus MowBite OS, manche Flächen ließen sich nicht übernehmen',
  'back on OpenMower, with its own map from before the switch': 'zurück auf OpenMower, mit seiner eigenen Karte von vor dem Wechsel',
  "nothing done: it isn't possible right now": 'nicht gemacht: Das geht gerade nicht',
  "nothing done: MowBite's schedule couldn't be held": 'nicht gemacht: Der Zeitplan von MowBite ließ sich nicht anhalten',
  "nothing done: OpenMower's data couldn't be kept first": 'nicht gemacht: Die Daten von OpenMower ließen sich vorher nicht sichern',
  "nothing done: MowBite OS couldn't be downloaded. Does the mower have internet?": 'nicht gemacht: MowBite OS ließ sich nicht laden. Hat der Mäher Internet?',
  'nothing done: this version of MowBite OS has no setup for this mower': 'nicht gemacht: Diese Version von MowBite OS bringt keine Einrichtung für diesen Mäher mit',
  "nothing done: this version of MowBite OS can't take over OpenMower's map": 'nicht gemacht: Diese Version von MowBite OS kann die Karte von OpenMower nicht übernehmen',
  "something couldn't be stopped, see the log": 'etwas ließ sich nicht stoppen, siehe Log',
  "something else still answers on the mower's MQTT port, MowBite OS can't run next to it. OpenMower runs again as before.":
    'auf dem MQTT-Port des Mähers antwortet noch etwas anderes, daneben kann MowBite OS nicht laufen. OpenMower läuft wieder wie vorher.',
  "nothing deleted: OpenMower's version can't be downloaded right now, it would be needed for the way back. OpenMower runs again as before.":
    'nichts gelöscht: Die Version von OpenMower lässt sich gerade nicht laden, sie wäre für den Rückweg nötig. OpenMower läuft wieder wie vorher.',
  "MowBite OS wasn't idle in the dock, it stays. Tap again when the mower is ready in the dock.":
    'MowBite OS stand nicht ruhig im Dock, es bleibt. Noch einmal tippen, wenn der Mäher bereit im Dock steht.',
  "OpenMower didn't come back, the mower can't mow. Tap Continue the way back.": 'OpenMower kam nicht zurück, der Mäher kann nicht mähen. Auf Rückweg fortsetzen tippen.',
  'stopped before anything changed (the mower or the updater restarted), OpenMower stays':
    'abgebrochen, bevor sich etwas geändert hat (der Mäher oder der Updater startete neu), OpenMower bleibt',
  "not done: stopped while MowBite OS runs in OpenMower's place": 'nicht gemacht: gestoppt, solange MowBite OS an Stelle von OpenMower läuft',
  'Stopped with OpenMower, it starts again once OpenMower is back.': 'Mit OpenMower gestoppt, es startet wieder, sobald OpenMower zurück ist.',
  // when
  'When it updates by itself': 'Wann automatisch aktualisiert wird',
  'At': 'Um',
  'every night': 'jede Nacht',
  'Days': 'Tage',
  "If the mower isn't ready in the dock then, it tries again every 10 minutes for 3 hours. The time is the mower's.":
    'Steht der Mäher dann nicht bereit im Dock, versucht er es 3 Stunden lang alle 10 Minuten wieder. Die Uhrzeit ist die des Mähers.',
  '{at} on the mower ({tz}) is {here} here.': '{at} auf dem Mäher ({tz}) ist hier {here}.',
  'Mon': 'Mo', 'Tue': 'Di', 'Wed': 'Mi', 'Thu': 'Do', 'Fri': 'Fr', 'Sat': 'Sa', 'Sun': 'So',
  // out of reach
  'Out of reach for the updater': 'Für den Updater nicht erreichbar',
  '"{name}" is in {dir}. The updater only sees {reach}. Move it there, or add this line to the updater\'s "volumes:":':
    '„{name}“ liegt in {dir}. Der Updater sieht nur {reach}. Dorthin verschieben oder diese Zeile bei den „volumes:“ des Updaters einfügen:',
  '"{name}" runs without a compose file, the updater can\'t update it.':
    '„{name}“ läuft ohne compose-Datei, das kann der Updater nicht aktualisieren.',
  'The updater doesn\'t see its own folder {dir}: it forgets its settings and can\'t update itself. Add this line to its "volumes:":':
    'Der Updater sieht seinen eigenen Ordner {dir} nicht: Er vergisst seine Einstellungen und kann sich nicht selbst aktualisieren. Diese Zeile bei seinen „volumes:“ einfügen:',
  'Copy': 'Kopieren',
  'copied': 'kopiert',
  // the folds
  'Make room': 'Platz schaffen',
  '{gb} GB free': '{gb} GB frei',
  '{size} can be freed': '{size} lassen sich freigeben',
  'Old versions and leftovers from building that nothing needs right now. After each update it clears away leftovers without a name, the unused leftovers from building and older versions beyond the ones kept by itself, the rest only when you tap it here. Versions kept to go back to only one at a time.':
    'Alte Versionen und Reste vom Bauen, die gerade nichts braucht. Nach jedem Update räumt er Reste ohne Namen, ungenutzte Reste vom Bauen und ältere Versionen über die behaltenen hinaus selbst weg, alles andere nur, wenn du es hier antippst. Aufgehobene Stände zum Zurückgehen nur einzeln.',
  'an old version without a name': 'eine alte Version ohne Namen',
  '{name}, the version before the update on {d}': '{name}, Stand vor dem Update am {d}',
  '{name}, the version before its last update': '{name}, Stand vor seinem letzten Update',
  '{name}, an older version': '{name}, ein älterer Stand',
  'kept to go back to': 'zum Zurückgehen aufgehoben',
  'left over, nothing uses it': 'übrig geblieben, nichts benutzt es',
  'nothing uses it right now': 'wird gerade nicht benutzt',
  'Leftovers from building': 'Reste vom Bauen',
  'Leftovers from building (the planner)': 'Reste vom Bauen (Planer)',
  'The next build then takes longer and needs the internet.': 'Der nächste Bau dauert dann länger und braucht Internet.',
  "The planner's next build then takes longer and needs the internet.": 'Der nächste Bau des Planers dauert dann länger und braucht Internet.',
  'Nothing to delete right now.': 'Gerade gibt es nichts zu löschen.',
  'Look again': 'Neu ansehen',
  'Delete': 'Löschen',
  'Clear': 'Leeren',
  'Really delete?': 'Wirklich löschen?',
  'Delete all but the ways back ({size})': 'Alles außer Rückwegen löschen ({size})',
  'Containers': 'Container',
  '{n} running': '{n} laufen',
  "The stacks' containers, like in Dockge: the last lines of their log and a restart. Passwords, tokens and access data stay hidden in the log.":
    'Die Container der Stacks, wie in Dockge: die letzten Zeilen ihres Logs und ein Neustart. Passwörter, Tokens und Zugangsdaten bleiben im Log verborgen.',
  "A restart only while OpenMower doesn't drive the mower, OpenMower itself only idle in the dock.":
    'Neu starten nur, solange OpenMower den Mäher nicht fährt, OpenMower selbst nur, wenn er ruhig im Dock steht.',
  'runs since {t}': 'läuft seit {t}',
  'stopped': 'gestoppt',
  'restarting': 'startet neu',
  '{n} restarts by itself': '{n} Neustarts von selbst',
  'Show the log': 'Log anzeigen',
  'The updater runs without a compose file: it forgets its settings and can\'t update itself. Start it from a stack, e.g. in Dockge or Portainer.': 'Der Updater läuft ohne Compose-Datei: Er vergisst seine Einstellungen und kann sich nicht selbst aktualisieren. Starte ihn aus einem Stack, z. B. in Dockge oder Portainer.',
  'Hide the log': 'Log ausblenden',
  'Restart': 'Neu starten',
  'Really restart?': 'Wirklich neu starten?',
  'restarts itself with its updates': 'startet bei seinen Updates selbst neu',
  'Getting the log…': 'Holt das Log…',
  'Restarting…': 'Startet neu…',
  'Looking at the containers…': 'Sieht nach den Containern…',
  'Look at the containers': 'Container ansehen',
  'Started again, {t}.': 'Neu gestartet, {t}.',
  "Not started again: the mower isn't idle in the dock.": 'Nicht neu gestartet: Der Mäher steht nicht ruhig im Dock.',
  'Not started again: OpenMower drives the mower.': 'Nicht neu gestartet: OpenMower fährt den Mäher gerade.',
  "Not started: it was stopped, it's only started the updater's own way.": 'Nicht gestartet: Er war gestoppt, starten tut ihn nur der Updater auf seinem Weg.',
  'Not started again: MowBite OS runs on the mower, OpenMower never runs next to it.': 'Nicht neu gestartet: Auf dem Mäher läuft MowBite OS, OpenMower läuft nie daneben.',
  'Started again, but it does not answer.': 'Neu gestartet, antwortet aber nicht.',
  "Couldn't be started again.": 'Konnte nicht neu gestartet werden.',
  'Newest at the bottom': 'Neueste unten',
  'Add another app': 'Weitere App aufnehmen',
  'Update other apps on the mower too': 'Andere Apps auf dem Mäher mit aktualisieren',
  'Any other app of your stacks, the updater then looks after it like the others: only with the mower ready in the dock, and back to the version before when the new one doesn\'t run for half a minute.':
    'Jede andere App deiner Stacks, der Updater kümmert sich dann wie um die anderen: nur wenn der Mäher bereit im Dock steht, und zurück auf die vorige Version, wenn die neue keine halbe Minute läuft.',
  'Pick an app': 'App auswählen',
  'Pick an app…': 'App auswählen…',
  'Add': 'Aufnehmen',
  'Log': 'Protokoll',
  'Newest at the top': 'Neueste oben',
};
// (MowBite passes its language on when it embeds the page)
const QUERY = new URLSearchParams(location.search);
const german = QUERY.get('lang') ? QUERY.get('lang') === 'de' : (navigator.language || '').toLowerCase().startsWith('de');
const LOCALE = german ? 'de-DE' : 'en-GB';
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
const fmt = (n, d) => n.toLocaleString(LOCALE, {minimumFractionDigits: d, maximumFractionDigits: d});

// --- what the updater says ---
let st = null;
// its answer as it came: the page is built anew only when that or what was done here changed
let lastRaw = '';
let shownKey = '';
let dirty = false;
let held = 0;
// what was asked on this page, and when: shown at once, until the updater shows it's on it
let asked = false;
let askedFor = '';
let askedAt = 0;
// (its run seen since: from then on its bars say it)
let askedRan = false;
// loads without an answer in a row, and when the last answer came
let misses = 0;
let lastOk = 0;
// a request without an answer, and where it was made: a part's id, 'schedule', 'room', 'add' or 'overview'
let failed = null;
let failedFor = '';
let sure = null;
let sureAt = 0;
let now = Date.now() / 1000;
// its start the page was loaded with: another one (its update) loads the page again, it may have changed
let started = null;
let reloading = false;
// the settings as the updater has them, and the ones on their way (sent, and come meanwhile): shown as set here
let savedConf = {};
let confSent = [];
let confWaiting = [];

const running = () => !!st && st.status.result === 'running';
// it restarts on its new version: since when, for a few minutes at most
function restarting() {
  const [state, t] = S('updater').split(' ');
  return state === 'restarting' && /^\d+$/.test(t || '') && now - Number(t) < 300 ? Number(t) : null;
}
// no answer for a while (a moment without one in a weak wlan isn't one), except while it restarts
const lost = () => misses >= (st ? 2 : 1) && !restarting();
// a request the updater took and works on before its bar shows (taken: "<since> now:<part> self back:<part> ..."): what
// and since when. a look for updates alone keeps nothing from being asked meanwhile, it stops for it
function taken() {
  const [since, ...what] = S('taken').split(' ');
  return {since: /^\d+$/.test(since || '') ? Number(since) : null, what: what.filter((w) => w && w !== 'check')};
}
// something on its way or running: the other requests wait for it
const working = () => asked || (!!st && (st.requested || taken().what.length > 0 || running() || !!restarting()));
// (shown in another page or without an answer: nothing to change from here)
const busy = () => locked || lost() || working();
// a request as the updater notes it when it takes it ("now:<part>", "data:<part>", "free", ...)
const wordOf = (query) => query.replace(/^now$/, 'now:all').replace('=', ':').replace(/^free:.*/, 'free').replace(/^(data:.*)-\d+$/, '$1');
// since when this was asked (on this page or taken by the updater), null when it wasn't: "now:<part>", "now:all",
// "back:<part>", "data:<part>", "self", "room", "free", "check"
function askedSince(what) {
  const word = wordOf(askedFor);
  if (asked && word === what) return askedAt / 1000;
  const t = taken();
  if (t.what.some((w) => (w.startsWith('free:') ? 'free' : w) === what)) return t.since;
  if (what === 'check' && S('taken').split(' ').includes('check')) return t.since;
  return null;
}
const looking = () => (/^\d+$/.test(S('looking')) ? Number(S('looking')) : askedSince('check'));
const stateKey = () => [lastRaw, lost(), asked, askedRan].join('|');

async function load() {
  let raw = null;
  try {
    const res = await fetch(API, {cache: 'no-store', signal: AbortSignal.timeout(8000)});
    if (!res.ok) throw new Error();
    raw = await res.text();
    st = JSON.parse(raw);
    misses = 0;
    lastOk = Date.now() / 1000;
  } catch {
    raw = null;
    misses++;
  }
  if (raw !== null) {
    lastRaw = raw;
    // a new start of it (its own update): the page anew, not while something is typed (it comes right after)
    if (started && st.status.started && st.status.started !== started) {
      if (!typing()) return void reloadFresh();
    } else started = st.status.started || started;
    savedConf = st.conf;
    showConf();
    noteStep();
    if (asked && running()) askedRan = true;
    // (a moment after asking: an answer from before it may not know of it yet)
    if (Date.now() - askedAt > 4000 && !st.requested && !taken().what.length && !running()) asked = false;
  }
  if (dirty || stateKey() !== shownKey) render();
}
// busybox httpd sends no cache-control: a reload alone may take app.js and style.css from the browser's cache (a build
// names them with its version, a copy run as it is doesn't), so they're fetched anew first
function reloadFresh() {
  if (reloading) return;
  reloading = true;
  const files = [...document.querySelectorAll('script[src], link[rel=stylesheet]')].map((e) => e.src || e.href);
  Promise.all(files.map((u) => fetch(u, {cache: 'reload'}).catch(() => {}))).then(() => location.reload());
}
// (as json, which only its own page and programs may send)
async function post(query, body) {
  if (locked) throw new Error();
  const res = await fetch(API + '?' + query, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: body || '', signal: AbortSignal.timeout(8000)});
  if (!res.ok || (await res.text()).trim() !== 'ok') throw new Error();
}
// where a request without an answer is said: on the card it was tapped on
function whereOf(query) {
  const [k, v] = query.split('=');
  if ((k === 'now' || k === 'back' || k === 'nokeep') && v) return v;
  if (k === 'data' && v) return wordOf(query).slice('data:'.length);
  if (k === 'self') return 'updater';
  if (k === 'switch') return 'os';
  if (k === 'room' || k === 'free') return 'room';
  if (k === 'containers' || k === 'logs' || k === 'restart') return 'containers';
  return 'overview';
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
    failedFor = whereOf(query);
    render();
  });
}
// the settings shown: the updater's with the ones on their way over them
function showConf() {
  st.conf = Object.assign({}, savedConf, ...confSent.map((c) => c.patch), ...confWaiting.map((c) => c.patch));
}
// only what changed: a value it shows but nobody set (OpenMower's channel from its .env) stays unset. one post after the
// other (it writes them whole), what comes meanwhile goes together after it. true once saved
function setConf(patch, where) {
  failed = null;
  return new Promise((done) => {
    confWaiting.push({patch, where: where || confWhere(patch), done});
    showConf();
    render();
    sendConf();
  });
}
// a setting from there on its way: its button waits for it
const saving = (where) => [...confSent, ...confWaiting].some((c) => c.where === where);
function confWhere(patch) {
  const k = Object.keys(patch)[0];
  if (k === 'at' || k === 'days') return 'schedule';
  if (k === 'picked') return 'add';
  return k.replace(/_auto$/, '');
}
function sendConf() {
  if (confSent.length || !confWaiting.length) return;
  confSent = confWaiting;
  confWaiting = [];
  const patch = Object.assign({}, ...confSent.map((c) => c.patch));
  const lines = Object.keys(patch).map((k) => k + ' ' + patch[k]);
  post('conf', lines.join('\n') + '\n').then(
    () => {
      const sent = confSent;
      confSent = [];
      Object.assign(savedConf, patch);
      sent.forEach((c) => c.done(true));
      sendConf();
    },
    () => {
      // (not saved: back to what the updater has)
      const sent = confSent;
      confSent = [];
      showConf();
      failed = tr('Not saved, the updater did not answer.');
      failedFor = sent[sent.length - 1].where;
      render();
      sent.forEach((c) => c.done(false));
      sendConf();
    },
  );
}

// a hidden page asks seldom, one with something running often
function loop() {
  load().finally(() => setTimeout(loop, document.hidden ? 30000 : working() || looking() !== null ? 2000 : 5000));
}
document.addEventListener('visibilitychange', () => !document.hidden && load());
// the seconds on the bars count on by themselves, the page is built anew only when its restart is over
let wasRestarting = false;
setInterval(() => {
  now = Date.now() / 1000;
  if (!!restarting() !== wasRestarting) return void render();
  for (const e of document.querySelectorAll('[data-since]')) e.textContent = sinceText(Number(e.dataset.since));
}, 1000);

// typed or picked in a field right now: not built anew under the finger, a few seconds after the last key at most
let typingAt = 0;
let pointerAt = 0;
const field = (e) => !!e && (e.tagName === 'SELECT' || (e.tagName === 'INPUT' && e.type !== 'checkbox'));
for (const ev of ['keydown', 'input', 'pointerdown']) document.addEventListener(ev, (e) => field(e.target) && (typingAt = Date.now()), true);
document.addEventListener('pointerdown', () => (pointerAt = Date.now()), true);
function typing() {
  const a = document.activeElement;
  return field(a) && document.getElementById('app').contains(a) && Date.now() - typingAt < 5000;
}
// a selection in the page (the log, a line to copy) stays while it's copied, for half a minute at most
let selAt = 0;
function selecting() {
  const s = window.getSelection();
  if (!s || s.isCollapsed || !document.getElementById('app').contains(s.anchorNode)) {
    selAt = 0;
    return false;
  }
  selAt = selAt || Date.now();
  return Date.now() - selAt < 30000;
}
// a pick with the finger or the mouse is done once picked, one with the keyboard goes on
const pickedBy = (e) => Date.now() - pointerAt < 3000 && e.target.blur();

// --- the parts, in words ---
const PARTS = () => (st && st.parts) || [];
const S = (k) => (st && st.status[k]) || '';
// the parts and itself, as their cards show them
const ALL = () => [...PARTS(), ...(S('updater_running') ? [{id: 'updater', kind: 'image', name: 'MowBite Updater'}] : [])];
const nameOf = (p) => (p.id === 'planner' ? tr('MowBite Planner') : p.name || p.container || p.id);
const avail = (id) => S(id + '_available').split(' ')[0];
const date = (d) => (/^\d{4}-\d\d-\d\d$/.test(d || '') ? new Date(d + 'T12:00:00').toLocaleDateString(LOCALE) : null);
// a time: today and yesterday in words, else its date
function when(t) {
  if (!t) return '?';
  const d = new Date(Number(t) * 1000);
  const day = (x) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime();
  const ago = Math.round((day(new Date()) - day(d)) / 86400000);
  const time = d.toLocaleTimeString(LOCALE, {hour: '2-digit', minute: '2-digit'});
  if (ago === 0) return tr('today, {t}', {t: time});
  if (ago === 1) return tr('yesterday, {t}', {t: time});
  return d.toLocaleDateString(LOCALE) + ', ' + time;
}
const size = (b) => (b >= 1e9 ? fmt(b / 1e9, 1) + ' GB' : b >= 1e6 ? Math.round(b / 1e6) + ' MB' : Math.max(0, Math.round(b / 1e3)) + ' kB');
const freeMb = () => (/^\d+$/.test(S('disk_free')) ? Number(S('disk_free')) : null);
const DAY_NAMES = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const nightDays = () => (st.conf.days === 'daily' ? [] : String(st.conf.days).split(',').map(Number).filter((d) => d >= 1 && d <= 7));
const autoOn = (id) => st.conf[id + '_auto'] === 1;

// what runs: the version and its day, of a build its release or else its commit, of an app with channels the one it
// follows (when there's no pick for it), of the updater its release (its commit for a build of main)
function installed(p, picker) {
  if (p.kind === 'os') return tr('comes with OpenMowerOS itself (openmower update-os)');
  const [what, day] = S(p.id + '_running').split(' ');
  if (p.kind === 'openmower' && what === 'missing') return tr("none, OpenMower isn't on the mower right now");
  const d = date(day);
  const chan = !picker && (S(p.id + '_stable') || st.conf[p.id] === 'stable') ? ' · ' + tr(st.conf[p.id] === 'stable' ? 'Stable' : 'Beta') : '';
  let v;
  if (p.id === 'updater' && S('updater_release')) {
    v = d ? tr('{v} from {d}', {v: S('updater_release'), d}) : S('updater_release');
  } else if (p.kind === 'build' && S(p.id + '_release')) {
    const rel = S(p.id + '_release');
    v = (d ? tr('{v} from {d}', {v: rel, d}) : rel) + (what && what !== '?' ? ' (' + what.slice(0, 7) + ')' : '');
    v += chan;
  } else if (p.kind === 'build' || p.kind === 'local' || p.id === 'updater') {
    const c = what && what !== '?' ? what.slice(0, 7) : null;
    v = d && c ? tr('from {d} ({c})', {d, c}) : d ? tr('from {d}', {d}) : c ? tr('commit {c}', {c}) : tr('state unknown');
  } else {
    const name = p.kind === 'openmower' ? {edge: tr('Edge'), latest: tr('Release')}[what] || what : what;
    v = name && d ? tr('{v} from {d}', {v: name, d}) : name || d || tr('state unknown');
    if (p.kind === 'image') v += chan;
  }
  return p.kind === 'openmower' && osParked(p) ? v + ' · ' + tr('stopped') : v;
}
// what runs and the channel to pick, as in MowBite
const facts = (p, picker) => h('div', {class: 'facts'}, h('span', null, tr('Runs')), h('span', null, installed(p, picker)),
  picker && [h('span', null, tr('Channel')), picker]);
const BADGE = {
  yes: 'Update available',
  switch: 'Switch to the version picked',
  no: 'Up to date',
  failed: 'Skipped',
  local: 'Built here',
  os: 'With the OS',
};
function badge(p) {
  const a = avail(p.id) || (p.kind === 'os' ? 'os' : '');
  if (a === 'failed') return h('span', {class: 'badge bad', title: tr("This version didn't start, it's left out until a newer one comes")}, tr(BADGE.failed));
  // (a part not looked at yet, or no answer when it was)
  if (!BADGE[a]) return h('span', {class: 'badge'}, tr(a === 'unknown' && S('checked') ? 'Unknown' : 'Not checked yet'));
  return h('span', {class: 'badge' + (a === 'yes' || a === 'switch' ? ' new' : '')}, tr(BADGE[a]));
}
const SUB = {openmower: 'Runs the mower', mowbite: 'The app for the mower', planner: 'Plans the mowing lanes', updater: 'Keeps everything here up to date'};
function head(p) {
  const sub = SUB[p.id] ? tr(SUB[p.id]) : S(p.id + '_picked') === 'yes' ? tr('Added by you') : null;
  return h('div', {class: 'head'}, h('div', {class: 'title'}, h('span', {class: 'name'}, nameOf(p)), sub && h('small', null, sub)), badge(p));
}

// when its last result came: <part>_at from the updater, else the time an update or a step back carries itself
function resultAt(p) {
  const at = S(p.id + '_at');
  if (/^\d+$/.test(at)) return Number(at);
  const [state, t] = S(p.id).split(' ');
  return ['updated', 'back', 'rolled_back'].includes(state) && /^\d+$/.test(t || '') ? Number(t) : null;
}
const DAYS3 = 3 * 86400;
// its last result in words and how bad: ok (as it should), warn (nothing done, or it went back by itself), error (it
// failed, see the log). being up to date isn't news
const ERRORS = {
  pull: 'Download not possible. Does the mower have internet?',
  registry: 'Download not possible. Does the mower have internet?',
  github: "GitHub can't be reached. Does the mower have internet?",
  build: 'building failed',
  compose: "the compose file couldn't be changed, nothing changed",
  keep: "nothing changed: the version before couldn't be kept",
  env: "OpenMower's .env can't be read or changed, nothing changed",
  helper: "the update of itself didn't start, the updater stays as it is",
  no_stable: 'no stable release found',
  base_missing: "not built: the OpenMower image it's built on isn't on the mower",
  hold: "nothing restarted: MowBite's schedule couldn't be held (mqtt)",
  data: "nothing changed: its data couldn't be kept first",
  data_put: "its data couldn't be put back, see the log. The copies stay on the mower.",
  no_data: 'this copy of its data is gone',
  missing: "its update without a copy isn't finished",
  remove: "a container couldn't be removed: nothing deleted, all runs as before",
  undo: "a container couldn't be removed and one removed before couldn't be made again, see the log",
  nokeep: "its update without a copy isn't done yet, that goes on first",
};
function result(p) {
  const [state, ...rest] = S(p.id).split(' ');
  const ok = (text) => ({text, level: 'ok'});
  const warn = (text) => ({text, level: 'warn'});
  switch (state) {
    case 'updated':
      return ok(rest[1] ? tr('updated to {v}', {v: rest[1]}) : tr('updated'));
    // (asked to update itself: said once, its badge doesn't change)
    case 'current':
      return p.id === 'updater' ? ok(tr('nothing new, it was up to date')) : null;
    case 'back':
      return ok(rest[1] ? tr('back to the version before ({v})', {v: rest[1]}) : tr('back to the version before'));
    case 'data_back':
      return ok(tr('its data from {when} put back, what it had before is kept', {when: when(rest[1])}));
    case 'local':
      // (a build from a copy says so already)
      return p.kind === 'local' ? null : ok(tr('runs a version built here, updated only when asked'));
    case 'nospace':
      return warn(tr('not enough room on the mower: needs about {need} MB and some to spare, {free} MB free', {need: rest[0] || '?', free: rest[1] || '?'}));
    case 'skipped_failed':
      return warn(tr("this version didn't start before, it waits for the next one"));
    case 'stable_older':
      return warn(tr('stable {v} is older than what runs, it stays until a newer stable is out', {v: rest[0] || '?'}));
    case 'replacing':
      return warn(tr("OpenMower is being replaced: the version before is deleted, the new one doesn't run yet. The mower can't mow until then."));
    case 'rolled_back':
      // (the version before runs again)
      if (rest[0] === 'nospace') return warn(tr("The new version couldn't be downloaded, there's no room for it even now. The one before came back from its registry."));
      if (rest[0] === 'hand') return warn(tr('The version before runs again, started by hand. The new one isn\'t on the mower.'));
      if (rest[0] === 'unknown') return warn(tr("The new version couldn't be downloaded, its registry doesn't have it. The one before came back from its registry."));
      if (rest[0] === 'data') {
        return warn(tr("The new version didn't start and had changed the format of its data: it went back to the one before by itself, with its data from before the update. What it had then is kept."));
      }
      if (rest[0] === 'firmware') {
        return warn(tr("The new version keeps the motors off, it needs newer firmware: openmower update-firmware. It went back to the one before by itself. After the firmware update, tap Try again."));
      }
      return warn(tr("The new version didn't start, it went back to the one before by itself. That version is left out, only the next one is tried again."));
    case 'unconfirmed':
      return warn(tr("not confirmed yet: the new version didn't answer as it should while the mower wasn't ready, nothing was restarted. The next run looks again"));
    case 'stopped':
      // (a build made anew on OpenMower's new version while stopped stays so, there's nothing newer then. one stopped
      // when its own update came was left as it is)
      return p.kind === 'build' && avail(p.id) === 'no'
        ? ok(tr('stopped, it stays stopped as it was'))
        : warn(tr('not updated: {name} is stopped right now', {name: nameOf(p)}));
    case 'error':
      if (rest[0] === 'not_docked') return warn(tr("not done: the mower wasn't ready in the dock. Tap again when it's there."));
      // (OpenMower, in the 30 minutes before MowBite's schedule may start the mower)
      if (rest[0] === 'schedule') return ok(tr('not done: the schedule starts the mower {when}, OpenMower is left alone until then', {when: when(rest[1])}));
      if (rest[0] === 'no_back') return warn(tr('there is no version before to go back to'));
      if (rest[0] === 'os') return ok(tr("not done: stopped while MowBite OS runs in OpenMower's place"));
      if (rest[0] === 'back') return warn(tr("The version before didn't start, the one from before runs again."));
      if (rest[0] === 'compose' && p.id === 'updater') return {text: tr("The updater doesn't run from a compose file and can't update itself."), level: 'error'};
      // (a build changes no compose file: the stopped one couldn't be made anew on it)
      if (rest[0] === 'compose' && p.kind === 'build') return {text: tr("built anew, but it couldn't be set up on the new build, the one before stays"), level: 'error'};
      if (rest[0] === 'rollback') return {text: tr('going back failed, {name} may not be running', {name: nameOf(p)}), level: 'error'};
      // (deleted with OpenMower's version before)
      if (rest[0] === 'gone_dock') return warn(tr("{name} isn't on the mower right now: it's built again once the mower is idle in the dock.", {name: nameOf(p)}));
      if (rest[0] === 'gone') return {text: tr("{name} isn't on the mower right now: it was deleted with OpenMower's version before and building it again failed. Update builds it again.", {name: nameOf(p)}), level: 'error'};
      return {text: ERRORS[rest[0]] ? tr(ERRORS[rest[0]]) : tr('failed ({why})', {why: rest.join(' ') || '?'}), level: 'error'};
    default:
      return null;
  }
}
function openLog() {
  folds.log = true;
  render();
  const log = document.getElementById('log');
  if (log) log.scrollIntoView({block: 'start'});
}
function resultLine(p) {
  // (a part that only waited for the dock: what to do is said once at the top)
  const waited = S('result') === 'waiting' && S(p.id) === 'error not_docked';
  return lastLine(waited ? {text: tr("not done: the mower wasn't ready in the dock"), level: 'ok'} : result(p), resultAt(p), p.id);
}
// a last result and when: dim as it should be, yellow, red with the log
function lastLine(r, at, key) {
  if (!r) return null;
  const text = at !== null ? tr('Last time ({when}): {what}', {when: when(at), what: r.text}) : tr('Last time: {what}', {what: r.text});
  if (r.level === 'ok') return dim(text);
  if (r.level === 'warn') return h('p', {class: 'warn'}, text);
  const link = !locked && st.log && st.log.length > 0 && h('button', {class: 'link', 'data-key': 'log:' + key, onclick: openLog}, tr('Open the log'));
  return h('p', {class: 'error'}, text, link && [' ', link]);
}
// a part whose last update went wrong lately, for the top: red for a failure (within 3 days when the updater says when,
// else one that may have left it not running), yellow for a new version that didn't start and was left
function troubled() {
  let found = null;
  for (const p of ALL()) {
    const r = result(p);
    if (!r || r.level === 'ok') continue;
    const at = resultAt(p);
    const fresh = at !== null ? now - at < DAYS3 : null;
    const [state, code] = S(p.id).split(' ');
    if (r.level === 'error' && (fresh || (fresh === null && code === 'rollback'))) return {p, tone: 'bad'};
    if (state === 'rolled_back' && fresh && !found) found = {p, tone: 'wait'};
  }
  return found;
}

// what it does right now, for the bar
const STEPS = ['prepare', 'download', 'extract', 'build', 'restart', 'wait', 'back', 'data'];
function progressOf() {
  const [part, step, pct, since, done, of] = S('progress').split(' ');
  const n = (x) => (/^\d+$/.test(x || '') ? Number(x) : undefined);
  return {part, step, pct: n(pct) === undefined ? null : Math.min(100, n(pct)), since: n(since), done: n(done), of: n(of)};
}
function progressNow() {
  const p = running() ? progressOf() : null;
  return p && STEPS.includes(p.step) ? {...p, since: p.since || 0} : null;
}
const runParts = () => (running() ? S('run_parts').split(' ').filter(Boolean) : []);
// each part's step before the one it's on: back right after its restart is a new version that didn't run
const stepNow = {};
const stepBefore = {};
function noteStep() {
  const p = progressNow();
  if (p && stepNow[p.part] !== p.step) {
    stepBefore[p.part] = stepNow[p.part];
    stepNow[p.part] = p.step;
  }
}
const didntRun = (p) => p.step === 'back' && ['restart', 'wait'].includes(stepBefore[p.part]) && askedFor !== 'back=' + p.part;
function stepLabel(p) {
  if (p.label) return p.label;
  if (didntRun(p)) return tr("The new version didn't run, back to the one before");
  return tr(
    {
      prepare: 'Getting ready',
      download: 'Downloading',
      extract: 'Unpacking',
      build: 'Building',
      restart: 'Restarting',
      wait: p.part === 'openmower' ? 'Waiting until OpenMower is ready again' : 'Waiting until it answers',
      back: 'Going back to the version before',
      data: 'Putting its data back',
      look: 'Looking for updates',
      room: 'Looking what can go',
      free: 'Deleting',
    }[p.step],
  );
}
// a step once it's done
const STEP_DONE = {
  prepare: 'Ready', download: 'Downloaded', extract: 'Unpacked', build: 'Built', restart: 'Restarted', wait: 'Waited',
  back: 'Back on the version before', data: 'Its data put back',
};
// the steps a part's run goes through, as in MowBite: one taken back or its data put back as asked, the updater itself,
// a build, else a download. a new version that doesn't run goes back after its wait
function stepsOf(id, step) {
  const p = ALL().find((x) => x.id === id) || {kind: 'image'};
  const steps = askedSince('back:' + id) !== null || (step === 'back' && !stepBefore[id]) ? ['back', 'restart', 'wait']
    : askedSince('data:' + id) !== null || (step === 'data' && !stepBefore[id]) ? ['data', 'restart', 'wait']
      : id === 'updater' ? ['prepare', 'download', 'restart']
        : p.kind === 'build' || p.kind === 'local' ? ['prepare', 'build', 'restart', 'wait']
          : ['prepare', 'download', 'extract', 'restart', 'wait'];
  if (step === 'data' && !steps.includes('data') && !steps.includes('back')) steps.push('back');
  if (!steps.includes(step)) steps.push(step);
  return steps;
}
// how far, besides the time it's on it
function stepDetail(p) {
  // (a step of the way to MowBite OS or back: what its bar does in it)
  if (p.pstep) p = {...p, step: p.pstep};
  if (p.step === 'extract' && p.of) return tr('{n} of {of} layers', {n: p.done || 0, of: p.of});
  if (p.step === 'build' && p.of) return tr('step {n} of {of}', {n: Math.min(p.of, (p.done || 0) + 1), of: p.of});
  if (p.pct !== null && p.step === 'download') return p.pct + ' %';
  return '';
}
// the time since it began, not the time it has left
function sinceText(t) {
  const secs = Math.max(0, Math.round(now - t));
  return Math.floor(secs / 60) + ':' + String(secs % 60).padStart(2, '0');
}
function runText() {
  if (!running()) return null;
  const p = progressNow();
  const parts = runParts();
  if (parts.includes('os')) return tr(osWay() === 'os' && !osUndo() ?'Switching to MowBite OS…' : 'Going back to OpenMower…');
  const part = p && ALL().find((x) => x.id === p.part);
  if (!part || !parts.includes(p.part)) return tr('Updating right now…');
  if (parts.length === 1) return tr('Updating {name}…', {name: nameOf(part)});
  return tr('Updating {name} ({n} of {of})…', {name: nameOf(part), n: parts.indexOf(p.part) + 1, of: parts.length});
}
// the night's window open now on the mower's clock (else this device's): within 3 hours after its time, on a day it
// runs, with something to update by itself
function nightWindow() {
  const [hh, mm] = String(st.conf.at).split(':').map(Number);
  if (Number.isNaN(hh) || Number.isNaN(mm) || !PARTS().some((p) => autoOn(p.id))) return false;
  const off = mowerOffset();
  // (the mower's time of day in the utc fields of a date)
  const t = new Date((now + (off === null ? -new Date().getTimezoneOffset() : off) * 60) * 1000);
  const since = (((t.getUTCHours() * 60 + t.getUTCMinutes() - hh * 60 - mm) % 1440) + 1440) % 1440;
  const day = new Date(t.getTime() - since * 60000).getUTCDay() || 7;
  return since < 180 && (st.conf.days === 'daily' || nightDays().includes(day));
}
// how the last run ended, when that's news: one asked for here (or one that left a part waiting) can be tapped again,
// the night's tries again by itself while its window is open
function lastRun() {
  const r = S('result');
  if (r === 'waiting') {
    if (S('openmower').startsWith('error schedule') && !ALL().some((p) => S(p.id) === 'error not_docked'))
      return dim(tr('The last run waited: the schedule starts the mower soon.'));
    if (askedFor.startsWith('now') || ALL().some((p) => S(p.id) === 'error not_docked'))
      return h('p', {class: 'warn'}, tr("Nothing updated: the mower wasn't ready in the dock. Tap again when it's there."));
    return dim(nightWindow()
      ? tr("The last run waited: the mower wasn't ready in the dock. It tries again every 10 minutes for 3 hours.")
      : tr("The last run waited: the mower wasn't ready in the dock."));
  }
  if (r === 'interrupted') return dim(tr('The last run was stopped halfway (the mower or the updater restarted), what had not started yet was put back.'));
  return null;
}
// OpenMower's states besides idle, in words
const STATES = {MOWING: 'is mowing', DOCKING: 'is driving to the dock', UNDOCKING: 'is leaving the dock', AREA_RECORDING: 'is recording an area'};
// the mower right now, whether updates can run: a word, no lock (its state is up to a minute old, and some parts don't
// wait for the dock)
function mowerLine() {
  const m = S('mower');
  let text;
  if (m === '1') text = tr('Mower ready in the dock, updates can run.');
  // (idle without the dock's voltage: out of it, or the dock without power)
  else if (m === '0 IDLE') text = tr("Mower ready, but not in the dock, or the dock has no power. Updates wait until it's ready in the dock.");
  else if (m === '0 unknown') text = tr("OpenMower doesn't answer, updates wait.");
  else if (m.startsWith('0 ')) {
    const what = STATES[m.slice(2)] ? tr(STATES[m.slice(2)]) : m.slice(2).toLowerCase().replace(/_/g, ' ');
    text = tr("Mower {what}. Updates wait until it's ready in the dock.", {what});
  }
  else text = tr("The updater can't reach OpenMower (MQTT), updates wait.");
  return h('p', {class: 'state'}, h('span', {class: 'dot' + (m === '1' ? '' : ' wait')}), h('span', null, text));
}
// "every night at 03:00", "Mon, Wed at 03:00", and for a tick "03:00, Mon, Wed"
const dayNames = () => nightDays().map((d) => tr(DAY_NAMES[d - 1]));
const nightText = () => (st.conf.days === 'daily' ? tr('every night at {at}', {at: st.conf.at}) : tr('{days} at {at}', {days: dayNames().join(', '), at: st.conf.at}));
const tickText = () => [st.conf.at, ...dayNames()].join(', ');

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
function copyButton(key, text) {
  const b = h('button', {class: 'control', 'data-key': key, onclick: () => {
    copyText(text);
    b.textContent = tr('copied');
    setTimeout(() => (b.textContent = tr('Copy')), 1500);
  }}, tr('Copy'));
  return b;
}
// a delete or a step back takes two taps: the first asks, for a few seconds. (a double tap isn't a yes)
function twoTaps(key, label, question, go) {
  return h('button', {
    class: 'control' + (sure === key ? ' danger' : ''),
    'data-key': key,
    disabled: busy(),
    onclick: () => {
      if (sure !== key) {
        const at = Date.now();
        sure = key;
        sureAt = at;
        setTimeout(() => {
          if (sure === key && sureAt === at) {
            sure = null;
            render();
          }
        }, 4000);
        render();
        return;
      }
      if (Date.now() - sureAt < 600) return;
      sure = null;
      go();
    },
  }, sure === key ? question : label);
}
// folds kept as left while the page is built anew: open as tapped, else as its state says, and open while it has a bar
const folds = {};
function fold(key, force, auto, name, sub, ...body) {
  const open = force || (key in folds ? folds[key] : auto);
  return h('details', {class: 'card fold', id: key, open, ontoggle: (e) => e.target.open !== open && (folds[key] = e.target.open)},
    h('summary', {'data-key': 'fold:' + key}, h('span', {class: 'title'}, h('span', {class: 'name'}, name), sub && h('small', null, sub))),
    h('div', {class: 'foldBody'}, body));
}
const openMore = new Set();
// what's folded away in a part's card, open as it was left
const more = (key, label, ...body) => h('details', {class: 'more', open: openMore.has(key), ontoggle: (e) => (e.target.open ? openMore.add(key) : openMore.delete(key))},
  h('summary', {'data-key': 'more:' + key}, tr(label)),
  h('div', {class: 'moreBody'}, body));

// a part asked for that isn't on its bar yet: from the tap on, so something moves at once. in a run before its first
// step only the first one (the others are in line), the time since it was asked when known
function waiting(id) {
  const prog = progressNow();
  const parts = runParts();
  if (parts.includes(id)) return !prog && parts.indexOf(id) === 0 ? {step: 'prepare', since: askedSince('now:' + id) || askedSince('now:all')} : null;
  const back = askedSince('back:' + id);
  if (back !== null) return {step: 'back', since: back};
  const data = askedSince('data:' + id);
  if (data !== null) return {step: 'data', since: data};
  const t = askedUpdate(id);
  return t !== null ? {step: 'prepare', since: t} : null;
}
// its update asked for on its own, with or without a copy
function askedUpdate(id) {
  const t = askedSince(id === 'updater' ? 'self' : 'now:' + id);
  return t !== null ? t : askedSince('nokeep:' + id);
}
// its getting ready counted from the tap, not from when the updater got to it
function fromTap(p) {
  if (p.step !== 'prepare') return p;
  const t = askedSince(p.part === 'updater' ? 'self' : 'now:' + p.part) || askedSince('now:all');
  return t && t < p.since ? {...p, since: t} : p;
}
// the bar of the step it's on, moving while there's no percent, and under it how far and its time
function bar(p) {
  const label = stepLabel(p);
  const detail = stepDetail(p);
  return h('div', {class: 'progress' + (didntRun(p) || p.warn ? ' warnbar' : '')},
    h('div', {class: 'track', role: 'progressbar', 'aria-label': label, 'aria-valuetext': [label, detail].filter(Boolean).join(', '),
      'aria-valuemin': 0, 'aria-valuemax': 100, 'aria-valuenow': p.pct === null ? undefined : p.pct},
    p.pct === null ? h('div', {class: 'moving'}) : h('div', {class: 'fill', style: 'width:' + p.pct + '%'})),
    (detail || p.since) && h('small', {class: 'dim'}, detail, detail && p.since ? ' · ' : null, p.since ? h('span', {'data-since': p.since}, sinceText(p.since)) : null),
  );
}
// a button while what it asked for is on its way
const waitButton = (key, label) => h('button', {class: 'control', 'data-key': key, disabled: true}, label);
// something it does without steps (a look for updates or for room, deleting): what, and its bar
const busyLine = (p) => h('div', {class: 'busy'}, h('b', null, stepLabel(p) + '…'), bar(p));
// a done step's tick
function tick() {
  const e = h('span', {'aria-hidden': 'true'});
  e.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12l5 5 9-10"/></svg>';
  return e;
}
// a run's steps, the done ones ticked, on the one it's on the bar
const stepList = (steps, at, prog, label, done) => h('ol', {class: 'steps'}, steps.map((step, i) =>
  h('li', {'data-step': step, class: i < at ? 'done' : i === at ? 'now' + (didntRun(prog) ? ' held' : '') : null},
    h('span', {class: 'stepDot'}, i < at ? tick() : i === at ? h('i') : String(i + 1)),
    h('span', null, h('b', null, i < at ? done(step) : label(step)), i === at && bar(prog)))));
// a part's run in its card, as in MowBite
function runCard(p, prog, ...more) {
  const steps = stepsOf(p.id, prog.step);
  const back = steps.includes('back');
  return h('div', {class: 'card run', 'data-update': p.id},
    h('h3', null, tr(back ? '{name} goes back' : '{name} is being updated', {name: nameOf(p)})),
    stepList(steps, steps.indexOf(prog.step), prog, (step) => stepLabel({...prog, step}), (step) => tr(STEP_DONE[step])),
    more);
}
// where a part is in what runs: its step now, asked and not on it yet, or in line behind another
function place(id) {
  const prog = progressNow();
  const mine = prog && prog.part === id ? prog : null;
  const parts = runParts();
  const queued = !mine && parts.includes(id) && parts.indexOf(id) > (prog ? parts.indexOf(prog.part) : 0);
  return {mine, queued, wait: !mine && !queued && waiting(id), parts};
}
// its run right now: its step, or asked and not on it yet (from the tap on), null while it isn't
function runOf(id) {
  const {mine, wait} = place(id);
  return mine ? fromTap(mine) : wait ? {part: id, step: wait.step, pct: null, since: wait.since} : null;
}
// in line behind another one of the run
function inLine(id) {
  const {queued, parts} = place(id);
  return queued && dim(tr('In line ({n} of {of})', {n: parts.indexOf(id) + 1, of: parts.length}));
}
// the one button of a card, only when there's something to do: what's new, a version built here to swap, or not known.
// none while it's in line for it (on it, its card shows the run)
function actButton(p) {
  if (p.kind === 'local' || p.kind === 'os' || place(p.id).queued || osParked(p)) return null;
  // (it can't update itself from outside its compose file)
  if (p.id === 'updater' && (S('updater_away') || S('updater_available') === 'unknown none')) return null;
  const a = avail(p.id);
  // (OpenMower left out for the firmware: again after openmower update-firmware. missing: its download again)
  const again = p.kind === 'openmower' && S('openmower_fw') ? 'Try again' : undefined;
  const label = p.kind === 'openmower' && S('openmower_missing') ? 'Try again'
    : {yes: 'Update', switch: 'Switch', local: 'Replace with the official version', unknown: 'Update', '': 'Update', failed: again}[a];
  if (!label) return null;
  return h('div', {class: 'act'},
    h('button', {class: 'control' + (a === 'yes' || a === 'switch' ? ' primary' : ''), 'data-key': 'now:' + p.id, disabled: busy(),
      onclick: () => ask(p.id === 'updater' ? 'self' : 'now=' + p.id)}, tr(label)));
}
// an update to another version line of OpenMower, before it's tapped
function lineChange() {
  const [from, to] = S('openmower_line').split(' ');
  if (!to) return null;
  return h('p', {class: 'warn'}, tr("This update goes to another version line of OpenMower ({from} → {to}). It can need newer firmware: if the motors stay off after it, the updater goes back by itself and says so.",
    {from: from === '-' ? tr('older') : from, to}));
}
const failedHere = (where) => failed && failedFor === where && h('p', {class: 'warn'}, failed);
// OpenMower without room for both versions: deleting the one that runs first, offered under its nospace, with what goes
// (openmower_nokeep "yes <MB> <parts> <tags back> <tags for good>"), or why not
const NOKEEP_NOT = {
  prev: "the version that runs can't be downloaded again from its registry (built here, or no answer)",
  env: "OpenMower's .env names another version than the one that runs",
  registry: "the size of the new version isn't known",
  holders: "it isn't known which images hold the version that runs",
};
const commas = (x) => (x && x !== '-' ? x.split(',') : []);
// (the updater counts in MiB)
const mib = (x) => (/^\d+$/.test(x || '') ? size(Number(x) * 1048576) : '?');
function nokeepOffer(p) {
  const [ok, a, b, c, d] = S(p.id + '_nokeep').split(' ');
  const name = (id) => nameOf(PARTS().find((x) => x.id === id) || {id});
  if (ok === 'no') {
    const why = NOKEEP_NOT[a] ? tr(NOKEEP_NOT[a])
      : a === 'room' ? tr("even then there isn't room enough (needs about {need}, {has} there)", {need: mib(b), has: mib(c)})
      : a === 'box' ? tr('the container "{name}" uses the version that runs and the updater can\'t build it again', {name: b || '?'})
      : a === 'base' ? tr('{name} is built on OpenMower and the version picked comes under another name', {name: name(b)})
      : a === 'github' ? tr("it isn't known what to build of {name} (GitHub doesn't answer)", {name: name(b)})
      : a || '?';
    return dim(tr("Deleting the old version first isn't possible here: {why}.", {why}));
  }
  if (ok !== 'yes') return null;
  const names = commas(b).map(name);
  return [
    h('p', {class: 'warn'}, tr("Both versions don't fit side by side. This way the version that runs is deleted first, then the new one downloaded ({size}). Until then the mower has no OpenMower and can't mow.",
      {size: mib(a)})),
    dim(tr("There's no way back on the mower itself: if the new one doesn't start, the updater downloads the old one again (that takes as long as the update and needs the internet).")),
    names.length > 0 && dim(tr("What's built on OpenMower ({names}) is deleted with it and built again afterwards. If building fails, the mower can only mow again once it's built.", {names: names.join(', ')})),
    commas(c).length > 0 && dim(tr('Deleted and downloaded or built again: {tags}.', {tags: commas(c).join(', ')})),
    commas(d).length > 0 && dim(tr('Deleted for good: {tags}.', {tags: commas(d).join(', ')})),
    h('div', {class: 'act'}, twoTaps('nokeep:' + p.id, tr('Delete the old version and update'), tr('Really delete it first?'), () => ask('nokeep=' + p.id))),
  ];
}
// OpenMower missing after its update without a copy: when it tries again, and both ways by hand (openmower_missing
// "<tries> <next> <new|back> <new version> <the one before by its digest> <its tag> <folder>")
function missing() {
  const [, next, way, target, prev, ref, dir] = S('openmower_missing').split(' ');
  if (!ref) return null;
  // (its .env names the tag of what it tries)
  const env = way === 'back' ? ref : target;
  const start = (tag) => (dir && dir !== '-' ? ' && cd ' + dir + (tag === env ? '' : " && sed -i 's/^VERSION=.*/VERSION=" + tag.split(':').pop() + "/' .env") + ' && docker compose up -d' : '');
  const by = (key, said, text) => [dim(tr(said)), h('pre', {class: 'log'}, text), h('div', {class: 'act'}, copyButton('copy:missing-' + key, text))];
  return [
    h('p', {class: 'error'}, tr("OpenMower isn't on the mower right now, the mower can't mow.")),
    dim(/^\d+$/.test(next || '') ? tr('Next try by itself: {when}.', {when: when(next)}) : tr('No more tries by itself: tap Try again.')),
    // (on the way back the new one can't be had or didn't run)
    ...(way === 'new' ? by('new', 'By hand in a terminal on the mower, the new version:', 'docker pull ' + target + start(target)) : []),
    ...by('back', way === 'new' ? 'or the version before:' : 'By hand in a terminal on the mower, the version before:', 'docker pull ' + prev + ' && docker tag ' + prev + ' ' + ref + start(ref)),
  ];
}

// MowBite OS in OpenMower's place, on OpenMower's card. os_switch: "yes <MB> keep|drop import|kept" offered, "no <why>
// [<MB needed> <MB there>]", "on <since>". switch_os: its step there ("os <step>") or back ("openmower <step> [map|old
// [lost]]", the way there given up: "os back rolled_back|error <why>"). os and os_at: how the last one ended. os_safety
// check_failed: on it, its lock for driving by itself closed
const osBusy = () => !!(S('switch_os') || S('os_ran'));
const osUndo = () => S('switch_os').startsWith('os back ');
// a part left alone next to MowBite OS: OpenMower, what was stopped or deleted with it
const osParked = (p) => osBusy() && (p.kind === 'openmower' || S('os_ran').split(' ').some((x) => x.startsWith(p.container + ':')) || !!S('gone_' + p.id));
// which way it goes while it's asked for or runs: 'os' there, 'openmower' back
const osTap = () => (askedSince('switch:os') !== null ? askedSince('switch:os') : askedSince('switch:openmower'));
function osWay() {
  if (askedSince('switch:os') !== null) return 'os';
  if (askedSince('switch:openmower') !== null) return 'openmower';
  const way = S('switch_os').split(' ')[0];
  if (way) return way;
  return running() && runParts().includes('os') ? (S('os_switch').startsWith('on ') ? 'openmower' : 'os') : null;
}
// each step on the way, while it's on it and once it's done
const OS_THERE = {
  prepare: ["Keeping OpenMower's data", "OpenMower's data kept"],
  pull: ['Downloading MowBite OS', 'MowBite OS downloaded'],
  stop: ['Stopping OpenMower', 'OpenMower stopped'],
  drop: ["Deleting OpenMower's version", "OpenMower's version deleted"],
  start: ['Starting MowBite OS', 'MowBite OS started'],
  wait: ['Checking that MowBite OS runs', 'MowBite OS checked'],
};
const OS_BACK = {
  export: ['Taking the map from MowBite OS', 'Map taken from MowBite OS'],
  stop: ['Stopping MowBite OS', 'MowBite OS stopped'],
  om: ['Downloading OpenMower again', 'OpenMower downloaded again'],
  data: ['Handing the map to OpenMower', 'Map handed to OpenMower'],
  start: ['Starting OpenMower', 'OpenMower started'],
};
// the way while it runs, is asked for or stopped halfway there (on again at the updater's start): its steps, the one
// it's on with the bar of what it does in it, and whether it went back to OpenMower on the way there
function osRun() {
  const [way, step, how] = S('switch_os').split(' ');
  const on = running() && runParts().includes('os');
  const tap = osTap();
  const go = osWay();
  if (!go || !(on || tap !== null || way === 'os')) return null;
  const drop = !!S('os_drop') || S('os_switch').split(' ')[2] === 'drop';
  const steps = go === 'os' ? (drop ? ['prepare', 'stop', 'drop', 'pull', 'start', 'wait'] : ['prepare', 'pull', 'stop', 'start', 'wait'])
    : ['export', 'stop', ...(S('os_drop') ? ['om'] : []), 'data', 'start'];
  const at = way ? step : steps[0];
  if (!steps.includes(at)) steps.push(at);
  const q = progressOf();
  const mine = on && q.part === 'os';
  const prog = {part: 'os', step: at, pstep: mine ? q.step : null, pct: mine ? q.pct : null,
    since: (mine && q.since) || tap, done: mine ? q.done : undefined, of: mine ? q.of : undefined};
  return {go, steps, at: steps.indexOf(at), prog, old: how === 'old', undo: osUndo()};
}
function osRunCard(run) {
  const {go, steps, at, prog, old} = run;
  if (run.undo) {
    const label = tr(prog.pstep === 'stop' ? OS_BACK.stop[0] : ['download', 'extract'].includes(prog.pstep) ? OS_BACK.om[0] : 'Bringing OpenMower back');
    // (switch_os "os back rolled_back|error <why>")
    const [, , kind, why, t] = S('switch_os').split(' ');
    const given = kind === 'rolled_back'
      ? tr("MowBite OS didn't run as it should: {why}. OpenMower comes back as it was.", {why: trWhy(OS_WHY, why)})
      : tr('The switch was given up: {why}. OpenMower comes back as it was.',
        {why: why === 'schedule' ? tr('the schedule starts the mower {when}', {when: when(t)}) : trWhy(OS_GIVEN_UP, why)});
    return h('div', {class: 'card run', 'data-update': 'os'},
      h('h3', null, tr('Back to OpenMower')),
      h('p', {class: 'warn'}, given),
      h('div', {class: 'busy'}, h('b', null, label + '…'), bar({...prog, label, warn: true})),
      failedHere('os'));
  }
  // (no map from MowBite OS: OpenMower keeps its own)
  const names = (s) => (go === 'os' ? OS_THERE : OS_BACK)[s] || [s, s];
  const doing = (s) => tr(old && s === 'data' ? "Keeping OpenMower's map from before" : names(s)[0]);
  const did = (s) => tr(old && s === 'export' ? 'No map from MowBite OS, OpenMower keeps its own' : old && s === 'data' ? "OpenMower's map from before kept" : names(s)[1]);
  return h('div', {class: 'card run', 'data-update': 'os'},
    h('h3', null, tr(go === 'os' ? 'Switching to MowBite OS' : 'Back to OpenMower')),
    stepList(steps, at, {...prog, label: doing(prog.step)}, doing, did),
    dim(tr(go === 'os' ? "If MowBite OS doesn't run as it should, OpenMower comes back as it was." : 'The mower can mow again once OpenMower runs.')),
    failedHere('os'));
}
// a reason's text from its map, else the reason as it came
const trWhy = (map, k) => (map[k] ? tr(map[k]) : k || '?');
// why it isn't offered (os_switch "no <why>")
const OS_NOT = {
  image: "the version of MowBite OS that's set can't be found",
  registry: "there's no answer from where MowBite OS is downloaded (does the mower have internet?)",
  data: "OpenMower's map and settings aren't in folders on the mower that MowBite OS could take them from",
  datum: 'mower_params.yaml has no position for the map (datum_lat and datum_long)',
  import: "this version of MowBite OS can't take over OpenMower's map",
  files: 'this version of MowBite OS has no setup for this mower',
  openmower: "OpenMower doesn't run right now",
  nokeep: "OpenMower's update without a copy isn't finished yet",
  pending: 'something else has to be finished first (an update, data put back or a calibration)',
  stack: "there's a MowBite OS on the mower already that the updater didn't set up, it leaves that alone",
  prev: "there's no room for both, and OpenMower's version couldn't be downloaded again for the way back",
};
// why MowBite OS was given up and OpenMower runs again (os "rolled_back <why>")
const OS_WHY = {
  start: "it didn't start",
  health: "it didn't get ready in time",
  halt: 'it stopped itself because of a fault',
  info: "it didn't answer as MowBite OS for this mower",
  state: "it didn't report the mower's state",
  emergency: 'the mower stayed in emergency stop',
  pull: "a part of it couldn't be downloaded",
  files: 'its setup for this mower is missing',
  import: "it can't take over OpenMower's map",
};
// os "error <why>": schedule and not_docked as a part's
const OS_ERRORS = {
  offer: "nothing done: it isn't possible right now",
  hold: "nothing done: MowBite's schedule couldn't be held",
  keep: "nothing done: OpenMower's data couldn't be kept first",
  pull: "nothing done: MowBite OS couldn't be downloaded. Does the mower have internet?",
  files: 'nothing done: this version of MowBite OS has no setup for this mower',
  import: "nothing done: this version of MowBite OS can't take over OpenMower's map",
  stop: "something couldn't be stopped, see the log",
  broker: "something else still answers on the mower's MQTT port, MowBite OS can't run next to it. OpenMower runs again as before.",
  registry: "nothing deleted: OpenMower's version can't be downloaded right now, it would be needed for the way back. OpenMower runs again as before.",
  busy: "MowBite OS wasn't idle in the dock, it stays. Tap again when the mower is ready in the dock.",
  back: "OpenMower didn't come back, the mower can't mow. Tap Continue the way back.",
  interrupted: 'stopped before anything changed (the mower or the updater restarted), OpenMower stays',
};
// why the way there was given up after OpenMower had stopped ("os back error <why>"): schedule with its time
const OS_GIVEN_UP = {
  hold: "MowBite's schedule couldn't be held",
  not_docked: "the mower wasn't ready in the dock",
  stop: "something couldn't be stopped",
  broker: "something else still answers on the mower's MQTT port",
  registry: "OpenMower's version can't be downloaded right now, it would be needed for the way back",
  keep: "OpenMower's data couldn't be kept first",
  pull: "MowBite OS couldn't be downloaded",
  files: OS_NOT.files,
  import: OS_NOT.import,
};
// how the last one ended, like a part's result
function osResult() {
  const [state, a, b, c] = S('os').split(' ');
  const ok = (text) => ({text, level: 'ok'});
  const warn = (text) => ({text, level: 'warn'});
  switch (state) {
    case 'switched':
      return ok(tr(b === 'kept' ? 'switched to MowBite OS, with its own data from before' : "switched to MowBite OS, it took over OpenMower's map and settings"));
    case 'rolled_back':
      return warn(tr("MowBite OS didn't run as it should: {why}. OpenMower runs again as before.", {why: trWhy(OS_WHY, a)}));
    case 'back':
      if (b !== 'map') return ok(tr('back on OpenMower, with its own map from before the switch'));
      return c === 'lost' ? warn(tr("back on OpenMower with the map from MowBite OS, some areas couldn't be taken over")) : ok(tr('back on OpenMower, with the map from MowBite OS'));
    case 'error':
      if (a === 'schedule') return ok(tr('not done: the schedule starts the mower {when}, OpenMower is left alone until then', {when: when(b)}));
      if (a === 'not_docked') return warn(tr("not done: the mower wasn't ready in the dock. Tap again when it's there."));
      return {text: OS_ERRORS[a] ? tr(OS_ERRORS[a]) : tr('failed ({why})', {why: a || '?'}), level: a === 'back' || a === 'stop' ? 'error' : 'warn'};
    default:
      return null;
  }
}
// for the top when it went wrong: OpenMower not back (red), MowBite OS that didn't run lately (yellow)
function osTrouble() {
  if (S('switch_os').startsWith('openmower ')) return {text: tr("OpenMower isn't back yet"), tone: 'bad'};
  const at = Number(S('os_at'));
  if (S('os').startsWith('rolled_back ') && at && now - at < DAYS3) return {text: tr("MowBite OS didn't run, OpenMower runs again"), tone: 'wait'};
  return null;
}
// its part of OpenMower's card: offered or why not (only once its image is set), on it and the way back, stopped
// halfway back, and how the last one ended
function osPart() {
  const [offer, a, b, c] = S('os_switch').split(' ');
  const way = S('switch_os').split(' ')[0];
  // (only once its image is set, or while OpenMower isn't back)
  if (!st.conf.os && !way && !S('os_ran')) return null;
  const [state, why] = S('os').split(' ');
  const at = /^\d+$/.test(S('os_at')) ? Number(S('os_at')) : null;
  // (on it: the line about it says when)
  const last = !(offer === 'on' && state === 'switched') && lastLine(osResult(), at, 'os');
  const go = (key, label, question, query) => h('div', {class: 'act'}, twoTaps(key, tr(label), tr(question), () => ask(query)));
  let body = null;
  if (way === 'openmower') {
    body = [!(state === 'error' && (why === 'back' || why === 'stop')) && h('p', {class: 'error'}, tr("The way back to OpenMower stopped halfway, OpenMower doesn't run yet.")),
      go('switch:openmower', 'Continue the way back', 'Really continue?', 'switch=openmower')];
  } else if (offer === 'on') {
    body = [dim(tr('MowBite OS runs the mower since {when}. OpenMower is stopped, its data stays as it was.', {when: when(a)})),
      dim(tr('On the way back OpenMower gets the map from MowBite OS and is started and checked again. Only with the mower ready in the dock.')),
      S('os_drop') && dim(tr("OpenMower's version is downloaded again, that needs the internet.")),
      S('os_safety') === 'check_failed' && h('p', {class: 'warn'},
        tr("A safety check in MowBite OS's setup failed, so it won't drive on its own. OpenMower doesn't know this check and will mow again without it.")),
      go('switch:openmower', 'Back to OpenMower', 'Really go back?', 'switch=openmower')];
  } else if (offer === 'yes') {
    body = [dim(tr("MowBite OS can take OpenMower's place on this mower. OpenMower's data is kept and OpenMower stopped, then MowBite OS is started and checked. If it doesn't run as it should, OpenMower comes back as it was.")),
      dim(tr(c === 'kept' ? "MowBite OS starts with its own map and settings from the last time it ran, not with OpenMower's current ones." : "MowBite OS takes over OpenMower's map and mower_params.yaml.")),
      b === 'drop' && h('p', {class: 'warn'}, tr("There isn't room for both: OpenMower's version is deleted first and downloaded again on the way back (that needs the internet).")),
      dim(Number(a) > 0 ? tr('Download: {size}. Only with the mower ready in the dock.', {size: mib(a)}) : tr('Only with the mower ready in the dock.')),
      go('switch:os', 'Switch to MowBite OS', 'Really switch?', 'switch=os')];
  } else if (offer === 'no') {
    const not = a === 'room' ? tr("there isn't room enough even with OpenMower's version deleted (needs about {need}, {has} there)", {need: mib(b), has: mib(c)})
      : trWhy(OS_NOT, a);
    body = dim(tr("Switching to MowBite OS isn't possible right now: {why}.", {why: not}));
  }
  return h('div', {class: 'os'}, h('b', null, 'MowBite OS'), last, body, failedHere('os'));
}

function partCard(p) {
  const id = p.id;
  const os = p.kind === 'openmower' && osRun();
  if (os) return osRunCard(os);
  const run = runOf(id);
  if (run) return runCard(p, run, failedHere(id));
  const fixed = p.kind === 'local' || p.kind === 'os';
  // (left alone next to MowBite OS: nothing to update or put back until OpenMower is back)
  const parked = osParked(p);
  const auto = autoOn(id);
  const stable = S(id + '_stable');
  const [state] = S(id).split(' ');
  const at = resultAt(p);

  let picker = null;
  if (p.kind === 'openmower') {
    const own = [st.conf.openmower, S('openmower_env')].filter((t) => t && t !== 'edge' && t !== 'latest');
    picker = h('select', {class: 'control', 'data-key': 'chan:' + id, 'aria-label': tr('Version'), value: st.conf.openmower,
      onchange: (e) => (pickedBy(e), setConf({openmower: e.target.value}).then((ok) => ok && ask('check')))},
    ['edge', 'latest', ...new Set(own)].map((t) => h('option', {value: t}, t === 'edge' ? tr('Edge (newest)') : t === 'latest' ? tr('Release') : t)));
  } else if ((p.kind === 'image' || p.kind === 'build') && stable) {
    picker = h('select', {class: 'control', 'data-key': 'chan:' + id, 'aria-label': tr('Version'), value: st.conf[id],
      onchange: (e) => (pickedBy(e), setConf({[id]: e.target.value}).then((ok) => ok && ask('check')))},
    h('option', {value: 'beta'}, tr('Beta')),
    (stable === 'yes' || st.conf[id] === 'stable') && h('option', {value: 'stable'}, tr('Stable')));
  }
  // the way back: out in the card a few days after an update, else folded. not after it went back already, a tap would go
  // one more version back
  const back = S(id + '_back') === 'yes' && (p.kind === 'image' || p.kind === 'openmower') && !parked &&
    h('div', {class: 'row'}, dim(tr('Something wrong since the last update?')),
      twoTaps('back:' + id, tr('Back to the version before'), tr('Really go back?'), () => ask('back=' + id)));
  const backOut = back && state === 'updated' && at !== null && now - at < DAYS3;
  const out = S(id + '_picked') === 'yes' &&
    h('div', {class: 'row'}, dim(tr('Not to be updated here any more?')),
      twoTaps('out:' + id, tr('Take out'), tr('Really take out?'), () => setPicked(picked().filter((c) => c !== p.container), id)));
  const notes = [
    p.kind === 'image' && st.conf[id] === 'stable' && !S(id + '_stable_older') &&
      dim(tr('Stable is the newest release without "beta". It can be older than the beta that runs now, going there leaves out what came since.')),
    id === 'planner' && stable && dim(tr('Stable is the default: the newest release without "beta". To get new planners first, pick Beta.')),
    p.kind === 'build' && id !== 'planner' && st.conf[id] === 'stable' &&
      dim(tr('Stable is the newest release without "beta", built from its main branch as long as there is none. It can be older than the beta that runs now, going there leaves out what came since.')),
    p.kind === 'openmower' && auto && st.conf.openmower === 'edge' &&
      dim(tr("Edge changes often, an update at night can bring a new fault. Only when there's room for the old and the new version at once.")),
  ].filter(Boolean);
  const inside = [!backOut && back, out].filter(Boolean);
  const label = out ? (back && !backOut ? 'The version before, taking out' : 'Taking out') : 'The version before';
  // its data kept before an update or before data was put back, newest first: back by hand
  const kept = (st.data || []).filter((k) => k.part === id).sort((a, b) => b.at - a.at).map((k) =>
    h('div', {class: 'row'},
      dim(tr(k.why === 'put' ? 'before putting data back, {when}: {what}' : 'before the update, {when}: {what}', {when: when(k.at), what: keptWhat(k.what)})),
      twoTaps('data:' + id + '-' + k.at, tr('Put back'), tr('Really put back?'), () => ask('data=' + id + '-' + k.at))));

  return h('div', {class: 'card'},
    head(p),
    facts(p, picker),
    notes,
    inLine(id),
    failedHere(id),
    resultLine(p),
    p.kind === 'openmower' && st.conf.openmower !== 'edge' && PARTS().some((x) => x.id === 'planner') &&
      h('p', {class: 'warn'}, tr("With this version the MowBite Planner doesn't work: it needs two changes that are only in edge so far (OM_PLANNER=external and keeping the planner's settings per area).")),
    p.kind === 'openmower' && ['yes', 'switch'].includes(avail(id)) && lineChange(),
    p.kind === 'openmower' && missing(),
    p.kind === 'openmower' && state === 'nospace' && nokeepOffer(p),
    p.kind === 'image' && st.conf[id] === 'stable' && S(id + '_stable_older') && state !== 'stable_older' &&
      dim(tr('stable {v} is older than what runs, it stays until a newer stable is out', {v: S(id + '_stable_older')})),
    p.kind === 'image' && avail(id) === 'local' && dim(tr("This version was built on its own, it isn't the official one.")),
    p.kind === 'local' && dim(tr('Built from a local copy, it is left as it is.')),
    p.gate === 'none' && dim(tr('Updates also with the mower out of the dock.')),
    parked && p.kind !== 'openmower' && S(id) !== 'error os' && dim(tr('Stopped with OpenMower, it starts again once OpenMower is back.')),
    actButton(p),
    backOut && back,
    !fixed && h('label', {class: 'check'},
      h('input', {type: 'checkbox', 'data-key': 'auto:' + id, checked: auto, onchange: (e) => setConf({[id + '_auto']: e.target.checked ? 1 : 0})}),
      tr('Automatically at night ({when})', {when: tickText()})),
    inside.length > 0 && more(id, label, inside),
    kept.length > 0 && !parked && more('data:' + id, 'Data kept',
      dim(tr("Before each update the updater keeps a copy of this part's data on the mower, the newest two. Putting one back stops it, keeps what it has now first and starts it again, only with the mower ready in the dock.")),
      kept),
    p.kind === 'openmower' && osPart(),
  );
}
// the pieces of a copy of data in words
const keptWhat = (what) => what.split(' ').map((w) => (w === '.' ? tr('all of its data') : w === 'map.json' ? tr('the map (map.json)') : w)).join(', ');

// the apps picked on this page (besides the known and labelled ones): changed, then looked at again once saved
const picked = () => String(st.conf.picked || 'none').split(',').filter((c) => c && c !== 'none');
function setPicked(list, where) {
  setConf({picked: list.length ? list.join(',') : 'none'}, where).then((ok) => ok && ask('check'));
}
let choice = '';
function addFold() {
  // (one picked already is on its way into the list)
  const cand = S('candidates').split(' ').filter((c) => c && !picked().includes(c));
  if (!cand.length) return null;
  if (!cand.includes(choice)) choice = '';
  return fold('add', false, false, tr('Add another app'), tr('Update other apps on the mower too'),
    dim(tr('Any other app of your stacks, the updater then looks after it like the others: only with the mower ready in the dock, and back to the version before when the new one doesn\'t run for half a minute.')),
    h('div', {class: 'row'},
      h('select', {class: 'control', 'data-key': 'pick', 'aria-label': tr('Pick an app'), value: choice, onchange: (e) => {
        choice = e.target.value;
        e.target.closest('.row').querySelector('button').disabled = busy() || !choice || saving('add');
        pickedBy(e);
      }},
      h('option', {value: ''}, tr('Pick an app…')),
      cand.map((c) => h('option', {value: c}, c))),
      h('button', {class: 'control', 'data-key': 'add', disabled: busy() || !choice || saving('add'), onclick: () => {
        const add = choice;
        choice = '';
        setPicked([...picked(), add], 'add');
      }}, tr('Add'))),
    failedHere('add'));
}

// itself: the commit it runs, whether there's a newer one and updating it, the bar while it downloads and restarts
function selfCard() {
  if (!S('updater_running')) return null;
  const p = ALL().find((x) => x.id === 'updater');
  const since = restarting();
  if (since) return runCard(p, {part: 'updater', step: 'restart', pct: null, since}, dim(tr('Restarting the updater, the page comes back by itself')));
  const run = runOf('updater');
  if (run) return runCard(p, run, failedHere('updater'));
  return h('div', {class: 'card'},
    head(p),
    facts(p),
    // (with all the others: first, before them)
    askedFor === 'now' && (running() || askedSince('now:all') !== null) && avail('updater') === 'yes' &&
      dim(tr('Comes first, the page then loads again by itself and the apps follow.')),
    failedHere('updater'),
    resultLine(p),
    avail('updater') === 'local' && dim(tr("This version was built on its own, it isn't the official one.")),
    PARTS().some((x) => autoOn(x.id)) && dim(tr('It updates itself too, at night before the automatic updates.')),
    S('mower') !== '1' && dim(tr('Updates also with the mower out of the dock.')),
    actButton(p),
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
  const line = (dir) => {
    const text = '      - ' + dir + ':' + dir;
    return [h('pre', {class: 'log'}, text), h('div', {class: 'act'}, copyButton('copy:' + dir, text))];
  };
  return h('div', {class: 'card'},
    h('span', {class: 'name'}, tr('Out of reach for the updater')),
    self === '-' && dim(tr('The updater runs without a compose file: it forgets its settings and can\'t update itself. Start it from a stack, e.g. in Dockge or Portainer.')),
    self && self !== '-' && [dim(tr('The updater doesn\'t see its own folder {dir}: it forgets its settings and can\'t update itself. Add this line to its "volumes:":', {dir: self})), line(self)],
    far.map((f) => f.dir === '-'
      ? dim(tr('"{name}" runs without a compose file, the updater can\'t update it.', {name: f.name}))
      : [dim(tr('"{name}" is in {dir}. The updater only sees {reach}. Move it there, or add this line to the updater\'s "volumes:":', {name: f.name, dir: f.dir, reach})), line(f.dir)]),
  );
}

// the mower's offset from utc in minutes (clock: +0100), null when it doesn't say
function mowerOffset() {
  const m = /^([+-])(\d\d)(\d\d)$/.exec(S('clock'));
  return m ? (m[1] === '-' ? -1 : 1) * (Number(m[2]) * 60 + Number(m[3])) : null;
}
// the mower's clock against this device's, when they differ
function clockLine() {
  const there = mowerOffset();
  const [hh, mm] = String(st.conf.at).split(':').map(Number);
  if (there === null || Number.isNaN(hh) || Number.isNaN(mm)) return null;
  const here = -new Date().getTimezoneOffset();
  if (there === here) return null;
  const t = ((((hh * 60 + mm - there + here) % 1440) + 1440) % 1440);
  const hm = (x) => String(Math.floor(x / 60)).padStart(2, '0') + ':' + String(x % 60).padStart(2, '0');
  const off = Math.abs(there);
  const tz = 'UTC' + (there < 0 ? '-' : '+') + Math.floor(off / 60) + (off % 60 ? ':' + String(off % 60).padStart(2, '0') : '');
  return dim(tr('{at} on the mower ({tz}) is {here} here.', {at: st.conf.at, tz, here: hm(t)}));
}
// the time typed in: saved once it rests a moment or the field is left, not after each digit
let atTimer = 0;
function saveAt(v) {
  clearTimeout(atTimer);
  atTimer = 0;
  if (/^\d\d:\d\d$/.test(v || '') && v !== st.conf.at) setConf({at: v}, 'schedule');
}
function scheduleCard() {
  const days = nightDays();
  const toggle = (d) => {
    const next = days.includes(d) ? days.filter((x) => x !== d) : [...days, d].sort();
    // the last day taken away would be every night: that day stays (off is each part's own tick)
    if (!next.length) return render();
    setConf({days: next.length < 7 ? next.join(',') : 'daily'});
  };
  return h('div', {class: 'card'},
    h('span', {class: 'name'}, tr('When it updates by itself')),
    h('div', {class: 'row'},
      h('input', {class: 'control', type: 'time', 'data-key': 'at', 'aria-label': tr('At'), value: st.conf.at,
        onchange: (e) => {
          const v = e.target.value;
          clearTimeout(atTimer);
          atTimer = setTimeout(() => saveAt(v), 800);
        },
        onblur: (e) => saveAt(e.target.value)}),
      h('label', {class: 'check'},
        h('input', {type: 'checkbox', 'data-key': 'daily', checked: st.conf.days === 'daily', onchange: (e) => setConf({days: e.target.checked ? 'daily' : '7'})}),
        tr('every night'))),
    st.conf.days !== 'daily' && h('div', {class: 'days', role: 'group', 'aria-label': tr('Days')},
      DAY_NAMES.map((d, i) =>
        h('button', {class: 'control' + (days.includes(i + 1) ? ' primary' : ''), 'data-key': 'day:' + (i + 1), 'aria-pressed': String(days.includes(i + 1)),
          onclick: () => toggle(i + 1)}, tr(d)))),
    dim(tr("If the mower isn't ready in the dock then, it tries again every 10 minutes for 3 hours. The time is the mower's.")),
    clockLine(),
    failedHere('schedule'),
  );
}

// the top: what there is to do or what's going on, the mower, when it updates by itself, and the buttons for all
let said = null;
let saying = {text: '', bad: false};
function overview() {
  const news = ALL().filter((p) => ['yes', 'switch'].includes(avail(p.id)) && !osParked(p));
  const switching = osTap() !== null;
  const osBad = osTrouble();
  const checked = /^\d+$/.test(S('checked')) ? Number(S('checked')) : null;
  const look = looking();
  const room = askedSince('room') !== null ? 'room' : askedSince('free') !== null ? 'free' : null;
  const all = running() || askedRan ? null : askedSince('now:all');
  // a part asked for on its own and not on a run's bar yet: its card has the bar, the top says which
  let one = null;
  for (const p of ALL()) {
    if (askedSince('back:' + p.id) !== null) one = one || {p, back: true};
    else if (askedUpdate(p.id) !== null) one = one || {p};
  }
  // the parts that can't tell, as there was no answer from where they come from
  const remote = ALL().filter((p) => ['image', 'openmower', 'build'].includes(p.kind));
  const offline = remote.some((p) => p.kind !== 'build' && ['unknown', ''].includes(avail(p.id))) &&
    !remote.some((p) => ['yes', 'no', 'switch'].includes(avail(p.id)));
  const trouble = troubled();
  const lines = [];
  let text;
  let tone = '';
  let check = false;
  if (restarting()) {
    text = tr('The updater restarts on its new version…');
    tone = 'run';
  } else if (lost()) {
    text = tr('No connection to the updater');
    tone = 'wait';
    lines.push(dim(tr('Shown is how things were {t}.', {t: when(lastOk)})));
  } else if (running() || one || all !== null || room || switching) {
    tone = 'run';
    if (running()) text = runText();
    else if (switching) text = tr(osWay() === 'os' ? 'Switching to MowBite OS…' : 'Going back to OpenMower…');
    else if (one) text = one.back ? tr('{name} goes back to the version before…', {name: nameOf(one.p)}) : tr('Updating {name}…', {name: nameOf(one.p)});
    else if (room) text = stepLabel({step: room}) + '…';
    else text = tr('Updating right now…');
    if (all !== null) lines.push(bar({part: '', step: 'prepare', pct: null, since: all}));
    if (!room) lines.push(dim(tr('While that runs, the other buttons wait.')));
  } else if (st.requested && !(asked && askedFor === 'check')) {
    // (in line: it finishes what it does first)
    text = tr('Asked…');
    tone = 'run';
  } else if (look !== null) {
    text = tr('Looking for updates…');
    tone = 'run';
    lines.push(bar({part: '', step: 'look', pct: null, since: look}));
  } else if (osBad) {
    text = osBad.text;
    tone = osBad.tone;
    lines.push(dim(tr("More on OpenMower's card below.")));
  } else if (trouble) {
    const name = nameOf(trouble.p);
    text = trouble.tone === 'bad' ? tr('Something went wrong with the last update of {name}', {name}) : tr("The last update of {name} didn't start", {name});
    tone = trouble.tone;
    lines.push(dim(trouble.tone === 'bad' ? tr('More on its card below.') : tr('It runs the version before again. More on its card below.')));
  } else if (news.length) {
    text = news.length === 1 ? tr('1 update available') : tr('{n} updates available', {n: news.length});
    tone = 'new';
    lines.push(dim([news.map(nameOf).join(', ') + '.', checked !== null && tr('Last checked {t}.', {t: when(checked)})].filter(Boolean).join(' ')));
  } else if (offline && checked !== null) {
    text = tr('Not known whether there are updates');
    tone = 'wait';
    lines.push(h('p', {class: 'warn'}, tr('No answer from GitHub and the registries. Does the mower have internet?')), dim(tr('Last checked {t}.', {t: when(checked)})));
  } else if (checked === null) {
    text = tr('Not looked for updates yet');
    tone = 'idle';
    check = true;
  } else {
    text = tr('Everything up to date');
    lines.push(dim(tr('Last checked {t}. It looks again every 6 hours by itself.', {t: when(checked)})));
  }
  // (what's new also when the top says something else, but not while something runs)
  if (news.length && tone !== 'new' && tone !== 'run') lines.push(dim(tr('Updates available: {names}.', {names: news.map(nameOf).join(', ')})));
  saying = {text, bad: tone === 'bad'};
  const on = PARTS().filter((p) => autoOn(p.id));
  return h('div', {class: 'card overview'},
    h('div', {class: 'name lead' + (tone ? ' ' + tone : '')}, text),
    lines,
    lastRun(),
    failedHere('overview'),
    failed && failedFor !== 'overview' && h('p', {class: 'warn'}, failed),
    mowerLine(),
    dim(on.length ? tr('Automatically: {when} ({names})', {when: nightText(), names: on.map(nameOf).join(', ')}) : tr('Automatically: off')),
    h('div', {class: 'act'},
      news.length > 0 && tone !== 'run' &&
        h('button', {class: 'control primary', 'data-key': 'all', disabled: busy(), onclick: () => ask('now')}, tr('Update all ({n})', {n: news.length})),
      h('button', {class: 'control' + (check ? ' primary' : ''), 'data-key': 'check', disabled: busy() || look !== null, onclick: () => ask('check')},
        tr(look !== null ? 'Checking…' : 'Check for updates'))),
  );
}

const ROOM_NOTE = {
  rollback: 'kept to go back to',
  planner: 'kept to go back to',
  dangling: 'left over, nothing uses it',
  unused: 'nothing uses it right now',
};
// an image to make room with, by the part it's of and what it was: "MowBite, the version before the update on 27.10.2026"
// kept to go back to: deleted one at a time, never with the rest
const WAY_BACK = ['rollback', 'planner'];
function roomName(refs) {
  if (refs === '-') return tr('an old version without a name');
  const ref = refs.split(',')[0];
  const at = ref.lastIndexOf(':');
  const [repo, tag] = at > ref.lastIndexOf('/') ? [ref.slice(0, at), ref.slice(at + 1)] : [ref, ''];
  const base = repo.split('/').pop();
  const known = {
    mowbite: 'MowBite', open_mower_ros: 'OpenMower', 'mowbite-updater': 'MowBite Updater', 'openmower-app': 'OpenMower App (xtech)', openmowerapp: 'OpenMowerApp',
  };
  const name = known[base] || (base.includes('planner') ? tr('MowBite Planner') : base);
  const rb = /^rb-(?:[a-z][a-z0-9_]*-)?(\d+)-/.exec(tag);
  if (rb) return tr('{name}, the version before the update on {d}', {name, d: new Date(Number(rb[1]) * 1000).toLocaleDateString(LOCALE)});
  if (tag === 'previous') return tr('{name}, the version before its last update', {name});
  // (its tag under the mouse)
  if (tag.startsWith('before-') || tag.startsWith('prev-')) return tr('{name}, an older version', {name});
  return tag ? name + ' (' + tag + ')' : name;
}
function roomFold() {
  const items = (st.room && st.room.items) || [];
  const cache = (st.room && st.room.cache) || 0;
  const free = freeMb();
  const total = items.reduce((n, i) => n + i.bytes, 0);
  // all of it but the ways back: those only one at a time
  const loose = items.filter((i) => !WAY_BACK.includes(i.kind));
  const builds = PARTS().filter((p) => p.kind === 'build');
  const planner = builds.length === 1 && builds[0].id === 'planner';
  const look = askedSince('room');
  const del = askedSince('free');
  // what's being deleted, where it was tapped: the image, the leftovers or all of them (asked elsewhere: not said which)
  const what = del !== null && askedFor.startsWith('free=') ? askedFor.slice('free='.length) : del !== null ? '' : null;
  const deleting = (w) => what === w && busyLine({part: '', step: 'free', pct: null, since: del});
  const delButton = (w, key, label) => (what === w ? waitButton(key, label)
    : twoTaps(key, label, tr('Really delete?'), () => ask('free=' + w)));
  const sub = [free !== null && tr('{gb} GB free', {gb: fmt(free / 1024, 1)}), total + cache > 0 && tr('{size} can be freed', {size: size(total + cache)})]
    .filter(Boolean)
    .join(', ');
  // (by itself when the mower runs out of room)
  const short = (free !== null && free < 1024) || ALL().some((p) => S(p.id).startsWith('nospace'));
  return fold('room', look !== null || del !== null, short, tr('Make room'), sub,
    dim(tr('Old versions and leftovers from building that nothing needs right now. After each update it clears away leftovers without a name, the unused leftovers from building and older versions beyond the ones kept by itself, the rest only when you tap it here. Versions kept to go back to only one at a time.')),
    items.map((i) => h('div', {class: 'item'},
      h('span', {class: 'itemName', title: i.refs === '-' ? null : i.refs.split(',').join(', ')}, roomName(i.refs)),
      dim(tr(ROOM_NOTE[i.kind] || ROOM_NOTE.unused)),
      h('div', {class: 'row'}, dim(size(i.bytes)), delButton('img:' + i.id, 'img:' + i.id, tr('Delete'))),
      deleting('img:' + i.id))),
    cache > 0 && h('div', {class: 'item'},
      h('span', {class: 'itemName'}, tr(planner ? 'Leftovers from building (the planner)' : 'Leftovers from building')),
      dim(tr(planner ? "The planner's next build then takes longer and needs the internet." : 'The next build then takes longer and needs the internet.')),
      h('div', {class: 'row'}, dim(size(cache)), delButton('cache', 'cache', tr('Clear'))),
      deleting('cache')),
    !items.length && !cache && dim(tr('Nothing to delete right now.')),
    look !== null && busyLine({part: '', step: 'room', pct: null, since: look}),
    deleting('all'),
    deleting(''),
    failedHere('room'),
    h('div', {class: 'row'},
      h('button', {class: 'control', 'data-key': 'room', disabled: busy(), onclick: () => ask('room')}, tr('Look again')),
      loose.length > 1 ? delButton('all', 'free-all', tr('Delete all but the ways back ({size})', {size: size(loose.reduce((n, i) => n + i.bytes, 0))})) : h('span')),
  );
}

// the stacks' containers, like a small dockge: their state, the last lines of a log (asked for, the updater takes the
// passwords out) and a restart (by the updater, with its rules)
let shownLog = null;
let logWait = null;
async function lastLog() {
  const [head, ...rest] = (await (await fetch(API + '?logs', {cache: 'no-store', signal: AbortSignal.timeout(8000)})).text()).split('\n');
  return {head, text: rest.join('\n').trim()};
}
// taken once another one than before is there (by the mower's clock in its head, this one's may differ), given up after
// a minute
async function getLog(name) {
  // (asked already, a second tap waits for that one)
  if (shownLog && shownLog.name === name && shownLog.text === null) return;
  shownLog = {name, text: null};
  clearInterval(logWait);
  render();
  const before = await lastLog().then((l) => l.head, () => '');
  if (!shownLog || shownLog.name !== name) return;
  ask('logs=' + name);
  const wait = (logWait = setInterval(async () => {
    try {
      const l = await lastLog();
      const m = /^#(\S+) \d+$/.exec(l.head);
      if (!m || m[1] !== name || l.head === before) return;
      clearInterval(wait);
      if (shownLog && shownLog.name === name) shownLog = {name, text: l.text};
      render();
    } catch {}
  }, 1500));
  setTimeout(() => {
    clearInterval(wait);
    if (shownLog && shownLog.name === name && shownLog.text === null) {
      shownLog = null;
      render();
    }
  }, 60000);
}
function restartLine(name) {
  const [who, what, t, why] = S('restarted').split(' ');
  if (who !== name) return null;
  if (what === 'done') return dim(tr('Started again, {t}.', {t: when(t)}));
  if (what === 'refused')
    return h('p', {class: 'warn'}, tr({
      not_docked: "Not started again: the mower isn't idle in the dock.",
      stopped: "Not started: it was stopped, it's only started the updater's own way.",
      os_host: 'Not started again: MowBite OS runs on the mower, OpenMower never runs next to it.',
    }[why] || 'Not started again: OpenMower drives the mower.'));
  if (what === 'error') return h('p', {class: 'warn'}, tr(why === 'not_running' ? 'Started again, but it does not answer.' : "Couldn't be started again."));
  return null;
}
function containerFold() {
  const items = st.containers || [];
  const looked = askedSince('containers');
  const up = items.filter((c) => c.state === 'running').length;
  const since = (c) => {
    const t = Date.parse(c.started);
    return Number.isFinite(t) ? when(Math.round(t / 1000)) : '?';
  };
  return fold('containers', looked !== null, false, tr('Containers'), items.length ? tr('{n} running', {n: up}) : null,
    dim(tr("The stacks' containers, like in Dockge: the last lines of their log and a restart. Passwords, tokens and access data stay hidden in the log.")),
    dim(tr("A restart only while OpenMower doesn't drive the mower, OpenMower itself only idle in the dock.")),
    items.map((c) => {
      const restarting = askedSince('restart:' + c.name) !== null;
      const logging = askedSince('logs:' + c.name) !== null || (shownLog && shownLog.name === c.name && shownLog.text === null);
      const open = shownLog && shownLog.name === c.name;
      return h('div', {class: 'item'},
        h('span', {class: 'itemName', title: c.image}, c.name),
        dim([c.stack, c.state === 'running' ? tr('runs since {t}', {t: since(c)}) : tr(c.state === 'restarting' ? 'restarting' : 'stopped'),
          c.restarts > 0 && tr('{n} restarts by itself', {n: c.restarts})].filter(Boolean).join(' · ')),
        restartLine(c.name),
        h('div', {class: 'row'},
          // (its own log is the one further down)
          !c.self && h('button', {class: 'control', 'data-key': 'log:' + c.name, disabled: busy() || logging, onclick: () => {
            if (open && shownLog.text !== null) {
              shownLog = null;
              render();
            } else getLog(c.name);
          }}, logging ? tr('Getting the log…') : open && shownLog.text !== null ? tr('Hide the log') : tr('Show the log')),
          c.self
            ? dim(tr('restarts itself with its updates'))
            : restarting
              ? waitButton('restart:' + c.name, tr('Restarting…'))
              : c.state === 'running'
                ? twoTaps('restart:' + c.name, tr('Restart'), tr('Really restart?'), () => ask('restart=' + c.name))
                : h('span')),
        open && shownLog.text !== null && h('div', {class: 'act'}, copyButton('copy:' + c.name, shownLog.text)),
        open && shownLog.text !== null && h('pre', {class: 'log boxlog'}, shownLog.text || '–'),
        open && shownLog.text !== null && dim(tr('Newest at the bottom')));
    }),
    looked !== null && dim(tr('Looking at the containers…')),
    failedHere('containers'),
    h('div', {class: 'row'},
      h('button', {class: 'control', 'data-key': 'containers', disabled: busy(), onclick: () => ask('containers')}, tr(items.length ? 'Look again' : 'Look at the containers')),
      h('span')),
  );
}

function logFold() {
  const log = [...(st.log || [])].reverse().join('\n');
  if (!log) return null;
  return fold('log', false, false, tr('Log'), tr('Newest at the top'),
    h('div', {class: 'act'}, copyButton('copy', log)),
    h('pre', {class: 'log runlog'}, log));
}

// own parts first (OpenMower, MowBite, the planner, itself), then the others in the updater's order
const RANK = {openmower: 0, mowbite: 1, planner: 2};
const rank = (p) => (p.id in RANK ? RANK[p.id] : 3);

function render() {
  const app = document.getElementById('app');
  // not while something is typed or picked, or selected to copy: again in a moment
  clearTimeout(held);
  if (typing() || selecting()) {
    dirty = true;
    held = setTimeout(render, 1000);
    return;
  }
  dirty = false;
  shownKey = stateKey();
  wasRestarting = !!restarting();
  if (!st) {
    app.replaceChildren(...(lost()
      ? [dim(tr('The updater does not answer.')), dim(tr('It may be restarting right now. If that lasts longer than 2 minutes: look in Dockge, in the stack "mowbite", whether "mowbite-updater" runs.'))]
      : [dim(tr('Loading…'))]));
    return;
  }
  // the control in use again after, and where the log was scrolled to
  const active = document.activeElement;
  const key = active && app.contains(active) ? active.getAttribute('data-key') : null;
  const pre = app.querySelector('pre.runlog');
  const scroll = pre ? pre.scrollTop : 0;
  // a container's log: at its end (the newest) unless scrolled up in it
  const box = app.querySelector('pre.boxlog');
  const boxAt = box && box.scrollTop + box.clientHeight < box.scrollHeight - 4 ? box.scrollTop : -1;
  const parts = PARTS().map((p, i) => ({p, i})).sort((a, b) => rank(a.p) - rank(b.p) || a.i - b.i).map((x) => x.p);
  const others = parts.filter((p) => rank(p) === 3);
  // (what isn't there this time, false or null, isn't shown)
  app.replaceChildren(...[
    locked && h('p', {class: 'warn'}, tr('This page is shown inside another one, open it on its own to change anything:'), ' ',
      h('a', {href: location.origin + '/', target: '_blank', rel: 'noreferrer'}, location.origin)),
    overview(),
    awayCard(),
    ...parts.filter((p) => rank(p) < 3).map(partCard),
    selfCard(),
    others.length > 0 && h('h2', {class: 'groupHead'}, tr('Other apps')),
    ...others.map(partCard),
    PARTS().some((p) => autoOn(p.id)) && scheduleCard(),
    h('p', {class: 'dim foot'}, tr("If a new version doesn't start, it goes back to the one before. Afterwards it clears away old versions.")),
    roomFold(),
    containerFold(),
    addFold(),
    logFold(),
  ].filter(Boolean));
  const log = app.querySelector('pre.runlog');
  if (log) log.scrollTop = scroll;
  const boxLog = app.querySelector('pre.boxlog');
  if (boxLog) boxLog.scrollTop = boxAt < 0 ? boxLog.scrollHeight : boxAt;
  const again = key && app.querySelector('[data-key="' + CSS.escape(key) + '"]');
  if (again) again.focus({preventScroll: true});
  say();
}
// for screen readers: what the top says, once when it changes (not on load), a failure at once
function say() {
  if (said === null || said === saying.text) {
    said = saying.text;
    return;
  }
  said = saying.text;
  const e = document.getElementById(saying.bad ? 'alert' : 'say');
  if (e) e.textContent = saying.text;
}

// embedded: its height to MowBite, which gives the frame that height (no scrolling box in a box). not while it loads,
// MowBite keeps the height it has until then
if (embedded && window.ResizeObserver) {
  new ResizeObserver(() => {
    if (!st && !lost()) return;
    window.parent.postMessage({mowbiteUpdater: 'height', height: Math.ceil(document.body.getBoundingClientRect().height)}, '*');
  }).observe(document.body);
}

render();
loop();
