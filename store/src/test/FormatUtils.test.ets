import { describe, it, expect } from '@ohos/hypium';
import { FormatUtils } from '../main/ets/common/utils/FormatUtils';

/**
 * FormatUtils 本地单元测试
 * 纯函数、无设备依赖，适合做回归基线
 */
export default function formatUtilsTest() {
  describe('FormatUtils', () => {
    it('formatBytes_zero', 0, () => {
      expect(FormatUtils.formatBytes(0)).assertEqual('0 B');
    });

    it('formatBytes_nan', 0, () => {
      expect(FormatUtils.formatBytes(Number.NaN)).assertEqual('0 B');
    });

    it('formatBytes_kb', 0, () => {
      // 2048 B → 2.0 KB（非 B 级别保留 1 位小数）
      expect(FormatUtils.formatBytes(2048)).assertEqual('2.0 KB');
    });

    it('formatBytes_mb', 0, () => {
      expect(FormatUtils.formatBytes(1572864)).assertEqual('1.5 MB');
    });

    it('formatBytes_gb', 0, () => {
      expect(FormatUtils.formatBytes(1610612736)).assertEqual('1.5 GB');
    });

    it('formatSpeed', 0, () => {
      expect(FormatUtils.formatSpeed(1048576)).assertEqual('1.0 MB/s');
    });

    it('formatUptime_seconds', 0, () => {
      expect(FormatUtils.formatUptime(45)).assertEqual('45秒');
    });

    it('formatUptime_minutes', 0, () => {
      expect(FormatUtils.formatUptime(90)).assertEqual('1分 30秒');
    });

    it('formatUptime_hours', 0, () => {
      expect(FormatUtils.formatUptime(3600)).assertEqual('1时 0分');
    });

    it('formatUptime_days', 0, () => {
      expect(FormatUtils.formatUptime(90061)).assertEqual('1天 1时 1分 1秒');
    });

    it('formatPercent_clamp', 0, () => {
      expect(FormatUtils.formatPercent(120)).assertEqual('100.0%');
      expect(FormatUtils.formatPercent(-5)).assertEqual('0.0%');
      expect(FormatUtils.formatPercent(85.55)).assertEqual('85.6%');
    });

    it('formatTemperature', 0, () => {
      expect(FormatUtils.formatTemperature(45.24)).assertEqual('45.2°C');
    });
  });
}
