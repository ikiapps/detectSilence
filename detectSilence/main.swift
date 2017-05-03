#!/usr/bin/env xcrun swift

var gName      = "detectSilence"
var gVersion   = "1.0.5"
var gCopyright = "Copyright (c) 2017 ikiApps LLC."

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
/// The script is configured by four global variables:
/// 1. gMinNoiseLevel
/// 2. gMinSilenceDuration
/// 3. gDurationFlagThresholdMiddleSilence
/// 4. gDurationFlagThresholdEndSilence
/// 5. gFfmpegPath

import Foundation
import RxSwift

// ------------------------------------------------------------
// MARK: - Configuration -
// ------------------------------------------------------------

/// Amplitude is considered silence when it is at or below the minimum noise level.
var gMinNoiseLevel: String = "-90.0dB"

/// The minimum duration that will be regarded as silence.
var gMinSilenceDuration: String = "0.25"

/// Middle occurring silence duration threshold at which a flag (🚩) will be printed during output of values.
var gDurationFlagThresholdSilenceMiddle: Double = 1

/// End occurring silence duration threshold at which a flag (🚩) will be printed during output of values.
var gDurationFlagThresholdSilenceEnd: Double = 2.5

/// The exact location of the ffmpeg binary.
var gFfmpegPath = "/usr/local/bin/ffmpeg"

var gNone = "🔳"

/// Holds the data for silences found.
struct SilenceResult
{
    var start:         String?
    var end:           String?
    var duration:      String?
    var path:          NSURL?
    var totalDuration: String?
}

// ------------------------------------------------------------
// MARK: - Private -
// ------------------------------------------------------------

/// Parse ffmpeg output to determine silences. Return the result as a struct.
private func silenceResults(_ result: String) -> Observable<SilenceResult?>
{
    return Observable.create { observer in
        let regex = try? NSRegularExpression(pattern: "silence_(.*?):\\s(\\-?\\d*\\.?\\d*)\\b",
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
                .distinctUntilChanged(silenceIsEqual)
                .subscribe(onNext: { (silenceResult) in
                    let allValuesNil = ([silenceResult.start,
                                         silenceResult.end,
                                         silenceResult.duration,
                                         silenceResult.totalDuration].flatMap{$0}.count == 0)

                    guard !allValuesNil else {
                        observer.onNext(nil);
                        return;
                    }

                    totalDuration(inReport: result).subscribe(onNext: { total in
                        var newResult = silenceResult
                        newResult.totalDuration = { return $0 != nil ? String($0!) : nil }(total)
                        observer.onNext(newResult);
                    }).addDisposableTo(bag)
            }).addDisposableTo(bag)
        }

        return Disposables.create();
    }
}

/// A comparator for silence results.
/// Used by subscription on textReportParses to get total duration.
private func silenceIsEqual(s1: SilenceResult, s2: SilenceResult) -> Bool
{
    if s1.start == s2.start &&
       s1.end == s2.end &&
       s1.duration == s2.duration &&
       s1.path == s2.path {
        return true;
    }
    return false;
}

/// Get the total duration of the audio file.
private func totalDuration(inReport: String) -> Observable<Double?>
{
    let regex = try? NSRegularExpression(pattern: "Duration:\\s(\\d*):(\\d*):(\\d*\\.?\\d*)",
                                         options: [])

    guard let uwRegex = regex else {
        fatalError("Regex could not be formed.");
    }

    let numberOfMatches = uwRegex.numberOfMatches(in: inReport,
                                                  options: [],
                                                  range: NSMakeRange(0, inReport.characters.count))
    if numberOfMatches == 0 {
        return Observable.just(nil);
    } else {
        var result: Double?
        let bag = DisposeBag()
        extractDuration(withRegex: uwRegex,
                        inReport: inReport)
            .subscribe(onNext: { value in
                result = value
        }).addDisposableTo(bag)

        return Observable.just(result);
    }
}

/// Extract the duration from the report.
private func extractDuration(withRegex: NSRegularExpression,
                             inReport: String) -> Observable<Double?>
{
    var result: Double?

    withRegex.enumerateMatches(in: inReport,
                               options: NSRegularExpression.MatchingOptions.reportCompletion,
                               range: NSMakeRange(0, inReport.characters.count),
                               using: { (match, flags, stop) in
        guard let uwMatch = match else {
            return;
        }

        let groups = uwMatch.getMatchGroups(content: inReport,
                                            matchCount: 3)

        guard let uwS = Double(groups[2]),
              let uwMin = Double(groups[1]),
              let uwH = Double(groups[0]) else {
            return;
        }

        let total = uwS + uwMin * 60 + uwH * 3600
        result = total
    })

    return Observable.just(result);
}

/// Find the points of silence in a text report from ffmpeg.
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

            let groups = uwMatch.getMatchGroups(content: inReport,
                                                matchCount: 2)
            let text = groups[0]
            let value = groups[1]

            switch text {
                case "start":
                    silenceResult.start = value
                case "end":
                    silenceResult.end = value
                case "duration":
                    silenceResult.duration = value
                    observer.onNext(silenceResult)
                    silenceResult = SilenceResult()
                default:
                    fatalError("Found nonmatching case.");
            }
        })

        observer.onNext(silenceResult)

        return Disposables.create();
    };
}

/// Make a horizontal graph representing silence that continues until the end of the file.
private func graphicEndSilence(_ start: String?, _ end: String?, _ duration: String?, _ total: String?) -> String?
{
    let maxChars: Double = 80
    guard end == nil && duration == nil else { return nil; }
    guard let uwStart = start, let uwTotal = total else { return nil; }
    guard let uwS = Double(uwStart), let uwT = Double(uwTotal) else { return nil; }
    let silentPercent = (uwT - uwS) / uwT
    let graphChars = Int(silentPercent * maxChars)
    guard graphChars >= 1 else { return nil; }
    return "\n\t" + drawGraph(0, graphChars);
}

private func drawGraph( _ current: Int, _ last: Int) -> String
{
    if current >= last { return ""; }
    else { return drawGraph(current + 1, last) + "▉"; }
}

private func printReport(silenceResult: SilenceResult?)
{
    guard let uwResult = silenceResult else {
        return;
    }

    let start = uwResult.start ?? nil,
        end = uwResult.end ?? nil,
        duration = uwResult.duration ?? nil,
        totalDuration = uwResult.totalDuration ?? nil
    var msg = "\t"

    // 1. Silence with a detected end occurs for a duration exceeding the global threshold.
    let flagThresholdExceededMiddle: (String?)->(Bool) = {
        return $0 != nil &&
              (Double($0!) ?? 0) >= gDurationFlagThresholdSilenceMiddle;
    }

    // 2. Silence with an undetected end occurs for a duration exceeding the global threshold.
    let flagThresholdExceededEnd: (String?, String?, String?)->(Bool) = {
        guard $0 != nil && $2 != nil else { return false; }
        let start = Double($0!) ?? 0, total = Double($2!) ?? 0
        return $1 == nil &&
               (total - start) >= gDurationFlagThresholdSilenceEnd;
    }

    if flagThresholdExceededMiddle(duration) ||
       flagThresholdExceededEnd(start, duration, totalDuration) {
        msg += "🚩 "
    }

    let allValuesNil = ([start, end, duration].flatMap{$0}.count == 0)
    guard !allValuesNil else { return; }

    msg += "start \(start ?? gNone), " +
        "end \(end ?? gNone), " +
        "duration \(duration ?? gNone)" +
        "\n\ttotal duration: \(totalDuration ?? gNone)"
    msg += graphicEndSilence(start, end, duration, totalDuration) ?? ""
    print(msg)
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

private extension NSTextCheckingResult
{
    /// Return match groups as an array of strings.
    func getMatchGroups(content: String,
                        matchCount: Int) -> [String]
    {
        var matches = [String](repeating: String(),
                               count: matchCount)

        for matchIndex in 1...matchCount {
            let range = self.rangeAt(matchIndex)
            let start = content.index(content.startIndex,
                                      offsetBy: range.location)
            let end = content.index(start,
                                    offsetBy: range.length)
            let text = content.substring(with: start..<end)
            matches[matchIndex - 1] = text
        }

        return matches;
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

// ------------------------------------------------------------
// MARK: - Public -
// ------------------------------------------------------------

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
// MARK: - Main Program
// ------------------------------------------------------------

print("\ndetectSilence v\(gVersion)")
let argCount = CommandLine.argc

guard argCount == 2 else {
    print("\nUsage: detectSilence ${A_VALID_ROOT_PATH_CONTAINING_AUDIO_FILES}\n")
    exit(EXIT_FAILURE);
}

print("\nScanning files for silence:\n")
let argument = CommandLine.arguments[1]
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
