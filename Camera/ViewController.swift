// Copyright (C) 2021 Parrot Drones SAS
//
//    Redistribution and use in source and binary forms, with or without
//    modification, are permitted provided that the following conditions
//    are met:
//    * Redistributions of source code must retain the above copyright
//      notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above copyright
//      notice, this list of conditions and the following disclaimer in
//      the documentation and/or other materials provided with the
//      distribution.
//    * Neither the name of the Parrot Company nor the names
//      of its contributors may be used to endorse or promote products
//      derived from this software without specific prior written
//      permission.
//
//    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
//    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
//    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
//    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
//    PARROT COMPANY BE LIABLE FOR ANY DIRECT, INDIRECT,
//    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
//    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
//    OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
//    AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
//    OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
//    OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
//    SUCH DAMAGE.

import UIKit
// import GroundSdk library.
import GroundSdk

class ViewController: UIViewController, WhiteBalanceDelegate {

    /// Ground SDk instance.
    private let groundSdk = GroundSdk()
    /// Drone uid
    private var droneUid: String?
    /// Current drone instance.
    private var drone: Drone?

    /// Reference to auto connection.
    private var autoConnectionRef: Ref<AutoConnection>?
    /// Reference to the current drone stream server Peripheral.
    private var streamServerRef: Ref<StreamServer>?
    /// Reference to the current drone live stream.
    private var liveStreamRef: Ref<CameraLive>?
    private var liveStreamFrontLeftRef: Ref<CameraLive>?
    /// Reference to the current drone state.
    private var droneStateRef: Ref<DeviceState>?
    
    private var stereoVisionSensorRef: Ref<StereoVisionSensor>?
    private var frontStereoGimbalRef: Ref<FrontStereoGimbal>?
    private var gimbalRef: Ref<Gimbal>?
    private var altimeterRef: Ref<Altimeter>?
    
    private var mainCamera2Ref: Ref<MainCamera2>?
    
    /// Displayed stream.
    private var stream: CameraLive?

    /// GL rendering sink obtained from 'stream'.
    private var sink: StreamSink?
    
    /// GL renderer given by the sink.
    /// `nil` if the rendering sink is not opened and ready to render.
    private var renderer: GlRenderSink?

    // Remote control:
    /// Current remote control instance.
    private var remote: RemoteControl?
    /// Reference to the current remote control state.
    private var remoteStateRef: Ref<DeviceState>?

    // Controller:
    /// White balance controller
    private var whiteBalanceController: WhiteBalanceController?
    /// Camera mode controller
    private var cameraModeController: CameraModeViewController?
    /// Active state controller
    private var activeStateController: ActiveStateViewController?

    // User Interface:
    /// Video stream view.
    @IBOutlet weak var streamView: StreamView!
    /// Drone state label.
    @IBOutlet weak var droneLabel: UILabel!
    /// Remote state label.
    @IBOutlet weak var remoteLabel: UILabel!
    
    @IBOutlet weak var candidateLabel1: UILabel!
    @IBOutlet weak var candidateLabel2: UILabel!
    @IBOutlet weak var candidateLabel3: UILabel!
    @IBOutlet weak var candidateLabel4: UILabel!
    @IBOutlet weak var candidateLabel5: UILabel!
    @IBOutlet weak var candidateLabel6: UILabel!
    @IBOutlet weak var candidateLabel7: UILabel!
    @IBOutlet weak var candidateLabel8: UILabel!
    @IBOutlet weak var candidateLabel9: UILabel!
    @IBOutlet weak var candidateLabel10: UILabel!
    
    /// White balance button.
    @IBOutlet weak var whiteBalanceButton: UIButton!
    /// White balance container.
    @IBOutlet weak var whiteBalanceContainer: UIView!
    /// White balance button.
    @IBOutlet weak var captureButton: UIButton!

    /// View did load
    override func viewDidLoad() {
        super.viewDidLoad()
        whiteBalanceButton.layer.cornerRadius = 15
        whiteBalanceButton.layer.borderWidth = 1
        whiteBalanceButton.layer.borderColor = UIColor.white.cgColor

        resetDroneUi()
        // Monitor the auto connection facility.
        // Keep the reference to be notified on update.
        autoConnectionRef = groundSdk.getFacility(Facilities.autoConnection) { [weak self] autoConnection in

            // Called when the auto connection facility is available and when it changes.
            if let self = self, let autoConnection = autoConnection {
                // Start auto connection.
                print("ViewController - autoConnection")
                if (autoConnection.state != AutoConnectionState.started) {
                    print("ViewController - autoConnection.state:\(autoConnection.state)")
                    autoConnection.start()
                }
                // If the drone has changed.
                if (self.drone?.uid != autoConnection.drone?.uid) {
                    if (self.drone != nil) {
                        // Stop to monitor the old drone.
                        self.stopDroneMonitors()
                        // Reset user interface drone part.
                        self.resetDroneUi()
                        self.whiteBalanceContainer.isHidden = true
                    }

                    // Monitor the new drone.
                    self.drone = autoConnection.drone
                    if self.drone != nil {
                        self.startDroneMonitors()
                    }
                }

                // If the remote control has changed.
                if (self.remote?.uid != autoConnection.remoteControl?.uid) {
                    print("ViewController - remoteControl")
                    if (self.remote != nil) {
                        // Stop to monitor the old remote.
                        self.stopRemoteMonitors()
                    }

                    // Monitor the new remote.
                    self.remote = autoConnection.remoteControl
                    if (self.remote != nil) {
                        self.startRemoteMonitors()
                    }
                }
            }
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let vc = segue.destination as? WhiteBalanceController, segue.identifier == "WhiteBalanceSegue" {
            // Gets white balance controller from segue
            whiteBalanceController = vc
            whiteBalanceController!.whiteBalanceValueButton = whiteBalanceButton
            whiteBalanceController?.delegate = self
        } else if let vc = segue.destination as? CameraModeViewController, segue.identifier == "CameraModeSegue" {
            // Gets camera mode controller from segue
            cameraModeController = vc
            cameraModeController!.photoRecordingButton = captureButton
        } else if let vc = segue.destination as? ActiveStateViewController, segue.identifier == "ActiveSegue" {
            // Gets active state controller from segue
            activeStateController = vc
        }
    }

    /// Resets drone user interface part.
    private func resetDroneUi() {
        // Stop rendering the stream
        streamView.setStream(stream: nil)
    }

    /// Starts drone monitors.
    private func startDroneMonitors() {
        // Start video stream.
        startVideoStream()

        // Monitor drone state.
        monitorDroneState()
        
        findCandidatesForDepthSensor()

        // Monitor white balance.
        whiteBalanceController?.startMonitoring(drone: self.drone!)
        // Monitor camera mode.
        cameraModeController?.startMonitoring(drone: self.drone!)
        // Monitor active state.
        activeStateController?.startMonitoring(drone: self.drone!)
    }

    /// Stops drone monitors.
    private func stopDroneMonitors() {
        // Release live stream reference.
        liveStreamRef = nil
        // Release stream server refeernce.
        streamServerRef = nil
        // Release reference to the current drone state
        droneStateRef = nil

        // Stop Monitoring white balance.
        whiteBalanceController?.stopMonitoring()
        // Stop Monitoring camera mode.
        cameraModeController?.stopMonitoring()
        // Stop Monitoring active state.
        activeStateController?.stopMonitoring()
    }

    /// Monitor current drone state.
    private func monitorDroneState() {
        // Monitor current drone state.
        droneStateRef = drone?.getState { [weak self] state in
            // Called at each drone state update.

            if let self = self, let state = state {
                // Update drone state view.
                self.droneLabel.text = state.connectionState.description
            }
        }
    }
    
    private func findCandidatesForDepthSensor() {
        stereoVisionSensorRef = drone?.getPeripheral(Peripherals.stereoVisionSensor) { stereoVisionSensor in
            if let calibrated = stereoVisionSensor?.isCalibrated {
                self.candidateLabel1.text = String(describing: calibrated)
            }
        }
        
        frontStereoGimbalRef = drone?.getPeripheral(Peripherals.frontStereoGimbal) { frontStereoGimbal in
            if let state = frontStereoGimbal?.calibrationProcessState {
                self.candidateLabel2.text = String(describing: state.description)
            }
        }
        
        gimbalRef = drone?.getPeripheral(Peripherals.gimbal) { gimbal in
            let pitch = String(format: "%f", gimbal?.currentAttitude[.pitch] ?? 0.0)
            let roll = String(format: "%f", gimbal?.currentAttitude[.roll] ?? 0.0)
            let yaw = String(format: "%f", gimbal?.currentAttitude[.yaw] ?? 0.0)
            self.candidateLabel3.text = "pitch:\(pitch) , roll:\(roll) , yaw:\(yaw)"
        }
        
        altimeterRef = drone?.getInstrument(Instruments.altimeter) { altimeter in
            if let groundRelativeAltitude = altimeter?.groundRelativeAltitude {
                self.candidateLabel4.text = String(format: "%f", groundRelativeAltitude)
            }
        }
    }

    /// Starts remote control monitors.
    private func startRemoteMonitors() {
        // Monitor remote state
        monitorRemoteState()
    }

    /// Stops remote control monitors.
    private func stopRemoteMonitors() {
        // Forget all references linked to the current remote to stop their monitoring.
        remoteStateRef = nil
    }

    /// Monitor current remote control state.
    private func monitorRemoteState() {
        // Monitor current drone state.
        remoteStateRef = remote?.getState { [weak self] state in
            // Called at each remote state update.

            if let self = self, let state = state {
                self.remoteLabel.text = state.description
            }
        }
    }

    /// Starts the video stream.
    private func startVideoStream() {
        // Monitor the stream server.
        streamServerRef = drone?.getPeripheral(Peripherals.streamServer) { [weak self] streamServer in
            // Called when the stream server is available and when it changes.

            if let self = self, let streamServer = streamServer {
                // Enable Streaming
                streamServer.enabled = true
                self.liveStreamRef = streamServer.live(source: .disparity) { liveStream in
                    // Called when the live stream is available and when it changes.

                    if let liveStream = liveStream {
                        // Set the live stream as the stream to be render by the stream view.
                        self.streamView.setStream(stream: liveStream)
//                        // Play the live stream.
//                        _ = liveStream.play()

                        print("StreamListener liveStream: \(liveStream.state)")
                        
                        if liveStream === self.stream {
                            return
                        }

                        if let sink = self.sink {
                            sink.close()
                            self.sink = nil
                        }

                        self.stream = liveStream

                        if let stream = self.stream {
//                            self.sink = stream.openSink(config: GlRenderSinkCore.config(listener: self))

                            let dispatchQueue = DispatchQueue.global()
                            self.sink = liveStream.openYuvSink(queue: dispatchQueue, listener: self)
                        }

                        _ = liveStream.play()
                        
                        print("StreamListener liveStream: \(liveStream.state)")
                    }
                    
                }
            }
        }
    }

    /// Value changed for segmented control mode.
    @IBAction func displayWhiteBalancePicker(_ sender: Any) {
        whiteBalanceContainer.isHidden = false
    }

    /// Hide white balance container
    func hideWhiteBalance() {
        whiteBalanceContainer.isHidden = true
    }

    /// Called when start / stop photo / recording button is pressed
    @IBAction func startStop(_ sender: Any) {
        cameraModeController?.startStop()
    }
}

extension ViewController: YuvSinkListener {
    public func frameReady(sink: StreamSink, frame: SdkCoreFrame) {
        var offSet: UnsafePointer<UInt8> = frame.data!
        
        var stringData = ""
        for i in 0...frame.len {
            stringData += "\(offSet[i]) "
        }
        
        NSLog("YuvSinkListener length: \(frame.len), data: \(stringData)")
    }
    
    public func didStart(sink: StreamSink) {
        NSLog("YuvSinkListener didStart")
    }
    
    public func didStop(sink: StreamSink) {
        NSLog("YuvSinkListener didStop")
    }
}

extension ViewController: GlRenderSinkListener {
    public func onRenderingMayStart(renderer: GlRenderSink) {
        self.renderer = renderer
        NSLog("GlRenderSinkListener onRenderingMayStart")
    }
    
    public func onRenderingMustStop(renderer: GlRenderSink) {
        NSLog("GlRenderSinkListener onRenderingMustStop")
        self.renderer = nil
    }
    
    public func onFrameReady(renderer: GlRenderSink) {
        NSLog("GlRenderSinkListener onFrameReady")
    }
    
    public func onContentZoneChange(contentZone: CGRect) {
        NSLog("GlRenderSinkListener onContentZoneChange content.size: \(contentZone.size)")
    }
}
