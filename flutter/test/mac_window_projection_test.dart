import 'package:flutter/material.dart';
import 'package:flutter_hbb/hanako/mac_window_mode.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_test/flutter_test.dart';

Display _display(double x, double y, int width, int height) {
  final display = Display()
    ..x = x
    ..y = y
    ..width = width
    ..height = height;
  // Display intentionally exposes scale only through capture metadata. The
  // test uses a physical-size arrangement so the fallback candidate is enough.
  return display;
}

UniLinkMacWindowInfo _window(double x, double y, double width, double height) {
  return UniLinkMacWindowInfo(
    appName: 'Test',
    title: 'Window',
    pid: 1,
    index: 1,
    x: x,
    y: y,
    width: width,
    height: height,
    visible: true,
  );
}

void main() {
  test('chooses the display containing a window center', () {
    final displays = [
      _display(0, 0, 1920, 1080),
      _display(1920, 0, 1920, 1080),
    ];

    final projection = uniLinkMacWindowDisplayProjection(
        _window(2300, 180, 800, 500), displays);

    expect(projection?.displayIndex, 1);
    expect(projection?.toRemotePixels(_window(2300, 180, 800, 500)),
        const Rect.fromLTWH(2300, 180, 800, 500));
  });

  test(
      'uses the display with the largest overlap when a window crosses screens',
      () {
    final displays = [
      _display(0, 0, 1920, 1080),
      _display(1920, 0, 1920, 1080),
    ];

    final projection = uniLinkMacWindowDisplayProjection(
        _window(1700, 120, 700, 500), displays);

    expect(projection?.displayIndex, 1);
  });
}
