// v1.8 一次性工具：生成应用图标三件套（运行：dart run tool/gen_icon.dart）
// 设计：棕底 + 奶油色台账册（左脊 + 三行字）+ 右上临期黄圆点，呼应主题色与预警语义。
// image 4.x 无圆角矩形，用切角多边形近似。
import 'dart:io';
import 'package:image/image.dart' as img;

// image 4.x ColorRgb8 构造非 const，用 final
final brown = img.ColorRgb8(0x8D, 0x6E, 0x63);
final deepBrown = img.ColorRgb8(0x5D, 0x40, 0x37);
final cream = img.ColorRgb8(0xFF, 0xF8, 0xE1);
final amber = img.ColorRgb8(0xF9, 0xD5, 0x6E);

/// 切角近似圆角矩形（八点多边形）
void _fillRRect(img.Image g, int x0, int y0, int x1, int y1, int r, img.Color c) {
  img.fillPolygon(g, vertices: [
    img.Point(x0 + r, y0),
    img.Point(x1 - r, y0),
    img.Point(x1, y0 + r),
    img.Point(x1, y1 - r),
    img.Point(x1 - r, y1),
    img.Point(x0 + r, y1),
    img.Point(x0, y1 - r),
    img.Point(x0, y0 + r),
  ], color: c);
}

img.Image _glyph(int size, {double scale = 0.62}) {
  // 册子图形画在透明底上；scale 控制占整图比例（自适应图标需留安全区）
  // image 4.x 新图默认 numChannels=3（无 alpha，底为不透明黑），透明底必须显式开 RGBA
  final g = img.Image(width: size, height: size, numChannels: 4);
  final w = (size * scale).round();
  final h = (w * 1.18).round();
  final x0 = (size - w) ~/ 2;
  final y0 = (size - h) ~/ 2;
  final r = (w * 0.12).round();
  // 册体
  _fillRRect(g, x0, y0, x0 + w, y0 + h, r, cream);
  // 左脊（叠在册体左缘）
  _fillRRect(g, x0, y0, x0 + (w * 0.16).round(), y0 + h, r, deepBrown);
  // 三行「文字」横线
  final lineX0 = x0 + (w * 0.28).round();
  final lineX1 = x0 + (w * 0.88).round();
  final lineH = (h * 0.035).round();
  for (var i = 0; i < 3; i++) {
    final ly = y0 + (h * (0.28 + i * 0.18)).round();
    _fillRRect(g, lineX0, ly, lineX1, ly + lineH, lineH ~/ 2, brown);
  }
  // 右上临期黄圆点
  final dotR = (w * 0.13).round();
  final cx = x0 + w - (w * 0.04).round();
  final cy = y0 - (h * 0.02).round();
  img.fillCircle(g, x: cx, y: cy, radius: dotR, color: amber);
  return g;
}

void main() {
  Directory('assets/icon').createSync(recursive: true);
  // 1) 主图标：棕底 + 图形（legacy + iOS）
  final main = img.Image(width: 1024, height: 1024);
  img.fill(main, color: brown);
  img.compositeImage(main, _glyph(1024));
  File('assets/icon/icon.png').writeAsBytesSync(img.encodePng(main));
  // 2) 自适应前景：透明底 + 图形缩进（安全区）
  File('assets/icon/adaptive_fg.png').writeAsBytesSync(img.encodePng(_glyph(1024, scale: 0.52)));
  // 3) 启动画面用：透明底小图
  File('assets/icon/splash_glyph.png').writeAsBytesSync(img.encodePng(_glyph(576, scale: 0.66)));
  print('icons generated under assets/icon/');
}
