//
// ConnectionConfiguration.swift
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

/// Helper class to make it possible to set connection properties in easy way
open class ConnectionConfiguration {
    
    var sessionObject:SessionObject!;
    
    init(_ sessionObject:SessionObject) {
        self.sessionObject = sessionObject;
    }
    
    /**
     Set domain as domain to which we should connect - will be used if `userJid` is not set
     - parameter domain: domain to connect to
     */
    open func setDomain(_ domain: String?) {
        self.sessionObject.setUserProperty(SessionObject.DOMAIN_NAME, value: domain);
    }
    
    /**
     Set jid of user as which we should connect
     - parameter jid: jid
     */
    open func setUserJID(_ jid:BareJID?) {
        self.sessionObject.setUserProperty(SessionObject.USER_BARE_JID, value: jid);
        setDomain(nil);
    }
    
    /** 
     Set password for authentication as user
     - parameter password: password
     */
    open func setUserPassword(_ password:String?) {
        self.sessionObject.setUserProperty(SessionObject.PASSWORD, value: password);
    }

    /**
     Set server host to which we should connect (ie. to select particular node of a server cluster)
     - parameter serverHost: name or ip address of server
     */
    open func setServerHost(_ serverHost: String?) {
        self.sessionObject.setUserProperty(SocketConnector.SERVER_HOST, value: serverHost);
    }
 
    /**
     Set server port to which we should connect (ie. if there is no SRV records and server uses port other than default port 5222)
     - parameter serverPort: server port to connect to
     */
    open func setServerPort(_ serverPort: Int?) {
        self.sessionObject.setUserProperty(SocketConnector.SERVER_PORT, value: serverPort);
    }
}
