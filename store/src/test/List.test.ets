import localUnitTest from './LocalUnit.test';
import formatUtilsTest from './FormatUtils.test';

/**
 * 测试套件入口
 * 注册所有测试用例
 */
export default function testsuite() {
  localUnitTest();
  formatUtilsTest();
}
