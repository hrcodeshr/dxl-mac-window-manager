import DXLSnapCore
import Foundation

enum LayoutStore {
    static func load() {
        guard let data = try? Data(contentsOf: AppSupport.layoutsURL) else { return }
        guard let file = try? JSONDecoder().decode(File.self, from: data) else {
            AppLog.error("could not decode custom layouts")
            return
        }
        LayoutRegistry.shared.customLayouts = file.layouts.filter { LayoutCatalog.builtIn(id: $0.id) == nil }
        AppLog.info("loaded \(LayoutRegistry.shared.customLayouts.count) custom layout(s)")
    }

    static func save() {
        let file = File(layouts: LayoutRegistry.shared.customLayouts)
        do {
            let data = try JSONEncoder().encode(file)
            try data.write(to: AppSupport.layoutsURL, options: .atomic)
            AppLog.info("saved \(file.layouts.count) custom layout(s)")
        } catch {
            AppLog.error("save layouts failed: \(error.localizedDescription)")
        }
    }

    static func add(_ layout: SnapLayout) {
        LayoutRegistry.shared.customLayouts.removeAll { $0.id == layout.id }
        LayoutRegistry.shared.customLayouts.append(layout)
        save()
    }

    static func remove(id: String) {
        LayoutRegistry.shared.customLayouts.removeAll { $0.id == id }
        save()
    }

    private struct File: Codable {
        var layouts: [SnapLayout]
    }
}
