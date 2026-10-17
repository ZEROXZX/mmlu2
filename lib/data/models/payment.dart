/// 支付相关 (PaymentBean / PaymentsResponse / BuyPaymentResponse / PaymentHistoryResponse)。
class PaymentBean {
  PaymentBean({this.id, this.title, this.subTitle, this.currency});

  final int? id;
  final String? title;
  final String? subTitle;
  final String? currency;

  factory PaymentBean.fromJson(Map<String, dynamic> j) => PaymentBean(
        id: j['id'] as int?,
        title: j['title'] as String?,
        subTitle: j['sub_title'] as String?,
        currency: j['currency'] as String?,
      );
}

class PaymentsResponse {
  PaymentsResponse({this.payments});

  final List<PaymentBean>? payments;

  factory PaymentsResponse.fromJson(Map<String, dynamic> j) => PaymentsResponse(
        payments: (j['payments'] as List<dynamic>?)
            ?.map((e) => PaymentBean.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class BuyPaymentResponse {
  BuyPaymentResponse({this.data, this.type});

  final Object? data;
  final String? type;

  factory BuyPaymentResponse.fromJson(Map<String, dynamic> j) =>
      BuyPaymentResponse(data: j['data'], type: j['type'] as String?);
}
