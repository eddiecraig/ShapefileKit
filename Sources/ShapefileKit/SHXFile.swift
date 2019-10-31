//
//  SHXFile.swift
//  ShapefileKit
//
//  Created by Eddie Craig on 10/03/2019.
//  Copyright © 2019 Box Farm Studios. All rights reserved.
//

import Foundation

class SHXFile {

    static let pathExtension = "shx"
    
    private var fileHandle: FileHandle
    var shapeOffsets = [UInt64]()
    var shapeCount : Int { return shapeOffsets.count }
    
    init(path: URL) throws {
        self.fileHandle = try FileHandle(forReadingFrom: path)
        
        // read number of records
        fileHandle.seek(toFileOffset: 24)
        let a = try unpack(">i", fileHandle.readData(ofLength: 4))
        let halfLength = a[0] as! Int
        let shxRecordLength = (halfLength * 2) - 100
        var numRecords = shxRecordLength / 8
        
        // measure number of records
        fileHandle.seekToEndOfFile()
        let eof = fileHandle.offsetInFile
        let lengthWithoutHeaders = eof - 100
        let numRecordsMeasured = Int(lengthWithoutHeaders / 8)
        
        // pick measured number of records if different
        if numRecords != numRecordsMeasured {
            print("-- numRecords \(numRecords) != numRecordsMeasured \(numRecordsMeasured) -> use numRecordsMeasured")
            numRecords = numRecordsMeasured
        }
        
        // read the offsets
        for offset in stride(from: UInt64(100), to: UInt64(100 + 8 * numRecords), by: 8) {
            fileHandle.seek(toFileOffset: offset)
            let b = try unpack(">i", fileHandle.readData(ofLength: 4))
            let i = UInt64(exactly: b[0] as! Int)!
            self.shapeOffsets.append(i * 2)
        }
    }
    
    deinit {
        self.fileHandle.closeFile()
    }
}
