import Foundation
import AppKit
import UserNotifications

/// Yeni mail bildirimleri ve Dock rozeti için küçük yardımcı. Otomatik senkron açıkken
/// gerçek yeni mail geldiğinde — ve kullanıcı Ayarlar > Genel'den açtıysa — macOS bildirimi
/// gösterir ve Dock ikonuna rozet basar. Tümü opt-in; bayrak kapalıyken hiçbir görsel iz kalmaz.
enum MailNotifier {
    /// Sabit bildirim kimliği: her yeni dalga öncekini DEĞİŞTİRSİN (replace), bildirimler yığılmasın.
    private static let notificationID = "trova.newmail"

    /// Bildirim iznini yalnız gerekiyorsa ister. Mevcut durum `.notDetermined` ise `.alert`+`.badge`
    /// izni ister ve kullanıcının kararını döndürür; zaten verilmişse `true`, reddedilmişse SESSİZCE
    /// `false` döner (hata banner'ı YOK). Ayarlar toggle'ı AÇILINCA çağrılır.
    @discardableResult
    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .badge])) ?? false
        @unknown default:
            return false
        }
    }

    /// Mevcut bildirim izin durumunu (istemeden, yalnız okuyarak) döndürür. Ayarlar ekranı bununla
    /// "izin reddedilmiş" uyarısını `.denied` iken gösterir.
    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Tek yeni-mail bildirimi gönderir. Çağıran (AppModel) bunu senkron dalgası başına YALNIZ BİR KEZ
    /// çağırır. Sabit kimlik sayesinde yeni dalga öncekini değiştirir; bildirimler üst üste yığılmaz.
    /// Anında gönderilir (trigger nil).
    static func notifyNewMail(count: Int, senderPreview: String?) {
        let content = UNMutableNotificationContent()
        content.title = "Trova"
        if count == 1, let sender = senderPreview, !sender.isEmpty {
            content.body = "Yeni mail: \(sender)"
        } else {
            content.body = "\(count) yeni mail"
        }
        let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Dock ikonundaki rozeti günceller. `count` 0 ise rozet kaldırılır. Ana thread'de çalışmalı
    /// (NSApp erişimi MainActor'a bağlı).
    @MainActor
    static func updateDockBadge(_ count: Int) {
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }
}
