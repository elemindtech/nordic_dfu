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

/// Callback for registering log events
typedef DFULoggerCallback = void Function(String level, String message);

/// Calculates the DFU mode MAC address for Nordic chips.
/// In DFU mode, the MAC address increments the last byte by 1.
/// Example: E4:3B:42:3B:88:7E (normal) -> E4:3B:42:3B:88:7F (DFU)
String _calculateDfuAddress(String normalAddress) {
  try {
    final parts = normalAddress.split(':');
    if (parts.length != 6) return normalAddress;

    final lastByte = int.parse(parts[5], radix: 16);
    final dfuLastByte = (lastByte + 1) & 0xFF;
    parts[5] = dfuLastByte.toRadixString(16).toUpperCase().padLeft(2, '0');

    return parts.join(':');
  } catch (e) {
    debugPrint('[NordicDfu] Error calculating DFU address: $e');
    return normalAddress;
  }
}

/// A singleton class to handle the Nordic DFU process.
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

  static const MethodChannel _methodChannel = MethodChannel(_methodChannelName);
  static const EventChannel _eventChannel = EventChannel(_eventChannelName);
  static const BasicMessageChannel<dynamic> _logChannel = BasicMessageChannel(
    'dev.steenbakker.nordic_dfu/log',
    StandardMessageCodec(),
  );

  static DFULoggerCallback? _dfuLoggerCallback;

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

    debugPrint('[NordicDfu] Event: $key for address: $address');
    debugPrint('[NordicDfu] Available handlers: ${_eventHandlerMap.keys}');

    // CRITICAL FIX: Nordic DFU Android library sometimes reports incorrect address
    // in progress callbacks (off by one in last byte). Try exact match first,
    // then fuzzy match based on first 5 bytes of MAC address.
    var handler = _eventHandlerMap[address];

    if (handler == null && _eventHandlerMap.isNotEmpty) {
      // Try fuzzy match: compare first 5 bytes (first 14 characters) of MAC address
      // Format: XX:XX:XX:XX:XX:YY where we match XX:XX:XX:XX:XX
      final addressPrefix =
          address.length >= 14 ? address.substring(0, 14) : address;

      for (final entry in _eventHandlerMap.entries) {
        final registeredPrefix =
            entry.key.length >= 14 ? entry.key.substring(0, 14) : entry.key;
        if (addressPrefix.toUpperCase() == registeredPrefix.toUpperCase()) {
          debugPrint('[NordicDfu] Using fuzzy match: $address -> ${entry.key}');
          handler = entry.value;
          break;
        }
      }
    }

    if (handler == null) {
      debugPrint('[NordicDfu] WARNING: No handler found for address: $address');
    }
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
    // Register event handler for both normal and DFU mode addresses
    // Nordic chips increment the last byte of MAC address when entering DFU mode
    final handler = DfuEventHandler(
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

    // Register handler for normal address
    _eventHandlerMap[address] = handler;

    // Also register for DFU mode address (last byte + 1)
    final dfuAddress = _calculateDfuAddress(address);
    if (dfuAddress != address) {
      _eventHandlerMap[dfuAddress] = handler;
      debugPrint(
        '[NordicDfu] Registered handler for both $address and $dfuAddress',
      );
    }

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
  Future<void> attachLoggerCallback(DFULoggerCallback callback) {
    _dfuLoggerCallback = callback;
    return _methodChannel.invokeMethod(
      'attachLoggerCallback',
      <String, dynamic>{},
    );
  }

  /// Remove logger
  Future<void> removeLoggerCallback() {
    _dfuLoggerCallback = null;
    return _methodChannel.invokeMethod(
      'removeLoggerCallback',
      <String, dynamic>{},
    );
  }
}
