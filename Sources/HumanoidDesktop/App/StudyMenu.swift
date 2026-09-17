import Foundation
import TeammateKit

/// The lessons submenu, worked out once from the session so the menu bar item and the right-click menu show the
/// same choices. Nil for a teammate without a course.
@MainActor
struct StudyMenu {
    struct Entry: Identifiable {
        let id: String
        let title: String
        var isChecked = false
        var isEnabled = true
        let action: () -> Void
    }

    let title: String
    /// What to do now: continue, review, end.
    let actions: [Entry]
    /// Every lesson, checked when finished.
    let lessons: [Entry]

    init?(session: TeammateSession, now: Date = Date()) {
        guard let course = session.course, let progress = session.progress else { return nil }
        title = AppText.lessonsMenu(course.title)
        var actions: [Entry] = []
        if session.study != nil {
            actions.append(Entry(id: "end", title: AppText.endLesson) { session.endStudy() })
        }
        if let next = progress.nextLesson(in: course) {
            actions.append(Entry(id: "next", title: AppText.nextLesson(next.title)) { session.startLesson(next) })
        } else {
            actions.append(Entry(id: "next", title: AppText.everyLessonFinished, isEnabled: false) {})
        }
        let due = progress.due(in: course, at: now, limit: .max).count
        actions.append(
            Entry(id: "review", title: due > 0 ? AppText.review(due: due) : AppText.nothingToReview, isEnabled: due > 0)
            {
                session.startReview()
            })
        self.actions = actions
        lessons = course.lessons.map { lesson in
            Entry(id: lesson.key, title: lesson.title, isChecked: progress.lessons[lesson.key] != nil) {
                session.startLesson(lesson)
            }
        }
    }
}
