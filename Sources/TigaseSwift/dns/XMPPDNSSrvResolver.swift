//
// DNSSrvResorver.swift
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

import dnssd;

/**
 Class used to resolve DNS XMPP SRV records.
 
 Returns resolved IP address if there is no SRV entries for domain
 */
open class XMPPDNSSrvResolver: Logger, DNSSrvResolver {
    
    private let resolverDispatcher: QueueDispatcher = QueueDispatcher(label: "XmmpDnsSrvResolverQueue");
    
    var directTlsEnabled: Bool = true;
    
    private var inProgress: [String: DNSOperation] = [:];

    
    class DNSOperation {
        
        let domain: String;
        let dispatchGroup = DispatchGroup();
        let dispatcher: QueueDispatcher;
        var completionHandlers: [BareJID:(Result<XMPPSrvResult,DNSError>) -> Void] = [:];
        var requests: [Request] = [];
        var results: [Result<[XMPPSrvRecord],DNSError>] = [];
        let onFinish: ()->Void;
        
        init(domain: String, dispatcher: QueueDispatcher, onFinish: @escaping ()->Void) {
            self.domain = domain;
            self.dispatcher = dispatcher;
            self.onFinish = onFinish;
        }
        
        deinit {
            requests.forEach({ $0.cancel(); });
        }
        
        func add(completionHandler: @escaping (Result<XMPPSrvResult,DNSError>) -> Void, for jid: BareJID) {
            completionHandlers[jid] = completionHandler;
        }
        
        func start(forServices services: [String]) {
            for service in services {
                dispatchGroup.enter();
                print("starting for service:", service, "at:", domain);
                requests.append(Request(srvName: "\(service)\(domain)", completionHandler: { result in
                    self.dispatcher.async {
                        self.results.append(result);
                        self.dispatchGroup.leave();
                    }
                }))
            }
            requests.forEach { (request) in
                print("starting for service:", request.srvName, "at:", domain);
                request.resolve(timeout: 30.0);
            }
            dispatchGroup.notify(queue: dispatcher.queue, execute: {
                self.finished();
            })
        }
        
        func finished() {
            var items: [XMPPSrvRecord] = [];
            var wasSuccess = false;
            var error: DNSError?;
            
            for result in results {
                switch result {
                case .success(let records):
                    wasSuccess = true;
                    items.append(contentsOf: records);
                case .failure(let err):
                    if error == nil {
                        error = err;
                    }
                }
            }
            
            guard wasSuccess else {
                onFinish();
                for handler in completionHandlers.values {
                    handler(.failure(error!));
                }
                return;
            }
            
            let result = XMPPSrvResult(domain: domain, records: items.sorted(by: { (a,b) -> Bool in
                if (a.priority < b.priority) {
                    return true;
                } else if (a.priority > b.priority) {
                    return false;
                } else {
                    return a.weight > b.weight;
                }
            }));
            onFinish();
            for handler in completionHandlers.values {
                handler(.success(result));
            }
        }
        
    }
    
    var services: [String] {
        return directTlsEnabled ? ["_xmpps-client._tcp.", "_xmpp-client._tcp."] : ["_xmpp-client._tcp."];
    }
    /**
     Resolve XMPP SRV records for domain
     - parameter domain: domain name to resolve
     - parameter completionHandler: handler to be called after DNS resoltion is finished
     */
    open func resolve(domain: String, for jid: BareJID, completionHandler: @escaping (Result<XMPPSrvResult,DNSError>) -> Void) {
        guard !domain.hasSuffix(".local") else {
            completionHandler(.success(XMPPSrvResult(domain: domain, records: [])));
            return;
        }
        
        resolverDispatcher.async {
            if let operation = self.inProgress[domain] {
                operation.add(completionHandler: completionHandler, for: jid);
            } else {
                let operation = DNSOperation(domain: domain, dispatcher: self.resolverDispatcher, onFinish: {
                    print("finished for:", domain);
                    self.inProgress.removeValue(forKey: domain);
                });
                self.inProgress[domain] = operation;
                operation.add(completionHandler: completionHandler, for: jid);
                operation.start(forServices: self.services);
            }
        }
    }
    
    open func markAsInvalid(for domain: String, record: XMPPSrvRecord, for: TimeInterval) {
        // nothing to do..
    }
    
    static func bridge<T : AnyObject>(_ obj : T) -> UnsafeMutableRawPointer {
        return Unmanaged.passUnretained(obj).toOpaque();
    }
    
    static func bridge<T : AnyObject>(_ ptr : UnsafeMutableRawPointer) -> T {
        return Unmanaged<T>.fromOpaque(ptr).takeUnretainedValue();
    }

    class Request {
        
        private let dispatcher = QueueDispatcher(label: "DnsSrvResolverQueue");
        let srvName: String;
        private var sdRef: DNSServiceRef?;
        private var sdFd: dnssd_sock_t = -1;
        private var sdFdReadSource: DispatchSourceRead?;
        private var timeoutTimer: DispatchSourceTimer?;
        private var completionHandler: ((Result<[XMPPSrvRecord],DNSError>)->Void)?;
        
        public private(set) var items: [XMPPSrvRecord] = [];
        
        init(srvName: String, completionHandler:  @escaping (Result<[XMPPSrvRecord],DNSError>)->Void) {
            self.srvName = srvName;
            self.completionHandler = completionHandler;
        }
        
        func resolve(timeout: TimeInterval) {
            dispatcher.async {
            let result: DNSServiceErrorType = self.srvName.withCString { (srvNameC) -> DNSServiceErrorType in
                let sdErr = DNSServiceQueryRecord(&self.sdRef, kDNSServiceFlagsReturnIntermediates, UInt32(kDNSServiceInterfaceIndexAny), srvNameC, UInt16(kDNSServiceType_SRV), UInt16(kDNSServiceClass_IN), QueryRecordCallback, XMPPDNSSrvResolver.bridge(self));
                return sdErr;
            }
            switch result {
            case DNSServiceErrorType(kDNSServiceErr_NoError):
                // we can proceed
                guard let sdRef = self.sdRef else {
                    self.fail(withError: .internalError);
                    return;
                }
                self.sdFd = DNSServiceRefSockFD(self.sdRef)
                guard self.sdFd != -1 else {
                    self.fail(withError: .internalError);
                    return;
                }
                print("srvName:", self.srvName,"sdFd:", self.sdFd, "resolverQueue:", self.dispatcher.queue);
                self.sdFdReadSource = DispatchSource.makeReadSource(fileDescriptor: self.sdFd, queue: self.dispatcher.queue);
                self.sdFdReadSource?.setEventHandler(handler: {
                    // lets process data..
                    let res = DNSServiceProcessResult(sdRef);
                    if res != kDNSServiceErr_NoError {
                        // we have an error..
                        self.fail(withDNSError: res);
                    }
                })
                self.sdFdReadSource?.setCancelHandler(handler: {
                    DNSServiceRefDeallocate(self.sdRef);
                })
                self.sdFdReadSource?.resume();
                
                self.timeoutTimer = DispatchSource.makeTimerSource(flags: [], queue: self.dispatcher.queue);
                self.timeoutTimer?.setEventHandler(handler: {
                    self.fail(withError: .timeout);
                })
                let deadline = DispatchTime(uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds + UInt64(timeout * Double(NSEC_PER_SEC)));
                self.timeoutTimer?.schedule(deadline: deadline, repeating: .infinity, leeway: DispatchTimeInterval.never);
                self.timeoutTimer?.resume();
            default:
                // an error happened
                self.fail(withDNSError: result);
                break;
                
            }
            }
        }
        
        func fail(withDNSError dnsError: DNSServiceErrorType) {
            fail(withError: .unknownError);
        }
        
        func fail(withError: DNSError) {
            complete(with: .failure(withError));
        }
        
        func add(record: XMPPSrvRecord) {
            self.items.append(record);
        }
        
        func succeed() {
            let isDirectTLS = srvName.starts(with: "_xmpps-client._tcp.");
            if isDirectTLS {
                complete(with: .success(self.items.map({ it in it.with(directTLS: isDirectTLS); })));
            } else {
                complete(with: .success(self.items));
            }
        }
        
        private func complete(with result: Result<[XMPPSrvRecord],DNSError>) {
            if let completionHandler = self.completionHandler {
                self.completionHandler = nil;
                completionHandler(result);
            }
            print("stopping for:", self.srvName)
            self.sdFdReadSource?.cancel();
            self.sdFdReadSource = nil;
            self.sdFd = -1;
            self.sdRef = nil;
            
            self.timeoutTimer?.cancel();
            self.timeoutTimer = nil;
        }
        
        func cancel() {
            dispatcher.sync {
                complete(with: .failure(DNSError.unknownError));
            }
        }
    }
}

let QueryRecordCallback: DNSServiceQueryRecordReply = { (sdRef, flags, interfaceIndex, errorCode, fullname, rrtype, rrclass, rdlen, rdata, ttl, context) -> Void in
    
    let request: XMPPDNSSrvResolver.Request = XMPPDNSSrvResolver.bridge(context!);
    
    guard (flags & kDNSServiceFlagsAdd) != 0 else {
        return;
    }
    
    switch errorCode {
    case DNSServiceErrorType(kDNSServiceErr_NoError):
        guard rrtype == kDNSServiceType_SRV else {
            request.fail(withDNSError: errorCode);
            return;
        }
        if let record = XMPPSrvRecord(parse: rdata?.assumingMemoryBound(to: UInt8.self), length: rdlen) {
            request.add(record: record);
        }
        guard (flags & kDNSServiceFlagsMoreComing) != 0 else {
            request.succeed();
            return
        }
    default:
        request.fail(withDNSError: errorCode);
    }
}
