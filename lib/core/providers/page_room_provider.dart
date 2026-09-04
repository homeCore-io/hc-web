import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The room the page being drawn is about, or null on a page that is not about
/// one.
///
/// Overridden in a `ProviderScope` around the page body, from the route's
/// `?room=` — which `room_field` has always sent and nothing has ever read.
/// A provider rather than an InheritedWidget because everything that needs it
/// is already a `ConsumerWidget` reading providers, and because an override is
/// the one mechanism that cannot be forgotten by a widget in between.
///
/// Null is the honest default: a page opened directly, without a room, is not
/// about a room, and every `@room` reference on it stays unresolved rather than
/// silently pointing at whichever room happens to sort first.
final pageRoomProvider = Provider<String?>((ref) => null);
