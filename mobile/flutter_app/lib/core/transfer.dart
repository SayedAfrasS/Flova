/// WORKFLOW OF THIS FILE:
/// 1. Small data class describing one transfer for the UI screens.
/// 2. "verified" carries the hash verdict from the transport layer so the
///    Complete screen can show success or failure.
class TransferInfo {
  final String name;
  final String size;
  final double bytes;
  final bool sending;
  final bool verified;

  const TransferInfo({
    required this.name,
    required this.size,
    required this.bytes,
    this.sending = true,
    this.verified = true,
  });
}