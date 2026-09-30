import 'package:flutter/material.dart';

import '../../database/consume_log_service.dart';
import '../../model/consume_log.dart';
import '../../utils/date_utils.dart';

/// v1.4：单条物资的出库流水历史（只读，不可编辑/删除——流水不可篡改）
class ConsumeHistorySection extends StatefulWidget {
  final int supplyId;

  const ConsumeHistorySection({super.key, required this.supplyId});

  @override
  State<ConsumeHistorySection> createState() => _ConsumeHistorySectionState();
}

class _ConsumeHistorySectionState extends State<ConsumeHistorySection> {
  final ConsumeLogService _service = ConsumeLogService();

  bool _loading = true;
  List<ConsumeLog> _logs = const [];
  int _totalConsumed = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final logs = await _service.listBySupply(widget.supplyId);
    final total = await _service.totalConsumed(widget.supplyId);
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _totalConsumed = total;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('出库流水（只读，共 $_logs 条 / 累计领用 $_totalConsumed）',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_logs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('暂无出库记录', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          )
        else
          for (final log in _logs)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.outbound, size: 18),
              title: Text(
                '出库 ${log.deductCount}（${formatLocalDateTime(log.consumeTime)}）',
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: (log.remark ?? '').trim().isEmpty
                  ? null
                  : Text('备注：${log.remark}', style: const TextStyle(fontSize: 12)),
            ),
      ],
    );
  }
}
