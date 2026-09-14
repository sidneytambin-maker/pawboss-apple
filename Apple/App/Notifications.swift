import Foundation
import UserNotifications
import PawBossCore

struct BusinessLink: Codable {
    var businessID: UUID
    var kind: String
    var recordID: UUID?
}
@MainActor final class BusinessNotifications: NSObject, UNUserNotificationCenterDelegate {
    var onOpen: ((BusinessLink) -> Void)?
    override init() { super.init(); UNUserNotificationCenter.current().delegate = self }
    func requestPermission() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
    func clear() { UNUserNotificationCenter.current().removeAllPendingNotificationRequests() }
    func refresh(old: BusinessState?, new: BusinessState, preferences: AppPreferences) {
        #if os(iOS)
        clear()
        guard preferences.notificationEnabled else { return }
        var reminders: [(String, String, String, BusinessLink)] = []
        if preferences.notifications["Enquiries"] == true, let enquiry = new.pendingEnquiries.first {
            reminders.append(("enquiry", "A new care relationship", "\(enquiry.customer.name)'s enquiry for \(enquiry.dog.name) is waiting.", BusinessLink(businessID: new.id, kind: "enquiry", recordID: enquiry.id)))
        }
        if preferences.notifications["Medication"] == true, let dog = new.dogs.first(where: { $0.present && $0.medications.contains { $0.dueDay <= new.day && !$0.givenDays.contains(new.day) } }) {
            reminders.append(("medication", "Care record to complete", "\(dog.name)'s medication record is outstanding on business day \(new.day + 1).", BusinessLink(businessID: new.id, kind: "medication", recordID: dog.id)))
        }
        if preferences.notifications["Vaccinations"] == true, let dog = new.dogs.first(where: { $0.vaccinationDueDay <= new.day + 7 }) {
            reminders.append(("vaccination", "Vaccination record review", "Check \(dog.name)'s record before the next booking.", BusinessLink(businessID: new.id, kind: "vaccination", recordID: dog.id)))
        }
        if preferences.notifications["Inspections"] == true, let day = new.licence.inspectionDay {
            reminders.append(("inspection", "Prepare for your inspection", "Your council inspection is due on business day \(day + 1).", BusinessLink(businessID: new.id, kind: "inspection")))
        }
        if preferences.notifications["Staff"] == true, let member = new.staff.first(where: { $0.employed && ($0.absentUntilDay ?? -1) >= new.day }) {
            reminders.append(("staff", "Review care cover", "\(member.name) is away. Check their rota and upcoming bookings.", BusinessLink(businessID: new.id, kind: "staff", recordID: member.id)))
        }
        if preferences.notifications["Messages"] == true, let message = new.messages.last(where: { !$0.read && !$0.archived && [.message, .complaint].contains($0.kind) }) {
            reminders.append(("message", message.title, "A message from \(message.sender) is waiting.", BusinessLink(businessID: new.id, kind: "message", recordID: message.id)))
        }
        if preferences.notifications["Reports"] == true, let message = new.messages.last(where: { !$0.read && !$0.archived && $0.kind == .report }) {
            reminders.append(("report", message.title, "Your business report is ready to explore.", BusinessLink(businessID: new.id, kind: "message", recordID: message.id)))
        }
        if preferences.notifications["Anniversaries"] == true, new.day > 0, new.day % 365 == 0 {
            reminders.insert(("anniversary", "A business worth celebrating", "\(new.name) has reached \(new.day / 365) years in business. Explore your story.", BusinessLink(businessID: new.id, kind: "anniversary")), at: 0)
        }
        for (index, reminder) in reminders.prefix(4).enumerated() {
            guard let data = try? JSONEncoder().encode(reminder.3) else { continue }
            let content = UNMutableNotificationContent()
            content.title = reminder.1; content.body = reminder.2; content.sound = .default
            content.userInfo = ["pawbossLink": data.base64EncodedString()]
            content.threadIdentifier = new.id.uuidString
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(6 + index * 6) * 3600, repeats: false)
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "pawboss-\(reminder.0)", content: content, trigger: trigger))
        }
        #endif
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if let value = response.notification.request.content.userInfo["pawbossLink"] as? String, let data = Data(base64Encoded: value), let link = try? JSONDecoder().decode(BusinessLink.self, from: data) {
            Task { @MainActor in self.onOpen?(link) }
        }
        completionHandler()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([]) }
}
