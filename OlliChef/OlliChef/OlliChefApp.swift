//
//  OlliChefApp.swift
//  OlliChef
//
//  Created by Константин Ктиторов on 10. 9. 2026..
//

import SwiftUI

@main
struct OlliChefApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
