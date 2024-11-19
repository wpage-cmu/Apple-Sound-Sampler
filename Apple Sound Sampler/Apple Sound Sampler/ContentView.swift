//
//  ContentView.swift
//  Apple Sound Sampler
//
//  Created by Will Page on 11/18/24.
//

import SwiftUI
import AVFoundation

class AudioCaptureManager: ObservableObject {
    private let audioEngine = AVAudioEngine()
    private let audioSession = AVAudioSession.sharedInstance()
    @Published var isRecording = false
    private var audioData: [Data] = []  // Raw PCM data for WAV
    
    private var sampleRate: Double = 44100 // Default sample rate for audio capture
    private var channelCount: UInt32 = 1  // Mono audio
    
    init() {
        configureAudioSession()
    }

    private func configureAudioSession() {
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetooth, .defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    func startAudioCapture() {
        guard !isRecording else { return }
        isRecording = true
        audioData.removeAll()

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        sampleRate = format.sampleRate
        channelCount = format.channelCount

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, time in
            self.processAudioBuffer(buffer)
        }

        do {
            try audioEngine.start()
        } catch {
            print("Audio engine failed to start: \(error)")
        }
    }

    func stopAudioCapture() {
        guard isRecording else { return }
        isRecording = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        saveToWav(data: audioData)
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        
        // Convert to raw PCM data (32-bit float)
        let data = Data(bytes: channelData[0], count: frameLength * MemoryLayout<Float>.size)
        audioData.append(data)
    }

    private func saveToWav(data: [Data]) {
        // Generate timestamp for the filename
        let timestamp = getCurrentTimestamp()
        let fileName = "audio_recording_\(timestamp).wav"

        // Get the file URL for the app's Documents directory
        guard let documentsDirectory = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else {
            print("Failed to get Documents directory")
            return
        }

        let outputFileURL = documentsDirectory.appendingPathComponent(fileName)

        // Create the WAV header
        let wavHeader = WAVHeader(sampleRate: sampleRate, numChannels: channelCount, dataSize: data.reduce(0) { $0 + $1.count })

        // Create the file and write the header and data
        do {
            // Ensure the file exists by creating it
            FileManager.default.createFile(atPath: outputFileURL.path, contents: nil, attributes: nil)

            // Open the file for writing
            let fileHandle = try FileHandle(forWritingTo: outputFileURL)

            // Write the WAV header first
            fileHandle.write(wavHeader.data)

            // Write the audio data
            for chunk in data {
                fileHandle.write(chunk)
            }

            fileHandle.closeFile()

            // Log the file path
            print("WAV file saved to: \(outputFileURL.path)")

        } catch {
            print("Failed to save WAV file: \(error)")
        }
    }


    // Generate a timestamp string in HHMMSS--MMDDYYYY format
    private func getCurrentTimestamp() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HHmmss--MMddyyyy"
        return dateFormatter.string(from: Date())
    }
}

// WAV header structure
struct WAVHeader {
    var riffIdentifier: Data
    var fileSize: UInt32
    var wavIdentifier: Data
    var fmtChunkID: Data
    var fmtChunkSize: UInt32
    var audioFormat: UInt16
    var numChannels: UInt16
    var sampleRate: UInt32
    var byteRate: UInt32
    var blockAlign: UInt16
    var bitsPerSample: UInt16
    var dataChunkID: Data
    var dataSize: UInt32

    init(sampleRate: Double, numChannels: UInt32, dataSize: Int) {
        self.riffIdentifier = "RIFF".data(using: .ascii)!
        self.fileSize = UInt32(36 + dataSize)
        self.wavIdentifier = "WAVE".data(using: .ascii)!
        self.fmtChunkID = "fmt ".data(using: .ascii)!
        self.fmtChunkSize = 16
        self.audioFormat = 1  // PCM
        self.numChannels = UInt16(numChannels)
        self.sampleRate = UInt32(sampleRate)
        self.byteRate = UInt32(sampleRate * Double(numChannels) * 4)  // 32-bit float -> 4 bytes per sample
        self.blockAlign = UInt16(numChannels * 4)
        self.bitsPerSample = 32
        self.dataChunkID = "data".data(using: .ascii)!
        self.dataSize = UInt32(dataSize)
    }

    // Combine the header fields into a single data object
    var data: Data {
        var headerData = Data()
        headerData.append(riffIdentifier)
        headerData.append(withUnsafeBytes(of: fileSize) { Data($0) })
        headerData.append(wavIdentifier)
        headerData.append(fmtChunkID)
        headerData.append(withUnsafeBytes(of: fmtChunkSize) { Data($0) })
        headerData.append(withUnsafeBytes(of: audioFormat) { Data($0) })
        headerData.append(withUnsafeBytes(of: numChannels) { Data($0) })
        headerData.append(withUnsafeBytes(of: sampleRate) { Data($0) })
        headerData.append(withUnsafeBytes(of: byteRate) { Data($0) })
        headerData.append(withUnsafeBytes(of: blockAlign) { Data($0) })
        headerData.append(withUnsafeBytes(of: bitsPerSample) { Data($0) })
        headerData.append(dataChunkID)
        headerData.append(withUnsafeBytes(of: dataSize) { Data($0) })
        return headerData
    }
}

struct ContentView: View {
    @StateObject private var audioCaptureManager = AudioCaptureManager()

    var body: some View {
        VStack(spacing: 20) {
            Text(audioCaptureManager.isRecording ? "Recording..." : "Not Recording")
                .font(.headline)

            Button(action: {
                audioCaptureManager.startAudioCapture()
            }) {
                Text("Start Recording")
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }

            Button(action: {
                audioCaptureManager.stopAudioCapture()
            }) {
                Text("Stop Recording")
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
