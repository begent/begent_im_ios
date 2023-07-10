//
// WelcomeController.swift
//
// Snikket
// Copyright (C) 2020 "Tigase, Inc." <office@tigase.com>
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
import AVFoundation

class WelcomeController: UIViewController, QRScannerViewDelegate {
    
    @IBOutlet var textView: UITextView!
    private var scannerViewController: UIViewController?;
    
    @IBOutlet var signInButton: UIButton!;
    @IBOutlet var learnMoreButton: UIButton!;
    
    override func viewWillAppear(_ animated: Bool) {
        let text = NSMutableAttributedString(attributedString: textView.attributedText);
        text.addAttribute(.font, value: UIFont.systemFont(ofSize: UIFont.systemFontSize, weight: .semibold), range: NSRange(location: 0, length: 9));
        if #available(iOS 13.0, *) {
            text.addAttribute(.foregroundColor, value: UIColor.label, range: NSRange(location: 0, length: text.length));
            text.addAttribute(.backgroundColor, value: UIColor.systemBackground, range: NSRange(location: 0, length: text.length));
            text.fixAttributes(in: NSRange(location: 0, length: text.length));
            textView.attributedText = text;
            textView.textColor = UIColor.label;
        } else {
            textView.attributedText = text;
        }
        learnMoreButton.layer.borderWidth = 1;
        learnMoreButton.layer.borderColor = UIColor(named: "snikketBlue")!.cgColor;
        orientationChanged();
        super.viewWillAppear(animated);
    }
    
    @IBAction func learnMoreTapped(_ sender: Any) {
        UIApplication.shared.open(URL(string: "https://otherhome.com.au")!);
    }
    
    @IBAction func signInTapped(_ sender: Any) {
        let addAccountController = AddAccountController.instantiate(fromAppStoryboard: .Account);
        addAccountController.hidesBottomBarWhenPushed = true;
        let navigationController = UINavigationController(rootViewController: addAccountController);
        navigationController.navigationBar.isOpaque = true;
        navigationController.navigationBar.barTintColor = self.navigationController?.navigationBar.barTintColor;
        navigationController.navigationBar.tintColor = self.navigationController?.navigationBar.tintColor;
        self.showDetailViewController(navigationController, sender: self);
    }
    
    @objc func orientationChanged(_ notification: Notification) {
        orientationChanged();
    }
    
    func orientationChanged() {
        learnMoreButton.layer.cornerRadius = learnMoreButton.frame.height / 2;
        signInButton.layer.cornerRadius = signInButton.frame.height / 2;
    }

    @IBAction func startScan(_ sender: Any) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { result in
                guard result else {
                    return;
                }
                
                DispatchQueue.main.async {
                    self.startScanning();
                }
            })
        default:
            self.startScanning();
        }
    }
    
    private func startScanning() {
        let scannerView = QRScannerView(frame: .zero);
        scannerView.delegate = self;
        
        let controller = UIViewController();
        controller.view = scannerView;
        self.scannerViewController = controller;
        self.navigationController?.pushViewController(controller, animated: true);
    }
    
    func found(code: String) {
        
        guard let url = URL(string: code) else { return }
        
        if let xmppUri = AppDelegate.XmppUri(url: url), (xmppUri.action == .register || xmppUri.action == .roster) {
            _ = (UIApplication.shared.delegate as? AppDelegate)?.application(UIApplication.shared, open: url)
            return
        } else {
            let session = URLSession(configuration: .default)
            
            session.dataTask(with: url) { data, response, error in
                guard error == nil else { return }
                guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                    self.showWrongQRScan()
                    return
                }
                
                if let link = response.allHeaderFields["Link"] as? String, var xmppComponent = link.components(separatedBy: " ").first {
                    xmppComponent = xmppComponent.replacingOccurrences(of: "<", with: "")
                    xmppComponent = xmppComponent.replacingOccurrences(of: ">", with: "")
                    if let url = URL(string: xmppComponent), let xmppUri = AppDelegate.XmppUri(url: url), (xmppUri.action == .register || xmppUri.action == .roster) {
                        DispatchQueue.main.async {
                            _ = (UIApplication.shared.delegate as? AppDelegate)?.application(UIApplication.shared, open: url)
                        }
                        return
                    } else {
                        self.showWrongQRScan()
                    }
                } else {
                    self.showWrongQRScan()
                }
            }.resume()
        }
    }
    
    func showWrongQRScan() {
        let alert = UIAlertController(title: NSLocalizedString("Error", comment: ""), message: NSLocalizedString("Scanned QR code is not valid for Snikket.", comment: ""), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil))
        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
        
    }
    
    func scanningDidStop() {
        guard self.scannerViewController != nil else {
            return;
        }
        navigationController?.popViewController(animated: true);
        scannerViewController = nil;
    }
    
    func scanningDidFail() {
        scanningDidStop();
        let alert = UIAlertController(title: NSLocalizedString("Error", comment: ""), message: NSLocalizedString("It was not possible to access camera. Please check in privacy settings that you have granted Snikket access to the camera.", comment: ""), preferredStyle: .alert);
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil));
        self.present(alert, animated: true, completion: nil);
    }
    
}

protocol QRScannerViewDelegate: class {
    
    func found(code: String);
    
    func scanningDidFail();
 
    func scanningDidStop();
    
}

class QRScannerView: UIView, AVCaptureMetadataOutputObjectsDelegate {
    
    weak var delegate: QRScannerViewDelegate? {
        didSet {
            if captureSession == nil {
                delegate?.scanningDidFail();
            }
        }
    }
    private var captureSession: AVCaptureSession?;
    
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self;
    }
    
    override var layer: AVCaptureVideoPreviewLayer {
        return super.layer as! AVCaptureVideoPreviewLayer;
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder);
        setup();
    }

    override init(frame: CGRect) {
        super.init(frame: frame);
        setup();
    }
    
    private func setup() {
        clipsToBounds = true;
        
        captureSession = AVCaptureSession();
        captureSession?.beginConfiguration();
        
        guard let device = AVCaptureDevice.default(for: .video), let videoInput = try? AVCaptureDeviceInput(device: device) else {
            scanningDidFail();
            return;
        }
        
        guard captureSession?.canAddInput(videoInput) ?? false else {
            scanningDidFail();
            return;
        }
        captureSession?.addInput(videoInput);

        let metadataOutput = AVCaptureMetadataOutput();

        guard captureSession?.canAddOutput(metadataOutput) ?? false else {
            scanningDidFail();
            return;
        }
        
        captureSession?.addOutput(metadataOutput);
        metadataOutput.setMetadataObjectsDelegate(self, queue: .main);
        metadataOutput.metadataObjectTypes = [.qr];

        captureSession?.commitConfiguration();
        captureSession?.startRunning();
        
        layer.session = captureSession;
        layer.videoGravity = .resizeAspectFill;
        layer.frame = self.bounds;
    }
    
    private func scanningDidFail() {
        captureSession = nil;
        delegate?.scanningDidFail();
    }
    
    private func stopScanning() {
        captureSession?.stopRunning();
        captureSession = nil;
        delegate?.scanningDidStop();
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        
        // TODO: most likely it would be good to validate scanned QR code before ending the scan..
        stopScanning();

        if let metadata = metadataObjects.first as? AVMetadataMachineReadableCodeObject, let string = metadata.stringValue {
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate));
            delegate?.found(code: string);
        }
    }
}
