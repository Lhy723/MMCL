//
//  MMCLApp.swift
//  MMCL
//
//  Created by 星音 on 2026/5/27.
//

import SwiftUI
import CoreData

@main
struct MMCLApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
