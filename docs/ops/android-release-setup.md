# Android Release Setup — Codemagic + Firebase App Distribution

Checkliste für den Owner, damit der Codemagic-Workflow `android-appdist`
ein Release-APK baut und an die Tester verteilt. Der Workflow steht in
`codemagic.yaml`, die Signatur-Logik in `android/app/build.gradle.kts`.

Alle Platzhalter im YAML sind mit `# OWNER:` markiert. Diese Werte hier
eintragen bzw. bestätigen.

## Was der Owner ausfüllen muss

| Wert | Wo | Aktuell im Repo |
|---|---|---|
| Keystore-Referenzname | `codemagic.yaml` → `android_signing` | `kubb_upload_keystore` (Platzhalter) |
| Firebase App-ID | `codemagic.yaml` → `firebase.android.app_id` | `1:106001380567:android:72f4f1f0989d54b996ac92` (bereits gesetzt) |
| Tester-Gruppe | `codemagic.yaml` → `firebase.android.groups` | `testers` (Platzhalter) |
| Service-Account-Secret | Codemagic Env-Var `FIREBASE_SERVICE_ACCOUNT` | noch anzulegen |
| `SUPABASE_URL` / `SUPABASE_ANON_KEY` | Codemagic Env-Gruppe `supabase` | schon vorhanden (bestätigen) |

## Schritte

### a) Keystore erzeugen

Einmalig lokal einen Upload-Keystore erzeugen. Das Passwort sicher ablegen
(z.B. Passwort-Manager) — ohne diesen Keystore kann später kein Update mehr
signiert werden.

```bash
keytool -genkey -v -keystore kubb-upload.jks \
  -keyalg RSA -keysize 2048 -validity 9125 -alias kubb
```

Der Keystore darf **nie** ins Repo. `android/key.properties`, `*.jks` und
`*.keystore` sind in `.gitignore` gesperrt.

### b) Keystore in Codemagic hochladen

Codemagic UI → **Code signing identities → Android keystores** → `kubb-upload.jks`
hochladen. Alias und beide Passwörter eintragen. Einen **Referenznamen** vergeben
und denselben Namen in `codemagic.yaml` unter `android_signing` eintragen
(Platzhalter aktuell: `kubb_upload_keystore`).

Codemagic stellt daraus beim Build automatisch die Variablen `CM_KEYSTORE_PATH`,
`CM_KEY_ALIAS`, `CM_KEYSTORE_PASSWORD` und `CM_KEY_PASSWORD` bereit — genau die,
die `android/app/build.gradle.kts` liest.

### c) Firebase-Credential für App Distribution beziehen

In der **Google Cloud Console** (Projekt `kubbclubapp`) ein Service-Account
anlegen bzw. auswählen und ihm die Rolle **Firebase App Distribution Admin**
geben. Einen JSON-Key erzeugen und herunterladen.

Den kompletten JSON-Inhalt in Codemagic als **gesicherte** Env-Variable
`FIREBASE_SERVICE_ACCOUNT` hinterlegen (Team- oder App-Ebene, "Secure"
aktiviert). Die JSON-Datei selbst nie ins Repo legen — `**/service-account*.json`
und `**/*firebase-adminsdk*.json` sind in `.gitignore` gesperrt.

### d) Tester-Gruppe anlegen

**Firebase Console → App Distribution → Testers & Groups** → Gruppe erstellen
und die Tester-Emails hinzufügen. Den Gruppen-Alias (nicht den Anzeigenamen)
in `codemagic.yaml` unter `firebase.android.groups` eintragen (Platzhalter
aktuell: `testers`).

Die Firebase App-ID `1:106001380567:android:72f4f1f0989d54b996ac92` ist bereits
im YAML gesetzt (aus `android/app/google-services.json`, Paket `ch.kubbclub.app`).

### e) Supabase-Env bestätigen

In der Codemagic-Env-Gruppe `supabase` müssen `SUPABASE_URL` und
`SUPABASE_ANON_KEY` auf die **Prod**-Werte zeigen (nicht auf die lokale
Emulator-URL). Der Build injiziert sie via `--dart-define`; `lib/main.dart`
wirft sonst beim Start einen `StateError`.

### f) Build starten und Verteilung prüfen

Codemagic UI → Workflow **Android · App Distribution** → **Start new build**.
Nach dem Lauf: in der Firebase Console prüfen, ob der Build in App Distribution
erscheint, und ob die Tester eine Einladung erhalten haben. Neue Tester müssen
die Einladung einmal annehmen, bevor sie Builds installieren können.

## Hinweise

- Der Trigger ist bewusst **manuell** gehalten, gleich wie beim iOS-Workflow.
  Ein Auto-Build auf `release/*`-Tags ist im YAML als auskommentierter
  `triggering`-Block vorbereitet.
- Der Workflow läuft auf einer Linux-Instanz — für Android wird kein Mac
  gebraucht.
- Als versionCode dient `$PROJECT_BUILD_NUMBER` (projektweiter Codemagic-Index).
  Damit ist jeder Upload eindeutig und App Distribution weist keinen doppelten
  versionCode zurück.
