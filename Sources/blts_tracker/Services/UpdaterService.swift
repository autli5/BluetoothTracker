import Foundation
import UserNotifications
import AppKit

public final class UpdaterService: ObservableObject {
    public static let shared = UpdaterService()
    
    @Published public var isUpdating: Bool = false
    @Published public var updateStatusMessage: String = ""
    
    private init() {}
    
    public func checkForUpdatesAndApply() {
        guard !isUpdating else { return }
        
        isUpdating = true
        updateStatusMessage = "Проверка обновлений на GitHub..."
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let projectDir = "/Users/autli/Documents/blts_tracker"
            let updateScript = """
            cd "\(projectDir)"
            git fetch origin main 2>&1
            LOCAL=$(git rev-parse HEAD)
            REMOTE=$(git rev-parse origin/main)
            
            if [ "$LOCAL" != "$REMOTE" ] || [ -f "\(projectDir)/force_update" ]; then
                echo "UPDATE_FOUND"
                git pull origin main 2>&1
                ./build_app.sh 2>&1
                
                USER_APPS="$HOME/Applications"
                mkdir -p "$USER_APPS"
                rm -rf "$USER_APPS/BLTS Tracker.app"
                cp -R "\(projectDir)/BLTS Tracker.app" "$USER_APPS/"
                xattr -cr "$USER_APPS/BLTS Tracker.app" 2>/dev/null || true
                
                if [ -w "/Applications" ]; then
                    rm -rf "/Applications/BLTS Tracker.app"
                    cp -R "\(projectDir)/BLTS Tracker.app" "/Applications/"
                    xattr -cr "/Applications/BLTS Tracker.app" 2>/dev/null || true
                fi
                
                echo "SUCCESS"
            else
                echo "UP_TO_DATE"
            fi
            """
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", updateScript]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                DispatchQueue.main.async {
                    self?.isUpdating = false
                    
                    if output.contains("SUCCESS") {
                        self?.sendNotification(
                            title: "🎉 Обновление установлено",
                            body: "BLTS Tracker успешно обновлён с GitHub! Перезапуск..."
                        )
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            let appPath = "\(projectDir)/BLTS Tracker.app"
                            let p = Process()
                            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                            p.arguments = [appPath]
                            try? p.run()
                            exit(0)
                        }
                    } else if output.contains("UP_TO_DATE") {
                        self?.sendNotification(
                            title: "✅ У вас последняя версия",
                            body: "Обновлений на GitHub нет, установлена актуальная версия."
                        )
                    } else {
                        print("Update output: \(output)")
                        self?.sendNotification(
                            title: "ℹ️ Проверка завершена",
                            body: "Репозиторий проверен. Код актуален."
                        )
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isUpdating = false
                    print("Failed to run update: \(error)")
                }
            }
        }
    }
    
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "updater_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
