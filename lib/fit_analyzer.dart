import 'dart:typed_data';
import 'package:fit_tool/fit_tool.dart';

/// FIT 文件解析结果
class FitActivityData {
  String sport = 'Ride';
  String subSport = '';
  double totalDistance = 0; // meters
  int totalElapsed = 0; // seconds
  double avgSpeed = 0; // m/s
  double maxSpeed = 0; // m/s
  int avgHeartRate = 0;
  int maxHeartRate = 0;
  int avgCadence = 0;
  int maxCadence = 0;
  double elevGain = 0; // m
  double elevLoss = 0; // m
  int calories = 0;
  double minAltitude = 0;
  double maxAltitude = 0;
  double avgTemperature = 0;
  double maxTemperature = 0;
  bool hasGpsData = false;
  String productName = '';
  DateTime? startTime;
  DateTime? endTime;
}

class FitAnalyzer {
  /// 从 FIT 二进制解析运动数据
  static FitActivityData analyze(Uint8List fitBytes) {
    final data = FitActivityData();
    final speeds = <double>[];
    final heartRates = <int>[];
    final cadences = <int>[];
    final altitudes = <double>[];
    final temperatures = <int>[];
    double? lastAltitude;

    try {
      final fitFile = FitFile.fromBytes(fitBytes);
      for (var record in fitFile.records) {
        final msg = record.message;

        switch (msg) {
          case FileIdMessage m:
            final tc = m.timeCreated;
            if (tc is int) {
              data.startTime ??= DateTime.fromMillisecondsSinceEpoch(
                  tc * 1000, isUtc: true);
            }
            data.productName = m.productName ?? '';

          case SportMessage m:
            final s = m.sport;
            data.sport = _sportName((s as int?) ?? 0);
            data.subSport = m.name ?? '';

          case SessionMessage m:
            if (m.totalAscent != null && (m.totalAscent as num) > 0) {
              data.elevGain = (m.totalAscent as num).toDouble();
            }
            if (m.totalDescent != null && (m.totalDescent as num) > 0) {
              data.elevLoss = (m.totalDescent as num).toDouble();
            }
            if (m.totalCalories != null) {
              data.calories = m.totalCalories as int;
            }
            final st = m.startTime;
            if (st is int) {
              data.startTime ??= DateTime.fromMillisecondsSinceEpoch(
                  st * 1000, isUtc: true);
            }

          case RecordMessage m:
            // Timestamp
            final ts = m.timestamp;
            if (ts is int) {
              final dt = DateTime.fromMillisecondsSinceEpoch(
                  ts * 1000, isUtc: true);
              data.startTime ??= dt;
              data.endTime = dt;
            }

            // Position
            if (m.positionLat != null && m.positionLong != null) {
              data.hasGpsData = true;
            }

            // Distance
            if (m.distance != null) {
              data.totalDistance = (data.totalDistance > m.distance!)
                  ? data.totalDistance
                  : m.distance!.toDouble();
            }

            // Speed
            final speed = m.enhancedSpeed ?? m.speed;
            if (speed != null && speed > 0) {
              speeds.add(speed.toDouble());
              data.maxSpeed =
                  data.maxSpeed > speed ? data.maxSpeed : speed.toDouble();
            }

            // Heart rate
            if (m.heartRate != null && (m.heartRate as int) > 0) {
              final hr = m.heartRate as int;
              heartRates.add(hr);
              if (hr > data.maxHeartRate) data.maxHeartRate = hr;
            }

            // Cadence
            if (m.cadence != null && (m.cadence as int) > 0 && (m.cadence as int) < 255) {
              final cad = m.cadence as int;
              cadences.add(cad);
              if (cad > data.maxCadence) data.maxCadence = cad;
            }

            // Altitude
            final alt = m.enhancedAltitude ?? m.altitude;
            if (alt != null) {
              final a = alt.toDouble();
              altitudes.add(a);
              if (data.minAltitude == 0 || a < data.minAltitude)
                data.minAltitude = a;
              if (a > data.maxAltitude) data.maxAltitude = a;
              final lastAlt = lastAltitude;
              if (lastAlt != null) {
                final diff = a - lastAlt;
                if (diff.abs() >= 1.0) {
                  if (diff > 0) {
                    data.elevGain += diff;
                  } else {
                    data.elevLoss += diff.abs();
                  }
                }
              }
              lastAltitude = a;
            }

            // Calories
            if (m.calories != null && m.calories! > 0) {
              data.calories = (data.calories > m.calories!)
                  ? data.calories
                  : m.calories!;
            }

            // Temperature
            if (m.temperature != null && (m.temperature as int) != 0x7F) {
              final t = m.temperature as int;
              temperatures.add(t);
              if (t > data.maxTemperature) data.maxTemperature = t.toDouble();
            }

          default:
            break;
        }
      }

      // 计算均值
      if (speeds.isNotEmpty) {
        data.avgSpeed = speeds.reduce((a, b) => a + b) / speeds.length;
      }
      if (heartRates.isNotEmpty) {
        data.avgHeartRate =
            heartRates.reduce((a, b) => a + b) ~/ heartRates.length;
      }
      if (cadences.isNotEmpty) {
        data.avgCadence =
            cadences.reduce((a, b) => a + b) ~/ cadences.length;
      }

      // 计算均温（去掉前2和后1个异常值，常见于开关机）
      if (temperatures.length > 3) {
        final clean = temperatures.sublist(2, temperatures.length - 1);
        data.avgTemperature =
            clean.reduce((a, b) => a + b) / clean.length;
      } else if (temperatures.isNotEmpty) {
        data.avgTemperature =
            temperatures.reduce((a, b) => a + b) / temperatures.length;
      }

      // 计算时长
      if (data.startTime != null && data.endTime != null) {
        data.totalElapsed =
            data.endTime!.difference(data.startTime!).inSeconds;
      }
    } catch (_) {
      // 解析失败，返回空数据
    }

    return data;
  }

  /// 生成活动标题（中文版，用于 Strava name 字段）
  static String buildTitle(FitActivityData d) => _buildTitle(d, false);

  /// 生成活动标题（英文版，用于文件名等 ASCII 场景）
  static String buildTitleAscii(FitActivityData d) => _buildTitle(d, true);

  static String _buildTitle(FitActivityData d, bool ascii) {
    final distKm = d.totalDistance / 1000;
    final ift = (d.maxHeartRate > 0) ? d.avgHeartRate / d.maxHeartRate : 0.0;
    final intensity = ascii ? _intensityLabelEn(ift) : _intensityLabel(ift);
    final distTag = d.sport == 'Ride' ? (ascii ? _distanceTagEn(distKm) : _distanceTag(distKm)) : '';

    String rideTime = '';
    if (d.startTime != null) {
      // 国产码表（MAGENE 等）FIT 时间戳存的是北京时间，直接取 hour
      final h = d.startTime!.hour;
      if (h >= 5 && h < 9) rideTime = ascii ? 'Morning' : '晨骑';
      else if (h >= 9 && h < 12) rideTime = ascii ? 'LateMorning' : '午前骑';
      else if (h >= 12 && h < 14) rideTime = ascii ? 'Noon' : '午骑';
      else if (h >= 14 && h < 18) rideTime = ascii ? 'Afternoon' : '午后骑';
      else rideTime = ascii ? 'Night' : '夜骑';
    }

    final parts = <String>['ridesync'];

    switch (d.sport) {
      case 'Ride':
        parts.add(rideTime);
        if (distTag.isNotEmpty) parts.add(distTag);
        if (intensity.isNotEmpty) parts.add(intensity);
        break;
      case 'Run':
        if (distKm < 3) parts.add(ascii ? 'ShortRun' : '晨跑');
        else if (distKm < 10) parts.add(ascii ? 'MidRun' : '中长跑训练');
        else if (distKm < 42) parts.add(ascii ? 'LongRun' : '长跑拉练');
        else parts.add(ascii ? 'Marathon' : '马拉松距离');
        break;
      case 'Walk': parts.add(ascii ? 'Hiking' : '徒步健行'); break;
      case 'Swim': parts.add(ascii ? 'Swim' : '游泳训练'); break;
      default: parts.add(d.subSport.isNotEmpty ? d.subSport : d.sport);
    }

    return parts.join('-');
  }

  static String _distanceTagEn(double distKm) {
    if (distKm > 1000) return 'SuperBRM';
    if (distKm > 600) return 'BRM';
    if (distKm > 300) return 'SuperEndurance';
    if (distKm > 200) return 'UltraDistance';
    if (distKm > 150) return 'LongDistance';
    if (distKm > 100) return 'Century';
    return '';
  }

  static String _intensityLabelEn(double ift) {
    if (ift <= 0) return '';
    if (ift < 0.60) return 'Recovery';
    if (ift < 0.75) return 'Endurance';
    if (ift < 0.85) return 'Tempo';
    if (ift < 0.95) return 'Threshold';
    if (ift < 1.05) return 'FTP';
    if (ift < 1.20) return 'VO2Max';
    return 'Anaerobic';
  }

  /// IF-based 强度标签（基于 avgHR/maxHR）
  static String _intensityLabel(double ift) {
    if (ift <= 0) return '';
    if (ift < 0.60) return '恢复骑';
    if (ift < 0.75) return '基础耐力';
    if (ift < 0.85) return '节奏骑';
    if (ift < 0.95) return '阈值训练';
    if (ift < 1.05) return 'FTP训练';
    if (ift < 1.20) return 'VO2Max训练';
    return '无氧冲刺';
  }

  /// IF-based 强度描述（用于详情）
  static String _intensityDesc(double ift) {
    if (ift <= 0) return '';
    if (ift < 0.60) return 'Z1 恢复/轻松';
    if (ift < 0.75) return 'Z2 有氧基础';
    if (ift < 0.85) return 'Z3 Tempo';
    if (ift < 0.95) return 'Z4 Threshold';
    if (ift < 1.05) return 'Z4/Z5 FTP';
    if (ift < 1.20) return 'Z5 最大摄氧';
    return 'Z6/Z7 无氧';
  }

  /// 距离标签（骑行）
  static String _distanceTag(double distKm) {
    if (distKm > 1000) return '超级BRM';
    if (distKm > 600) return 'BRM';
    if (distKm > 300) return '超级耐力';
    if (distKm > 200) return '超长途';
    if (distKm > 150) return '长途';
    if (distKm > 100) return '百公里';
    return '';
  }

  /// 生成 Strava 活动描述
  static String buildDescription(FitActivityData d) {
    if (!d.hasGpsData && d.totalDistance == 0) return '';

    final buf = StringBuffer();
    final distKm = d.totalDistance / 1000;
    final avgKph = d.avgSpeed * 3.6;
    final maxKph = d.maxSpeed * 3.6;
    final durStr = d.totalElapsed > 0 ? _formatDuration(d.totalElapsed) : '';

    buf.writeln('📊 运动数据摘要');
    buf.writeln('─' * 20);
    if (durStr.isNotEmpty) buf.writeln('⚡ 时长: $durStr');
    buf.writeln('📏 里程: ${distKm.toStringAsFixed(2)} km');
    if (d.avgSpeed > 0) buf.writeln('🚴 平均速度: ${avgKph.toStringAsFixed(1)} km/h');
    if (d.maxSpeed > 0) buf.writeln('🔥 最高速度: ${maxKph.toStringAsFixed(1)} km/h');

    if (d.sport == 'Ride' && d.avgCadence > 0) {
      buf.writeln('🔄 平均踏频: ${d.avgCadence} rpm');
      if (d.maxCadence > 0) buf.writeln('⚡ 最高踏频: ${d.maxCadence} rpm');
    }

    if (d.avgHeartRate > 0) {
      buf.writeln('❤️ 平均心率: ${d.avgHeartRate} bpm');
      buf.writeln('💓 最高心率: ${d.maxHeartRate} bpm');
      final ift = d.maxHeartRate > 0 ? d.avgHeartRate / d.maxHeartRate : 0.0;
      final zone = _intensityDesc(ift);
      if (zone.isNotEmpty) buf.writeln('🏷️ 训练强度: $zone (IF=${ift.toStringAsFixed(2)})');
    }

    if (d.elevGain > 0) buf.writeln('⬆️ 爬升: ${d.elevGain.toStringAsFixed(0)} m');
    if (d.elevLoss > 0) buf.writeln('⬇️ 下降: ${d.elevLoss.toStringAsFixed(0)} m');
    if (d.maxAltitude > d.minAltitude) {
      buf.writeln('⛰️ 海拔: ${d.minAltitude.toStringAsFixed(0)}m ~ ${d.maxAltitude.toStringAsFixed(0)}m');
    }

    if (d.calories > 0) buf.writeln('🔥 热量: ${d.calories} kcal');
    if (d.avgTemperature.abs() > 0) {
      buf.writeln('🌡️ 均温: ${d.avgTemperature.toStringAsFixed(0)}°C');
    }

    buf.writeln('─' * 20);
    buf.writeln('📝 训练评价');
    buf.writeln('─' * 20);

    if (d.sport == 'Ride') {
      final comments = <String>[];
      if (avgKph > 30) {
        comments.add('速度表现优秀🔥');
      } else if (avgKph > 20) {
        comments.add('巡航节奏稳定');
      }
      if (d.elevGain > 200) comments.add('爬坡训练扎实');
      if (d.totalElapsed > 7200) comments.add('长距离耐力训练');
      if (d.calories > 500) comments.add('消耗热量${d.calories}kcal，燃脂效果好');
      buf.writeln(comments.isNotEmpty ? comments.join('\n') : '完成一次训练，继续保持💪');
    } else if (d.sport == 'Run') {
      if (distKm > 10) {
        buf.writeln('长跑训练完成，距离感人的意志力👍');
      } else if (distKm > 5) {
        buf.writeln('有氧耐力训练，维持好状态');
      }
      if (d.avgHeartRate > 0 && d.avgHeartRate < 130) {
        buf.writeln('心率稳定，训练强度适中');
      }
    } else {
      buf.writeln('训练完成💪');
    }

    if (d.productName.isNotEmpty) {
      buf.writeln('📱 码表: ${d.productName}');
    }

    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    buf.writeln('🤖 自动生成 | ${now.year}-${_pad(now.month)}-${_pad(now.day)} ${_pad(now.hour)}:${_pad(now.minute)}');

    return buf.toString();
  }

  static String _sportName(int sport) {
    switch (sport) {
      case 1: return 'Run';
      case 2: return 'Ride';
      case 5: return 'Swim';
      case 9: return 'Walk';
      case 10: return 'Hike';
      default: return 'Ride';
    }
  }

  static String _formatDuration(int totalSec) {
    final h = totalSec ~/ 3600;
    final m = (totalSec % 3600) ~/ 60;
    final s = totalSec % 60;
    if (h > 0) return '${h}小时${m}分';
    return '${m}分${s}秒';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}
