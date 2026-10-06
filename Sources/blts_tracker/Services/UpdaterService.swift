import Foundation
import UserNotifications
import AppKit

public final class UpdaterService: ObservableObject {
    public static let shared = UpdaterService()
    public static let didUpdateStateNotification = Notification.Name("UpdaterServiceDidUpdateStateNotification")
    
    @Published public var isUpdating: Bool = false
    @Published public var updateStatusMessage: String = ""
    @Published public var progressText: String = ""
    @Published public var progressVisual: String = "▰▱▱▱▱"
    
    private var animationTimer: Timer?
    private var animIndex = 0
    private let animFrames = ["▰▱▱▱▱", "▰▰▱▱▱", "▰▰▰▱▱", "▰▰▰▰▱", "▰▰▰▰▰", "▱▱▱▱▱"]
    
    private init() {}
    
    private func startAnimation(initialStage: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.progressText = initialStage
            self.progressVisual = self.animFrames[0]
            self.animationTimer?.invalidate()
            self.animIndex = 0
            
            self.animationTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                guard let self = self, self.isUpdating else { return }
                self.animIndex = (self.animIndex + 1) % self.animFrames.count
                self.progressVisual = self.animFrames[self.animIndex]
                NotificationCenter.default.post(name: UpdaterService.didUpdateStateNotification, object: self)
            }
            RunLoop.main.add(self.animationTimer!, forMode: .common)
            NotificationCenter.default.post(name: UpdaterService.didUpdateStateNotification, object: self)
        }
    }
    
    private func updateStage(stage: String, visual: String? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.progressText = stage
            if let v = visual { self.progressVisual = v }
            NotificationCenter.default.post(name: UpdaterService.didUpdateStateNotification, object: self)
        }
    }
    
    private func stopAnimation() {
        DispatchQueue.main.async { [weak self] in
            self?.animationTimer?.invalidate()
            self?.animationTimer = nil
            self?.isUpdating = false
            NotificationCenter.default.post(name: UpdaterService.didUpdateStateNotification, object: self)
        }
    }
    
    public func checkForUpdatesAndApply() {
        guard !isUpdating else { return }
        
        isUpdating = true
        updateStatusMessage = "Проверка обновлений на GitHub..."
        startAnimation(initialStage: "Проверка")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let projectDir = "/Users/autli/Documents/blts_tracker"
            
            self?.updateStage(stage: "Связь с GitHub", visual: "▰▰▱▱▱")
            
            let updateScript = """
            cd "\(projectDir)"
            git -c http.timeout=8 fetch origin main 2>&1
            FETCH_STATUS=$?
            
            if [ $FETCH_STATUS -ne 0 ]; then
                echo "NETWORK_ERROR"
                exit 0
            fi
            
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
                
                // Advance visual stages during execution
                DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                    if self?.isUpdating == true {
                        self?.updateStage(stage: "Загрузка", visual: "▰▰▰▱▱")
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 2.5) {
                    if self?.isUpdating == true {
                        self?.updateStage(stage: "Сборка", visual: "▰▰▰▰▱")
                    }
                }
                
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                DispatchQueue.main.async {
                    self?.stopAnimation()
                    
                    if output.contains("SUCCESS") {
                        self?.updateStage(stage: "Готово", visual: "▰▰▰▰▰")
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
                    } else if output.contains("NETWORK_ERROR") {
                        self?.sendNotification(
                            title: "⚠️ Ошибка сети",
                            body: "Не удалось связаться с GitHub. Проверьте интернет или отключите VPN."
                        )
                    } else if output.contains("UP_TO_DATE") {
                        self?.sendNotification(
                            title: "✅ У вас последняя версия",
                            body: "Обновлений на GitHub нет, установлена актуальная версия."
                        )
                    } else {
                        self?.sendNotification(
                            title: "ℹ️ Проверка завершена",
                            body: "Репозиторий проверен. Код актуален."
                        )
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.stopAnimation()
                    self?.sendNotification(
                        title: "⚠️ Ошибка",
                        body: "Не удалось выполнить проверку: \(error.localizedDescription)"
                    )
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
