enum BingxFuturesOrderSizingStatus {
  sized,
  blocked,
  unavailable,
}

class BingxFuturesOrderSizingResult {
  final BingxFuturesOrderSizingStatus status;
  final String reasonCode;
  final String reasonMessage;
  final String? quantityDecimal;
  final String? orderNotionalQuoteDecimal;
  final String? minimumQuantityDecimal;
  final String? minimumNotionalQuoteDecimal;

  const BingxFuturesOrderSizingResult({
    required this.status,
    required this.reasonCode,
    required this.reasonMessage,
    required this.quantityDecimal,
    required this.orderNotionalQuoteDecimal,
    required this.minimumQuantityDecimal,
    required this.minimumNotionalQuoteDecimal,
  });
}
