# A Swift Script for Detecting Silence in Audio Files: Made with Reactive Programming in RxSwift

![A stereo waveform with unexpected silence.](https://www.ikiapps.com/img/2017-03-15-swift-script-for-detecting-silence-in-audio-files/sample-waveform-w-silence.png)

Detecting silence in audio files is an essential capability to ensure correct audio processing. When handling large numbers of files, this can be a cumbersome and time-consuming task to perform manually. I've written a script in Swift to automate this job. It uses `ffmpeg` as a subprocess along with its `silencedetect` filter. I've written the script using Reactive Programming in Swift 3 and RxSwift. It's capable of relatively fast, recursive scanning of huge numbers of files given a single starting point while reliably reporting all of its results to the console.

This project is somewhat experimental since Mac command line tools do not yet have full support for linking external frameworks. The libraries for Swift still cannot be statically linked. Anything else containing Swift code cannot be built as a static framework. If a framework containing Swift code is linked, an external source of the Swift libraries must be provided. Thus, there is a high barrier to writing Swift scripts with RxSwift, but it is one that can be overcome.

The choice to use reactive programming for this script was made due to the streaming nature of processing files and handling of audio data as streams. I had this dream where everything is a stream 😊. I will cover more aspects of reactive programming in a future tutorial.

## Silence

The following silence cases are supported:

1. Silence occurring at the beginning of audio.
2. Silence occurring in the middle of audio.
3. Silence occurring at the end of audio.

Complete silence should be detected as case (1). Another option for this is the `volumedetect` filter.

## Usage

Usage for the script is:

    $ detectSilence ${ANY_VALID_BASE_PATH} 2>/dev/null

Here is a sample of the output:

    Silence found in file:///Audio-Files/2017-Mar-15/01.flac
        🚩 start -0.0410202, end 0.417959, duration 0.45898 
        total duration: 939.97
    Silence found in file:///Audio-Files/2017-Mar-19/01.flac
        🚩 start 2081.81, end 2088.02, duration 6.20592
        total duration: 3005.23
    Silence found in file:///Audio-Files/2017-Mar-17/02.flac
        🚩 start 301.103, end 🔳, duration 🔳
        total duration: 729.11
        ▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉


The red flags indicate silences that have exceeded a given duration. The `silencedetect` filter can detect silences with no end or no duration. These usually correspond to silences at the end of a file. This type of silence is also graphically represented to show its relative length with respect to the total duration. The level at which audio is considered silence is set by a noise floor variable in units of dB in the script.

## Installation

### Dependencies

The additional dependencies for this script beyond Xcode 8 are:

* [RxSwift](https://github.com/ReactiveX/RxSwift) (installed by [Carthage](https://github.com/Carthage/Carthage))
* [ffmpeg](https://trac.ffmpeg.org/wiki/CompilationGuide/MacOSX) with the `silencedetect` filter

Installation of RxSwift is accomplished with:

	$ carthage update

### Make the binary

Build the project with Xcode. Show the Products folder in the Finder from Xcode. Copy the contents of the Products folder to a location of your choice. The `detectSilence` binary is needed along with the RxSwift.framework directory and its contents. The detectSilence.swiftmodule directory is not needed because the Swift libraries are accessed from the toolchain (the command-line tools) of Xcode. This is the external source mentioned in the introduction.

That concludes the installation process. Once installed, the compiled script can be accessed as a normal command. 

### Alternative option 1: Add a Copy Files phase

Under build phases for the `detectSilence` target, add a Copy Files phase to copy the freshly built binary to an Absolute Path of your choice. Leave 'Copy only when installing' unchecked. With this phase added, every time the project is built, the binary will be updated in the destination location such as in `~/bin`.

## Conclusion

RxSwift for scripting is a probably an uncommon idea but, then again, Swift for scripting is still catching on, too. This project is a demonstration of the possibilities of both while providing a practical tool that can be enjoyed now.

---

## Release Notes

* v1.0.0 First release verified with Xcode 8.3, Swift 3.1 and RxSwift 3.3.1.
* v1.0.1 Made sure that the presence of variable width encoded characters do not affect text matches.
* v1.0.2 Handled negative numbers. Fixed output to show only when duration is available.
* v1.0.3 Added reporting of detectsilence starts that have no end. Added retrieval of total duration. These changes handle the case where silence starts in the middle of a file and continues until the end.
* v1.0.4 Added a graphic rendering of silences that extend all the way to the end of a file.
* v1.0.5 Prevented sending a result with no values.
* v1.0.6 Reduced some extraneous code.

## Repositories

The script has an open-source MIT license and repository links are here:

* [Github](https://github.com/ikiapps/detectSilence)
* [Bitbucket](https://bitbucket.org/ikiapps/detectsilence)
