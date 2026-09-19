// ignore_for_file: library_private_types_in_public_api, use_build_context_synchronously

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:atomic_notes/utility/component/login_button.dart';
import 'package:atomic_notes/utility/component/logo_container.dart';
import 'package:atomic_notes/utility/component/my_snackbar.dart';
import 'package:flutter/material.dart';

/// MIGRATION NOTE: this used to be an email/password sign-in and sign-up
/// pair (with a mode-switch tab, textfields, an email-verification detour to
/// signup_verify_page.dart, and a forgot-password detour to
/// reset_password_page.dart/reset_verify_page.dart) built on Supabase Auth.
/// The new backend only supports Google Sign-In (see the server's README —
/// that was the original brief's stated auth design, not a simplification
/// made here), so there is no password to forget and nothing to verify by
/// email. Those three pages were deleted along with their main.dart routes
/// once Google-only auth was confirmed — there was no live path to them left.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _api = ApiClient.instance;
  bool _isLoading = false;

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      await _api.signInWithGoogle();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/splashpage');
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'cancelled') return; // user dismissed the picker — not an error
      // Visible in `adb logcat -s flutter`; carries error codes only, never tokens.
      debugPrint('Sign-in failed: ${e.code} (HTTP ${e.statusCode})');
      MySnackBar(text: _friendly(e), sec: 2500).showMySnackBar(context);
    } catch (e) {
      if (!mounted) return;
      // A Google PlatformException (for example ApiException: 10 when the signing
      // certificate is not registered) or a network error ends up here.
      debugPrint('Sign-in failed unexpectedly: ${e.runtimeType}: $e');
      const MySnackBar(text: 'Unknown error occurred!', sec: 2000)
          .showMySnackBar(context);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendly(ApiException e) {
    switch (e.code) {
      case 'no_server_auth_code':
        return "Couldn't complete Google sign-in. Please try again.";
      case 'code_exchange_failed':
        return 'Sign-in expired before it finished — please try again.';
      case 'refresh_token_required':
        return 'Google did not allow offline access. Sign in again and accept every permission.';
      case 'incomplete_token_response':
      case 'invalid_id_token':
        return "Google's answer could not be verified. Please try again.";
      case 'internal_error':
      case 'http_500':
      case 'http_502':
      case 'http_503':
        return 'The Atomic Notes server had a problem. Please try again shortly.';
      default:
        return 'Sign-in failed. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 96),
              const LogoContainer(showTagline: true),
              const SizedBox(height: AppSpace.xxl),
              const _AuthHeader(
                eyebrow: 'WELCOME',
                title: 'Your notes,\nyour Drive.',
                subtitle:
                    'Sign in with Google. Notes sync to your own Google Drive — nothing is stored on our servers but sync metadata.',
              ),
              const SizedBox(height: AppSpace.xl),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.screenMargin),
                child: LoginButton(
                  ico: 'assets/login.svg',
                  isLoading: _isLoading,
                  signIn: _signInWithGoogle,
                  text: 'Sign in with Google',
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.screenMargin),
                child: GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/tcpage'),
                  behavior: HitTestBehavior.opaque,
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HairRule(),
                      SizedBox(height: AppSpace.md),
                      MonoLabel('BY SIGNING IN YOU AGREE TO THE TERMS'),
                      SizedBox(height: AppSpace.xs),
                      ArrowLink('Read terms & conditions'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.xl),
            ],
          ),
        ),
      ),
    );
  }
}

/// Eyebrow + display headline + one-line subtitle, left-aligned against the
/// page margin — the standard section opener in this design system.
class _AuthHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  const _AuthHeader({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpace.screenMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MonoLabel(eyebrow, color: AppColors.signal),
          const SizedBox(height: AppSpace.xs),
          EditorialHeading(title, style: AppType.displayLg),
          const SizedBox(height: AppSpace.xs),
          Text(subtitle, style: AppType.bodyMd),
          const SizedBox(height: AppSpace.md),
          const HairRule(color: AppColors.ink),
        ],
      ),
    );
  }
}
