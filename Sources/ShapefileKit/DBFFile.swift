//
//  DBFFile.swift
//  ShapefileKit
//
//  Created by Eddie Craig on 08/03/2019.
//  Copyright © 2019 Box Farm Studios. All rights reserved.
//
//  dBase III+ specs http://www.oocities.org/geoff_wass/dBASE/GaryWhite/dBASE/FAQ/qformt.htm#A
//  extended with dBase IV 2.0 'F' type

import Foundation

class DBFFile {
    
    struct FieldDescriptor {
        
        enum FieldType: Character {
            case character = "C"
            case date = "D"
            case floating = "F"
            case numeric = "N"
            case logical = "L"
            case memo = "M"
        }
        
        init(data: Data) throws {
            let fieldDesc = try unpack("<11sc4xBB14x", data)
            self.name = fieldDesc[0] as! String
            self.type = FieldType.init(rawValue: Character(fieldDesc[1] as! String))!
            self.length = fieldDesc[2] as! Int
            self.count = fieldDesc[3] as! Int
        }
        
        init(name: String, type: FieldType, length: Int, count: Int) {
            self.name = name
            self.type = type
            self.length = length
            self.count = count
        }
        
        let name: String
        let type: FieldType
        let length: Int
        let count: Int
    }
    
    static let pathExtension = "dbf"
    
    typealias DBFRecord = [Any]
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()
    
    private var fileHandle : FileHandle
    let numberOfRecords: Int
    let shapeType: Shape.ShapeType
    let lastUpdate: Date
    var fields: [FieldDescriptor]!
    private let headerLength: Int
    private var recordLengthFromHeader: Int
    private let recordFormat : String!
    
    init(path: URL) throws {
        self.fileHandle = try FileHandle(forReadingFrom: path)
        self.fileHandle.seek(toFileOffset: 0)
        
        let a = try unpack("<BBBBIHH20x", self.fileHandle.readData(ofLength: 32))
        
        self.shapeType = Shape.ShapeType.init(rawValue: a[0] as! Int) ?? .nullShape
        var lastUpdateComponents = DateComponents()
        let YY = a[1] as! Int
        lastUpdateComponents.year = YY > 80 ? 1900 + YY : 2000 + YY
        lastUpdateComponents.month = a[2] as? Int
        lastUpdateComponents.day = a[3] as? Int
        self.lastUpdate = Calendar.init(identifier: .gregorian).date(from: lastUpdateComponents) ?? Date.distantPast
        self.numberOfRecords = a[4] as! Int
        self.headerLength = a[5] as! Int
        self.recordLengthFromHeader = a[6] as! Int
        
        print("-- shapeType:\(shapeType)")
        print("-- lastUpdate:\(DateFormatter.localizedString(from: lastUpdate, dateStyle: .medium, timeStyle: .none))")
        print("-- numberOfRecords:\(numberOfRecords)")
        
        let numFields = (headerLength - 33) / 32
        
        self.fields = []
        for _ in 0..<numFields {
            let fieldDesc = try FieldDescriptor(data: self.fileHandle.readData(ofLength: 32))
            self.fields.append(fieldDesc)
        }
        
        let terminator = try unpack("<s", self.fileHandle.readData(ofLength: 1))[0] as! String
        assert(terminator == "\r", "unexpected terminator")
        
        self.fields.insert(FieldDescriptor.init(name: "DeletionFlag", type: .character, length: 1, count: 0), at: 0)
        
        let sizes = fields.map{ $0.length }
        let totalSize = sizes.reduce(0, +)
        self.recordFormat = "<" + sizes.map( { String($0) + "s" } ).joined(separator: "")
        
        if totalSize != recordLengthFromHeader {
            print("-- error: record size declated in header \(recordLengthFromHeader) != record size declared in fields format \(totalSize)")
            recordLengthFromHeader = totalSize
        }
    }
    
    deinit {
        self.fileHandle.closeFile()
    }
    
    
    fileprivate func recordAtOffset(_ offset:UInt64) throws -> DBFRecord {
        
        self.fileHandle.seek(toFileOffset: offset)
        
        guard let recordContents = try! unpack(self.recordFormat, self.fileHandle.readData(ofLength: self.recordLengthFromHeader), .ascii) as? [NSString] else {
            print("bad record contents")
            return []
        }
        
        let isDeletedRecord = recordContents[0] != " "
        if isDeletedRecord { return [] }
        
        assert(self.fields.count == recordContents.count)
        
        var record : DBFRecord = []
        
        for (fields, value) in Array(zip(self.fields, recordContents)) {
            
            if fields.name == "DeletionFlag" { continue }
            
            let trimmedValue = value.trimmingCharacters(in: CharacterSet.whitespaces)
            
            if trimmedValue.count == 0 {
                record.append("")
                continue
            }
            
            var v : Any = ""
            
            switch fields.type {
            case .numeric: // Numeric, Number stored as a string, right justified, and padded with blanks to the width of the field.
                if trimmedValue == "" {
                    v = trimmedValue
                } else if fields.count > 0 || trimmedValue.contains(".") {
                    v = Double(trimmedValue)!
                } else {
                    v = Int(trimmedValue)!
                }
            case .floating: // Float - since dBASE IV 2.0
                v = Double(trimmedValue)!
            case .date: // Date, 8 bytes - date stored as a string in the format YYYYMMDD.
                v = dateFormatter.date(from: trimmedValue)!
            case .character: // Character, All OEM code page characters - padded with blanks to the width of the field.
                v = trimmedValue
            case .logical: // Logical, 1 byte - initialized to 0x20 (space) otherwise T or F. ? Y y N n T t F f (? when not initialized).
                v = ["T","t","Y","y"].contains(trimmedValue)
            case .memo: // Memo, a string, 10 digits (bytes) representing a .DBT block number. The number is stored as a string, right justified and padded with blanks. All OEM code page characters (stored internally as 10 digits representing a .DBT block number).
                v = trimmedValue
            }
            
            record.append(v)
        }
        
        return record
    }
    
    subscript(i:Int) -> DBFRecord {
        return try! recordAtIndex(i)
    }
    
    func recordAtIndex(_ i:Int = 0) throws -> DBFRecord {
        
        self.fileHandle.seek(toFileOffset: 0)
        assert(headerLength != 0)
        let offset = headerLength + (i * recordLengthFromHeader)
        return try self.recordAtOffset(UInt64(offset))
    }
    
    func recordGenerator() throws -> AnyIterator<DBFRecord> {
        
        if (numberOfRecords == 0) {
            return AnyIterator {
                print("-- unknown number of records")
                return nil
            }
        }
        
        var i = 0
        
        return AnyIterator {
            if i >= self.numberOfRecords { return nil}
            let rec = try! self.recordAtIndex(i)
            i += 1
            return rec
        }
    }
    
    func allRecords() throws -> [DBFRecord] {
        
        var records : [DBFRecord] = []
        
        let generator = try self.recordGenerator()
        
        while let r = generator.next() {
            records.append(r)
        }
        
        return records
    }
}
