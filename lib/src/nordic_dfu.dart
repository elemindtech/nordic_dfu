import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nordic_dfu/src/dfu_event_handler.dart';
import 'package:nordic_dfu/src/parameters/android_parameters.dart';
import 'package:nordic_dfu/src/parameters/android_special_parameter.dart';
import 'package:nordic_dfu/src/parameters/darwin_parameters.dart';
import 'package:nordic_dfu/src/parameters/ios_special_parameter.dart';

/// Callback for when dfu status has changed
/// [address] Device with error
typedef DfuCallback = void Function(String address);

/// Callback for when dfu has error
/// [address] Device with error
/// [error] Error which occurs
/// [errorType] Error type which has occured
/// [message] Message that has been thrown with error
typedef DfuErrorCallback = void Function(
  String address,
  int error,
  int errorType,
  String message,
);

/// Callback for when the dfu progress has changed
/// [address] Device with dfu
/// [percent] Percentage dfu completed
/// [speed] Speed of the dfu proces
/// [avgSpeed] Average speed of the dfu process
/// [currentPart] Current part being uploaded
/// [totalParts] All parts that need to be uploaded
typedef DfuProgressCallback = void Function(
  String address,
  int percent,
  double speed,
  double avgSpeed,
  int currentPart,
  int totalParts,
);

/// Callback for registering log events
typedef DFULoggerCallback = void Function(String level, String message);

/// This singleton handles the DFU process.
class NordicDfu {
  /// Factory for initiating the Singleton
  factory NordicDfu() => _singleton;

  NordicDfu._internal() {
    _logChannel.setMessageHandler((data) async {
      if (data is Map) {
        _dfuLoggerCallback?.call(
          data['level'] as String,
          data['message'] as String,
        );
      }
      return null;
    });
  }

  static final NordicDfu _singleton = NordicDfu._internal();

  static const String _methodChannelName = 'dev.steenbakker.nordic_dfu/method';
  static const String _eventChannelName = 'dev.steenbakker.nordic_dfu/event';
  static const String _logChannelName = 'dev.steenbakker.nordic_dfu/log';

  static const MethodChannel _methodChannel = MethodChannel(_methodChannelName);
  static const EventChannel _eventChannel = EventChannel(_eventChannelName);
  static const _logChannel =
      BasicMessageChannel(_logChannelName, StandardMessageCodec());

  DFULoggerCallback? _dfuLoggerCallback;

  StreamSubscription<void>? _events;
  final Map<String, DfuEventHandler> _eventHandlerMap = {};

  void _ensureEventStreamSetup() {
    if (_events != null) return;

    _events = _eventChannel.receiveBroadcastStream().listen(
          _onEvent,
          onError: _onError,
        );
  }

  void _onEvent(dynamic data) {
    if (data is! Map) {
      debugPrint('Return value is not a map but ${data.runtimeType} $data');
      return;
    }

    final events = Map<String, dynamic>.from(data);
    for (final entry in events.entries) {
      _handleSingleEvent(entry.key, entry.value);
    }
  }

  void _onError(dynamic error) {
    debugPrint('Error in event stream: $error');
  }

  void _handleSingleEvent(String key, dynamic value) {
    if (value == null) {
      debugPrint('Value is null for key: $key');
      return;
    }

    final String address;
    final Map<String, dynamic>? values;

    if (value is Map) {
      address = value['deviceAddress'] as String;
      values = Map<String, dynamic>.from(value);
    } else {
      address = value as String;
      values = null;
    }

    final handler = _eventHandlerMap[address];
    handler?.dispatchEvent(key, values, address);
  }

  /// Starts the DFU process.
  Future<String?> startDfu(
    String address,
    String filePath, {
    String? name,
    bool fileInAsset = false,
    bool forceDfu = false,
    int? numberOfPackets,
    bool enableUnsafeExperimentalButtonlessServiceInSecureDfu = false,
    @Deprecated('Use androidParameters instead')
    AndroidSpecialParameter? androidSpecialParameter,
    @Deprecated('Use darwinParameters instead')
    IosSpecialParameter? iosSpecialParameter,
    AndroidParameters androidParameters = const AndroidParameters(),
    DarwinParameters darwinParameters = const DarwinParameters(),
    DfuEventHandler? dfuEventHandler,
    @Deprecated('Use dfuEventHandler.onDeviceConnected instead')
    DfuCallback? onDeviceConnected,
    @Deprecated('Use dfuEventHandler.onDeviceConnecting instead')
    DfuCallback? onDeviceConnecting,
    @Deprecated('Use dfuEventHandler.onDeviceDisconnected instead')
    DfuCallback? onDeviceDisconnected,
    @Deprecated('Use dfuEventHandler.onDeviceDisconnecting instead')
    DfuCallback? onDeviceDisconnecting,
    @Deprecated('Use dfuEventHandler.onDfuAborted instead')
    DfuCallback? onDfuAborted,
    @Deprecated('Use dfuEventHandler.onDfuCompleted instead')
    DfuCallback? onDfuCompleted,
    @Deprecated('Use dfuEventHandler.onDfuProcessStarted instead')
    DfuCallback? onDfuProcessStarted,
    @Deprecated('Use dfuEventHandler.onDfuProcessStarting instead')
    DfuCallback? onDfuProcessStarting,
    @Deprecated('Use dfuEventHandler.onEnablingDfuMode instead')
    DfuCallback? onEnablingDfuMode,
    @Deprecated('Use dfuEventHandler.onFirmwareValidating instead')
    DfuCallback? onFirmwareValidating,
    @Deprecated('Use dfuEventHandler.onError instead')
    DfuErrorCallback? onError,
    @Deprecated('Use dfuEventHandler.onProgressChanged instead')
    DfuProgressCallback? onProgressChanged,
  }) async {
    _eventHandlerMap[address] = DfuEventHandler(
      onDeviceConnected:
          dfuEventHandler?.onDeviceConnected ?? onDeviceConnected,
      onDeviceConnecting:
          dfuEventHandler?.onDeviceConnecting ?? onDeviceConnecting,
      onDeviceDisconnected:
          dfuEventHandler?.onDeviceDisconnected ?? onDeviceDisconnected,
      onDeviceDisconnecting:
          dfuEventHandler?.onDeviceDisconnecting ?? onDeviceDisconnecting,
      onDfuAborted: dfuEventHandler?.onDfuAborted ?? onDfuAborted,
      onDfuCompleted: dfuEventHandler?.onDfuCompleted ?? onDfuCompleted,
      onDfuProcessStarted:
          dfuEventHandler?.onDfuProcessStarted ?? onDfuProcessStarted,
      onDfuProcessStarting:
          dfuEventHandler?.onDfuProcessStarting ?? onDfuProcessStarting,
      onEnablingDfuMode:
          dfuEventHandler?.onEnablingDfuMode ?? onEnablingDfuMode,
      onFirmwareValidating:
          dfuEventHandler?.onFirmwareValidating ?? onFirmwareValidating,
      onError: dfuEventHandler?.onError ?? onError,
      onProgressChanged:
          dfuEventHandler?.onProgressChanged ?? onProgressChanged,
    );

    // if (dfuEventHandler != null) {
    //   _eventHandlerMap[address] = dfuEventHandler;
    // }

    _ensureEventStreamSetup();

    return _methodChannel.invokeMethod('startDfu', {
      'address': address,
      'filePath': filePath,
      'name': name,
      'fileInAsset': fileInAsset,
      'forceDfu': forceDfu,
      'numberOfPackets': numberOfPackets,
      'enableUnsafeExperimentalButtonlessServiceInSecureDfu':
          enableUnsafeExperimentalButtonlessServiceInSecureDfu,
      ...(androidSpecialParameter?.toJson() ?? androidParameters.toJson()),
      ...(iosSpecialParameter?.toJson() ?? darwinParameters.toJson()),
    });
  }

  /// Aborts the DFU process.
  Future<String?> abortDfu({String? address}) async {
    if (address != null && Platform.isAndroid) {
      debugPrint(
        '[NordicDfu:abortDfu] Warning: aborting all DFU processes on Android',
      );
    }

    return _methodChannel.invokeMethod(
      'abortDfu',
      address != null ? {'address': address} : <String, dynamic>{},
    );
  }

  /// Disposes of the event stream subscription.
  void dispose() {
    _events?.cancel();
    _events = null;
  }

  /// Attach flutter logger
  Future<void> attachLoggerCallback(
    DFULoggerCallback callback,
  ) {
    _dfuLoggerCallback = callback;
    return _methodChannel
        .invokeMethod('attachLoggerCallback', <String, dynamic>{});
  }

  /// Remove logger
  Future<void> removeLoggerCallback() {
    _dfuLoggerCallback = null;
    return _methodChannel
        .invokeMethod('removeLoggerCallback', <String, dynamic>{});
  }
}
