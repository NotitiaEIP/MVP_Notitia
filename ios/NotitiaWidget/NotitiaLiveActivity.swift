// NotitiaLiveActivity.swift
// Live Activity + Dynamic Island pour l'enregistrement
//
// Le plugin Flutter `live_activities` utilise ses propres ActivityAttributes
// (LiveActivitiesAppAttributes) et stocke les données dans l'App Group
// UserDefaults avec le format : "{uuid}_{key}"
//
// Le widget Swift lit ces données depuis UserDefaults pour les afficher.

import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

private let kAppGroupId = "group.com.example.notitia"

// ─────────────────────────────────────────────────────────────────────────────
// Helper pour lire les données du plugin live_activities
// ─────────────────────────────────────────────────────────────────────────────
@available(iOSApplicationExtension 16.1, *)
private struct LiveActivityData {
    let noteTitle: String
    let duration: String
    let isRecording: Bool

    /// Lit les données depuis l'App Group UserDefaults.
    /// Le plugin stocke les valeurs sous la clé "{appGroupId}_{dataKey}".
    /// Mais en pratique, le prefix est l'UUID de l'activité.
    /// On cherche toutes les clés matchant *_noteTitle, *_duration, *_isRecording.
    static func read() -> LiveActivityData {
        let defaults = UserDefaults(suiteName: kAppGroupId)
        let dict = defaults?.dictionaryRepresentation() ?? [:]

        var noteTitle = "Enregistrement"
        var duration = "00:00"
        var isRecording = true

        for (key, value) in dict {
            if key.hasSuffix("_noteTitle"), let v = value as? String {
                noteTitle = v
            } else if key.hasSuffix("_duration"), let v = value as? String {
                duration = v
            } else if key.hasSuffix("_isRecording") {
                if let v = value as? Bool {
                    isRecording = v
                } else if let v = value as? Int {
                    isRecording = v != 0
                } else if let v = value as? String {
                    isRecording = v == "true" || v == "1"
                }
            }
        }

        return LiveActivityData(noteTitle: noteTitle, duration: duration, isRecording: isRecording)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Attributes du plugin live_activities (doit correspondre exactement)
// ─────────────────────────────────────────────────────────────────────────────
@available(iOSApplicationExtension 16.1, *)
struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
    public typealias LiveDeliveryData = ContentState

    public struct ContentState: Codable, Hashable {
        var appGroupId: String
    }

    var id = UUID()
}

// ─────────────────────────────────────────────────────────────────────────────
// Intent Stop (iOS 17+) — bouton sur Dynamic Island / Lock Screen
// ─────────────────────────────────────────────────────────────────────────────
@available(iOSApplicationExtension 17.0, *)
struct StopTranscriptionIntent: AppIntent {
    static var title: LocalizedStringResource = "Arrêter la transcription"

    func perform() async throws -> some IntentResult {
        // 1) UserDefaults
        let defaults = UserDefaults(suiteName: kAppGroupId)
        defaults?.set(true, forKey: "live_activity_stop_requested")
        defaults?.synchronize()
        // 2) Fichier flag (cross-process)
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: kAppGroupId
        ) {
            let flagURL = containerURL.appendingPathComponent("live_activity_stop_requested")
            try? "1".write(to: flagURL, atomically: true, encoding: .utf8)
        }
        return .result()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget Live Activity (Lock Screen + Dynamic Island)
// ─────────────────────────────────────────────────────────────────────────────
@available(iOSApplicationExtension 16.1, *)
struct NotitiaWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
            // Lire les données depuis l'App Group
            let data = LiveActivityData.read()

            // Vue écran de verrouillage / bannière
            HStack(spacing: 12) {
                // Indicateur micro animé
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "mic.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 20, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(data.noteTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(data.isRecording ? Color.red : Color.gray)
                            .frame(width: 6, height: 6)
                        Text(data.isRecording ? "REC" : "PAUSE")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(data.isRecording ? .red : .gray)
                        Text(data.duration)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                    }
                }

                Spacer()

                if #available(iOSApplicationExtension 17.0, *) {
                    Button(intent: StopTranscriptionIntent()) {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.2))
                                .frame(width: 40, height: 40)
                            Image(systemName: "stop.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(Color.black)

        } dynamicIsland: { context in
            let data = LiveActivityData.read()

            return DynamicIsland {
                // Vue étendue (appui long)
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "mic.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 18))
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(data.noteTitle)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if #available(iOSApplicationExtension 17.0, *) {
                        Button(intent: StopTranscriptionIntent()) {
                            Text("Stop")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .tint(.red)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(data.duration)
                            .font(.system(size: 22, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                }
            } compactLeading: {
                Image(systemName: "mic.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 13))
            } compactTrailing: {
                Text(data.duration)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.red)
            } minimal: {
                Image(systemName: "mic.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 12))
            }
        }
    }
}
