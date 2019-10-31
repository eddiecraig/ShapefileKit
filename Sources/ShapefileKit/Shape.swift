//
//  Shape.swift
//  ShapefileKit
//
//  Created by Eddie Craig on 08/03/2019.
//  Copyright © 2019 Box Farm Studios. All rights reserved.
//

import Foundation
import MapKit

public class Shape: NSObject {
    
    public enum ShapeType: Int {
        case nullShape = 0
        case point = 1
        case polyLine = 3
        case polygon = 5
        case multipoint = 8
        case pointZ = 11
        case polylineZ = 13
        case polygonZ = 15
        case multipointZ = 18
        case pointM = 21
        case polylineM = 23
        case polygonM = 25
        case multipointM = 28
        case multipatch = 31
        
        var hasBoundingBox: Bool {
            return [ShapeType.polyLine,.polygon,.multipoint,.polylineZ,.polygonZ,.multipointZ,.polylineM,.polygonM,.multipointM,.multipatch].contains(self)
        }
        
        var hasParts: Bool {
            return [ShapeType.polyLine,.polygon,.polylineZ,.polygonZ,.polylineM,.polygonM,.multipatch].contains(self)
        }
        
        var hasPoints: Bool {
            return [ShapeType.polyLine,.polygon,.multipoint,.polylineZ,.polygonZ,.polylineM,.polygonM,.multipatch].contains(self)
        }
        
        var hasZValues: Bool {
            return [ShapeType.polylineZ,.polygonZ,.multipointZ,.multipatch].contains(self)
        }
        
        var hasMValues: Bool {
            return [ShapeType.polylineZ,.polygonZ,.multipointZ,.polylineM,.polygonM,.multipointM,.multipatch].contains(self)
        }
        
        var hasSinglePoint: Bool {
            return [ShapeType.point,.pointZ,.pointM].contains(self)
        }
        
        var hasSingleZ: Bool {
            return [ShapeType.pointZ].contains(self)
        }
        
        var hasSingleM: Bool {
            return [ShapeType.pointZ,.pointM].contains(self)
        }
    }
    
    public init(type:ShapeType = .nullShape) {
        self.shapeType = type
    }
    
    public let shapeType: ShapeType
    
    var coordinates = [CLLocationCoordinate2D]()
    public var exteriorCoordinates: [CLLocationCoordinate2D] {
        let count = parts.count > 1 ? parts[1] : coordinates.count
        return Array(coordinates[0..<count])
    }
    public var interiorCoordinates: [[CLLocationCoordinate2D]]? {
        guard parts.count > 1 else { return nil }
        var interiorCoordinates = [[CLLocationCoordinate2D]]()
        for (i, startIndex) in parts.enumerated() {
            if (i == 0) { continue } // skip over the start point index for the external polygon
            let endIndex = i + 1 < parts.count ? parts[i + 1] : coordinates.count
            interiorCoordinates.append(Array(coordinates[startIndex..<endIndex]))
        }
        return interiorCoordinates
    }
    
    public var exteriorPolygon: MKPolygon { return MKPolygon(coordinates: exteriorCoordinates, count: exteriorCoordinates.count) }
    public var interiorPolygons: [MKPolygon]? { return interiorCoordinates?.map{ MKPolygon(coordinates: $0, count: $0.count) } }
    public var polygon: MKPolygon { return MKPolygon(coordinates: exteriorCoordinates, count: exteriorCoordinates.count, interiorPolygons: interiorPolygons)}
    
    var boundingBox = MKMapRect.null
    private var center: MKMapPoint { return MKMapPoint(x: boundingBox.midX, y: boundingBox.midY) }
    public var parts = [Int]()
    public var partTypes = [Int]()
    public var z = 0.0
    public var m = [Double?]()
    
    public var info = [String : Any]()
}

extension Shape: MKOverlay {
    
    public var coordinate: CLLocationCoordinate2D { return center.coordinate }
    
    public var boundingMapRect: MKMapRect { return boundingBox }
    
    public var title: String? { return info.filter{ $0.value is String }.first?.value as? String }
}
