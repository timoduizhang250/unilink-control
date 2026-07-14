import 'dart:async';

import 'package:auto_size_text_field/auto_size_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/common/widgets/connection_page_title.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/hanako/android_updater.dart';
import 'package:flutter_hbb/hanako/official_login.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_hbb/models/peer_model.dart';

import '../../common.dart';
import '../../common/widgets/peer_tab_page.dart';
import '../../common/widgets/autocomplete.dart';
import '../../consts.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import 'home_page.dart';

/// Connection page for connecting to a remote peer.
class ConnectionPage extends StatefulWidget implements PageShape {
  ConnectionPage({Key? key, required this.appBarActions}) : super(key: key);

  @override
  final icon = const Icon(Icons.connected_tv);

  @override
  final title = translate("Connection");

  @override
  final List<Widget> appBarActions;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

/// State for the connection page.
class _ConnectionPageState extends State<ConnectionPage> {
  /// Controller for the id input bar.
  final _idController = IDTextEditingController();
  final RxBool _idEmpty = true.obs;

  final FocusNode _idFocusNode = FocusNode();
  final TextEditingController _idEditingController = TextEditingController();

  final AllPeersLoader _allPeersLoader = AllPeersLoader();

  StreamSubscription? _uniLinksSubscription;

  // https://github.com/flutter/flutter/issues/157244
  Iterable<Peer> _autocompleteOpts = [];
  bool _updateInProgress = false;
  double? _updateProgress;

  _ConnectionPageState() {
    if (!isWeb) _uniLinksSubscription = listenUniLinks();
    _idController.addListener(() {
      _idEmpty.value = _idController.text.isEmpty;
    });
    Get.put<IDTextEditingController>(_idController);
  }

  @override
  void initState() {
    super.initState();
    _allPeersLoader.init(setState);
    _idFocusNode.addListener(onFocusChanged);
    if (_idController.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final lastRemoteId = await bind.mainGetLastRemoteId();
        if (lastRemoteId != _idController.id) {
          setState(() {
            _idController.id = lastRemoteId;
          });
        }
      });
    }
    Get.put<TextEditingController>(_idEditingController);
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<FfiModel>(context);
    return CustomScrollView(
      slivers: [
        SliverList(
            delegate: SliverChildListDelegate([
          if ((!bind.isCustomClient() ||
                  bind
                      .mainGetAppNameSync()
                      .toLowerCase()
                      .contains('unilink')) &&
              !isIOS)
            Obx(() => _buildUpdateUI(stateGlobal.updateUrl.value)),
          _buildRemoteIDTextField(),
          _buildLanConnectionEntry(),
        ])),
        SliverFillRemaining(
          hasScrollBody: true,
          child: PeerTabPage(),
        )
      ],
    ).marginOnly(top: 2, left: 10, right: 10);
  }

  /// Callback for the connect button.
  /// Connects to the selected peer.
  void onConnect() {
    var id = _idController.id;
    uniLinkConnect(context, id);
  }

  Widget _buildLanConnectionEntry() {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        constraints: kMobilePageConstraints,
        padding: const EdgeInsets.only(top: 2, bottom: 8),
        child: TextButton.icon(
          onPressed: _showLanConnectionDialog,
          icon: const Icon(Icons.lan_outlined),
          label: const Text('\u5c40\u57df\u7f51\u8fde\u63a5'),
        ),
      ),
    );
  }

  void _showLanConnectionDialog() {
    final hostController = TextEditingController();
    final usernameController = TextEditingController();
    final portController = TextEditingController(text: '3389');
    var isLaunching = false;
    var useMacScreenSharing = false;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('\u8fde\u63a5\u5c40\u57df\u7f51\u8bbe\u5907'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<bool>(
                  value: useMacScreenSharing,
                  decoration: const InputDecoration(
                      labelText: '\u8bbe\u5907\u7c7b\u578b'),
                  items: const [
                    DropdownMenuItem(
                        value: false,
                        child: Text('Windows \u8fdc\u7a0b\u684c\u9762 (RDP)')),
                    DropdownMenuItem(
                        value: true,
                        child: Text('Mac \u5c4f\u5e55\u5171\u4eab (VNC)')),
                  ],
                  onChanged: isLaunching
                      ? null
                      : (value) {
                          setDialogState(() {
                            useMacScreenSharing = value ?? false;
                            portController.text =
                                useMacScreenSharing ? '5900' : '3389';
                          });
                        },
                ),
                const SizedBox(height: 10),
                Text(
                  useMacScreenSharing
                      ? '\u76ee\u6807 Mac \u5fc5\u987b\u5df2\u5728\u7cfb\u7edf\u8bbe\u7f6e\u4e2d\u5f00\u542f\u5c4f\u5e55\u5171\u4eab\u3002\u5bc6\u7801\u4f1a\u5728 VNC \u5ba2\u6237\u7aef\u5185\u8f93\u5165\u3002'
                      : '\u76ee\u6807 Windows \u5fc5\u987b\u5df2\u5f00\u542f\u8fdc\u7a0b\u684c\u9762\u3002Windows \u5bb6\u5ead\u7248\u4e0d\u652f\u6301\u4f5c\u4e3a RDP \u88ab\u63a7\u7aef\uff0c\u8bf7\u6539\u7528 UniLink Quick Support\u3002',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: hostController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '\u7535\u8111 IP \u5730\u5740\u6216\u540d\u79f0',
                    hintText: '\u4f8b\u5982 192.168.1.20',
                  ),
                  keyboardType: TextInputType.url,
                ),
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Windows \u7528\u6237\u540d',
                    hintText: '\u4f8b\u5982 WORKGROUP\\name',
                  ),
                ),
                TextField(
                  controller: portController,
                  decoration: const InputDecoration(
                      labelText: '\u8fde\u63a5\u7aef\u53e3'),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  isLaunching ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('\u53d6\u6d88'),
            ),
            ElevatedButton(
              onPressed: isLaunching
                  ? null
                  : () async {
                      final host = hostController.text.trim();
                      final port = int.tryParse(portController.text.trim());
                      if (host.isEmpty ||
                          host.contains(RegExp(r'\s')) ||
                          port == null ||
                          port < 1 ||
                          port > 65535) {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  '\u8bf7\u586b\u5199\u6b63\u786e\u7684\u7535\u8111\u5730\u5740\u548c\u7aef\u53e3\u3002')),
                        );
                        return;
                      }
                      if (!isAndroid) {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  '\u6b64\u5165\u53e3\u76ee\u524d\u9700\u8981 Android \u7248 UniLink\u3002')),
                        );
                        return;
                      }
                      setDialogState(() => isLaunching = true);
                      final opened = await gFFI.invokeMethod(
                        useMacScreenSharing
                            ? AndroidChannel.kOpenVncClient
                            : AndroidChannel.kOpenRdpClient,
                        {
                          'host': host,
                          'port': port,
                          'username': usernameController.text.trim(),
                        },
                      );
                      if (!mounted) return;
                      if (opened == true) {
                        Navigator.of(dialogContext).pop();
                      } else {
                        setDialogState(() => isLaunching = false);
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                '\u672a\u627e\u5230\u53ef\u7528\u5ba2\u6237\u7aef\u3002\u8bf7\u5148\u5b89\u88c5\u652f\u6301 RDP \u6216 VNC \u7684\u8fdc\u7a0b\u684c\u9762\u5ba2\u6237\u7aef\u3002'),
                          ),
                        );
                      }
                    },
              child: isLaunching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('\u6253\u5f00\u5ba2\u6237\u7aef'),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      hostController.dispose();
      usernameController.dispose();
      portController.dispose();
    });
  }

  void onFocusChanged() {
    _idEmpty.value = _idEditingController.text.isEmpty;
    if (_idFocusNode.hasFocus) {
      if (_allPeersLoader.needLoad) {
        _allPeersLoader.getAllPeers();
      }

      final textLength = _idEditingController.value.text.length;
      // Select all to facilitate removing text, just following the behavior of address input of chrome.
      _idEditingController.selection =
          TextSelection(baseOffset: 0, extentOffset: textLength);
    }
  }

  /// UI for software update.
  /// If _updateUrl] is not empty, shows a button to update the software.
  Widget _buildUpdateUI(String updateUrl) {
    return updateUrl.isEmpty
        ? const SizedBox(height: 0)
        : InkWell(
            onTap: () async {
              if (_updateInProgress) return;
              if (!isAndroid || stateGlobal.updateDownloadUrl.value.isEmpty) {
                await launchUrl(Uri.parse(updateUrl));
                return;
              }
              setState(() {
                _updateInProgress = true;
                _updateProgress = null;
              });
              try {
                final result = await UniLinkAndroidUpdater.downloadAndInstall(
                  downloadUrl: stateGlobal.updateDownloadUrl.value,
                  expectedSha256: stateGlobal.updateSha256.value,
                  onProgress: (progress) {
                    if (!mounted) return;
                    setState(() => _updateProgress = progress);
                  },
                );
                if (result.permissionRequired) {
                  showToast('请允许 UniLink 安装更新，返回后会自动打开安装界面');
                } else if (!result.installerLaunched) {
                  showToast('无法打开系统安装界面');
                }
              } catch (e) {
                showToast(e.toString().replaceFirst('FormatException: ', ''));
              } finally {
                if (mounted) {
                  setState(() {
                    _updateInProgress = false;
                    _updateProgress = null;
                  });
                }
              }
            },
            child: Container(
                alignment: AlignmentDirectional.center,
                width: double.infinity,
                color: Colors.pinkAccent,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                    _updateInProgress
                        ? _updateProgress == null
                            ? '正在下载更新…'
                            : '正在下载 ${(_updateProgress! * 100).round()}%'
                        : '下载并安装新版本',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold))));
  }

  /// UI for the remote ID TextField.
  /// Search for a peer and connect to it if the id exists.
  Widget _buildRemoteIDTextField() {
    final w = SizedBox(
      height: 84,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Ink(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.all(Radius.circular(13)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Container(
                  padding: const EdgeInsets.only(left: 16, right: 16),
                  child: RawAutocomplete<Peer>(
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text == '') {
                        _autocompleteOpts = const Iterable<Peer>.empty();
                      } else if (_allPeersLoader.peers.isEmpty &&
                          !_allPeersLoader.isPeersLoaded) {
                        Peer emptyPeer = Peer(
                          id: '',
                          username: '',
                          hostname: '',
                          alias: '',
                          platform: '',
                          tags: [],
                          hash: '',
                          password: '',
                          forceAlwaysRelay: false,
                          rdpPort: '',
                          rdpUsername: '',
                          loginName: '',
                          device_group_name: '',
                          note: '',
                        );
                        _autocompleteOpts = [emptyPeer];
                      } else {
                        String textWithoutSpaces =
                            textEditingValue.text.replaceAll(" ", "");
                        if (int.tryParse(textWithoutSpaces) != null) {
                          textEditingValue = TextEditingValue(
                            text: textWithoutSpaces,
                            selection: textEditingValue.selection,
                          );
                        }
                        String textToFind = textEditingValue.text.toLowerCase();

                        _autocompleteOpts = _allPeersLoader.peers
                            .where((peer) =>
                                peer.id.toLowerCase().contains(textToFind) ||
                                peer.username
                                    .toLowerCase()
                                    .contains(textToFind) ||
                                peer.hostname
                                    .toLowerCase()
                                    .contains(textToFind) ||
                                peer.alias.toLowerCase().contains(textToFind))
                            .toList();
                        _allPeersLoader.queryOnlines(_autocompleteOpts);
                      }
                      return _autocompleteOpts;
                    },
                    focusNode: _idFocusNode,
                    textEditingController: _idEditingController,
                    fieldViewBuilder: (BuildContext context,
                        TextEditingController fieldTextEditingController,
                        FocusNode fieldFocusNode,
                        VoidCallback onFieldSubmitted) {
                      updateTextAndPreserveSelection(
                          fieldTextEditingController, _idController.text);
                      return AutoSizeTextField(
                        controller: fieldTextEditingController,
                        focusNode: fieldFocusNode,
                        minFontSize: 18,
                        autocorrect: false,
                        enableSuggestions: false,
                        keyboardType: TextInputType.visiblePassword,
                        // keyboardType: TextInputType.number,
                        onChanged: (String text) {
                          _idController.id = text;
                        },
                        style: const TextStyle(
                          fontFamily: 'WorkSans',
                          fontWeight: FontWeight.bold,
                          fontSize: 30,
                          color: MyTheme.idColor,
                        ),
                        decoration: InputDecoration(
                          labelText: translate('Remote ID'),
                          // hintText: 'Enter your remote ID',
                          border: InputBorder.none,
                          helperStyle: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: MyTheme.darkGray,
                          ),
                          labelStyle: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            letterSpacing: 0.2,
                            color: MyTheme.darkGray,
                          ),
                        ),
                        inputFormatters: [IDTextInputFormatter()],
                        onSubmitted: (_) {
                          onConnect();
                        },
                      );
                    },
                    onSelected: (option) {
                      setState(() {
                        _idController.id = option.id;
                        FocusScope.of(context).unfocus();
                      });
                    },
                    optionsViewBuilder: (BuildContext context,
                        AutocompleteOnSelected<Peer> onSelected,
                        Iterable<Peer> options) {
                      options = _autocompleteOpts;
                      double maxHeight = options.length * 50;
                      if (options.length == 1) {
                        maxHeight = 52;
                      } else if (options.length == 3) {
                        maxHeight = 146;
                      } else if (options.length == 4) {
                        maxHeight = 193;
                      }
                      maxHeight = maxHeight.clamp(0, 200);
                      return Align(
                          alignment: Alignment.topLeft,
                          child: Container(
                              decoration: BoxDecoration(
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 5,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                  borderRadius: BorderRadius.circular(5),
                                  child: Material(
                                      elevation: 4,
                                      child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxHeight: maxHeight,
                                            maxWidth: 320,
                                          ),
                                          child: _allPeersLoader
                                                      .peers.isEmpty &&
                                                  !_allPeersLoader.isPeersLoaded
                                              ? Container(
                                                  height: 80,
                                                  child: Center(
                                                      child:
                                                          CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  )))
                                              : ListView(
                                                  padding:
                                                      EdgeInsets.only(top: 5),
                                                  children: options
                                                      .map((peer) =>
                                                          AutocompletePeerTile(
                                                              onSelect: () =>
                                                                  onSelected(
                                                                      peer),
                                                              peer: peer))
                                                      .toList(),
                                                ))))));
                    },
                  ),
                ),
              ),
              Obx(() => Offstage(
                    offstage: _idEmpty.value,
                    child: IconButton(
                        onPressed: () {
                          setState(() {
                            _idController.clear();
                          });
                        },
                        icon: Icon(Icons.clear, color: MyTheme.darkGray)),
                  )),
              SizedBox(
                width: 60,
                height: 60,
                child: IconButton(
                  icon: const Icon(Icons.arrow_forward,
                      color: MyTheme.darkGray, size: 45),
                  onPressed: onConnect,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final child = Column(children: [
      if (isWebDesktop)
        getConnectionPageTitle(context, true)
            .marginOnly(bottom: 10, top: 15, left: 12),
      w
    ]);
    return Align(
        alignment: Alignment.topCenter,
        child: Container(constraints: kMobilePageConstraints, child: child));
  }

  @override
  void dispose() {
    _uniLinksSubscription?.cancel();
    _idController.dispose();
    _idFocusNode.removeListener(onFocusChanged);
    _allPeersLoader.clear();
    _idFocusNode.dispose();
    _idEditingController.dispose();
    if (Get.isRegistered<IDTextEditingController>()) {
      Get.delete<IDTextEditingController>();
    }
    if (Get.isRegistered<TextEditingController>()) {
      Get.delete<TextEditingController>();
    }
    super.dispose();
  }
}
