import 'package:flutter/material.dart';

import '../../core/models/dashboard.dart';
import '../../shell/hc_sheet.dart';
import 'card_library.dart';

/// The catalogue, as a sheet.
///
/// **One catalogue.** This file used to hold a second one — a hand-kept list
/// of fourteen types under a doc comment claiming it listed "whatever the
/// WidgetRegistry knows", which it had not for a long time. It is the same
/// `CardLibrary` the panel used to show, opened from the ⊞ tool and from the
/// add button, so a card added in one place is added everywhere.
///
/// It is a sheet rather than a permanent tab because of what the panel is for.
/// The panel holds what this *house* has — its layers, its devices, its
/// pictures. A catalogue of card types is not a fact about the house; it is a
/// list of what this app can draw, which is the rail's question, and the ⊞ tool
/// is the rail asking it.
Future<DashboardWidgetModel?> showWidgetPalette(BuildContext context) {
  return showHcSheet<DashboardWidgetModel>(
    context,
    title: 'Add to this page',
    // **As tall as the window allows, not a fixed 520.** The catalogue always
    // has more to show than fits, so a fixed height left it ending partway
    // down a tall panel with dead space beneath it. The sheet sizes to its
    // child, so the child is the one that has to ask for the room.
    child: Builder(
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: CardLibrary(
          onPick: (created) => Navigator.of(context).pop(created),
        ),
      ),
    ),
  );
}
