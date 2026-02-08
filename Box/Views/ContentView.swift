import SwiftUI

struct ContentView: View {
    @ObservedObject var manager: PlaylistManager

    var body: some View {
        VStack(spacing: 0) {
            ControlsView(manager: manager)
            Divider()
            PlaylistView(manager: manager)
        }
        .background(.ultraThinMaterial)
        .frame(minWidth: 300, idealWidth: 320, minHeight: 400, idealHeight: 500)
    }
}
