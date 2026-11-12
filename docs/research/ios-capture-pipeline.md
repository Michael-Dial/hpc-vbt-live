# iOS capture pipeline for the Station app (iPhone XR, iOS 18)

Research for issue #2. Read on 2026-11-12.

## How to read this document

Every claim carries one of three labels:

- **[V] Verified**: stated in a primary source that was read for this ticket. The source is linked and quoted.
- **[I] Inferred**: likely, and consistent with the primary sources, but not stated by Apple in so many words.
- **[U] Unknown**: only the XR benchmark can settle it.

Apple documentation pages were read through their JSON form (`https://developer.apple.com/tutorials/data/documentation/<path>.json`); the links below are the matching human-readable pages. Quotes from documentation are verbatim from that JSON. Quotes from the WWDC22 transcript, the forum threads, and the two support.apple.com pages were extracted by a fetch tool that summarises pages, so a reviewer should re-check their exact wording against the page.

"Min iOS" is the version in which Apple's documentation says the API was introduced.

## Question

On an iPhone XR (A12, 3 GB RAM, iOS 18 as its final OS), which AVFoundation pipeline can, for 60+ minutes without interruption:

- capture 1080p at 120 fps (and are the 240 fps formats exposed to third-party apps?),
- encode every frame into one continuous Recording per Session,
- deliver every frame to app code for live tag detection,
- keep the hardware presentation timestamp of every frame?

## Short answer: recommended pipeline

1. One `AVCaptureSession` with one `AVCaptureDeviceInput` for the back wide camera. Pick the capture format by enumerating `device.formats` for 1920x1080 with a frame-rate range that reaches 120 fps, set `activeFormat`, and set `activeVideoMinFrameDuration` and `activeVideoMaxFrameDuration` both to 1/120 s. All of this is iOS 7-era API.
2. One `AVCaptureVideoDataOutput` as the only video output. Request a bi-planar 4:2:0 YpCbCr pixel format (`420v` or `420f`), not BGRA. The luma plane feeds AprilTag directly and the same buffer feeds the encoder.
3. Encode with `AVAssetWriter` plus one `AVAssetWriterInput` (`expectsMediaDataInRealTime = true`), using the settings returned by `recommendedVideoSettings(forVideoCodecType: .hevc, assetWriterOutputFileType: .mov)`. Set `movieFragmentInterval` (about 10 s) so a crash leaves a playable Recording.
4. In the delegate callback, do three cheap things per frame: read the presentation timestamp, append the sample buffer to the writer, and append one row to the timestamp sidecar. Hand tag detection to a second queue so that slow detection can never block recording.
5. Set `alwaysDiscardsLateVideoFrames = false` so a brief stall delays frames rather than discarding them, and implement `captureOutput(_:didDrop:from:)` to log every drop with its reason into the sidecar.
6. Lock the camera: fixed frame duration (step 1), `setExposureModeCustom(duration:iso:)`, `setFocusModeLocked(lensPosition:)`, `setWhiteBalanceModeLocked(with:)`, video HDR off, low-light boost off, `preferredVideoStabilizationMode = .off`.
7. OIS: Apple documents no API that turns the optical stabiliser off for video. Treat lens movement as a benchmark question and rely on a rigid mount.
8. Observe `AVCaptureDevice.systemPressureState` and `ProcessInfo.thermalState`. First degradation step: run tag detection on every second frame (60 fps) while still appending all 120 fps to the Recording. Lowering the capture frame rate is the last resort, because it changes the Recording.
9. Handle `AVCaptureSession.wasInterruptedNotification` and `runtimeErrorNotification`; log them in the sidecar. Keep the app in the foreground with `isIdleTimerDisabled = true`; the camera is not available in the background.
10. Fallback if the writer path cannot keep up on the XR: `AVCaptureMovieFileOutput` plus `AVCaptureVideoDataOutput` in the same session. Apple supports this for apps linked against iOS 16 or later. It is second choice because the app no longer sees exactly which frames were written to the file.
11. Nothing in the recommended pipeline needs iOS 26. The two iOS 26-only items (locked frame duration, external sync) are improvements the XRs must do without.
12. Budget storage at roughly 10 GB per hour in HEVC and 21 GB per hour in H.264 until the benchmark measures it (basis in "Storage per minute" below).

## Findings

### 1. Capturing 1080p at 120 fps, and whether 240 fps is exposed

- **[V]** High frame rates are not reachable through session presets; the app must set a device format. "some specialized options (such as high frame rate) require directly setting a capture format on an `AVCaptureDevice` instance." [AVCaptureSession](https://developer.apple.com/documentation/avfoundation/avcapturesession) (min iOS 4.0). Setting `activeFormat` switches the session preset to `inputPriority`: "If you set a device's active format, the session to which it's attached changes its preset to `inputPriority`." [activeFormat](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activeformat) (min iOS 7.0).
- **[V]** The formats a device offers are listed at run time in [`AVCaptureDevice.formats`](https://developer.apple.com/documentation/avfoundation/avcapturedevice/formats) (min iOS 7.0), and each format reports its rates in [`videoSupportedFrameRateRanges`](https://developer.apple.com/documentation/avfoundation/avcapturedevice/format/videosupportedframerateranges) (min iOS 7.0).
- **[V]** The iPhone XR hardware records 1080p slo-mo at both rates: "Slo-mo video support for 1080p at 120 fps or 240 fps." [iPhone XR Technical Specifications](https://support.apple.com/en-us/111868). The same page lists "Optical image stabilization for video", "Video formats recorded: HEVC and H.264", and the A12 Bionic chip.
- **[V]** 1080p240 formats exist in the third-party API in general. Apple's own documentation uses one as its example: "only run a 1080p240 fps format at a maximum frame rate of 60". [videoMinFrameDurationOverride](https://developer.apple.com/documentation/avfoundation/avcapturedeviceinput/videominframedurationoverride) (min iOS 13.0).
- **[I]** The XR therefore very likely exposes both a 1080p120 and a 1080p240 format to third-party apps through `device.formats`. Apple publishes no per-device format table for the XR that I could find, so this is not verified for the XR specifically.
- **[U]** The exact XR format list: which 1080p formats exist, their maximum frame rates, whether they are binned (`isVideoBinned`), their field of view, exposure-duration and ISO ranges, and which pixel formats the data output offers for them.
- **[V]** If the only 1080p format that reaches 120 fps is the 240 fps one, the session pays for 240 fps unless told otherwise: "`AVCaptureSession` must always allocate sufficient resources to allow the device to run at its active format's maximum frame rate." Setting `videoMinFrameDurationOverride` to 1/120 before starting the session avoids that. [videoMinFrameDurationOverride](https://developer.apple.com/documentation/avfoundation/avcapturedeviceinput/videominframedurationoverride).

### 2. AVAssetWriter from a data output, versus movie file output alongside a data output

**Is the combination supported on iOS 18? Yes.**

- **[V]** "Prior to iOS 16, you can add an `AVCaptureVideoDataOutput` and an `AVCaptureMovieFileOutput` to the same session, but only one may have its connection active. ... For apps that link against iOS 16 or later, this restriction no longer exists." [canAddOutput(_:)](https://developer.apple.com/documentation/avfoundation/avcapturesession/canaddoutput(_:)).
- **[V]** Apple announced it at WWDC22: "New in iOS 16 and iPadOS 16, apps can record with AVCaptureMovieFileOutput while receiving data from AVCaptureVideoDataOutput and AVCaptureAudioDataOutput." and "Implementing these advanced streaming configurations requires use of no new API." [WWDC22 session 110429, "Discover advancements in iOS camera capture"](https://developer.apple.com/videos/play/wwdc2022/110429/).
- **[V]** Support is conditional on the hardware budget. `hardwareCost` (min iOS 16.0) is computed for exactly this configuration, and "When the value is greater than `1.0`, the capture session can't run in its current configuration due to hardware constraints." It also says "The hardware cost increases when using high frame rates." [hardwareCost](https://developer.apple.com/documentation/avfoundation/avcapturesession/hardwarecost).
- **[U]** Whether `canAddOutput` returns true and `hardwareCost` stays at or below 1.0 for movie file output plus data output on an XR at 1080p120.
- Lead only (secondary, unanswered): a developer reports the combination failing with a ProRes 422 format on an iPhone 14 Pro on iOS 26.0, with no Apple reply. [Forum thread 807734](https://developer.apple.com/forums/thread/807734). ProRes is not relevant to the XR, but it shows the combination can fail for specific formats. An older forum answer saying the two outputs cannot be combined predates iOS 16 and is from a non-Apple poster ([thread 98113](https://developer.apple.com/forums/thread/98113)).

**Comparison against the four requirements.**

| Requirement | Data output + `AVAssetWriter` | Movie file output + data output |
| --- | --- | --- |
| Encode every frame | The app appends each buffer and sees the result of each append. | The system records; the app is not told about individual frames. |
| Deliver every frame to app code | Yes, one delegate callback per frame. | Yes, same delegate. |
| Hardware timestamp per frame | The buffer the app timestamps is the buffer it writes. | The app timestamps the data-output frames; the file is written separately. |
| Know about every drop | `didDrop` callback plus `append` failures cover the whole path. | `didDrop` covers only the data output. No documented per-frame drop report for the file. |

- **[V]** The writer path is a documented, intended use. TN3121 describes it: "An app takes the output pixel buffers and feeds them to an AVAssetWriter, configured to write with the hevc codec. This app is a good candidate for a bi-planar YpCbCr format". [TN3121](https://developer.apple.com/documentation/technotes/tn3121-selecting-a-pixel-format-for-an-avcapturevideodataoutput).
- **[V]** The data output supplies encoder settings that match what the movie file output would use: "For QuickTime movie and ISO file types, the recommended video settings produce output comparable to that of `AVCaptureMovieFileOutput`." [recommendedVideoSettings(forVideoCodecType:assetWriterOutputFileType:)](https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput/recommendedvideosettings(forvideocodectype:assetwriteroutputfiletype:)) (min iOS 11.0). Query it after the session is configured: "configure your session first, then query the recommended video settings."
- **[V]** The writer must be told the source is live: "Set this value to `true` if your app appends media data to the input from a real-time source, such as an `AVCaptureOutput`." [expectsMediaDataInRealTime](https://developer.apple.com/documentation/avfoundation/avassetwriterinput/expectsmediadatainrealtime) (min iOS 4.1).
- **[V]** The writer signals when it cannot keep up: with a real-time source, `isReadyForMoreMediaData` "becomes `false` only when the input can't process media samples at the current data rate. If this property value becomes `false` for a real-time source, your app may need to reduce the rate at which it appends samples, or drop them altogether." [isReadyForMoreMediaData](https://developer.apple.com/documentation/avfoundation/avassetwriterinput/isreadyformoremediadata). Every such event must be logged as a dropped frame in the sidecar.
- **[V]** The file keeps the capture timestamps relative to the session start: "a sample you append with timestamp `T` plays at movie time (`T-startTime`)." [startSession(atSourceTime:)](https://developer.apple.com/documentation/avfoundation/avassetwriter/startsession(atsourcetime:)) (min iOS 4.1). Start the writer session at the first frame's timestamp and record that value in the sidecar.
- **[V]** Crash safety: fragments are off by default for the writer and must be enabled. "Using this feature enables you to open and play a partially written movie in the event that an unexpected error or interruption occurs. An asset writer disables this feature by default". [AVAssetWriter.movieFragmentInterval](https://developer.apple.com/documentation/avfoundation/avassetwriter/moviefragmentinterval) (min iOS 4.1). The movie file output does this by default ("The default is 10 seconds", [AVCaptureMovieFileOutput.movieFragmentInterval](https://developer.apple.com/documentation/avfoundation/avcapturemoviefileoutput/moviefragmentinterval)).
- **[V]** One writer makes one file, which fits one Recording per Session: "An asset writer is a single-use object that writes one output file." [AVAssetWriter](https://developer.apple.com/documentation/avfoundation/avassetwriter).
- **[V]** The movie file output has no duration cap by default: `maxRecordedDuration` defaults to `invalid`, "which indicates no limit." [maxRecordedDuration](https://developer.apple.com/documentation/avfoundation/avcapturefileoutput/maxrecordedduration). It can report the timestamp at which recording started through `fileOutput(_:didStartRecordingTo:startPTS:from:)`, but that callback is min iOS 18.2. [Documentation](https://developer.apple.com/documentation/avfoundation/avcapturefileoutputrecordingdelegate/fileoutput(_:didstartrecordingto:startpts:from:)).
- **[I]** With the movie file output, frames dropped on the data output are not necessarily dropped in the file and the reverse, so the sidecar cannot be guaranteed to match the file frame for frame. The file's own sample timestamps could be read back after the Session to rebuild the mapping, but Apple does not document that they equal the data-output timestamps. This is the main reason the writer path is preferred.
- **[I]** The movie file output is likely the lighter path for app code, since Apple describes it as a way to "offload the mechanics of recording" (WWDC22 110429). If the writer path drops frames on the XR and the fallback does not, the fallback wins and the frame mapping becomes a post-Session step.
- **[V]** Forward-compatibility note, no effect on the iOS 18 target: Apple's documentation metadata marks `expectsMediaDataInRealTime`, `isReadyForMoreMediaData`, and `append(_:)` as deprecated in iOS 27.0. They remain the available API on iOS 18.

**Pixel format and buffer handling.**

- **[V]** Do not request BGRA: "'BGRA' pixel buffers require approximately 2.6x more memory than their '420v' equivalent pixel buffers!" and BGRA "is not a native capture format, which means that AVCapture has to perform a conversion". [TN3121](https://developer.apple.com/documentation/technotes/tn3121-selecting-a-pixel-format-for-an-avcapturevideodataoutput). The offered formats are listed at run time in [`availableVideoPixelFormatTypes`](https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput/availablevideopixelformattypes) and depend on the active format.
- **[I]** In a bi-planar YpCbCr buffer, plane 0 is the 8-bit luma image, which is the grayscale input AprilTag needs, so no colour conversion is required. This follows from the pixel format definition rather than from a quoted Apple sentence.
- **[V]** Check the delivered size. By default the data output may scale buffers down: `automaticallyConfiguresOutputBufferDimensions` defaults to `true`, and when true "the output is free to scale the buffers ... to a size suitable for preview". [Documentation](https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput/automaticallyconfiguresoutputbufferdimensions) (min iOS 13.0). Set it to `false` and confirm 1920x1080 from `videoSettings` or the first buffer.
- **[V]** Do not hold capture buffers for long: "If multiple sample buffers reference such pools of memory for too long, inputs will no longer be able to copy new samples into memory and those samples will be dropped." Apple's advice is to copy what you need and release the buffer. [captureOutput(_:didOutput:from:)](https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutputsamplebufferdelegate/captureoutput(_:didoutput:from:)). For the Station app this means the detection queue should copy the luma plane (about 2 MB per 1080p frame) or finish before the next frame, never queue up retained capture buffers.

### 3. Locking frame rate, exposure, and focus; stabilisation; OIS

- **[V] Frame rate.** Set both frame durations to the same value inside `lockForConfiguration()`. `activeVideoMinFrameDuration` limits the maximum rate and `activeVideoMaxFrameDuration` limits the minimum rate; values outside the format's ranges raise an exception. Apple's sample sets `activeFormat` and both durations together between `beginConfiguration()` and `commitConfiguration()`. [activeVideoMinFrameDuration](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activevideominframeduration), [activeVideoMaxFrameDuration](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activevideomaxframeduration), [activeFormat](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activeformat) (all min iOS 7.0).
- **[I]** On iOS 18 this requests a fixed rate; it does not guarantee that every interval is exactly 1/120 s. The guarantee is what iOS 26 adds (see "iOS 26-only items"). The sidecar timestamps are the record of what actually happened.
- **[V]** Leave `isAutoVideoFrameRateEnabled` (min iOS 18.0) at its default of `false`. When on, the device lowers frame rate in low light, and "attempting to set a device's `activeVideoMinFrameDuration` or `activeVideoMaxFrameDuration` throws an exception." [Documentation](https://developer.apple.com/documentation/avfoundation/avcapturedevice/isautovideoframerateenabled).
- **[V] Exposure.** `setExposureModeCustom(duration:iso:completionHandler:)` "Sets the exposure mode to a custom state, and locks exposure duration and ISO at explicit values." [Documentation](https://developer.apple.com/documentation/avfoundation/avcapturedevice/setexposuremodecustom(duration:iso:completionhandler:)) (min iOS 8.0). Valid durations lie between the format's `minExposureDuration` and `maxExposureDuration` ([exposureDuration](https://developer.apple.com/documentation/avfoundation/avcapturedevice/exposureduration)).
- **[I]** For a moving bar end, a short fixed exposure (well under the 8.3 ms frame interval) limits motion blur on the tag. The right duration and ISO for gym lighting is a benchmark and calibration matter.
- **[V] Focus.** `setFocusModeLocked(lensPosition:completionHandler:)` "Locks the lens position at the specified value, and sets the focus mode to a locked state." [Documentation](https://developer.apple.com/documentation/avfoundation/avcapturedevice/setfocusmodelocked(lensposition:completionhandler:)) (min iOS 8.0). Check [`isLockingFocusWithCustomLensPositionSupported`](https://developer.apple.com/documentation/avfoundation/avcapturedevice/islockingfocuswithcustomlenspositionsupported) (min iOS 10.0) first; if it is false, only locking at the current lens position is allowed.
- **[V] White balance.** `setWhiteBalanceModeLocked(with:completionHandler:)` locks gains. [Documentation](https://developer.apple.com/documentation/avfoundation/avcapturedevice/setwhitebalancemodelocked(with:completionhandler:)) (min iOS 8.0). It matters little for luma-only tracking but keeps the Recording consistent.
- **[V] Other automatic behaviour to switch off.** Video HDR is automatic by default: "By default, this value is `true`, and a capture device automatically enables `isVideoHDREnabled` if it's a good fit for the active format." [automaticallyAdjustsVideoHDREnabled](https://developer.apple.com/documentation/avfoundation/avcapturedevice/automaticallyadjustsvideohdrenabled) (min iOS 8.0). Low-light boost defaults to off, and Apple notes that switching in or out of it "may drop one or more video frames." [automaticallyEnablesLowLightBoostWhenAvailable](https://developer.apple.com/documentation/avfoundation/avcapturedevice/automaticallyenableslowlightboostwhenavailable) (min iOS 6.0).
- **[V] Video stabilisation.** It is off unless requested: `preferredVideoStabilizationMode` "defaults to `AVCaptureVideoStabilizationMode.off`." Apple also notes "Video stabilization introduces additional latency into the video capture pipeline". Set `.off` explicitly on the data output's connection and confirm with `activeVideoStabilizationMode`, which "explicitly indicates whether it's using stabilization". [preferredVideoStabilizationMode](https://developer.apple.com/documentation/avfoundation/avcaptureconnection/preferredvideostabilizationmode), [activeVideoStabilizationMode](https://developer.apple.com/documentation/avfoundation/avcaptureconnection/activevideostabilizationmode) (min iOS 8.0).
- **[V] OIS.** The XR has "Optical image stabilization for video" ([tech specs](https://support.apple.com/en-us/111868)). The only OIS switch I found in AVFoundation is for bracketed still photos: `AVCapturePhotoBracketSettings.isLensStabilizationEnabled`, "the photo output uses optical image stabilization to hold the lens steady for the duration of the bracketed capture". [Documentation](https://developer.apple.com/documentation/avfoundation/avcapturephotobracketsettings/islensstabilizationenabled) (min iOS 10.0). The documentation for `AVCaptureVideoStabilizationMode.off` says only "A mode that doesn't stabilize video capture." and does not mention the lens. [Documentation](https://developer.apple.com/documentation/avfoundation/avcapturevideostabilizationmode/off).
- **[I]** There is no documented way for a third-party app to disable OIS for video. Absence from the documentation is not proof, which is why this is labelled inferred. A developer asked Apple this exact question on the forums and has had no reply ([thread 801283](https://developer.apple.com/forums/thread/801283), lead only).
- **[U]** Whether the XR lens actually moves during 1080p120 capture with stabilisation mode `.off` on a rigid mount, and whether that movement is large enough to matter for calibration (bar impacts and dropped plates shake the rack).

### 4. Per-frame timestamp sidecar

- **[V]** Each delivered frame is a `CMSampleBuffer`; its presentation timestamp is read with [`CMSampleBufferGetPresentationTimeStamp`](https://developer.apple.com/documentation/coremedia/cmsamplebuffergetpresentationtimestamp(_:)) (min iOS 4.0).
- **[V]** The clock those timestamps are on is published by the session: "All capture output sample buffer timestamps are on the synchronization clock's timebase." [AVCaptureSession.synchronizationClock](https://developer.apple.com/documentation/avfoundation/avcapturesession/synchronizationclock) (min iOS 15.4). The same page shows how to convert a timestamp to the device's own clock with `sessionClock.convertTime(syncedPTS, to: originalClock)`, using the input port's [`clock`](https://developer.apple.com/documentation/avfoundation/avcaptureinput/port/clock) (min iOS 7.0).
- **[I]** With a single video input and no audio, the synchronization clock is very likely the device host-time clock, so timestamps would be directly comparable to `mach_absolute_time`-based times on the same phone. Apple does not state this; the Station app should log the session clock and compare it with `CMClockGetHostTimeClock()` at start.
- **[U]** How Station timestamps relate to the Host's clock and to the Criterion. That is a cross-device alignment question outside this ticket; the sidecar only needs to preserve the on-device timestamps exactly.
- **[I] Recommended sidecar design.** No Apple API writes this; it is app code. One append-only file per Recording, written from the capture callback queue, flushed every second or so:
  - Header: device ID, calibration version, capture format (dimensions, frame rate, pixel format), codec, exposure duration, ISO, lens position, name of the session clock, the writer's `startSession` source time, app and iOS version.
  - One row per delivered frame: frame index, timestamp as the raw `CMTime` value and timescale (store integers, not a rounded float), whether it was appended to the Recording, whether it was sent to tag detection.
  - One row per dropped frame: the timestamp from the drop callback and the drop reason.
  - Event rows: system pressure level and factors, thermal state, session interruptions, runtime errors, changes to the detection rate.
- **[V]** An in-file alternative exists: `AVAssetWriterInputMetadataAdaptor` appends timed metadata groups to a writer input (min iOS 8.0), and `AVCaptureMetadataInput` does the same for a movie file output (min iOS 9.0). [AVAssetWriterInputMetadataAdaptor](https://developer.apple.com/documentation/avfoundation/avassetwriterinputmetadataadaptor), [AVCaptureMetadataInput](https://developer.apple.com/documentation/avfoundation/avcapturemetadatainput).
- **[I]** A separate sidecar file is the better primary record: it survives a damaged movie file, can be read without AVFoundation, and can record frames that never reached the file. Timed metadata could be added later as a duplicate.
- **[I]** The movie track also holds each frame's timestamp minus the session start time (finding 2), so the sidecar can be cross-checked against the Recording after a Session. Whether the round trip is exact to the tick depends on the track timescale the writer chooses ([`mediaTimeScale`](https://developer.apple.com/documentation/avfoundation/avassetwriterinput/mediatimescale) defaults to "an appropriate value"); check this in the benchmark.

### 5. Detecting and logging dropped frames

- **[V]** The data output reports each drop: "This method is called once for each dropped frame." The dropped buffer carries a reason attachment. [captureOutput(_:didDrop:from:)](https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutputsamplebufferdelegate/captureoutput(_:diddrop:from:)) (min iOS 6.0). The marker buffers "contain no image or data buffer." [kCMSampleBufferAttachmentKey_DroppedFrameReason](https://developer.apple.com/documentation/coremedia/kcmsamplebufferattachmentkey_droppedframereason).
- **[V]** The three reasons:
  - `FrameWasLate`: "typically caused by the client's processing taking too long." [Documentation](https://developer.apple.com/documentation/coremedia/kcmsamplebufferdroppedframereason_framewaslate)
  - `OutOfBuffers`: "typically caused by the client holding onto buffers for too long". [Documentation](https://developer.apple.com/documentation/coremedia/kcmsamplebufferdroppedframereason_outofbuffers)
  - `Discontinuity`: "an unknown number of frames have been lost. This condition is typically caused by the system being too busy." [Documentation](https://developer.apple.com/documentation/coremedia/kcmsamplebufferdroppedframereason_discontinuity)
- **[V]** Because a discontinuity can hide an unknown number of lost frames, the callback count alone is not a complete record.
- **[I]** The sidecar timestamps are the complete record: at a fixed 120 fps, any gap between consecutive timestamps noticeably larger than 8.33 ms is a lost frame, whatever the cause. The Station app should compute this live and after the Session.
- **[V]** Late-frame policy is a setting. With `alwaysDiscardsLateVideoFrames = true` (the default) the output discards frames while the delegate queue is blocked. "When set to `false`, the output gives delegates more time to process old frames before it discards new frames, but application memory usage may increase significantly as a result." [alwaysDiscardsLateVideoFrames](https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput/alwaysdiscardslatevideoframes) (min iOS 4.0).
- **[I]** For a pipeline that must record every frame, `false` is the right setting, combined with a callback that does almost nothing. This is the trade-off Apple describes: "If you need to minimize the chances of frames being dropped, you should specify a queue on which a sufficiently small amount of processing is being done ... you are responsible for ensuring that memory usage does not grow without bound". [setSampleBufferDelegate(_:queue:)](https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput/setsamplebufferdelegate(_:queue:)).
- **[V]** Both delegate methods run on the capture queue and Apple says each "must be efficient". Keep file I/O for the sidecar buffered.
- **[V]** Encoder-side losses appear separately: `isReadyForMoreMediaData` going false (finding 2), or `append(_:)` returning `false`, in which case "check the value of the asset writer's `status` property". [append(_:)](https://developer.apple.com/documentation/avfoundation/avassetwriterinput/append(_:)). Log both in the sidecar.
- **[V]** Give the encoder the frame rate as a hint. `AVVideoExpectedSourceFrameRateKey` "should be set if ... the source content has a high frame rate higher than 30 fps. The encoder might have to drop frames to satisfy bit stream requirements if this key is not specified." [Documentation](https://developer.apple.com/documentation/avfoundation/avvideoexpectedsourceframeratekey) (min iOS 7.0). Confirm that the recommended settings dictionary already includes it at 120; add it if not.
- **[U]** The actual drop rate on an XR at 1080p120 over 60+ minutes, with tag detection running, for each `alwaysDiscardsLateVideoFrames` setting.

### 6. Thermal and system pressure, and degrading gracefully

- **[V]** The camera has its own pressure signal. `AVCaptureDevice.systemPressureState` (min iOS 11.1) is key-value observable and carries a level and contributing factors. "If during a capture session the total system pressure reaches excessive levels, the capture system automatically shuts down, causing a session interruption ... Under less heavy pressure, the system may automatically reduce capture quality." [SystemPressureState](https://developer.apple.com/documentation/avfoundation/avcapturedevice/systempressurestate-swift.class).
- **[V]** Levels and Apple's guidance: `serious`, "Consider limiting the frame rate until system pressure state improves." `critical`, "Capture quality and performance are significantly impacted. Reduce the frame rate until system pressure state improves." `shutdown`, "the capture system automatically shuts down, causing a session interruption." [serious](https://developer.apple.com/documentation/avfoundation/avcapturedevice/systempressurestate-swift.class/level-swift.struct/serious), [critical](https://developer.apple.com/documentation/avfoundation/avcapturedevice/systempressurestate-swift.class/level-swift.struct/critical), [shutdown](https://developer.apple.com/documentation/avfoundation/avcapturedevice/systempressurestate-swift.class/level-swift.struct/shutdown).
- **[V]** Factors include overall temperature and battery condition. `peakPower`: "Devices with chemically aged batteries are less able to respond to rapid increases in total power usage ... the system may limit capture sperformance to prevent an unexpected device shutdown." [peakPower](https://developer.apple.com/documentation/avfoundation/avcapturedevice/systempressurestate-swift.class/factors-swift.struct/peakpower). The XRs are old phones, so battery health is a real factor, separate from heat.
- **[V]** Apple's stated mitigation is to lower the capture frame rate: "You can effectively mitigate system pressure by lowering the device's `activeVideoMinFrameDuration` in response to changes in the system pressure state." [systemPressureState](https://developer.apple.com/documentation/avfoundation/avcapturedevice/systempressurestate-swift.property). (The sentence says "lowering"; the intent, from the surrounding text on "frame rate throttling", is a lower frame rate.)
- **[V]** The system-wide signal is `ProcessInfo.thermalState` (min iOS 11.0) with `thermalStateDidChangeNotification`. At `serious`, "Reduce CPU and GPU usage by stopping or deferring work"; at `critical`, "If possible, stop using peripherals such as the camera". [serious](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum/serious), [critical](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum/critical). Note the registration rule: "you must access the `thermalState` prior to registering for the notification." [Documentation](https://developer.apple.com/documentation/foundation/processinfo/thermalstatedidchangenotification).
- **[V]** A pressure shutdown arrives as a session interruption with reason `videoDeviceNotAvailableDueToSystemPressure` (min iOS 11.1); the notification's user info includes the pressure state. [InterruptionReason](https://developer.apple.com/documentation/avfoundation/avcapturesession/interruptionreason/videodevicenotavailableduetosystempressure), [wasInterruptedNotification](https://developer.apple.com/documentation/avfoundation/avcapturesession/wasinterruptednotification).
- **[V]** The camera stops if the app leaves the foreground: "Camera usage is prohibited while in the background." [videoDeviceNotAvailableInBackground](https://developer.apple.com/documentation/avfoundation/avcapturesession/interruptionreason/videodevicenotavailableinbackground). Keep the screen awake with [`isIdleTimerDisabled`](https://developer.apple.com/documentation/uikit/uiapplication/isidletimerdisabled) (min iOS 2.0).
- **[I] Recommended degradation ladder.** Steps 1 and 2 are app logic and reduce CPU load without touching the Recording. Step 3 is Apple's documented mitigation and does change the Recording.
  1. Pressure `fair` or `serious`, or thermal `serious`: run tag detection on every second frame (60 fps) and dim the screen. Keep appending all 120 fps. Log the change.
  2. Still rising: run detection on every fourth frame, or pause live feedback and show that state at the Station. Keep recording.
  3. Pressure `critical`: lower the capture rate to 60 fps with `activeVideoMinFrameDuration` and `activeVideoMaxFrameDuration`. The Recording continues in the same file with its true timestamps, since the writer takes timing from each buffer (finding 2). Log the change; analysis must then handle a Recording with mixed frame rates.
  4. `shutdown` interruption: log it, keep the writer open, and resume appending when `interruptionEndedNotification` arrives, leaving a visible gap in the timestamps. If the app cannot keep the writer open, finish the file and start a second one, and record that the Recording is in two parts.
- **[I]** Halving detection rate should help because AprilTag detection is CPU work the app controls. Whether it helps enough is unknown: the sensor, image signal processor, and encoder still run at 120 fps.
- **[U]** Whether an XR reaches `serious`, `critical`, or `shutdown` during 60+ minutes of 1080p120 capture, encoding, and detection in a warm gym, on charger power, in whatever case or mount is used; and whether step 1 is enough to stop the climb.
- **[U]** Whether a single `AVAssetWriter` survives a session interruption and accepts frames afterwards (step 4).
- **[U]** Whether the system "automatically reduce[s] capture quality" under pressure in a way that shows up as a silently reduced frame rate. The sidecar timestamps will reveal it.

### 7. Storage per minute at 1080p120

No Apple support page or developer documentation page that I could find states a per-minute size for 1080p120. The numbers below are estimates with their basis shown.

- **Conversion.** Megabytes per minute = average bitrate in Mbit/s x 7.5. Gigabytes per hour = Mbit/s x 0.45.
- **[V]** In the recommended pipeline the bitrate is not fixed by Apple documentation. It is whatever `recommendedVideoSettings(forVideoCodecType:assetWriterOutputFileType:)` returns for the XR's active format, described only as "comparable to that of `AVCaptureMovieFileOutput`", or whatever the app sets with [`AVVideoAverageBitRateKey`](https://developer.apple.com/documentation/avfoundation/avvideoaveragebitratekey).
- **[V]** The XR records both codecs ("Video formats recorded: HEVC and H.264", [tech specs](https://support.apple.com/en-us/111868)), and iPhone 7 and later can capture HEVC ([Using HEIF or HEVC media on Apple devices](https://support.apple.com/en-us/116944)). Which codecs the data output offers for the writer is listed by [`availableVideoCodecTypesForAssetWriter(writingTo:)`](https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput/availablevideocodectypesforassetwriter(writingto:)) (min iOS 11.0).
- **Estimate (secondary source, labelled as such).** The iOS Settings app, under Camera > Record Slo-mo, shows per-minute sizes for Apple's own Camera app. Third-party write-ups that transcribe that screen give about 170 MB per minute for 1080p at 120 fps in High Efficiency (HEVC) and about 350 MB per minute in Most Compatible (H.264). I did not read these figures on an Apple page; they should be read off an XR's Settings screen during the benchmark. Example secondary sources: [iMore](https://www.imore.com/how-turn-4k-video-your-iphone-6s), [iDownloadBlog](https://www.idownloadblog.com/?p=532815).

| Codec | Per minute (estimate) | Implied bitrate | Per 60-minute Recording |
| --- | --- | --- | --- |
| HEVC | about 170 MB | about 23 Mbit/s | about 10 GB |
| H.264 | about 350 MB | about 47 Mbit/s | about 21 GB |

- **[I]** A third-party pipeline using the recommended settings should land near these figures, because Apple says the recommended settings match the movie file output. The gym scene (static background, small moving bar) may compress better than typical footage; a short exposure with higher ISO adds noise and compresses worse.
- **[I]** HEVC is the sensible default: roughly half the storage for a Recording that must be kept and transferred to the Host. The cost is encoder load on the A12, which is a benchmark question.
- **[U]** Actual MB per minute on the XR for each codec with the recommended settings; whether HEVC encoding at 1080p120 holds real time for an hour; free space needed per Station for the longest Session (check each XR's capacity).
- **[I]** The app must watch free space itself when using the writer. The movie file output has a built-in guard ([`minFreeDiskSpaceLimit`](https://developer.apple.com/documentation/avfoundation/avcapturefileoutput/minfreediskspacelimit)); `AVAssetWriter` documents no equivalent, so the Station app should check available capacity before a Session and during it.

## iOS 26-only items (unavailable on the XRs)

| API | Min iOS | What it would give | What the XRs do instead |
| --- | --- | --- | --- |
| [`AVCaptureDeviceInput.activeLockedVideoFrameDuration`](https://developer.apple.com/documentation/avfoundation/avcapturedeviceinput/activelockedvideoframeduration), with `isLockedVideoFrameDurationSupported`, `AVCaptureDevice.isVideoFrameDurationLocked`, `minSupportedLockedVideoFrameDuration` | 26.0 | "Setting this property guarantees the intra-frame duration delivered by the device input is precisely the frame duration you request." | Set min and max frame duration equal, and treat the sidecar timestamps as the truth about frame timing. |
| [`AVCaptureDeviceInput.follow(_:videoFrameDuration:delegate:)`](https://developer.apple.com/documentation/avfoundation/avcapturedeviceinput/follow(_:videoframeduration:delegate:)), [`AVExternalSyncDevice`](https://developer.apple.com/documentation/avfoundation/avexternalsyncdevice), `AVCaptureDevice.isFollowingExternalSyncDevice` | 26.0 | Genlock: the sensor follows an external sync pulse. | No hardware sync between Stations. Alignment across devices is done from timestamps. |

- **[V]** All of the above are documented as introduced in iOS 26.0. An Apple DTS engineer named the first two as the genlock-related APIs in [forum thread 799739](https://developer.apple.com/forums/thread/799739) (Apple staff reply).
- **[I]** These may also be limited by hardware even on iOS 26; the thread concerns the iPhone 17 Pro. That only matters for the reference camera.
- **[V]** Nothing in the recommended pipeline or the fallback needs iOS 26. The newest APIs used are `AVCaptureSession.synchronizationClock` (15.4), `hardwareCost` (16.0), and the iOS 16 output-combination rule. `isAutoVideoFrameRateEnabled` (18.0) is only mentioned so it is left off. `fileOutput(_:didStartRecordingTo:startPTS:from:)` (18.2) applies to the fallback only; confirm the XRs run 18.2 or later if the fallback is used.

## What only the XR benchmark can settle

1. The XR's actual format list: 1080p formats, their maximum frame rates (120 and 240), binning, field of view, exposure and ISO ranges, and the pixel formats offered.
2. Whether data output plus `AVAssetWriter` sustains 1080p120 for 60+ minutes with zero or near-zero dropped frames while tag detection runs; the drop count by reason.
3. Whether HEVC encoding holds real time at 1080p120 on the A12 for an hour, compared with H.264 (`isReadyForMoreMediaData` never false).
4. Memory behaviour in 3 GB with `alwaysDiscardsLateVideoFrames = false`, including the detection queue's copies.
5. System pressure and thermal state over the hour, on charger power, in the real mount and room temperature; whether dropping detection to 60 fps stops the climb; whether the session is ever interrupted.
6. Whether the fallback (movie file output plus data output) is accepted at 1080p120 (`canAddOutput`, `hardwareCost`), and its drop rate compared with the writer path.
7. Whether the OIS lens moves with stabilisation off on a rigid mount, and whether tag position is stable for a static tag over time and through rack impacts.
8. Actual storage per minute for HEVC and H.264 with the recommended settings, and the Settings > Camera figures read off the XR itself.
9. Timestamp quality: the distribution of intervals between consecutive frames at a nominal 1/120 s; whether the session clock equals the host-time clock; whether timestamps read back from the movie file match the sidecar exactly.
10. Whether one `AVAssetWriter` can keep writing across a session interruption, or the Recording must split.
11. Whether the 240 fps format is usable at all for an hour (expected to be harder on every count above). Only worth running if 120 fps passes with margin.
12. Battery-health effects: whether any XR reports the `peakPower` pressure factor.

## Sources

Apple developer documentation (read as JSON on 2026-11-12):

- AVCaptureSession: https://developer.apple.com/documentation/avfoundation/avcapturesession
- canAddOutput(_:): https://developer.apple.com/documentation/avfoundation/avcapturesession/canaddoutput(_:)
- hardwareCost: https://developer.apple.com/documentation/avfoundation/avcapturesession/hardwarecost
- synchronizationClock: https://developer.apple.com/documentation/avfoundation/avcapturesession/synchronizationclock
- wasInterruptedNotification: https://developer.apple.com/documentation/avfoundation/avcapturesession/wasinterruptednotification
- InterruptionReason (system pressure, background): https://developer.apple.com/documentation/avfoundation/avcapturesession/interruptionreason
- AVCaptureDevice formats, activeFormat, activeVideoMinFrameDuration, activeVideoMaxFrameDuration, isAutoVideoFrameRateEnabled, setExposureModeCustom, setFocusModeLocked, setWhiteBalanceModeLocked, automaticallyAdjustsVideoHDREnabled, automaticallyEnablesLowLightBoostWhenAvailable, systemPressureState: under https://developer.apple.com/documentation/avfoundation/avcapturedevice
- AVCaptureDevice.SystemPressureState and its levels and factors: https://developer.apple.com/documentation/avfoundation/avcapturedevice/systempressurestate-swift.class
- AVCaptureDeviceInput videoMinFrameDurationOverride, activeLockedVideoFrameDuration, follow(_:videoFrameDuration:delegate:): under https://developer.apple.com/documentation/avfoundation/avcapturedeviceinput
- AVExternalSyncDevice: https://developer.apple.com/documentation/avfoundation/avexternalsyncdevice
- AVCaptureConnection preferredVideoStabilizationMode, activeVideoStabilizationMode: under https://developer.apple.com/documentation/avfoundation/avcaptureconnection
- AVCaptureVideoStabilizationMode: https://developer.apple.com/documentation/avfoundation/avcapturevideostabilizationmode
- AVCapturePhotoBracketSettings.isLensStabilizationEnabled: https://developer.apple.com/documentation/avfoundation/avcapturephotobracketsettings/islensstabilizationenabled
- AVCaptureVideoDataOutput and its alwaysDiscardsLateVideoFrames, videoSettings, availableVideoPixelFormatTypes, automaticallyConfiguresOutputBufferDimensions, setSampleBufferDelegate, recommendedVideoSettings, availableVideoCodecTypesForAssetWriter: under https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput
- AVCaptureVideoDataOutputSampleBufferDelegate didOutput and didDrop: under https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutputsamplebufferdelegate
- AVCaptureMovieFileOutput, movieFragmentInterval; AVCaptureFileOutput maxRecordedDuration, minFreeDiskSpaceLimit; AVCaptureFileOutputRecordingDelegate: under https://developer.apple.com/documentation/avfoundation/avcapturemoviefileoutput and https://developer.apple.com/documentation/avfoundation/avcapturefileoutput
- AVCaptureMetadataInput: https://developer.apple.com/documentation/avfoundation/avcapturemetadatainput
- AVAssetWriter, movieFragmentInterval, startSession(atSourceTime:): under https://developer.apple.com/documentation/avfoundation/avassetwriter
- AVAssetWriterInput expectsMediaDataInRealTime, isReadyForMoreMediaData, append(_:), mediaTimeScale: under https://developer.apple.com/documentation/avfoundation/avassetwriterinput
- AVAssetWriterInputMetadataAdaptor: https://developer.apple.com/documentation/avfoundation/avassetwriterinputmetadataadaptor
- AVVideoExpectedSourceFrameRateKey, AVVideoAverageBitRateKey: under https://developer.apple.com/documentation/avfoundation
- Core Media dropped-frame reason constants and CMSampleBufferGetPresentationTimeStamp: under https://developer.apple.com/documentation/coremedia
- ProcessInfo.thermalState, ThermalState, thermalStateDidChangeNotification: under https://developer.apple.com/documentation/foundation/processinfo
- UIApplication.isIdleTimerDisabled: https://developer.apple.com/documentation/uikit/uiapplication/isidletimerdisabled

Apple technical notes, sessions, and support pages:

- TN3121, Selecting a pixel format for an AVCaptureVideoDataOutput: https://developer.apple.com/documentation/technotes/tn3121-selecting-a-pixel-format-for-an-avcapturevideodataoutput
- TN2409, New AV Foundation Camera Features for the iPhone 6 and iPhone 6 Plus (archived; background on stabilisation modes and OIS for stills): https://developer.apple.com/library/archive/technotes/tn2409/_index.html
- WWDC22 session 110429, Discover advancements in iOS camera capture: https://developer.apple.com/videos/play/wwdc2022/110429/
- iPhone XR Technical Specifications: https://support.apple.com/en-us/111868
- Using HEIF or HEVC media on Apple devices: https://support.apple.com/en-us/116944

Apple Developer Forums:

- Thread 799739, genlock APIs, answered by an Apple DTS engineer: https://developer.apple.com/forums/thread/799739
- Thread 801283, disabling OIS, no replies (lead only): https://developer.apple.com/forums/thread/801283
- Thread 807734, movie file output plus data output failing with ProRes, no replies (lead only): https://developer.apple.com/forums/thread/807734
- Thread 98113, pre-iOS 16 answer from a non-Apple poster (outdated, lead only): https://developer.apple.com/forums/thread/98113

Secondary (storage figures only, not load-bearing):

- iMore: https://www.imore.com/how-turn-4k-video-your-iphone-6s
- iDownloadBlog: https://www.idownloadblog.com/?p=532815
