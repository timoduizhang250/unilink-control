import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/hanako/control_client.dart';

String hanakoControlEnrollmentStatusLabel() {
  return hanakoControlClient.isEnrolled
      ? translate('Enrolled')
      : translate('Not enrolled');
}

String hanakoControlEnrollmentDescription() {
  if (!hanakoControlClient.isEnrolled) {
    return translate('Enter enrollment token to add this device.');
  }
  final lastHeartbeatAt = hanakoControlClient.lastHeartbeatAt;
  if (lastHeartbeatAt.isEmpty) {
    return translate('Enrolled, waiting for first heartbeat.');
  }
  return '${translate('Last heartbeat')}: ${_formatLocalTime(lastHeartbeatAt)}';
}

Widget hanakoControlEnrollmentBadge(BuildContext context) {
  final enrolled = hanakoControlClient.isEnrolled;
  final color =
      enrolled ? const Color(0xFF0A9471) : Theme.of(context).colorScheme.error;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withOpacity(0.45)),
    ),
    child: Text(
      hanakoControlEnrollmentStatusLabel(),
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// The personal device list is local-first. The former enrollment backend is
/// not required for normal UniLink use, so keep its setup out of the product UI.
void showUniLinkMyDevicesHelpDialog({VoidCallback? onChanged}) {
  gFFI.dialogManager.show((_, close, context) {
    return CustomAlertDialog(
      title: const Text('我的设备'),
      content: const SizedBox(
        width: 420,
        child: Text(
          '这里会自动显示这台电脑的最近连接记录和局域网发现的设备。\n\n'
          '不需要填写 API 服务器、管理员令牌或设备登记令牌。要添加另一台设备，只需在那台设备上打开 UniLink，或通过局域网连接它。',
        ),
      ),
      actions: [dialogButton('确定', onPressed: close)],
      onCancel: close,
    );
  });
}

void showHanakoControlEnrollmentDialog({VoidCallback? onChanged}) {
  final tokenController = TextEditingController();
  final aliasController = TextEditingController();
  final enrolledByController = TextEditingController();
  final adminTokenController = TextEditingController(
    text: hanakoControlClient.adminToken,
  );
  final newEnrollmentTokenLabelController = TextEditingController();
  var generatedEnrollmentToken = '';
  var generatedEnrollmentTokenId = '';
  var tokenMsg = '';
  var statusMsg = '';
  var isInProgress = false;

  gFFI.dialogManager.show((setState, close, context) {
    Future<void> submit() async {
      if (isInProgress) return;
      final token = tokenController.text.trim();
      if (token.isEmpty) {
        setState(() {
          tokenMsg = translate('Enrollment token is required');
        });
        return;
      }

      setState(() {
        tokenMsg = '';
        statusMsg = '';
        isInProgress = true;
      });

      try {
        await hanakoControlClient.setAdminToken(adminTokenController.text);
        final result = await hanakoControlClient.enroll(
          enrollmentToken: token,
          alias: _emptyToNull(aliasController.text),
          enrolledBy: _emptyToNull(enrolledByController.text),
        );
        await hanakoControlClient.heartbeat();
        onChanged?.call();
        showToast(
          '${translate('Enrolled')}: ${_deviceLabel(result.device)}',
        );
        close();
      } catch (e) {
        setState(() {
          statusMsg = _cleanError(e);
          isInProgress = false;
        });
      }
    }

    Future<void> saveSettings() async {
      if (isInProgress) return;
      setState(() {
        statusMsg = '';
        isInProgress = true;
      });
      await hanakoControlClient.setAdminToken(adminTokenController.text);
      onChanged?.call();
      showToast(translate('Successful'));
      close();
    }

    Future<void> generateEnrollmentToken() async {
      if (isInProgress) return;
      setState(() {
        statusMsg = '';
        generatedEnrollmentToken = '';
        generatedEnrollmentTokenId = '';
        isInProgress = true;
      });
      try {
        await hanakoControlClient.setAdminToken(adminTokenController.text);
        final result = await hanakoControlClient.createEnrollmentToken(
          label: _emptyToNull(newEnrollmentTokenLabelController.text),
        );
        setState(() {
          generatedEnrollmentToken = result.token;
          generatedEnrollmentTokenId = result.enrollmentToken.id;
          isInProgress = false;
        });
        onChanged?.call();
        showToast(translate('Successful'));
      } catch (e) {
        setState(() {
          statusMsg = _cleanError(e);
          isInProgress = false;
        });
      }
    }

    Future<void> clearEnrollment() async {
      if (isInProgress) return;
      setState(() {
        statusMsg = '';
        isInProgress = true;
      });
      await hanakoControlClient.clearEnrollment();
      onChanged?.call();
      showToast(translate('UniLink Control enrollment cleared'));
      close();
    }

    final isEnrolled = hanakoControlClient.isEnrolled;
    final deviceId = hanakoControlClient.deviceId;
    return CustomAlertDialog(
      title: Text(translate('UniLink Control')),
      content: ConstrainedBox(
        constraints: BoxConstraints(minWidth: isDesktop ? 420 : 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                hanakoControlEnrollmentBadge(context),
                if (deviceId.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: SelectableText(
                      deviceId,
                      maxLines: 1,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Text(hanakoControlEnrollmentDescription()),
            const SizedBox(height: 16),
            TextField(
              controller: tokenController,
              enabled: !isInProgress,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(
                labelText: translate('Enrollment token'),
                errorText: tokenMsg.isEmpty ? null : tokenMsg,
              ),
            ).workaroundFreezeLinuxMint(),
            const SizedBox(height: 10),
            TextField(
              controller: aliasController,
              enabled: !isInProgress,
              decoration: InputDecoration(
                labelText: translate('Device alias'),
              ),
            ).workaroundFreezeLinuxMint(),
            const SizedBox(height: 10),
            TextField(
              controller: enrolledByController,
              enabled: !isInProgress,
              decoration: InputDecoration(
                labelText: translate('Enrolled by'),
              ),
            ).workaroundFreezeLinuxMint(),
            const SizedBox(height: 10),
            TextField(
              controller: adminTokenController,
              enabled: !isInProgress,
              obscureText: true,
              decoration: InputDecoration(
                labelText: translate('Admin token'),
                helperText: translate('Used to show My Devices.'),
              ),
            ).workaroundFreezeLinuxMint(),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: newEnrollmentTokenLabelController,
                    enabled: !isInProgress,
                    decoration: InputDecoration(
                      labelText: translate('Enrollment token label'),
                    ),
                  ).workaroundFreezeLinuxMint(),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: translate('Generate enrollment token'),
                  child: IconButton(
                    icon: const Icon(Icons.add_link_outlined),
                    onPressed: isInProgress ? null : generateEnrollmentToken,
                  ),
                ),
              ],
            ),
            if (generatedEnrollmentToken.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      generatedEnrollmentToken,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (generatedEnrollmentTokenId.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: SelectableText(
                          generatedEnrollmentTokenId,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
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
        if (isEnrolled)
          dialogButton(
            'Clear',
            onPressed: isInProgress ? null : clearEnrollment,
          ),
        dialogButton('Save', onPressed: isInProgress ? null : saveSettings),
        dialogButton('Enroll', onPressed: isInProgress ? null : submit),
      ],
      onSubmit: isInProgress ? null : submit,
      onCancel: close,
    );
  });
}

String? _emptyToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String _deviceLabel(HanakoDevice device) {
  final alias = device.alias?.trim();
  if (alias != null && alias.isNotEmpty) return alias;
  if (device.hostname.isNotEmpty) return device.hostname;
  if (device.rustdeskId.isNotEmpty) return device.rustdeskId;
  return device.id;
}

String _cleanError(Object error) {
  final message = error.toString().replaceFirst('HanakoControlException: ', '');
  if (message.startsWith('HTTP ')) {
    return '${translate('Request failed')}: $message';
  }
  return translate(message);
}

String _formatLocalTime(String isoValue) {
  final parsed = DateTime.tryParse(isoValue);
  if (parsed == null) return isoValue;
  final local = parsed.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)} '
      '${_two(local.hour)}:${_two(local.minute)}';
}

String _two(int value) => value.toString().padLeft(2, '0');
