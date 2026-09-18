// ignore_for_file: non_constant_identifier_names

// Public configuration only. Copy to cred.dart; CI supplies --dart-define values.
// GOOGLE_SERVER_CLIENT_ID must exactly equal the Server GOOGLE_CLIENT_ID:
// use the SAME Web application OAuth client, plus a separate Android client
// registered for com.notes.atomic and the actual release signing certificate.
class CredService {
  final String API_BASE_URL = const String.fromEnvironment('API_BASE_URL',
      defaultValue: 'https://atomic-notes-server-gde2e.vercel.app/api');
  final String GOOGLE_SERVER_CLIENT_ID = const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID',
      defaultValue: 'YOUR_WEB_OAUTH_CLIENT_ID.apps.googleusercontent.com');
}
