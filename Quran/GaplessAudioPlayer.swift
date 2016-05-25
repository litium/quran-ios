//
//  GaplessAudioPlayer.swift
//  Quran
//
//  Created by Mohamed Afifi on 5/16/16.
//  Copyright © 2016 Quran.com. All rights reserved.
//

import Foundation
import AVFoundation

private class GaplessPlayerItem: AVPlayerItem {
    let sura: Int
    init(URL: NSURL, sura: Int) {
        self.sura = sura
        super.init(asset: AVAsset(URL: URL), automaticallyLoadedAssetKeys: nil)
    }

    private override var description: String {
        return super.description + " sura: \(sura)"
    }
}

class GaplessAudioPlayer: AudioPlayer {

    weak var delegate: AudioPlayerDelegate?

    let player = QueuePlayer()

    let timingRetriever: QariTimingRetriever

    private var ayahsDictionary: [AVPlayerItem: [AyahNumber]] = [:]

    init(timingRetriever: QariTimingRetriever) {
        self.timingRetriever = timingRetriever
    }

    func play(qari qari: Qari, startAyah: AyahNumber, endAyah: AyahNumber) {
        let items = playerItemsForQari(qari, startAyah: startAyah, endAyah: endAyah)

        timingRetriever.retrieveTimingForQari(qari, suras: items.map { $0.sura }) { [weak self] timings in

            var mutableTimings = timings
            if let timeArray = mutableTimings[startAyah.sura] {
                mutableTimings[startAyah.sura] = Array(timeArray.dropFirst(startAyah.ayah - 1))
            }

            var times: [AVPlayerItem: [Double]] = [:]
            var ayahs: [AVPlayerItem: [AyahNumber]] = [:]
            for item in items {
                var array: [AyahTiming] = cast(mutableTimings[item.sura])
                if array.last?.ayah == AyahNumber(sura: item.sura, ayah: 999) {
                    array = Array(array.dropLast())
                }
                times[item] = array.enumerate().map { $0 == 0 ? 0 : $1.seconds }
                ayahs[item] = array.map { $0.ayah }
            }
            self?.ayahsDictionary = ayahs

            let startSuraTimes: [AyahTiming] = cast(mutableTimings[startAyah.sura])
            let startTime = startAyah.ayah == 1 ? 0 : startSuraTimes[0].seconds

            self?.player.onPlaybackEnded = { [weak self] in
                self?.delegate?.onPlaybackEnded()
            }
            self?.player.onPlaybackStartingTimeFrame = { [weak self] (item: AVPlayerItem, timeIndex: Int) in
                guard let item = item as? GaplessPlayerItem, let ayahs = self?.ayahsDictionary[item] else { return }
                self?.delegate?.playingAyah(ayahs[timeIndex])
            }

            self?.player.play(startTimeInSeconds: startTime, items: items, playingItemBoundaries: times)
        }
    }

    func pause() {
        player.pause()
    }

    func resume() {
        player.resume()
    }

    func stop() {
        player.stop()
        player.onPlaybackEnded = nil
        player.onPlayerItemChangedTo = nil
        player.onPlaybackStartingTimeFrame = nil
    }

    func goForward() {
        player.onStepForward()
    }

    func goBackward() {
        player.onStepBackward()
    }
}

extension GaplessAudioPlayer {

    private func playerItemsForQari(qari: Qari, startAyah: AyahNumber, endAyah: AyahNumber) -> [GaplessPlayerItem] {
        return filesToPlay(qari: qari, startAyah: startAyah, endAyah: endAyah).map { GaplessPlayerItem(URL: $0, sura: $1) }
    }

    private func filesToPlay(qari qari: Qari, startAyah: AyahNumber, endAyah: AyahNumber) -> [(NSURL, Int)] {

        guard case AudioType.Gapless = qari.audioType else {
            fatalError("Unsupported qari type gapped. Only gapless qaris can be played here.")
        }

        // loop over the files
        var files = [(NSURL, Int)]()
        for sura in startAyah.sura...endAyah.sura {
            let fileName = String(format: "%03d", sura)
            let localURL = qari.localFolder().URLByAppendingPathComponent(fileName).URLByAppendingPathExtension(Files.AudioExtension)
            files.append(localURL, sura)
        }
        return files
    }
}