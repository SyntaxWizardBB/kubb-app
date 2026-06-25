# ADR-0042: OAuth-an-Keypair-Konto serverseitig reconcilen

- **Status**: Proposed
- **Date**: 2026-06-25
- **Depends on**: ADR-0010
- **Amends**: ADR-0010 (§Account upgrade path, §Multi-credential users)

## Context

Ein zurückkehrender Gast/Keypair-Nutzer kann kein OAuth-Konto an sein bestehendes Profil hängen. Der Versuch schlägt fehl und endet in einem festen Fehler-Banner.

Die Ursache ist gesichert. Ein wiederkehrender Keypair-Nutzer hält eine selbst-gemintete HS256-Session: `keypair-verify` signiert sie mit dem `SUPABASE_JWT_SECRET`, mit zufälliger `session_id`, ohne `auth.sessions`-Zeile und ohne Refresh-Token. Der Client adoptiert sie rein lokal über `recoverSession`. GoTrue kennt diesen Token nie.

`linkOAuthToCurrentUser` ruft client-seitig `linkIdentity()` — ein authentifizierter GET an GoTrue `/user/identities/authorize` mit genau diesem Token. Für einen Token, den GoTrue nie ausgestellt hat, gibt es keine Session und keine Identität. GoTrue wirft, der Fehler wird verschluckt.

Drei Lücken verstärken das: kein Backend schreibt je eine `oauth_*`-Credential gegen die bestehende Keypair-user_id, es gibt keinen `kubbapp://auth/callback`-Deep-Link-Handler, und der `AccountUpgradeController` feuert `done()` sofort und schluckt den echten Fehler.

ADR-0010 fordert, dass ein Upgrade die interne user_id erhält und der Keypair als Fallback gültig bleibt. ADR-0010 §Sign-in collision rule verbietet zugleich Auto-Merge per E-Mail — Mergen muss eine explizite, authentifizierte Aktion sein.

## Decision

Der client-seitige `linkIdentity`-Pfad für Keypair-Nutzer wird durch einen **serverseitigen Reconcile** ersetzt.

Die App startet den OAuth-Browser-Flow (`signInWithOAuth`, kein `linkIdentity`), fängt den `kubbapp://auth/callback` über einen neuen `AuthDeepLinkService` und tauscht den Code über `getSessionFromUrl`. Eine neue Edge-Function `oauth-reconcile` (`verify_jwt=false`) bindet die OAuth-Identität an die bestehende Keypair-user_id — gegen zwei unabhängige Beweise:

- **Proof A — Keypair-Besitz**: eine Ed25519-Signatur über eine server-ausgestellte, Single-Use-, 60s-TTL-Challenge. Derselbe Mechanismus, dem `keypair-verify` schon vertraut. Liefert die Keypair-user_id (das Ziel).
- **Proof B — OAuth-Besitz**: der OAuth-Access-Token wird server-seitig über `GET ${SUPABASE_URL}/auth/v1/user` (Service-Role-`apikey`) re-validiert. GoTrue liefert die autoritativen `identities`; das `oauth_subject` wird aus dieser Antwort gelesen, nie aus dem Request-Body. Liefert das `oauth_subject` und die geforkte user_id (die Quelle).

Nur wenn beide passen, schreibt die Function über die SECURITY-DEFINER-RPC `reconcile_link_oauth` (Service-Role-only) die `oauth_*`-Credential gegen die Keypair-user_id und löscht den geforkten `auth.users`-Eintrag in derselben Transaktion. Sie mintet einen frischen HS256-Keypair-Token und gibt ihn in derselben Antwort zurück, sodass der Client in einem Schritt auf die Keypair-user_id zurückkehrt.

Schema-Delta: ein neuer partieller Unique-Index `user_credentials_user_kind_idx ON (user_id, kind) WHERE kind <> 'keypair'`, damit höchstens je eine `oauth_google`- und `oauth_apple`-Zeile pro Nutzer existiert. Kein neues Column — `oauth_subject` und die Shape-/Unique-Constraints existieren bereits.

Begleitende Fixes: `AccountUpgradeController` wird eine echte State-Machine (`launching` → `awaitingCallback` → `reconciling` → `done`/`failed(code)`) ohne Premature-`done()`; typisierte Fehlercodes mappen auf spezifische Banner; das Clobber-Fenster (transiente geforkte OAuth-Emission) wird im `auth_controller` unterdrückt; der `kubbapp`-Scheme wird auf Android registriert (iOS geschrieben, aber geparkt); die Account-Link-Zeile erscheint künftig auch für Keypair-Sessions.

**Gestaged, nicht jetzt gebaut**: die Cold-Start-Auflösung — ein zurückkehrender Nutzer auf einem frischen Gerät, der „Mit Google anmelden" tippt, ohne Seed. Das braucht einen GoTrue-Auth-Hook (`before-user-created` oder `custom-access-token`) auf der Hetzner-Box, der `oauth_subject` in `user_credentials` nachschlägt und die Session an die bestehende user_id bindet statt eine neue Zeile anzulegen. GoTrue konsultiert `user_credentials` nicht von selbst. Das Schema, das der Add-Pfad jetzt schreibt, reicht für den Hook ohne spätere Migration. Bis der Hook existiert, forkt ein Cold-Google-Login für ein bereits verknüpftes Subject weiterhin — dokumentiert als bekannte Lücke.

## Alternatives considered

**Client-seitiges `linkIdentity` reparieren.** Verworfen. `linkIdentity` setzt eine server-bekannte GoTrue-Session voraus. Der Keypair-Nutzer hat keine — sein Token ist selbst-gemintet und GoTrue nie bekannt. Es gibt keinen Client-Trick, der GoTrue dazu bringt, eine Identität an eine Session zu hängen, die es nie ausgestellt hat. Der Pfad ist die Ursache, nicht ein Symptom.

**Eine echte GoTrue-Session für Keypair-Nutzer ausstellen (statt selbst-minten).** Verworfen für diesen Zyklus. Das hiesse, die `keypair-verify`-Architektur umzubauen, sodass GoTrue eine echte Session mit `auth.sessions`-Zeile und Refresh-Token ausstellt — ein viel grösserer Eingriff, der den ganzen Keypair-Auth-Pfad berührt und in ADR-0010 §Auth challenge bewusst als Phase-1-Trade-off abgegrenzt wurde. Bleibt eine Option für eine spätere Identity-Revision, ist aber für das Verknüpfen-Feature nicht nötig.

**Auto-Merge per E-Mail beim Cold-Login.** Verworfen, ausdrücklich von ADR-0010 §Sign-in collision rule verboten. Mergen über E-Mail ist destruktiv und nicht authentifiziert — zwei Konten mit gleicher E-Mail sind nicht zwangsläufig dieselbe Person. Der Reconcile mergt nur über ein kryptografisch bewiesenes Subject.

**`oauth_subject` aus dem Request-Body oder aus `admin.getUser(token).identities` lesen.** Verworfen als unsicher bzw. unzuverlässig. Aus dem Body wäre client-fälschbar. `admin.getUser` kann den Token je nach supabase-js/GoTrue-Version lokal decodieren, und Access-Token-Claims tragen den Provider-`sub` nicht zuverlässig. Nur der GoTrue-autoritative `GET /auth/v1/user`-Read liefert das Subject verlässlich.

**Geforkten Nutzer best-effort über `admin.deleteUser` löschen statt transaktional in der RPC.** Verworfen. Ein separater Admin-Delete riskiert ein Fenster, in dem das Subject auf zwei Nutzern gültig ist (Split-Brain), und Waisen-Nutzer, wenn die App zwischen Insert und Delete stirbt. Der Delete läuft in derselben Transaktion wie der Credential-Insert.

## Consequences

Einfacher wird:

- Keypair-Nutzer können OAuth aus der App hinzufügen, ohne ihre user_id oder Historie zu verlieren. Das erfüllt ADR-0010 §Account upgrade path.
- Der tote Cold-Start-OAuth-Sign-in-Pfad wird nebenbei lebendig, weil der Deep-Link-Service `getSessionFromUrl` für Nicht-Upgrade-Callbacks aufruft.
- Fehler sind sichtbar und actionable statt in ein festes Banner geschluckt.
- Die UI zeigt den verknüpften Provider und die Keypair-Fallback-Notiz wahrheitsgemäss.

Teurer oder offen bleibt:

- Eine zweite Edge-Function und eine SECURITY-DEFINER-RPC mehr an Auth-Oberfläche. Der Trust hängt daran, dass die RPC Service-Role-only bleibt und beide Proofs vor jedem Schreiben passen.
- Prod-GoTrue-Provider-Config (google/apple aktivieren, Secrets, Redirect-Allowlist) ist eine Owner-Aktion. Ohne sie scheitert der Browser-Schritt in Prod, obwohl der gesamte App-/Edge-Code korrekt ist.
- Die Cold-Login-Fork-Lücke bleibt offen, bis der GoTrue-Auth-Hook (Owner-Aktion, eigener ADR) existiert. Ein Nutzer, der reinstalliert und Google cold tippt, forkt bis dahin ein zweites Konto.
- iOS ist heute nicht baubar (kein `Info.plist`/`AppDelegate`/`pbxproj`). Das iOS-Deep-Link-Wiring ist geschrieben, aber bis zum Runner-Scaffolding unverifizierbar. Android ist der Ship-Target (ADR-0015).
- Es gibt kein Edge-Test-Harness im Repo; `oauth-reconcile` wird über eine manuelle curl-Matrix verifiziert, schwächer als die Dart-Test-Disziplin sonst.

### GoTrue-Auth-Hook-Vertrag (für den gestagten Cold-Login-Schritt)

Wenn der Owner den Cold-Login-Hook später baut: ein `before-user-created`- oder `custom-access-token`-Hook auf der Hetzner-GoTrue-Instanz, der bei OAuth-Sign-up für Subject `S` `SELECT user_id FROM user_credentials WHERE kind = 'oauth_'||provider AND oauth_subject = S` ausführt. Treffer -> Session an die gefundene user_id binden statt neue Zeile anlegen. Kein Treffer -> normaler Neu-Nutzer. Das Schema dafür schreibt der Add-Pfad bereits; es ist keine spätere Migration nötig.

Lokale `config.toml` hat `auth.external.google` und `auth.external.apple` auf `enabled = false` — das Aktivieren (lokal mit Mock oder echten Credentials, prod auf Hetzner mit Redirect-Allowlist inkl. `kubbapp://auth/callback`) ist die gegatete Owner-Aktion.
