//
// MessageModule.swift
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
 Module provides features responsible for handling messages
 */
open class MessageModule: XmppModule, ContextAware, Initializable {
    /// ID of module for lookup in `XmppModulesManager`
    public static let ID = "message";
    
    public let id = ID;
    
    public let criteria = Criteria.name("message", types:[StanzaType.chat, StanzaType.normal, nil, StanzaType.headline, StanzaType.error]);
    
    public let features = [String]();
    
    /// Instance of `ChatManager`
    open var chatManager:ChatManager!;
    
    open var context:Context!
    
    public init() {
        
    }
    
    /**
     Create chat for message exchange
     - parameter jid: recipient of messages
     - parameter thread: thread id of chat
     - returns: instance of `Chat`
     */
    open func createChat(with jid:JID, thread: String? = UIDGenerator.nextUid) -> Chat? {
        return chatManager.createChat(with: jid, thread: thread);
    }
    
    open func initialize() {
        if chatManager == nil {
            chatManager = DefaultChatManager(context: context);
        }
    }
    
    open func process(stanza: Stanza) {
        let message = stanza as! Message;
        _ = processMessage(message, interlocutorJid: message.from);
    }
    
    open func processMessage(_ message: Message, interlocutorJid: JID?, fireEvents: Bool = true) -> Chat? {
        guard let jid = interlocutorJid, let chat = getOrCreateChatForProcessing(message: message, interlocutorJid: jid) else {
            fire(MessageReceivedEvent(sessionObject: context.sessionObject, chat: nil, message: message));
            return nil;
        }
        
        if chat.jid != jid {
            chat.jid = jid;
        }
        if chat.thread != message.thread {
            chat.thread = message.thread;
        }
        
        if fireEvents {
            fire(MessageReceivedEvent(sessionObject: context.sessionObject, chat: chat, message: message));
        }
        
        return chat;
    }
    
    fileprivate func getOrCreateChatForProcessing(message: Message, interlocutorJid: JID) -> Chat? {
        if message.body != nil && (message.findChild(name: "x", xmlns: "jabber:x:conference") == nil || !context.modulesManager.hasModule(MucModule.ID)) {
            return chatManager.getChatOrCreate(with: interlocutorJid, thread: message.thread);
        } else {
            return chatManager.getChat(with: interlocutorJid, thread: message.thread);
        }
    }
    
    /**
     Send message as part of message exchange
     - parameter chat: instance of Chat
     - parameter body: text of message to send
     - parameter type: type of message
     - parameter subject: subject of message
     - parameter additionalElements: array of additional elements to add to message
     */
    open func sendMessage(in chat:Chat, body:String, type:StanzaType = StanzaType.chat, subject:String? = nil, additionalElements:[Element]? = nil) -> Message {
        let msg = chat.createMessage(body, type: type, subject: subject, additionalElements: additionalElements);
        context.writer?.write(msg);
        return msg;
    }
    
    func fire(_ event:Event) {
        context.eventBus.fire(event);
    }
    
    /// Event fired when Chat is created/opened
    open class ChatCreatedEvent: Event {
        /// Identifier of event which should be used during registration of `EventHandler`
        public static let TYPE = ChatCreatedEvent();
        
        public let type = "ChatCreatedEvent";
        /// Instance of `SessionObject` allows to tell from which connection event was fired
        public let sessionObject:SessionObject!;
        /// Instance of opened chat
        public let chat:Chat!;
        
        fileprivate init() {
            self.sessionObject = nil;
            self.chat = nil;
        }
        
        public init(sessionObject:SessionObject, chat:Chat) {
            self.sessionObject = sessionObject;
            self.chat = chat;
        }
    }

    /// Event fired when Chat is closed
    open class ChatClosedEvent: Event {
        /// Identifier of event which should be used during registration of `EventHandler`
        public static let TYPE = ChatClosedEvent();
        
        public let type = "ChatClosedEvent";
        /// Instance of `SessionObject` allows to tell from which connection event was fired
        public let sessionObject:SessionObject!;
        /// Instance of closed chat
        public let chat:Chat!;
        
        fileprivate init() {
            self.sessionObject = nil;
            self.chat = nil;
        }
        
        public init(sessionObject:SessionObject, chat:Chat) {
            self.sessionObject = sessionObject;
            self.chat = chat;
        }
    }
    
    /// Event fired when message is received
    open class MessageReceivedEvent: Event {
        /// Identifier of event which should be used during registration of `EventHandler`
        public static let TYPE = MessageReceivedEvent();
        
        public let type = "MessageReceivedEvent";
        /// Instance of `SessionObject` allows to tell from which connection event was fired
        public let sessionObject:SessionObject!;
        /// Instance of chat to which this message belongs
        public let chat:Chat?;
        /// Received message
        public let message:Message!;
        
        fileprivate init() {
            self.sessionObject = nil;
            self.chat = nil;
            self.message = nil;
        }
        
        public init(sessionObject:SessionObject, chat:Chat?, message:Message) {
            self.sessionObject = sessionObject;
            self.chat = chat;
            self.message = message;
        }
    }
    
}
