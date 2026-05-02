# app — top-level wiring

```
app/
├── app.dart        MaterialApp.router root, ProviderScope
├── router.dart     go_router configuration
└── theme.dart      Material 3 theme (light + dark, color seed)
```

Entry point in `lib/main.dart` should remain a thin `runApp(...)` wrapper around what lives here.
