/// Route paths for the auth flow. Centralised so screen widgets and
/// the router agree on a single source of truth.
abstract final class AuthRoutes {
  static const signIn = '/sign-in';
  static const earlyAccess = '/sign-in/early-access';
  static const anonymousSignup = '/sign-in/anonymous';
  static const restore = '/sign-in/restore';
  static const accountLink = '/sign-in/account-link';
  static const deleteAccount = '/sign-in/delete';
  static const onboardingTour = '/onboarding-tour';
  static const editProfile = '/profile/edit';
  static const inbox = '/inbox';
}
