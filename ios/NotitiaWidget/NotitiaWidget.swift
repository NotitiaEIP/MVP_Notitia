// =============================================================================
// NOTITIA — Widgets iOS (WidgetKit + SwiftUI)
//
// Deux tailles identiques à Android :
//   ● PETIT  (systemSmall)  = Android 2×2 → Micro/Stop centré + label NOTITIA
//   ● GRAND  (systemMedium) = Android 3×3 → Titre, micro/stop, timer, transcript
//   ● Lock Screen (accessoryCircular) → Micro/Stop minimaliste
//
// Design cyberpunk néon identique :
//   Couleurs : deepBlue #000830, neonPink #FF0178, redRec #FF3366, cyan #00E5FF
//   Background : gradient dark blue + bordure néon + glow externe
//   Boutons : 4 couches glow (outer → mid → ring → circle) + shadow
//
// Communication : URI notitia://record (toggle via Flutter).
// =============================================================================

import WidgetKit
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Configuration
// ─────────────────────────────────────────────────────────────────────────────

private let kAppGroupId = "group.com.example.notitia"

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Couleurs (identiques Android)
// ─────────────────────────────────────────────────────────────────────────────

private struct C {
    static let deepBlue = Color(red: 0, green: 0, blue: 0.247)        // #00003F
    static let darkBlue = Color(red: 0, green: 0.031, blue: 0.188)    // #000830
    static let pink     = Color(red: 1, green: 0.004, blue: 0.471)    // #FF0178
    static let red      = Color(red: 1, green: 0.2, blue: 0.4)        // #FF3366
    static let cyan     = Color(red: 0, green: 0.898, blue: 1)        // #00E5FF
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Timeline Entry
// ─────────────────────────────────────────────────────────────────────────────

struct NotitiaEntry: TimelineEntry {
    let date: Date
    let isRecording: Bool
    let timer: String
    let liveTranscript: String
    let lastTranscript: String
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Timeline Provider
// ─────────────────────────────────────────────────────────────────────────────

struct NotitiaProvider: TimelineProvider {

    func placeholder(in context: Context) -> NotitiaEntry {
        NotitiaEntry(date: .now, isRecording: false, timer: "00:00",
                     liveTranscript: "", lastTranscript: "")
    }

    func getSnapshot(in context: Context, completion: @escaping (NotitiaEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NotitiaEntry>) -> Void) {
        let entry = readEntry()
        let next = Date().addingTimeInterval(entry.isRecording ? 1 : 86400)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func readEntry() -> NotitiaEntry {
        let d = UserDefaults(suiteName: kAppGroupId)
        return NotitiaEntry(
            date: .now,
            isRecording: d?.bool(forKey: "is_recording") ?? false,
            timer: d?.string(forKey: "timer") ?? "00:00",
            liveTranscript: d?.string(forKey: "live_transcript") ?? "",
            lastTranscript: d?.string(forKey: "last_transcription") ?? ""
        )
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Composants partagés
// ═══════════════════════════════════════════════════════════════════════════════

// ── Background (identique Android widget_background.xml) ─────────────────────

private struct WidgetBG: View {
    let recording: Bool

    var body: some View {
        let accent = recording ? C.red : C.pink
        ZStack {
            // Glow externe diffus (couche 3)
            RoundedRectangle(cornerRadius: 24)
                .fill(accent.opacity(recording ? 0.15 : 0.10))

            // Glow moyenne (couche 2)
            RoundedRectangle(cornerRadius: 22)
                .fill(accent.opacity(recording ? 0.20 : 0.14))
                .padding(2)

            // Fond principal opaque + bordure néon
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [NC.darkBlue, NC.deepBlue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(accent.opacity(recording ? 0.60 : 0.50), lineWidth: 1.5)
                )
                .padding(3)
        }
    }

    // Couleurs (raccourcis)
    private struct NC {
        static let darkBlue = C.darkBlue.opacity(0.94)
        static let deepBlue = C.deepBlue.opacity(0.94)
    }
}

// ── Bouton Micro (idle) ──────────────────────────────────────────────────────
// 4 couches : glow outer → glow mid → neon ring → pink circle
// Identique Android : ic_glow_ring.xml + ic_mic_widget.xml

private struct MicBtn: View {
    let glowSize: CGFloat
    let btnSize: CGFloat

    var body: some View {
        ZStack {
            // Glow outer
            Circle().fill(C.pink.opacity(0.12))
                .frame(width: glowSize, height: glowSize)
            // Glow mid
            Circle().fill(C.pink.opacity(0.20))
                .frame(width: glowSize * 0.82, height: glowSize * 0.82)
            // Glow inner
            Circle().fill(C.pink.opacity(0.14))
                .frame(width: glowSize * 0.72, height: glowSize * 0.72)
            // Neon ring
            Circle().stroke(C.pink.opacity(0.60), lineWidth: 2)
                .frame(width: glowSize * 0.68, height: glowSize * 0.68)

            // Bouton rose (gradient + shadow)
            Circle()
                .fill(LinearGradient(
                    colors: [C.pink, C.pink.opacity(0.7)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: btnSize, height: btnSize)
                .shadow(color: C.pink.opacity(0.50), radius: 10)

            // Sur-brillance (identique Android ic_mic_widget.xml demi-cercle)
            Circle()
                .fill(Color.white.opacity(0.13))
                .frame(width: btnSize, height: btnSize)
                .mask(
                    VStack { Rectangle().frame(height: btnSize / 2); Spacer() }
                        .frame(width: btnSize, height: btnSize)
                )

            // Icône micro
            Image(systemName: "mic.fill")
                .font(.system(size: btnSize * 0.40, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

// ── Bouton Stop (recording) ──────────────────────────────────────────────────
// Identique Android : ic_glow_ring_recording.xml + ic_stop_widget.xml

private struct StopBtn: View {
    let glowSize: CGFloat
    let btnSize: CGFloat

    var body: some View {
        ZStack {
            // Glow outer
            Circle().fill(C.red.opacity(0.15))
                .frame(width: glowSize, height: glowSize)
            // Glow mid
            Circle().fill(C.red.opacity(0.25))
                .frame(width: glowSize * 0.82, height: glowSize * 0.82)
            // Glow inner
            Circle().fill(C.red.opacity(0.18))
                .frame(width: glowSize * 0.72, height: glowSize * 0.72)
            // Neon ring
            Circle().stroke(C.red.opacity(0.70), lineWidth: 2.5)
                .frame(width: glowSize * 0.68, height: glowSize * 0.68)

            // Bouton rouge (gradient + shadow)
            Circle()
                .fill(LinearGradient(
                    colors: [C.red, C.red.opacity(0.7)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: btnSize, height: btnSize)
                .shadow(color: C.red.opacity(0.50), radius: 10)

            // Sur-brillance
            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: btnSize, height: btnSize)
                .mask(
                    VStack { Rectangle().frame(height: btnSize / 2); Spacer() }
                        .frame(width: btnSize, height: btnSize)
                )

            // Carré stop arrondi
            RoundedRectangle(cornerRadius: 3)
                .fill(.white)
                .frame(width: btnSize * 0.36, height: btnSize * 0.36)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - PETIT WIDGET (systemSmall) — identique Android 2×2
// ═══════════════════════════════════════════════════════════════════════════════
//
//  Android 2×2 IDLE :     glow(90dp) + mic(58dp) centré, "NOTITIA" 11sp bold pink
//  Android 2×2 RECORDING: glow(82dp) + stop(52dp), "● REC" 11sp red, timer 16sp cyan

private struct SmallView: View {
    let e: NotitiaEntry

    var body: some View {
        Link(destination: URL(string: "notitia://record")!) {
            ZStack {
                WidgetBG(recording: e.isRecording)
                if e.isRecording { recState } else { idleState }
            }
        }
    }

    // ── IDLE ──
    private var idleState: some View {
        VStack(spacing: 4) {
            MicBtn(glowSize: 90, btnSize: 58)

            Text("NOTITIA")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(C.pink)
                .tracking(2)
                .shadow(color: C.pink.opacity(0.65), radius: 8)
        }
    }

    // ── RECORDING ──
    private var recState: some View {
        VStack(spacing: 2) {
            StopBtn(glowSize: 82, btnSize: 52)

            HStack(spacing: 4) {
                Circle().fill(C.red).frame(width: 7, height: 7)
                Text("REC")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(C.red)
                    .shadow(color: C.red.opacity(0.70), radius: 8)
            }

            Text(e.timer)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(C.cyan)
                .shadow(color: C.cyan.opacity(0.60), radius: 10)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - GRAND WIDGET (systemMedium) — identique Android 3×3
// ═══════════════════════════════════════════════════════════════════════════════
//
//  Android 3×3 IDLE :     "N O T I T I A" 16sp, separator, glow(110)+mic(72),
//                         "Tap to record" cyan, zone transcript
//  Android 3×3 RECORDING: "● REC — 00:00" en horizontal, separator,
//                         glow(100)+stop(64), zone transcript live cyan

private struct LargeView: View {
    let e: NotitiaEntry

    var body: some View {
        Link(destination: URL(string: "notitia://record")!) {
            ZStack {
                WidgetBG(recording: e.isRecording)
                Group {
                    if e.isRecording { recState } else { idleState }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    // ── IDLE ──
    private var idleState: some View {
        VStack(spacing: 0) {
            // Titre "N O T I T I A" (16sp Android)
            Text("N O T I T I A")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(C.pink)
                .shadow(color: C.pink.opacity(0.55), radius: 12)
                .padding(.bottom, 5)

            // Séparateur néon rose (#44FF0178)
            Rectangle().fill(C.pink.opacity(0.27)).frame(height: 1)
                .padding(.horizontal, 30)
                .padding(.bottom, 8)

            // Micro (glow 110 + btn 72)
            MicBtn(glowSize: 100, btnSize: 66)

            // "Tap to record" (11sp cyan Android)
            Text("Tap to record")
                .font(.system(size: 11, weight: .light))
                .foregroundColor(C.cyan.opacity(0.60))
                .padding(.top, 4)

            Spacer(minLength: 2)

            // Zone dernière transcription
            Text(
                e.lastTranscript.isEmpty
                    ? "Dernière transcription apparaîtra ici"
                    : "\"\(trunc(e.lastTranscript, n: 90))\""
            )
            .font(.system(size: 9))
            .foregroundColor(.white.opacity(e.lastTranscript.isEmpty ? 0.22 : 0.50))
            .lineLimit(3)
            .multilineTextAlignment(.center)
        }
    }

    // ── RECORDING ──
    private var recState: some View {
        VStack(spacing: 0) {
            // En-tête : ● REC — 00:00 (horizontal, identique Android)
            HStack(spacing: 0) {
                Circle().fill(C.red).frame(width: 8, height: 8)
                Text(" REC")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(C.red)
                    .shadow(color: C.red.opacity(0.70), radius: 10)

                Text("  —  ")
                    .font(.system(size: 14)).foregroundColor(C.cyan.opacity(0.35))

                Text(e.timer)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(C.cyan)
                    .shadow(color: C.cyan.opacity(0.60), radius: 14)
            }
            .padding(.bottom, 5)

            // Séparateur néon rouge (#55FF3366)
            Rectangle().fill(C.red.opacity(0.33)).frame(height: 1)
                .padding(.horizontal, 30)
                .padding(.bottom, 6)

            // Stop (glow 100 + btn 64)
            StopBtn(glowSize: 90, btnSize: 58)

            Spacer(minLength: 2)

            // Zone transcription live (cyan, 10sp Android)
            Text(
                e.liveTranscript.isEmpty
                    ? "En attente de transcription…"
                    : trunc(e.liveTranscript, n: 100)
            )
            .font(.system(size: 10))
            .foregroundColor(C.cyan.opacity(e.liveTranscript.isEmpty ? 0.35 : 0.80))
            .lineLimit(4)
            .multilineTextAlignment(.center)
            .lineSpacing(2)
        }
    }

    private func trunc(_ s: String, n: Int) -> String {
        s.count > n ? "…\(s.suffix(n))" : s
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Lock Screen Widget (accessoryCircular)
// ═══════════════════════════════════════════════════════════════════════════════

@available(iOSApplicationExtension 16.0, *)
private struct LockView: View {
    let e: NotitiaEntry

    var body: some View {
        Link(destination: URL(string: "notitia://record")!) {
            ZStack {
                AccessoryWidgetBackground()
                if e.isRecording {
                    RoundedRectangle(cornerRadius: 3).fill(.white)
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

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Router
// ═══════════════════════════════════════════════════════════════════════════════

struct NotitiaWidgetEntryView: View {
    var entry: NotitiaEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallView(e: entry)
        case .systemMedium:
            LargeView(e: entry)
        case .accessoryCircular:
            if #available(iOSApplicationExtension 16.0, *) {
                LockView(e: entry)
            }
        default:
            SmallView(e: entry)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Widget Declaration
// ═══════════════════════════════════════════════════════════════════════════════

struct NotitiaWidget: Widget {
    let kind = "NotitiaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NotitiaProvider()) { entry in
            NotitiaWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Notitia Capture")
        .description("Capture vocale cyberpunk. Petit = micro + label. Grand = micro + timer + transcription.")
        .supportedFamilies(families)
    }

    private var families: [WidgetFamily] {
        var f: [WidgetFamily] = [.systemSmall, .systemMedium]
        if #available(iOSApplicationExtension 16.0, *) {
            f.append(.accessoryCircular)
        }
        return f
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Previews
// ═══════════════════════════════════════════════════════════════════════════════

struct NotitiaWidget_Previews: PreviewProvider {
    static var previews: some View {
        let idle = NotitiaEntry(date: .now, isRecording: false, timer: "00:00",
                                liveTranscript: "", lastTranscript: "")
        let rec  = NotitiaEntry(date: .now, isRecording: true, timer: "02:34",
                                liveTranscript: "Alors pour le projet Notitia on va implémenter les widgets natifs avec un design cyberpunk…",
                                lastTranscript: "")
        let idleT = NotitiaEntry(date: .now, isRecording: false, timer: "00:00",
                                 liveTranscript: "",
                                 lastTranscript: "Réunion du lundi : discuter du sprint planning et des objectifs Q2.")

        Group {
            // Petit — Idle
            NotitiaWidgetEntryView(entry: idle)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .previewDisplayName("Petit — Idle")

            // Petit — Recording
            NotitiaWidgetEntryView(entry: rec)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .previewDisplayName("Petit — REC")

            // Grand — Idle (avec dernière transcription)
            NotitiaWidgetEntryView(entry: idleT)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .previewDisplayName("Grand — Idle")

            // Grand — Recording
            NotitiaWidgetEntryView(entry: rec)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .previewDisplayName("Grand — REC")
        }
    }
}