import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/auth_provider.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';

/// The first thing anyone sees.
///
/// It was stock Material — underline fields, a default-blue pill — in an app
/// whose whole point is that it does not look like that. Whatever the rest of
/// the app does, this is the impression it makes first, and it was making the
/// wrong one.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _error = null);

    await ref.read(authProvider.notifier).login(_userCtrl.text, _passCtrl.text);
    final auth = ref.read(authProvider);

    if (auth.hasError) {
      setState(() => _error = 'That username and password did not work.');
    } else if (auth.value == true && mounted) {
      // Home, not '/dashboard' — the redirector that route pointed at is gone.
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final loading = ref.watch(authProvider).isLoading;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: EdgeInsets.all(t.space.xl),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // `active`, not `primary`. The token layer has both, and
                      // `primary` is a sky blue that on a pill button reads as
                      // exactly the stock-Material default this redesign exists
                      // to get away from. Amber is what the app actually signs
                      // with — the nav, the toggles, every lit device.
                      Icon(HcIcons.home, size: 22, color: t.accent.active),
                      SizedBox(width: t.space.sm),
                      Text(
                        'HomeCore',
                        style: t.text.displayStyle.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                            color: t.surface.onBase),
                      ),
                    ],
                  ),
                  SizedBox(height: t.space.xl),
                  _Field(
                    controller: _userCtrl,
                    label: 'Username',
                    autofocus: true,
                  ),
                  SizedBox(height: t.space.md),
                  _Field(
                    controller: _passCtrl,
                    label: 'Password',
                    obscure: true,
                    onSubmit: _submit,
                  ),
                  if (_error != null) ...[
                    SizedBox(height: t.space.md),
                    Row(
                      children: [
                        Icon(HcIcons.warning, size: 13, color: t.accent.danger),
                        SizedBox(width: t.space.xs),
                        Expanded(
                          child: Text(
                            _error!,
                            style: t.text.bodySmallStyle
                                .copyWith(color: t.accent.danger),
                          ),
                        ),
                      ],
                    ),
                  ],
                  SizedBox(height: t.space.lg),
                  FilledButton(
                    onPressed: loading ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: t.accent.active,
                      foregroundColor: t.surface.base,
                      padding: EdgeInsets.symmetric(vertical: t.space.md),
                      shape: RoundedRectangleBorder(
                        borderRadius: t.radius.mdR,
                      ),
                    ),
                    child: loading
                        ? SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: t.surface.base,
                            ),
                          )
                        : const Text('Sign in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A filled field, not an underlined one.
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.obscure = false,
    this.autofocus = false,
    this.onSubmit,
  });

  final TextEditingController controller;
  final String label;
  final bool obscure;
  final bool autofocus;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return TextFormField(
      controller: controller,
      obscureText: obscure,
      autofocus: autofocus,
      style: t.text.subtitleStyle.copyWith(color: t.surface.onBase),
      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
      onFieldSubmitted: onSubmit == null ? null : (_) => onSubmit!(),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: t.text.bodyStyle.copyWith(color: t.surface.onBaseMuted),
        filled: true,
        fillColor: t.surface.raised,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: t.space.md,
          vertical: t.space.md,
        ),
        border: OutlineInputBorder(
          borderRadius: t.radius.mdR,
          borderSide: BorderSide(color: t.stroke.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: t.radius.mdR,
          borderSide: BorderSide(color: t.stroke.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: t.radius.mdR,
          borderSide: BorderSide(color: t.accent.active, width: 1.5),
        ),
      ),
    );
  }
}
