//
//  SampleBufferDisplayRendererLowLatencySuperResolution.swift
//  CloudX
//
//  Low-latency super-resolution pipeline for the sample-buffer renderer.
//

#if WEBRTC_AVAILABLE && canImport(UIKit) && canImport(AVFoundation)
import Foundation
@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
#if canImport(VideoToolbox)
@preconcurrency import VideoToolbox
#endif
import VideoRenderingKit

#if canImport(VideoToolbox) && !targetEnvironment(simulator)
extension SampleBufferDisplayRenderer {
    @available(tvOS 26.0, *)
    func makeLowLatencySuperResolutionSourceFrame(
        from pixelBuffer: CVPixelBuffer,
        presentationTimeStamp: CMTime,
        resources: LowLatencySuperResolutionResources
    ) throws -> VTFrameProcessorFrame {
        if !lowLatencySourceBufferNeedsCopy(pixelBuffer, requiredAttributes: resources.configuration.sourcePixelBufferAttributes),
           let directSourceFrame = VTFrameProcessorFrame(buffer: pixelBuffer, presentationTimeStamp: presentationTimeStamp) {
            return directSourceFrame
        }

        var preparedSourcePixelBuffer: CVPixelBuffer?
        let sourceStatus = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, resources.sourcePool, &preparedSourcePixelBuffer)
        guard sourceStatus == kCVReturnSuccess, let preparedSourcePixelBuffer else {
            throw NSError(
                domain: "StreamView.LowLatencySuperResolution",
                code: Int(sourceStatus),
                userInfo: [NSLocalizedDescriptionKey: "source pixel buffer allocation failed: \(sourceStatus)"]
            )
        }

        let transferStatus = VTPixelTransferSessionTransferImage(resources.pixelTransferSession, from: pixelBuffer, to: preparedSourcePixelBuffer)
        guard transferStatus == noErr else {
            throw NSError(
                domain: "StreamView.LowLatencySuperResolution",
                code: Int(transferStatus),
                userInfo: [NSLocalizedDescriptionKey: "source pixel transfer failed: \(transferStatus)"]
            )
        }
        copyDisplayAttachments(from: pixelBuffer, to: preparedSourcePixelBuffer)
        if !didLogLLSRSourceCopy {
            didLogLLSRSourceCopy = true
            let inputPixelFormat = pixelFormatDescription(CVPixelBufferGetPixelFormatType(pixelBuffer))
            let copiedPixelFormat = pixelFormatDescription(CVPixelBufferGetPixelFormatType(preparedSourcePixelBuffer))
            let copiedAttributes = (CVPixelBufferCopyCreationAttributes(preparedSourcePixelBuffer) as? [String: Any])
                .map(lowLatencyAttributeSummary) ?? "unavailable"
            streamLog("[StreamView][SBR \(rendererDebugID)] LLSR source copy inputPF=\(inputPixelFormat) copiedPF=\(copiedPixelFormat) attrs={\(copiedAttributes)}", force: true)
        }

        guard let copiedSourceFrame = VTFrameProcessorFrame(buffer: preparedSourcePixelBuffer, presentationTimeStamp: presentationTimeStamp) else {
            throw NSError(
                domain: "StreamView.LowLatencySuperResolution",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "source frame was not IOSurface-backed"]
            )
        }
        return copiedSourceFrame
    }

    @available(tvOS 26.0, *)
    func submitLowLatencySuperResolutionFrame(
        _ pixelBuffer: CVPixelBuffer,
        presentationTimeStamp: CMTime,
        scaleFactor: Float
    ) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let resources: LowLatencySuperResolutionResources
        do {
            resources = try lowLatencySuperResolutionResources(for: pixelBuffer, scaleFactor: scaleFactor)
        } catch {
            handleLowLatencySuperResolutionFailure(
                expectedGeneration: currentLLSRGeneration,
                rung: .vtSuperResolution(scaleFactor: scaleFactor),
                reason: "session startup failed: \(lowLatencyErrorDetails(error))"
            )
            return
        }

        let expectedGeneration: UInt64
        stateLock.lock()
        processingInputWidth = width
        processingInputHeight = height
        processingOutputWidth = resources.outputWidth
        processingOutputHeight = resources.outputHeight
        if llsrProcessingInFlight {
            let alreadyQueuedFrame = pendingLLSRPixelBuffer != nil
            if alreadyQueuedFrame {
                framesDroppedByCoalescing += 1
            }
            pendingLLSRPixelBuffer = pixelBuffer
            pendingLLSRPresentationTimeStamp = presentationTimeStamp
            drawQueueDepthMax = max(drawQueueDepthMax, alreadyQueuedFrame ? 2 : 1)
            stateLock.unlock()
            emitTelemetryIfNeeded()
            return
        }

        llsrProcessingInFlight = true
        llsrProcessingGeneration = currentLLSRGeneration
        expectedGeneration = llsrProcessingGeneration
        stateLock.unlock()

        updateLowLatencyStatus(
            "warming",
            inputWidth: width,
            inputHeight: height,
            outputWidth: resources.outputWidth,
            outputHeight: resources.outputHeight
        )
        processLowLatencySuperResolution(
            pixelBuffer: pixelBuffer,
            presentationTimeStamp: presentationTimeStamp,
            resources: resources,
            expectedGeneration: expectedGeneration,
            rung: .vtSuperResolution(scaleFactor: scaleFactor)
        )
    }

    @available(tvOS 26.0, *)
    func processLowLatencySuperResolution(
        pixelBuffer: CVPixelBuffer,
        presentationTimeStamp: CMTime,
        resources: LowLatencySuperResolutionResources,
        expectedGeneration: UInt64,
        rung: RenderLadderRung,
        initializationRetryAttempt: Int = 0,
        initializationRetryStartTime: TimeInterval? = nil
    ) {
        let sourceFrame: VTFrameProcessorFrame
        do {
            sourceFrame = try makeLowLatencySuperResolutionSourceFrame(
                from: pixelBuffer,
                presentationTimeStamp: presentationTimeStamp,
                resources: resources
            )
        } catch {
            handleLowLatencySuperResolutionFailure(
                expectedGeneration: expectedGeneration,
                rung: rung,
                reason: "source frame preparation failed: \(lowLatencyErrorDetails(error))"
            )
            return
        }

        var destinationPixelBuffer: CVPixelBuffer?
        let destinationStatus = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, resources.destinationPool, &destinationPixelBuffer)
        guard destinationStatus == kCVReturnSuccess, let destinationPixelBuffer else {
            handleLowLatencySuperResolutionFailure(
                expectedGeneration: expectedGeneration,
                rung: rung,
                reason: "destination pixel buffer allocation failed: \(destinationStatus)"
            )
            return
        }

        guard let destinationFrame = VTFrameProcessorFrame(
            buffer: destinationPixelBuffer,
            presentationTimeStamp: presentationTimeStamp
        ) else {
            handleLowLatencySuperResolutionFailure(
                expectedGeneration: expectedGeneration,
                rung: rung,
                reason: "destination frame was not IOSurface-backed"
            )
            return
        }

        let parameters = VTLowLatencySuperResolutionScalerParameters(
            sourceFrame: sourceFrame,
            destinationFrame: destinationFrame
        )

        let resourcesToken = Self.makeRetainedReferenceToken(resources)
        let parametersToken = Self.makeRetainedReferenceToken(parameters)
        let pixelBufferToken = Self.makeRetainedReferenceToken(pixelBuffer as AnyObject)
        let destinationPixelBufferToken = Self.makeRetainedReferenceToken(destinationPixelBuffer as AnyObject)

        let safeTokens = SafeTokens(
            r: resourcesToken,
            p: parametersToken,
            pb: pixelBufferToken,
            dpb: destinationPixelBufferToken
        )

        let watchdogTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.stateLock.lock()
                if self.llsrProcessingInFlight && self.llsrProcessingGeneration == expectedGeneration {
                    self.llsrProcessingInFlight = false
                    self.llsrProcessingGeneration = 0
                    self.llsrFallbackToPlainSampleBuffer = true
                    self.llsrDisplayActivated = false
                    self.framesFailed += 1
                    self.processingStatus = "failed"
                    self.lastError = "processor timed out after 150ms"
                }
                self.stateLock.unlock()
                
                _ = safeTokens.take()
            }
        }

        resources.processor.process(parameters: parameters) { _, error in
            watchdogTask.cancel()
            guard let objects = safeTokens.take() else { return }
            let resources = objects.0 as! LowLatencySuperResolutionResources
            let parameters = objects.1 as! VTLowLatencySuperResolutionScalerParameters
            let pixelBuffer = objects.2 as! CVPixelBuffer
            let destinationPixelBuffer = objects.3 as! CVPixelBuffer
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    let errorDetails = self.lowLatencyErrorDetails(error)
                    if self.isLowLatencyInitializationError(error) {
                        let retryStartTime = initializationRetryStartTime ?? Date.timeIntervalSinceReferenceDate
                        let elapsed = Date.timeIntervalSinceReferenceDate - retryStartTime
                        let retryWindow = self.lowLatencyInitializationRetryWindowSeconds()
                        if elapsed < retryWindow {
                            let nextAttempt = initializationRetryAttempt + 1
                            let retryDelay = self.lowLatencyInitializationRetryDelayNanoseconds(forAttempt: nextAttempt)
                            self.updateLowLatencyStatus(
                                "warming",
                                inputWidth: CVPixelBufferGetWidth(pixelBuffer),
                                inputHeight: CVPixelBufferGetHeight(pixelBuffer),
                                outputWidth: CVPixelBufferGetWidth(destinationPixelBuffer),
                                outputHeight: CVPixelBufferGetHeight(destinationPixelBuffer),
                                lastError: "processor initializing \(errorDetails)"
                            )
                            Task {
                                try? await Task.sleep(for: .nanoseconds(retryDelay))
                                self.processLowLatencySuperResolution(
                                    pixelBuffer: pixelBuffer,
                                    presentationTimeStamp: presentationTimeStamp,
                                    resources: resources,
                                    expectedGeneration: expectedGeneration,
                                    rung: rung,
                                    initializationRetryAttempt: nextAttempt,
                                    initializationRetryStartTime: retryStartTime
                                )
                            }
                            return
                        }
                    }
                    self.handleLowLatencySuperResolutionFailure(
                        expectedGeneration: expectedGeneration,
                        rung: rung,
                        reason: "process failed: \(errorDetails)"
                    )
                    return
                }

                self.handleLowLatencySuperResolutionSuccess(
                    expectedGeneration: expectedGeneration,
                    rung: rung,
                    sourcePixelBuffer: pixelBuffer,
                    destinationPixelBuffer: destinationPixelBuffer,
                    presentationTimeStamp: presentationTimeStamp,
                    inputWidth: CVPixelBufferGetWidth(pixelBuffer),
                    inputHeight: CVPixelBufferGetHeight(pixelBuffer),
                    outputWidth: CVPixelBufferGetWidth(destinationPixelBuffer),
                    outputHeight: CVPixelBufferGetHeight(destinationPixelBuffer)
                )
            }
        }
    }

    @available(tvOS 26.0, *)
    func lowLatencySuperResolutionResources(
        for pixelBuffer: CVPixelBuffer,
        scaleFactor: Float
    ) throws -> LowLatencySuperResolutionResources {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let outputWidth = Int((Float(width) * scaleFactor).rounded())
        let outputHeight = Int((Float(height) * scaleFactor).rounded())

        let cachedResources: LowLatencySuperResolutionResources?
        stateLock.lock()
        cachedResources = activeLowLatencySuperResolutionResources
        if let cachedResources,
           cachedResources.sourceWidth == width,
           cachedResources.sourceHeight == height,
           cachedResources.scaleFactor == scaleFactor {
            stateLock.unlock()
            if !didLogLLSRSessionReuse {
                didLogLLSRSessionReuse = true
                streamLog("[StreamView][SBR \(rendererDebugID)] reusing LLSR session \(width)x\(height) -> \(outputWidth)x\(outputHeight) scale=\(scaleFactor)", force: true)
            }
            return cachedResources
        }
        stateLock.unlock()

        let configuration = VTLowLatencySuperResolutionScalerConfiguration(
            frameWidth: width,
            frameHeight: height,
            scaleFactor: scaleFactor
        )

        let processor = VTFrameProcessor()
        do {
            try processor.startSession(configuration: configuration)
        } catch {
            throw NSError(
                domain: "StreamView.LowLatencySuperResolution",
                code: (error as NSError).code,
                userInfo: [
                    NSLocalizedDescriptionKey: "startSession failed: \(lowLatencyErrorDetails(error))",
                    NSUnderlyingErrorKey: error as NSError
                ]
            )
        }

        let sourcePixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let resolvedSourceAttributes = try makeResolvedPixelBufferAttributes(
            baseAttributes: configuration.sourcePixelBufferAttributes,
            width: width,
            height: height,
            pixelFormat: sourcePixelFormat,
            label: "llsr-source"
        )
        var sourcePool: CVPixelBufferPool?
        let sourcePoolStatus = CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, resolvedSourceAttributes, &sourcePool)
        guard sourcePoolStatus == kCVReturnSuccess, let sourcePool else {
            processor.endSession()
            throw NSError(
                domain: "StreamView.LowLatencySuperResolution",
                code: Int(sourcePoolStatus),
                userInfo: [NSLocalizedDescriptionKey: "source pool creation failed: \(sourcePoolStatus)"]
            )
        }

        let destinationPixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let resolvedDestinationAttributes = try makeResolvedPixelBufferAttributes(
            baseAttributes: configuration.destinationPixelBufferAttributes,
            width: outputWidth,
            height: outputHeight,
            pixelFormat: destinationPixelFormat,
            label: "llsr-destination"
        )
        var destinationPool: CVPixelBufferPool?
        let destinationPoolStatus = CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, resolvedDestinationAttributes, &destinationPool)
        guard destinationPoolStatus == kCVReturnSuccess, let destinationPool else {
            processor.endSession()
            throw NSError(
                domain: "StreamView.LowLatencySuperResolution",
                code: Int(destinationPoolStatus),
                userInfo: [NSLocalizedDescriptionKey: "destination pool creation failed: \(destinationPoolStatus)"]
            )
        }

        var pixelTransferSession: VTPixelTransferSession?
        let pixelTransferStatus = VTPixelTransferSessionCreate(
            allocator: kCFAllocatorDefault,
            pixelTransferSessionOut: &pixelTransferSession
        )
        guard pixelTransferStatus == noErr, let pixelTransferSession else {
            processor.endSession()
            throw NSError(
                domain: "StreamView.LowLatencySuperResolution",
                code: Int(pixelTransferStatus),
                userInfo: [NSLocalizedDescriptionKey: "pixel transfer session creation failed: \(pixelTransferStatus)"]
            )
        }

        let resources = LowLatencySuperResolutionResources(
            sourceWidth: width,
            sourceHeight: height,
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            scaleFactor: scaleFactor,
            configuration: configuration,
            processor: processor,
            sourcePool: sourcePool,
            destinationPool: destinationPool,
            pixelTransferSession: pixelTransferSession
        )
        stateLock.lock()
        currentLLSRGeneration &+= 1
        activeLowLatencySuperResolutionResources = resources
        stateLock.unlock()
        didLogLLSRSessionReuse = false
        return resources
    }

    @available(tvOS 26.0, *)
    func handleLowLatencySuperResolutionSuccess(
        expectedGeneration: UInt64,
        rung: RenderLadderRung,
        sourcePixelBuffer: CVPixelBuffer,
        destinationPixelBuffer: CVPixelBuffer,
        presentationTimeStamp: CMTime,
        inputWidth: Int,
        inputHeight: Int,
        outputWidth: Int,
        outputHeight: Int
    ) {
        let shouldDisplayFrame: Bool
        let shouldPromoteDisplay: Bool
        let nextFrame: (pixelBuffer: CVPixelBuffer, pts: CMTime)?

        stateLock.lock()
        shouldDisplayFrame = currentLLSRGeneration == expectedGeneration
        shouldPromoteDisplay = shouldDisplayFrame && !llsrDisplayActivated
        if shouldPromoteDisplay {
            llsrDisplayActivated = true
        }
        if llsrProcessingInFlight, llsrProcessingGeneration == expectedGeneration {
            llsrProcessingInFlight = false
            llsrProcessingGeneration = 0
        }
        if shouldDisplayFrame,
           let queuedPixelBuffer = pendingLLSRPixelBuffer,
           let queuedPTS = pendingLLSRPresentationTimeStamp {
            pendingLLSRPixelBuffer = nil
            pendingLLSRPresentationTimeStamp = nil
            llsrProcessingInFlight = true
            llsrProcessingGeneration = currentLLSRGeneration
            nextFrame = (queuedPixelBuffer, queuedPTS)
        } else {
            nextFrame = nil
        }
        stateLock.unlock()

        guard shouldDisplayFrame else { return }

        copyDisplayAttachments(from: sourcePixelBuffer, to: destinationPixelBuffer)

        if !didLogFirstLLSRFrame {
            didLogFirstLLSRFrame = true
            streamLog("[StreamView] Low-latency super-resolution first processed frame \(inputWidth)x\(inputHeight) -> \(outputWidth)x\(outputHeight)", force: true)
        }

        updateLowLatencyStatus(
            "active",
            inputWidth: inputWidth,
            inputHeight: inputHeight,
            outputWidth: outputWidth,
            outputHeight: outputHeight
        )

        if shouldPromoteDisplay {
            clearPendingPlainSampleBuffers()
            flushDisplayLayer(removingDisplayedImage: false)
            reportCandidateReadyIfNeeded(rung)
        }

        guard let processedSampleBuffer = makeSampleBuffer(from: destinationPixelBuffer, presentationTimeStamp: presentationTimeStamp) else {
            handleLowLatencySuperResolutionFailure(
                expectedGeneration: expectedGeneration,
                rung: rung,
                reason: "processed sample buffer creation failed"
            )
            return
        }
        enqueueSampleBuffer(processedSampleBuffer)
        emitTelemetryIfNeeded(force: true)

        if let nextFrame, let resources = activeLowLatencySuperResolutionResources {
            processLowLatencySuperResolution(
                pixelBuffer: nextFrame.pixelBuffer,
                presentationTimeStamp: nextFrame.pts,
                resources: resources,
                expectedGeneration: llsrProcessingGeneration,
                rung: rung
            )
        }
    }

    @available(tvOS 26.0, *)
    func handleLowLatencySuperResolutionFailure(
        expectedGeneration: UInt64,
        rung: RenderLadderRung,
        reason: String
    ) {
        let isCurrentGeneration: Bool
        stateLock.lock()
        isCurrentGeneration = currentLLSRGeneration == expectedGeneration || expectedGeneration == 0
        if llsrProcessingInFlight, llsrProcessingGeneration == expectedGeneration {
            llsrProcessingInFlight = false
            llsrProcessingGeneration = 0
        }
        if isCurrentGeneration {
            llsrFallbackToPlainSampleBuffer = true
            llsrDisplayActivated = false
            framesFailed += 1
            processingStatus = "failed"
            lastError = reason
        }
        stateLock.unlock()

        guard isCurrentGeneration else { return }
        reportCandidateFailureIfNeeded(rung, reason: reason)
        emitTelemetryIfNeeded(force: true)
    }
}

@available(tvOS 26.0, *)
private final class SafeTokens {
    private var resourcesToken: SampleBufferDisplayRenderer.RetainedReferenceToken?
    private var parametersToken: SampleBufferDisplayRenderer.RetainedReferenceToken?
    private var pixelBufferToken: SampleBufferDisplayRenderer.RetainedReferenceToken?
    private var destinationPixelBufferToken: SampleBufferDisplayRenderer.RetainedReferenceToken?
    private let lock = NSLock()
    
    init(r: SampleBufferDisplayRenderer.RetainedReferenceToken, p: SampleBufferDisplayRenderer.RetainedReferenceToken, pb: SampleBufferDisplayRenderer.RetainedReferenceToken, dpb: SampleBufferDisplayRenderer.RetainedReferenceToken) {
        self.resourcesToken = r
        self.parametersToken = p
        self.pixelBufferToken = pb
        self.destinationPixelBufferToken = dpb
    }
    
    func take() -> (AnyObject, AnyObject, AnyObject, AnyObject)? {
        lock.lock()
        defer { lock.unlock() }
        guard let r = resourcesToken, let p = parametersToken, let pb = pixelBufferToken, let dpb = destinationPixelBufferToken else { return nil }
        self.resourcesToken = nil
        self.parametersToken = nil
        self.pixelBufferToken = nil
        self.destinationPixelBufferToken = nil
        
        let res = SampleBufferDisplayRenderer.takeRetainedReference(r)
        let param = SampleBufferDisplayRenderer.takeRetainedReference(p)
        let pbuf = SampleBufferDisplayRenderer.takeRetainedReference(pb)
        let dpbuf = SampleBufferDisplayRenderer.takeRetainedReference(dpb)
        return (res, param, pbuf, dpbuf)
    }
    
    deinit {
        _ = take()
    }
}
#endif

#endif
