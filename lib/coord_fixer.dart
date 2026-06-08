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

enum CoordDirection { gcj2wgs, wgs2gcj }

class CoordFixer {
  static bool? lastDetectionResult;
  static int lastSampleCount = 0;

  /// 从 FIT 提取坐标样本（使用 fit_tool 解析）
  static List<List<double>> _extractCoordsFromFit(Uint8List fitBytes, {int maxSamples = 10}) {
    final coords = <List<double>>[];
    try {
      for (var record in FitFile.fromBytes(fitBytes).records) {
        final msg = record.message;
        if (msg is RecordMessage) {
          if (msg.positionLat != null && msg.positionLong != null) {
            coords.add([msg.positionLat!, msg.positionLong!]);
            if (coords.length >= maxSamples) break;
          }
        }
      }
    } catch (_) {}
    return coords;
  }

  /// 使用 fit_tool 纠正 FIT 坐标（与 ref/strava_auto 一致，自动 CRC）
  static Uint8List _correctFit(Uint8List fitBytes, CoordDirection direction) {
    final fitFile = FitFile.fromBytes(fitBytes);
    final isGcj2Wgs = direction == CoordDirection.gcj2wgs;

    for (var record in fitFile.records) {
      final msg = record.message;
      switch (msg) {
        case RecordMessage m:
          _fix(m.positionLat, m.positionLong, (la, lo) { m.positionLat = la; m.positionLong = lo; }, isGcj2Wgs);
        case CoursePointMessage m:
          _fix(m.positionLat, m.positionLong, (la, lo) { m.positionLat = la; m.positionLong = lo; }, isGcj2Wgs);
        case SegmentPointMessage m:
          _fix(m.positionLat, m.positionLong, (la, lo) { m.positionLat = la; m.positionLong = lo; }, isGcj2Wgs);
        case SegmentLapMessage m:
          _fix(m.startPositionLat, m.startPositionLong, (la, lo) { m.startPositionLat = la; m.startPositionLong = lo; }, isGcj2Wgs);
          _fix(m.endPositionLat, m.endPositionLong, (la, lo) { m.endPositionLat = la; m.endPositionLong = lo; }, isGcj2Wgs);
        case LapMessage m:
          _fix(m.startPositionLat, m.startPositionLong, (la, lo) { m.startPositionLat = la; m.startPositionLong = lo; }, isGcj2Wgs);
          _fix(m.endPositionLat, m.endPositionLong, (la, lo) { m.endPositionLat = la; m.endPositionLong = lo; }, isGcj2Wgs);
        case SessionMessage m:
          _fix(m.startPositionLat, m.startPositionLong, (la, lo) { m.startPositionLat = la; m.startPositionLong = lo; }, isGcj2Wgs);
          _fix(m.necLat, m.necLong, (la, lo) { m.necLat = la; m.necLong = lo; }, isGcj2Wgs);
          _fix(m.swcLat, m.swcLong, (la, lo) { m.swcLat = la; m.swcLong = lo; }, isGcj2Wgs);
      }
    }
    fitFile.crc = null;
    return fitFile.toBytes();
  }

  static void _fix(double? lat, double? lng, void Function(double la, double lo) apply, bool isGcj2Wgs) {
    if (lat == null || lng == null) return;
    final c = isGcj2Wgs ? CoordinateConverter.gcj2WGSExact(lat, lng) : CoordinateConverter.wgs2Gcj(lat, lng);
    apply(c[0], c[1]);
  }

  /// 纠正 FIT 文件坐标
  static Future<Uint8List> processFitBytes(Uint8List fitBytes, CoordDirection direction) async {
    final coords = _extractCoordsFromFit(fitBytes);
    lastSampleCount = coords.length;
    if (coords.isEmpty) { lastDetectionResult = null; return fitBytes; }

    final isWgs84 = CoordinateConverter.isLikelyWGS84Enhanced(coords);
    lastDetectionResult = isWgs84;
    if (direction == CoordDirection.gcj2wgs && isWgs84 == true) return fitBytes;
    if (direction == CoordDirection.wgs2gcj && isWgs84 == false) return fitBytes;

    lastDetectionResult = (direction == CoordDirection.gcj2wgs) ? false : true;
    return _correctFit(fitBytes, direction);
  }

  /// 纠正 GPX 文件坐标
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

  /// 纠正 TCX 文件坐标
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
