//
// MixModule.swift
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

open class MixModule: XmppModule, ContextAware, EventHandler, RosterAnnotationAwareProtocol {
    func prepareRosterGetRequest(queryElem el: Element) {
        el.addChild(Element(name: "annotate", xmlns: "urn:xmpp:mix:roster:0"));
    }
    
    func process(rosterItemElem el: Element) -> RosterItemAnnotation? {
        guard el.name == "channel" && el.xmlns == "urn:xmpp:mix:roster:0", let id = el.getAttribute("participant-id") else {
            return nil;
        }
        return RosterItemAnnotation(type: "mix", values: ["participant-id": id]);
    }
    
    public static let CORE_XMLNS = "urn:xmpp:mix:core:1";
    public static let ID = "mix";
    public static let PAM2_XMLNS = "urn:xmpp:mix:pam:2";
    
    public let id: String = MixModule.ID;
    
    public let criteria: Criteria = Criteria.or(
        Criteria.name("message", types: [.groupchat], containsAttribute: "from").add(Criteria.name("mix", xmlns: MixModule.CORE_XMLNS)),
        Criteria.name("message", types: [.error], containsAttribute: "from")
    );
    
    public let features: [String] = [CORE_XMLNS];

    public var context: Context! {
        didSet {
            oldValue?.eventBus.unregister(handler: self, for: [RosterModule.ItemUpdatedEvent.TYPE, PubSubModule.NotificationReceivedEvent.TYPE]);
            context?.eventBus.register(handler: self, for: [RosterModule.ItemUpdatedEvent.TYPE, PubSubModule.NotificationReceivedEvent.TYPE]);
        }
    }
    
    public let channelManager: ChannelManager;
    
    public var isPAM2SupportAvailable: Bool {
        let accountFeatures: [String] = context.sessionObject.getProperty(DiscoveryModule.ACCOUNT_FEATURES_KEY) ?? [];
        return accountFeatures.contains(MixModule.PAM2_XMLNS);
    }
    
    public init(channelManager: ChannelManager) {
        self.channelManager = channelManager;
    }
    
    open func create(channel: String?, at componentJid: BareJID, completionHandler: @escaping (Result<BareJID,ErrorCondition>)->Void) {
        guard componentJid.localPart == nil else {
            completionHandler(.failure(.bad_request));
            return;
        }
        
        let iq = Iq();
        iq.to = JID(componentJid);
        iq.type = .set;
        let createEl = Element(name: "create", xmlns: MixModule.CORE_XMLNS);
        if channel != nil {
            iq.setAttribute("channel", value: channel);
        }
        iq.addChild(createEl);
        context.writer?.write(iq, completionHandler: { result in
            switch result {
            case .success(let response):
                if let channel = response.findChild(name: "create", xmlns: MixModule.CORE_XMLNS)?.getAttribute("channel") {
                    completionHandler(.success(BareJID(localPart: channel, domain: componentJid.domain)));
                } else {
                    completionHandler(.failure(.unexpected_request));
                }
            case .failure(let errorCondition, let response):
                completionHandler(.failure(errorCondition));
            }
        });
    }
        
    open func destroy(channel channelJid: BareJID, completionHandler: @escaping (Result<Void,ErrorCondition>)->Void) {
        guard channelJid.localPart != nil else {
            completionHandler(.failure(.bad_request));
            return;
        }
        
        let iq = Iq();
        iq.to = JID(channelJid.domain);
        iq.type = .set;
        let createEl = Element(name: "destroy", xmlns: MixModule.CORE_XMLNS);
        iq.setAttribute("channel", value: channelJid.localPart);
        iq.addChild(createEl);
        context.writer?.write(iq, completionHandler: { result in
            switch result {
            case .success(let response):
                completionHandler(.success(Void()));
            case .failure(let errorCondition, let response):
                completionHandler(.failure(errorCondition));
            }
        });
    }
    
    open func join(channel channelJid: BareJID, withNick nick: String?, subscribeNodes nodes: [String] = ["urn:xmpp:mix:nodes:messages", "urn:xmpp:mix:nodes:participants", "urn:xmpp:mix:nodes:info"], completionHandler: @escaping (AsyncResult<Stanza>) -> Void) {
        if isPAM2SupportAvailable {
            let iq = Iq();
            iq.to = JID(context.sessionObject.userBareJid!);
            iq.type = .set;
            let clientJoin = Element(name: "client-join", xmlns: MixModule.PAM2_XMLNS);
            clientJoin.setAttribute("channel", value: channelJid.stringValue);
            clientJoin.addChild(createJoinEl(withNick: nick, withNodes: nodes));
            iq.addChild(clientJoin);
            
            context.writer?.write(iq, completionHandler: { result in
                switch result {
                case .success(let response):
                    if let joinEl = response.findChild(name: "client-join", xmlns: MixModule.PAM2_XMLNS)?.findChild(name: "join", xmlns: MixModule.CORE_XMLNS) {
                        if let resultJid = joinEl.getAttribute("jid"), let idx = resultJid.firstIndex(of: "#") {
                            let participantId = String(resultJid[resultJid.startIndex..<idx]);
                            let jid = BareJID(String(resultJid[resultJid.index(after: idx)..<resultJid.endIndex]));
                            self.channelJoined(channelJid: jid, participantId: participantId, nick: joinEl.findChild(name: "nick")?.value);
                        } else if let participantId = joinEl.getAttribute("id") {
                            self.channelJoined(channelJid: channelJid, participantId: participantId, nick: joinEl.findChild(name: "nick")?.value);
                        }
                    }
                default:
                    break;
                }
                completionHandler(result);
            });
        } else {
            let iq = Iq();
            iq.to = JID(channelJid);
            iq.type = .set;
            iq.addChild(createJoinEl(withNick: nick, withNodes: nodes));
            context.writer?.write(iq, completionHandler: { result in
                switch result {
                case .success(let response):
                    if let joinEl = response.findChild(name: "join", xmlns: MixModule.CORE_XMLNS), let participantId = joinEl.getAttribute("id") {
                        self.channelJoined(channelJid: channelJid, participantId: participantId, nick: joinEl.findChild(name: "nick")?.value);
                    }
                default:
                    break;
                }
                completionHandler(result);
            });
        }
    }
    
    open func leave(channel: Channel, completionHandler: @escaping (AsyncResult<Stanza>)->Void) {
        if isPAM2SupportAvailable {
            let iq = Iq();
            iq.to = JID(context.sessionObject.userBareJid!);
            iq.type = .set;
            let clientLeave = Element(name: "client-leave", xmlns: MixModule.PAM2_XMLNS);
            clientLeave.setAttribute("channel", value: channel.channelJid.stringValue);
            iq.addChild(Element(name: "leave", xmlns: MixModule.CORE_XMLNS));
            
            context.writer?.write(iq, completionHandler: completionHandler);
        } else {
            let iq = Iq();
            iq.to = channel.jid;
            iq.type = .set;
            iq.addChild(Element(name: "leave", xmlns: MixModule.CORE_XMLNS));
            context.writer?.write(iq, completionHandler: completionHandler);
        }
    }
    
    open func channelJoined(channelJid: BareJID, participantId: String, nick: String?) {
        _ = self.channelManager.createChannel(jid: channelJid, participantId: participantId, nick: nick);
        // TODO: retrieve participants? and our own nick..
        // should we do that on "channel created event"?
    }
    
    -- do we need channel left? so we could actually close it??
    -- we may want to add "status" to the channel, to know if we are in participants or not..
    
    open func createJoinEl(withNick nick: String?, withNodes nodes: [String]) -> Element {
        let joinEl = Element(name: "join", xmlns: MixModule.CORE_XMLNS);
        joinEl.addChildren(nodes.map({ Element(name: "subscribe", attributes: ["node": $0]) }));
        if let nick = nick {
            joinEl.addChild(Element(name: "nick", cdata: nick));
        }
        return joinEl;
    }
    
    open func process(stanza: Stanza) throws {
        switch stanza {
        case let message as Message:
            // we have received groupchat message..
            guard let channel = channelManager.channel(for: message.from!.bareJid) else {
                return;
            }
            self.context.eventBus.fire(MessageReceivedEvent(sessionObject: self.context.sessionObject, message: message, channel: channel, nickname: message.mix?.nickname, senderJid: message.mix?.jid, timestamp: message.delay?.stamp ?? Date()));
        default:
            break;
        }
    }
    
    open func retrieveParticipants(for channel: Channel, completionHandler: @escaping (ParticipantsResult)->Void) {
        guard let pubsubModule: PubSubModule = context.modulesManager.getModule(PubSubModule.ID) else {
            completionHandler(.failure(errorCondition: ErrorCondition.undefined_condition, pubsubErrorCondition: nil, errorText: nil));
            return;
        }
        
        pubsubModule.retrieveItems(from: channel.channelJid, for: "urn:xmpp:mix:nodes:participants", completionHandler: { result in
            switch result {
            case .success(let response, let node, let items, let rsm):
                let participants = items.map({ (item) -> MixParticipant? in
                    return MixParticipant(from: item);
                }).filter({ $0 != nil }).map({ $0! });
                let oldParticipants = channel.participants.values;
                let left = oldParticipants.filter({ old in !participants.contains(where: { new in new.id == old.id})});
                if let ownParticipant = participants.first(where: { (participant) -> Bool in
                    return participant.id == channel.participantId
                }) {
                    self.channelManager.update(channel: channel, nick: ownParticipant.id);
                }
                channel.update(participants: participants);
                self.context.eventBus.fire(ParticipantsChangedEvent(sessionObject: self.context.sessionObject, channel: channel, joined: participants, left: left));
                completionHandler(.success(participants: participants));
            case .failure(let errorCondition, let pubsubErrorCondition, let response):
                completionHandler(.failure(errorCondition: errorCondition, pubsubErrorCondition: pubsubErrorCondition, errorText: response?.errorText));
            }
        })
    }
    
    open func handle(event: Event) {
        switch event {
        case let e as RosterModule.ItemUpdatedEvent:
            // react on add/remove channel in the roster
            guard isPAM2SupportAvailable, let ri = e.rosterItem else {
                return;
            }
            
            switch e.action {
            case .removed:
                guard let channel = channelManager.channel(for: ri.jid.bareJid) else {
                    return;
                }
                _ = self.channelManager.close(channel: channel);
            default:
                guard let annotation = ri.annotations.first(where: { item -> Bool in
                    return item.type == "urn:xmpp:mix:roster:0";
                }), let participantId = annotation.values["participant-id"] else {
                    return;
                }
                
                self.channelJoined(channelJid: ri.jid.bareJid, participantId: participantId, nick: nil);
            }
            break;
        case let e as PubSubModule.NotificationReceivedEvent:
            guard let from = e.message.from?.bareJid, let node = e.nodeName, let channel = channelManager.channel(for: from) else {
                return;
            }

            switch node {
            case "urn:xmpp:mix:nodes:participants":
                switch e.itemType {
                case "item":
                    if let item = e.item, let participant = MixParticipant(from: item) {
                        if participant.id == channel.participantId {
                            _ = self.channelManager.update(channel: channel, nick: participant.nickname);
                        }
                        channel.update(participant: participant);
                        self.context.eventBus.fire(ParticipantsChangedEvent(sessionObject: context.sessionObject, channel: channel, joined: [participant]));
                    }
                case "retract":
                    if let id = e.itemId {
                        if let participant = channel.participantLeft(participantId: id) {
                            self.context.eventBus.fire(ParticipantsChangedEvent(sessionObject: context.sessionObject, channel: channel, left: [participant]));
                        }
                    }
                default:
                    break;
                }
            default:
                break;
            }
        default:
            break;
        }
    }
    
    
    /// Event fired when received message in room
    open class MessageReceivedEvent: Event {
        /// Identifier of event which should be used during registration of `EventHandler`
        public static let TYPE = MessageReceivedEvent();
        
        public let type = "MixModuleMessageReceivedEvent";
        /// Instance of `SessionObject` allows to tell from which connection event was fired
        public let sessionObject: SessionObject!;
        /// Received message
        public let message: Message!;
        /// Room which delivered message
        public let channel: Channel!;
        /// Nickname of message sender
        public let nickname: String?;
        /// Sender real JID
        public let senderJid: BareJID?;
        /// Timestamp of message
        public let timestamp: Date!;
        
        init() {
            self.sessionObject = nil;
            self.message = nil;
            self.channel = nil;
            self.nickname = nil;
            self.senderJid = nil;
            self.timestamp = nil;
        }
        
        public init(sessionObject: SessionObject, message: Message, channel: Channel, nickname: String?, senderJid: BareJID?, timestamp: Date) {
            self.sessionObject = sessionObject;
            self.message = message;
            self.channel = channel;
            self.nickname = nickname;
            self.senderJid = senderJid;
            self.timestamp = timestamp;
        }
        
    }

    /// Event fired when received message in room
    open class ParticipantsChangedEvent: Event {
        
        public static let TYPE = ParticipantsChangedEvent();
        public let type = "MixModuleParticipantChangedEvent";
        
        public let sessionObject: SessionObject!;
        public let channel: Channel!;
        public let joined: [MixParticipant];
        public let left: [MixParticipant];
        
        init() {
            self.sessionObject = nil;
            self.channel = nil;
            self.joined = [];
            self.left = [];
        }
        
        public init(sessionObject: SessionObject, channel: Channel, joined: [MixParticipant] = [], left: [MixParticipant] = []) {
            self.sessionObject = sessionObject;
            self.channel = channel;
            self.joined = joined;
            self.left = left;
        }
        
        public enum Action {
            case joined
            case left
        }
    }
    
    public enum ParticipantsResult {
        case success(participants: [MixParticipant])
        case failure(errorCondition: ErrorCondition, pubsubErrorCondition: PubSubErrorCondition?, errorText: String?)
    }
}