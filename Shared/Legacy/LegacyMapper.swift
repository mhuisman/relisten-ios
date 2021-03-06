//
//  LegacyMapper.swift
//  RelistenShared
//
//  Created by Jacob Farkas on 8/12/18.
//  Copyright © 2018 Alec Gorge. All rights reserved.
//

import Foundation

class LegacyMapper {
    public struct GenericImportError : Error { }
    
    private let api : RelistenLegacyAPI = RelistenLegacyAPI()
    private let callbackQueue : DispatchQueue = DispatchQueue(label: "net.relisten.importer")
    
    // (farkas) Holy crap this is a mess. I'm hoping to replace this with a state machine soon. If you're reading this I failed at doing that :(
    public func matchLegacyTrack(_ trackID: Int, artist artistSlug: String, showID: Int, completion: @escaping (Track?, Error?) -> Void) {
        let group = DispatchGroup()
        var error : Error? = nil
        var fullArtist : ArtistWithCounts? = nil
        var legacyShow : LegacyShowWithTracks? = nil
        
        group.enter()
        fetchArtist(artistSlug) { (artist) in
            fullArtist = artist
            group.leave()
        }
        
        group.enter()
        DispatchQueue.main.async {
            self.api.fullShow(byArtist: artistSlug, showID: showID).getLatestDataOrFetchIfNeeded { (latestData, blockError) in
                if blockError != nil {
                    error = blockError
                }
                legacyShow = latestData?.typedContent()
                group.leave()
            }
        }
        
        group.notify(queue: self.callbackQueue) {
            if error == nil,
                let fullArtist = fullArtist,
                let legacyShow = legacyShow
            {
                LogDebug("[Import] Fetched artist and legacy show information for track \(trackID) in show \(showID)")
                self.continueMatchingLegacyTrack(trackID: trackID, legacyShow: legacyShow, fullArtist: fullArtist, completion: completion)
            } else {
                LogWarning("[Import] Couldn't fetch \(legacyShow == nil ? "legacy show" : "") \(fullArtist == nil ? "full artist" : "") for \(artistSlug)-\(showID)")
                // TODO: Create an error here if one doesn't exist
                if error == nil { error = GenericImportError() }
                completion(nil, error)
            }
        }
    }
    
    private func continueMatchingLegacyTrack(trackID: Int, legacyShow : LegacyShowWithTracks, fullArtist : ArtistWithCounts, completion: @escaping (Track?, Error?) -> Void) {
        var legacyTrack : LegacyTrack? = nil
        if let matchingTracksByID = legacyShow.tracks?.filter({ $0.id == trackID }) {
            if matchingTracksByID.count == 1 {
                legacyTrack = matchingTracksByID.first
            } else {
                LogWarning("Too many tracks matched the track with ID \(trackID). What gives?")
            }
        }
        
        if let displayDate = legacyShow.displayDate,
            let legacyTrack = legacyTrack {
            performOnMainQueueSync {
                RelistenApi.show(onDate: displayDate, byArtist: fullArtist).getLatestDataOrFetchIfNeeded { (latestData, blockError) in
                    self.callbackQueue.async {
                        if let newShow : ShowWithSources = latestData?.typedContent() {
                            if let matchingSource = self.findSource(inShow: newShow, fromLegacyShow: legacyShow) {
                                if let matchingTrack = matchingSource.findMatchingTrack(legacyTrack) {
                                    // We finally did it!
                                    LogDebug("[Import] Found a matching track in the new API for track \(trackID) in show \(legacyShow.id ?? -1)")
                                    let completeShowInfo = CompleteShowInformation(source: matchingSource, show: newShow, artist: fullArtist)
                                    let track = Track(sourceTrack: matchingTrack, showInfo: completeShowInfo)
                                    completion(track, nil)
                                } else {
                                    LogWarning("[Import] Couldn't find a matching track to match \(fullArtist.name)-\(legacyShow.displayDate ?? "?").\(legacyTrack.title ?? String(trackID))")
                                    completion(nil, GenericImportError())
                                }
                            } else {
                                LogWarning("[Import] Couldn't find a matching show from the new API to match \(fullArtist.name)-\(legacyShow.displayDate ?? "?")")
                                completion(nil, GenericImportError())
                            }
                        } else {
                            LogWarning("[Import] Couldn't get a show from the new API to match \(fullArtist.name)-\(legacyShow.displayDate ?? "?")")
                            var error = blockError
                            if error == nil { error = GenericImportError() }
                            completion(nil, error)
                        }
                    }
                }
            }
        } else {
            LogWarning("[Import] legacy show has no \(legacyShow.displayDate == nil ? "display date" : "") \(legacyTrack == nil ? "matching track" : "")")
            completion(nil, GenericImportError())
        }
    }
    
    public func getCompleteShowForDate(_ showDate: String, artist artistSlug: String, completion: @escaping (CompleteShowInformation?, Error?) -> Void) {
        let group = DispatchGroup()
        var error : Error? = nil
        var showInfo : CompleteShowInformation? = nil
        
        group.enter()
        fetchArtist(artistSlug) { (artist) in
            if let artist = artist {
                performOnMainQueueSync {
                    RelistenApi.show(onDate: showDate, byArtist: artist).getLatestDataOrFetchIfNeeded { (latestData, blockError) in
                        self.callbackQueue.async {
                            if let newShow : ShowWithSources = latestData?.typedContent() {
                                // The old version of relisten just saved the show date, not a specific source. We'll need to pick one here- let's just pick the highest rated source.
                                if let bestSource = newShow.bestSource() {
                                    showInfo = CompleteShowInformation(source: bestSource, show: newShow, artist: artist)
                                } else {
                                    error = GenericImportError()
                                }
                                group.leave()
                            } else {
                                error = GenericImportError()
                                group.leave()
                            }
                        }
                    }
                }
            } else {
                error = GenericImportError()
                group.leave()
            }
        }
        
        group.notify(queue: self.callbackQueue) {
            completion(showInfo, error)
        }
    }
    
    private func findSource(inShow show : ShowWithSources, fromLegacyShow legacyShow : LegacyShow) -> SourceFull? {
        var retval : SourceFull? = nil
        for source in show.sources {
            if source.matchesLegacyShow(legacyShow) {
                retval = source
                break
            }
        }
        return retval
    }
    
    private var slugToArtist : [String : ArtistWithCounts] = [:]
    public func fetchArtist(_ artistSlug: String, completion: @escaping ((ArtistWithCounts?) -> Void)) {
        if slugToArtist[artistSlug] != nil {
            completion(slugToArtist[artistSlug])
            return
        }
        
        performOnMainQueueSync {
            RelistenApi.artists().getLatestDataOrFetchIfNeeded { (latestData, _) in
                var resultArtist : ArtistWithCounts? = nil
                if let artists : [ArtistWithCounts] = latestData?.typedContent() {
                    for artist in artists {
                        if artist.slug == artistSlug {
                            resultArtist = artist
                        }
                    }
                }
                if resultArtist != nil {
                    self.slugToArtist[artistSlug] = resultArtist
                }
                self.callbackQueue.async { completion(resultArtist) }
            }
        }
    }
    
    public func fetchSlimArtist(withArtistSlug artistSlug: String, completion : @escaping ((SlimArtistWithFeatures?) -> Void)) {
        performOnMainQueueSync {
            RelistenApi.artist(withSlug: artistSlug).getLatestDataOrFetchIfNeeded { (latestData, _) in
                var artist : SlimArtistWithFeatures? = nil
                if let responseArtist : SlimArtistWithFeatures = latestData?.typedContent() {
                    artist = responseArtist
                }
                self.callbackQueue.async { completion(artist) }
            }
        }
    }
    
    public func loadShowInfoForDate(withArtistSlug artistSlug: String, showDate : String, completion : @escaping ((ShowWithSources?) -> Void)) {
        fetchSlimArtist(withArtistSlug: artistSlug) { (artist) in
            if let artist = artist {
                performOnMainQueueSync {
                    RelistenApi.show(onDate: showDate, byArtist: artist).getLatestDataOrFetchIfNeeded { (latestData, _) in
                        var show : ShowWithSources? = nil
                        if let responseShow : ShowWithSources = latestData?.typedContent() {
                            show = responseShow
                        }
                        self.callbackQueue.async { completion(show) }
                    }
                }
            }
        }
    }
}
    
extension ShowWithSources {
    fileprivate func bestSource() -> SourceFull? {
        var bestRating : Float = -1.0
        var bestSource : SourceFull? = nil
        for source in self.sources {
            if source.avg_rating_weighted > bestRating {
                bestRating = source.avg_rating_weighted
                bestSource = source
            }
        }
        return bestSource
    }
}

extension SourceFull {
    fileprivate func matchesLegacyShow(_ legacyShow : LegacyShow) -> Bool {
        if let archiveIdentifier = legacyShow.archive_identifier {
            if self.upstream_identifier == archiveIdentifier { return true }
        }
        
        if let source = self.source, let legacySource = legacyShow.source {
            if source != legacySource { return false }
        }
        if let lineage = self.lineage, let legacyLineage = legacyShow.lineage {
            if lineage != legacyLineage { return false }
        }
        if let taper = self.taper, let legacyTaper = legacyShow.taper, legacyTaper != "Unknown" {
            if taper != legacyTaper { return false }
        }
        if let transferer = self.transferrer, let legacyTransferer = legacyShow.transferer, legacyTransferer != "Unknown" {
            if transferer != legacyTransferer{ return false }
        }
        return true
    }
    
    fileprivate func findMatchingTrack(_ legacyTrack : LegacyTrack) -> SourceTrack? {
        // Match on MD5
        if let legacyMD5 = legacyTrack.md5 {
            let hashMatches = self.tracksFlattened.filter({ $0.md5 == legacyMD5 })
            if hashMatches.count == 1 {
                return hashMatches.first
            }
        }
        
        // Match on MP3 URL
        if let legacyMP3URL = legacyTrack.mp3_url {
            let urlMatches = self.tracksFlattened.filter({ $0.mp3_url == legacyMP3URL })
            if urlMatches.count == 1 {
                return urlMatches.first
            }
        }
        
        // Match on title
        if let legacyTitle = legacyTrack.title {
            let titleMatches = self.tracksFlattened.filter({ $0.title == legacyTitle })
            if titleMatches.count == 1 {
                return titleMatches.first
            } else if let legacyDuration = legacyTrack.duration {
                // Find a match that has the same duration
                let durationMatches = titleMatches.filter({ $0.duration == legacyDuration})
                if durationMatches.count == 1 {
                    return durationMatches.first
                }
            }
        }
        
        return nil
    }
}
