// =============================================================================
// NOTITIA — Widget iOS (WidgetKit + SwiftUI)
//
// Widget écran d'accueil & écran de verrouillage. Double état :
//   - IDLE     : Bouton micro néon rose → tap lance l'enregistrement
//   - RECORDING: Timer cyan + bouton stop rouge → tap arrête et sauvegarde
//
// Communique avec Flutter via l'URI notitia://record (toggle).
// =============================================================================

import WidgetKit
import SwiftUI

// MARK: - App Group ID (doit correspondre au Flutter service)
let appGroupId = "group.com.example.notitia"

// MARK: - Timeline Provider

struct NotitiaProvider: TimelineProvider {
    func placeholder(in context: Context) -> NotitiaEntry {
        NotitiaEntry(date: Date(), isRecording: false, timer: "00:00")
    }

    func getSnapshot(in context: Context, completion: @escaping (NotitiaEntry) -> Void) {
        let entry = readEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NotitiaEntry>) -> Void) {
        let entry = readEntry()
        // Rafraîchir fréquemment pendant l'enregistrement, sinon toutes les 24h
        let interval: TimeInterval = entry.isRecording ? 1 : 86400
        let nextUpdate = Date().addingTimeInterval(interval)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    /// Lit l'état depuis les UserDefaults partagés (home_widget)
    private func readEntry() -> NotitiaEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        let isRecording = defaults?.bool(forKey: "is_recording") ?? false
        let timer = defaults?.string(forKey: "timer") ?? "00:00"
        return NotitiaEntry(date: Date(), isRecording: isRecording, timer: timer)
    }
}

// MARK: - Entry

struct NotitiaEntry: TimelineEntry {
    let date: Date
    let isRecording: Bool
    let timer: String
}

// MARK: - Couleurs Notitia
struct NotitiaColors {
    static let deepBlue = Color(red: 0.0, green: 0.0, blue: 0.247)      // #00003F
    static let darkBlue = Color(red: 0.0, green: 0.031, blue: 0.188)    // #000830
    static let neonPink = Color(red: 1.0, green: 0.004, blue: 0.471)    // #FF0178
    static let redRecording = Color(red: 1.0, green: 0.2, blue: 0.4)    // #FF3366
    static let neonCyan = Color(red: 0.0, green: 0.898, blue: 1.0)      // #00E5FF
}

// MARK: - Widget View

struct NotitiaWidgetEntryView: View {
    var entry: NotitiaProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            lockScreenView
        default:
            homeScreenView
        }
    }

    // MARK: Widget écran d'accueil
    var homeScreenView: some View {
        Link(destination: URL(string: "notitia://record")!) {
            ZStack {
                // Fond
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [NotitiaColors.darkBlue, NotitiaColors.deepBlue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(
                                entry.isRecording
                                    ? NotitiaColors.redRecording.opacity(0.5)
                                    : NotitiaColors.neonPink.opacity(0.3),
                                lineWidth: 1
                            )
                    )

                if entry.isRecording {
                    recordingContent
                } else {
                    idleContent
                }
            }
        }
    }

    // MARK: Contenu IDLE
    var idleContent: some View {
        VStack(spacing: 6) {
            // Halo néon rose
            ZStack {
                Circle()
                    .fill(NotitiaColors.neonPink.opacity(0.15))
                    .frame(width: 60, height: 60)

                Circle()
                    .fill(NotitiaColors.neonPink.opacity(0.08))
                    .frame(width: 52, height: 52)

                // Bouton micro
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [NotitiaColors.neonPink, NotitiaColors.neonPink.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: NotitiaColors.neonPink.opacity(0.4), radius: 8)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
            }

            // Label NOTITIA
            Text("NOTITIA")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(NotitiaColors.neonPink)
                .tracking(2)

            Text("Tap to record")
                .font(.system(size: 7, weight: .light))
                .foregroundColor(.white.opacity(0.35))
        }
    }

    // MARK: Contenu RECORDING
    var recordingContent: some View {
        VStack(spacing: 4) {
            // Halo rouge pulsant
            ZStack {
                Circle()
                    .fill(NotitiaColors.redRecording.opacity(0.2))
                    .frame(width: 60, height: 60)

                Circle()
                    .stroke(NotitiaColors.redRecording.opacity(0.5), lineWidth: 2)
                    .frame(width: 52, height: 52)

                // Bouton STOP
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [NotitiaColors.redRecording, NotitiaColors.redRecording.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: NotitiaColors.redRecording.opacity(0.4), radius: 8)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white)
                        .frame(width: 16, height: 16)
                }
            }

            // Label REC
            HStack(spacing: 4) {
                Circle()
                    .fill(NotitiaColors.redRecording)
                    .frame(width: 6, height: 6)
                Text("REC")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(NotitiaColors.redRecording)
            }

            // Timer
            Text(entry.timer)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(NotitiaColors.neonCyan)
        }
    }

    // MARK: Widget écran de verrouillage (iOS 16+)
    var lockScreenView: some View {
        Link(destination: URL(string: "notitia://record")!) {
            ZStack {
                AccessoryWidgetBackground()
                if entry.isRecording {
                    // Mode recording : carré stop
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white)
                        .frame(width: 14, height: 14)
                } else {
                    // Mode idle : micro
                    Image(systemName: "mic.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
    }
}

// MARK: - Widget Declaration

@main
struct NotitiaWidget: Widget {
    let kind: String = "NotitiaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NotitiaProvider()) { entry in
            NotitiaWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Notitia Capture")
        .description("Lancez la capture vocale d'un tap. Enregistrement direct sans ouvrir l'app.")
        .supportedFamilies(supportedFamilies)
    }

    var supportedFamilies: [WidgetFamily] {
        var families: [WidgetFamily] = [.systemSmall]
        if #available(iOSApplicationExtension 16.0, *) {
            families.append(.accessoryCircular)
        }
        return families
    }
}

// MARK: - Preview

struct NotitiaWidget_Previews: PreviewProvider {
    static var previews: some View {
        // Preview idle
        NotitiaWidgetEntryView(entry: NotitiaEntry(date: Date(), isRecording: false, timer: "00:00"))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            .previewDisplayName("Idle")

        // Preview recording
        NotitiaWidgetEntryView(entry: NotitiaEntry(date: Date(), isRecording: true, timer: "02:34"))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            .previewDisplayName("Recording")

        if #available(iOSApplicationExtension 16.0, *) {
            NotitiaWidgetEntryView(entry: NotitiaEntry(date: Date(), isRecording: false, timer: "00:00"))
                .previewContext(WidgetPreviewContext(family: .accessoryCircular))
                .previewDisplayName("Lock Screen - Idle")
        }
    }
}
