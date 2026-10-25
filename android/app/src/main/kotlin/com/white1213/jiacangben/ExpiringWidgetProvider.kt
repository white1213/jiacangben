package com.white1213.jiacangben

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
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
 *
 * v1.7：单部件可缩放（2x1 ~ 4x2+）。按实例实际高度分档显行数：
 * 约 1 格高 → 隐标题只显最急 1 条；约 2 格高 → 标题 + 3 条；更高 → 标题 + 5 条。
 * 拖动缩放由 onAppWidgetOptionsChanged 实时响应，无需重新添加。
 */
class ExpiringWidgetProvider : HomeWidgetProvider() {

    private data class Row(val name: String, val expireMillis: Long, val expired: Boolean)

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        // 各实例尺寸不同，逐个按自己的高度档位渲染
        val rows = parseRows(widgetData.getString(ROWS_KEY, null))
        appWidgetIds.forEach { id ->
            val tier = tierForHeight(appWidgetManager.getAppWidgetOptions(id))
            appWidgetManager.updateAppWidget(id, buildViews(context, rows, tier))
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle?,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        // 拖动缩放时立即按新尺寸重绘
        val rows = parseRows(widgetPrefs(context).getString(ROWS_KEY, null))
        appWidgetManager.updateAppWidget(appWidgetId, buildViews(context, rows, tierForHeight(newOptions)))
    }

    /** 高度分档：1 格（<110dp）→1 行不显标题；2 格（<180dp）→3 行；更高→5 行 */
    private fun tierForHeight(options: Bundle?): Int {
        val h = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0) ?: 0
        return when {
            h in 1 until TIER3_MIN_DP -> 1
            h in TIER3_MIN_DP until TIER5_MIN_DP -> 3
            else -> 5
        }
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

    /** 读取 home_widget 插件写入的共享数据（onAppWidgetOptionsChanged 不经基类传参，直接按插件约定读） */
    private fun widgetPrefs(context: Context): SharedPreferences =
        context.getSharedPreferences(HOME_WIDGET_PREFS, Context.MODE_PRIVATE)

    private fun buildViews(context: Context, rows: List<Row>, tier: Int): RemoteViews {
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

        // 单行档位：压掉标题，把空间留给内容
        val showTitle = tier > 1
        views.setViewVisibility(R.id.widget_title, if (showTitle) View.VISIBLE else View.GONE)
        views.setViewVisibility(R.id.widget_empty, if (rows.isEmpty()) View.VISIBLE else View.GONE)
        for (i in 0 until ROW_COUNT) {
            val visible = i < tier && i < rows.size
            views.setViewVisibility(ROW_IDS[i], if (visible) View.VISIBLE else View.GONE)
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
        const val TIER3_MIN_DP = 110
        const val TIER5_MIN_DP = 180
        // home_widget 0.10.0 原生存储名（HomeWidgetPlugin.PREFERENCES，internal 不可直接引用）
        const val HOME_WIDGET_PREFS = "HomeWidgetPreferences"
        const val COLOR_EXPIRED = 0xFFE55555.toInt()
        const val COLOR_EXPIRING = 0xFF8A6D00.toInt()
        val ROW_IDS = intArrayOf(R.id.row_0, R.id.row_1, R.id.row_2, R.id.row_3, R.id.row_4)
        val NAME_IDS = intArrayOf(R.id.tv_name_0, R.id.tv_name_1, R.id.tv_name_2, R.id.tv_name_3, R.id.tv_name_4)
        val DAYS_IDS = intArrayOf(R.id.tv_days_0, R.id.tv_days_1, R.id.tv_days_2, R.id.tv_days_3, R.id.tv_days_4)
    }
}
