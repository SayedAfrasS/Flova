class TransferInfo {
  final String name;
  final String size;
  final double bytes;
  final bool sending;

  const TransferInfo({
    required this.name,
    required this.size,
    required this.bytes,
    this.sending = true,
  });
}