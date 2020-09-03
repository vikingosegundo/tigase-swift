//
// MessageDeliveryReceiptsModule.swift
//
// TigaseSwift
// Copyright (C) 2017 "Tigase, Inc." <office@tigase.com>
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

open class ChatMarkerModule: XmppModule, ContextAware {
    
    /// Namespace used by Message Carbons
    public static let XMLNS = "urn:xmpp:chat-markers:0";
    /// ID of module for lookup in `XmppModulesManager`
    public static let ID = XMLNS;
    
    public let id = XMLNS;
    
    public let criteria = Criteria.name("message").add(Criteria.xmlns(XMLNS));
    
    public let features = [XMLNS];
    
    open var context: Context!

    public init() {
        
    }
    
    open func sendDisplayedEvent(id: String, to: JID){

        let response = Message();
        response.type = .chat
        response.to = to
        response.messageChatMarker = ChatMarkerEnum.displayed(id: id)
        response.hints = [.store]
        context.writer?.write(response)
    }
    
    open func process(stanza: Stanza) throws {
        guard let message = stanza as? Message, stanza.type != StanzaType.error else {
            return;
        }
        
        guard let delivery = message.messageChatMarker else {
            return;
        }
        
        switch delivery {
        case .request:
            guard let id = message.id, message.from != nil, message.type != .groupchat else {
                return;
            }
            // need to send response/ack
            let response = Message();
            response.type = message.type;
            response.to = message.from;
            response.messageChatMarker = ChatMarkerEnum.received(id: id);
            response.hints = [.store];
            context.writer?.write(response);
            break;
        case .received(let id):
            // need to notify client - fire event
            context.eventBus.fire(ChatMarkerReceivedEvent(sessionObject: context.sessionObject, message: message, messageId: id));
            break;
        case .displayed(let id):
            context.eventBus.fire(ChatMarkerDisplayedEvent(sessionObject: context.sessionObject, message: message, messageId: id));
            break;
        }
       
        
    }
    
    /// Event fired when message delivery confirmation is received
    open class ChatMarkerReceivedEvent: Event {
        /// Identifier of event which should be used during registration of `EventHandler`
        public static let TYPE = ChatMarkerReceivedEvent();
        
        public let type = "ChatMarkerReceivedEvent";
        /// Instance of `SessionObject` allows to tell from which connection event was fired
        public let sessionObject:SessionObject!;
        /// Received message
        public let message:Message!;
        /// ID of confirmed message
        public let messageId: String!;
        
        
        fileprivate init() {
            self.sessionObject = nil;
            self.messageId = nil;
            self.message = nil;
        }
        
        public init(sessionObject:SessionObject, message:Message, messageId: String) {
            self.sessionObject = sessionObject;
            self.message = message;
            self.messageId = messageId;
        }
    }
    
    /// Event fired when message displayed cofnirmation is received
    open class ChatMarkerDisplayedEvent: Event {
        /// Identifier of event which should be used during registration of `EventHandler`
        public static let TYPE = ChatMarkerDisplayedEvent();
        
        public let type = "ChatMarkerDisplayedEvent";
        /// Instance of `SessionObject` allows to tell from which connection event was fired
        public let sessionObject:SessionObject!;
        /// Received message
        public let message:Message!;
        /// ID of confirmed message
        public let messageId: String!;
        
        
        fileprivate init() {
            self.sessionObject = nil;
            self.messageId = nil;
            self.message = nil;
        }
        
        public init(sessionObject:SessionObject, message:Message, messageId: String) {
            self.sessionObject = sessionObject;
            self.message = message;
            self.messageId = messageId;
        }
    }
}

extension Message {
    
    open var messageChatMarker: ChatMarkerEnum? {
        get {
            if let el = element.findChild(xmlns: ChatMarkerModule.XMLNS) {
                switch el.name {
                case "request":
                    return ChatMarkerEnum.request;
                case "received":
                    if let id = el.getAttribute("id") {
                        return ChatMarkerEnum.received(id: id);
                    }
                case "displayed":
                    if let id = el.getAttribute("id") {
                        return ChatMarkerEnum.displayed(id: id);
                    }
                default:
                    break;
                }
            }
            return nil;
        }
        set {
            element.getChildren(xmlns: ChatMarkerModule.XMLNS).forEach { (el) in
                element.removeChild(el);
            }
            if newValue != nil {
                if self.id == nil {
                    self.id = UUID().description;
                }
                switch newValue! {
                case .request:
                    element.addChild(Element(name: "request", xmlns: ChatMarkerModule.XMLNS));
                case .received(let id):
                    let el = Element(name: "received", xmlns: ChatMarkerModule.XMLNS);
                    el.setAttribute("id", value: id);
                    element.addChild(el);
                case .displayed(let id):
                    let el = Element(name: "displayed", xmlns: ChatMarkerModule.XMLNS);
                    el.setAttribute("id", value: id);
                    element.addChild(el);
                }
            }
        }
    }
    
}

public enum ChatMarkerEnum {
    case request
    case received(id: String)
    case displayed(id: String)
    
    func getMessageId() -> String? {
        switch self {
        case .received(let id):
            return id;
        case .displayed(let id):
            return id;
        default:
            return nil;
        }
    }
}
