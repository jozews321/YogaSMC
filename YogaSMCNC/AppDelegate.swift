//
//  AppDelegate.swift
//  YogaSMCNC
//
//  Created by Zhen on 10/11/20.
//  Copyright © 2020 Zhen. All rights reserved.
//

import AppKit
import ApplicationServices
import Carbon
import NotificationCenter
import os.log
import ServiceManagement
import IOKit

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let defaults = UserDefaults(suiteName: "org.zhen.YogaSMC")!
    var conf = SharedConfig()
    var IOClass = "YogaSMC"
    
    //DYTC Slider
    let slider = NSSlider(frame: NSRect(x: 15, y: 20, width: 200, height: 5))
    let PSCSupport = NSLocalizedString("PSC Support", comment: "")
    
    let DYTCCommand = ["L", "M", "H"]
            
    var statusItem: NSStatusItem?
    @IBOutlet weak var appMenu: NSMenu!
    var hide = false

    // MARK: - CapsLock

    var hideCapslock = false
    var capslockTimer: Timer?
    var capslockState = false
    var PSCState = true
    var SliderNumber = 1
    
    @objc func showCapslock(sender: Timer) {
        let current = GetCurrentKeyModifiers() & UInt32(alphaLock) != 0
        if current != capslockState {
            showOSDRes("Caps Lock", current ? "On" : "Off", current ? .kCapslockOn : .kCapslockOff)
            capslockState = current
        }
    }

    // MARK: - Think

    var fanHelper: ThinkFanHelper?
    var fanHelper2: ThinkFanHelper?
    var fanTimer: Timer?

    @objc func setPerformance() {
        if (defaults.bool (forKey: "PSCState") == false)
        {
            switch defaults.integer (forKey: "SliderNumber"){
            case 0:
                _ = sendString("DYTCMode", DYTCCommand[0], conf.service)
            case 1:
                _ = sendString("DYTCMode", DYTCCommand[1], conf.service)
            case 2:
                _ = sendString("DYTCMode", DYTCCommand[2], conf.service)
            default:
                os_log("Invalid value", type: .info)
            }
            print("Setting Performance to, Slider Value: \(defaults.integer (forKey: "SliderNumber")) PSCSupport: \(defaults.bool (forKey: "PSCState"))")
        }
        else
        {
            _ = sendNumber("DYTCPSCMode", (defaults.integer (forKey: "SliderNumber") != 0) ? defaults.integer (forKey: "SliderNumber") : 0xf, conf.service)
            print("Setting Performance to, Slider Value: \(defaults.integer (forKey: "SliderNumber")) PSCSupport: \(defaults.bool (forKey: "PSCState"))")
        }
        
    }
    @objc func thinkWakeup() {
        
        micMuteLEDHelper(conf.service)
        muteLEDHelper(conf.service)

        if fanHelper2 != nil {
            fanHelper2?.setFanLevel()
        }
        if fanHelper != nil {
            fanHelper?.setFanLevel()
        }
        
        //Set performance after wake
        print("Wakeup detected, setting saved performance level")
        setPerformance()
        
    }

    @objc func thinkMuteLEDFixup() {
        muteLEDHelper(conf.service, false)
    }

    // MARK: - Menu

    @IBAction func openAboutPanel(_ sender: NSMenuItem) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(sender)
    }

    @objc func toggleStartAtLogin(_ sender: NSMenuItem) {
        let identifier = "\(Bundle.main.bundleIdentifier!)Helper" as CFString
        if SMLoginItemSetEnabled(identifier, sender.state == .off) {
            sender.state = (sender.state == .on) ? .off : .on
            defaults.setValue((sender.state == .on), forKey: "StartAtLogin")
        } else {
            if #available(macOS 10.12, *) {
                os_log("Toggle start at login failed", type: .error)
            }
        }
    }
    
    @objc func enablePSC(_ sender: NSMenuItem) {
        if sender.state == .off
        {
            slider.maxValue = 8
            slider.minValue = 0
            slider.numberOfTickMarks = 9
            slider.target = self
            slider.action = #selector(sliderChanged)
            slider.allowsTickMarkValuesOnly = true
            slider.isContinuous = false
            print("Slider value: \(slider.intValue))")
            print("PSCStateAfterOFF: \(defaults.bool(forKey: "PSCState"))")
            defaults.setValue((true), forKey: "PSCState")
            sender.state = .on
            print("senderValue: \(sender.state)")
            setPerformance()
            sliderChanged(slider)
           
        }
        else
        {
            slider.maxValue = 2
            slider.minValue = 0
            slider.numberOfTickMarks = 3
            slider.target = self
            slider.action = #selector(sliderChanged)
            slider.allowsTickMarkValuesOnly = true
            slider.isContinuous = false
            print("PSCStateAfterON: \(defaults.bool(forKey: "PSCState"))")
            defaults.setValue((false), forKey: "PSCState")
            sender.state = .off
            print("senderValue: \(sender.state)")
            if (defaults.integer(forKey: "SliderNumber") >= 3)
            {
                print("more than 3")
                defaults.setValue(1, forKey: "SliderNumber")
                slider.integerValue = 1
            }
            setPerformance()
            sliderChanged(slider)
        }
    }

    @objc func openPrefpane() {
        prefpaneHelper()
    }

    @objc func midnightTimer(sender: Timer) {
        setHolidayIcon(statusItem!)
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: Date())
        sender.fireDate = calendar.date(byAdding: .day, value: 1, to: midnight)!
        if #available(macOS 10.12, *) {
            os_log("Timer sheduled at %s", type: .info, sender.fireDate.description(with: Locale.current))
        }
    }

    @objc func iconWakeup() {
        setHolidayIcon(statusItem!)
    }

    @objc func update () {
        DispatchQueue.main.async {
            if self.fanHelper2 != nil {
                self.fanHelper2!.update()
            }
            if self.fanHelper != nil {
                self.fanHelper!.update()
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        update()
        DispatchQueue.global(qos: .default).async {
            self.fanTimer = Timer.scheduledTimer(
                timeInterval: 1,
                target: self,
                selector: #selector(self.update),
                userInfo: nil,
                repeats: true
            )

            if self.fanTimer == nil {
                return
            }
            self.fanTimer?.tolerance = 0.2
            let currentRunLoop = RunLoop.current
            currentRunLoop.add(self.fanTimer!, forMode: .common)
            currentRunLoop.run()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        self.fanTimer?.invalidate()
    }

    // MARK: - Application

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        var iter: io_iterator_t = 0

        IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("YogaVPC"), &iter)

        while let service = IOIteratorNextOptional(iter) {
            guard let IOClass = getString("IOClass", service) else {
                if #available(macOS 10.12, *) {
                    os_log("Invalid YogaVPC instance", type: .info)
                }
                continue
            }

            if #available(macOS 10.12, *) {
                os_log("Found %s", type: .info, IOClass)
            }

            var connect: io_connect_t = 0

            guard kIOReturnSuccess == IOServiceOpen(service, mach_task_self_, 0, &connect) else { continue }

            conf.service = service
            self.IOClass = IOClass

            guard kIOReturnSuccess == IOConnectCallScalarMethod(connect, UInt32(kYSMCUCOpen), nil, 0, nil, nil) else {
                IOServiceClose(connect)
                continue
            }

            conf.connect = connect
            break
        }

        guard conf.service != 0 else {
            if #available(macOS 10.12, *) {
                os_log("Failed to connect to YogaSMC", type: .fault)
            }
            showOSD("ConnectFail", duration: 2000)
            NSApp.terminate(nil)
            return
        }

        guard let props = getProperties(conf.service) else {
            if #available(macOS 10.12, *) {
                os_log("YogaSMC unavailable", type: .error)
            }
            showOSD("YogaSMC Unavailable", duration: 2000)
            NSApp.terminate(nil)
            return
        }

        guard conf.connect != 0 else {
            if #available(macOS 10.12, *) {
                os_log("Another instance has connected to %s", type: .fault, IOClass)
            }
            showOSD("AlreadyConnected", duration: 2000)
            NSApp.terminate(nil)
            return
        }

        if #available(macOS 10.12, *) {
            os_log("Connected to %s", type: .info, IOClass)
        }

        loadConfig()

        initMenu(props["VersionInfo"] as? String ?? NSLocalizedString("Unknown Version", comment: ""))
        
        initNotification(props["EC Capability"] as? String)

        capslockState = GetCurrentKeyModifiers() & UInt32(alphaLock) != 0
        if capslockState {
            conf.modifier.insert(.capsLock)
        }
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flagsCallBack)
        
        setPerformance()
        slider.integerValue = defaults.integer(forKey: "SliderNumber")
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        saveConfig()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        IOServiceClose(conf.connect)
    }
    
    // DYTC: - Control
    
    func addDYTCEntries(_ dict: NSDictionary) {
        appMenu.insertItem(NSMenuItem.separator(), at: 4)

            let DYTCRevision = "DYTCRevision: \(dict["Revision"] as? NSNumber ?? 0).\(dict["SubRevision"] as? NSNumber ?? 0)"

            appMenu.insertItem(withTitle: DYTCRevision, action: nil, keyEquivalent: "", at: 5)
            
            let DYTCFunction = "DYTCFunction: \(dict["FuncMode"] as? String ?? "Unknown")"
            appMenu.insertItem(withTitle: DYTCFunction, action: nil, keyEquivalent: "", at: 6)
        
        
            //PSC Support
            let psc = NSMenuItem(title: PSCSupport, action: #selector(enablePSC), keyEquivalent: "p")
            print("PSCStateToSetCheck: \(defaults.bool(forKey: "PSCState"))")
            
            psc.state = defaults.bool(forKey: "PSCState") ? .on : .off
            appMenu.insertItem(psc, at: 7)

            if defaults.bool(forKey: "PSCState") == false{
                slider.maxValue = 2
                slider.minValue = 0
                slider.numberOfTickMarks = 3
                slider.target = self
                slider.action = #selector(sliderChanged)
                slider.allowsTickMarkValuesOnly = true
                slider.isContinuous = false
                
                
                let view = NSView(frame: NSRect(x: 0, y: 0, width: slider.frame.width + 40, height: slider.frame.height + 40))
                view.addSubview(slider)
                let item = NSMenuItem()
                item.view = view
                appMenu.insertItem(item, at: 8)
            
            }
            if defaults.bool(forKey: "PSCState") == true{
                slider.maxValue = 8
                slider.minValue = 0
                slider.numberOfTickMarks = 9
                slider.target = self
                slider.action = #selector(sliderChanged)
                slider.allowsTickMarkValuesOnly = true
                slider.isContinuous = false
                
                
                let view = NSView(frame: NSRect(x: 0, y: 0, width: slider.frame.width + 40, height: slider.frame.height + 40))
                view.addSubview(slider)
                let item = NSMenuItem()
                item.view = view
                appMenu.insertItem(item, at: 8)
            }
            
        appMenu.insertItem(withTitle: "Quiet        Balance        Perf" , action: nil, keyEquivalent: "", at: 9)
        appMenu.insertItem(NSMenuItem.separator(), at: 10)
            
        switch dict["FuncMode"] as? String{
        case "Desk":
            slider.intValue = 2
        case "Standard":
            slider.intValue = 1
        default:
            slider.intValue = 0
            os_log("Unknown", type: .info)
        }
        
    }
    func setDYTC(slider: NSSlider) {
        
        os_log("Slider Value: %d", type: .info, slider.integerValue)
        defaults.setValue(slider.integerValue, forKey: "SliderNumber")
        
        setPerformance()
    }

    @objc func sliderChanged(_ sender: NSSlider) {
        //os_log("Slider Value: %d", type: .info, sender.integerValue)
                
        setDYTC(slider: sender)
        
        let dict = getDictionary("DYTC", self.conf.service)!

        let NewDYTCFunction = "DYTCFunction: \(dict["FuncMode"] as? String ?? "Unknown")"
        print("New DYTCFunction: \(NewDYTCFunction)")
    
        guard let DYTCFunctionItem = self.appMenu.item(at: 6) else {
            print("DYTCFunctionItem not found at index 5")
            return
            }
        DYTCFunctionItem.title = NewDYTCFunction
    }

    // MARK: - Configuration

    func initMenu(_ version: String) {
        if hide {
            if #available(macOS 10.12, *) {
                os_log("Icon hidden", type: .info)
            }
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.menu = appMenu
        if let title = defaults.string(forKey: "Title") {
            statusItem?.title = title
            statusItem?.toolTip = defaults.string(forKey: "ToolTip")
        } else {
            _ = Timer.scheduledTimer(
                timeInterval: 0,
                target: self,
                selector: #selector(midnightTimer(sender:)),
                userInfo: nil,
                repeats: true
            )
            NSWorkspace.shared.notificationCenter.addObserver(
                self,
                selector: #selector(iconWakeup),
                name: NSWorkspace.didWakeNotification,
                object: nil
            )
        }

        appMenu.delegate = self

        let classPrompt = NSLocalizedString("ClassVar", comment: "Class: ") + IOClass
        appMenu.insertItem(NSMenuItem.separator(), at: 1)
        appMenu.insertItem(withTitle: classPrompt, action: nil, keyEquivalent: "", at: 2)
        appMenu.insertItem(withTitle: version, action: nil, keyEquivalent: "", at: 3)
       
        if let dict = getDictionary("DYTC", conf.service) {
            let DYTCRevision = "DYTCRevision: \(dict["Revision"] as? NSNumber ?? 0).\(dict["SubRevision"] as? NSNumber ?? 0)"
            addDYTCEntries(dict)
        }

        let loginPrompt = NSLocalizedString("Start at Login", comment: "")
        let login = NSMenuItem(title: loginPrompt, action: #selector(toggleStartAtLogin), keyEquivalent: "s")
        login.state = defaults.bool(forKey: "StartAtLogin") ? .on : .off
        appMenu.insertItem(NSMenuItem.separator(), at: 11)
        appMenu.insertItem(login, at: 12)

        let prefPrompt = NSLocalizedString("Preferences", comment: "")
        let pref = NSMenuItem(title: prefPrompt, action: #selector(openPrefpane), keyEquivalent: "p")
        appMenu.insertItem(NSMenuItem.separator(), at: 13)
        appMenu.insertItem(pref, at: 14)
        appMenu.insertItem(NSMenuItem.separator(), at: 15)

    }

    func initNotification(_ ECCap: String?) {
        var isOpen = false
        switch IOClass {
        case "IdeaVPC":
            conf.events = ideaEvents
            isOpen = registerNotification(&conf)
        case "ThinkVPC":
            conf.events = thinkEvents
            isOpen = registerNotification(&conf)
            thinkWakeup()
            if !hide, !defaults.bool(forKey: "DisableFan") {
                if ECCap == "RW" {
                    if !getBoolean("Dual fan", conf.service), defaults.bool(forKey: "SecondThinkFan") {
                        fanHelper2 = ThinkFanHelper(appMenu, conf.connect, false, false)
                        if defaults.bool(forKey: "SaveFanLevel"),
                           let level = defaults.object(forKey: "Fan2Level") as? UInt8 {
                            fanHelper2?.setFanLevel(level)
                        }
                        fanHelper2?.update(true)
                    }
                    fanHelper = ThinkFanHelper(appMenu, conf.connect, true, fanHelper2 == nil)
                    if defaults.bool(forKey: "SaveFanLevel"),
                       let level = defaults.object(forKey: "FanLevel") as? UInt8 {
                        fanHelper?.setFanLevel(level)
                    }
                    fanHelper?.update(true)
                } else {
                    showOSD("ECAccessUnavailable")
                }
            }
            
            NSWorkspace.shared.notificationCenter.addObserver(
                self,
                selector: #selector(thinkWakeup),
                name: NSWorkspace.didWakeNotification,
                object: nil
            )

            if defaults.bool(forKey: "ThinkMuteLEDFixup") {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(thinkMuteLEDFixup),
                    name: VolumeObserver.volumeChanged,
                    object: nil
                )

                DistributedNotificationCenter.default.addObserver(
                    self,
                    selector: #selector(thinkMuteLEDFixup),
                    name: NSNotification.Name(rawValue: "com.apple.sound.settingsChangedNotification"),
                    object: nil
                )
            }
        case "YogaHIDD":
            conf.events = HIDDEvents
            _ = registerNotification(&conf)
            if #available(macOS 10.12, *) {
                os_log("Skip loadEvents", type: .info)
            }
        default:
            if #available(macOS 10.12, *) {
                os_log("Unknown class", type: .error)
            }
            showOSD("Unknown Class", duration: 2000)
        }
        if isOpen { loadEvents(&conf) }
    }

    func flagsCallBack(event: NSEvent) {
//        print(event.keyCode)
//        switch event.keyCode {
//        case 0x36:
//            os_log("left_option", type: .debug)
//        case 0x37:
//            os_log("right_option", type: .debug)
//        case 0x39:
//            os_log("caps_lock", type: .debug)
//        case 0x3b:
//            os_log("left_control", type: .debug)
//        case 0x3d:
//            os_log("left_command", type: .debug)
//        case 0x3e:
//            os_log("right_control", type: .debug)
//        default:
//            os_log("Unknown %x", type: .debug, event.keyCode)
//        }
        // 1 << 16
        if !hideCapslock {
            if event.modifierFlags.contains(.capsLock) != conf.modifier.contains(.capsLock) {
                capslockTimer = Timer.scheduledTimer(
                    timeInterval: 0.05,
                    target: self,
                    selector: #selector(showCapslock(sender:)),
                    userInfo: nil,
                    repeats: false
                )
            }
        }
        conf.modifier = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // 1 << 17
//        if conf.modifier.contains(.shift) {
//            os_log("Shift", type: .debug)
//            flags.remove(.shift)
//        }
        // 1 << 18
//        if conf.modifier.contains(.control) {
//            os_log("Control", type: .debug)
//            flags.remove(.control)
//        }
        // 1 << 19
//        if conf.modifier.contains(.option) {
//            os_log("Option", type: .debug)
//            flags.remove(.option)
//        }
        // 1 << 20
//        if conf.modifier.contains(.command) {
//            os_log("Command", type: .debug)
//            flags.remove(.command)
//        }
//        if !flags.isEmpty {
//            print(flags)
//        }
    }

    func loadConfig() {
        if defaults.object(forKey: "StartAtLogin") == nil {
            if #available(macOS 10.12, *) {
                os_log("First launch", type: .info)
            }
            defaults.setValue(false, forKey: "StartAtLogin")
        }
        
        PSCState = defaults.bool(forKey: "PSCState")
        SliderNumber = defaults.integer(forKey: "SliderNumber")


        hide = defaults.bool(forKey: "HideIcon")
        hideCapslock = defaults.bool(forKey: "HideCapsLock")

        if !Bundle.main.bundlePath.hasPrefix("/Applications") {
            showOSD("MoveApp")
        }

        // Load driver settings
        if defaults.object(forKey: "AutoBacklight") != nil {
            _ = sendNumber("AutoBacklight", defaults.integer(forKey: "AutoBacklight"), conf.service)
        }
        if defaults.object(forKey: "BacklightTimeout") != nil {
            _ = sendNumber("BacklightTimeout", defaults.integer(forKey: "BacklightTimeout"), conf.service)
        }
    }

    func saveConfig() {
        if !conf.events.isEmpty,
           Bundle.main.bundlePath.hasPrefix("/Applications"),
           IOClass != "YogaHIDD" {
            saveEvents(&conf)
        }

        if defaults.bool(forKey: "SaveFanLevel") {
            if fanHelper2 != nil {
                defaults.setValue(fanHelper2?.savedLevel, forKey: "Fan2Level")
            }
            if fanHelper != nil {
                defaults.setValue(fanHelper?.savedLevel, forKey: "FanLevel")
            }
        }

        // Save driver settings
        defaults.setValue(getNumber("AutoBacklight", conf.service), forKey: "AutoBacklight")
        defaults.setValue(getNumber("BacklightTimeout", conf.service), forKey: "BacklightTimeout")
    }
}
