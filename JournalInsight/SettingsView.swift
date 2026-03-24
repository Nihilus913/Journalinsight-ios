//
//  SettingsView.swift
//  JournalInsight
//
//  Created by Tobias Tensfeldt on 25.04.2025.
//

import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

struct SettingsView: View {
    @AppStorage(StorageKeys.userName) private var userName: String = ""
    @State private var nameField: String = ""
    @State private var showSaved = false
    @State private var wallpaperImageData: Data? = WallpaperStorage.load()
    @AppStorage(StorageKeys.selectedAppearance) private var selectedAppearance: AppAppearance = .system
    @State private var showImagePicker = false
    @State private var selectedItem: PhotosPickerItem? = nil

    var body: some View {
        Form {
            Section("Name") {
                TextField("Your name", text: $nameField)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    userName = nameField.trimmingCharacters(in: .whitespacesAndNewlines)
                    showSaved = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        showSaved = false
                    }
                }
                .disabled(nameField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if showSaved {
                    Text("Saved!")
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
            }

            Section("Wallpaper") {
                Button {
                    showImagePicker.toggle()
                } label: {
                    Label("Select New Wallpaper", systemImage: "photo")
                }

                #if canImport(UIKit)
                if let data = wallpaperImageData, let uiImage = UIImage(data: data) {
                    NavigationLink(destination: FullscreenWallpaperView(imageData: data)) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 100)
                            .clipped()
                            .cornerRadius(8)
                            .padding(.top, 8)
                    }
                }
                #endif

                if wallpaperImageData != nil {
                    Button("Remove Wallpaper", role: .destructive) {
                        wallpaperImageData = nil
                        WallpaperStorage.delete()
                    }
                }
            }

            Section("Theme") {
                Text("Coming Soon: Theme Selection")
                    .foregroundColor(.secondary)
            }

            Section("Text Size") {
                Text("Coming Soon: Font Settings")
                    .foregroundColor(.secondary)
            }

            Section("Appearance") {
                Picker("Appearance", selection: $selectedAppearance) {
                    Text("System").tag(AppAppearance.system)
                    Text("Light").tag(AppAppearance.light)
                    Text("Dark").tag(AppAppearance.dark)
                }
                .pickerStyle(SegmentedPickerStyle())
            }
        }
        .navigationTitle("Personalize")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            nameField = userName
        }
        .onChange(of: selectedItem) { _, newItem in
            if let newItem {
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        wallpaperImageData = data
                        WallpaperStorage.save(data)
                    }
                }
            }
        }
        .photosPicker(isPresented: $showImagePicker, selection: $selectedItem)
    }
}

/// Stores wallpaper image on the file system instead of UserDefaults.
enum WallpaperStorage {
    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("wallpaper.dat")
    }

    static func save(_ data: Data) {
        try? data.write(to: fileURL)
    }

    static func load() -> Data? {
        try? Data(contentsOf: fileURL)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

struct FullscreenWallpaperView: View {
    let imageData: Data

    var body: some View {
        #if canImport(UIKit)
        if let uiImage = UIImage(data: imageData) {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .padding()
            }
            .navigationTitle("Wallpaper")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            Text("Unable to load image")
                .foregroundColor(.secondary)
                .navigationTitle("Wallpaper")
                .navigationBarTitleDisplayMode(.inline)
        }
        #else
        Text("Image preview not available on this platform.")
            .foregroundColor(.secondary)
            .navigationTitle("Wallpaper")
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
