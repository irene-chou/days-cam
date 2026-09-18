import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
            Text("Days Cam")
                .font(.title)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
