//
//  OSDHelper.swift
//  YogaSMC
//
//  Created by Zhen on 10/14/20.
//  Copyright © 2020 Zhen. All rights reserved.
//

import Foundation
import os.log

import SwiftUI

// from https://ffried.codes/2018/01/20/the-internals-of-the-macos-hud/
//@objc enum OSDImage: CLongLong {
//    case kBrightness = 1
//    case brightness2 = 2
//    case kVolume = 3
//    case kMute = 4
//    case volume5 = 5
//    case kEject = 6
//    case brightness7 = 7
//    case brightness8 = 8
//    case kAirportRange = 9
//    case wireless2Forbid = 10
//    case kBright = 11
//    case kBrightOff = 12
//    case kBright13 = 13
//    case kBrightOff14 = 14
//    case ajar = 15
//    case mute16 = 16
//    case volume17 = 17
//    case empty18 = 18
//    case kRemoteLinkedGeneric = 19
//    case kRemoteSleepGeneric = 20 // will put into sleep
//    case muteForbid = 21
//    case volumeForbid = 22
//    case volume23 = 23
//    case empty24 = 24
//    case kBright25 = 25
//    case kBrightOff26 = 26
//    case backlightonForbid = 27
//    case backlightoffForbid = 28
//    /* and more cases from 1 to 28 (except 18 and 24) */
//}

let defaultImage: NSString = "/System/Library/CoreServices/OSDUIHelper.app/Contents/Resources/kBrightOff.pdf"

// Bundled resources
enum EventImage: String {
    case kAirplaneMode, kAntenna, kMic, kMicOff, kKeyboard, kKeyboardOff, kWifi, kWifiOff
    case kBacklightHigh, kBacklightLow, kBacklightOff, kCapslockOn, kCapslockOff, kDock, kUndock
    case kBluetooth, kCamera, kFunctionKey, kFunctionKeyOff, kFunctionKeyOn, kSecondDisplay, kSleep, kStar
}
 
@available(macOS 26.0, *)
final class OSDWindowController {

    static let shared = OSDWindowController()
    private var window: NSWindow?
    private var dismissWorkItem: DispatchWorkItem?
    private var isVisible = false

    private init() {}

    func show<Content: View>(
        width: CGFloat = 260,
        height: CGFloat = 220,
        @ViewBuilder content: () -> Content
    ) {
        let hosting = NSHostingView(rootView: content())
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)

        if window == nil {
            let window = NSWindow(
                contentRect: hosting.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )

            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .statusBar
            window.hasShadow = true
            window.ignoresMouseEvents = true
            window.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary
            ]

            self.window = window
        }

        window?.contentView = hosting
        positionTopRight()
        window?.alphaValue = 1
        window?.makeKeyAndOrderFront(nil)

        scheduleAutoDismiss()
    }
    
    // MARK: - Top-right positioning

    private func positionTopRight() {
        guard let window else { return }
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame

        let marginX: CGFloat = 34   // distance from right edge
        let marginY: CGFloat = 12   // distance from menu bar

        let x = screenFrame.maxX - window.frame.width - marginX
        let y = screenFrame.maxY - window.frame.height - marginY

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Auto-dismiss

    private func scheduleAutoDismiss(delay: TimeInterval = 1.5) {
        dismissWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                self.window?.animator().alphaValue = 0
            } completionHandler: {
                self.window?.orderOut(nil)
                self.isVisible = false
            }
        }

        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

}

@available(macOS 26.0, *)
struct CustomGlassEffectView<Content: View>: NSViewRepresentable {
  private let variant: Int? // 0 - 19
  private let scrimState: Int? // Scrim overlay (0 = off, 1 = on)
  private let subduedState: Int? // Subdued state (0 = normal, 1 = subdued)
  private let style: NSGlassEffectView.Style?
  private let tint: NSColor?
  private let cornerRadius: CGFloat?
  private let content: Content

  init(variant: Int? = nil,
       scrimState: Int? = nil,
       subduedState: Int? = nil,
       style: NSGlassEffectView.Style? = nil,
       tint: NSColor? = nil,
       cornerRadius: CGFloat? = nil,
       @ViewBuilder content: () -> Content)
  {
    self.variant = variant
    self.scrimState = scrimState
    self.subduedState = subduedState
    self.style = style
    self.tint = tint
    self.cornerRadius = cornerRadius
    self.content = content()
  }

  func makeNSView(context _: Context) -> NSView {
    guard let nsGlassEffectViewType = NSClassFromString("NSGlassEffectView") as? NSView.Type else {
      return NSView()
    }
    let nsView = nsGlassEffectViewType.init(frame: .zero)
    self.configureView(nsView)
    let hosting = NSHostingView(rootView: content)
    hosting.translatesAutoresizingMaskIntoConstraints = false
    nsView.setValue(hosting, forKey: "contentView")
    return nsView
  }

  func updateNSView(_ nsView: NSView, context _: Context) {
    if let hosting = nsView.value(forKey: "contentView") as? NSHostingView<Content> { hosting.rootView = content }
    self.configureView(nsView)
  }

  func configureView(_ nsView: NSView) {
    if let variant { nsView.setValue(variant, forKey: "_variant") }
    if let scrimState { nsView.setValue(scrimState, forKey: "_scrimState") }
    if let subduedState { nsView.setValue(subduedState, forKey: "_subduedState") }
    if let style { (nsView as? NSGlassEffectView)?.style = style }
    if let tint { nsView.setValue(tint, forKey: "tintColor") }
    if let cornerRadius { nsView.setValue(cornerRadius, forKey: "cornerRadius") }
  }
    
}

@available(macOS 26.0, *)
struct OSDContentView: View {
    let image: NSImage?
    let text: String

    var body: some View {
        HStack(spacing: image == nil ? 0 : 0) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .offset(x: -12, y: 4)
            }

            Text(text)
                .font(.system(size: 14, weight: .medium))
                .frame(
                    maxWidth: image == nil ? .infinity : nil,
                    alignment: image == nil ? .center : .leading
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}


@available(macOS 26.0, *)
func osdImage(from event: EventImage) -> NSImage? {
    let name = String(event.rawValue.dropFirst(1))
    guard let path = Bundle.main.pathForImageResource(name) else {
        print("OSD: No image found for:", name)
        return nil
    }
    let image = NSImage(contentsOfFile: path)
    return image
}

@available(macOS 26.0, *)
func showOSDRaw26(_ prompt: String, _ img: EventImage? = nil) {
    let image = img.flatMap { osdImage(from: $0) }

    let osdWidth: CGFloat = 220
    let osdHeight: CGFloat = 64

    OSDWindowController.shared.show {
        ZStack {
            // Glass background
            CustomGlassEffectView(
                variant: 5,
                scrimState: 0,
                subduedState: 0,
                cornerRadius: 24
            ) {
                Spacer()
                    .frame(width: osdWidth, height: osdHeight)
            }
            //.saturation(1.5)
            //.brightness(0.2)
            //.blur(radius: 0.25)
            
            // Foreground content
            OSDContentView(
                image: image,
                text: prompt
            )
        }
        .frame(width: osdWidth, height: osdHeight)
    }
}


// from https://github.com/alin23/Lunar/blob/master/Lunar/Data/Hotkeys.swift
func showOSDRaw(_ prompt: String, _ img: NSString? = nil, duration: UInt32 = 1000, priority: UInt32 = 0x1f4) {
    guard let manager = OSDManager.sharedManager() as? OSDManager else {
        if #available(macOS 10.12, *) {
            os_log("OSDManager unavailable", type: .error)
        }
        return
    }

    manager.showImage(
        atPath: img ?? defaultImage,
        onDisplayID: CGMainDisplayID(),
        priority: priority,
        msecUntilFade: duration,
        withText: prompt as NSString)
}


func showOSD(_ prompt: String, _ img: NSString? = nil, duration: UInt32 = 1000, priority: UInt32 = 0x1f4) {
    
    if #available(macOS 26.0, *){
        showOSDRaw26(NSLocalizedString(prompt, comment: "LocalizedString"), nil)
    }
    else{
        showOSDRaw(NSLocalizedString(prompt, comment: "LocalizedString"), img, duration: duration, priority: priority)
    }
}

func showOSDRes(_ prompt: String, _ image: EventImage, duration: UInt32 = 1000, priority: UInt32 = 0x1f4) {
    var img: NSString?
    if let path = Bundle.main.pathForImageResource(String(image.rawValue.dropFirst(1))),
              path.hasPrefix("/Applications") {
        img = path as NSString
    }
    if #available(macOS 26.0, *){
        showOSDRaw26(NSLocalizedString(prompt, comment: "LocalizedString"), image)
    }
    else{
        showOSDRaw(NSLocalizedString(prompt, comment: "LocalizedString"), img, duration: duration, priority: priority)
    }
    
}

func showOSDRes(
    _ prompt: String,
    _ status: String,
    _ image: EventImage,
    duration: UInt32 = 1000,
    priority: UInt32 = 0x1f4
) {
    var img: NSString?
    if let path = Bundle.main.pathForImageResource(String(image.rawValue.dropFirst(1))),
              path.hasPrefix("/Applications") {
        img = path as NSString
    }
    var alias = prompt
    if img != nil {
        alias = NSLocalizedString(prompt, comment: "")
    }
    if alias.isEmpty {
        if #available(macOS 26.0, *){
            showOSDRaw26(alias, image)
        }
        else{
            showOSDRaw(alias, img, duration: duration, priority: priority)

        }
    } else {
        alias += " " + NSLocalizedString(status, comment: "")
        if #available(macOS 26.0, *){
            showOSDRaw26(alias, image)
        }
        else{
            showOSDRaw(alias, img, duration: duration, priority: priority)
        }
    }
}
