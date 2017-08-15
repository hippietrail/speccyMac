//
//  ViewController.swift
//  speccyMac
//
//  Created by John Ward on 21/07/2017.
//  Copyright © 2017 John Ward. All rights reserved.
//

import Cocoa

protocol Machine : class {
    
    func refreshScreen()
    func captureRow(_ row: UInt16)
    
    func input(_ reg: Register, high: UInt8, low: UInt8)
    func output(_ port: UInt8, byte: UInt8)
    
    func beep()
    
    var ticksPerFrame: UInt32 { get }
    var audioPacketSize: UInt32 { get }
}

struct colour {
    let r: UInt8
    let g: UInt8
    let b: UInt8
}

struct keyboardMap {
    let macKeycode: UInt16
    let spectrumCode: UInt16
}

class Spectrum: NSViewController {
    
    @IBOutlet weak var spectrumScreen: NSImageView!
    @IBOutlet weak var lateLabel: NSTextField!
    
    var z80: Z80!
    var clickCount: UInt32 = 0
    
    var flashCount = 0
    var invertColours = false
    
    var gameIndex = 0
    
    let colourSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue).union(CGBitmapInfo())
    
    // bmp pool to render image
    var bmpData = [UInt32](repeating: 0, count: 32 * 8 * 24 * 8)
    
    // precalculated screen and attribute rows
    var screenRowAddress    = [UInt16](repeating: 0, count: 192)
    var attributeRowAddress = [UInt16](repeating: 0, count: 24)
    
    // Screen image and saved version
    var screenCopy = [UInt8](repeating: 0, count: 32 * 192)
    var screenCopySave = [UInt8](repeating: 255, count: 32 * 192)
    
    // Attribute image and saved version
    var colourCopy = [UInt8](repeating: 0, count: 32 * 192)
    var colourCopySave = [UInt8](repeating: 255, count: 32 * 192)
    
    var provider: CGDataProvider!
    
    let colourTable = [colour(r: 0x00, g: 0x00, b: 0x00), colour(r: 0x00, g: 0x00, b: 0xcd), colour(r: 0xcd, g: 0x00, b: 0x00), colour(r: 0xcd, g: 0x00, b: 0xcd),
                       colour(r: 0x00, g: 0xcd, b: 0x00), colour(r: 0x00, g: 0xcd, b: 0xcd), colour(r: 0xcd, g: 0xcd, b: 0x00), colour(r: 0xcd, g: 0xcd, b: 0xcd),
                       colour(r: 0x00, g: 0x00, b: 0x00), colour(r: 0x00, g: 0x00, b: 0xff), colour(r: 0xff, g: 0x00, b: 0x00), colour(r: 0xff, g: 0x00, b: 0xff),
                       colour(r: 0x00, g: 0xff, b: 0x00), colour(r: 0x00, g: 0xff, b: 0xff), colour(r: 0xff, g: 0xff, b: 0x00), colour(r: 0xff, g: 0xff, b: 0xff)]
    
    let keyMap = [0xfd01, 0xfd02, 0xfd04, 0xfd08, 0xbf10, 0xfd10, 0xfe02, 0xfe04, 0xfe08, 0xfe10,
                  0x0000, 0x7f10, 0xfb01, 0xfb02, 0xfb04, 0xfb08, 0xdf10, 0xfb10, 0xf701, 0xf702,
                  0xf704, 0xf708, 0xef10, 0xf710, 0x0000, 0xef02, 0xef08, 0x0000, 0xef04, 0xef01,
                  0x0000, 0xdf02, 0xdf08, 0x0000, 0xdf04, 0xdf01, 0xbf01, 0xbf02, 0xbf08, 0x0000,
                  0xbf04, 0x0000, 0x0000, 0x7f02, 0x0000, 0x7f08, 0x7f04, 0x0000, 0x0000, 0x7f01,
                  0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0xfe01, 0x0000, 0x0000, 0x0000,
                  0xfe01]
    
    let allGames = ["manic.sna", "aticatac.sna", "brucelee.sna",
                    "deathchase.sna", "JetPac.sna", "monty.sna",
                    "spacies.sna", "thehobbit.sna", "jetsetw.sna",
                    "techted.sna", "uridium.sna",
                    "cobra.sna", "cybernoid1.sna", "cybernoid2.sna",
                    "dynadan.sna", "greenberet.sna", "headoverheels.sna",
                    "hypersports.sna", "JetMan.sna", //"ninjaman.sna",
                    "sabre.sna", "starquake.sna"] //, "testz80.sna"]
    
    var colours = [UInt32](repeating: 0, count: 16)
    
    let memory = Memory("48.rom")
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // allows us to use NSView for border colour
        self.view.wantsLayer = true
        
        // Spectrum colour pallette
        var colourIndex = 0
        for colour in colourTable {
            let rComp = UInt32(colour.r) << 8
            let gComp = UInt32(colour.g) << 16
            let bComp = UInt32(colour.b) << 24
            colours[colourIndex] = rComp | gComp | bComp | UInt32(0xff)
            colourIndex = colourIndex + 1
        }
        
        // Precalculate screen and colour rows
        var rowNum = 0
        for row in 0..<24 {
            for pixelRow in 0..<8 {
                let dataByteHigh = 0x40 | (row & 0x18) | (pixelRow % 8)
                let dataByteLow  = ((row & 0x7) << 5)
                
                let address:UInt16 = UInt16((dataByteHigh) << 8) + UInt16(dataByteLow)
                screenRowAddress[rowNum] = address
                
                rowNum = rowNum + 1
            }
            
            attributeRowAddress[row] = 22528 + (32 * UInt16(row))
        }
        
        // Used in bitmap generator
        provider = CGDataProvider(dataInfo: nil, data: bmpData, size: 4, releaseData: {
            (info: UnsafeMutableRawPointer?, data: UnsafeRawPointer, size: Int) -> () in
        })!
        
        z80 = Z80(memory: memory)
        z80.machine = self
        
        DispatchQueue.global().async {
            self.z80.start()
        }
        
        gameIndex = allGames.count  // start at 0
    }
    
    @IBAction func loadNextGame(_ sender: NSButton) {
        gameIndex = gameIndex + 1
        if gameIndex > allGames.count - 1 {
            gameIndex = 0
        }
        
        loadGame(allGames[gameIndex], z80: z80)
    }
    
    func loadGame(_ game: String, z80: Z80) {
        z80.paused = true
        
        // Wait until background thread is paused...
        Thread.sleep(forTimeInterval: 0.01)
        
        if let _ = Loader(game, z80: z80) {
            print("loaded \(game)")
        } else {
            print("couldnt load \(game)")
        }
        
        z80.paused = false
    }
}

extension Spectrum : Machine {
    
    final func input(_ reg: Register, high: UInt8, low: UInt8) {
        
        var byte: UInt8 = 0x00
        
        if low == 0xfe {            // keyboard
            let downKeys = (view as! SpectrumView).keysDown
            
            var keysDown: [UInt16] = []
            for key in downKeys {
                if key < keyMap.count  {
                    if keyMap[key] > 0 {
                        keysDown.append(UInt16(keyMap[key]))
                    }
                }
            }
            
            var keys: Array<UInt8> = [0xbf, 0xbf, 0xbf, 0xbf, 0xbf, 0xbf, 0xbf, 0xbf]
            
            if keysDown.count > 0 {
                for key in keysDown {
                    let row: UInt8 = UInt8(key >> 8)
                    let val: UInt8 = UInt8(key & 0xff)
                    
                    if let keyNum = [0xfe, 0xfd, 0xfb, 0xf7, 0xef, 0xdf, 0xbf, 0x7f].index(of: row) {
                        var thisKey: UInt8 = keys[keyNum]
                        thisKey &= ~val
                        keys[keyNum] = thisKey
                    }
                }
            }
            
            switch high {
            case 0xfe:
                byte = keys[0]
            case 0xfd:
                byte = keys[1]
            case 0xfb:
                byte = keys[2]
            case 0xf7:
                byte = keys[3]
            case 0xef:
                byte = keys[4]
            case 0xdf:
                byte = keys[5]
            case 0xbf:
                byte = keys[6]
            case 0x7f:
                byte = keys[7]
            case 0x7e:
                byte = keys[0] & keys[7]
            case 0x00:
                byte = keys[0] & keys[1] & keys[2] & keys[3] & keys[4] & keys[5] & keys[6] & keys[7]
            default:
                byte = 0xbf
                let value = high ^ 0xff
                var bit:UInt8 = 0x01
                for loop in 0..<8 {
                    if value & bit > 0 {
                        byte = byte & keys[loop]
                    }
                    bit = bit << 1
                }
            }
        } else if low == 0x1f {     // kempston
            let downKeys = (view as! SpectrumView).keysDown
            
            let padKeys = [124, 123, 125, 126, 49]  // cursor keys and space bar
            var bit:  UInt8 = 0x01
            
            for key in padKeys {
                if downKeys.contains(UInt16(key)) {
                    byte |= bit
                }
                bit = bit << 1
            }
        } else if low == 0xff {     // video beam
            if z80.videoRow < 64 || z80.videoRow > 255 {
                byte = 0xff
            } else {
                if z80.ula >= 24 && z80.ula <= 152 {
                    let rowNum = z80.videoRow - 64
                    let attribAddress = 22528 + ((rowNum >> 3) << 5)
                    let col = (z80.ula - 24) >> 2
                    byte = memory.get(attribAddress + UInt16(col & 0xffff))
                } else {
                    byte = 0xff
                }
            }
        } else {
            byte = 0xff
        }
        
        Z80.f.value = (Z80.f.value & Z80.cBit) | Z80.sz53pvTable[byte]
        reg.value = byte
    }
    
    final func output(_ port: UInt8, byte: UInt8) {
        if port == 0xfe {
            let colour = colourTable[byte & 0x07]
            
            DispatchQueue.main.async {
                self.view.layer?.backgroundColor = CGColor(red: CGFloat(colour.r) / 255.0, green: CGFloat(colour.g) / 255.0, blue: CGFloat(colour.b) / 255.0, alpha: 1)
            }
            
            if byte & 0x10 > 0 {
                self.clickCount = self.clickCount + 1
            }
        }
    }
    
    final func beep() {
        if clickCount > 0 {
            print("beep click count \(clickCount)")
        }

        clickCount = 0
    }
    
    var ticksPerFrame: UInt32 {
        return 69888
    }
    
    var audioPacketSize: UInt32 {
        return 79
    }
    
    final func captureRow(_ row: UInt16) {
        var pixelAddress  = screenRowAddress[row]
        var colourAddress = attributeRowAddress[row >> 3]
        
        var index = Int(row << 5)
        for _ in 0..<32 {
            screenCopy[index] = memory.get(pixelAddress)
            colourCopy[index] = memory.get(colourAddress)
            
            pixelAddress = pixelAddress + 1
            colourAddress = colourAddress + 1
            index = index + 1
        }
    }
    
    final func refreshScreen() {        
        
        self.lateLabel.stringValue = "\(z80.lateFrames)"
        
        flashCount = flashCount + 1
        if flashCount == 16 {
            invertColours = !invertColours
            flashCount = 0
        }
        
        var bmpIndex = 0
        
        for index in 0..<192 * 32 {
            let byte   = screenCopy[index]
            let colour = colourCopy[index]
            
//            if byte != screenCopySave[index] || colour != colourCopySave[index] {
//                screenCopySave[index] = byte
//                colourCopySave[index] = colour
            
                let offset:UInt8 = colour & 0x40 > 0 ? 8 : 0
                
                var ink   = colours[(colour & 0x07) + offset]
                var paper = colours[((colour & 0x38) >> 3) + offset]
                
                if colour & 0x80 > 0 && invertColours {
                    paper = colours[(colour & 0x07) + offset]
                    ink   = colours[((colour & 0x38) >> 3) + offset]
                }
                
                bmpData[bmpIndex + 0] = (byte & 0x80) > 0 ? ink : paper
                bmpData[bmpIndex + 1] = (byte & 0x40) > 0 ? ink : paper
                bmpData[bmpIndex + 2] = (byte & 0x20) > 0 ? ink : paper
                bmpData[bmpIndex + 3] = (byte & 0x10) > 0 ? ink : paper
                bmpData[bmpIndex + 4] = (byte & 0x08) > 0 ? ink : paper
                bmpData[bmpIndex + 5] = (byte & 0x04) > 0 ? ink : paper
                bmpData[bmpIndex + 6] = (byte & 0x02) > 0 ? ink : paper
                bmpData[bmpIndex + 7] = (byte & 0x01) > 0 ? ink : paper
//            }
            
            bmpIndex = bmpIndex + 8
        }
        
        if let image = CGImage(width: 256, height: 192, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 1024, space: colourSpace, bitmapInfo: bitmapInfo, provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) {
            spectrumScreen.image = NSImage(cgImage: image, size: .zero)
        }
    }
}

