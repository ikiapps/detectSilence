#!/usr/bin/env xcrun swift

/// detectSilence 1.0.1
///
/// Copyright (c) 2017 ikiApps LLC.
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.
///
/// This is a Swift 3 script that uses ffmpeg and its detectsilence filter to detect
/// areas of silence in audio files. It requires that ffmpeg is installed on your system.
///
/// Usage example: detectSilence ${ANY_VALID_BASE_PATH} 2>/dev/null
///
/// Note: Directing stderr output to null is optional.  I've added this to
/// silence the complaints from Swift over its awkward framework linking
/// situation in the context of command line tools.
///
/// Pass in a path as the first argument and it will be recursively scanned.
///
/// This script depends on ffmpeg.
/// See https://trac.ffmpeg.org/wiki/CompilationGuide/MacOSX for how to install ffmpeg.
///
/// Sample output from an ffmpeg report when silence is detected:
///
/// [silencedetect @ 0x1027000c0] silence_start: 334.117
/// [silencedetect @ 0x1027000c0] silence_end: 431.543 | silence_duration: 97.4255
///
/// The output is parsed to obtain the values that are reported.
///
/// The script is configured by four global variables.
/// 1. gMinNoiseLevel
/// 2. gMinSilenceDuration
/// 3. gDurationFlagThreshold
/// 4. gFfmpegPath

import Foundation
import RxSwift

/// Amplitude is considered silence when it is at or below the minimum noise level.
var gMinNoiseLevel: String = "-90.0dB"

/// The minimum duration that will be regarded as silence.
var gMinSilenceDuration: String = "0.25"

/// Threshold at which a flag (🚩) will be printed during output of values.
var gDurationFlagThreshold: Double = 1

/// The exact location of the ffmpeg binary.
var gFfmpegPath = "/usr/local/bin/ffmpeg"

/// Holds the data for silences found.
struct SilenceResult
{
    var start: String?
    var end: String?
    var duration: String?
    var path: NSURL?
}

/// Parse ffmpeg output to determine silences. Return the result as a struct.
private func silenceResults(_ result: String) -> Observable<SilenceResult?>
{
    return Observable.create { observer in
        let regex = try? NSRegularExpression(pattern: "silence_(.*?)\\:\\s(\\d*\\.?\\d*)\\b",
                                             options: NSRegularExpression.Options.caseInsensitive)

        guard let uwRegex = regex else {
            fatalError("Regex could not be formed.");
        }

        let numberOfMatches = uwRegex.numberOfMatches(in: result,
                                                      options: [],
                                                      range: NSMakeRange(0, result.characters.count))
        if numberOfMatches == 0 {
            observer.onNext(nil);
        } else {
            let bag = DisposeBag()

            textReportParses(withRegex: uwRegex,
                             inReport: result)
                .subscribe(onNext: { (silenceResult) in
                    observer.onNext(silenceResult);
            }).addDisposableTo(bag)
        }

        return Disposables.create();
    }
}

/// Find the points of silence given a report from ffmpeg.
private func textReportParses(withRegex: NSRegularExpression,
                              inReport: String) -> Observable<SilenceResult>
{
    return Observable.create { observer in
        var silenceResult = SilenceResult()

        withRegex.enumerateMatches(in: inReport,
                                   options: NSRegularExpression.MatchingOptions.reportCompletion,
                                   range: NSMakeRange(0, inReport.characters.count),
                                   using: { (match, flags, stop) in
            guard let uwMatch = match else {
                return;
            }

            let range1 = uwMatch.rangeAt(1)
            let start1 = inReport.index(inReport.startIndex,
                                        offsetBy: range1.location)
            let end1   = inReport.index(start1,
                                        offsetBy: range1.length)
            let text   = inReport.substring(with: start1..<end1)

            let range2 = uwMatch.rangeAt(2)
            let start2 = inReport.index(inReport.startIndex,
                                        offsetBy: range2.location)
            let end2   = inReport.index(start2,
                                        offsetBy: range2.length)
            let value  = inReport.substring(with: start2..<end2)

            switch text {
                case "start":
                    silenceResult.start = value
                case "end":
                    silenceResult.end = value
                case "duration":
                    silenceResult.duration = value
                default:
                    fatalError("Found nonmatching case.");
            }

            observer.onNext(silenceResult)
        })

        return Disposables.create();
    };
}

/// Return true if a threshold has been reached or crossed.
private func flagThresholdExceeded(valueString: String) -> Bool
{
    if let uwValue = Double(valueString) {
        if uwValue >= gDurationFlagThreshold {
            return true;
        } else {
            return false;
        }
    } else {
        fatalError("Cannot convert value");
    }
}

private func printReport(silenceResult: SilenceResult?)
{
    guard let uwResult = silenceResult else {
        return;
    }

    let start = uwResult.start ?? "[none]"
    let end = uwResult.end ?? "[none]"
    let duration = uwResult.duration ?? "[none]"

    if duration != "[none]" &&
        flagThresholdExceeded(valueString: duration) {
        print("\t🚩 start \(start), end \(end), duration \(duration)")
    } else {
        print("\tstart \(start), end \(end), duration \(duration)")
    }
}

/// Run a task as a subprocess.
private func taskRuns(launchPath: String,
                      arguments: [String]) -> Observable<String>
{
    return Observable.create { observer in
        let task = Process()
        task.launchPath = launchPath
        task.arguments = arguments
        let pipe = Pipe()
        task.standardError = pipe
        task.launch()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let result = NSString(data: data,
                              encoding: String.Encoding.ascii.rawValue)! as String;

        observer.onNext(result)

        return Disposables.create();
    }
}

private extension NSURL
{
    /// Return if the NSURL belongs to a directory.
    var isDirectory: NSNumber? {
        let values = try? resourceValues(forKeys: [URLResourceKey.isDirectoryKey])
        if let uwIsDir = values?[URLResourceKey.isDirectoryKey] {
            return uwIsDir as? NSNumber;
        } else {
            return nil;
        }
    }
}

/// Get all files recursively based on a root path.
/// - parameter rootPath: The base path from which to recursively descend.
/// - returns: A stream of NSURLs.
func allFiles(rootPath: String) -> Observable<NSURL>
{
    return Observable.create { observer in
        let fileURL = URL(fileURLWithPath: rootPath)
        let fm = FileManager.default
        let dirEnum = fm.enumerator(at: fileURL,
                                    includingPropertiesForKeys: [URLResourceKey.nameKey,
                                                                 URLResourceKey.isDirectoryKey],
                                    options: [.skipsHiddenFiles],
                                    errorHandler: nil)

        while let file = dirEnum?.nextObject() as? NSURL {
            if file.isDirectory == 0 {
                observer.onNext(file)
            }
        }

        return Disposables.create();
    };
}

/// Use ffmpeg to detect silence in a file.
/// The arguments are vital to having ffmpeg work as a subprocess.
/// - parameter pathURL: A file path URL for any file.
/// - returns: A stream of SilenceResult structs.
func silences(_ pathURL: NSURL) -> Observable<SilenceResult?>
{
    return Observable.create { observer in
        let bag = DisposeBag()
        let path = pathURL.absoluteString?.removingPercentEncoding
        taskRuns(launchPath: gFfmpegPath,
                 arguments: ["-i",
                            path!,
                            "-nostdin",
                            "-loglevel",
                            "32",
                            "-af",
                            "silencedetect=noise=\(gMinNoiseLevel):d=\(gMinSilenceDuration)",
                            "-f",
                            "null",
                            "-"])
        .flatMap(silenceResults)
        .subscribe(onNext: { (silenceResult) in
            if var uwSilence = silenceResult {
                uwSilence.path = pathURL
                observer.onNext(uwSilence)
            }
        }).addDisposableTo(bag)

        return Disposables.create();
    };
}

// ------------------------------------------------------------
// MARK: - Main Program -
// ------------------------------------------------------------
let argCount = CommandLine.argc

guard argCount == 2 else {
    print("\nUsage: detectSilence ${A_VALID_ROOT_PATH_CONTAINING_AUDIO_FILES}\n")
    exit(EXIT_FAILURE);
}

let argument = CommandLine.arguments[1]

print("\nScanning files for silence:\n")

let bag = DisposeBag()

allFiles(rootPath: argument)
    .flatMap(silences)
    .subscribe(onNext: { (event: SilenceResult?) in
        if event != nil {
            print("Silence found in \(event?.path?.absoluteString?.removingPercentEncoding ?? "[Unknown]")")
            printReport(silenceResult: event)
        }
}).addDisposableTo(bag)

print("\nFinished scanning.")
