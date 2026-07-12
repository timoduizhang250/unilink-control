import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/hanako/drive_mounter.dart';
import 'package:flutter_hbb/hanako/endpoint_resolver.dart';
import 'package:flutter_hbb/hanako/native_service_launcher.dart';
import 'package:flutter_hbb/hanako/ssh_terminal.dart';

void showUniLinkConnectionDecision({
  required UniLinkEndpointTarget target,
  required VoidCallback onRemoteControl,
  void Function(String host)? onLocalRemoteControl,
  VoidCallback? onPublicRemoteControl,
}) {
  gFFI.dialogManager.show((setState, close, context) => CustomAlertDialog(
        title: Text('${translate('Connect')} ${target.label}'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: isDesktop ? 440 : 0,
            maxWidth: isDesktop ? 520 : double.infinity,
          ),
          child: _ConnectionDecisionBody(
            target: target,
            onClose: close,
            onRemoteControl: onRemoteControl,
            onLocalRemoteControl: onLocalRemoteControl,
            onPublicRemoteControl: onPublicRemoteControl,
          ),
        ),
        actions: [dialogButton('Close', onPressed: close, isOutline: true)],
        onCancel: close,
      ));
}

class _ConnectionDecisionBody extends StatefulWidget {
  final UniLinkEndpointTarget target;
  final VoidCallback onClose;
  final VoidCallback onRemoteControl;
  final void Function(String host)? onLocalRemoteControl;
  final VoidCallback? onPublicRemoteControl;

  const _ConnectionDecisionBody({
    required this.target,
    required this.onClose,
    required this.onRemoteControl,
    required this.onLocalRemoteControl,
    required this.onPublicRemoteControl,
  });

  @override
  State<_ConnectionDecisionBody> createState() =>
      _ConnectionDecisionBodyState();
}

class _ConnectionDecisionBodyState extends State<_ConnectionDecisionBody> {
  late Future<UniLinkCapabilityStatus> _capabilities;

  @override
  void initState() {
    super.initState();
    _capabilities = UniLinkEndpointResolver.capabilityStatus(widget.target);
  }

  void _refresh() => setState(() {
        _capabilities = UniLinkEndpointResolver.capabilityStatus(widget.target,
            force: true);
      });

  void _open(VoidCallback action) {
    widget.onClose();
    action();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<UniLinkCapabilityStatus>(
        future: _capabilities,
        builder: (context, snapshot) {
          final checking = snapshot.connectionState == ConnectionState.waiting;
          final status = snapshot.data;
          final remoteReady = status?.remoteControlAvailable == true;
          final localUniLinkHost = status?.localUniLinkHost;
          final localUniLinkReady =
              localUniLinkHost != null && widget.onLocalRemoteControl != null;
          final sshReady = status?.sshReachable == true;
          final driveReady = status?.smbReachable == true;
          final rdpReady = status?.rdpReachable == true;
          final vncReady = status?.vncReachable == true;
          final isWindowsTarget =
              widget.target.platform.toLowerCase().contains('windows');
          final isMacTarget = widget.target.isMac;
          final primaryTitle = localUniLinkReady
              ? translate('Connect on local network')
              : translate('Remote Control');
          final primaryDetail = checking
              ? translate('Checking available connections...')
              : localUniLinkReady
                  ? translate('Fast local connection is ready')
                  : remoteReady
                      ? (widget.target.online
                          ? translate('Online')
                          : translate('Ready to try'))
                      : translate('Device ID is not ready');
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                  translate(
                      'UniLink will select the best available connection.'),
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              _ConnectionOption(
                icon: Icons.desktop_windows_outlined,
                title: primaryTitle,
                detail: primaryDetail,
                available: localUniLinkReady || remoteReady,
                primary: true,
                onPressed: localUniLinkReady
                    ? () => _open(
                          () => widget.onLocalRemoteControl!(localUniLinkHost),
                        )
                    : remoteReady
                        ? () => _open(widget.onRemoteControl)
                        : null,
              ),
              if (isWindowsTarget) ...[
                const SizedBox(height: 8),
                _ConnectionOption(
                  icon: Icons.laptop_windows_outlined,
                  title: translate('Windows Remote Desktop'),
                  detail: checking
                      ? translate('Checking available connections...')
                      : rdpReady
                          ? translate('Available on local network')
                          : translate(
                              'Windows Remote Desktop is not reachable'),
                  available: rdpReady,
                  onPressed: rdpReady
                      ? () => _open(() => UniLinkNativeServiceLauncher.launch(
                            widget.target,
                            UniLinkEndpointService.rdp,
                          ))
                      : null,
                ),
              ],
              if (isMacTarget) ...[
                const SizedBox(height: 8),
                _ConnectionOption(
                  icon: Icons.laptop_mac_outlined,
                  title: translate('Mac Screen Sharing'),
                  detail: checking
                      ? translate('Checking available connections...')
                      : vncReady
                          ? translate('Available on local network')
                          : translate('Mac Screen Sharing is not reachable'),
                  available: vncReady,
                  onPressed: vncReady
                      ? () => _open(() => UniLinkNativeServiceLauncher.launch(
                            widget.target,
                            UniLinkEndpointService.vnc,
                          ))
                      : null,
                ),
              ],
              const SizedBox(height: 8),
              _ConnectionOption(
                icon: Icons.terminal_rounded,
                title: translate('SSH'),
                detail: checking
                    ? translate('Checking available connections...')
                    : sshReady
                        ? translate('Available on local network')
                        : translate('SSH is not reachable'),
                available: sshReady,
                onPressed: sshReady
                    ? () => _open(
                          () => showUniLinkSshTerminal(target: widget.target),
                        )
                    : null,
              ),
              const SizedBox(height: 8),
              _ConnectionOption(
                icon: Icons.storage_outlined,
                title: translate('Mount drive'),
                detail: checking
                    ? translate('Checking available connections...')
                    : driveReady
                        ? translate('Available on local network')
                        : translate('Remote SMB is not reachable'),
                available: driveReady,
                onPressed: driveReady
                    ? () => _open(
                          () => showUniLinkDriveDialog(
                            target:
                                UniLinkDriveTarget.fromEndpoint(widget.target),
                          ),
                        )
                    : null,
              ),
              if (widget.onPublicRemoteControl != null)
                TextButton.icon(
                  onPressed: () => _open(widget.onPublicRemoteControl!),
                  icon: const Icon(Icons.public, size: 18),
                  label: Text(translate('Connect via public server')),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: translate('Refresh'),
                  onPressed: checking ? null : _refresh,
                  icon: const Icon(Icons.refresh, size: 18),
                ),
              ),
            ],
          );
        },
      );
}

class _ConnectionOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final bool available;
  final bool primary;
  final VoidCallback? onPressed;

  const _ConnectionOption({
    required this.icon,
    required this.title,
    required this.detail,
    required this.available,
    required this.onPressed,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = available
        ? (primary ? MyTheme.accent : Theme.of(context).colorScheme.primary)
        : Theme.of(context).disabledColor;
    return Material(
      color: available
          ? color.withValues(alpha: 0.06)
          : color.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(detail, style: Theme.of(context).textTheme.bodySmall),
              ],
            )),
            Icon(available ? Icons.chevron_right_rounded : Icons.block_outlined,
                color: color),
          ]),
        ),
      ),
    );
  }
}
