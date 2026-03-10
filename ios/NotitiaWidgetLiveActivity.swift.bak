//
//  NotitiaWidgetLiveActivity.swift
//  NotitiaWidget
//
//  Created by Lucas Lejeune on 10/03/2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct NotitiaWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct NotitiaWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NotitiaWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension NotitiaWidgetAttributes {
    fileprivate static var preview: NotitiaWidgetAttributes {
        NotitiaWidgetAttributes(name: "World")
    }
}

extension NotitiaWidgetAttributes.ContentState {
    fileprivate static var smiley: NotitiaWidgetAttributes.ContentState {
        NotitiaWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: NotitiaWidgetAttributes.ContentState {
         NotitiaWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: NotitiaWidgetAttributes.preview) {
   NotitiaWidgetLiveActivity()
} contentStates: {
    NotitiaWidgetAttributes.ContentState.smiley
    NotitiaWidgetAttributes.ContentState.starEyes
}
