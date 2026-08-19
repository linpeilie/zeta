import 'package:flutter/services.dart';

/// A plugin-neutral method-channel call received from native code.
final class PlatformMethodCall {
  /// Creates a platform method call.
  const PlatformMethodCall(this.method, this.arguments);

  /// Native method name.
  final String method;

  /// Standard-codec arguments.
  final Object? arguments;
}

/// Callback installed on a [PlatformMethodChannelFacade].
typedef PlatformMethodCallHandler = Future<Object?> Function(
  PlatformMethodCall call,
);

/// Injectable subset of Flutter's method-channel API.
abstract interface class PlatformMethodChannelFacade {
  /// Invokes a native method.
  Future<T?> invokeMethod<T>(String method, [Object? arguments]);

  /// Installs or clears the native-to-Dart handler.
  void setMethodCallHandler(PlatformMethodCallHandler? handler);
}

/// Production facade over a Flutter [MethodChannel].
final class FlutterMethodChannelFacade implements PlatformMethodChannelFacade {
  /// Creates a facade around an injected channel.
  FlutterMethodChannelFacade(this._channel);

  final MethodChannel _channel;

  @override
  Future<T?> invokeMethod<T>(String method, [Object? arguments]) =>
      _channel.invokeMethod<T>(method, arguments);

  @override
  void setMethodCallHandler(PlatformMethodCallHandler? handler) {
    _channel.setMethodCallHandler(
      handler == null
          ? null
          : (call) => handler(PlatformMethodCall(call.method, call.arguments)),
    );
  }
}
