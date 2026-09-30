import 'package:flutter_test/flutter_test.dart';

import 'package:jiacangben/consts.dart';
import 'package:jiacangben/service/backup_service.dart';

void main() {
  const validBackup = '{"app": "家藏本", "schemaVersion": 1, '
      '"storageLocation": [], "storedItem": [], "homeSupply": [], "tag": [], "tagRelation": []}';

  test('本应用导出的备份（含 app + schemaVersion）校验通过', () {
    final data = BackupService().validate(validBackup);
    expect(data['app'], kAppName);
  });

  test('缺少应用标识的 JSON 被拒绝（防误导入不兼容备份）', () {
    expect(
      () => BackupService().validate(
        '{"schemaVersion": 1, "storageLocation": [], "storedItem": [], "homeSupply": [], "tag": [], "tagRelation": []}',
      ),
      throwsFormatException,
    );
  });

  test('未知 schema 版本被拒绝', () {
    expect(
      () => BackupService().validate(
        '{"app": "家藏本", "schemaVersion": 99, "storageLocation": [], "storedItem": [], "homeSupply": [], "tag": [], "tagRelation": []}',
      ),
      throwsFormatException,
    );
  });
}
