//
//  ContentView.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 20/06/2026.
//

import SwiftUI

/// The menubar popover. Mirrors the main window's updates list — selectable rows
/// with per-row install controls and a right-click menu — in a compact form.
struct ContentView: View {
  let openMainWindow: () -> Void
  let openPreferences: () -> Void
  @EnvironmentObject private var updateManager: UpdateManager
  @State private var selection: Set<AppInfo.ID> = []
  // Persisted popover size; the resize grip writes these and the popover follows.
  @AppStorage("popoverWidth") private var width = 460.0
  @AppStorage("popoverHeight") private var height = 560.0
  @State private var dragStartSize: CGSize?
  @State private var dragStartMouse: CGPoint?

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      content
      Divider()
      footer
    }
    .frame(width: width, height: height)
  }

  private var header: some View {
    HStack(spacing: 8) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 20, height: 20)
      Text(AppBranding.title).font(.headline)
      Spacer()
      Button {
        Task { await updateManager.checkForUpdates() }
      } label: {
        if updateManager.isChecking {
          ProgressView().controlSize(.small)
        } else {
          Image(systemName: "arrow.clockwise")
        }
      }
      .buttonStyle(.plain)
      .focusable(false)
      .disabled(updateManager.isChecking)
      .help("Check for updates")

      Button(action: openPreferences) {
        Image(systemName: "gearshape")
      }
      .buttonStyle(.plain)
      .focusable(false)
      .help("Preferences")

      Button(action: openMainWindow) {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
      }
      .buttonStyle(.plain)
      .focusable(false)
      .help("Open full window")
    }
    .padding(.horizontal, 12).padding(.vertical, 10)
    .background(.bar)
  }

  @ViewBuilder private var content: some View {
    if !updateManager.updates.isEmpty {
      VStack(spacing: 0) {
        actionBar
        Divider()
        List(updateManager.updates, selection: $selection) { app in
          UpdateRow(app: app)
        }
        .contextMenu(forSelectionType: AppInfo.ID.self) { ids in
          AppContextMenuItems(ids: ids)
        }
      }
    } else {
      status
    }
  }

  private var actionBar: some View {
    HStack(spacing: 8) {
      Text("^[\(updateManager.updates.count) update](inflect: true)")
        .font(.subheadline).foregroundStyle(.secondary)
      Spacer()
      if !selection.isEmpty {
        Button("Update \(selectedInstallableCount)") {
          updateManager.updateSelected(selection)
          selection = []
        }
        .controlSize(.small)
        .disabled(selectedInstallableCount == 0)
      }
      Button {
        updateManager.updateAll()
      } label: {
        if updateManager.isUpdatingAll {
          HStack(spacing: 4) {
            ProgressView().controlSize(.small)
            Text("Updating…")
          }
        } else {
          Text("Update All")
        }
      }
      .controlSize(.small)
      .buttonStyle(.borderedProminent)
      .disabled(updateManager.isUpdatingAll || updateManager.installableUpdates.isEmpty)
    }
    .padding(.horizontal, 12).padding(.vertical, 8)
  }

  @ViewBuilder private var status: some View {
    VStack(spacing: 12) {
      Spacer()
      if updateManager.isChecking {
        ProgressView()
        Text("Checking for updates…").font(.subheadline).foregroundStyle(.secondary)
      } else if let error = updateManager.lastError {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 32)).foregroundStyle(.orange)
        Text(error).font(.caption).foregroundStyle(.secondary)
          .multilineTextAlignment(.center).padding(.horizontal)
      } else {
        Image(systemName: "checkmark.seal.fill")
          .font(.system(size: 36)).foregroundStyle(.green)
        Text("All apps are up to date").font(.subheadline).foregroundStyle(.secondary)
      }
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  private var footer: some View {
    HStack(spacing: 8) {
      Button {
        NSApp.terminate(nil)
      } label: {
        Image(systemName: "power")
      }
      .buttonStyle(.plain).foregroundStyle(.secondary)
      .focusable(false)
      .help("Quit \(AppBranding.title)")
      if updateManager.isChecking || updateManager.isUpdatingAll {
        ProgressView().controlSize(.small).scaleEffect(0.7)
      }
      Text(updateManager.statusLine)
        .font(.caption).foregroundStyle(.secondary)
        .lineLimit(1).truncationMode(.middle)
      Spacer(minLength: 4)
      resizeGrip
    }
    .padding(.horizontal, 12).padding(.vertical, 8)
    .background(.bar)
  }

  /// Bottom-right drag handle that resizes (and persists) the popover.
  private var resizeGrip: some View {
    Canvas { context, size in
      for offset in stride(from: 2.0, through: 10.0, by: 4.0) {
        var path = Path()
        path.move(to: CGPoint(x: size.width - offset, y: size.height - 1))
        path.addLine(to: CGPoint(x: size.width - 1, y: size.height - offset))
        context.stroke(path, with: .color(.secondary.opacity(0.7)), lineWidth: 1)
      }
    }
    .frame(width: 12, height: 12)
    .contentShape(Rectangle())
    .onHover { hovering in
      if hovering { NSCursor.diagonalResize.push() } else { NSCursor.pop() }
    }
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { _ in
          // Measure against the screen (stable) rather than the grip, which moves as
          // the popover resizes — otherwise the resize lags the mouse.
          let mouse = NSEvent.mouseLocation
          if dragStartMouse == nil {
            dragStartMouse = mouse
            dragStartSize = CGSize(width: width, height: height)
          }
          guard let startMouse = dragStartMouse, let startSize = dragStartSize else { return }
          // The popover grows centered, so its right edge moves at half the width's
          // rate — double the x delta so the grip stays under the cursor.
          width = min(max(380, startSize.width + 2 * (mouse.x - startMouse.x)), 900)
          // Screen y grows upward, so dragging down (smaller y) increases height.
          height = min(max(360, startSize.height + (startMouse.y - mouse.y)), 1100)
        }
        .onEnded { _ in
          dragStartMouse = nil
          dragStartSize = nil
        }
    )
    .help("Drag to resize")
  }

  /// How many selected apps actually have something to install.
  private var selectedInstallableCount: Int {
    updateManager.installableUpdates.filter { selection.contains($0.id) }.count
  }
}

extension NSCursor {
  /// The diagonal (↘↖) window-resize cursor. It's private API, so this guards on
  /// availability and falls back to the crosshair cursor.
  static var diagonalResize: NSCursor {
    let selector = NSSelectorFromString("_windowResizeNorthWestSouthEastCursor")
    let cursorClass = NSCursor.self as AnyObject
    if cursorClass.responds(to: selector),
      let cursor = cursorClass.perform(selector)?.takeUnretainedValue() as? NSCursor
    {
      return cursor
    }
    return .crosshair
  }
}
