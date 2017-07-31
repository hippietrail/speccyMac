//
//  Z80+dd.swift
//  speccyMac
//
//  Created by John Ward on 21/07/2017.
//  Copyright © 2017 John Ward. All rights reserved.
//

import Foundation

extension Z80 {
    
    final func ddprefix(opcode: UInt8, first: UInt8, second: UInt8) throws {
        
        let word16 = (UInt16(second) << 8) + UInt16(first)
        let instruction = ddprefixedOps[Int(opcode)]
        
        let offset = UInt16(first)
        
        switch opcode {
            
        case 0x21:  // ld ixy, nnnn
            ixy = word16
            
        case 0x35:  // dec (ixy + d)
            let paired = ixy + offset
            memory.set(paired, byte: memory.get(paired))
            
        default:
            throw NSError(domain: "z80+dd", code: 1, userInfo: ["opcode" : String(opcode, radix: 16, uppercase: true), "instruction" : instruction.opCode, "pc" : pc])
        }
        
//        print("\(pc) : \(instruction.opCode)")
        
        pc = pc &+ instruction.length
        
        let ts = instruction.tStates
        incCounters(amount: ts)
        
        incR()
        incR()
    }
}
