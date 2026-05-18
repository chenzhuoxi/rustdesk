/// Foldable device detection and state management utilities.
///
/// Provides detection for foldable devices (e.g., Pixel Fold) and
/// exposes the current fold state so that the UI can adaptively
/// switch between cover-screen and inner-screen layouts.
///
/// Pixel Fold reference dimensions:
///   - Cover screen:  1080 x 2092 px  (slender phone ratio)
///   - Inner screen:  2208 x 1840 px  (~6:5, near-square)
///
/// Behavior:
///   - Detects fold state via Android's Jetpack WindowManager
///   - Provides `MediaQuery`-based fallback for non-foldable devices
///   - Exposes screen size tiers: phone / foldable-inner / tablet

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Foldable screen posture values.
enum FoldPosture {
  /// Device is folded (cover screen active).
  folded,

  /// Device is fully unfolded (inner screen active).
  unfolded,

  /// Device is in a half-opened state (e.g., tabletop mode).
  halfOpened,

  /// Unknown / not a foldable device.
  unknown,
}

/// Screen size classification for layout adaptation.
enum ScreenSizeTier {
  /// Standard phone (< 600dp shortest side)
  phone,

  /// Pixel Fold inner screen or small tablet (600-840dp)
  foldable,

  /// Full-size tablet (> 840dp)
  tablet,
}

/// Pixel Fold inner screen dimensions for reference.
class PixelFoldSpec {
  /// Inner screen logical dimensions (portrait).
  static const Size innerScreenPortrait = Size(1840, 2208);

  /// Inner screen logical dimensions (landscape).
  static const Size innerScreenLandscape = Size(2208, 1840);

  /// Cover screen logical dimensions (portrait).
  static const Size coverScreenPortrait = Size(1080, 2092);

  /// Inner screen aspect ratio (width/height in landscape, ~1.2).
  static const double innerAspectRatio = 2208 / 1840;
}

/// Singleton manager for foldable device state.
///
/// Usage:
/// ```dart
/// final foldable = FoldableHelper.instance;
/// await foldable.init();
/// print(foldable.isFoldable);
/// print(foldable.foldPosture);
/// ```
class FoldableHelper extends ChangeNotifier {
  FoldableHelper._();

  static final FoldableHelper _instance = FoldableHelper._();
  static FoldableHelper get instance => _instance;

  static const _channel = MethodChannel('com.carriez.flutter_hbb/foldable');

  FoldPosture _foldPosture = FoldPosture.unknown;
  bool _isFoldable = false;
  bool _initialized = false;

  // -- public getters --

  FoldPosture get foldPosture => _foldPosture;
  bool get isFoldable => _isFoldable;
  bool get isUnfolded => _foldPosture == FoldPosture.unfolded;
  bool get isFolded => _foldPosture == FoldPosture.folded;
  bool get initialized => _initialized;

  /// Initialize foldable detection.
  /// Call once during app startup (after Flutter binding is ready).
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final result = await _channel.invokeMethod<bool>('isFoldable');
        _isFoldable = result ?? false;

        if (_isFoldable) {
          final posture = await _channel.invokeMethod<String>('getFoldPosture');
          _foldPosture = _parsePosture(posture);
        }

        _channel.setMethodCallHandler(_onMethodCall);
      } catch (e) {
        debugPrint('FoldableHelper: native channel unavailable ($e)');
        _isFoldable = false;
      }
    }

    notifyListeners();
  }

  /// Update state from platform channel events (fold/unfold transitions).
  Future<void> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onFoldStateChanged':
        final posture = _parsePosture(call.arguments as String?);
        if (posture != _foldPosture) {
          debugPrint('FoldableHelper: posture changed $_foldPosture → $posture');
          _foldPosture = posture;
          notifyListeners();
        }
        break;
      default:
        break;
    }
  }

  FoldPosture _parsePosture(String? posture) {
    switch (posture) {
      case 'folded':
        return FoldPosture.folded;
      case 'unfolded':
        return FoldPosture.unfolded;
      case 'halfOpened':
        return FoldPosture.halfOpened;
      default:
        return FoldPosture.unknown;
    }
  }

  /// Classify the current screen size tier based on logical pixels.
  ///
  /// Uses [MediaQuery] data from the provided [BuildContext].
  /// On foldables, the tier may change when the device is folded or unfolded.
  static ScreenSizeTier classifyScreen(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final shortest = size.shortestSide;

    if (shortest >= 840) {
      return ScreenSizeTier.tablet;
    } else if (shortest >= 600) {
      return ScreenSizeTier.foldable;
    } else {
      return ScreenSizeTier.phone;
    }
  }

  /// Returns true if the current screen is likely the Pixel Fold inner
  /// screen (or a similarly sized foldable / tablet).
  static bool isWideScreen(BuildContext context) {
    final shortest = MediaQuery.of(context).size.shortestSide;
    return shortest >= 580;
  }

  /// Returns true if the device should use a side-panel / two-pane
  /// layout instead of stacked controls.
  static bool shouldUseSidePanel(BuildContext context) {
    return isWideScreen(context) &&
        MediaQuery.of(context).orientation == Orientation.landscape;
  }

  /// Calculate optimal content area padding for foldable inner screens
  /// to avoid content being hidden by the hinge.
  static EdgeInsets foldableSafePadding(BuildContext context) {
    final inset = MediaQuery.of(context).padding;
    // On Pixel Fold inner screen, add extra horizontal padding
    // to keep controls away from the center hinge area.
    if (isWideScreen(context)) {
      return EdgeInsets.only(
        top: inset.top + 8,
        bottom: inset.bottom + 8,
        left: inset.left + 16,
        right: inset.right + 16,
      );
    }
    return EdgeInsets.zero;
  }
}

/// Builder widget that rebuilds when foldable state changes.
///
/// ```dart
/// FoldableBuilder(
///   builder: (context, isFoldable, posture) {
///     if (posture == FoldPosture.unfolded) {
///       return WideLayout();
///     }
///     return NarrowLayout();
///   },
/// )
/// ```
class FoldableBuilder extends StatelessWidget {
  final Widget Function(
      BuildContext context, bool isFoldable, FoldPosture posture)
      builder;

  const FoldableBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FoldableHelper.instance,
      builder: (context, _) {
        final h = FoldableHelper.instance;
        return builder(context, h.isFoldable, h.foldPosture);
      },
    );
  }
}
