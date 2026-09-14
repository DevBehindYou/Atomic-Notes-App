// ignore_for_file: non_constant_identifier_names

// TEMPLATE. Copy this file to `cred.dart` in the same folder and fill in your
// own values. `cred.dart` is gitignored, so real values never land in this
// public repo — same setup as before, updated for the new backend.
//
// GOOGLE_SERVER_CLIENT_ID is the OAuth client ID of a *second*, separate
// OAuth client registered in the same Google Cloud project as the server's
// GOOGLE_CLIENT_ID — type "Web application", not Android/iOS. google_sign_in
// needs this to request a serverAuthCode the backend can exchange for tokens
// with Drive access; it is NOT a secret and is safe to embed in a client,
// the same way the old Supabase anon key was — nothing here can authenticate
// as your backend without also having the matching CLIENT_SECRET, which
// stays server-side only (see the server's own .env.example).

class CredService {
  final String API_BASE_URL = "https://your-domain.vercel.app/api";
  final String GOOGLE_SERVER_CLIENT_ID = "YOUR_WEB_OAUTH_CLIENT_ID.apps.googleusercontent.com";
}
