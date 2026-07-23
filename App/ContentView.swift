import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text("Activez l'extension dans Réglages → Apps → Safari → Extensions, puis autorisez-la sur tous les sites.")
                    } icon: {
                        Image(systemName: "puzzlepiece.extension")
                    }
                } header: {
                    Text("Activation")
                }

                Section {
                    // M5 : remplacé par le vrai contenu (limites de couverture, réglages).
                    Text("Impostor n'alerte que lorsqu'une page réclame une identité qui ne correspond pas à son domaine. Il ne voit pas tout — l'écran des limites arrive en M5.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Ce que fait Impostor")
                }
            }
            .navigationTitle("Impostor")
        }
    }
}

#Preview {
    ContentView()
}
