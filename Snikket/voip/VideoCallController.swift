//
// VideoCallController.swift
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
import WebRTC
import TigaseSwift
import UserNotifications
import os
//import CallKit

public class VideoCallController: UIViewController, CallManagerDelegate {

    #if targetEnvironment(simulator)
    func didSendDTMF(_ sender: CallManager, digit: String) {
    }
    func callDidStart(_ sender: CallManager) {
    }
    func callDidEnd(_ sender: CallManager) {
    }
    func callManager(_ sender: CallManager, didReceiveRemoteVideoTrack remoteTrack: RTCVideoTrack) {
    }
    func callManager(_ sender: CallManager, didReceiveLocalVideoCapturer localCapturer: RTCCameraVideoCapturer) {
    }
    func callStateChanged(_ sender: CallManager) {
    }
    #else

    func didSendDTMF(_ sender: CallManager, digit: String) {
        if let pc = sender.currentConnection {
            for rtpSender in pc.senders {
                if rtpSender.track?.kind == "audio" {
                    
                    dtmfQueue.addOperation {
                        rtpSender.dtmfSender?.insertDtmf(digit, duration: TimeInterval(0.5), interToneGap: TimeInterval(0.5))
                    }
                    
                }
            }
        }
    }
    
    func callDidStart(_ sender: CallManager) {
        DispatchQueue.main.async {
            self.call = sender.currentCall;
            self.localVideoCapturer = sender.localCapturer;
            if self.localVideoCapturer != nil && self.localVideoView != nil {
                self.localVideoView.captureSession = self.localVideoCapturer?.captureSession;
            }
            self.updateTitleLabel();
            self.updateAvatar();
        }
    }
    
    func callDidEnd(_ sender: CallManager) {
        DispatchQueue.main.async {
            self.call = nil;
            self.dismiss(animated: true, completion: nil);
        }
    }
    
    func callManager(_ sender: CallManager, didReceiveLocalVideoCapturer localCapturer: RTCCameraVideoCapturer) {
        DispatchQueue.main.async {
            self.localVideoCapturer = localCapturer;
            self.localVideoView.isHidden = false;
            self.localVideoView.captureSession = localCapturer.captureSession;
        }
    }
    
    func callManager(_ sender: CallManager, didReceiveRemoteVideoTrack remoteTrack: RTCVideoTrack) {
        DispatchQueue.main.async {
            self.remoteVideoTrack = remoteTrack;
        }
    }
    
    func callStateChanged(_ sender: CallManager) {
        DispatchQueue.main.async {
            self.updateTitleLabel();
            self.updateAvatarVisibility();
        }
    }
    
    static func checkMediaAvailability(forCall call: Call, completionHandler: @escaping (Result<Void,Error>)->Void) {
        var errors: Bool = false;
        let group = DispatchGroup();
        group.enter();
        for media in call.media {
            group.enter();
            self.checkAccesssPermission(media: media, completionHandler: { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(_):
                        break;
                    case .failure(_):
                        errors = true;
                    }
                    group.leave();
                }
            })
        }
        group.leave();
        group.notify(queue: DispatchQueue.main, execute: {
            completionHandler(errors ? .failure(ErrorCondition.forbidden) : .success(Void()));
        })
    }

    static func checkAccesssPermission(media: Call.Media, completionHandler: @escaping(Result<Void,Error>)->Void) {
        switch AVCaptureDevice.authorizationStatus(for: media.avmedia) {
        case .authorized:
            completionHandler(.success(Void()));
        case .denied, .restricted:
            completionHandler(.failure(ErrorCondition.forbidden));
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: media.avmedia, completionHandler: { result in
                completionHandler(result ? .success(Void()) : .failure(ErrorCondition.forbidden));
            })
        default:
            completionHandler(.failure(ErrorCondition.forbidden));
        }
    }
    
    static func call(jid: BareJID, from account: BareJID, media: [Call.Media], sender: UIViewController) {
        call(jid: jid, from: account, media: media, completionHandler: { result in
            switch result {
            case .success(_):
                break;
            case .failure(let err):
                var message = "It was not possible to establish call";
                if let e = err as? ErrorCondition {
                    switch e {
                    case .forbidden:
                        message = "It was not possible to access camera or microphone. Please check privacy settings";
                    default:
                        break;
                    }
                }
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: "Call failed", message: message, preferredStyle: .alert);
                    alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
                    sender.present(alert, animated: true, completion: nil);
                }
            }
        });
    }
    
    static func call(jid: BareJID, from account: BareJID, media: [Call.Media], completionHandler: @escaping (Result<Void,Error>)->Void) {
        guard let instance = CallManager.instance else {
            completionHandler(.failure(ErrorCondition.not_allowed))
            return;
        }
        
        let continueCall = {
            // we do not know "internal id" of a session
            let call = Call(account: account, with: jid, sid: UUID().uuidString, direction: .outgoing, media: media, sessionId: nil);
                
            checkMediaAvailability(forCall: call, completionHandler: { result in
                switch result {
                case .success(_):
                    instance.reportOutgoingCall(call, completionHandler: completionHandler);
                case .failure(let err):
                    completionHandler(.failure(err));
                }

            })
        };
        
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: { result in
            if result {
                if media.contains(.video) {
                    AVCaptureDevice.requestAccess(for: .audio, completionHandler: { result in
                        if result {
                            continueCall();
                        } else {
                            completionHandler(.failure(ErrorCondition.not_allowed))
                        }
                    });
                } else {
                    continueCall();
                }
            } else {
                completionHandler(.failure(ErrorCondition.not_allowed))
            }
        });
        
        
    }

    fileprivate let hasMetal = MTLCreateSystemDefaultDevice() != nil;
    
    let dtmfQueue = OperationQueue()
    @IBOutlet weak var dialpadButton: RoundButton!
    @IBOutlet weak var dialpadView: UIView!
    
    @IBOutlet var titleLabel: UILabel?;
    
    @IBOutlet var remoteVideoView: RTCMTLVideoView!;
    @IBOutlet var localVideoView: CameraPreviewView!;
    
    @IBOutlet fileprivate var avatar: AvatarView?;
    @IBOutlet fileprivate var avatarWidthConstraint: NSLayoutConstraint!;
    @IBOutlet fileprivate var avatarHeightConstraint: NSLayoutConstraint!;
        
    private var localVideoCapturer: RTCCameraVideoCapturer?;
    private var remoteVideoTrack: RTCVideoTrack? {
        willSet {
            if remoteVideoTrack != nil && remoteVideoView != nil && hasMetal {
                remoteVideoTrack!.remove(remoteVideoView);
                self.updateAvatarVisibility();
            }
        }
        didSet {
            if remoteVideoTrack != nil && remoteVideoView != nil && hasMetal {
                remoteVideoTrack!.add(remoteVideoView);
                self.updateAvatarVisibility();
            }
        }
    }
    
    private var call: Call?;
    public override func viewDidLoad() {
        super.viewDidLoad();

        self.updateTitleLabel();
        
        let mtkview = self.view.subviews.last!;
        self.view.sendSubviewToBack(mtkview);
//        remoteVideoView.delegate = self;
        NotificationCenter.default.addObserver(self, selector: #selector(orientationChanged), name: UIDevice.orientationDidChangeNotification, object: nil)
        if CallManager.isAvailable {
            CallManager.instance?.delegate = self;
        }
    }
    
    private func setAvatarAspectRatio() {
        guard let avatar = avatar else { return }
        avatar.heightAnchor.constraint(equalTo: avatar.widthAnchor, multiplier: 1).isActive = true
        self.avatarHeightConstraint.isActive = false
        self.avatarWidthConstraint.isActive = true
    }
    
    private func updateAvatar() {
        if let call = self.call, let avatar = self.avatar {
            let rosterModule: RosterModule? = XmppService.instance.getClient(for: call.account)?.modulesManager.getModule(RosterModule.ID);
            
            let contactName: String = rosterModule?.rosterStore.get(for: JID(call.jid))?.name ?? call.jid.stringValue;
            avatar.set(name: contactName, avatar: AvatarManager.instance.avatar(for: call.jid, on: call.account), orDefault: AvatarManager.instance.defaultAvatar);
        }
    }
    
//    var timer: Foundation.Timer?;
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        setAvatarAspectRatio()
        self.updateAvatar()
        //self.orientationChanged();
        NotificationCenter.default.addObserver(self, selector: #selector(audioRouteChanged), name: AVAudioSession.routeChangeNotification, object: nil)
//        timer = Foundation.Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { timer in
//            CallManager.instance?.currentConnection?.statistics(completionHandler: { report in
//                print("stats: \(report.statistics.description)");
//            });
//        })
    }

    public override func viewWillDisappear(_ animated: Bool) {
//        timer?.invalidate();
//        timer = nil;
        remoteVideoTrack = nil;
        localVideoView.captureSession = nil;
        localVideoCapturer = nil;
        super.viewWillDisappear(animated);
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        for i in 51...62 {
            if let v = view.viewWithTag(i) {
                v.layer.cornerRadius = v.frame.width / 2
                v.backgroundColor = #colorLiteral(red: 0.1960784314, green: 0.1960784314, blue: 0.1960784314, alpha: 1)
                
                if UIDevice.modelName == "iPhone SE" || UIDevice.modelName == "Simulator iPhone SE" {
                    if let stackview = v.subviews.first as? UIStackView {
                        for label in stackview.subviews {
                            let label = label as? UILabel
                            var oldSize = label?.font.pointSize ?? 0
                            oldSize = oldSize > 15 ? oldSize : 18
                            label?.font = label?.font.withSize(oldSize - 5)
                        }
                    }
                }
            }
        }
    }
    
    @objc func audioRouteChanged(_ notification: Notification) {
        guard let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt, let reason = AVAudioSession.RouteChangeReason(rawValue: value) else {
            return;
        }
        switch reason {
        case .categoryChange:
            guard !AVAudioSession.sharedInstance().categoryOptions.contains(.defaultToSpeaker) else {
                return;
            }
            var options = AVAudioSession.sharedInstance().categoryOptions;
            options.update(with: .defaultToSpeaker);
            try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: options);
        default:
            break;
        }
    }
    
    @objc func orientationChanged() {
        switch UIDevice.current.orientation {
        case .portrait, .portraitUpsideDown, .faceUp:
            self.avatarHeightConstraint.isActive = false;
            self.avatarWidthConstraint.isActive = true;
        default:
            self.avatarHeightConstraint.isActive = true;
            self.avatarWidthConstraint.isActive = false;
        }
    }
    
//    func showAlert(title: String, message: String, completionHandler: @escaping ()->Void) {
//        DispatchQueue.main.async {
//            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert);
//            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { action in
//                self.dismiss();
//            }));
//            self.present(alert, animated: true, completion: nil);
//        }
//    }
    
    @IBAction func switchCamera(_ sender: UIButton) {
        if let instance = CallManager.instance {
            instance.switchCameraDevice();
        }
    }
    
    fileprivate var muted: Bool = false;
    
    @IBAction func mute(_ sender: UIButton) {
        self.muted = !self.muted;
        if let instance = CallManager.instance, let call = self.call {
            instance.muteCall(call, value: self.muted);
        }
        sender.backgroundColor = self.muted ? UIColor.red : UIColor.white;
        sender.tintColor = self.muted ? UIColor.white : UIColor.black;
    }
    
    @IBAction func disconnectClicked(_ sender: UIButton) {
        if let instance = CallManager.instance, let call = self.call {
            instance.endCall(call);
        }
        dismiss();
    }
    
    @IBAction func dialpadTapped(_ sender: UIButton) {
        self.dialpadView.isHidden = !self.dialpadView.isHidden
        self.avatar?.isHidden = !self.dialpadView.isHidden
    }
    
    
    @IBAction func digitPressed(_ sender: UIButton) {
        let tag = sender.tag
        if(tag > 0 && tag < 10) {
            sendDTMF(toneString: "\(tag)")
        }
        else if (tag == 10) {
            sendDTMF(toneString: "*")
        }
        else if (tag == 11) {
            sendDTMF(toneString: "0")
        }
        else {
            sendDTMF(toneString: "#")
        }
    }
    
    func sendDTMF(toneString: String) {
        if let cm = CallManager.instance, let pc = cm.currentConnection {
            for rtpSender in pc.senders {
                if rtpSender.track?.kind == "audio" {
                    dtmfQueue.addOperation {
                        rtpSender.dtmfSender?.insertDtmf(toneString, duration: TimeInterval(0.5), interToneGap: TimeInterval(0.5))
                    }
                    
                }
            }
        }
        
    }
    
    func dismiss() {
        DispatchQueue.main.async {
            self.dismiss(animated: true, completion: nil);
        }
    }
        
    
    private func updateAvatarVisibility() {
        let isHidden = remoteVideoTrack != nil && (call?.state ?? .new) == .connected;
        self.avatar?.isHidden = isHidden
        self.localVideoView.isHidden = !isHidden
        
        if call?.state == .connected , remoteVideoTrack == nil {
            self.dialpadButton.isHidden = false
        }
        
    }
    
    fileprivate func updateTitleLabel() {
        switch call?.state ?? .new {
        case .new:
            self.titleLabel?.text = "New call...";
        case .ringing:
            self.titleLabel?.text = "Ringing...";
        case .connecting:
            self.titleLabel?.text = "Connecting...";
        case .connected:
            self.titleLabel?.text = nil;
        case .ended:
            self.titleLabel?.text = "Call ended";
        }
    }
    #endif
    
    static var peerConnectionFactory: RTCPeerConnectionFactory {
        return JingleManager.instance.connectionFactory;
    }

    static let defaultCallConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil);
    
    static func initiatePeerConnection(iceServers servers: [RTCIceServer], withDelegate delegate: RTCPeerConnectionDelegate) -> RTCPeerConnection {
        
        let iceServers = (servers.isEmpty && Settings.usePublicStunServers.bool()) ? [ RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302","stun:stun1.l.google.com:19302","stun:stun2.l.google.com:19302","stun:stun3.l.google.com:19302","stun:stun4.l.google.com:19302"]), RTCIceServer(urlStrings: ["stun:stunserver.org:3478"]) ] : servers;
        os_log("using ICE servers: %s", log: .jingle, type: .debug, iceServers.map({ $0.urlStrings.description }).description);

        let configuration = RTCConfiguration();
        configuration.tcpCandidatePolicy = .disabled;
        configuration.sdpSemantics = .unifiedPlan;
        configuration.iceServers = iceServers;
        configuration.bundlePolicy = .maxCompat;
        configuration.rtcpMuxPolicy = .require;
        configuration.iceCandidatePoolSize = 5;
        
        return JingleManager.instance.connectionFactory.peerConnection(with: configuration, constraints: defaultCallConstraints, delegate: delegate)!;
    }

}
