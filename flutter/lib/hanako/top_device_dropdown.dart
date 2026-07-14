import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/hanako/connection_decision.dart';
import 'package:flutter_hbb/hanako/control_client.dart';
import 'package:flutter_hbb/hanako/control_settings.dart';
import 'package:flutter_hbb/hanako/drive_mounter.dart';
import 'package:flutter_hbb/hanako/endpoint_resolver.dart';
import 'package:flutter_hbb/hanako/official_login.dart';
import 'package:flutter_hbb/hanako/public_server.dart';
import 'package:flutter_hbb/hanako/ssh_terminal.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';

class HanakoTopDeviceDropdown extends StatefulWidget {
  const HanakoTopDeviceDropdown({Key? key}) : super(key: key);

  @override
  State<HanakoTopDeviceDropdown> createState() =>
      _HanakoTopDeviceDropdownState();
}

class _HanakoTopDeviceDropdownState extends State<HanakoTopDeviceDropdown> {
  static const _listenerKey = 'HanakoTopDeviceDropdown';
  static const _cbQueryOnlines = 'callback_query_onlines';
  static const _maxOnlineQuery = 20;
  static const _maxVisibleDevices = 30;

  final _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  Timer? _queryOnlineTimer;
  List<Peer> _peers = const [];
  List<HanakoDevice> _hanakoDevices = const [];
  Set<String> _lastOnlineIds = {};
  Set<String> _lastOfflineIds = {};
  bool _isLoadingHanakoDevices = false;
  Object? _hanakoDevicesError;

  @override
  void initState() {
    super.initState();
    gFFI.recentPeersModel.addListener(_mergeLocalPeers);
    gFFI.lanPeersModel.addListener(_mergeLocalPeers);
    gFFI.abModel.addPeerUpdateListener(_listenerKey, _mergeLocalPeers);
    gFFI.groupModel.addPeerUpdateListener(_listenerKey, _mergeLocalPeers);
    platformFFI.registerEventHandler(_cbQueryOnlines, _listenerKey,
        (evt) async {
      _updateOnlineState(evt);
    });
    _refreshAll();
  }

  @override
  void dispose() {
    _hideOverlay();
    _queryOnlineTimer?.cancel();
    gFFI.recentPeersModel.removeListener(_mergeLocalPeers);
    gFFI.lanPeersModel.removeListener(_mergeLocalPeers);
    gFFI.abModel.removePeerUpdateListener(_listenerKey);
    gFFI.groupModel.removePeerUpdateListener(_listenerKey);
    platformFFI.unregisterEventHandler(_cbQueryOnlines, _listenerKey);
    super.dispose();
  }

  void _refreshAll() {
    unawaited(bind.mainLoadRecentPeers());
    unawaited(bind.mainLoadLanPeers());
    _mergeLocalPeers();
    unawaited(_loadHanakoDevices());
  }

  void _mergeLocalPeers() {
    final peers = _mergePeers(
      addressBookPeers: gFFI.abModel.allPeers(),
      groupPeers: gFFI.groupModel.peers,
      lanPeers: gFFI.lanPeersModel.peers,
      recentPeers: gFFI.recentPeersModel.peers,
      restRecentPeerIds: gFFI.recentPeersModel.restPeerIds,
    );
    _updatePeerOnlineStates(
      peers,
      onlines: _lastOnlineIds,
      offlines: _lastOfflineIds,
    );
    _updateUi(() {
      _peers = peers;
    });
    _queryOnlines(peers);
  }

  Future<void> _loadHanakoDevices() async {
    if (!hanakoControlClient.canListDevices) {
      _updateUi(() {
        _hanakoDevices = const [];
        _hanakoDevicesError = null;
        _isLoadingHanakoDevices = false;
      });
      return;
    }
    _updateUi(() {
      _isLoadingHanakoDevices = true;
      _hanakoDevicesError = null;
    });
    try {
      final devices = await hanakoControlClient.listDevices();
      _updateUi(() {
        _hanakoDevices = devices;
        _isLoadingHanakoDevices = false;
      });
    } catch (e) {
      _updateUi(() {
        _hanakoDevicesError = e;
        _isLoadingHanakoDevices = false;
      });
    }
  }

  void _queryOnlines(Iterable<Peer> peers) {
    final ids = <String>[];
    final seen = <String>{};
    for (final peer in peers) {
      if (peer.id.isEmpty || seen.contains(peer.id)) continue;
      seen.add(peer.id);
      ids.add(peer.id);
      if (ids.length >= _maxOnlineQuery) break;
    }
    _queryOnlineTimer?.cancel();
    if (ids.isEmpty) return;
    _queryOnlineTimer = Timer(const Duration(milliseconds: 250), () async {
      try {
        await bind.queryOnlines(ids: ids);
      } catch (e) {
        debugPrint('UniLink top devices online query failed: $e');
      }
    });
  }

  void _updateOnlineState(Map<String, dynamic> evt) {
    _lastOnlineIds = _splitPeerIds(evt['onlines']);
    _lastOfflineIds = _splitPeerIds(evt['offlines']);
    final peers = _peers.map(Peer.copy).toList(growable: false);
    final changed = _updatePeerOnlineStates(
      peers,
      onlines: _lastOnlineIds,
      offlines: _lastOfflineIds,
    );
    if (changed) {
      _updateUi(() {
        _peers = peers;
      });
    }
  }

  Set<String> _splitPeerIds(dynamic ids) {
    if (ids is! String || ids.isEmpty) return {};
    return ids.split(',').where((id) => id.isNotEmpty).toSet();
  }

  List<_TopDeviceEntry> _deviceEntries() {
    final entries = <String, _TopDeviceEntry>{};
    for (final device in _hanakoDevices) {
      final id = device.rustdeskId.trim();
      if (id.isEmpty) continue;
      entries[id] = _TopDeviceEntry.fromHanakoDevice(device);
    }
    for (final peer in _peers) {
      final id = peer.id.trim();
      if (id.isEmpty) continue;
      final peerEntry = _TopDeviceEntry.fromPeer(peer);
      final current = entries[id];
      entries[id] = current == null ? peerEntry : current.merge(peerEntry);
    }
    final devices = entries.values.toList(growable: false);
    devices.sort(_compareDeviceEntry);
    return devices.take(_maxVisibleDevices).toList(growable: false);
  }

  int _compareDeviceEntry(_TopDeviceEntry a, _TopDeviceEntry b) {
    final sourceOrder = a.source.index.compareTo(b.source.index);
    if (sourceOrder != 0) return sourceOrder;
    if (a.online != b.online) return a.online ? -1 : 1;
    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  }

  void _updateUi(VoidCallback callback) {
    if (!mounted) return;
    setState(callback);
    _overlayEntry?.markNeedsBuild();
  }

  void _toggleOverlay() {
    if (_overlayEntry == null) {
      _showOverlay();
      _refreshAll();
    } else {
      _hideOverlay();
    }
  }

  void _showOverlay() {
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(builder: (context) {
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _hideOverlay,
              child: const SizedBox.expand(),
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 4),
            child: _TopDevicePopup(
              devices: _deviceEntries(),
              isLoading: _isLoadingHanakoDevices,
              error: _hanakoDevicesError,
              canListHanakoDevices: hanakoControlClient.canListDevices,
              onRefresh: _refreshAll,
              onSettings: _openSettings,
              onConnect: _connect,
              onConnectPublic: _connectPublic,
              onBeforeSsh: _hideOverlay,
              onMountDrive: _openDrive,
              onDeleteDevice: _deleteDevice,
            ),
          ),
        ],
      );
    });
    overlay.insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _openSettings() {
    _hideOverlay();
    showUniLinkMyDevicesHelpDialog(onChanged: _refreshAll);
  }

  void _connect(_TopDeviceEntry device) {
    _hideOverlay();
    showUniLinkConnectionDecision(
      target: device.toEndpointTarget(),
      onRemoteControl: () => uniLinkConnect(context, device.id),
      onLocalRemoteControl: (host) => uniLinkConnect(context, host),
      onPublicRemoteControl: uniLinkCanUsePublicServer(device.id)
          ? () => uniLinkConnect(context, uniLinkPublicPeerId(device.id))
          : null,
    );
  }

  void _connectPublic(String id) {
    _hideOverlay();
    uniLinkConnect(context, uniLinkPublicPeerId(id));
  }

  void _openDrive(_TopDeviceEntry device) {
    _hideOverlay();
    showUniLinkDriveDialog(
      target: UniLinkDriveTarget(
        peerId: device.id,
        label: device.label,
        platform: device.platform,
        hostname: device.hostname,
        username: device.username,
        lanAddresses: device.lanAddresses,
      ),
    );
  }

  void _deleteDevice(_TopDeviceEntry device) {
    _hideOverlay();
    _showDeleteDeviceDialog(device: device, onChanged: _refreshAll);
  }

  @override
  Widget build(BuildContext context) {
    final devices = _deviceEntries();
    return CompositedTransformTarget(
      link: _layerLink,
      child: Tooltip(
        message: translate('Devices'),
        waitDuration: const Duration(seconds: 1),
        child: InkWell(
          hoverColor: MyTheme.tabbar(context).hoverColor,
          onTap: _toggleOverlay,
          child: SizedBox(
            height: kDesktopRemoteTabBarHeight - 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.devices_other_outlined,
                    size: 15,
                    color: MyTheme.tabbar(context).unSelectedIconColor,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    translate('Devices'),
                    style: TextStyle(
                      fontSize: 12,
                      color: MyTheme.tabbar(context).unSelectedIconColor,
                    ),
                  ),
                  if (devices.isNotEmpty) ...[
                    const SizedBox(width: 5),
                    Text(
                      devices.length.toString(),
                      style: TextStyle(
                        fontSize: 11,
                        color: MyTheme.tabbar(context)
                            .unSelectedIconColor
                            ?.withOpacity(0.72),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

List<Peer> _mergePeers({
  Iterable<Peer> addressBookPeers = const [],
  Iterable<Peer> groupPeers = const [],
  Iterable<Peer> lanPeers = const [],
  Iterable<Peer> recentPeers = const [],
  Iterable<String> restRecentPeerIds = const [],
}) {
  final combinedPeers = <String, Peer>{};

  void addPeer(Peer peer) {
    if (peer.id.isEmpty) return;
    final existingPeer = combinedPeers[peer.id];
    if (existingPeer == null) {
      combinedPeers[peer.id] = Peer.copy(peer);
    } else if (peer.online) {
      existingPeer.online = true;
    }
  }

  for (final peer in addressBookPeers) {
    addPeer(peer);
  }
  for (final peer in groupPeers) {
    addPeer(peer);
  }
  for (final peer in lanPeers) {
    addPeer(peer);
  }
  for (final peer in recentPeers) {
    addPeer(peer);
  }
  for (final id in restRecentPeerIds) {
    if (id.isNotEmpty && !combinedPeers.containsKey(id)) {
      combinedPeers[id] = Peer.fromJson({'id': id});
    }
  }

  return combinedPeers.values.toList(growable: false);
}

bool _updatePeerOnlineStates(
  List<Peer> peers, {
  required Set<String> onlines,
  required Set<String> offlines,
}) {
  var changed = false;
  for (final peer in peers) {
    if (onlines.contains(peer.id)) {
      if (!peer.online) {
        peer.online = true;
        changed = true;
      }
    } else if (offlines.contains(peer.id)) {
      if (peer.online) {
        peer.online = false;
        changed = true;
      }
    }
  }
  return changed;
}

class _TopDevicePopup extends StatelessWidget {
  final List<_TopDeviceEntry> devices;
  final bool isLoading;
  final Object? error;
  final bool canListHanakoDevices;
  final VoidCallback onRefresh;
  final VoidCallback onSettings;
  final ValueChanged<_TopDeviceEntry> onConnect;
  final ValueChanged<String> onConnectPublic;
  final VoidCallback onBeforeSsh;
  final ValueChanged<_TopDeviceEntry> onMountDrive;
  final ValueChanged<_TopDeviceEntry> onDeleteDevice;

  const _TopDevicePopup({
    required this.devices,
    required this.isLoading,
    required this.error,
    required this.canListHanakoDevices,
    required this.onRefresh,
    required this.onSettings,
    required this.onConnect,
    required this.onConnectPublic,
    required this.onBeforeSsh,
    required this.onMountDrive,
    required this.onDeleteDevice,
  });

  @override
  Widget build(BuildContext context) {
    final showError = devices.isEmpty && error != null && canListHanakoDevices;
    return Material(
      color: Theme.of(context).cardColor,
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 320,
          maxWidth: 420,
          maxHeight: 420,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 42,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(
                    Icons.devices_other_outlined,
                    size: 18,
                    color: MyTheme.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      translate('Devices'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
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
            ),
            if (isLoading) const LinearProgressIndicator(minHeight: 2),
            const Divider(height: 1),
            if (showError)
              _TopDeviceEmpty(
                icon: Icons.error_outline,
                text: _cleanError(error!),
              )
            else if (devices.isEmpty)
              _TopDeviceEmpty(
                icon: Icons.devices_other_outlined,
                text: translate('No devices yet.'),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 334),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: devices.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    return _TopDeviceRow(
                      device: device,
                      onConnect: () => onConnect(device),
                      onConnectPublic: uniLinkCanUsePublicServer(device.id)
                          ? () => onConnectPublic(device.id)
                          : null,
                      onBeforeSsh: onBeforeSsh,
                      onMountDrive: () => onMountDrive(device),
                      onDeleteDevice: device.canDelete
                          ? () => onDeleteDevice(device)
                          : null,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TopDeviceRow extends StatelessWidget {
  final _TopDeviceEntry device;
  final VoidCallback onConnect;
  final VoidCallback? onConnectPublic;
  final VoidCallback onBeforeSsh;
  final VoidCallback onMountDrive;
  final VoidCallback? onDeleteDevice;

  const _TopDeviceRow({
    required this.device,
    required this.onConnect,
    required this.onConnectPublic,
    required this.onBeforeSsh,
    required this.onMountDrive,
    required this.onDeleteDevice,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = device.online
        ? const Color(0xFF0A9471)
        : Theme.of(context).disabledColor;
    final secondaryStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color:
              Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.68),
        );
    return InkWell(
      onTap: onConnect,
      child: SizedBox(
        height: 62,
        child: Padding(
          padding: const EdgeInsets.only(left: 12, right: 6),
          child: Row(
            children: [
              Icon(_platformIcon(device.platform), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            device.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        Text(
                          translate(device.source.label),
                          style: secondaryStyle,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      device.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: secondaryStyle,
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: translate('Connect'),
                child: IconButton(
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  onPressed: onConnect,
                ),
              ),
              Tooltip(
                message: translate('Connect via public server'),
                child: IconButton(
                  icon: const Icon(Icons.public, size: 19),
                  onPressed: onConnectPublic,
                ),
              ),
              UniLinkSshActionButton(
                target: device.toEndpointTarget(),
                iconSize: 20,
                beforeOpen: onBeforeSsh,
              ),
              Tooltip(
                message: translate('Mount drive'),
                child: IconButton(
                  icon: const Icon(Icons.storage_outlined, size: 20),
                  onPressed: onMountDrive,
                ),
              ),
              if (onConnectPublic != null || onDeleteDevice != null)
                PopupMenuButton<String>(
                  tooltip: translate('More'),
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (value) {
                    if (value == 'public') {
                      onConnectPublic?.call();
                    } else if (value == 'delete') {
                      onDeleteDevice?.call();
                    }
                  },
                  itemBuilder: (context) => [
                    if (onConnectPublic != null)
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
                    if (onDeleteDevice != null)
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
        ),
      ),
    );
  }
}

void _showDeleteDeviceDialog({
  required _TopDeviceEntry device,
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
        await hanakoControlClient.deleteDevice(id: device.registryId);
        onChanged();
        showToast(translate('Device deleted'));
        close();
      } catch (e) {
        if (_canHideAfterDeleteFailure(e)) {
          await hanakoControlClient.hideDeviceLocally(
            id: device.registryId,
            rustdeskId: device.id,
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
            _TopDeviceDeleteLine(
              label: translate('Device alias'),
              value: device.label,
            ),
            _TopDeviceDeleteLine(
              label: 'RustDesk ID',
              value: device.id,
            ),
            _TopDeviceDeleteLine(
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

class _TopDeviceDeleteLine extends StatelessWidget {
  final String label;
  final String value;

  const _TopDeviceDeleteLine({
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

class _TopDeviceEmpty extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TopDeviceEmpty({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
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
        ],
      ),
    );
  }
}

enum _TopDeviceSource {
  added('Added'),
  recent('Recent');

  final String label;

  const _TopDeviceSource(this.label);
}

class _TopDeviceEntry {
  final String registryId;
  final String id;
  final String label;
  final String detail;
  final String platform;
  final String hostname;
  final String username;
  final List<String> lanAddresses;
  final bool online;
  final _TopDeviceSource source;

  const _TopDeviceEntry({
    required this.registryId,
    required this.id,
    required this.label,
    required this.detail,
    required this.platform,
    required this.hostname,
    required this.username,
    required this.lanAddresses,
    required this.online,
    required this.source,
  });

  factory _TopDeviceEntry.fromHanakoDevice(HanakoDevice device) {
    final label = _firstNotEmpty([
      device.alias,
      device.hostname,
      device.rustdeskId,
      device.id,
    ]);
    final details = <String>[device.rustdeskId];
    if (device.hostname.isNotEmpty && device.hostname != label) {
      details.add(device.hostname);
    }
    if (device.lanAddresses.isNotEmpty) {
      details.add(device.lanAddresses.take(2).join(', '));
    }
    return _TopDeviceEntry(
      registryId: device.id,
      id: device.rustdeskId.trim(),
      label: label,
      detail: details.where((part) => part.trim().isNotEmpty).join('  '),
      platform: device.platform,
      hostname: device.hostname,
      username: '',
      lanAddresses: device.lanAddresses,
      online: _isRecentlySeen(device.lastSeenAt),
      source: _TopDeviceSource.added,
    );
  }

  factory _TopDeviceEntry.fromPeer(Peer peer) {
    final label = _firstNotEmpty([
      peer.alias,
      peer.hostname,
      peer.username,
      peer.id,
    ]);
    final details = <String>[];
    if (peer.id != label) details.add(peer.id);
    final userHost = _userHost(peer);
    if (userHost.isNotEmpty && userHost != label) details.add(userHost);
    if (peer.note.isNotEmpty) details.add(peer.note);
    return _TopDeviceEntry(
      registryId: '',
      id: peer.id.trim(),
      label: label,
      detail: details.isEmpty ? peer.id : details.join('  '),
      platform: peer.platform,
      hostname: peer.hostname,
      username: peer.username,
      lanAddresses: const [],
      online: peer.online,
      source: _TopDeviceSource.recent,
    );
  }

  _TopDeviceEntry merge(_TopDeviceEntry peerEntry) {
    return _TopDeviceEntry(
      registryId: registryId.isNotEmpty ? registryId : peerEntry.registryId,
      id: id,
      label: label.isNotEmpty ? label : peerEntry.label,
      detail: detail.isNotEmpty ? detail : peerEntry.detail,
      platform: platform.isNotEmpty ? platform : peerEntry.platform,
      hostname: hostname.isNotEmpty ? hostname : peerEntry.hostname,
      username: username.isNotEmpty ? username : peerEntry.username,
      lanAddresses:
          lanAddresses.isNotEmpty ? lanAddresses : peerEntry.lanAddresses,
      online: online || peerEntry.online,
      source: source,
    );
  }

  bool get canDelete =>
      source == _TopDeviceSource.added && registryId.trim().isNotEmpty;

  UniLinkEndpointTarget toEndpointTarget() {
    return UniLinkEndpointTarget(
      peerId: id,
      label: label,
      platform: platform,
      hostname: hostname,
      username: username,
      lanAddresses: lanAddresses,
      online: online,
    );
  }
}

String _firstNotEmpty(Iterable<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
  }
  return '';
}

String _userHost(Peer peer) {
  final username = peer.username.trim();
  final hostname = peer.hostname.trim();
  if (username.isNotEmpty && hostname.isNotEmpty) {
    return '$username@$hostname';
  }
  return username.isNotEmpty ? username : hostname;
}

IconData _platformIcon(String platform) {
  switch (platform) {
    case 'windows':
      return Icons.desktop_windows_outlined;
    case 'macos':
    case 'mac':
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
