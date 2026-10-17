import 'package:flutter_test/flutter_test.dart';
import 'package:mmlu_client/core/network/api_exception.dart';

void main() {
  group('extractApiMessage（服务端错误文案提取）', () {
    test('直接字符串', () {
      expect(extractApiMessage('密码错误'), '密码错误');
    });

    test('顶层 message', () {
      expect(extractApiMessage({'message': '账号被禁用'}), '账号被禁用');
    });

    test('嵌套 error.msg', () {
      expect(
        extractApiMessage({
          'error': {'msg': 'unidentify'}
        }),
        'unidentify',
      );
    });

    test('errors 为字段 -> 数组', () {
      expect(
        extractApiMessage({
          'errors': {
            'phone': ['手机号格式不正确']
          }
        }),
        '手机号格式不正确',
      );
    });

    test('优先常见键而非首个值', () {
      expect(
        extractApiMessage({'code': 500, 'message': '服务繁忙'}),
        '服务繁忙',
      );
    });

    test('无可读文案时回退', () {
      expect(extractApiMessage({'code': 500}, fallback: '登录失败'), '登录失败');
      expect(extractApiMessage(null, fallback: '登录失败'), '登录失败');
      expect(extractApiMessage('   ', fallback: '登录失败'), '登录失败');
    });
  });
}
