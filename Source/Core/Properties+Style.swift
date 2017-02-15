//
//  Properties+Style.swift
//  Reactant
//
//  Created by Filip Dolnik on 15.02.17.
//  Copyright © 2017 Brightify. All rights reserved.
//

extension Properties.Style {
    
    public static func style<T>(for type: T.Type) -> Property<(T) -> Void> {
        return Property<(T) -> Void>(defaultValue: { _ in })
    }
}
