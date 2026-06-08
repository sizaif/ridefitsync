import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:fit_tool/fit_tool.dart';
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

  /// 判断是否在中国境外
  static bool outOfChina(double lat, double lng) {
    if (lng < 72.004 || lng > 137.8347) return true;
    if (lat < 0.8293 || lat > 55.8271) return true;
    return false;
  }

  /// 转换偏移量辅助函数
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

  /// 计算经纬度差值
  static List<double> _delta(double lat, double lng) {
    List<double> t = _transform(lng - 105.0, lat - 35.0);
    double dLat = t[0];
    double dLng = t[1];

    double radLat = lat / 180.0 * math.pi;
    double magic = math.sin(radLat);
    magic = 1 - ee * magic * magic;
    double sqrtMagic = math.sqrt(magic);

    dLat =
        (dLat * 180.0) / ((earthR * (1 - ee)) / (magic * sqrtMagic) * math.pi);
    dLng = (dLng * 180.0) / (earthR / sqrtMagic * math.cos(radLat) * math.pi);
    return [dLat, dLng];
  }

  /// GCJ-02 转换为 WGS-84 (精确迭代版)
  static List<double> gcj2WGSExact(double gcjLat, double gcjLng) {
    if (outOfChina(gcjLat, gcjLng)) {
      return [gcjLat, gcjLng];
    }

    double newLat = gcjLat;
    double newLng = gcjLng;
    double oldLat, oldLng;
    const double threshold = 1e-6;

    for (int i = 0; i < 30; i++) {
      oldLat = newLat;
      oldLng = newLng;

      List<double> d = _delta(newLat, newLng);
      newLat = gcjLat - d[0];
      newLng = gcjLng - d[1];

      if (max((oldLat - newLat).abs(), (oldLng - newLng).abs()) <
          threshold) {
        break;
      }
    }
    return [newLat, newLng];
  }

  /// WGS-84 转换为 GCJ-02
  static List<double> wgs2Gcj(double wgsLat, double wgsLng) {
    if (outOfChina(wgsLat, wgsLng)) {
      return [wgsLat, wgsLng];
    }

    List<double> d = _delta(wgsLat, wgsLng);
    return [wgsLat + d[0], wgsLng + d[1]];
  }

  /// 检测单个坐标是否为 WGS-84 格式
  /// 返回 true 表示坐标是 WGS-84（不需要纠正）
  /// 返回 false 表示坐标可能是 GCJ-02（需要纠正）
  static bool _isSingleCoordLikelyWGS84(double lat, double lng) {
    // 中国境外不需要纠正
    if (outOfChina(lat, lng)) {
      return true;
    }

    // 双向转换比较
    List<double> asWgs2Gcj = wgs2Gcj(lat, lng);
    List<double> asGcj2Wgs = gcj2WGSExact(lat, lng);

    // 计算两种转换的偏移量（单位：度）
    double offsetIfWgs = _distance(lat, lng, asWgs2Gcj[0], asWgs2Gcj[1]);
    double offsetIfGcj = _distance(lat, lng, asGcj2Wgs[0], asGcj2Wgs[1]);

    // 当输入是 WGS-84 时：
    //   offsetIfWgs = GCJ-02 的偏移量（约 500 米）
    //   offsetIfGcj = 很小（因为 gcj2Wgs 对 WGS-84 坐标几乎不变）
    // 当输入是 GCJ-02 时：
    //   offsetIfWgs = 很小（因为 wgs2Gcj 对 GCJ-02 坐标几乎不变）
    //   offsetIfGcj = GCJ-02 的偏移量（约 500 米）
    return offsetIfWgs > offsetIfGcj;
  }

  /// 检测坐标是否为 WGS-84 格式（单点版本）
  static bool isLikelyWGS84(double lat, double lng) {
    return _isSingleCoordLikelyWGS84(lat, lng);
  }

  /// 检测坐标是否为 WGS-84 格式（多点投票增强版）
  /// 通过多个坐标点投票来提高判断准确性
  ///
  /// [coords] 坐标列表，每个元素为 [lat, lng]
  /// [minSamples] 最少需要的样本数量（默认 3 个）
  /// [maxSamples] 最多使用的样本数量（默认 10 个）
  ///
  /// 返回 true 表示坐标是 WGS-84（不需要纠正）
  /// 返回 false 表示坐标可能是 GCJ-02（需要纠正）
  /// 返回 null 表示没有足够的有效坐标点进行判断
  static bool? isLikelyWGS84Enhanced(
    List<List<double>> coords, {
    int minSamples = 3,
    int maxSamples = 10,
  }) {
    if (coords.isEmpty) return null;

    // 过滤出中国境内的有效坐标点
    final validCoords = <List<double>>[];
    for (var coord in coords) {
      if (coord.length >= 2) {
        final lat = coord[0];
        final lng = coord[1];
        if (!outOfChina(lat, lng)) {
          validCoords.add(coord);
          if (validCoords.length >= maxSamples) break;
        }
      }
    }

    // 如果没有中国境内的坐标点，说明都是国外的，不需要纠正
    if (validCoords.isEmpty) {
      return true;
    }

    // 如果样本数量不足，使用单点判断
    if (validCoords.length < minSamples) {
      return _isSingleCoordLikelyWGS84(validCoords[0][0], validCoords[0][1]);
    }

    // 多点投票
    int wgsVotes = 0;
    int gcjVotes = 0;

    for (var coord in validCoords) {
      if (_isSingleCoordLikelyWGS84(coord[0], coord[1])) {
        wgsVotes++;
      } else {
        gcjVotes++;
      }
    }

    // 多数投票决定结果
    return wgsVotes > gcjVotes;
  }

  /// 计算两个经纬度点之间的距离（单位：度）
  static double _distance(double lat1, double lng1, double lat2, double lng2) {
    double dLat = lat2 - lat1;
    double dLng = lng2 - lng1;
    return math.sqrt(dLat * dLat + dLng * dLng);
  }

  static double max(double a, double b) => a > b ? a : b;
}

class CoordFixer {
  /// 最后一次检测结果：true 表示 WGS-84（不需要纠正），false 表示 GCJ-02（已纠正）
  static bool? lastDetectionResult;

  /// 最后一次检测使用的样本数量
  static int lastSampleCount = 0;

  /// 对坐标进行 GCJ-02 → WGS-84 纠正
  static void _fixCoords(
    double? latField,
    double? lngField,
    void Function(double lat, double lng) onUpdate,
  ) {
    if (latField != null && lngField != null) {
      List<double> wgs84 = CoordinateConverter.gcj2WGSExact(latField, lngField);
      onUpdate(wgs84[0], wgs84[1]);
    }
  }

  /// 从 FIT 文件中提取多个有效坐标点用于检测
  static List<List<double>> _extractCoords(FitFile fitFile, {int maxSamples = 10}) {
    final coords = <List<double>>[];
    for (var record in fitFile.records) {
      if (coords.length >= maxSamples) break;
      final msg = record.message;
      switch (msg) {
        case RecordMessage m:
          if (m.positionLat != null && m.positionLong != null) {
            coords.add([m.positionLat!, m.positionLong!]);
          }
        case CoursePointMessage m:
          if (m.positionLat != null && m.positionLong != null) {
            coords.add([m.positionLat!, m.positionLong!]);
          }
        case SegmentPointMessage m:
          if (m.positionLat != null && m.positionLong != null) {
            coords.add([m.positionLat!, m.positionLong!]);
          }
        case SegmentLapMessage m:
          if (m.startPositionLat != null && m.startPositionLong != null) {
            coords.add([m.startPositionLat!, m.startPositionLong!]);
          }
        case LapMessage m:
          if (m.startPositionLat != null && m.startPositionLong != null) {
            coords.add([m.startPositionLat!, m.startPositionLong!]);
          }
        case SessionMessage m:
          if (m.startPositionLat != null && m.startPositionLong != null) {
            coords.add([m.startPositionLat!, m.startPositionLong!]);
          }
        default:
          break;
      }
    }
    return coords;
  }

  static Future<Uint8List> processFitBytes(Uint8List fitBytes) async {
    final fitFile = FitFile.fromBytes(fitBytes);

    // 检测坐标格式：提取多个有效坐标点进行投票检测
    final coords = _extractCoords(fitFile);
    lastSampleCount = coords.length;
    if (coords.isNotEmpty) {
      final isWgs84 = CoordinateConverter.isLikelyWGS84Enhanced(coords);
      lastDetectionResult = isWgs84;
      if (isWgs84 == true) {
        // 坐标已经是 WGS-84，不需要纠正
        return fitBytes;
      }
    } else {
      lastDetectionResult = null; // 无坐标数据
    }

    // 坐标是 GCJ-02 或无法确定，进行纠正
    for (var record in fitFile.records) {
      final msg = record.message;
      switch (msg) {
        case RecordMessage m:
          _fixCoords(m.positionLat, m.positionLong, (la, lo) {
            m.positionLat = la;
            m.positionLong = lo;
          });
        case CoursePointMessage m:
          _fixCoords(m.positionLat, m.positionLong, (la, lo) {
            m.positionLat = la;
            m.positionLong = lo;
          });
        case SegmentPointMessage m:
          _fixCoords(m.positionLat, m.positionLong, (la, lo) {
            m.positionLat = la;
            m.positionLong = lo;
          });
        case SegmentLapMessage m:
          _fixCoords(m.startPositionLat, m.startPositionLong, (la, lo) {
            m.startPositionLat = la;
            m.startPositionLong = lo;
          });
          _fixCoords(m.endPositionLat, m.endPositionLong, (la, lo) {
            m.endPositionLat = la;
            m.endPositionLong = lo;
          });
        case LapMessage m:
          _fixCoords(m.startPositionLat, m.startPositionLong, (la, lo) {
            m.startPositionLat = la;
            m.startPositionLong = lo;
          });
          _fixCoords(m.endPositionLat, m.endPositionLong, (la, lo) {
            m.endPositionLat = la;
            m.endPositionLong = lo;
          });
        case SessionMessage m:
          _fixCoords(m.startPositionLat, m.startPositionLong, (la, lo) {
            m.startPositionLat = la;
            m.startPositionLong = lo;
          });
          _fixCoords(m.necLat, m.necLong, (la, lo) {
            m.necLat = la;
            m.necLong = lo;
          });
          _fixCoords(m.swcLat, m.swcLong, (la, lo) {
            m.swcLat = la;
            m.swcLong = lo;
          });
        default:
          // 忽略其他消息类型
          break;
      }
    }

    fitFile.crc = null; // 重新计算 CRC
    return fitFile.toBytes();
  }

  static Future<Uint8List> processGpxBytes(Uint8List gpxBytes) async {
    final gpxString = utf8.decode(gpxBytes);
    final document = XmlDocument.parse(gpxString);
    const coordinateTags = ['trkpt', 'wpt', 'rtept'];

    // 检测坐标格式：提取多个有效坐标点进行投票检测
    final coords = <List<double>>[];
    const maxSamples = 10;
    for (var tagName in coordinateTags) {
      if (coords.length >= maxSamples) break;
      final elements = document.findAllElements(tagName);
      for (var element in elements) {
        if (coords.length >= maxSamples) break;
        final latAttr = element.getAttribute('lat');
        final lonAttr = element.getAttribute('lon');
        if (latAttr != null && lonAttr != null) {
          double? lat = double.tryParse(latAttr);
          double? lng = double.tryParse(lonAttr);
          if (lat != null && lng != null) {
            coords.add([lat, lng]);
          }
        }
      }
    }

    // 使用多点投票检测
    bool? isWgs84;
    lastSampleCount = coords.length;
    if (coords.isNotEmpty) {
      isWgs84 = CoordinateConverter.isLikelyWGS84Enhanced(coords);
    }
    lastDetectionResult = isWgs84;

    // 如果检测为 WGS-84，直接返回原文件
    if (isWgs84 == true) {
      return gpxBytes;
    }

    // 坐标是 GCJ-02，进行纠正
    for (var tagName in coordinateTags) {
      final elements = document.findAllElements(tagName);
      for (var element in elements) {
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

    // 检测坐标格式：提取多个有效坐标点进行投票检测
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
        if (lat != null && lng != null) {
          coords.add([lat, lng]);
        }
      }
    }

    // 使用多点投票检测
    bool? isWgs84;
    lastSampleCount = coords.length;
    if (coords.isNotEmpty) {
      isWgs84 = CoordinateConverter.isLikelyWGS84Enhanced(coords);
    }
    lastDetectionResult = isWgs84;

    // 如果检测为 WGS-84，直接返回原文件
    if (isWgs84 == true) {
      return tcxBytes;
    }

    // 坐标是 GCJ-02，进行纠正
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

  static Future<Uint8List> processFile(Uint8List fileBytes, String fileType) async {
    if (fileType == 'fit') {
      return await processFitBytes(fileBytes);
    } else if (fileType == 'tcx') {
      return await processTcxBytes(fileBytes);
    } else if (fileType == 'gpx') {
      return await processGpxBytes(fileBytes);
    } else {
      throw Exception('Unsupported file type: $fileType');
    }
  }
}
