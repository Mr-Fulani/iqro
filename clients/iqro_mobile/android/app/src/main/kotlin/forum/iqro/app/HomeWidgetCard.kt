package forum.iqro.app

import android.content.Context
import android.widget.RemoteViews
import androidx.compose.ui.unit.DpSize
import kotlin.math.max
import kotlin.math.min

/**
 * Keeps a home screen widget card near its 2:1 design. A launcher cell on a
 * tablet (or a big phone grid) is much taller than the card needs, and the
 * card stretched to fill it; the frame around the card now takes the rest.
 */
internal object HomeWidgetCard {
    private const val MAX_HEIGHT_DP = 200f
    private const val MAX_WIDTH_DP = 560f
    private const val MAX_HEIGHT_PER_WIDTH = 0.55f

    fun fit(context: Context, views: RemoteViews, frameId: Int, size: DpSize) {
        val width = size.width.value
        val height = size.height.value
        if (!width.isFinite() || !height.isFinite() || width <= 0f || height <= 0f) return
        val cardWidth = min(width, MAX_WIDTH_DP)
        val cardHeight = min(height, min(MAX_HEIGHT_DP, cardWidth * MAX_HEIGHT_PER_WIDTH))
        val density = context.resources.displayMetrics.density
        val sides = (max(0f, width - cardWidth) / 2 * density).toInt()
        val ends = (max(0f, height - cardHeight) / 2 * density).toInt()
        views.setViewPadding(frameId, sides, ends, sides, ends)
    }
}
