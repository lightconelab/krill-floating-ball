import Foundation
import ServiceManagement

@MainActor
enum LaunchAtLoginController {
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static var isEnabled: Bool {
        status == .enabled
    }

    static var requiresApproval: Bool {
        status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp

        if enabled {
            guard service.status != .enabled else {
                return
            }
            try service.register()
            return
        }

        guard service.status == .enabled else {
            return
        }
        try service.unregister()
    }

    static func menuTitle() -> String {
        switch status {
        case .enabled:
            return "开机启动：已开启"
        case .notRegistered:
            return "开机启动：已关闭"
        case .requiresApproval:
            return "开机启动：等待系统批准"
        case .notFound:
            return "开机启动：不可用"
        @unknown default:
            return "开机启动：未知状态"
        }
    }
}
