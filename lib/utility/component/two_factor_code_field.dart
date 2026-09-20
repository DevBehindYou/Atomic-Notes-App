import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The box a two-factor code is typed into: six digits from an authenticator
/// app, or (with [recovery]) one of the single-use recovery codes.
class TwoFactorCodeField extends StatelessWidget {
  final TextEditingController controller;
  final bool recovery;
  final bool enabled;
  final bool autofocus;

  /// Called once six digits have been typed. Not used for recovery codes,
  /// which have no fixed moment of completion.
  final ValueChanged<String>? onCompleted;
  final ValueChanged<String>? onSubmitted;

  const TwoFactorCodeField({
    required this.controller,
    this.recovery = false,
    this.enabled = true,
    this.autofocus = false,
    this.onCompleted,
    this.onSubmitted,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MonoLabel(recovery ? 'Recovery code' : '6-digit code', small: true),
        TextField(
          controller: controller,
          enabled: enabled,
          autofocus: autofocus,
          textAlign: TextAlign.center,
          keyboardType: recovery ? TextInputType.text : TextInputType.number,
          textCapitalization: recovery
              ? TextCapitalization.characters
              : TextCapitalization.none,
          autocorrect: false,
          enableSuggestions: false,
          cursorColor: AppColors.signal,
          style: const TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 28,
            fontWeight: FontWeight.w500,
            letterSpacing: 6,
            color: AppColors.ink,
          ),
          inputFormatters: recovery
              ? [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
                  LengthLimitingTextInputFormatter(11),
                  const _UpperCase(),
                ]
              : [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
          onChanged: (value) {
            if (!recovery && value.length == 6) onCompleted?.call(value);
          },
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            isDense: true,
            filled: false,
            hintText: recovery ? 'XXXXX-XXXXX' : '000000',
            hintStyle: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 28,
              letterSpacing: 6,
              color: AppColors.outlineVariant,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            enabledBorder: const UnderlineInputBorder(
              borderSide:
                  BorderSide(color: AppColors.ink, width: AppStroke.rule),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide:
                  BorderSide(color: AppColors.signal, width: AppStroke.offset),
            ),
            disabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(
                  color: AppColors.outlineVariant, width: AppStroke.rule),
            ),
          ),
        ),
      ],
    );
  }
}

class _UpperCase extends TextInputFormatter {
  const _UpperCase();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
