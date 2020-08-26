//
// Event.swift
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

/**
 Event protocol needs to be implemented by every event fired using `EventBus`
 */
public protocol Event: class {
    
    /// Unique identifier of event class
    var type:String { get }
    
}

/**
 Protocol to mark events for which handlers must be called only one at the time
 */
public protocol SerialEvent {
    
}

public func ==(lhs:Event, rhs:Event) -> Bool {
    return lhs === rhs || lhs.type == rhs.type;
}

public func ==(lhs:[Event], rhs:[Event]) -> Bool {
    guard lhs.count == rhs.count else {
        return false;
    }
    
    for le in lhs {
        if rhs.contains(where: {(re) -> Bool in
            return le == re;
        }) {
            // this is ok
        } else {
            return false;
        }
    }
    return true;
}
