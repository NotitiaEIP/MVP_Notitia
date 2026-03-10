//
//  NotitiaWidgetBundle.swift
//  NotitiaWidget
//
//  Created by Lucas Lejeune on 10/03/2026.
//

import WidgetKit
import SwiftUI

@main
struct NotitiaWidgetBundle: WidgetBundle {
    var body: some Widget {
        NotitiaWidget()
        NotitiaWidgetControl()
        NotitiaWidgetLiveActivity()
    }
}
