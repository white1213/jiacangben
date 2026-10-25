package com.white1213.jiacangben

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

/**
 * v1.6：临期提醒桌面小部件。
 *
 * 数据流：Flutter 侧 WidgetService 把快照 JSON（名称/到期毫秒/是否过期）写入
 * home_widget 共享存储；本 Provider 在 onUpdate（30 分钟系统周期 + App 打开时触发）
 * 读取快照并用「当前时刻」现算剩余天数——不打开 App 数字也不会 stale。
 */
class ExpiringWidgetProvider : HomeWidgetProvider() {

    private data class Row(val name: String, val expireMillis: Long, val expired: Boolean)

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val rows = parseRows(widgetData.getString(ROWS_KEY, null))
        val views = buildViews(context, rows)
        appWidgetIds.forEach { appWidgetManager.updateAppWidget(it, views) }
    }

    private fun parseRows(json: String?): List<Row> {
        if (json.isNullOrEmpty()) return emptyList()
        return try {
            val arr = JSONArray(json)
            (0 until arr.length()).mapNotNull { i ->
                val o = arr.getJSONObject(i)
                val name = o.optString("n")
                val expire = o.optLong("e")
                if (name.isEmpty() || expire <= 0L) null
                else Row(name, expire, o.optInt("x", 0) == 1)
            }
        } catch (_: Exception) {
            emptyList() // 快照损坏按空处理，避免拖垮整个小部件
        }
    }

    private fun buildViews(context: Context, rows: List<Row>): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.expiring_widget)
        // 点击任意位置 → 打开 App 直达「临期+过期」筛选
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = Uri.parse(URI_URGENT)
        }
        val pending = PendingIntent.getActivity(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(R.id.widget_root, pending)

        views.setViewVisibility(R.id.widget_empty, if (rows.isEmpty()) View.VISIBLE else View.GONE)
        for (i in 0 until ROW_COUNT) {
            val rowId = ROW_IDS[i]
            val visible = i < rows.size
            views.setViewVisibility(rowId, if (visible) View.VISIBLE else View.GONE)
            if (!visible) continue
            val row = rows[i]
            views.setTextViewText(NAME_IDS[i], row.name)
            views.setTextViewText(DAYS_IDS[i], daysLeftLabel(row.expireMillis))
            views.setTextColor(DAYS_IDS[i], if (row.expired) COLOR_EXPIRED else COLOR_EXPIRING)
        }
        return views
    }

    /** 剩余天数标签：过期向上取整、不足一天=今天到期、其余向下取整 */
    private fun daysLeftLabel(expireMillis: Long): String {
        val diff = expireMillis - System.currentTimeMillis()
        return when {
            diff < 0 -> {
                val overdue = ((-diff + DAY_MS - 1) / DAY_MS).toInt()
                if (overdue <= 0) "刚过期" else "过期${overdue}天"
            }
            diff < DAY_MS -> "今天到期"
            else -> "剩${(diff / DAY_MS).toInt()}天"
        }
    }

    private companion object {
        const val ROWS_KEY = "jiacangben_expiring_rows"
        const val ROW_COUNT = 5
        const val URI_URGENT = "jiacangben://supplies?filter=urgent"
        const val DAY_MS = 24 * 60 * 60 * 1000L
        const val COLOR_EXPIRED = 0xFFE55555.toInt()
        const val COLOR_EXPIRING = 0xFF8A6D00.toInt()
        val ROW_IDS = intArrayOf(R.id.row_0, R.id.row_1, R.id.row_2, R.id.row_3, R.id.row_4)
        val NAME_IDS = intArrayOf(R.id.tv_name_0, R.id.tv_name_1, R.id.tv_name_2, R.id.tv_name_3, R.id.tv_name_4)
        val DAYS_IDS = intArrayOf(R.id.tv_days_0, R.id.tv_days_1, R.id.tv_days_2, R.id.tv_days_3, R.id.tv_days_4)
    }
}
