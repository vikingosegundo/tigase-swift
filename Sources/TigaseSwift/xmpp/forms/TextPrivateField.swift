//
// TextPrivateField.swift
//
// TigaseSwift
// Copyright (C) 2016 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License,
// or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see http://www.gnu.org/licenses/.
//

import Foundation

open class TextPrivateField: Field, SingleField {
    
    open var value: String? {
        get {
            return rawValue
        }
        set {
            self.rawValue = newValue;
        }
    }
    
    public override init?(from: Element) {
        super.init(from: from);
    }
    
    public convenience init(name: String, label: String? = nil, desc: String? = nil, required: Bool = false) {
        let elem = Field.createFieldElement(name: name, type: "text-private", label: label, desc: desc, required: required);
        self.init(from: elem)!;
    }
    
}
