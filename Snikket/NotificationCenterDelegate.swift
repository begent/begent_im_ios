//
// NotificationCenterDelegate.swift
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
import Shared
import WebRTC
import TigaseSwift
import UserNotifications

class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        switch NotificationCategory.from(identifier: notification.request.content.categoryIdentifier) {
        case .MESSAGE:
            let account = notification.request.content.userInfo["account"] as? String;
            let sender = notification.request.content.userInfo["sender"] as? String;
            if (AppDelegate.isChatVisible(account: account, with: sender) && XmppService.instance.applicationState == .active) {
                completionHandler([]);
            } else {
                completionHandler([.alert, .sound]);
            }
        case .MUC_ROOM_INVITATION:
            didReceive(mucInvitation: notification.request.content)
            return
        case .SUBSCRIPTION_REQUEST:
            let account = notification.request.content.userInfo["account"] as? String;
            let sender = notification.request.content.userInfo["sender"] as? String;
            if let account = account, let sender = sender {
                AppDelegate.subscriptionsRequest[account] = sender
                NotificationCenter.default.post(name: Notification.Name("SUBSCRIPTION_REQUEST"), object: nil)
            }
        default:
            completionHandler([.alert, .sound]);
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content;
         
        switch NotificationCategory.from(identifier: response.notification.request.content.categoryIdentifier) {
        case .ERROR:
            didReceive(error: content, withCompletionHandler: completionHandler);
        case .SUBSCRIPTION_REQUEST:
            break
            //didReceive(subscriptionRequest: content, withCompletionHandler: completionHandler);
        case .MUC_ROOM_INVITATION:
            //didReceive(mucInvitation: content, withCompletionHandler: completionHandler);
        break
        case .MESSAGE:
            didReceive(messageResponse: response, withCompletionHandler: completionHandler);
        case .CALL:
            didReceive(call: content, withCompletionHandler: completionHandler);
        case .UNSENT_MESSAGES:
            completionHandler();
        case .UNKNOWN:
            print("received unknown notification category:", response.notification.request.content.categoryIdentifier);
            completionHandler();
        }
     }

    func didReceive(error content: UNNotificationContent, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = content.userInfo;
            if userInfo["cert-name"] != nil {
                let accountJid = BareJID(userInfo["account"] as! String);
                let alert = CertificateErrorAlert.create(domain: accountJid.domain, certName: userInfo["cert-name"] as! String, certHash: userInfo["cert-hash-sha1"] as! String, issuerName: userInfo["issuer-name"] as? String, issuerHash: userInfo["issuer-hash-sha1"] as? String, onAccept: {
                    print("accepted certificate!");
                    guard let account = AccountManager.getAccount(for: accountJid) else {
                        return;
                    }
                    var certInfo = account.serverCertificate;
                    certInfo?["accepted"] = true as NSObject;
                    account.serverCertificate = certInfo;
                    account.active = true;
                    AccountSettings.LastError(accountJid).set(string: nil);
                    AccountManager.save(account: account);
                }, onDeny: nil);
                
                var topController = UIApplication.shared.keyWindow?.rootViewController;
                while (topController?.presentedViewController != nil) {
                    topController = topController?.presentedViewController;
                }
                
                topController?.present(alert, animated: true, completion: nil);
            }
            if let authError = userInfo["auth-error-type"] {
                let accountJid = BareJID(userInfo["account"] as! String);
                
                let alert = UIAlertController(title: "Authentication issue", message: "Authentication for account \(accountJid) failed: \(authError)\nVerify provided account password.", preferredStyle: .alert);
                alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil));
                
                var topController = UIApplication.shared.keyWindow?.rootViewController;
                while (topController?.presentedViewController != nil) {
                    topController = topController?.presentedViewController;
                }
                
                topController?.present(alert, animated: true, completion: nil);
            } else {
                let alert = UIAlertController(title: content.title, message: content.body, preferredStyle: .alert);
                alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil));
                
                var topController = UIApplication.shared.keyWindow?.rootViewController;
                while (topController?.presentedViewController != nil) {
                    topController = topController?.presentedViewController;
                }
                
                topController?.present(alert, animated: true, completion: nil);
            }
        completionHandler();
    }
    
    func didReceive(subscriptionRequest content: UNNotificationContent, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = content.userInfo;
        let senderJid = BareJID(userInfo["sender"] as! String);
        let accountJid = BareJID(userInfo["account"] as! String);
        var senderName = userInfo["senderName"] as! String;
        if senderName != senderJid.stringValue {
            senderName = "\(senderName) (\(senderJid.stringValue))";
        }
        let alert = UIAlertController(title: "Subscription request", message: "Received presence subscription request from\n\(senderName)\non account \(accountJid.stringValue)", preferredStyle: .alert);
        alert.addAction(UIAlertAction(title: "Accept", style: .default, handler: {(action) in
            guard let client = XmppService.instance.getClient(forJid: accountJid), let presenceModule: PresenceModule = client.context.modulesManager.getModule(PresenceModule.ID) else {
                return;
            }
            presenceModule.subscribed(by: JID(senderJid));
            let subscription = RosterModule.getRosterStore(client.context.sessionObject).get(for: JID(senderJid))?.subscription ?? RosterItem.Subscription.none;
            guard !subscription.isTo else {
                return;
            }
            if (Settings.AutoSubscribeOnAcceptedSubscriptionRequest.getBool()) {
                presenceModule.subscribe(to: JID(senderJid));
            } else {
                let alert2 = UIAlertController(title: "Subscribe to " + senderName, message: "Do you wish to subscribe to \n\(senderName)\non account \(accountJid.stringValue)", preferredStyle: .alert);
                alert2.addAction(UIAlertAction(title: "Accept", style: .default, handler: {(action) in
                    presenceModule.subscribe(to: JID(senderJid));
                }));
                alert2.addAction(UIAlertAction(title: "Reject", style: .destructive, handler: nil));
                
                var topController = UIApplication.shared.keyWindow?.rootViewController;
                while (topController?.presentedViewController != nil) {
                    topController = topController?.presentedViewController;
                }
                
                topController?.present(alert2, animated: true, completion: nil);
            }
        }));
        alert.addAction(UIAlertAction(title: "Reject", style: .destructive, handler: {(action) in
            guard let client = XmppService.instance.getClient(forJid: accountJid), let presenceModule: PresenceModule = client.context.modulesManager.getModule(PresenceModule.ID) else {
                return;
            }
            presenceModule.unsubscribed(by: JID(senderJid));
        }));
        
        var topController = UIApplication.shared.keyWindow?.rootViewController;
        while (topController?.presentedViewController != nil) {
            topController = topController?.presentedViewController;
        }
        
        topController?.present(alert, animated: true, completion: nil);
        completionHandler();
    }
    
    func didReceive(mucInvitation content: UNNotificationContent) {
        guard let account = BareJID(content.userInfo["account"] as? String), let roomJid: BareJID = BareJID(content.userInfo["roomJid"] as? String) else {
            return;
        }
                
        let password = content.userInfo["password"] as? String;


        let nick = AccountSettings.displayName(account).getString() ?? ""
        joinMUC(account: account, channelJid: roomJid, componentType: .muc, nick: nick, password: password)
        
    }
    
    func didReceive(messageResponse response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo;
        guard let accountJid = BareJID(userInfo["account"] as? String) else {
            completionHandler();
            return;
        }
        
        guard let senderJid = BareJID(userInfo["sender"] as? String) else {
            (UIApplication.shared.delegate as? AppDelegate)?.updateApplicationIconBadgeNumber(completionHandler: completionHandler);
            return;
        }

        if response.actionIdentifier == UNNotificationDismissActionIdentifier {
            if userInfo[AnyHashable("uid")] as? String != nil {
                DBChatHistoryStore.instance.markAsRead(for: accountJid, with: senderJid, before: response.notification.date, completionHandler: {
                    let threadId = response.notification.request.content.threadIdentifier;
                    let date = response.notification.date;
                    UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
                        let toRemove = notifications.filter({ (notification) -> Bool in
                            notification.request.content.threadIdentifier == threadId && notification.date < date;
                        }).map({ (notification) -> String in
                            return notification.request.identifier;
                        });
                        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: toRemove);
                        DispatchQueue.main.async {
                            (UIApplication.shared.delegate as? AppDelegate)?.updateApplicationIconBadgeNumber(completionHandler: completionHandler);
                        }
                    }
                });
            } else {
                completionHandler();
            }
        } else {
            openChatView(on: accountJid, with: senderJid, completionHandler: completionHandler);
        }
    }
    
    private func openChatView(on account: BareJID, with jid: BareJID, completionHandler: @escaping ()->Void) {
        var topController = UIApplication.shared.keyWindow?.rootViewController;
        while (topController?.presentedViewController != nil) {
            if #available(iOS 13.0, *), let tmp = topController?.presentedViewController, tmp.modalPresentationStyle != .none {
                tmp.dismiss(animated: true, completion: {
                    self.openChatView(on: account, with: jid, completionHandler: completionHandler);
                });
                return;
            } else {
                topController = topController?.presentedViewController;
            }
        }
        
        if topController != nil {
            guard let chat = DBChatStore.instance.getChat(for: account, with: jid), let controller = viewController(for: chat) else {
                completionHandler();
                return;
            }
            
            let navigationController = controller;
            let destination = navigationController.visibleViewController ?? controller;
            
            if let baseChatViewController = destination as? BaseChatViewController {
                baseChatViewController.account = account;
                baseChatViewController.jid = jid;
            }
            destination.hidesBottomBarWhenPushed = true;
            
            if let chatController = AppDelegate.getChatController(visible: false), let navController = chatController.parent as? UINavigationController {
                navController.pushViewController(destination, animated: true);
                var viewControllers = navController.viewControllers;
                if !viewControllers.isEmpty {
                    var i = 0;
                    while viewControllers[i] != chatController {
                        i = i + 1;
                    }
                    while (!viewControllers.isEmpty) && i > 0 && viewControllers[i] != destination {
                        viewControllers.remove(at: i);
                        i = i - 1;
                    }
                    navController.viewControllers = viewControllers;
                }
            } else {
                topController!.showDetailViewController(controller, sender: self);
            }
        } else {
            print("No top controller!");
        }
    }
    
    private func viewController(for item: DBChatProtocol) -> UINavigationController? {
        switch item {
        case is DBRoom:
            return UIStoryboard(name: "Groupchat", bundle: nil).instantiateViewController(withIdentifier: "RoomViewNavigationController") as? UINavigationController;
        case is DBChat:
            return UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "ChatViewNavigationController") as? UINavigationController;
        case is DBChannel:
            return UIStoryboard(name: "MIX", bundle: nil).instantiateViewController(withIdentifier: "ChannelViewNavigationController") as? UINavigationController;
        default:
            return nil;
        }
    }
    
    func didReceive(call content: UNNotificationContent, withCompletionHandler completionHandler: @escaping () -> Void) {
        #if targetEnvironment(simulator)
        #else
        let userInfo = content.userInfo;
        let senderName = userInfo["senderName"] as! String;
        let senderJid = JID(userInfo["sender"] as! String);
        let accountJid = BareJID(userInfo["account"] as! String);
        let sdp = userInfo["sdpOffer"] as! String;
        let sid = userInfo["sid"] as! String;
        
        var topController = UIApplication.shared.keyWindow?.rootViewController;
        while (topController?.presentedViewController != nil) {
            topController = topController?.presentedViewController;
        }
        
        if let session = JingleManager.instance.session(for: accountJid, with: senderJid, sid: sid) {
            // can still can be received!
            let alert = UIAlertController(title: "Incoming call", message: "Incoming call from \(senderName)", preferredStyle: .alert);
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .denied, .restricted:
                break;
            default:
                break;
//                alert.addAction(UIAlertAction(title: "Video call", style: .default, handler: { action in
//                    // accept video
//                    VideoCallController.accept(session: session, sdpOffer: sdp, withAudio: true, withVideo: true, sender: topController!);
//                }))
            }
//            alert.addAction(UIAlertAction(title: "Audio call", style: .default, handler: { action in
//                VideoCallController.accept(session: session, sdpOffer: sdp, withAudio: true, withVideo: false, sender: topController!);
//            }));
            alert.addAction(UIAlertAction(title: "Dismiss", style: .cancel, handler: { action in
                _ = session.decline();
            }));
            topController?.present(alert, animated: true, completion: nil);
        } else {
            // call missed...
            let alert = UIAlertController(title: "Missed call", message: "Missed incoming call from \(senderName)", preferredStyle: .alert);
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
            
            topController?.present(alert, animated: true, completion: nil);
        }
        #endif
        completionHandler();
    }
    
    public func joinMUC(account: BareJID, channelJid: BareJID, componentType: ChannelsHelper.ComponentType, nick: String, password: String?) {
        
        switch componentType {
         case .mix:
             break
         case .muc:
            guard let client = XmppService.instance.getClient(for: account), let mucModule: MucModule = client.modulesManager.getModule(MucModule.ID), let discoModule: DiscoveryModule = client.modulesManager.getModule(DiscoveryModule.ID) else {
                 return;
             }
             let room = channelJid;
            _ = mucModule.join(roomName: room.localPart!, mucServer: room.domain, nickname: nick, password: password, onJoined: { room in
                discoModule.getInfo(for: room.jid, node: nil, completionHandler: { result in
                    switch result {
                    case .success(_, _, let features):
                        (room as! DBRoom).supportedFeatures = features;
                    case .failure(_, _):
                        break;
                    }
                });
                room.registerForTigasePushNotification(true, completionHandler: { (result) in
                    print("automatically enabled push for:", room.roomJid, "result:", result);
                })
            });
             PEPBookmarksModule.updateOrAdd(for: account, bookmark: Bookmarks.Conference(name: room.localPart!, jid: JID(room), autojoin: true, nick: nick, password: password));
         }
    }
}
