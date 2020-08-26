//
// Channel.swift
//
// TigaseSwift
// Copyright (C) 2020 "Tigase, Inc." <office@tigase.com>
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

open class Channel: ChatProtocol {
    
    public let allowFullJid = false;

    public let channelJid: BareJID;
    
    open var jid: JID {
        get {
            return JID(channelJid);
        }
        set {
            // nothing to do..
        }
    }
    
    public var nickname: String?;
    public let participantId: String;
    public private(set) var state: State;
    open var lastMessageDate: Date?;
    open private(set) var participants: [String:MixParticipant] = [:];
    open private(set) var permissions: Set<Permission>?;
    
    public init(channelJid: BareJID, participantId: String, nickname: String?, state: State) {
        self.channelJid = channelJid;
        self.participantId = participantId;
        self.nickname = nickname;
        self.state = state;
    }
    
    open func has(permission: Permission) -> Bool {
        return permissions?.contains(permission) ?? false;
    }
    
    open func update(participants: [MixParticipant]) {
        self.participants = Dictionary(uniqueKeysWithValues: participants.map { ($0.id, $0) });
    }
    
    open func update(participant: MixParticipant) {
        self.participants[participant.id] = participant;
    }
    
    open func update(info: ChannelInfo) {
        
    }
    
    open func update(state: State) -> Bool {
        guard self.state != state else {
            return false;
        }
        self.state = state;
        return true;
    }
    
    open func update(permissions: Set<Permission>) {
        self.permissions = permissions;
    }
    
    open func participantLeft(participantId: String) -> MixParticipant? {
        return self.participants.removeValue(forKey: participantId);
    }
    
    open func createMessage(_ body: String?) -> Message {
        let msg = Message();
        msg.to = jid;
        msg.type = StanzaType.groupchat;
        msg.body = body;
        let id = UUID().uuidString;
        msg.id = id;
        msg.originId = id;
        return msg;
    }
    
    public enum State: Int {
        case left = 0
        case joined = 1
    }
    
    public enum Permission {
        case changeConfig
        case changeInfo
        case changeAvatar
    }

}
