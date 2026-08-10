import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/assets_api.dart';
import '../../core/providers/assets_provider.dart';
import '../../core/web/browser_files.dart';
import '../../design/tokens.dart';

/// An address, with a way to make one.
///
/// Every picture and font in the app has been stored as a *string* the browser
/// resolves — a card's picture, a page background, the image widget, a skin's
/// font. That was never the problem: the problem was that there was nowhere to
/// put a file, so the only way to fill the string was to host the file
/// yourself first.
///
/// So this is the same field it always was, plus a button. Paste an address and
/// nothing has changed; choose a file and it is uploaded and the address it
/// comes back with is written into the same string. Nothing stored changes
/// shape, which is why this could be added to four places at once without
/// migrating anything.
///
/// [kinds] decides what the file picker offers and what is accepted — pictures
/// for a background, fonts for a skin. It is checked here as well as in core:
/// a 415 after choosing a file is a worse way to learn than being told before
/// the upload starts.
class AssetField extends ConsumerStatefulWidget {
  const AssetField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.hint = 'Address, or choose a file',
    this.kinds = imageExtensions,
    this.group,
    this.preview = true,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? label;
  final String hint;

  /// Extensions offered and accepted. See [imageExtensions], [fontExtensions].
  final List<String> kinds;

  /// Ties the upload to whatever it arrived with, so it can be pruned as a set.
  final String? group;

  /// A thumbnail of what the address points at. Off for fonts, which have
  /// nothing to show at this size.
  final bool preview;

  @override
  ConsumerState<AssetField> createState() => _AssetFieldState();
}

class _AssetFieldState extends ConsumerState<AssetField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);
  bool _uploading = false;
  String? _note;

  @override
  void didUpdateWidget(AssetField old) {
    super.didUpdateWidget(old);
    // Only when something else changed it — never mid-typing, which would move
    // the caret to the end on every keystroke.
    if (widget.value != old.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    final file = await pickFile(accept: acceptFor(widget.kinds));
    if (file == null || !mounted) return;

    final type = contentTypeFor(file.name);
    if (type == null || !widget.kinds.contains(_extensionOf(file.name))) {
      setState(
          () => _note = 'Not a kind this stores: ${widget.kinds.join(', ')}');
      return;
    }
    if (file.bytes.length > maxAssetBytes) {
      setState(() => _note =
          '${formatBytes(file.bytes.length)} is over the ${formatBytes(maxAssetBytes)} limit');
      return;
    }

    setState(() {
      _uploading = true;
      _note = null;
    });
    try {
      final ref0 = await ref.read(assetsApiProvider).upload(
            file.bytes,
            filename: file.name,
            contentType: type,
            group: widget.group,
          );
      if (!mounted) return;
      _controller.text = ref0.url;
      widget.onChanged(ref0.url);
      setState(() {
        _uploading = false;
        _note = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        // The upload is the one step here that reaches the network, so say
        // which step failed rather than blaming the file.
        _note = 'Upload failed: ${_short(e)}';
      });
    }
  }

  void _clear() {
    _controller.clear();
    widget.onChanged('');
    setState(() => _note = null);
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final value = _controller.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.preview && value.isNotEmpty) ...[
              _Thumb(url: value),
              SizedBox(width: t.space.sm),
            ],
            Expanded(
              child: TextField(
                controller: _controller,
                style: t.text.bodySmallStyle.copyWith(color: t.surface.onBase),
                onChanged: (s) => widget.onChanged(s.trim()),
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  labelText: widget.label,
                  hintText: widget.hint,
                  hintStyle: t.text.bodySmallStyle
                      .copyWith(color: t.surface.onBaseMuted),
                  suffixIcon: value.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          tooltip: 'Clear',
                          onPressed: _uploading ? null : _clear,
                        ),
                ),
              ),
            ),
            SizedBox(width: t.space.sm),
            SizedBox(
              height: 38,
              child: _uploading
                  ? Padding(
                      padding: EdgeInsets.symmetric(horizontal: t.space.sm),
                      child: const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: _choose,
                      icon: const Icon(Icons.upload_file, size: 16),
                      label: const Text('Choose'),
                    ),
            ),
          ],
        ),
        if (_note != null)
          Padding(
            padding: EdgeInsets.only(top: t.space.xs),
            child: Text(
              _note!,
              style: t.text.captionStyle.copyWith(color: t.accent.warn),
            ),
          ),
      ],
    );
  }
}

String _extensionOf(String filename) {
  final dot = filename.lastIndexOf('.');
  return dot < 0 ? '' : filename.substring(dot + 1).toLowerCase();
}

String _short(Object e) {
  final s = e.toString();
  return s.length > 90 ? '${s.substring(0, 90)}…' : s;
}

/// What the address points at, small.
///
/// A broken address is the most common mistake this field invites, and it is
/// invisible until the card is drawn. Showing it here means finding out while
/// the field is still in front of you.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: t.radius.smR,
        border: Border.all(color: t.stroke.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        // Not an error state: a font has no thumbnail and an address being
        // typed is not yet wrong.
        errorBuilder: (_, __, ___) => Icon(
          Icons.image_not_supported_outlined,
          size: 16,
          color: t.surface.onBaseMuted,
        ),
      ),
    );
  }
}
