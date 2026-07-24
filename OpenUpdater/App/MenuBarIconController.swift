//
//  MenuBarIconController.swift
//  OpenUpdater
//
//  Created by Chen Asraf.
//

import AppKit

/// Draws the menubar glyph and keeps it in sync with the update engine's state:
/// spins the brand glyph while working, and composites a small monochrome badge in
/// the corner for the resting states. Everything is drawn as a template image so
/// macOS tints it for light/dark menubars.
@MainActor
final class MenuBarIconController {
  /// What the icon should convey right now, in precedence order.
  enum State: Equatable {
    /// Scanning apps / resolving latest versions — spin, no badge.
    case checking
    /// Downloading/installing an update — spin with a down-arrow badge.
    case installing
    /// One or more updates are ready — resting glyph with a "!" badge.
    case updatesAvailable
    /// Everything is current — resting glyph with a checkmark badge.
    case upToDate
  }

  private weak var button: NSStatusBarButton?
  private let baseImage: NSImage
  private let size = NSSize(width: 18, height: 18)

  private var state: State = .upToDate
  private var angle: CGFloat = 0
  private var spinTimer: Timer?

  init(button: NSStatusBarButton, baseImage: NSImage) {
    self.button = button
    self.baseImage = baseImage
    render()
  }

  /// Point the icon at a new state. Spinning states re-render on a timer; resting
  /// states render once. A no-op when the state is unchanged.
  func update(_ newState: State) {
    guard newState != state else { return }
    state = newState
    switch state {
    case .checking, .installing:
      startSpinning()
    case .updatesAvailable, .upToDate:
      stopSpinning()
    }
    render()
  }

  // MARK: - Spin

  private func startSpinning() {
    guard spinTimer == nil else { return }
    // ~30fps, one full turn per second. Scheduled in the common run-loop mode so it
    // keeps animating while the menu / popover is tracking.
    let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.angle -= 360.0 / 30.0  // negative = clockwise
        self.render()
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    spinTimer = timer
  }

  private func stopSpinning() {
    spinTimer?.invalidate()
    spinTimer = nil
    angle = 0  // rest upright
  }

  // MARK: - Draw

  private func render() {
    guard let button else { return }
    let image = NSImage(size: size)
    image.lockFocus()
    defer {
      image.unlockFocus()
      image.isTemplate = true
      button.image = image
      button.image?.accessibilityDescription = AppBranding.title
    }
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }

    // Base glyph, rotated about its center.
    NSGraphicsContext.saveGraphicsState()
    ctx.translateBy(x: size.width / 2, y: size.height / 2)
    ctx.rotate(by: angle * .pi / 180)
    ctx.translateBy(x: -size.width / 2, y: -size.height / 2)
    baseImage.draw(
      in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    guard let badge = badgeSymbol else { return }

    // Stamp the (non-rotating) badge into the hollow center of the ring — it stays put
    // even while the arrows spin around it, since rotation is about that same center.
    // Fit to the symbol's natural aspect ratio (a "!" is narrow and tall) so it isn't
    // stretched square.
    let box = NSRect(x: 0, y: 0, width: size.width, height: size.height).insetBy(dx: 3.5, dy: 3.5)
    badge.draw(in: fit(badge.size, in: box), from: .zero, operation: .sourceOver, fraction: 1)
  }

  /// Aspect-fit `content` inside `box`, centered — so a tall, narrow symbol keeps its
  /// proportions instead of being stretched to the box's shape.
  private func fit(_ content: NSSize, in box: NSRect) -> NSRect {
    guard content.width > 0, content.height > 0 else { return box }
    let scale = min(box.width / content.width, box.height / content.height)
    let fitted = NSSize(width: content.width * scale, height: content.height * scale)
    return NSRect(
      x: box.midX - fitted.width / 2, y: box.midY - fitted.height / 2,
      width: fitted.width, height: fitted.height)
  }

  /// The corner badge for the current state, as a bold template symbol (nil while
  /// spinning without a badge).
  private var badgeSymbol: NSImage? {
    let name: String
    switch state {
    case .checking: return nil
    case .installing: name = "arrow.down"
    case .updatesAvailable: name = "exclamationmark"
    case .upToDate: name = "checkmark"
    }
    let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
    let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
      .withSymbolConfiguration(config)
    symbol?.isTemplate = true
    return symbol
  }
}
