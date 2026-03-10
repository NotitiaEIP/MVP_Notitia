//
//  NotitiaWidget.swift
//  NotitiaWidget
//
//  Created by Lucas Lejeune on 10/03/2026.
//

import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), emoji: "😀")
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(), emoji: "😀")
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        var entries: [SimpleEntry] = []

        // Generate a timeline consisting of five entries an hour apart, starting from the current date.
        let currentDate = Date()
        for hourOffset in 0 ..< 5 {
            let entryDate = Calendar.current.date(byAdding: .hour, value: hourOffset, to: currentDate)!
            let entry = SimpleEntry(date: entryDate, emoji: "😀")
            entries.append(entry)
        }

        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }

//    func relevances() async -> WidgetRelevances<Void> {
//        // Generate a list containing the contexts this widget is relevant in.
//    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let emoji: String
}

struct NotitiaWidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        VStack {
            Text("Time:")
            Text(entry.date, style: .time)

            Text("Emoji:")
            Text(entry.emoji)
        }
    }
}

<<<<<<< Updated upstream
=======
// ═══════════════════════════════════════════════════════════════════════════
// MARK: - Stop Button (recording)
// ═══════════════════════════════════════════════════════════════════════════

struct StopButton: View {
    let size: CGFloat
    let iconSize: CGFloat

    var body: some View {
        ZStack {
            // Glow outer
            Circle()
                .fill(NC.redRec.opacity(0.15))
                .frame(width: size, height: size)

            // Glow mid
            Circle()
                .fill(NC.redRec.opacity(0.22))
                .frame(width: size * 0.82, height: size * 0.82)

            // Neon ring
            Circle()
                .stroke(NC.redRec.opacity(0.65), lineWidth: 2.5)
                .frame(width: size * 0.72, height: size * 0.72)

            // Red button
            Circle()
                .fill(
                    LinearGradient(
                        colors: [NC.redRec, NC.redRec.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: iconSize, height: iconSize)
                .shadow(color: NC.redRec.opacity(0.5), radius: 10)

            // Stop square
            RoundedRectangle(cornerRadius: 3)
                .fill(.white)
                .frame(width: iconSize * 0.38, height: iconSize * 0.38)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - SMALL Widget View (systemSmall — 2×2)
//         Identique au widget Android 2×2 : micro/stop + label
// ═══════════════════════════════════════════════════════════════════════════

struct SmallWidgetView: View {
    let entry: NotitiaEntry

    var body: some View {
        Link(destination: URL(string: "notitia://record")!) {
            ZStack {
                WidgetBG(isRecording: entry.isRecording)

                if entry.isRecording {
                    smallRecording
                } else {
                    smallIdle
                }
            }
        }
    }

    // — IDLE —
    var smallIdle: some View {
        VStack(spacing: 4) {
            MicButton(size: 90, iconSize: 56)

            Text("NOTITIA")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(NC.neonPink)
                .tracking(2)
                .shadow(color: NC.neonPink.opacity(0.6), radius: 6)
        }
    }

    // — RECORDING —
    var smallRecording: some View {
        VStack(spacing: 2) {
            StopButton(size: 82, iconSize: 52)

            // ● REC
            HStack(spacing: 4) {
                Circle()
                    .fill(NC.redRec)
                    .frame(width: 7, height: 7)
                Text("REC")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(NC.redRec)
                    .shadow(color: NC.redRec.opacity(0.7), radius: 6)
            }

            // Timer
            Text(entry.timer)
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundColor(NC.neonCyan)
                .shadow(color: NC.neonCyan.opacity(0.6), radius: 8)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - MEDIUM Widget View (systemMedium — ~3×3 equivalent)
//         Identique au widget Android 3×3 : micro/stop + timer + transcription
// ═══════════════════════════════════════════════════════════════════════════

struct MediumWidgetView: View {
    let entry: NotitiaEntry

    var body: some View {
        Link(destination: URL(string: "notitia://record")!) {
            ZStack {
                WidgetBG(isRecording: entry.isRecording)

                if entry.isRecording {
                    mediumRecording
                } else {
                    mediumIdle
                }
            }
            .padding(8)
        }
    }

    // — IDLE —
    var mediumIdle: some View {
        HStack(spacing: 14) {
            // Gauche : micro
            VStack(spacing: 4) {
                MicButton(size: 100, iconSize: 64)

                Text("Tap to record")
                    .font(.system(size: 10, weight: .light))
                    .foregroundColor(NC.neonCyan.opacity(0.55))
            }

            // Droite : titre + dernière transcription
            VStack(alignment: .leading, spacing: 6) {
                Text("N O T I T I A")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(NC.neonPink)
                    .shadow(color: NC.neonPink.opacity(0.5), radius: 8)

                // Séparateur néon
                Rectangle()
                    .fill(NC.neonPink.opacity(0.3))
                    .frame(height: 1)

                // Dernière transcription
                Text(
                    entry.lastTranscript.isEmpty
                        ? "Dernière transcription ici…"
                        : "\"\(truncate(entry.lastTranscript, max: 80))\""
                )
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(entry.lastTranscript.isEmpty ? 0.25 : 0.55))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // — RECORDING —
    var mediumRecording: some View {
        HStack(spacing: 14) {
            // Gauche : stop + timer
            VStack(spacing: 4) {
                StopButton(size: 90, iconSize: 56)

                // ● REC — timer
                HStack(spacing: 5) {
                    Circle()
                        .fill(NC.redRec)
                        .frame(width: 7, height: 7)
                    Text("REC")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(NC.redRec)
                }

                Text(entry.timer)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(NC.neonCyan)
                    .shadow(color: NC.neonCyan.opacity(0.6), radius: 10)
            }

            // Droite : transcription live
            VStack(alignment: .leading, spacing: 6) {
                Text("TRANSCRIPTION")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(NC.neonCyan.opacity(0.7))
                    .tracking(1.5)

                Rectangle()
                    .fill(NC.redRec.opacity(0.3))
                    .frame(height: 1)

                Text(
                    entry.liveTranscript.isEmpty
                        ? "En attente de transcription…"
                        : truncate(entry.liveTranscript, max: 100)
                )
                .font(.system(size: 10))
                .foregroundColor(NC.neonCyan.opacity(entry.liveTranscript.isEmpty ? 0.35 : 0.8))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func truncate(_ text: String, max: Int) -> String {
        text.count > max ? "…" + String(text.suffix(max)) : text
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - Lock Screen Widget (accessoryCircular)
// ═══════════════════════════════════════════════════════════════════════════

@available(iOSApplicationExtension 16.0, *)
struct LockScreenWidgetView: View {
    let entry: NotitiaEntry

    var body: some View {
        Link(destination: URL(string: "notitia://record")!) {
            ZStack {
                AccessoryWidgetBackground()
                if entry.isRecording {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - Router View
// ═══════════════════════════════════════════════════════════════════════════

struct NotitiaWidgetEntryView: View {
    var entry: NotitiaProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .accessoryCircular:
            if #available(iOSApplicationExtension 16.0, *) {
                LockScreenWidgetView(entry: entry)
            }
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - Widget Declaration
// ═══════════════════════════════════════════════════════════════════════════

>>>>>>> Stashed changes
struct NotitiaWidget: Widget {
    let kind: String = "NotitiaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                NotitiaWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                NotitiaWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("My Widget")
        .description("This is an example widget.")
    }
}

#Preview(as: .systemSmall) {
    NotitiaWidget()
} timeline: {
    SimpleEntry(date: .now, emoji: "😀")
    SimpleEntry(date: .now, emoji: "🤩")
}
