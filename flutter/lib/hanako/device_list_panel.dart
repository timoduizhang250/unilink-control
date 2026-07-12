import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/hanako/connection_decision.dart';
import 'package:flutter_hbb/hanako/control_client.dart';
import 'package:flutter_hbb/hanako/control_settings.dart';
import 'package:flutter_hbb/hanako/drive_mounter.dart';
import 'package:flutter_hbb/hanako/endpoint_resolver.dart';
import 'package:flutter_hbb/hanako/public_server.dart';
import 'package:flutter_hbb/hanako/ssh_terminal.dart';
import 'package:flutter_hbb/hanako/unilink_theme.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';

class HanakoDeviceListPanel extends StatefulWidget {
  const HanakoDeviceListPanel({Key? key}) : super(key: key);

  @override
  State<HanakoDeviceListPanel> createState() => _HanakoDeviceListPanelState();
}

class _HanakoDeviceListPanelState extends State<HanakoDeviceListPanel> {
  Future<List<HanakoDevice>>? _devicesFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _devicesFuture = hanakoControlClient.canListDevices
        ? hanakoControlClient.listDevices()
        : _loadLocalDevices();
  }

  Future<List<HanakoDevice>> _loadLocalDevices() async {
    await Future.wait([
      bind.mainLoadRecentPeers(),
      bind.mainLoadLanPeers(),
    ]);
    final peers = <String, Peer>{};
    for (final peer in [
      ...gFFI.recentPeersModel.peers,
      ...gFFI.lanPeersModel.peers,
    ]) {
      if (peer.id.trim().isEmpty) continue;
      peers[peer.id] = peer;
    }
    return peers.values
        .map((peer) => HanakoDevice(
              id: peer.id,
              alias: peer.alias,
              platform: peer.platform,
              rustdeskId: peer.id,
              hostname: peer.hostname,
              lanAddresses: const [],
              lastSeenAt:
                  peer.online ? DateTime.now().toUtc().toIso8601String() : null,
              version: null,
              tags: const [],
              notes: peer.note,
              enrolledBy: null,
              createdAt: '',
              updatedAt: '',
            ))
        .toList(growable: false);
  }

  void _refresh() {
    if (!mounted) return;
    setState(_reload);
  }

  void _openSettings() {
    showUniLinkMyDevicesHelpDialog(onChanged: _refresh);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.54),
        border: Border.all(color: UniLinkPalette.border),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.045),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Header(onRefresh: _refresh, onSettings: _openSettings),
          FutureBuilder<List<HanakoDevice>>(
            future: _devicesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator(minHeight: 2);
              }
              if (snapshot.hasError) {
                return _EmptyState(
                  icon: Icons.error_outline,
                  text: _cleanError(snapshot.error!),
                  action: translate('Refresh'),
                  onPressed: _refresh,
                );
              }
              final devices = snapshot.data ?? const <HanakoDevice>[];
              if (devices.isEmpty) {
                return _EmptyState(
                  icon: Icons.devices_other_outlined,
                  text: translate('No enrolled devices yet.'),
                  action: translate('Refresh'),
                  onPressed: _refresh,
                );
              }
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 190),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: devices.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    return _DeviceRow(
                      device: devices[index],
                      onChanged: _refresh,
                      isManaged: hanakoControlClient.canListDevices,
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onRefresh;
  final VoidCallback onSettings;

  const _Header({
    required this.onRefresh,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          const Icon(Icons.devices_other_outlined,
              size: 20, color: UniLinkPalette.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              translate('My Devices'),
              style: const TextStyle(
                color: UniLinkPalette.text,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Tooltip(
            message: translate('Refresh'),
            child: IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: onRefresh,
            ),
          ),
          Tooltip(
            message: translate('Settings'),
            child: IconButton(
              icon: const Icon(Icons.settings_outlined, size: 18),
              onPressed: onSettings,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  final HanakoDevice device;
  final VoidCallback onChanged;
  final bool isManaged;

  const _DeviceRow({
    required this.device,
    required this.onChanged,
    required this.isManaged,
  });

  @override
  Widget build(BuildContext context) {
    final online = _isRecentlySeen(device.lastSeenAt);
    final statusColor =
        online ? const Color(0xFF0A9471) : Theme.of(context).disabledColor;
    final detail = _deviceDetail(device);
    final canUsePublic = uniLinkCanUsePublicServer(device.rustdeskId);
    final target = UniLinkEndpointTarget(
      peerId: device.rustdeskId,
      label: _deviceLabel(device),
      platform: device.platform,
      hostname: device.hostname,
      username: '',
      lanAddresses: device.lanAddresses,
      online: online,
    );
    return ListTile(
      onTap: device.rustdeskId.isEmpty
          ? null
          : () => showUniLinkConnectionDecision(
                target: target,
                onRemoteControl: () => connect(context, device.rustdeskId),
                onLocalRemoteControl: (host) => connect(context, host),
                onPublicRemoteControl: canUsePublic
                    ? () =>
                        connect(context, uniLinkPublicPeerId(device.rustdeskId))
                    : null,
              ),
      dense: true,
      isThreeLine: detail.isNotEmpty,
      minLeadingWidth: 0,
      leading: Icon(_platformIcon(device.platform), size: 20),
      title: Text(
        _deviceLabel(device),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${device.rustdeskId}  ${_lastSeenLabel(device.lastSeenAt)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (detail.isNotEmpty)
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: translate('Connect'),
            child: IconButton(
              icon: const Icon(Icons.play_arrow_rounded, size: 22),
              onPressed: device.rustdeskId.isEmpty
                  ? null
                  : () => showUniLinkConnectionDecision(
                        target: target,
                        onRemoteControl: () =>
                            connect(context, device.rustdeskId),
                        onLocalRemoteControl: (host) => connect(context, host),
                        onPublicRemoteControl: canUsePublic
                            ? () => connect(
                                context, uniLinkPublicPeerId(device.rustdeskId))
                            : null,
                      ),
            ),
          ),
          Tooltip(
            message: translate('Connect via public server'),
            child: IconButton(
              icon: const Icon(Icons.public, size: 19),
              onPressed: canUsePublic
                  ? () => connect(
                        context,
                        uniLinkPublicPeerId(device.rustdeskId),
                      )
                  : null,
            ),
          ),
          UniLinkSshActionButton(
            target: target,
          ),
          Tooltip(
            message: translate('Mount drive'),
            child: IconButton(
              icon: const Icon(Icons.storage_outlined, size: 19),
              onPressed: () => showUniLinkDriveDialog(
                target: UniLinkDriveTarget(
                  peerId: device.rustdeskId,
                  label: _deviceLabel(device),
                  platform: device.platform,
                  hostname: device.hostname,
                  username: '',
                  lanAddresses: device.lanAddresses,
                ),
              ),
            ),
          ),
          if (isManaged)
            PopupMenuButton<String>(
              tooltip: translate('More'),
              icon: const Icon(Icons.more_vert, size: 18),
              onSelected: (value) {
                if (value == 'edit') {
                  _showEditDeviceDialog(
                    context: context,
                    device: device,
                    onChanged: onChanged,
                  );
                } else if (value == 'public') {
                  connect(context, uniLinkPublicPeerId(device.rustdeskId));
                } else if (value == 'delete') {
                  _showDeleteDeviceDialog(
                    context: context,
                    device: device,
                    onChanged: onChanged,
                  );
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  value: 'edit',
                  child: Row(
                    children: [
                      const Icon(Icons.edit_outlined, size: 18),
                      const SizedBox(width: 8),
                      Text(translate('Edit Device')),
                    ],
                  ),
                ),
                if (canUsePublic)
                  PopupMenuItem<String>(
                    value: 'public',
                    child: Row(
                      children: [
                        const Icon(Icons.public, size: 18),
                        const SizedBox(width: 8),
                        Text(translate('Connect via public server')),
                      ],
                    ),
                  ),
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        translate('Delete device'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

void _showEditDeviceDialog({
  required BuildContext context,
  required HanakoDevice device,
  required VoidCallback onChanged,
}) {
  final aliasController = TextEditingController(text: device.alias ?? '');
  final tagsController = TextEditingController(text: device.tags.join(', '));
  final notesController = TextEditingController(text: device.notes ?? '');
  var statusMsg = '';
  var isInProgress = false;

  gFFI.dialogManager.show((setState, close, context) {
    Future<void> submit() async {
      if (isInProgress) return;
      setState(() {
        statusMsg = '';
        isInProgress = true;
      });
      try {
        await hanakoControlClient.updateDevice(
          id: device.id,
          alias: aliasController.text,
          tags: _parseTags(tagsController.text),
          notes: notesController.text,
        );
        onChanged();
        showToast(translate('Successful'));
        close();
      } catch (e) {
        setState(() {
          statusMsg = _cleanError(e);
          isInProgress = false;
        });
      }
    }

    return CustomAlertDialog(
      title: Text(translate('Edit Device')),
      content: ConstrainedBox(
        constraints: BoxConstraints(minWidth: isDesktop ? 420 : 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: aliasController,
              enabled: !isInProgress,
              autofocus: true,
              decoration: InputDecoration(labelText: translate('Device alias')),
            ).workaroundFreezeLinuxMint(),
            const SizedBox(height: 10),
            TextField(
              controller: tagsController,
              enabled: !isInProgress,
              decoration: InputDecoration(labelText: translate('Tags')),
            ).workaroundFreezeLinuxMint(),
            const SizedBox(height: 10),
            TextField(
              controller: notesController,
              enabled: !isInProgress,
              maxLines: 3,
              decoration: InputDecoration(labelText: translate('Notes')),
            ).workaroundFreezeLinuxMint(),
            if (statusMsg.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  statusMsg,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (isInProgress)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
      actions: [
        dialogButton('Cancel', onPressed: close, isOutline: true),
        dialogButton('Save', onPressed: isInProgress ? null : submit),
      ],
      onSubmit: isInProgress ? null : submit,
      onCancel: close,
    );
  });
}

void _showDeleteDeviceDialog({
  required BuildContext context,
  required HanakoDevice device,
  required VoidCallback onChanged,
}) {
  var statusMsg = '';
  var isInProgress = false;

  gFFI.dialogManager.show((setState, close, context) {
    Future<void> submit() async {
      if (isInProgress) return;
      setState(() {
        statusMsg = '';
        isInProgress = true;
      });
      try {
        await hanakoControlClient.deleteDevice(id: device.id);
        onChanged();
        showToast(translate('Device deleted'));
        close();
      } catch (e) {
        if (_canHideAfterDeleteFailure(e)) {
          await hanakoControlClient.hideDeviceLocally(
            id: device.id,
            rustdeskId: device.rustdeskId,
          );
          onChanged();
          showToast(translate('Device hidden locally'));
          close();
          return;
        }
        setState(() {
          statusMsg = _cleanError(e);
          isInProgress = false;
        });
      }
    }

    return CustomAlertDialog(
      title: Text(translate('Delete device')),
      content: ConstrainedBox(
        constraints: BoxConstraints(minWidth: isDesktop ? 420 : 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(translate('Delete this device from My Devices?')),
            const SizedBox(height: 12),
            _DeviceDeleteLine(
              label: translate('Device alias'),
              value: _deviceLabel(device),
            ),
            _DeviceDeleteLine(
              label: 'RustDesk ID',
              value: device.rustdeskId,
            ),
            _DeviceDeleteLine(
              label: 'Hostname',
              value: device.hostname,
            ),
            const SizedBox(height: 12),
            Text(
              translate('This only removes the saved device entry.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (statusMsg.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  statusMsg,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (isInProgress)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
      actions: [
        dialogButton('Cancel', onPressed: close, isOutline: true),
        dialogButton('Delete device', onPressed: isInProgress ? null : submit),
      ],
      onSubmit: isInProgress ? null : submit,
      onCancel: close,
    );
  });
}

class _DeviceDeleteLine extends StatelessWidget {
  final String label;
  final String value;

  const _DeviceDeleteLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final text = value.trim().isEmpty ? '-' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onPressed;

  const _EmptyState({
    required this.icon,
    required this.text,
    required this.action,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).disabledColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextButton(onPressed: onPressed, child: Text(action)),
        ],
      ),
    );
  }
}

String _deviceLabel(HanakoDevice device) {
  final alias = device.alias?.trim();
  if (alias != null && alias.isNotEmpty) return alias;
  if (device.hostname.isNotEmpty) return device.hostname;
  if (device.rustdeskId.isNotEmpty) return device.rustdeskId;
  return device.id;
}

String _deviceDetail(HanakoDevice device) {
  final parts = <String>[];
  if (device.tags.isNotEmpty) {
    parts.add(device.tags.map((tag) => '#$tag').join(' '));
  }
  final notes = device.notes?.trim();
  if (notes != null && notes.isNotEmpty) {
    parts.add(notes);
  }
  return parts.join('  ');
}

List<String> _parseTags(String value) {
  final tags = <String>{};
  for (final item in value.split(',')) {
    final tag = item.trim();
    if (tag.isNotEmpty) tags.add(tag);
  }
  return tags.toList();
}

IconData _platformIcon(String platform) {
  switch (platform) {
    case 'windows':
      return Icons.desktop_windows_outlined;
    case 'macos':
      return Icons.laptop_mac_outlined;
    case 'linux':
      return Icons.computer_outlined;
    case 'android':
      return Icons.phone_android_outlined;
    case 'ios':
      return Icons.phone_iphone_outlined;
    default:
      return Icons.devices_other_outlined;
  }
}

bool _isRecentlySeen(String? value) {
  final parsed = value == null ? null : DateTime.tryParse(value);
  if (parsed == null) return false;
  return DateTime.now().toUtc().difference(parsed.toUtc()).inSeconds <= 150;
}

String _lastSeenLabel(String? value) {
  final parsed = value == null ? null : DateTime.tryParse(value);
  if (parsed == null) return translate('Never seen');
  final seconds = DateTime.now().toUtc().difference(parsed.toUtc()).inSeconds;
  if (seconds < 90) return translate('Online');
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes ${translate('min ago')}';
  final hours = minutes ~/ 60;
  if (hours < 24) return '$hours ${translate('h ago')}';
  final days = hours ~/ 24;
  return '$days ${translate('d ago')}';
}

String _cleanError(Object error) {
  final message = error.toString().replaceFirst('HanakoControlException: ', '');
  if (message.startsWith('HTTP ')) {
    return '${translate('Request failed')}: $message';
  }
  return translate(message);
}

bool _canHideAfterDeleteFailure(Object error) {
  final message = error.toString();
  return message.contains('HTTP 404') ||
      message.contains('HTTP 405') ||
      message.contains('HTTP 501');
}
