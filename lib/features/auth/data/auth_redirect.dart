/// Custom-scheme deep link the OAuth browser flow redirects back to.
/// Registered on Android via the `kubbapp`/`auth` intent-filter and
/// listed in `config.toml` `additional_redirect_urls`. Single source of
/// truth so the adapter and the deep-link service never drift apart.
const kAuthCallback = 'kubbapp://auth/callback';
