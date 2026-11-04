package forum.iqro.app

import forum.iqro.app.ReadingPlanWidgetViews.Face
import org.junit.Assert.assertEquals
import org.junit.Test

class ReadingPlanWidgetFaceTest {
    private val midnight = 1_790_000_000_000L

    private fun face(isCurrent: Boolean = true, hasNextDay: Boolean = true, now: Long) =
        ReadingPlanWidgetViews.face(isCurrent, midnight, hasNextDay, now)

    @Test
    fun publishedDayIsShownUntilMidnight() {
        assertEquals(Face.TODAY, face(now = midnight - 1))
    }

    @Test
    fun nextDayStartsAtMidnightWithoutTheApp() {
        assertEquals(Face.NEXT_DAY, face(now = midnight))
        // Days later the goal is still shown, not an empty card.
        assertEquals(Face.NEXT_DAY, face(now = midnight + 3 * 86_400_000L))
    }

    @Test
    fun oldSnapshotsWithoutNextDayStillExpire() {
        assertEquals(Face.EMPTY, face(hasNextDay = false, now = midnight))
    }

    @Test
    fun noPlanShowsTheInvitation() {
        assertEquals(Face.EMPTY, face(isCurrent = false, now = midnight - 1))
        assertEquals(Face.EMPTY, face(isCurrent = false, now = midnight + 1))
    }
}
