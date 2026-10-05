import SwiftUI

struct ThirdPartyNoticesView: View {
    private var license: String {
        guard let root = Bundle.main.url(forResource: "Notices", withExtension: nil) else { return "" }
        return (try? String(contentsOf: root.appendingPathComponent("VLCKit-COPYING.txt"), encoding: .utf8)) ?? ""
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("VLCKit · VideoLAN").font(.title2.bold())
                Text("Copyright © VLC authors and VideoLAN. Distributed under GNU LGPL 2.1 or later. Used without modification as a dynamically linked framework.")
                Link("VLCKit source code", destination: URL(string: "https://github.com/videolan/vlckit/tree/2e0868f5ed40fe59cd92f377645fdcc260c6e759")!)
                Link("VideoLAN source and build tools", destination: URL(string: "https://code.videolan.org/videolan/VLCKit")!)
                Text(license).font(.footnote).textSelection(.enabled)
            }.padding(24)
        }.background(MirrorStyle.background).navigationTitle("VLCKit · VideoLAN")
    }
}

struct CastNoticesView: View {
    private var notices: String {
        guard let root = Bundle.main.url(forResource: "Notices", withExtension: nil) else { return "" }
        return (try? String(contentsOf: root.appendingPathComponent("GoogleCast-COPYING.txt"), encoding: .utf8)) ?? ""
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Google Cast iOS SDK 4.8.6").font(.title2.bold())
                Link("Google Cast SDK", destination: URL(string: "https://developers.google.com/cast/docs/ios_sender")!)
                Text(notices).font(.footnote).textSelection(.enabled)
            }.padding(24)
        }.background(MirrorStyle.background).navigationTitle("Google Cast")
    }
}
