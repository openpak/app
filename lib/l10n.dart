/// The app's strings: lib/l10n/*.arb, generated into AppLocalizations by
/// `flutter pub get`. English is the template; the other languages follow the
/// website's glossary (website/docs/glossary.md), so a player reads the same
/// word for the same thing on both.
library;

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'l10n/app_localizations.dart';

export 'l10n/app_localizations.dart';

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// What a person reads for a failed call: the translation of the server's
/// stable error code. An unknown code (a newer server) or none at all (an older
/// one) is worded by its HTTP status, as the contract asks; the English `error`
/// is only shown when an old server sent a status nothing else covers.
String apiErrorText(AppLocalizations l, ApiException e) {
  final byCode = switch (e.code) {
    'account_suspended' => l.errorAccountSuspended,
    'avatar_invalid' => l.errorAvatarInvalid,
    'avatars_unavailable' => l.errorAvatarsUnavailable,
    'bad_request' => l.errorBadRequest,
    'challenge_expired' => l.errorChallengeExpired,
    'chat_blocked' => l.errorChatBlocked,
    'chat_not_friends' => l.errorChatNotFriends,
    'chat_unavailable' => l.errorChatUnavailable,
    'conflict' => l.errorConflict,
    'console_taken' => l.errorConsoleTaken,
    'forbidden' => l.errorForbidden,
    'friend_code_unknown' => l.errorFriendCodeUnknown,
    'friend_conflict' => l.errorFriendConflict,
    'friend_self' => l.errorFriendSelf,
    'internal' => l.errorInternal,
    'invalid_pin' => l.parentalPinInvalid,
    'invalid_credentials' => l.errorInvalidCredentials,
    'link_expired' => l.errorLinkExpired,
    'no_pending_request' => l.errorNoPendingRequest,
    'not_found' => l.errorNotFound,
    'not_votable' => l.errorNotVotable,
    'quota_exceeded' => l.errorQuotaExceeded,
    'rate_limited' => l.errorRateLimited,
    'registrations_closed' => l.errorRegistrationsClosed,
    'saves_unavailable' => l.errorSavesUnavailable,
    'service_unavailable' => l.errorServiceUnavailable,
    'session_expired' => l.errorSessionExpired,
    'two_factor_locked' => l.errorTwoFactorLocked,
    'two_factor_required' => l.errorTwoFactorRequired,
    'unauthorized' => l.errorUnauthorized,
    'voice_room_full' => l.errorVoiceRoomFull,
    'voice_room_unknown' => l.errorVoiceRoomUnknown,
    'wfc_not_found' => l.errorWfcNotFound,
    'wfc_unavailable' => l.errorWfcUnavailable,
    'wrong_code' => l.errorWrongCode,
    'wrong_password' => l.errorWrongPassword,
    _ => null,
  };
  if (byCode != null) return byCode;
  final byStatus = switch (e.statusCode) {
    400 => l.errorBadRequest,
    401 => l.errorUnauthorized,
    403 => l.errorForbidden,
    404 => l.errorNotFound,
    409 => l.errorConflict,
    429 => l.errorRateLimited,
    502 || 503 => l.errorServiceUnavailable,
    507 => l.errorQuotaExceeded,
    _ => null,
  };
  if (byStatus != null) return byStatus;
  if (e.code == null && e.fromServer) return e.message;
  return l.errorGeneric(e.statusCode);
}

/// A day, as the locale writes it short: "Sep 18, 2026", "18. Sept. 2026".
String shortDate(AppLocalizations l, DateTime d) =>
    DateFormat.yMMMd(l.localeName).format(d.toLocal());

/// A day and a time: "Sep 18, 2026 14:05".
String shortDateTime(AppLocalizations l, DateTime d) =>
    DateFormat.yMMMd(l.localeName).add_Hm().format(d.toLocal());
