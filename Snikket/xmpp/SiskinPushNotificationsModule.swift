//
// SiskinPushNotificationsModule.swift
//
// Siskin IM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see https://www.gnu.org/licenses/.
//

import UIKit
import Foundation
import UserNotifications
import Shared
import TigaseSwift

open class SiskinPushNotificationsModule: TigasePushNotificationsModule {
    
    public struct PushSettings {
                
        public let jid: JID;
        public let node: String;
        public let deviceId: String;
        public let pushkitDeviceId: String?;
        public let encryption: Bool;
        public let maxSize: Int?;

        init?(dictionary: [String: Any]?) {
            guard let dict = dictionary else {
                return nil;
            }
            guard let jid = JID(dict["jid"] as? String), let node = dict["node"] as? String, let deviceId = dict["device"] as? String else {
                return nil;
            }
            self.init(jid: jid, node: "register-push-apns", deviceId: deviceId, pushkitDeviceId: dict["pushkitDevice"] as? String, encryption: dict["encryption"] as? Bool ?? false, maxSize: dict["maxSize"] as? Int);
        }
        
        init(jid: JID, node: String, deviceId: String, pushkitDeviceId: String? = nil, encryption: Bool, maxSize: Int?) {
            self.jid = jid;
            self.node = "register-push-apns";
            self.deviceId = deviceId;
            self.pushkitDeviceId = pushkitDeviceId;
            self.encryption = encryption;
            self.maxSize = maxSize;
        }
        
        func dictionary() -> [String: Any] {
            var dict: [String: Any] =  ["jid": jid.stringValue, "node": node, "device": deviceId];
            if let pushkitDevice = self.pushkitDeviceId {
                dict["pushkitDevice"] = pushkitDevice;
            }
            if encryption {
                dict["encryption"] = true;
            }
            if maxSize != nil {
                dict["maxSize"] = maxSize;
            }
            return dict;
        }
        
    }
    
    open var pushSettings: PushSettings?;
    open var shouldEnable: Bool = false;
    
    open var isEnabled: Bool {
        return pushSettings != nil && shouldEnable;
    }
    
    open func isEnabled(for deviceId: String) -> Bool {
        guard let settings = self.pushSettings else {
            return false;
        }
        return settings.deviceId == deviceId;
    }
    
    public let defaultPushServiceJid: JID;

    fileprivate let providerId = "snikket:apns:1";
    fileprivate let provider: SiskinPushNotificationsModuleProviderProtocol;
    
    public init(defaultPushServiceJid: JID, provider: SiskinPushNotificationsModuleProviderProtocol) {
        self.defaultPushServiceJid = defaultPushServiceJid;
        self.provider = provider;
        //
        //self.shouldEnable = false;
        //
        super.init();
    }
    
    open func registerDeviceAndEnable(deviceId: String, pushkitDeviceId: String?, completionHandler: @escaping (Result<PushSettings,ErrorCondition>)->Void) {
        self.findPushComponent { result in
            switch result {
            case .success(let jid):
                self.registerDeviceAndEnable(deviceId: deviceId, pushkitDeviceId: pushkitDeviceId, pushServiceJid: jid, completionHandler: completionHandler);
            case .failure(_):
                self.registerDeviceAndEnable(deviceId: deviceId, pushkitDeviceId: pushkitDeviceId, pushServiceJid: self.defaultPushServiceJid, completionHandler: completionHandler);
            }
        }
    }

    private func prepareExtensions(componentSupportsEncryption: Bool, maxSize: Int?) -> [PushNotificationsModuleExtension] {
        var extensions: [PushNotificationsModuleExtension] = [];
        
        if !Settings.NotificationsFromUnknown.bool() {
            if self.isSupported(extension: TigasePushNotificationsModule.IgnoreUnknown.self) {
                extensions.append(TigasePushNotificationsModule.IgnoreUnknown());
            }
        }
        
        let account = self.context.sessionObject.userBareJid!;
        
        let groupchatFilter = self.isSupported(extension: TigasePushNotificationsModule.GroupchatFilter.self);
        if groupchatFilter {
            extensions.append(TigasePushNotificationsModule.GroupchatFilter(rules: provider.groupchatFilterRules(for: account)));
        }
        let muted = self.isSupported(extension: TigasePushNotificationsModule.Muted.self)
        if muted {
            extensions.append(TigasePushNotificationsModule.Muted(jids: provider.mutedChats(for: account)));
        }
                
        if muted && groupchatFilter {
            let priority = self.isSupported(extension: TigasePushNotificationsModule.Priority.self);
            if priority {
                extensions.append(TigasePushNotificationsModule.Priority());
                if componentSupportsEncryption && self.isSupported(extension: TigasePushNotificationsModule.Encryption.self) && self.isSupported(feature: TigasePushNotificationsModule.Encryption.AES_128_GCM) {
                    extensions.append(TigasePushNotificationsModule.Encryption(algorithm: TigasePushNotificationsModule.Encryption.AES_128_GCM.replacingOccurrences(of: "tigase:push:encrypt:", with: ""), key: NotificationEncryptionKeys.key(for: account) ?? Cipher.AES_GCM.generateKey(ofSize: 128)!, maxPayloadSize: maxSize));
                }
            }
        }
        
        if AccountSettings.PushNotificationsForAway(self.context.sessionObject.userBareJid!).getBool() {
            extensions.append(TigasePushNotificationsModule.PushForAway());
        }
        
        if self.isSupported(extension: TigasePushNotificationsModule.Jingle.self) {
            extensions.append(TigasePushNotificationsModule.Jingle());
        }
        
        return extensions;
    }

    

//
    open class RegistrationResult {
        
        public let node: String;
        public let features: [String]?;
        public let maxPayloadSize: Int?;
        
        public let secret: String; //lucia
        
        init?(form resultData: JabberDataElement?) {
            guard let node = (resultData?.getField(named: "node") as? TextSingleField)?.value else {
                return nil;
            }
            self.node = node;
            
            //>lucia
            guard let secret = (resultData?.getField(named: "secret") as? TextSingleField)?.value else {
                return nil;
            }
            self.secret = secret;
            //<lucia
            
            features = (resultData?.getField(named: "features") as? TextMultiField)?.value;
            maxPayloadSize = Int((resultData?.getField(named: "max-payload-size") as? TextSingleField)?.value ?? "");
        }
        
    }
   
    func _registerDevice(serviceJid: JID, provider: String, deviceId: String, pushkitDeviceId: String? = nil, completionHandler: @escaping (Result<RegistrationResult,ErrorCondition>)->Void) {
        guard let adhocModule: AdHocCommandsModule_Jr = context.modulesManager.getModule(AdHocCommandsModule_Jr.ID) else {
            completionHandler(.failure(ErrorCondition.undefined_condition));
            return;
        }
        
        let data = JabberDataElement(type: .submit);
        data.addField(TextSingleField(name: "token", value: deviceId));
        data.addField(TextSingleField(name: "device-id", value: deviceId));
        if pushkitDeviceId != nil {
            data.addField(TextSingleField(name: "device-second-token", value: pushkitDeviceId));
        }
        
        adhocModule.execute(on: serviceJid, command: "register-push-apns", action: .execute, data: data, onSuccess: { (stanza, resultData) in
            
            guard let result = RegistrationResult(form: resultData) else {
                completionHandler(.failure(.undefined_condition));
                return;
            }
            
            completionHandler(.success(result));
        }, onError: { error in
            completionHandler(.failure(error ?? ErrorCondition.undefined_condition));
        });
    }

    func _unregisterDevice(serviceJid: JID, provider: String, deviceId: String, completionHandler: @escaping (Result<Void, ErrorCondition>)->Void) {
        guard let adhocModule: AdHocCommandsModule = context.modulesManager.getModule(AdHocCommandsModule.ID) else {
            completionHandler(.failure(ErrorCondition.undefined_condition));
            return;
        }
        
        let data = JabberDataElement(type: .submit);
        data.addField(TextSingleField(name: "provider", value: provider));
        data.addField(TextSingleField(name: "device-id", value: deviceId));
        
        adhocModule.execute(on: serviceJid, command: "unregister-push-apns", action: .execute, data: data, onSuccess: { (stanza, resultData) in
            completionHandler(.success(Void()));
        }, onError: { error in
            completionHandler(.failure(error ?? ErrorCondition.undefined_condition));
        })
    }
    
    /*org source
     
     open func registerDeviceAndEnable(deviceId: String, pushkitDeviceId: String? = nil, pushServiceJid: JID, completionHandler: @escaping (Result<PushSettings,ErrorCondition>)->Void) {
         self.registerDevice(serviceJid: pushServiceJid, provider: self.providerId, deviceId: deviceId, pushkitDeviceId: pushkitDeviceId, completionHandler: { (result) in
             switch result {
             case .success(let data):
                 self.enable(serviceJid: pushServiceJid, node: data.node, deviceId: deviceId, pushkitDeviceId: pushkitDeviceId, features: data.features ?? [], maxSize: data.maxPayloadSize, completionHandler: completionHandler);
             case .failure(let err):
                 completionHandler(.failure(err));
             }
         });
     }
     
     */
    open func registerDeviceAndEnable(deviceId: String, pushkitDeviceId: String? = nil, pushServiceJid: JID, completionHandler: @escaping (Result<PushSettings,ErrorCondition>)->Void) {
        

        self._registerDevice(serviceJid: pushServiceJid, provider: self.providerId, deviceId: deviceId, pushkitDeviceId: pushkitDeviceId, completionHandler: { (result) in
            switch result {
            case .success(let data):
                //>lucia
                let publishOptions = JabberDataElement(type: .submit);
                publishOptions.addField(TextSingleField(name: "FORM_TYPE", value: "http://jabber.org/protocol/pubsub#publish-options"));
                publishOptions.addField(TextSingleField(name: "secret", value: data.secret));
                publishOptions.addField(TextSingleField(name: "sandbox", value: "true"));
                //<lucia
                
                self.enable(serviceJid: pushServiceJid, node: data.node, deviceId: deviceId, pushkitDeviceId: pushkitDeviceId, features: data.features ?? [], maxSize: data.maxPayloadSize, publishOptions: publishOptions, completionHandler: completionHandler);
            case .failure(let err):
                completionHandler(.failure(err));
            }
        });
             
    }
    
  /*/ /////////
    open func registerDevice(serviceJid: JID, provider: String, deviceId: String, pushkitDeviceId: String? = nil, completionHandler: @escaping (Result<RegistrationResult,ErrorCondition>)->Void) {
        guard let adhocModule: AdHocCommandsModule = context.modulesManager.getModule(AdHocCommandsModule.ID) else {
            completionHandler(.failure(ErrorCondition.undefined_condition));
            return;
        }
        
        let data = JabberDataElement(type: .submit);
        data.addField(TextSingleField(name: "register-push-apns", value: provider));
        data.addField(TextSingleField(name: "device-id", value: deviceId));
        if pushkitDeviceId != nil {
            data.addField(TextSingleField(name: "device-second-token", value: pushkitDeviceId));
        }
        
        adhocModule.execute(on: serviceJid, command: "register-device", action: .execute, data: data, onSuccess: { (stanza, resultData) in
            
            guard let result = RegistrationResult(form: resultData) else {
                completionHandler(.failure(.undefined_condition));
                return;
            }
            
            completionHandler(.success(result));
        }, onError: { error in
            completionHandler(.failure(error ?? ErrorCondition.undefined_condition));
        });
    }
    // ///////////
   */
    
    open func reenable(pushSettings: PushSettings, completionHandler: @escaping (Result<PushSettings,ErrorCondition>)->Void) {
        self.enable(serviceJid: pushSettings.jid, node: pushSettings.node, deviceId: pushSettings.deviceId, pushkitDeviceId: pushSettings.pushkitDeviceId, features: pushSettings.encryption ? [TigasePushNotificationsModule.Encryption.XMLNS] : [], maxSize: pushSettings.maxSize, completionHandler: completionHandler);
    }
    
    private func hash(extensions: [PushNotificationsModuleExtension]) -> Int {
        var hasher = Hasher();
        for ext in extensions {
            ext.hash(into: &hasher);
        }
        let hash = hasher.finalize();
        if hash == 0 {
            return 1;
        }
        return hash;
    }
    
    private func enable(serviceJid: JID, node: String, deviceId: String, pushkitDeviceId: String? = nil, features: [String], maxSize: Int?, publishOptions: JabberDataElement? = nil, completionHandler: @escaping (Result<PushSettings,ErrorCondition>)->Void) {
        let extensions: [PushNotificationsModuleExtension] = self.prepareExtensions(componentSupportsEncryption: features.contains(TigasePushNotificationsModule.Encryption.XMLNS), maxSize: maxSize);
        
        let newHash = hash(extensions: extensions);
        if let oldSettings = self.pushSettings {
            guard newHash != AccountSettings.pushHash(self.context.sessionObject.userBareJid!).int() else {
                completionHandler(.success(oldSettings));
                return;
            }
        }
        
        let encryption = extensions.first(where: { ext in
            return ext is TigasePushNotificationsModule.Encryption;
        }) as? TigasePushNotificationsModule.Encryption;
                
        let settings = PushSettings(jid: serviceJid, node: node, deviceId: deviceId, pushkitDeviceId: pushkitDeviceId, encryption: encryption != nil, maxSize: maxSize);

        self.enable(serviceJid: serviceJid, node: node, extensions: extensions, publishOptions: publishOptions, completionHandler: { (result) in
            switch result {
            case .success(_):
                let accountJid = self.context.sessionObject.userBareJid!;
                NotificationEncryptionKeys.set(key: encryption?.key, for: accountJid);
                AccountSettings.pushHash(accountJid).set(int: newHash);
                self.pushSettings = settings;
                if let config = AccountManager.getAccount(for: accountJid) {
                    config.pushSettings = settings;
                    config.pushNotifications = true;
                    _ = AccountManager.save(account: config);
                }
                completionHandler(.success(settings));
            case .failure(let err):
                self._unregisterDevice(serviceJid: serviceJid, provider: self.providerId, deviceId: deviceId, completionHandler: { result in
                    print("unregistered device:", result);
                    completionHandler(.failure(err));
                });
            }
        });
    }
        
    public func unregisterDeviceAndDisable(completionHandler: @escaping (Result<Void,ErrorCondition>) -> Void) {
        if let settings = self.pushSettings {
            var total: Result<Void, ErrorCondition> = .success(Void());
            let group = DispatchGroup();
            group.enter();
            group.enter();
            
            AccountSettings.pushHash(self.context.sessionObject.userBareJid!).set(int: 0);
            
            let resultHandler: (Result<Void,ErrorCondition>)->Void = {
                result in
                DispatchQueue.main.async {
                    switch result {
                    case .failure(let error):
                        if error != .item_not_found {
                            total = .failure(error);
                        }
                    default:
                        break;
                    }
                    group.leave();
                }
            }
            
            group.notify(queue: DispatchQueue.main) {
                self.pushSettings = nil;
                let accountJid = self.context.sessionObject.userBareJid!;
                NotificationEncryptionKeys.set(key: nil, for: accountJid);
                if let config = AccountManager.getAccount(for: accountJid) {
                    config.pushSettings = nil;
                    config.pushNotifications = false;
                    _ = AccountManager.save(account: config);
                }
                completionHandler(total);
            }
            
            self.disable(serviceJid: settings.jid, node: settings.node, completionHandler: { result in
                switch result {
                case .success(_):
                    resultHandler(.success(Void()));
                case .failure(let err):
                    resultHandler(.failure(err));
                }
            });
            self._unregisterDevice(serviceJid: settings.jid, provider: self.providerId, deviceId: settings.deviceId, completionHandler: resultHandler);
        }
    }
    
    func findPushComponent(completionHandler: @escaping (Result<JID,ErrorCondition>)->Void) {
        self.findPushComponent(requiredFeatures: ["urn:xmpp:push:0", self.providerId], completionHandler: completionHandler);
    }
    
}

open class AdHocCommandsModule_Jr:AdHocCommandsModule {
    open override func execute(on to: JID?, command node: String, action: Action?, data: JabberDataElement?, onSuccess: @escaping (Stanza, JabberDataElement?)->Void, onError: @escaping (Stanza?,ErrorCondition?)->Void) {
        let iq = Iq();
        iq.type = .set;
        iq.to = to;
        
        let command = Element(name: "command", xmlns: AdHocCommandsModule.COMMANDS_XMLNS);
        command.setAttribute("node", value: node);
        command.setAttribute("action", value: action?.rawValue);

        if data != nil {
            command.addChild(data!.submitableElement(type: XDataType.submit));
        }
        
        iq.addChild(command);
        
        context.writer?.write(iq) { (stanza: Stanza?) in
            var errorCondition:ErrorCondition?;
            if let type = stanza?.type {
                switch type {
                case .result:
                    onSuccess(stanza!, JabberDataElement(from: stanza!.findChild(name: "command", xmlns: AdHocCommandsModule.COMMANDS_XMLNS)?.findChild(name: "x", xmlns: "jabber:x:data")));
                    return;
                default:
                    if let name = stanza!.element.findChild(name: "error")?.firstChild()?.name {
                        errorCondition = ErrorCondition(rawValue: name);
                    }
                }
            }
            onError(stanza, errorCondition);
        }
    }
}

public protocol SiskinPushNotificationsModuleProviderProtocol {
    
    func mutedChats(for account: BareJID) -> [BareJID];
    
    func groupchatFilterRules(for account: BareJID) -> [TigasePushNotificationsModule.GroupchatFilter.Rule];
    
}
