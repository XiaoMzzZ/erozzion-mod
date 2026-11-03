//
//  SettingsView.swift
//  Erosion
//
//  Created by lunginspector on 8/20/26.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("autoRespring") var autoRespring = false
    @AppStorage("displayNotReadablePaths") private var displayNotReadablePaths = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Auto-Respring", isOn: $autoRespring)
                    if airliftUIAccessRequired() {
                        Toggle("Display not readable paths", isOn: $displayNotReadablePaths)
                    }
                } header: {
                    HeaderLabel("App Settings", symbol: "gearshape")
                } footer: {
                    Text("Automatically resprings your device after applying a tweak.")
                }
                
                Section {
                    Link(destination: URL(string: "https://t.me/usrlibexec")!) {
                        AppInfoCell(build: "Release", appName: "Erosion mod", appVersion: "2.2")
                    }
                    .tint(.white)
                } header: {
                    HeaderLabel("About", symbol: "info.circle")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Made with love by the [jailbreak.party](https://jailbreak.party) team.\nNeed support or want to know about new releases? Join the [jailbreak.party Discord server!](https://jailbreak.party/discord)")
                    }
                }
                
                Section {
                    LinkCreditCell(image: Image("lunginspector"), name: "lunginspector", description: "Primary developer and maintainer.", url: "https://github.com/lunginspector")
                    LinkCreditCell(image: Image("forcequit"), name: "forcequit", description: "Developed and published bad_query sandbox escape.", url: "https://github.com/forcequitOS")
                    LinkCreditCell(image: Image("skadz108"), name: "Skadz", description: "Minor UI adjustments, respring implementation, and various backend functions.", url: "https://github.com/skadz108")
                    LinkCreditCell(image: Image("rooootdev"), name: "rooootdev", description: "Various backend components.", url: "https://github.com/rooootdev")
                    LinkCreditCell(image: Image("neonmodder123"), name: "neonmodder123", description: "Developed WebView respring method.", url: "https://github.com/neonmodder123")
                } header: {
                    HeaderLabel("Credits", symbol: "star")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        ToolbarLabel("Close", symbol: "xmark")
                    }
                }
            }
        }
    }
}
