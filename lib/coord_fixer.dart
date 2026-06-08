import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:xml/xml.dart';

extension GpsFormatter on double {
  static final Pattern _trimZeros = RegExp(r'\.?0+$');
  String toGpsString() {
    return toStringAsFixed(10).replaceFirst(_trimZeros, '');
  }
}

class CoordinateConverter {
  static const double earthR = 6378137.0;
  static const double ee = 0.00669342162296594323;

  static bool outOfChina(double lat, double lng) {
    if (lng < 72.004 || lng > 137.8347) return true;
    if (lat < 0.8293 || lat > 55.8271) return true;
    return false;
  }

  static List<double> _transform(double x, double y) {
    double xy = x * y;
    double absX = math.sqrt(x.abs());
    double xPi = x * math.pi;
    double yPi = y * math.pi;
    double d = 20.0 * math.sin(6.0 * xPi) + 20.0 * math.sin(2.0 * xPi);

    double lat = d;
    double lng = d;

    lat += 20.0 * math.sin(yPi) + 40.0 * math.sin(yPi / 3.0);
    lng += 20.0 * math.sin(xPi) + 40.0 * math.sin(xPi / 3.0);

    lat += 160.0 * math.sin(yPi / 12.0) + 320 * math.sin(yPi / 30.0);
    lng += 150.0 * math.sin(xPi / 12.0) + 300.0 * math.sin(xPi / 30.0);

    lat *= 2.0 / 3.0;
    lng *= 2.0 / 3.0;

    lat += -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * xy + 0.2 * absX;
    lng += 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * xy + 0.1 * absX;

    return [lat, lng];
  }

  static List<double> _delta(double lat, double lng) {
    List<double> t = _transform(lng - 105.0, lat - 35.0);
    double dLat = t[0];
    double dLng = t[1];

    double radLat = lat / 180.0 * math.pi;
    double magic = math.sin(radLat);
    magic = 1 - ee * magic * magic;
    double sqrtMagic = math.sqrt(magic);

    dLat = (dLat * 180.0) / ((earthR * (1 - ee)) / (magic * sqrtMagic) * math.pi);
    dLng = (dLng * 180.0) / (earthR / sqrtMagic * math.cos(radLat) * math.pi);
    return [dLat, dLng];
  }

  static List<double> gcj2WGSExact(double gcjLat, double gcjLng) {
    if (outOfChina(gcjLat, gcjLng)) return [gcjLat, gcjLng];

    double newLat = gcjLat, newLng = gcjLng;
    double oldLat, oldLng;
    const double threshold = 1e-6;

    for (int i = 0; i < 30; i++) {
      oldLat = newLat;
      oldLng = newLng;
      List<double> d = _delta(newLat, newLng);
      newLat = gcjLat - d[0];
      newLng = gcjLng - d[1];
      if (max((oldLat - newLat).abs(), (oldLng - newLng).abs()) < threshold) break;
    }
    return [newLat, newLng];
  }

  static List<double> wgs2Gcj(double wgsLat, double wgsLng) {
    if (outOfChina(wgsLat, wgsLng)) return [wgsLat, wgsLng];
    List<double> d = _delta(wgsLat, wgsLng);
    return [wgsLat + d[0], wgsLng + d[1]];
  }

  static bool _isSingleCoordLikelyWGS84(double lat, double lng) {
    if (outOfChina(lat, lng)) return true;
    List<double> asWgs2Gcj = wgs2Gcj(lat, lng);
    List<double> asGcj2Wgs = gcj2WGSExact(lat, lng);
    double offsetIfWgs = _distance(lat, lng, asWgs2Gcj[0], asWgs2Gcj[1]);
    double offsetIfGcj = _distance(lat, lng, asGcj2Wgs[0], asGcj2Wgs[1]);
    return offsetIfWgs > offsetIfGcj;
  }

  static bool isLikelyWGS84(double lat, double lng) {
    return _isSingleCoordLikelyWGS84(lat, lng);
  }

  static bool? isLikelyWGS84Enhanced(List<List<double>> coords, {int minSamples = 3, int maxSamples = 10}) {
    if (coords.isEmpty) return null;

    final validCoords = <List<double>>[];
    for (var coord in coords) {
      if (coord.length >= 2) {
        if (!outOfChina(coord[0], coord[1])) {
          validCoords.add(coord);
          if (validCoords.length >= maxSamples) break;
        }
      }
    }
    if (validCoords.isEmpty) return true;
    if (validCoords.length < minSamples) {
      return _isSingleCoordLikelyWGS84(validCoords[0][0], validCoords[0][1]);
    }

    int wgsVotes = 0, gcjVotes = 0;
    for (var coord in validCoords) {
      if (_isSingleCoordLikelyWGS84(coord[0], coord[1])) wgsVotes++; else gcjVotes++;
    }
    return wgsVotes > gcjVotes;
  }

  static double _distance(double lat1, double lng1, double lat2, double lng2) {
    double dLat = lat2 - lat1;
    double dLng = lng2 - lng1;
    return math.sqrt(dLat * dLat + dLng * dLng);
  }

  static double max(double a, double b) => a > b ? a : b;
}

/// 坐标纠偏方向
enum CoordDirection {
  /// GCJ-02 → WGS-84（国内平台数据源 → 海外目标平台）
  gcj2wgs,
  /// WGS-84 → GCJ-02（海外平台数据源 → 国内目标平台）
  wgs2gcj,
}

// === FIT 二进制格式常量 ===

// FIT message types that contain coordinate fields
const _MSG_RECORD = 20;
const _MSG_SEGMENT_LAP = 34;
const _MSG_LAP = 19;
const _MSG_SESSION = 2;
const _MSG_COURSE_POINT = 32;
const _MSG_SEGMENT_POINT = 33;

// Field definition numbers for coordinate fields
const _FIELD_POSITION_LAT = 0;
const _FIELD_POSITION_LONG = 1;
const _FIELD_START_POSITION_LAT = 0;
const _FIELD_START_POSITION_LONG = 1;
const _FIELD_END_POSITION_LAT = 2;
const _FIELD_END_POSITION_LONG = 3;
const _FIELD_NEC_LAT = 4;
const _FIELD_NEC_LONG = 5;
const _FIELD_SWC_LAT = 6;
const _FIELD_SWC_LONG = 7;

/// semcircles → degrees
double _semicirclesToDeg(int sc) => sc * (180.0 / 0x80000000);

/// degrees → semcircles
int _degToSemicircles(double deg) => (deg * (0x80000000 / 180.0)).round();

/// FIT CRC 查表
final List<int> _fitCrcTable = _buildFitCrcTable();

List<int> _buildFitCrcTable() {
  final table = List<int>.filled(256, 0);
  for (int i = 0; i < 256; i++) {
    int crc = i;
    for (int j = 0; j < 8; j++) {
      if (crc & 1 != 0) {
        crc = (crc >> 1) ^ 0xEDB88320;
      } else {
        crc >>= 1;
      }
    }
    table[i] = crc;
  }
  return table;
}

int _fitCrcUpdate(int crc, Uint8List data) {
  for (final b in data) {
    crc = _fitCrcTable[(crc ^ b) & 0xFF] ^ (crc >> 8);
  }
  return crc & 0xFFFF;
}

/// FIT 定义消息中一个字段的定义
class _FitFieldDef {
  final int defNum;
  final int size;
  final int baseType;
  _FitFieldDef(this.defNum, this.size, this.baseType);
}

/// 缓存的 FIT 定义消息，用于解析后续数据消息
class _FitDefMsg {
  final int localMsgType;
  final int globalMsgNum;
  final List<_FitFieldDef> fields;
  int totalFieldDataSize = 0;

  _FitDefMsg(this.localMsgType, this.globalMsgNum, this.fields) {
    for (var f in fields) {
      totalFieldDataSize += f.size;
    }
  }
}

/// 需要 patch 的坐标字段信息
class _CoordFieldPatch {
  final int defNum;  // e.g. 0 for position_lat
  final int latDefNum; // paired lat def_num
  _CoordFieldPatch(this.defNum, {required this.latDefNum});
}

/// 根据 global message number 返回需要纠正的坐标字段列表
List<_CoordFieldPatch>? _coordFieldsForMsg(int globalMsgNum) {
  switch (globalMsgNum) {
    case _MSG_RECORD:
    case _MSG_COURSE_POINT:
      return [
        _CoordFieldPatch(_FIELD_POSITION_LAT, latDefNum: _FIELD_POSITION_LAT),
        _CoordFieldPatch(_FIELD_POSITION_LONG, latDefNum: _FIELD_POSITION_LAT),
      ];
    case _MSG_SEGMENT_LAP:
      return [
        _CoordFieldPatch(_FIELD_START_POSITION_LAT, latDefNum: _FIELD_START_POSITION_LAT),
        _CoordFieldPatch(_FIELD_START_POSITION_LONG, latDefNum: _FIELD_START_POSITION_LAT),
        _CoordFieldPatch(_FIELD_END_POSITION_LAT, latDefNum: _FIELD_END_POSITION_LAT),
        _CoordFieldPatch(_FIELD_END_POSITION_LONG, latDefNum: _FIELD_END_POSITION_LAT),
      ];
    case _MSG_LAP:
      return [
        _CoordFieldPatch(_FIELD_START_POSITION_LAT, latDefNum: _FIELD_START_POSITION_LAT),
        _CoordFieldPatch(_FIELD_START_POSITION_LONG, latDefNum: _FIELD_START_POSITION_LAT),
        _CoordFieldPatch(_FIELD_END_POSITION_LAT, latDefNum: _FIELD_END_POSITION_LAT),
        _CoordFieldPatch(_FIELD_END_POSITION_LONG, latDefNum: _FIELD_END_POSITION_LAT),
      ];
    case _MSG_SESSION:
      return [
        _CoordFieldPatch(_FIELD_START_POSITION_LAT, latDefNum: _FIELD_START_POSITION_LAT),
        _CoordFieldPatch(_FIELD_START_POSITION_LONG, latDefNum: _FIELD_START_POSITION_LAT),
        _CoordFieldPatch(_FIELD_NEC_LAT, latDefNum: _FIELD_NEC_LAT),
        _CoordFieldPatch(_FIELD_NEC_LONG, latDefNum: _FIELD_NEC_LAT),
        _CoordFieldPatch(_FIELD_SWC_LAT, latDefNum: _FIELD_SWC_LAT),
        _CoordFieldPatch(_FIELD_SWC_LONG, latDefNum: _FIELD_SWC_LAT),
      ];
    case _MSG_SEGMENT_POINT:
      return [
        _CoordFieldPatch(_FIELD_POSITION_LAT, latDefNum: _FIELD_POSITION_LAT),
        _CoordFieldPatch(_FIELD_POSITION_LONG, latDefNum: _FIELD_POSITION_LAT),
      ];
    default:
      return null;
  }
}

class CoordFixer {
  static bool? lastDetectionResult;
  static int lastSampleCount = 0;

  /// 从 FIT 二进制提取坐标用于检测
  static List<List<double>> _extractCoordsFromBinary(Uint8List fitBytes, {int maxSamples = 10}) {
    final coords = <List<double>>[];
    if (fitBytes.length < 14) return coords;

    final headerSize = fitBytes[0];
    final dataSize = ByteData.sublistView(fitBytes, 4, 8).getUint32(0, Endian.little);
    final bodyEnd = headerSize + dataSize;

    // 第一遍：扫描定义消息，建立缓存
    final defMsgs = <int, _FitDefMsg>{}; // localMsgType → def
    int pos = headerSize;
    while (pos < bodyEnd) {
      final recHeader = fitBytes[pos];
      final isDef = (recHeader & 0x40) != 0; // bit 6 = definition message
      final localMsgType = recHeader & 0x0F;

      if (isDef) {
        // Definition message structure:
        //   [0]: record header
        //   [1]: reserved
        //   [2]: endian (0=LE, 1=BE)
        //   [3:5]: global message number (uint16 LE)
        //   [5]: num fields
        //   [6+]: field definitions (3 bytes each)
        if (pos + 6 > bodyEnd) break;
        final numFields = fitBytes[pos + 5];
        final globalMsgNum = ByteData.sublistView(fitBytes, pos + 3, pos + 5).getUint16(0, Endian.little);
        final fields = <_FitFieldDef>[];
        for (int i = 0; i < numFields; i++) {
          final offset = pos + 6 + i * 3;
          if (offset + 3 > bodyEnd) break;
          fields.add(_FitFieldDef(fitBytes[offset], fitBytes[offset + 1], fitBytes[offset + 2]));
        }
        defMsgs[localMsgType] = _FitDefMsg(localMsgType, globalMsgNum, fields);
        pos += 6 + numFields * 3;
      } else {
        // Data message — use cached definition
        final def = defMsgs[localMsgType];
        if (def == null || _coordFieldsForMsg(def.globalMsgNum) == null) {
          pos++;
          if (def != null) pos += def.totalFieldDataSize;
          continue;
        }
        pos++; // skip record header

        // Read position_lat (def_num=0) and position_long (def_num=1) if available
        int? latSemi, lngSemi;
        int fieldOffset = pos;
        for (var field in def.fields) {
          if (field.defNum == _FIELD_POSITION_LAT || field.defNum == _FIELD_START_POSITION_LAT) {
            if (field.size == 4 && fieldOffset + 4 <= bodyEnd) {
              latSemi = ByteData.sublistView(fitBytes, fieldOffset, fieldOffset + 4).getInt32(0, Endian.little);
            }
          }
          if (field.defNum == _FIELD_POSITION_LONG || field.defNum == _FIELD_START_POSITION_LONG) {
            if (field.size == 4 && fieldOffset + 4 <= bodyEnd) {
              lngSemi = ByteData.sublistView(fitBytes, fieldOffset, fieldOffset + 4).getInt32(0, Endian.little);
            }
          }
          fieldOffset += field.size;
        }
        pos += def.totalFieldDataSize;

        if (latSemi != null && lngSemi != null && latSemi != 0x80000000 && lngSemi != 0x80000000) {
          coords.add([_semicirclesToDeg(latSemi), _semicirclesToDeg(lngSemi)]);
          if (coords.length >= maxSamples) break;
        }
      }
    }
    return coords;
  }

  /// 二进制级别 patch FIT 文件坐标
  /// [direction] 纠偏方向：gcj2wgs (GCJ→WGS) 或 wgs2gcj (WGS→GCJ)
  static Uint8List _patchFitBinary(Uint8List fitBytes, CoordDirection direction) {
    final result = Uint8List.fromList(fitBytes);
    if (result.length < 14) return result;

    final headerSize = result[0];
    final dataSize = ByteData.sublistView(result, 4, 8).getUint32(0, Endian.little);
    final bodyEnd = headerSize + dataSize;

    // 第一遍：扫描定义消息
    final defMsgs = <int, _FitDefMsg>{};
    int pos = headerSize;
    while (pos < bodyEnd) {
      final recHeader = result[pos];
      final isDef = (recHeader & 0x40) != 0;
      final localMsgType = recHeader & 0x0F;

      if (isDef) {
        if (pos + 6 > bodyEnd) break;
        final numFields = result[pos + 5];
        final globalMsgNum = ByteData.sublistView(result, pos + 3, pos + 5).getUint16(0, Endian.little);
        final fields = <_FitFieldDef>[];
        for (int i = 0; i < numFields; i++) {
          final offset = pos + 6 + i * 3;
          if (offset + 3 > bodyEnd) break;
          fields.add(_FitFieldDef(result[offset], result[offset + 1], result[offset + 2]));
        }
        defMsgs[localMsgType] = _FitDefMsg(localMsgType, globalMsgNum, fields);
        pos += 6 + numFields * 3;
      } else {
        // Data message — patch coordinate fields
        final def = defMsgs[localMsgType];
        if (def == null) {
          pos++; // no definition, skip
          continue;
        }
        final coordFields = _coordFieldsForMsg(def.globalMsgNum);

        if (coordFields == null) {
          pos += 1 + def.totalFieldDataSize;
          continue;
        }

        final dataStart = pos + 1; // skip record header

        // Build (latDefNum, lngDefNum) pairs from coord field list
        for (int i = 0; i < coordFields.length; i += 2) {
          final latField = coordFields[i];
          final lngField = (i + 1 < coordFields.length) ? coordFields[i + 1] : null;
          if (lngField == null) break;

          // Find offsets in data for paired lat/lng fields
          int? latOff, lngOff;
          int off = dataStart;
          for (var fd in def.fields) {
            if (fd.defNum == latField.defNum && fd.size == 4) latOff = off;
            if (fd.defNum == lngField.defNum && fd.size == 4) lngOff = off;
            off += fd.size;
          }

          if (latOff != null && lngOff != null &&
              latOff + 4 <= bodyEnd && lngOff + 4 <= bodyEnd) {
            final latSemi = ByteData.sublistView(result, latOff, latOff + 4).getInt32(0, Endian.little);
            final lngSemi = ByteData.sublistView(result, lngOff, lngOff + 4).getInt32(0, Endian.little);

            // 0x80000000 is the invalid/missing value for semicircles
            if (latSemi != 0x80000000 && lngSemi != 0x80000000) {
              final latDeg = _semicirclesToDeg(latSemi);
              final lngDeg = _semicirclesToDeg(lngSemi);
              final corrected = direction == CoordDirection.gcj2wgs
                  ? CoordinateConverter.gcj2WGSExact(latDeg, lngDeg)
                  : CoordinateConverter.wgs2Gcj(latDeg, lngDeg);
              final newLatSemi = _degToSemicircles(corrected[0]);
              final newLngSemi = _degToSemicircles(corrected[1]);

              final bd = ByteData.sublistView(result);
              bd.setInt32(latOff, newLatSemi, Endian.little);
              bd.setInt32(lngOff, newLngSemi, Endian.little);
              // Write back — ByteData.sublistView shares the underlying buffer
            }
          }
        }
        pos += def.totalFieldDataSize + 1;
      }
    }

    // 更新 data_size 和 CRC
    final newDataSize = bodyEnd - headerSize;
    ByteData.sublistView(result, 4, 8).setUint32(0, newDataSize, Endian.little);

    // CRC: header[0:12] + body
    int crc = 0;
    crc = _fitCrcUpdate(crc, Uint8List.sublistView(result, 0, 12));
    crc = _fitCrcUpdate(crc, Uint8List.sublistView(result, headerSize, bodyEnd));
    ByteData.sublistView(result, headerSize - 2, headerSize).setUint16(0, crc, Endian.little);

    // File CRC at the end
    if (fitBytes.length >= headerSize + dataSize + 2) {
      int fileCrc = 0;
      fileCrc = _fitCrcUpdate(fileCrc, Uint8List.sublistView(result, 0, 12));
      fileCrc = _fitCrcUpdate(fileCrc, Uint8List.sublistView(result, headerSize, bodyEnd));
      final crcPos = bodyEnd;
      if (crcPos + 2 <= result.length) {
        ByteData.sublistView(result, crcPos, crcPos + 2).setUint16(0, fileCrc, Endian.little);
      }
    }

    return result;
  }

  static Future<Uint8List> processFitBytes(Uint8List fitBytes, CoordDirection direction) async {
    final coords = _extractCoordsFromBinary(fitBytes);
    lastSampleCount = coords.length;
    if (coords.isEmpty) {
      lastDetectionResult = null;
      return fitBytes;
    }

    // 检测是否需要纠正（如果坐标已经是目标格式则跳过）
    final isWgs84 = CoordinateConverter.isLikelyWGS84Enhanced(coords);
    lastDetectionResult = isWgs84;
    if (direction == CoordDirection.gcj2wgs && isWgs84 == true) return fitBytes;
    if (direction == CoordDirection.wgs2gcj && isWgs84 == false) return fitBytes;

    lastDetectionResult = (direction == CoordDirection.gcj2wgs) ? false : true;
    return _patchFitBinary(fitBytes, direction);
  }

  static Future<Uint8List> processGpxBytes(Uint8List gpxBytes) async {
    final gpxString = utf8.decode(gpxBytes);
    final document = XmlDocument.parse(gpxString);
    const coordinateTags = ['trkpt', 'wpt', 'rtept'];

    final coords = <List<double>>[];
    const maxSamples = 10;
    for (var tagName in coordinateTags) {
      if (coords.length >= maxSamples) break;
      for (var element in document.findAllElements(tagName)) {
        if (coords.length >= maxSamples) break;
        final latAttr = element.getAttribute('lat');
        final lonAttr = element.getAttribute('lon');
        if (latAttr != null && lonAttr != null) {
          double? lat = double.tryParse(latAttr);
          double? lng = double.tryParse(lonAttr);
          if (lat != null && lng != null) coords.add([lat, lng]);
        }
      }
    }

    bool? isWgs84;
    lastSampleCount = coords.length;
    if (coords.isNotEmpty) isWgs84 = CoordinateConverter.isLikelyWGS84Enhanced(coords);
    lastDetectionResult = isWgs84;

    if (isWgs84 == true || coords.isEmpty) return gpxBytes;

    for (var tagName in coordinateTags) {
      for (var element in document.findAllElements(tagName)) {
        final latAttr = element.getAttribute('lat');
        final lonAttr = element.getAttribute('lon');
        if (latAttr != null && lonAttr != null) {
          double? lat = double.tryParse(latAttr);
          double? lng = double.tryParse(lonAttr);
          if (lat != null && lng != null) {
            List<double> corrected = CoordinateConverter.gcj2WGSExact(lat, lng);
            element.setAttribute('lat', corrected[0].toGpsString());
            element.setAttribute('lon', corrected[1].toGpsString());
          }
        }
      }
    }
    return utf8.encode(document.toXmlString());
  }

  static Future<Uint8List> processTcxBytes(Uint8List tcxBytes) async {
    final tcxString = utf8.decode(tcxBytes);
    final document = XmlDocument.parse(tcxString);
    final allLatitudes = document.findAllElements('LatitudeDegrees');

    final coords = <List<double>>[];
    const maxSamples = 10;
    for (var latElem in allLatitudes) {
      if (coords.length >= maxSamples) break;
      final parent = latElem.parentElement;
      if (parent == null) continue;
      final lngElem = parent.findElements('LongitudeDegrees').firstOrNull;
      if (lngElem != null) {
        double? lat = double.tryParse(latElem.innerText);
        double? lng = double.tryParse(lngElem.innerText);
        if (lat != null && lng != null) coords.add([lat, lng]);
      }
    }

    bool? isWgs84;
    lastSampleCount = coords.length;
    if (coords.isNotEmpty) isWgs84 = CoordinateConverter.isLikelyWGS84Enhanced(coords);
    lastDetectionResult = isWgs84;

    if (isWgs84 == true || coords.isEmpty) return tcxBytes;

    for (var latElem in allLatitudes) {
      final parent = latElem.parentElement;
      if (parent == null) continue;
      final lngElem = parent.findElements('LongitudeDegrees').firstOrNull;
      if (lngElem != null) {
        double? lat = double.tryParse(latElem.innerText);
        double? lng = double.tryParse(lngElem.innerText);
        if (lat != null && lng != null) {
          List<double> corrected = CoordinateConverter.gcj2WGSExact(lat, lng);
          latElem.innerText = corrected[0].toGpsString();
          lngElem.innerText = corrected[1].toGpsString();
        }
      }
    }
    return utf8.encode(document.toXmlString());
  }

  static Future<Uint8List> processFile(Uint8List fileBytes, String fileType, CoordDirection direction) async {
    if (fileType == 'fit') return await processFitBytes(fileBytes, direction);
    if (fileType == 'tcx') return await processTcxBytes(fileBytes);
    if (fileType == 'gpx') return await processGpxBytes(fileBytes);
    throw Exception('Unsupported file type: $fileType');
  }
}
