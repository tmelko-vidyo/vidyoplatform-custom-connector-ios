//
//  ConferenceViewController.swift
//  VidyoConnector
//
//  Created by taras.melko on 01.03.2021.
//

import UIKit

class ConferenceViewController: UIViewController {
        
    @IBOutlet weak var callButton: UIButton!
    @IBOutlet weak var cameraButton: UIButton!
    @IBOutlet weak var microphoneButton: UIButton!
    @IBOutlet weak var speakerButton: UIButton!
    
    @IBOutlet weak var libVersion: UILabel!
    @IBOutlet weak var progress: UIActivityIndicatorView!

    /* !Important note: rendering container should not be weak */
    @IBOutlet var removeView: UIView!
    @IBOutlet var localView: UIView!
    
    public var connectParams: ConnectParams?
    
    private var connector: VCConnector?
    
    struct CallState {
        var hasDevicesSelected = true
        var cameraMuted = false
        var micMuted = false
        var speakerMuted = false

        var connected = false
        var disconnectingWithQuit = false
    }
    
    var callState = CallState()
    
    var lastSelectedLocalCamera: VCLocalCamera?
    
    var participantsMap: [String: VCRemoteCamera] = [:]
    var loudestParticipantId: String?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        connector = VCConnector(nil,
                                viewStyle: .default,
                                remoteParticipants: 8,
                                logFileFilter: "warning debug@VidyoClient debug@VidyoConnector".cString(using: .utf8),
                                logFileName: "".cString(using: .utf8),
                                userData: 0)
        
        connector?.registerLocalCameraEventListener(self)
        connector?.registerLocalSpeakerEventListener(self)
        connector?.registerLocalMicrophoneEventListener(self)
        connector?.registerRemoteCameraEventListener(self)
        connector?.registerParticipantEventListener(self)
        
        // Orientation change observer
        NotificationCenter.default.addObserver(self, selector: #selector(onOrientationChanged),
                                               name: UIDevice.orientationDidChangeNotification, object: nil)
        
        // Foreground mode observer
        NotificationCenter.default.addObserver(self, selector: #selector(onForeground),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        
        // Background mode observer
        NotificationCenter.default.addObserver(self, selector: #selector(onBackground),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        
        libVersion.text = "Version: \(connector!.getVersion()!)"
        
        progress.isHidden = true
        progress.startAnimating()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        connector?.select(nil as VCLocalCamera?)
        connector?.select(nil as VCLocalMicrophone?)
        connector?.select(nil as VCLocalSpeaker?)
        
        self.hideView(view: &localView)
        self.hideView(view: &removeView)
        
        connector?.disable()
        connector = nil
        
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func onForeground() {
        guard let connector = connector else {
            return
        }
        
        connector.setMode(.foreground)
        
        if !callState.hasDevicesSelected {
            
            if let camera = self.lastSelectedLocalCamera {
                connector.select(camera)
            } else {
                connector.selectDefaultCamera()
            }
            
            connector.selectDefaultMicrophone()
            connector.selectDefaultSpeaker()
            
            callState.hasDevicesSelected = true
        }
        
        connector.setCameraPrivacy(callState.cameraMuted)
    }
    
    @objc func onBackground() {
        guard let connector = connector else {
            return
        }
        
        if isInCallingState() {
            connector.setCameraPrivacy(true)
        } else {
            callState.hasDevicesSelected = false
            
            connector.select(nil as VCLocalCamera?)
            connector.select(nil as VCLocalMicrophone?)
            connector.select(nil as VCLocalSpeaker?)
        }
        
        connector.setMode(.background)
    }
    
    @objc func onOrientationChanged() {
        self.refreshView(view: &self.localView)
        self.refreshView(view: &self.removeView)
    }
    
    @IBAction func onConferenceCall(_ sender: Any) {
        if callState.connected {
            disconnectConference()
        } else {
            connectConference()
        }
    }
    
    @IBAction func onCameraStateChanged(_ sender: Any) {
        callState.cameraMuted = !callState.cameraMuted
        updateCallState()
        
        connector?.showPreview(callState.cameraMuted)
        connector?.setCameraPrivacy(callState.cameraMuted)
        
        self.localView.isHidden = callState.cameraMuted
    }

    @IBAction func onMicStateChanged(_ sender: Any) {
        callState.micMuted = !callState.micMuted
        updateCallState()
        
        connector?.setMicrophonePrivacy(callState.micMuted)
    }
    
    @IBAction func onSpeakerStateChanged(_ sender: Any) {
        callState.speakerMuted = !callState.speakerMuted
        updateCallState()
        
        connector?.setSpeakerPrivacy(callState.speakerMuted)
    }
    
    @IBAction func onCycleCamera(_ sender: Any) {
        connector?.cycleCamera()
    }
    
    @IBAction func closeConference(_ sender: Any) {
        if isInCallingState() {
            progress.isHidden = false
            callState.disconnectingWithQuit = true
            disconnectConference()
            return
        }
        
        dismiss(animated: true, completion: nil)
    }
}

// MARK: - IConnect delegate methods

extension ConferenceViewController: VCConnectorIConnect {
    
    func onSuccess() {
        print("Connection Successful.")
        
        DispatchQueue.main.async {
            [weak self] in
            guard let this = self else { fatalError("Can't maintain self reference.") }
            
            this.progress.isHidden = true
            this.updateCallState()
            
            this.libVersion.text = "Connected."
        }
    }
    
    func onFailure(_ reason: VCConnectorFailReason) {
        print("Connection failed \(reason)")
        
        DispatchQueue.main.async {
            [weak self] in
            guard let this = self else { fatalError("Can't maintain self reference.") }
            
            this.progress.isHidden = true
            this.callState.connected = false

            this.updateCallState()
            
            this.libVersion.text = "Error: \(reason)"
        }
    }
    
    func onDisconnected(_ reason: VCConnectorDisconnectReason) {
        print("Call Disconnected")
        
        DispatchQueue.main.async {
            [weak self] in
            guard let this = self else { fatalError("Can't maintain self reference.") }
            
            this.progress.isHidden = true
            this.callState.connected = false
            
            this.updateCallState()
            
            this.libVersion.text = "Disconnected: \(reason)"
            
            /* Force quit */
            if this.callState.disconnectingWithQuit { this.dismiss(animated: true, completion: nil) }
        }
    }
}

// MARK: Custom Layouts API

extension ConferenceViewController: VCConnectorIRegisterLocalCameraEventListener, VCConnectorIRegisterRemoteCameraEventListener {
    
    func onLocalCameraAdded(_ localCamera: VCLocalCamera!) {}
    
    func onLocalCameraSelected(_ localCamera: VCLocalCamera!) {
        if (localCamera == nil) { return }
        
        self.lastSelectedLocalCamera = localCamera
        
        self.assignLocalCamera(localCamera: localCamera, view: &localView)
        self.refreshView(view: &localView)
    }
    
    func onLocalCameraRemoved(_ localCamera: VCLocalCamera!) {}
    
    func onLocalCameraStateUpdated(_ localCamera: VCLocalCamera!, state: VCDeviceState) {}
    
    func onRemoteCameraAdded(_ remoteCamera: VCRemoteCamera!, participant: VCParticipant!) {
        self.participantsMap[participant.getId()] = remoteCamera
        
        if (self.loudestParticipantId == nil || participant.getId() == self.loudestParticipantId) {
            self.hideView(view: &removeView)
            self.assignRemoteCamera(remoteCamera: remoteCamera, view: &removeView)
            self.refreshView(view: &removeView)
        }
    }
    
    func onRemoteCameraRemoved(_ remoteCamera: VCRemoteCamera!, participant: VCParticipant!) {
        self.participantsMap.removeValue(forKey: participant.getId())

        if (participant.getId() == self.loudestParticipantId) {
            self.hideView(view: &removeView)
            self.loudestParticipantId = nil
            
            self.takeDefaultCameraBeforeLoudestDetected()
        }
    }
    
    func onRemoteCameraStateUpdated(_ remoteCamera: VCRemoteCamera!, participant: VCParticipant!, state: VCDeviceState) {}
}

// MARK: Participants Listener

extension ConferenceViewController: VCConnectorIRegisterParticipantEventListener {
    
    func onLoudestParticipantChanged(_ participant: VCParticipant!, audioOnly: Bool) {
        if (audioOnly) {
            print("There is no need to render since loudest is audio only. Pick someone else.")
            return
        }
        
        guard let remoteCamera = self.participantsMap[participant.getId()] else {
            print("Failed to find loudest camera")
            return
        }

        self.hideView(view: &removeView)
        self.assignRemoteCamera(remoteCamera: remoteCamera, view: &removeView)
        self.refreshView(view: &removeView)
        
        self.loudestParticipantId = participant.getId()
    }
    
    func onParticipantJoined(_ participant: VCParticipant!) {}
    
    func onParticipantLeft(_ participant: VCParticipant!) {}
    
    func onDynamicParticipantChanged(_ participants: NSMutableArray!) {}
}

// MARK: Audio Devices Event Listener

extension ConferenceViewController: VCConnectorIRegisterLocalSpeakerEventListener, VCConnectorIRegisterLocalMicrophoneEventListener {
    func onLocalSpeakerAdded(_ localSpeaker: VCLocalSpeaker!) {}
    
    func onLocalSpeakerRemoved(_ localSpeaker: VCLocalSpeaker!) {}
    
    func onLocalSpeakerSelected(_ localSpeaker: VCLocalSpeaker!) {}
    
    func onLocalSpeakerStateUpdated(_ localSpeaker: VCLocalSpeaker!, state: VCDeviceState) {}
    
    func onLocalMicrophoneAdded(_ localMicrophone: VCLocalMicrophone!) {}
    
    func onLocalMicrophoneRemoved(_ localMicrophone: VCLocalMicrophone!) {}
    
    func onLocalMicrophoneSelected(_ localMicrophone: VCLocalMicrophone!) {}
    
    func onLocalMicrophoneStateUpdated(_ localMicrophone: VCLocalMicrophone!, state: VCDeviceState) {}
}

// MARK: Private

extension ConferenceViewController {
    
    private func connectConference() {
        progress.isHidden = false

        callState.connected = true
        updateCallState()
        
        connector?.connectToRoom(asGuest: connectParams?.portal,
                                 displayName: connectParams?.displayName,
                                 roomKey: connectParams?.roomKey,
                                 roomPin: connectParams?.pin,
                                 connectorIConnect: self)
    }
    
    private func disconnectConference() {
        progress.isHidden = false
        
        connector?.disconnect()
    }
    
    private func updateCallState() {
        self.cameraButton.setImage(UIImage(named: callState.cameraMuted ? "cameraOff": "cameraOn"), for: .normal)
        self.callButton.setImage(UIImage(named: callState.connected ? "callEnd": "callStart"), for: .normal)
        self.microphoneButton.setImage(UIImage(named: callState.micMuted ? "microphoneOff": "microphoneOn"), for: .normal)
        self.speakerButton.setImage(UIImage(named: callState.speakerMuted ? "speakerOff": "speakerOn"), for: .normal)
    }
    
    /**
     * Attach local camera to the view
     */
    private func assignLocalCamera(localCamera: VCLocalCamera, view: inout UIView?) {
        guard var view = view else { return }

        DispatchQueue.main.async {
            [weak self] in
            guard let this = self else { return }
            
            this.connector?.assignView(toLocalCamera: &view,
                                       localCamera: localCamera,
                                       displayCropped: true,
                                       allowZoom: true)
        }
    }
    
    /**
     * Attach remote camera to the view
     */
    private func assignRemoteCamera(remoteCamera: VCRemoteCamera, view: inout UIView?) {
        guard var view = view else { return }
        
        DispatchQueue.main.async {
            [weak self] in
            guard let this = self else { return }
            
            this.connector?.assignView(toRemoteCamera: &view,
                                       remoteCamera: remoteCamera,
                                       displayCropped: true,
                                       allowZoom: true)
        }
    }
    
    /**
     * Start rendering by attached camera to this view. Refresh renderer position in view container
     */
    private func refreshView(view: inout UIView?) {
        guard var view = view else { return }

        DispatchQueue.main.async {
            [weak self] in
            guard let this = self else { return }
            
            this.connector?.showView(at: &view,
                                     x: 0,
                                     y: 0,
                                     width: UInt32(view.frame.size.width),
                                     height: UInt32(view.frame.size.height))
        }
    }
    
    /**
     * Remove and deallocate renderer from view container, when view remains untouched and could accept next camera
     */
    private func hideView(view: inout UIView?) {
        guard var view = view else { return }

        DispatchQueue.main.async {
            [weak self] in
            guard let this = self else { return }
            this.connector?.hideView(&view)
        }
    }
    
    private func takeDefaultCameraBeforeLoudestDetected() {
        DispatchQueue.main.async {
            [weak self] in
            guard let this = self else { return }
            
            for (participantId, remoteCamera) in this.participantsMap {
                this.assignRemoteCamera(remoteCamera: remoteCamera, view: &this.removeView)
                this.refreshView(view: &this.removeView)
                print("Participant with id \(participantId) was taken as default before loudest detected")
                break
            }
        }
    }
    
    private func isInCallingState() -> Bool {
        if let connector = connector {
            let state = connector.getState()
            return state != .idle && state != .ready
        }
        
        return false
    }
}
