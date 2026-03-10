//
//  NotitiaWidget.swift
//  NotitiaWidget
//
//  Created by Lucas Lejeune on 10/03/2026.
//

import WidgetKit
import SwiftUI

// MARK: - App Group ID
let appGroupId = "group.com.example.notitia"

// MARK: - Timeline Provider

struct NotitiaProvider: TimelineProvider {
    func placeholder(in context: Context) -> NotitiaEntry {
        NotitiaEntry(
            date: Date(),
            isRecording: false,
            timer: "00:00",
            liveTranscript: "",
            lastTranscript: ""
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (NotitiaEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NotitiaEntry>) -> Void) {
        let entry = readEntry()
        let interval: TimeInterval = entry.isRecording ? 1 : 86400
        let nextUpdate = Date().addingTimeInterval(interval)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func readEntry() -> NotitiaEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        return NotitiaEntry(
            date: Date(),
            isRecording: defaults?.bool(forKey: "is_recording") ?? false,
            timer: defaults?.string(forKey: "timer") ?? "00:00",
            liveTranscript: defaults?.string(forKey: "live_transcript") ?? "",
            lastTranscript: defaults?.string(forKey: "last_transcription") ?? ""
        )
    }
}

// MARK: - Entry

struct NotitiaEntry: TimelineEntry {
    let date: Date
    let isRecording: Bool
    let timer: String
    let liveTranscript: String
    let lastTranscript: String
}

// MARK: - Couleurs Notitia (identiques Android)
struct NC {
    static let deepBlue    = Color(red: 0.0,  green: 0.0,   blue: 0.247)   // #00003F
    static let darkBlue    = Color(red: 0.0,  green: 0.031, blue: 0.188)   // #000830
    static let neonPink    = Color(red: 1.0,  green: 0.004, blue: 0.471)   // #FF0178
    static let redRec      = Color(red: 1.0,  green: 0.2,   blue: 0.4)     // #FF3366
    static let neonCyan    = Color(red: 0.0,  green: 0.898, blue: 1.0)     // #00E5FF
    static let dimCyan     = Color(red: 0.0,  green: 0.898, blue: 1.0).opacity(0.5)
    static let dimPink     = Color(red: 1.0,  green: 0.004, blue: 0.471).opacity(0.5)
}

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - Widget Backgrounds (shared)
// ═══════════════════════════════════════════════════════════════════════════

struct WidgetBG: View {
    let isRecording: Bool
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(
                    LinearGradient(
                        colors: [NC.darkBlue, NC.deepBlue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            // Neon border
            RoundedRectangle(cornerRadius: 22)
                .stroke(
                    isRecording
                        ? NC.redRec.opacity(0.6)
                        : NC.neonPink.opacity(0.5),
                    lineWidth: 1.5
                )
            // Outer glow
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    isRecording
                        ? NC.redRec.opacity(0.15)
                        : NC.neonPink.opacity(0.12),
                    lineWidth: 4
                )
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - Micro Button (idle)
// ═══════════════════════════════════════════════════════════════════════════

struct MicButton: View {
    let size: CGFloat      // outer glow size
    let iconSize: CGFloat  // mic circle size

    var body: some View {
        ZStack {
            // Glow outer
            Circle()
                .fill(NC.neonPink.opacity(0.12))
                .frame(width: size, height: size)

            // Glow mid
            Circle()
                .fill(NC.neonPink.opacity(0.18))
                .frame(width: size * 0.82, height: size * 0.82)

            // Neon ring
            Circle()
                .stroke(NC.neonPink.opacity(0.55), lineWidth: 2)
                .frame(width: size * 0.72, height: size * 0.72)

            // Pink button
            Circle()
                .fill(
                    LinearGradient(
                        colors: [NC.neonPink, NC.neonPink.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: iconSize, height: iconSize)
                .shadow(color: NC.neonPink.opacity(0.5), radius: 10)

            // Mic icon
            Image(systemName: "mic.fill")
                .font(.system(size: iconSize * 0.42, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

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
            LockScreenWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - Widget Declaration
// ═══════════════════════════════════════════════════════════════════════════

@main
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
        StaticConfiguration(kind: kind, provider: NotitiaProvider()) { entry in
            NotitiaWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Notitia Capture")
        .description("Capture vocale rapide. Petit = micro compact, Moyen = micro + transcription.")
        .supportedFamilies(supportedFamilies)
    }

    var supportedFamilies: [WidgetFamily] {
        var families: [WidgetFamily] = [.systemSmall, .systemMedium]
        if #available(iOSApplicationExtension 16.0, *) {
            families.append(.accessoryCircular)
        }
        return families
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - Previews
// ═══════════════════════════════════════════════════════════════════════════

struct NotitiaWidget_Previews: PreviewProvider {
    static var previews: some View {
        // Small — Idle
        NotitiaWidgetEntryView(
            entry: NotitiaEntry(date: Date(), isRecording: false, timer: "00:00",
                                liveTranscript: "", lastTranscript: "")
        )
        .previewContext(WidgetPreviewContext(family: .systemSmall))
        .previewDisplayName("Small — Idle")

        // Small — Recording
        NotitiaWidgetEntryView(
            entry: NotitiaEntry(date: Date(), isRecording: true, timer: "02:34",
                                liveTranscript: "Bonjour c'est un test", lastTranscript: "")
        )
        .previewContext(WidgetPreviewContext(family: .systemSmall))
        .previewDisplayName("Small — Recording")

        // Medium — Idle
        NotitiaWidgetEntryView(
            entry: NotitiaEntry(date: Date(), isRecording: false, timer: "00:00",
                                liveTranscript: "",
                                lastTranscript: "Réunion du lundi : discuter du sprint planning et des objectifs Q2.")
        )
        .previewContext(WidgetPreviewContext(family: .systemMedium))
        .previewDisplayName("Medium — Idle")

        // Medium — Recording
        NotitiaWidgetEntryView(
            entry: NotitiaEntry(date: Date(), isRecording: true, timer: "01:15",
                                liveTranscript: "Alors pour le projet Notitia, on va implémenter les widgets natifs…",
                                lastTranscript: "")
        )
        .previewContext(WidgetPreviewContext(family: .systemMedium))
        .previewDisplayName("Medium — Recording")

        // Lock Screen
        if #available(iOSApplicationExtension 16.0, *) {
            NotitiaWidgetEntryView(
                entry: NotitiaEntry(date: Date(), isRecording: false, timer: "00:00",
                                    liveTranscript: "", lastTranscript: "")
            )
            .previewContext(WidgetPreviewContext(family: .accessoryCircular))
            .previewDisplayName("Lock Screen")
        }
    }
}
